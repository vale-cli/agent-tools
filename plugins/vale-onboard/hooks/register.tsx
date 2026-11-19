import { atom, read, update } from 'claude-code'
import type { Elements, EngineInterface, Register } from 'claude-code'

import type {
  CheckPreview,
  Checks,
  Choice,
  Counts,
  Extras,
  FailOn,
  Level,
  PackageCount,
  Proposal,
  Rule,
  Scope,
  Term,
} from '../types'

const PANE = 'vale-onboard'
const TITLE = 'Vale setup'
const CHECKS_PANE = 'vale-checks'
const CHECKS_TITLE = 'Vale checks'
const CANDIDATES = ['Microsoft', 'Google']
const FRONT_MATTER = 'text.frontmatter.id,text.frontmatter.slug'
const MAX_RULES = 12
const MAX_TERMS = 16

const NO_CHECKS: Checks = {
  githubAction: false,
  preCommit: false,
  scope: 'new-lines',
  report: 'suggestion',
  failOn: 'never',
  reviewComments: false,
}

const NO_PREVIEW: CheckPreview = { workflow: '', workflowNotes: [], hook: '', hookNotes: [] }

const NO_EXTRAS: Extras = {
  codeComments: false,
  commitMessages: false,
  writtenGuide: false,
}

const EMPTY: Proposal = {
  status: 'idle',
  note: 'Preview a Vale baseline for this repository. Nothing is written until you apply.',
  path: '',
  files: '',
  pkg: '',
  packages: [],
  first: null,
  now: null,
  rules: [],
  terms: [],
  skipsFrontMatter: true,
  view: 'onboard',
  checks: NO_CHECKS,
  preview: NO_PREVIEW,
  isOnGitHub: false,
  usesPreCommit: false,
  extras: NO_EXTRAS,
}

// Change the tag when Proposal's fields change: it declines what an earlier
// version stored, which outlives a reload.
const proposal = atom({ plugin: 'vale-onboard', key: 'proposal' } as const, EMPTY, {
  shape: 'proposal-3',
})

type Parsed = {
  files: string
  counts: Counts | null
  packages: PackageCount[]
  rules: Rule[]
  terms: Term[]
}

const toCounts = (cells: string[]): Counts => ({
  total: Number(cells[0]) || 0,
  errors: Number(cells[1]) || 0,
  warnings: Number(cells[2]) || 0,
  suggestions: Number(cells[3]) || 0,
})

const isLevel = (text: string): text is Level =>
  text === 'error' || text === 'warning' || text === 'suggestion'

/** Reads the tab-separated records `preview.sh -t` prints. */
export const parse = (text: string): Parsed => {
  const parsed: Parsed = { files: '', counts: null, packages: [], rules: [], terms: [] }

  for (const line of text.split('\n')) {
    const [kind, ...cells] = line.replace(/\r$/, '').split('\t')

    if (kind === 'meta' && cells[0] === 'files') {
      parsed.files = cells[1] ?? ''
    } else if (kind === 'counts') {
      parsed.counts = toCounts(cells)
    } else if (kind === 'package' && cells[0]) {
      parsed.packages.push({ name: cells[0], counts: toCounts(cells.slice(1)) })
    } else if (kind === 'rule' && cells[0] && isLevel(cells[1] ?? '')) {
      parsed.rules.push({
        name: cells[0],
        level: cells[1] as Level,
        count: Number(cells[2]) || 0,
        example: cells.slice(3).join(' '),
        choice: 'keep',
      })
    } else if (kind === 'term' && cells[0]) {
      parsed.terms.push({
        word: cells[0],
        count: Number(cells[1]) || 0,
        where: cells[2] ?? '',
        isAccepted: false,
      })
    }
  }

  return parsed
}

const RANK: Record<Level, number> = { error: 0, warning: 1, suggestion: 2 }

/** Error-level rules first, since each of those needs a decision; then the busiest. */
const byNeed = (a: Rule, b: Rule): number =>
  RANK[a.level] - RANK[b.level] || b.count - a.count

/** The first lines of a file are front matter: an id there is a URL, not a word. */
const isInFrontMatter = (where: string): boolean => {
  const line = Number(where.slice(where.lastIndexOf(':') + 1))

  return line > 0 && line <= 3
}

/**
 * A capitalised word in the body is most likely a name; a lowercase one is as
 * likely a typo or an inconsistent casing, which is a finding, not vocabulary.
 */
const looksLikeName = (term: Term): boolean =>
  /^[A-Z]/.test(term.word) && !isInFrontMatter(term.where)

/** What a press on a rule's button moves it to. Only ever quieter than shipped. */
export const nextChoice = (rule: Rule): Choice => {
  const steps: Choice[] =
    rule.level === 'error'
      ? ['keep', 'warning', 'suggestion', 'off']
      : rule.level === 'warning'
        ? ['keep', 'suggestion', 'off']
        : ['keep', 'off']

  return steps[(steps.indexOf(rule.choice) + 1) % steps.length] ?? 'keep'
}

const overrideOf = (rule: Rule): string =>
  `${rule.name}=${rule.choice === 'off' ? 'NO' : rule.choice}`

/** The arguments that make `preview.sh` lint with everything chosen so far. */
export const previewArgs = (p: Proposal): string[] => {
  const accepted = p.terms.filter(term => term.isAccepted).map(term => term.word)
  const changed = p.rules.filter(rule => rule.choice !== 'keep').map(overrideOf)

  return [
    '-t',
    '-p',
    p.pkg,
    ...(accepted.length > 0 ? ['-A', accepted.join(',')] : []),
    ...(changed.length > 0 ? ['-O', changed.join(';')] : []),
    ...(p.skipsFrontMatter ? ['-i', FRONT_MATTER] : []),
    p.path,
  ]
}

const EXTRA_LABELS: Record<keyof Extras, string> = {
  codeComments: 'Code comments',
  commitMessages: 'Commit messages',
  writtenGuide: 'A written guide',
}

const describe = (rule: Rule): string =>
  rule.choice === 'off'
    ? `${rule.name} = NO (${rule.count} hits; switched off in the setup pane)`
    : `${rule.name} = ${rule.choice} (${rule.count} hits; was ${rule.level})`

const SCOPES: Scope[] = ['new-lines', 'changed-files', 'everything']
const REPORTS: Level[] = ['suggestion', 'warning', 'error']
const FAILS: FailOn[] = ['never', 'error', 'warning']

const SCOPE_LABELS: Record<Scope, string> = {
  'new-lines': 'New lines only',
  'changed-files': 'Changed files, whole',
  everything: 'Everything, every time',
}

const REPORT_LABELS: Record<Level, string> = {
  suggestion: 'Every alert',
  warning: 'Warnings and errors',
  error: 'Errors only',
}

const FAIL_LABELS: Record<FailOn, string> = {
  never: 'Never (advisory)',
  error: 'On errors',
  warning: 'On warnings too',
}

/** The value after this one, round to the first again. */
export const after = <T,>(all: readonly T[], now: T): T =>
  all[(all.indexOf(now) + 1) % all.length] ?? now

/** The arguments that make `ci.sh` print the workflow these choices describe. */
export const actionArgs = (p: Proposal): string[] => [
  'action',
  ...(p.checks.scope !== 'new-lines' ? ['-s', p.checks.scope] : []),
  ...(p.checks.report !== 'suggestion' ? ['-l', p.checks.report] : []),
  ...(p.checks.failOn !== 'never' ? ['-x', p.checks.failOn] : []),
  ...(p.checks.reviewComments ? ['-r'] : []),
  ...(p.path !== '' && p.path !== '.' ? ['-f', p.path] : []),
]

/** The arguments that make `ci.sh` print the pre-commit entry. */
export const hookArgs = (p: Proposal): string[] => [
  'pre-commit',
  ...(p.path !== '' && p.path !== '.' ? ['-f', p.path] : []),
]

/** Where Vale will run by itself, as the instruction to Claude names it. */
const runsIn = (p: Proposal): string[] => {
  const lines = [
    ...(p.checks.githubAction
      ? [
          `  a GitHub Actions workflow: ${SCOPE_LABELS[p.checks.scope].toLowerCase()}; reports ${REPORT_LABELS[p.checks.report].toLowerCase()}; fails ${FAIL_LABELS[p.checks.failOn].toLowerCase()}${p.checks.reviewComments ? '; as review comments' : ''}.`,
          `    Generate it with the ci skill: ci.sh ${actionArgs(p).join(' ')}`,
          '    Update a workflow that already runs Vale rather than adding a second.',
        ]
      : []),
    ...(p.checks.preCommit
      ? [
          '  a pre-commit hook, on the files being committed, stopping on errors.',
          `    Generate it with the ci skill: ci.sh ${hookArgs(p).join(' ')}`,
        ]
      : []),
  ]

  return lines.length > 0 ? lines : ['  nowhere automatic; do not add a workflow or a hook']
}

/** The instruction placed in the prompt: what was chosen, for Claude to apply. */
export const applyText = (p: Proposal): string => {
  const accepted = p.terms.filter(term => term.isAccepted).map(term => term.word)
  const left = p.terms.filter(term => !term.isAccepted).map(term => term.word)
  const changed = p.rules.filter(rule => rule.choice !== 'keep')
  const extras = (Object.keys(EXTRA_LABELS) as (keyof Extras)[])
    .filter(key => p.extras[key])
    .map(key => EXTRA_LABELS[key])
  const counts = (c: Counts | null): string =>
    c === null
      ? 'unknown'
      : `${c.total} alerts (${c.errors} errors, ${c.warnings} warnings, ${c.suggestions} suggestions)`

  return [
    'Apply this Vale baseline. I chose it in the Vale setup pane, so treat it as the',
    'approved proposal and follow the vale:onboard skill from its apply step: write the',
    'config, verify the counts against the preview, and finish as that skill says.',
    '',
    `Path: ${p.path}`,
    `Package: ${p.pkg}`,
    `First run: ${counts(p.first)}`,
    `Expected after applying: ${counts(p.now)}`,
    `Vocabulary, accept: ${accepted.length > 0 ? accepted.join(', ') : 'nothing'}`,
    `Unknown words I left unticked (findings, not vocabulary): ${left.length > 0 ? left.join(', ') : 'none'}`,
    `Front matter id and slug: ${p.skipsFrontMatter ? 'leave unlinted' : 'lint them'}`,
    'Overrides, each with its reason as a comment:',
    ...(changed.length > 0 ? changed.map(rule => `  ${describe(rule)}`) : ['  none']),
    'Where it runs:',
    ...runsIn(p),
    `Also set up: ${extras.length > 0 ? extras.join(', ') : 'nothing else'}`,
  ].join('\n')
}

/** The instruction for a repository that already has Vale: only where it runs. */
export const applyChecksText = (p: Proposal): string =>
  [
    'Set up where Vale runs in this repository, with the vale:ci skill. I chose these',
    'in the Vale checks pane, so treat them as decided: generate each file with the',
    "command given, say what changes in any file that already exists, and save it.",
    '',
    'Where it runs:',
    ...runsIn(p),
  ].join('\n')

const script = ($: EngineInterface, name: string): string =>
  `${$.plugin.root}/scripts/${name}`

const fail = ($: EngineInterface, note: string) =>
  update($, proposal, p => ({ ...p, status: 'failed' as const, note }))

/** Runs preview.sh and reads its records, or says in one line why it could not. */
const preview = async ($: EngineInterface, args: string[]): Promise<Parsed | string> => {
  try {
    const ran = await $.process.run(['sh', script($, 'preview.sh'), ...args], {
      timeoutMs: 180_000,
    })

    if (ran.exitCode !== 0) {
      const why = ran.stderr.trim().split('\n').filter(Boolean)

      return why.slice(0, 3).join(' ') || `preview.sh exited ${ran.exitCode}`
    }

    return parse(ran.stdout)
  } catch {
    return 'Could not run the preview script. It needs a POSIX shell (Git Bash on Windows).'
  }
}

/** Finds where the prose is when the person did not say. */
type Surveyed = {
  path: string
  isOnGitHub: boolean
  usesPreCommit: boolean
  /** The root's own config, if it has one. */
  config: string
}

/** Reads the repository: where the prose is, and what it already has. */
const survey = async ($: EngineInterface): Promise<Surveyed | string> => {
  try {
    const ran = await $.process.run(['sh', script($, 'survey.sh')], { timeoutMs: 60_000 })
    const lines = ran.stdout.split('\n')

    if (lines.some(line => /^Vale:\s+not installed/.test(line))) {
      return 'Vale is not installed. Ask Claude to set it up (/vale:setup), then try again.'
    }

    // Only a config at the root is this repository's own; one deeper down
    // belongs to an example or a fixture.
    const config =
      (lines.find(line => line.startsWith('Config:')) ?? '')
        .replace(/^Config:\s+/, '')
        .split(/\s+/)
        .find(one => one === '.vale.ini' || one === '_vale.ini') ?? ''
    const at = lines.findIndex(line => line.startsWith('Prose:'))
    const first = at >= 0 ? (lines[at + 1] ?? '') : ''
    const dir = first.startsWith('  ') ? (first.trim().split(/\s{2,}/)[0] ?? '') : ''

    return {
      path: dir === '(root)' ? '.' : dir,
      isOnGitHub: lines.some(line => /^GitHub:\s+yes/.test(line)),
      usesPreCommit: lines.some(line => /^Hook runner:.*\.pre-commit-config\.yaml/.test(line)),
      config,
    }
  } catch {
    return 'Could not read the repository. The pane needs a POSIX shell (Git Bash on Windows).'
  }
}

/** One of the generator's files, with what it said about it, or nothing on a failure. */
const generate = async ($: EngineInterface, args: string[]): Promise<{ text: string; notes: string[] }> => {
  try {
    const ran = await $.process.run(['sh', script($, 'ci.sh'), ...args], { timeoutMs: 30_000 })
    const notes = ran.stderr
      .split('\n')
      .map(line => line.replace(/^ci\.sh:\s*/, '').trim())
      .filter(line => line !== '' && !line.startsWith('save as'))

    return { text: ran.exitCode === 0 ? ran.stdout.trimEnd() : '', notes }
  } catch {
    return { text: '', notes: ['Could not run the generator.'] }
  }
}

/** Regenerates the files the current choices describe, for the pane to show. */
const refresh = async ($: EngineInterface) => {
  const p = await read($, proposal)
  const workflow = p.checks.githubAction ? await generate($, actionArgs(p)) : { text: '', notes: [] }
  const hook = p.checks.preCommit ? await generate($, hookArgs(p)) : { text: '', notes: [] }

  await update($, proposal, now => ({
    ...now,
    preview: {
      workflow: workflow.text,
      workflowNotes: workflow.notes,
      hook: hook.text,
      hookNotes: hook.notes,
    },
  }))
}

/** Changes one choice about where Vale runs, and shows what that produces. */
const choose = async ($: EngineInterface, change: Partial<Checks>) => {
  await update($, proposal, now => ({ ...now, checks: { ...now.checks, ...change } }))
  await refresh($)
}

/** Lints with everything chosen so far and puts the result beside the first run. */
const recount = async ($: EngineInterface) => {
  const p = await read($, proposal)

  if (p.pkg === '' || p.path === '') {
    return
  }

  await update($, proposal, now => ({ ...now, status: 'working' as const, note: 'Counting…' }))
  const got = await preview($, previewArgs(p))

  if (typeof got === 'string') {
    await fail($, got)

    return
  }

  await update($, proposal, now => ({
    ...now,
    status: 'ready' as const,
    note: 'Nothing is written until you apply.',
    now: got.counts,
  }))

  // One line in the status bar, so the count stays in view with the pane shut.
  if (got.counts !== null) {
    $.ui.status(`Vale preview: ${got.counts.errors} errors · ${got.counts.total} alerts`)
  }
}

/** Loads one package's rules and unknown words, with the quiet defaults ticked. */
const load = async ($: EngineInterface, pkg: string) => {
  const p = await read($, proposal)

  await update($, proposal, now => ({
    ...now,
    status: 'working' as const,
    note: `Reading what ${pkg} reports…`,
    pkg,
  }))
  const got = await preview($, ['-t', '-p', pkg, p.path])

  if (typeof got === 'string') {
    await fail($, got)

    return
  }

  await update($, proposal, now => ({
    ...now,
    files: got.files,
    first: got.counts,
    rules: [...got.rules].sort(byNeed).slice(0, MAX_RULES),
    terms: [...got.terms]
      .sort((a, b) => b.count - a.count)
      .slice(0, MAX_TERMS)
      .map(term => ({ ...term, isAccepted: looksLikeName(term) })),
  }))
  await recount($)
}

const start = async ($: EngineInterface, asked: string) => {
  await update($, proposal, () => ({
    ...EMPTY,
    status: 'working' as const,
    note: 'Reading the repository…',
  }))

  const found = await survey($)

  if (typeof found === 'string') {
    await fail($, found)

    return
  }

  if (found.config !== '') {
    await fail(
      $,
      `This repository already has a Vale config (${found.config}). This pane is for first-time setup; /vale-checks sets up where it runs, and Claude can change the rest (/vale:tune).`,
    )

    return
  }

  const path = asked === '' ? found.path : asked

  if (path === '') {
    await fail($, 'No prose files found here. Run /vale-onboard <path> with the directory your docs are in.')

    return
  }

  await update($, proposal, p => ({
    ...p,
    path,
    isOnGitHub: found.isOnGitHub,
    usesPreCommit: found.usesPreCommit,
    // Each check starts on only where the repository already works that way.
    checks: { ...NO_CHECKS, githubAction: found.isOnGitHub, preCommit: found.usesPreCommit },
    note: `Trying ${CANDIDATES.join(' and ')} against ${path}…`,
  }))
  await refresh($)
  const compared = await preview($, ['-t', ...CANDIDATES.flatMap(name => ['-p', name]), path])

  if (typeof compared === 'string') {
    await fail($, compared)

    return
  }

  const quietest = [...compared.packages].sort((a, b) => a.counts.total - b.counts.total)[0]

  if (quietest === undefined) {
    await fail($, 'The preview returned no packages.')

    return
  }

  await update($, proposal, p => ({ ...p, files: compared.files, packages: compared.packages }))
  await load($, quietest.name)
}

/** For a repository that already has Vale: only the choices about where it runs. */
const startChecks = async ($: EngineInterface, asked: string) => {
  await update($, proposal, () => ({
    ...EMPTY,
    view: 'checks' as const,
    status: 'working' as const,
    note: 'Reading the repository…',
  }))

  const found = await survey($)

  if (typeof found === 'string') {
    await fail($, found)

    return
  }

  if (found.config === '') {
    await fail($, 'This repository has no Vale config yet. Run /vale-onboard first; it covers where Vale runs too.')

    return
  }

  await update($, proposal, p => ({
    ...p,
    path: asked === '' ? found.path : asked,
    isOnGitHub: found.isOnGitHub,
    usesPreCommit: found.usesPreCommit,
    checks: { ...NO_CHECKS, githubAction: found.isOnGitHub, preCommit: found.usesPreCommit },
  }))
  await refresh($)
  await update($, proposal, p => ({
    ...p,
    status: 'ready' as const,
    note: 'Nothing is written until you apply.',
  }))
}

type Table = Pick<Elements['terminal'], 'Box' | 'Button' | 'Code' | 'Text'>

/** The choices about where Vale runs, and the files they produce. Both panes draw it. */
const checksSection = ($: EngineInterface, { Box, Button, Code, Text }: Table, p: Proposal) => (
  <Box marginTop={1} flexDirection="column">
    <Text bold>Where it runs</Text>
    <Text dimColor>
      {p.isOnGitHub ? 'A GitHub repository' : 'Not a GitHub repository, as far as I can tell'}
      {p.usesPreCommit ? ', and it already uses pre-commit.' : '; pre-commit is not in use here.'}
    </Text>
    <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
      <Button
        key="check-githubAction"
        label={`${p.checks.githubAction ? '✓' : '·'} GitHub Action`}
        variant={p.checks.githubAction ? 'primary' : 'secondary'}
        onPress={() => choose($, { githubAction: !p.checks.githubAction })}
      />
      <Button
        key="check-preCommit"
        label={`${p.checks.preCommit ? '✓' : '·'} pre-commit hook`}
        variant={p.checks.preCommit ? 'primary' : 'secondary'}
        onPress={() => choose($, { preCommit: !p.checks.preCommit })}
      />
    </Box>

    {p.checks.githubAction && (
      <Box marginTop={1} flexDirection="column">
        <Text dimColor>On a pull request — press to change</Text>
        <Box flexDirection="row" columnGap={1}>
          <Text>{'Looks at  '}</Text>
          <Button
            key="check-scope"
            label={SCOPE_LABELS[p.checks.scope]}
            onPress={() => choose($, { scope: after(SCOPES, p.checks.scope) })}
          />
        </Box>
        <Box flexDirection="row" columnGap={1}>
          <Text>{'Reports   '}</Text>
          <Button
            key="check-report"
            label={REPORT_LABELS[p.checks.report]}
            onPress={() => choose($, { report: after(REPORTS, p.checks.report) })}
          />
        </Box>
        <Box flexDirection="row" columnGap={1}>
          <Text>{'Fails     '}</Text>
          <Button
            key="check-failOn"
            label={FAIL_LABELS[p.checks.failOn]}
            variant={p.checks.failOn === 'never' ? 'secondary' : 'primary'}
            onPress={() => choose($, { failOn: after(FAILS, p.checks.failOn) })}
          />
        </Box>
        <Box flexDirection="row" columnGap={1}>
          <Text>{'Shows as  '}</Text>
          <Button
            key="check-reviewComments"
            label={p.checks.reviewComments ? 'Review comments, with fixes' : 'Annotations'}
            onPress={() => choose($, { reviewComments: !p.checks.reviewComments })}
          />
        </Box>
        {p.preview.workflowNotes.map(note => (
          <Text dimColor>{note}</Text>
        ))}
        {p.checks.failOn !== 'never' && p.now !== null && p.now.errors > 0 && p.checks.scope === 'everything' && (
          <Text>{`${p.now.errors} errors are left, so this would fail on its first run.`}</Text>
        )}
        {p.preview.workflow !== '' && (
          <Box marginTop={1} flexDirection="column">
            <Text dimColor>.github/workflows/vale.yml</Text>
            <Code source={p.preview.workflow} language="yaml" />
          </Box>
        )}
      </Box>
    )}

    {p.checks.preCommit && (
      <Box marginTop={1} flexDirection="column">
        {p.preview.hookNotes.map(note => (
          <Text dimColor>{note}</Text>
        ))}
        {p.preview.hook !== '' && (
          <Box marginTop={1} flexDirection="column">
            <Text dimColor>.pre-commit-config.yaml</Text>
            <Code source={p.preview.hook} language="yaml" />
          </Box>
        )}
      </Box>
    )}

    {!p.checks.githubAction && !p.checks.preCommit && (
      <Text dimColor>Nothing will run Vale automatically.</Text>
    )}
  </Box>
)

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'vale-onboard',
      description: 'Preview and choose a Vale baseline for this repository in a pane',
    })

    await $.command.register({
      name: 'vale-checks',
      description: 'Choose where Vale runs here (GitHub Action, pre-commit) and what it reports',
    })

    return next(e)
  })

  on('command.run', { command: 'vale-checks' }, async ($, e) => {
    await $.ui.open({ id: CHECKS_PANE, title: CHECKS_TITLE })
    void startChecks($, e.args.trim())

    return { text: 'Vale checks pane opened. Nothing is written until you apply.' }
  })

  on('ui.render', { component: 'Pane', requestId: CHECKS_PANE }, async ($, e) => {
    const table = $.ui.resolve(e)
    const { Box, Button, Progress, Text } = table
    const p = await read($, proposal)

    if (p.status !== 'ready' || p.path === '') {
      return (
        <Box flexDirection="column">
          <Text bold>{CHECKS_TITLE}</Text>
          {p.status === 'working' ? (
            <Progress label={p.note} />
          ) : (
            <Text dimColor={p.status !== 'failed'}>
              {p.status === 'failed' ? p.note : 'Choose where Vale runs in this repository, and what it reports.'}
            </Text>
          )}
          {p.status !== 'working' && (
            <Box marginTop={1}>
              <Button key="start-checks" label="Look at this repository" variant="primary" onPress={() => startChecks($, '')} />
            </Box>
          )}
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        <Text bold>Where Vale runs, for {p.path}</Text>
        <Text dimColor>Nothing is written until you apply.</Text>
        {checksSection($, table, p)}
        <Box marginTop={1}>
          <Button
            key="apply-checks"
            variant="primary"
            onPress={async () => {
              const ready = await read($, proposal)
              const filled = await $.prompt.fill({ text: applyChecksText(ready) })

              $.ui.toast(
                filled.isFilled
                  ? 'Your choices are in the prompt. Press Enter and Claude sets them up.'
                  : 'Could not reach the prompt. Close any open dialog and press Apply again.',
              )
            }}
          >
            Apply <Text dimColor>puts it in the prompt</Text>
          </Button>
        </Box>
      </Box>
    )
  })

  on('command.run', { command: 'vale-onboard' }, async ($, e) => {
    await $.ui.open({ id: PANE, title: TITLE })
    void start($, e.args.trim())

    return { text: 'Vale setup pane opened. It is previewing a baseline; nothing is written until you apply.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const table = $.ui.resolve(e)
    const { Box, Button, Progress, Text } = table
    const p = await read($, proposal)
    const isBusy = p.status === 'working'
    const width = Math.max(20, e.props.bodyColumns ?? 60)
    const cell = (value: number | string): string => String(value).padStart(8)
    const row = (label: string, c: Counts): string =>
      `${label.padEnd(13)}${cell(c.total)}${cell(c.errors)}${cell(c.warnings)}${cell(c.suggestions)}`

    if (p.status === 'idle' || p.status === 'failed' || p.first === null || p.view === 'checks') {
      return (
        <Box flexDirection="column">
          <Text bold>{TITLE}</Text>
          {p.status === 'working' ? (
            <Progress label={p.note} />
          ) : (
            <Text dimColor={p.status !== 'failed'}>{p.note}</Text>
          )}
          {p.status !== 'working' && (
            <Box marginTop={1}>
              <Button
                key="start"
                label={p.status === 'failed' ? 'Try again' : 'Preview this repository'}
                variant="primary"
                onPress={() => start($, p.path)}
              />
            </Box>
          )}
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        <Text bold>
          Vale baseline for {p.path} ({p.files})
        </Text>
        {isBusy ? <Progress label={p.note} /> : <Text dimColor>{p.note}</Text>}

        <Box marginTop={1} flexDirection="row" flexWrap="wrap" columnGap={1}>
          <Text>Package</Text>
          {p.packages.map(one => (
            <Button
              key={`pkg-${one.name}`}
              label={`${one.name} ${one.counts.total}`}
              variant={one.name === p.pkg ? 'primary' : 'secondary'}
              onPress={() => (one.name === p.pkg || isBusy ? undefined : load($, one.name))}
            />
          ))}
        </Box>

        <Box marginTop={1} flexDirection="column">
          <Text dimColor mono>
            {`${''.padEnd(13)}${cell('total')}${cell('errors')}${cell('warn')}${cell('suggest')}`}
          </Text>
          <Text mono>{row('First run', p.first)}</Text>
          {p.now !== null && (
            <Text mono bold>
              {row('With choices', p.now)}
            </Text>
          )}
          {p.now !== null && p.first.total > 0 && (
            <Progress
              label="Alerts left"
              value={p.now.total}
              max={p.first.total}
              valueText={`${p.now.total} of ${p.first.total}`}
            />
          )}
          {p.now !== null && (
            <Text dimColor>
              {p.now.errors === 0
                ? 'No errors left: a blocking check would pass.'
                : `${p.now.errors} errors left: keep CI advisory, or decide those rules below.`}
            </Text>
          )}
        </Box>

        <Box marginTop={1} flexDirection="column">
          <Text bold>Rules</Text>
          <Text dimColor>Press one to make it quieter. Errors block a merge.</Text>
          {p.rules.map(rule => (
            <Box key={`rule-${rule.name}`} flexDirection="column">
              <Box flexDirection="row" columnGap={1}>
                <Button
                  key={`choice-${rule.name}`}
                  label={rule.choice === 'keep' ? rule.level : rule.choice}
                  variant={rule.choice === 'keep' && rule.level === 'error' ? 'primary' : 'secondary'}
                  onPress={async () => {
                    await update($, proposal, now => ({
                      ...now,
                      rules: now.rules.map(one =>
                        one.name === rule.name ? { ...one, choice: nextChoice(one) } : one,
                      ),
                    }))
                    await recount($)
                  }}
                />
                <Text strikethrough={rule.choice === 'off'}>
                  {String(rule.count).padStart(4)} {rule.name}
                </Text>
              </Box>
              {rule.level === 'error' && rule.example !== '' && (
                <Text dimColor wrap="truncate-end">
                  {'      '}
                  {rule.example.slice(0, Math.max(10, width - 8))}
                </Text>
              )}
            </Box>
          ))}
        </Box>

        {p.terms.length > 0 && (
          <Box marginTop={1} flexDirection="column">
            <Text bold>Words spell check does not know</Text>
            <Text dimColor>Tick the ones that are right. Leave typos unticked.</Text>
            <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
              {p.terms.map(term => (
                <Button
                  key={`term-${term.word}`}
                  label={`${term.isAccepted ? '✓' : '·'} ${term.word} ${term.count}`}
                  variant={term.isAccepted ? 'primary' : 'secondary'}
                  onPress={async () => {
                    await update($, proposal, now => ({
                      ...now,
                      terms: now.terms.map(one =>
                        one.word === term.word ? { ...one, isAccepted: !one.isAccepted } : one,
                      ),
                    }))
                    await recount($)
                  }}
                />
              ))}
            </Box>
            <Box marginTop={1}>
              <Button
                key="front-matter"
                label={`${p.skipsFrontMatter ? '✓' : '·'} Skip front matter ids and slugs (they are URLs)`}
                onPress={async () => {
                  await update($, proposal, now => ({ ...now, skipsFrontMatter: !now.skipsFrontMatter }))
                  await recount($)
                }}
              />
            </Box>
          </Box>
        )}

        {checksSection($, table, p)}

        <Box marginTop={1} flexDirection="column">
          <Text bold>Not included</Text>
          <Text dimColor>Tick any you also want set up.</Text>
          <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
            {(Object.keys(EXTRA_LABELS) as (keyof Extras)[]).map(key => (
              <Button
                key={`extra-${key}`}
                label={`${p.extras[key] ? '✓' : '·'} ${EXTRA_LABELS[key]}`}
                variant={p.extras[key] ? 'primary' : 'secondary'}
                onPress={() =>
                  update($, proposal, now => ({
                    ...now,
                    extras: { ...now.extras, [key]: !now.extras[key] },
                  }))
                }
              />
            ))}
          </Box>
        </Box>

        <Box marginTop={1} flexDirection="row" columnGap={1}>
          <Button
            key="apply"
            variant="primary"
            onPress={async () => {
              const ready = await read($, proposal)

              const filled = await $.prompt.fill({ text: applyText(ready) })

              if (filled.isFilled) {
                $.ui.status(undefined)
              }

              $.ui.toast(
                filled.isFilled
                  ? 'The baseline is in the prompt. Press Enter and Claude applies it.'
                  : 'Could not reach the prompt. Close any open dialog and press Apply again.',
              )
            }}
          >
            Apply <Text dimColor>puts it in the prompt</Text>
          </Button>
          <Button key="again" label="Start over" onPress={() => start($, p.path)} />
        </Box>
      </Box>
    )
  })
}
