import type { EngineInterface, Register } from 'claude-code'

const LINT = 'mcp__vale-tools__lint'
const TEST = 'mcp__vale-tools__test'
const LEVELS = ['suggestion', 'warning', 'error'] as const
const MAX_ALERTS = 200

type Level = (typeof LEVELS)[number]

/** One alert as `vale --output=JSON` writes it; only the fields used here. */
type Alert = {
  Check?: string
  Message?: string
  Severity?: string
  Line?: number
  Span?: number[]
  Match?: string
  Suggestions?: string[]
}

const isLevel = (value: unknown): value is Level =>
  typeof value === 'string' && (LEVELS as readonly string[]).includes(value)

const text = (value: unknown): string => (typeof value === 'string' ? value : '')

// The CLI colours its error text; a model reads the words.
const plain = (value: string): string =>
  value.replace(new RegExp(String.fromCharCode(27) + '\\[[0-9;]*m', 'g'), '').trim()

/** Vale's own account of why it could not run, from the JSON it prints. */
const failure = (stdout: string, stderr: string): string => {
  // The error is JSON under --output=JSON, and it goes to standard error.
  for (const stream of [stderr, stdout]) {
    try {
      const error = JSON.parse(plain(stream)) as { Code?: string; Text?: string; Path?: string }

      if (typeof error.Text === 'string') {
        const where = error.Path ? ` (${error.Path})` : ''
        const hint =
          error.Text === 'no config file found'
            ? ' This project has no .vale.ini yet: set Vale up first (the vale:onboard or vale:setup skill).'
            : ''

        return `Vale could not run: ${error.Code ?? 'error'}: ${plain(error.Text)}${where}.${hint}`
      }
    } catch {
      // Not JSON: try the other stream, then fall through to the raw text.
    }
  }

  return `Vale could not run: ${plain(stderr) || plain(stdout) || 'no output'}`
}

const some = (count: number, noun: string): string => `${count} ${noun}${count === 1 ? '' : 's'}`

/**
 * Turns Vale's JSON into the lines a model acts on: where, how serious, which
 * rule, what it says, and the fix the rule itself carries when it has one.
 */
export const report = (stdout: string, minLevel: Level): string => {
  const byFile = JSON.parse(stdout) as Record<string, Alert[]>
  const floor = LEVELS.indexOf(minLevel)
  const counts: Record<Level, number> = { error: 0, warning: 0, suggestion: 0 }
  const lines: string[] = []
  let hidden = 0

  for (const [file, alerts] of Object.entries(byFile)) {
    for (const alert of alerts) {
      const severity = isLevel(alert.Severity) ? alert.Severity : 'suggestion'

      if (LEVELS.indexOf(severity) < floor) {
        continue
      }

      counts[severity] += 1

      if (lines.length >= MAX_ALERTS) {
        hidden += 1
        continue
      }

      const at = `${file}:${alert.Line ?? 0}:${alert.Span?.[0] ?? 0}`
      // A spelling suggestion is a guess at the word meant, not a fix to apply.
      const fix =
        alert.Check !== 'Vale.Spelling' && alert.Suggestions && alert.Suggestions.length > 0
          ? ` Fix: replace "${alert.Match ?? ''}" with "${alert.Suggestions[0] ?? ''}".`
          : ''

      lines.push(`${at} ${severity} ${alert.Check ?? '?'}: ${alert.Message ?? ''}${fix}`)
    }
  }

  const total = counts.error + counts.warning + counts.suggestion

  if (total === 0) {
    return minLevel === 'suggestion'
      ? 'No alerts. Either the text is clean, or no section of the configuration matches it.'
      : `No alerts at ${minLevel} level or above.`
  }

  return [
    `${some(total, 'alert')}: ${some(counts.error, 'error')}, ${some(counts.warning, 'warning')}, ${some(counts.suggestion, 'suggestion')}.`,
    'Errors are what the project decided must not ship; warnings and suggestions are advisory.',
    ...lines,
    ...(hidden > 0 ? [`…and ${hidden} more, not listed. Lint a narrower path to see them.`] : []),
  ].join('\n')
}

// A tool.run hook answers `{ result }`, or `{ deny }` with the error the model
// reads when the call could not be served.
const lint = async ($: EngineInterface, input: Record<string, unknown>) => {
  const draft = text(input.text)
  const path = text(input.path)
  const minLevel = isLevel(input.min_level) ? input.min_level : 'suggestion'

  if ((draft === '') === (path === '')) {
    return { deny: 'Give either `text` (a draft to lint) or `path` (a file or directory), not both and not neither.' }
  }

  const base = ['vale', '--no-exit', '--output=JSON']
  // A draft has no name, so say what it stands for: its format, and the path
  // whose configuration section should apply to it.
  const standsFor = text(input.as_path)
  const format = text(input.format).replace(/^\./, '') || 'md'
  const argv =
    draft !== ''
      ? [...base, standsFor !== '' ? `--path=${standsFor}` : `--ext=.${format}`]
      : [...base, path]

  try {
    const ran = await $.process.run(argv, draft !== '' ? { stdin: draft, timeoutMs: 120_000 } : { timeoutMs: 120_000 })

    if (ran.exitCode !== 0) {
      return { deny: failure(ran.stdout, ran.stderr) }
    }

    return { result: report(ran.stdout, minLevel), isReadOnly: true as const }
  } catch {
    return { deny: 'Could not start vale. Is it installed and on PATH? The vale:setup skill installs it.' }
  }
}

const test = async ($: EngineInterface, input: Record<string, unknown>) => {
  const path = text(input.path)
  const argv = ['vale', 'test', ...(input.coverage === true ? ['--coverage'] : []), ...(path !== '' ? [path] : [])]

  try {
    const ran = await $.process.run(argv, { timeoutMs: 180_000 })
    const out = plain(`${ran.stdout}\n${ran.stderr}`)

    if (ran.exitCode !== 0) {
      return { deny: out || `vale test exited ${ran.exitCode}` }
    }

    return { result: out || 'vale test passed and printed nothing.', isReadOnly: true as const }
  } catch {
    return { deny: 'Could not start vale. Is it installed and on PATH? The vale:setup skill installs it.' }
  }
}

/** A selection worth a row: some prose, not a page of it. */
const isPhrase = (selected: string): boolean => selected.trim().length > 0 && selected.length <= 2000

/** A single word or name, which is what a vocabulary holds. */
const isTerm = (selected: string): boolean => /^[\p{L}][\p{L}\p{N}'’.-]{1,40}$/u.test(selected.trim())

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.tool.register({
      name: 'lint',
      description:
        "Lint prose with Vale against this project's own style rules and vocabulary. Give `text` for a draft you have not written to disk yet (a paragraph, a commit message, a page), or `path` for a file or directory. Returns each alert with its line, severity, rule, message and, where the rule has one, the exact replacement. Use it before writing prose into the repository, and to check a file after editing it. Reads only; changes nothing.",
      isDeferred: false,
      inputSchema: {
        type: 'object',
        properties: {
          text: { type: 'string', description: 'The draft to lint. Use this or `path`.' },
          path: { type: 'string', description: 'A file or directory to lint, relative to the working directory. Use this or `text`.' },
          format: { type: 'string', description: 'With `text`: the format it is written in, as a file extension. Default "md".' },
          as_path: { type: 'string', description: 'With `text`: the path the draft will be saved at, so the rules for that location apply (e.g. "docs/guide/install.md", or "COMMIT_EDITMSG" for a commit message).' },
          min_level: { type: 'string', enum: [...LEVELS], description: 'Lowest severity to report. Default "suggestion".' },
        },
      },
    })
    await $.tool.register({
      name: 'test',
      description:
        "Run the test cases kept beside a project's own Vale rules (`vale test`). Give `path` for one style directory or rule file, and `coverage: true` to fail when a rule never produces an alert in any case. Use it after writing or changing a rule. Reads only.",
      inputSchema: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'A style directory or rule file, e.g. "styles/Acme". Without it, every test the configuration can find.' },
          coverage: { type: 'boolean', description: 'Fail when a rule under `path` matched nothing in any case. Name a `path` with this, or synced packages count as untested.' },
        },
      },
    })

    return next(e)
  })

  // In the desktop app's right-click menu: check a selection, or accept a
  // selected word. Both put a request in the prompt; neither acts by itself.
  on('ui.render', { component: 'ContextMenu' }, ($, e, next) => {
    const selected = e.props.selection?.text ?? ''

    if (!isPhrase(selected)) {
      return next(e)
    }

    const { Box, Button, Text } = $.ui.resolve(e)
    const ask = (text: string) => $.prompt.fill({ text, mode: 'insert' })
    const quoted = selected.trim().replace(/^/gm, '> ')

    return (
      <Box flexDirection="column">
        <Button
          key="vale-check"
          onPress={() => ask(`Check this with Vale and tell me what it flags:\n${quoted}\n`)}
        >
          Check with Vale <Text dimColor>Adds to the prompt</Text>
        </Button>
        {isTerm(selected) && (
          <Button
            key="vale-accept"
            onPress={() =>
              ask(`Add "${selected.trim()}" to this project's Vale vocabulary (vale:vocab), if it is spelled the way we write it.\n`)
            }
          >
            Add to Vale vocabulary <Text dimColor>Adds to the prompt</Text>
          </Button>
        )}
      </Box>
    )
  })

  on('tool.run', { tool: LINT }, ($, e) => lint($, e as Record<string, unknown>))
  on('tool.run', { tool: TEST }, ($, e) => test($, e as Record<string, unknown>))
}
