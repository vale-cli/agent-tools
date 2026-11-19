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

/** Where Vale runs by itself. Each starts ticked only where the repository already works that way. */
export type Checks = {
  /** A GitHub Actions workflow: on for a GitHub repository. */
  githubAction: boolean
  /** An entry in .pre-commit-config.yaml: on where pre-commit is already used. */
  preCommit: boolean
  /** How much of a pull request is reported. */
  scope: Scope
  /** The lowest severity reported. */
  report: Level
  /** When the workflow fails. `never` is advisory. */
  failOn: FailOn
  /** Review comments with one-click fixes, rather than annotations. */
  reviewComments: boolean
}

export type Scope = 'new-lines' | 'changed-files' | 'everything'

export type FailOn = 'never' | 'error' | 'warning'

/** The files the choices would produce, and what the generator says about them. */
export type CheckPreview = {
  workflow: string
  workflowNotes: string[]
  hook: string
  hookNotes: string[]
}

/** Things Vale could also do here. Named in the pane, off until ticked. */
export type Extras = {
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
  /** Which pane last started work: the whole baseline, or only where Vale runs. */
  view: 'onboard' | 'checks'
  checks: Checks
  preview: CheckPreview
  /** What the survey found, so the pane can say why a check starts on or off. */
  isOnGitHub: boolean
  usesPreCommit: boolean
  extras: Extras
}

declare module 'claude-code' {
  interface PluginState {
    'vale-onboard': { proposal: Shaped<Proposal> }
  }
}
