import std/[options, strutils]
import types, dom, semantic, transport, url_policy

type
  BrowserActionKind* = enum
    ActionExtractText
    ActionWaitForText
    ActionBack
    ActionForward
    ActionReload
    ActionClick
    ActionFill

  BrowserAction* = object
    case kind*: BrowserActionKind
    of ActionWaitForText:
      targetText*: string
    of ActionClick:
      clickRef*: string
    of ActionFill:
      fillRef*: string
      fillValue*: string
    else:
      discard

  BrowserError* = object of CatchableError

  BrowserOutput* = object
    snapshot*: Option[SemanticSnapshot]
    text*: Option[string]

  HttpSnapshotBrowser* = ref object
    transport*: SafeHttpTransport
    snapshot*: Option[SemanticSnapshot]
    currentText*: Option[string]
    history*: seq[string]
    historyIndex*: Option[int]

proc newHttpSnapshotBrowser*(transport: SafeHttpTransport = newSafeHttpTransport()): HttpSnapshotBrowser =
  HttpSnapshotBrowser(
    transport: transport,
    snapshot: none(SemanticSnapshot),
    currentText: none(string),
    history: @[],
    historyIndex: none(int)
  )

proc currentSnapshot*(b: HttpSnapshotBrowser): Option[SemanticSnapshot] =
  b.snapshot

proc currentText*(b: HttpSnapshotBrowser): Option[string] =
  b.currentText

proc fetchAndParse*(b: HttpSnapshotBrowser, targetUrl: string): (SemanticSnapshot, string) =
  let res = b.transport.get(targetUrl)
  if not res.isOk:
    raise newException(BrowserError, res.err)

  let resp = res.val
  let snap = parseSemanticHtml(resp.finalUrl, resp.body)
  let page = parsePage(resp.finalUrl, resp.body, resp.status, 0)
  (snap, page.text)

proc navigate*(b: HttpSnapshotBrowser, targetUrl: string): SemanticSnapshot =
  let (snap, text) = b.fetchAndParse(targetUrl)

  if b.historyIndex.isSome:
    b.history.setLen(b.historyIndex.get + 1)
  else:
    b.history.setLen(0)

  b.history.add(snap.url)
  b.historyIndex = some(b.history.len - 1)
  b.currentText = some(text)
  b.snapshot = some(snap)
  snap

proc loadHistoryEntry*(b: HttpSnapshotBrowser, idx: int): SemanticSnapshot =
  if idx < 0 or idx >= b.history.len:
    raise newException(BrowserError, "History entry does not exist")
  let url = b.history[idx]
  let (snap, text) = b.fetchAndParse(url)
  b.snapshot = some(snap)
  b.currentText = some(text)
  b.historyIndex = some(idx)
  snap

proc perform*(b: HttpSnapshotBrowser, action: BrowserAction): BrowserOutput =
  case action.kind
  of ActionExtractText:
    BrowserOutput(snapshot: b.snapshot, text: b.currentText)
  of ActionWaitForText:
    let cur = if b.currentText.isSome: b.currentText.get else: ""
    if cur.contains(action.targetText):
      BrowserOutput(snapshot: b.snapshot, text: some(cur))
    else:
      raise newException(BrowserError, "Text not found in snapshot: " & action.targetText)
  of ActionBack:
    if b.historyIndex.isNone or b.historyIndex.get == 0:
      raise newException(BrowserError, "Already at first history entry")
    let snap = b.loadHistoryEntry(b.historyIndex.get - 1)
    BrowserOutput(snapshot: some(snap), text: b.currentText)
  of ActionForward:
    if b.historyIndex.isNone or b.historyIndex.get + 1 >= b.history.len:
      raise newException(BrowserError, "Already at latest history entry")
    let snap = b.loadHistoryEntry(b.historyIndex.get + 1)
    BrowserOutput(snapshot: some(snap), text: b.currentText)
  of ActionReload:
    if b.historyIndex.isNone:
      raise newException(BrowserError, "No page to reload")
    let snap = b.loadHistoryEntry(b.historyIndex.get)
    BrowserOutput(snapshot: some(snap), text: b.currentText)
  of ActionClick, ActionFill:
    raise newException(BrowserError, "Mutating actions require a live JavaScript-capable browser engine")
