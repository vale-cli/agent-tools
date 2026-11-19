import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type {
  Choice,
  Counts,
  Extras,
  Level,
  PackageCount,
  Proposal,
  Rule,
  Term,
} from '../types'

const PANE = 'vale-onboard'
const TITLE = 'Vale setup'
const CANDIDATES = ['Microsoft', 'Google']
const FRONT_MATTER = 'text.frontmatter.id,text.frontmatter.slug'
const MAX_RULES = 12
const MAX_TERMS = 16

const NO_EXTRAS: Extras = {
  blockingCi: false,
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
  extras: NO_EXTRAS,
}

// Change the tag when Proposal's fields change: it declines what an earlier
// version stored, which outlives a reload.
const proposal = atom({ plugin: 'vale-onboard', key: 'proposal' } as const, EMPTY, {
  shape: 'proposal-1',
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
  blockingCi: 'Blocking CI',
  codeComments: 'Code comments',
  commitMessages: 'Commit messages',
  writtenGuide: 'A written guide',
}

const describe = (rule: Rule): string =>
  rule.choice === 'off'
    ? `${rule.name} = NO (${rule.count} hits; switched off in the setup pane)`
    : `${rule.name} = ${rule.choice} (${rule.count} hits; was ${rule.level})`

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
    `Also set up: ${extras.length > 0 ? extras.join(', ') : 'nothing else'}`,
  ].join('\n')
}

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
const survey = async ($: EngineInterface): Promise<{ path: string } | string> => {
  try {
    const ran = await $.process.run(['sh', script($, 'survey.sh')], { timeoutMs: 60_000 })
    const lines = ran.stdout.split('\n')

    if (lines.some(line => /^Vale:\s+not installed/.test(line))) {
      return 'Vale is not installed. Ask Claude to set it up (/vale:setup), then run /vale-onboard again.'
    }

    const config = lines.find(line => line.startsWith('Config:'))

    // Only a config at the root is this repository's own; one deeper down
    // belongs to an example or a fixture.
    const own = (config ?? '')
      .replace(/^Config:\s+/, '')
      .split(/\s+/)
      .find(one => one === '.vale.ini' || one === '_vale.ini')

    if (own !== undefined) {
      return `This repository already has a Vale config (${own}). This pane is for first-time setup; ask Claude for /vale:tune or /vale:triage.`
    }

    const at = lines.findIndex(line => line.startsWith('Prose:'))
    const first = at >= 0 ? (lines[at + 1] ?? '') : ''
    const dir = first.startsWith('  ') ? (first.trim().split(/\s{2,}/)[0] ?? '') : ''

    if (dir === '') {
      return 'No prose files found here. Run /vale-onboard <path> with the directory your docs are in.'
    }

    return { path: dir === '(root)' ? '.' : dir }
  } catch {
    return 'Could not read the repository. The pane needs a POSIX shell (Git Bash on Windows).'
  }
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

  let path = asked

  if (path === '') {
    const found = await survey($)

    if (typeof found === 'string') {
      await fail($, found)

      return
    }

    path = found.path
  }

  await update($, proposal, p => ({
    ...p,
    path,
    note: `Trying ${CANDIDATES.join(' and ')} against ${path}…`,
  }))
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

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'vale-onboard',
      description: 'Preview and choose a Vale baseline for this repository in a pane',
    })

    return next(e)
  })

  on('command.run', { command: 'vale-onboard' }, async ($, e) => {
    await $.ui.open({ id: PANE, title: TITLE })
    void start($, e.args.trim())

    return { text: 'Vale setup pane opened. It is previewing a baseline; nothing is written until you apply.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const p = await read($, proposal)
    const isBusy = p.status === 'working'
    const width = Math.max(20, e.props.bodyColumns ?? 60)
    const cell = (value: number | string): string => String(value).padStart(8)
    const row = (label: string, c: Counts): string =>
      `${label.padEnd(13)}${cell(c.total)}${cell(c.errors)}${cell(c.warnings)}${cell(c.suggestions)}`

    if (p.status === 'idle' || p.status === 'failed' || p.first === null) {
      return (
        <Box flexDirection="column">
          <Text bold>{TITLE}</Text>
          <Text dimColor={p.status !== 'failed'}>{p.note}</Text>
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
        <Text dimColor>{p.note}</Text>

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
            label="Apply"
            variant="primary"
            onPress={async () => {
              const ready = await read($, proposal)

              const filled = await $.prompt.fill({ text: applyText(ready) })

              $.ui.toast(
                filled.isFilled
                  ? 'The baseline is in the prompt. Press Enter and Claude applies it.'
                  : 'Could not reach the prompt. Close any open dialog and press Apply again.',
              )
            }}
          />
          <Button key="again" label="Start over" onPress={() => start($, p.path)} />
        </Box>
      </Box>
    )
  })
}
