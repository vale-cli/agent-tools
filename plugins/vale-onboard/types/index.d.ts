/** Alerts by severity, for one run. */
export type Counts = {
  total: number
  errors: number
  warnings: number
  suggestions: number
}

/** What the person has decided a rule should do. `keep` leaves it as shipped. */
export type Choice = 'keep' | 'warning' | 'suggestion' | 'off'

export type Level = 'error' | 'warning' | 'suggestion'

export type Rule = {
  name: string
  level: Level
  count: number
  /** One real alert from the person's own files: `path:line  message`. */
  example: string
  choice: Choice
}

/** A word spell check does not know, and whether to accept it. */
export type Term = {
  word: string
  count: number
  /** `path:line` of its first use. */
  where: string
  isAccepted: boolean
}

export type PackageCount = { name: string; counts: Counts }

/** Things Vale could also do here. Named in the pane, off until ticked. */
export type Extras = {
  blockingCi: boolean
  codeComments: boolean
  commitMessages: boolean
  writtenGuide: boolean
}

export type Proposal = {
  status: 'idle' | 'working' | 'ready' | 'failed'
  /** What is happening, or what went wrong, in one line. */
  note: string
  path: string
  files: string
  pkg: string
  packages: PackageCount[]
  first: Counts | null
  now: Counts | null
  rules: Rule[]
  terms: Term[]
  /** Leave front matter `id` and `slug` fields unlinted: they are URLs. */
  skipsFrontMatter: boolean
  extras: Extras
}

declare module 'claude-code' {
  interface PluginState {
    'vale-onboard': { proposal: Shaped<Proposal> }
  }
}
