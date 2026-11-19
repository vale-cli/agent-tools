import { expect, test } from 'claude-code/testing'

import {
  actionArgs,
  after,
  applyChecksText,
  applyText,
  hookArgs,
  nextChoice,
  parse,
  previewArgs,
} from '../hooks/register'
import type { Proposal, Rule } from '../types'

const PANE = {
  plugin: 'vale-onboard',
  component: 'Pane',
  requestId: 'vale-onboard',
  props: {
    title: 'Vale setup',
    isFocused: false,
    bodyColumns: 72,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const SURVEY = [
  'Vale:          3.27.0 installed',
  'Config:        none',
  'Prose:',
  '  docs                         40 .md',
  'Translations:  none found',
  'GitHub:        yes',
  'CI:            none',
  'Hook runner:   none',
].join('\n')

const COMPARED = [
  'meta\tsection\t*.md',
  'meta\tfiles\t40 .md',
  'package\tMicrosoft\t404\t52\t99\t253',
  'package\tGoogle\t571\t67\t210\t294',
].join('\n')

const SINGLE = [
  'meta\tpackage\tMicrosoft',
  'meta\tfiles\t40 .md',
  'counts\t404\t52\t99\t253',
  "rule\tMicrosoft.Passive\tsuggestion\t77\tdocs/a.md:9  'is done' looks like passive voice.",
  "rule\tMicrosoft.Quotes\terror\t9\tdocs/b.md:27  Punctuation should be inside the quotes.",
  "rule\tVale.Spelling\terror\t33\tdocs/c.md:14  Did you really mean 'Tengo'?",
  'term\tTengo\t2\tdocs/c.md:14',
  'term\tvscode\t1\tdocs/d.md:2',
  'term\tVSCode\t4\tdocs/e.md:16',
].join('\n')

test('parse reads counts, packages, rules and terms', () => {
  expect(parse(COMPARED).packages.map(one => one.name)).toEqual(['Microsoft', 'Google'])

  const single = parse(SINGLE)

  expect(single.counts).toEqual({ total: 404, errors: 52, warnings: 99, suggestions: 253 })
  expect(single.rules.length).toBe(3)
  expect(single.rules[1]?.example).toBe('docs/b.md:27  Punctuation should be inside the quotes.')
  expect(single.terms[0]).toEqual({ word: 'Tengo', count: 2, where: 'docs/c.md:14', isAccepted: false })
})

test('a rule only ever gets quieter, then returns to how it shipped', () => {
  const rule: Rule = { name: 'A.B', level: 'error', count: 1, example: '', choice: 'keep' }
  const seen: string[] = []
  let now = rule

  for (let i = 0; i < 4; i += 1) {
    now = { ...now, choice: nextChoice(now) }
    seen.push(now.choice)
  }

  expect(seen).toEqual(['warning', 'suggestion', 'off', 'keep'])
  expect(nextChoice({ ...rule, level: 'suggestion' })).toBe('off')
})

const CHOSEN: Proposal = {
  status: 'ready',
  note: '',
  path: 'docs',
  files: '40 .md',
  pkg: 'Microsoft',
  packages: [],
  first: { total: 404, errors: 52, warnings: 99, suggestions: 253 },
  now: { total: 335, errors: 5, warnings: 65, suggestions: 265 },
  rules: [
    { name: 'Microsoft.We', level: 'warning', count: 47, example: '', choice: 'off' },
    { name: 'Microsoft.Quotes', level: 'error', count: 9, example: '', choice: 'warning' },
    { name: 'Microsoft.Passive', level: 'suggestion', count: 77, example: '', choice: 'keep' },
  ],
  terms: [
    { word: 'Tengo', count: 2, where: 'docs/c.md:14', isAccepted: true },
    { word: 'VSCode', count: 4, where: 'docs/e.md:16', isAccepted: false },
  ],
  skipsFrontMatter: true,
  view: 'onboard',
  checks: {
    githubAction: true,
    preCommit: false,
    scope: 'new-lines',
    report: 'suggestion',
    failOn: 'never',
    reviewComments: false,
  },
  preview: { workflow: '', workflowNotes: [], hook: '', hookNotes: [] },
  isOnGitHub: true,
  usesPreCommit: false,
  extras: { codeComments: true, commitMessages: false, writtenGuide: false },
}

test('the preview is asked for exactly what was chosen', () => {
  expect(previewArgs(CHOSEN)).toEqual([
    '-t',
    '-p',
    'Microsoft',
    '-A',
    'Tengo',
    '-O',
    'Microsoft.We=NO;Microsoft.Quotes=warning',
    '-i',
    'text.frontmatter.id,text.frontmatter.slug',
    'docs',
  ])
})

test('what goes to Claude names every choice and nothing that was left alone', () => {
  const text = applyText(CHOSEN)

  expect(text).toContain('Package: Microsoft')
  expect(text).toContain('Vocabulary, accept: Tengo')
  expect(text).toContain('left unticked (findings, not vocabulary): VSCode')
  expect(text).toContain('Microsoft.We = NO (47 hits')
  expect(text).toContain('Microsoft.Quotes = warning (9 hits; was error)')
  expect(text).toContain('a GitHub Actions workflow: new lines only; reports every alert; fails never (advisory).')
  expect(text).toContain('ci.sh action -f docs')
  expect(text.includes('pre-commit hook')).toBe(false)
  expect(text).toContain('Also set up: Code comments')
  expect(
    applyText({ ...CHOSEN, checks: { ...CHOSEN.checks, githubAction: false } }),
  ).toContain('nowhere automatic')
  expect(text.includes('Microsoft.Passive')).toBe(false)
})

test('the choices about a pull request become the generator\'s flags', () => {
  const strict: Proposal = {
    ...CHOSEN,
    checks: {
      githubAction: true,
      preCommit: true,
      scope: 'changed-files',
      report: 'warning',
      failOn: 'error',
      reviewComments: true,
    },
  }

  expect(actionArgs(CHOSEN)).toEqual(['action', '-f', 'docs'])
  expect(actionArgs(strict)).toEqual(['action', '-s', 'changed-files', '-l', 'warning', '-x', 'error', '-r', '-f', 'docs'])
  expect(hookArgs(strict)).toEqual(['pre-commit', '-f', 'docs'])
  // The repository root needs no -f.
  expect(actionArgs({ ...CHOSEN, path: '.' })).toEqual(['action'])

  const text = applyChecksText(strict)

  expect(text).toContain('changed files, whole; reports warnings and errors; fails on errors; as review comments.')
  expect(text).toContain('ci.sh action -s changed-files -l warning -x error -r -f docs')
  expect(text).toContain('ci.sh pre-commit -f docs')
  expect(after(['a', 'b', 'c'], 'c')).toBe('a')
})

const WORKFLOW = 'name: Vale\non: [pull_request]\n'
const NOTES = 'ci.sh: save as .github/workflows/vale.yml\nci.sh: advisory - reports on the lines a pull request adds, and always passes\n'

test('the pane previews, takes a choice, and hands the baseline to the prompt', async ($, on) => {
  const runs: string[][] = []
  let filled = ''

  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.toast', () => ({ value: undefined }))
  on('prompt.fill', (_, e) => {
    filled = e.text

    // An event, not a call on $: it is answered by its own result.
    return { isFilled: true, text: e.text, cursor: e.text.length }
  })
  on('process.run', (_, e) => {
    const argv = [...e.argv]

    runs.push(argv)
    const isSurvey = (argv[1] ?? '').endsWith('survey.sh')
    const isGenerator = (argv[1] ?? '').endsWith('ci.sh')
    const packages = argv.filter(one => one === '-p').length
    const stdout = isGenerator ? WORKFLOW : isSurvey ? SURVEY : packages > 1 ? COMPARED : SINGLE

    return {
      value: {
        exitCode: 0,
        stdout,
        stderr: isGenerator ? NOTES : '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    }
  })

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    runs.length = 0
    const ui = await $.ui.mount({ ...PANE, surface })
    // The proposal is the session's, so the second surface finds the first
    // one's result and starts over from it.
    const isFresh = (await ui.find({ key: 'start' })) !== undefined

    await ui.press({ key: isFresh ? 'start' : 'again' })
    expect(await ui.find({ type: 'Text', text: /Vale baseline for docs/ })).toBeDefined()
    // The survey chose the path, the comparison the quieter package.
    const compared = runs.find(argv => argv.filter(one => one === '-p').length === 2)
    // The survey runs every time, so a check's default is never stale.
    expect((runs[0]?.[1] ?? '').endsWith('survey.sh')).toBe(true)

    expect(compared?.slice(-5)).toEqual(['-p', 'Microsoft', '-p', 'Google', 'docs'])
    expect(await ui.find({ key: 'pkg-Microsoft' })).toBeDefined()
    // A capitalised word in the body is ticked; a front matter id is not.
    expect((await ui.find({ key: 'term-Tengo' }))?.props.label).toBe('✓ Tengo 2')
    expect((await ui.find({ key: 'term-vscode' }))?.props.label).toBe('· vscode 1')

    await ui.press({ key: 'choice-Microsoft.Quotes' })
    expect((await ui.find({ key: 'choice-Microsoft.Quotes' }))?.props.label).toBe('warning')
    expect(runs.some(argv => argv.includes('Microsoft.Quotes=warning'))).toBe(true)

    // On GitHub with no pre-commit: the action starts ticked, the hook does not.
    expect((await ui.find({ key: 'check-githubAction' }))?.props.label).toBe('✓ GitHub Action')
    expect((await ui.find({ key: 'check-preCommit' }))?.props.label).toBe('· pre-commit hook')
    // The generator's own words explain the choice, and its file is shown.
    expect(await ui.find({ type: 'Text', text: /advisory - reports on the lines/ })).toBeDefined()
    expect((await ui.find({ key: 'check-scope' }))?.props.label).toBe('New lines only')
    await ui.press({ key: 'check-scope' })
    expect((await ui.find({ key: 'check-scope' }))?.props.label).toBe('Changed files, whole')
    expect(runs.at(-1)).toEqual(expect.arrayContaining(['action', '-s', 'changed-files']))
    await ui.press({ key: 'check-preCommit' })

    await ui.press({ key: 'apply' })
    expect(filled).toContain('ci.sh action -s changed-files -f docs')
    expect(filled).toContain('a pre-commit hook')
    expect(filled).toContain('Microsoft.Quotes = warning (9 hits; was error)')
    expect(filled).toContain('Path: docs')
    await ui.unmount()
  }
})

const HAS_CONFIG = [
  'Vale:          3.27.0 installed',
  'Config:        .vale.ini ',
  'Prose:',
  '  docs                         3 .md',
  'GitHub:        yes',
  'Hook runner:   .pre-commit-config.yaml',
].join('\n')

test('a repository that already has Vale gets the checks pane alone', async ($, on) => {
  const runs: string[][] = []
  let filled = ''

  on('ui.toast', () => ({ value: undefined }))
  on('prompt.fill', (_, e) => {
    filled = e.text

    return { isFilled: true, text: e.text, cursor: e.text.length }
  })
  on('process.run', (_, e) => {
    const argv = [...e.argv]

    runs.push(argv)
    const isGenerator = (argv[1] ?? '').endsWith('ci.sh')

    return {
      value: {
        exitCode: 0,
        stdout: isGenerator ? WORKFLOW : HAS_CONFIG,
        stderr: isGenerator ? NOTES : '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    }
  })

  const ui = await $.ui.mount({ ...PANE, requestId: 'vale-checks', props: { ...PANE.props, title: 'Vale checks' }, surface: 'desktop' })

  await ui.press({ key: 'start-checks' })
  expect(await ui.find({ type: 'Text', text: /Where Vale runs, for docs/ })).toBeDefined()
  // On GitHub and already using pre-commit: both start ticked.
  expect((await ui.find({ key: 'check-githubAction' }))?.props.label).toBe('✓ GitHub Action')
  expect((await ui.find({ key: 'check-preCommit' }))?.props.label).toBe('✓ pre-commit hook')

  await ui.press({ key: 'check-failOn' })
  expect((await ui.find({ key: 'check-failOn' }))?.props.label).toBe('On errors')
  await ui.press({ key: 'check-reviewComments' })
  await ui.press({ key: 'apply-checks' })
  expect(filled).toContain('Set up where Vale runs in this repository')
  expect(filled).toContain('ci.sh action -x error -r -f docs')
  expect(filled).toContain('ci.sh pre-commit -f docs')
  // It never ran the baseline preview: this repository has one already.
  expect(runs.some(argv => (argv[1] ?? '').endsWith('preview.sh'))).toBe(false)
  await ui.unmount()
})

test('a repository that already has a config is told where to go instead', async ($, on) => {
  on('process.run', () => ({
    value: {
      exitCode: 0,
      stdout: 'Vale:          3.27.0 installed\nConfig:        .vale.ini \nProse:\n  docs   3 .md\n',
      stderr: '',
      isStdoutTruncated: false,
      isStderrTruncated: false,
    },
  }))

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })

  await ui.press({ key: 'start' })
  expect(await ui.find({ type: 'Text', text: /already has a Vale config/ })).toBeDefined()
  await ui.unmount()
})
