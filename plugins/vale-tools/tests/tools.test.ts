import { expect, test } from 'claude-code/testing'

import { report } from '../hooks/register'

const LINT = 'mcp__vale-tools__lint'
const TEST = 'mcp__vale-tools__test'

// What Vale 3.27.0 printed for one sentence, in a project using the Microsoft
// package: the fields the tool reads, unedited.
const REAL = String.raw`{"stdin.md":[{"Check":"Microsoft.Wordiness","Message":"Consider using 'to' instead of 'In order to'.","Severity":"suggestion","Line":1,"Span":[1,11],"Match":"In order to","Suggestions":["to"]},{"Check":"Microsoft.Wordiness","Message":"Consider using 'use' instead of 'utilize'.","Severity":"suggestion","Line":1,"Span":[13,19],"Match":"utilize","Suggestions":["use"]},{"Check":"Vale.Spelling","Message":"Did you really mean 'teh'?","Severity":"error","Line":1,"Span":[21,23],"Match":"teh","Suggestions":[]},{"Check":"Docs.Terms","Message":"Use 'VS Code' instead of 'VSCode'.","Severity":"warning","Line":1,"Span":[25,30],"Match":"VSCode","Suggestions":[]},{"Check":"Vale.Spelling","Message":"Did you really mean 'VSCode'?","Severity":"error","Line":1,"Span":[25,30],"Match":"VSCode","Suggestions":[]},{"Check":"Microsoft.Foreign","Message":"Use 'for example' instead of 'e.g.,'.","Severity":"warning","Line":1,"Span":[32,36],"Match":"e.g.,","Suggestions":["for example"]}]}`

const ran = (stdout: string, exitCode = 0, stderr = '') => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})

test('a report gives each alert its place, rule, message and the fix it carries', () => {
  const text = report(REAL, 'suggestion')

  expect(text).toContain('stdin.md:1:1 suggestion Microsoft.Wordiness')
  expect(text).toContain('Fix: replace "In order to" with "to".')
  // A spelling suggestion is a guess, so it is not offered as a fix.
  expect(text).toContain("Vale.Spelling: Did you really mean 'teh'?")
  expect(/Vale\.Spelling[^\n]*Fix:/.test(text)).toBe(false)
  expect(text.split('\n')[0]).toMatch(/^\d+ alerts?: \d+ errors?, \d+ warnings?, \d+ suggestions?\.$/)
})

test('a floor leaves out what is below it', () => {
  const text = report(REAL, 'error')

  expect(text.includes(' suggestion ')).toBe(false)
  expect(text).toContain(' error ')
  expect(report('{"stdin.md":[]}', 'error')).toBe('No alerts at error level or above.')
})

test('lint sends a draft on stdin and names what it stands for', async ($, on) => {
  const calls: { argv: string[]; stdin: string | undefined }[] = []

  on('tool.register', (_, e) => ({ value: { tool: `mcp__vale-tools__${e.name}` } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    calls.push({ argv: [...e.argv], stdin: e.init?.stdin })

    return ran(REAL)
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const plainDraft = await $.tool.call({ tool: LINT, text: 'In order to utilize teh VSCode e.g., this.' })

  expect(calls[0]?.argv).toEqual(['vale', '--no-exit', '--output=JSON', '--ext=.md'])
  expect(calls[0]?.stdin).toBe('In order to utilize teh VSCode e.g., this.')
  expect(String(plainDraft.result)).toContain('Microsoft.Wordiness')

  await $.tool.call({ tool: LINT, text: 'fixed stuff.', as_path: 'COMMIT_EDITMSG' })
  expect(calls[1]?.argv.at(-1)).toBe('--path=COMMIT_EDITMSG')

  await $.tool.call({ tool: LINT, path: 'docs', min_level: 'error' })
  expect(calls[2]?.argv).toEqual(['vale', '--no-exit', '--output=JSON', 'docs'])
  expect(calls[2]?.stdin).toBeUndefined()
})

test('lint says what to do when the project has no configuration', async ($, on) => {
  on('tool.register', (_, e) => ({ value: { tool: `mcp__vale-tools__${e.name}` } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  // Where Vale 3.27.0 really writes it: standard error, pretty-printed.
  on('process.run', () =>
    ran('', 2, '{\n  "Line": 0,\n  "Path": "",\n  "Text": "no config file found",\n  "Code": "E100",\n  "Span": 0\n}\n'),
  )
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const answer = await $.tool.call({ tool: LINT, text: 'Hello.' })

  // The hook's { deny } reaches the model as the call's error.
  expect(answer.isError).toBe(true)
  expect(String(answer.text)).toContain('E100: no config file found')
  expect(String(answer.text)).toContain('vale:onboard')

  const neither = await $.tool.call({ tool: LINT })

  expect(String(neither.text)).toContain('either `text`')
})

test('test runs the cases for one style and passes the verdict on', async ($, on) => {
  const calls: string[][] = []

  on('tool.register', (_, e) => ({ value: { tool: `mcp__vale-tools__${e.name}` } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    calls.push([...e.argv])

    return calls.length === 1
      ? ran(' SUCCESS  3 files — 8 passed, 0 failed\n')
      : ran('', 1, ' ERROR   1 file — 1 passed, 1 failed\n')
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const passed = await $.tool.call({ tool: TEST, path: 'styles/Acme', coverage: true })

  expect(calls[0]).toEqual(['vale', 'test', '--coverage', 'styles/Acme'])
  expect(String(passed.result)).toContain('8 passed, 0 failed')

  const failed = await $.tool.call({ tool: TEST })

  expect(calls[1]).toEqual(['vale', 'test'])
  expect(failed.isError).toBe(true)
  expect(String(failed.text)).toContain('1 failed')
})
