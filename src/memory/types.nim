import std/[tables, options, times, json]

type
  ActionFeedback* = object
    success*: bool
    elementFound*: bool
    errorMsg*: Option[string]

  DomainPlaybook* = object
    domain*: string
    learnedSelectors*: Table[string, string]
    fastpaths*: Table[string, string]
    dismissModals*: seq[string]
    updatedAt*: string

  PageRecord* = object
    url*: string
    title*: string
    domain*: string
    snippet*: string
    content*: string
    status*: int
    rank*: float

  HandoffSession* = object
    id*: string
    goal*: string
    activeUrl*: string
    activeTitle*: string
    history*: seq[string]
    savedAt*: string
