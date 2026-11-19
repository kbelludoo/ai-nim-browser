import std/[strutils, tables, options, times, json, os, math, algorithm]
import types

type
  MemoryEngine* = ref object
    storagePath*: string
    playbooks*: Table[string, DomainPlaybook]
    handoffs*: Table[string, HandoffSession]
    pages*: seq[PageRecord]

proc extractDomain*(urlStr: string): string =
  var s = urlStr
  let protoIdx = s.find("://")
  if protoIdx != -1:
    s = s[protoIdx + 3 .. ^1]
  let slashIdx = s.find('/')
  if slashIdx != -1:
    s = s[0 ..< slashIdx]
  let colonIdx = s.find(':')
  if colonIdx != -1:
    s = s[0 ..< colonIdx]
  s.toLowerAscii()

proc newMemoryEngine*(path: string = ""): MemoryEngine =
  let finalPath = if path.len > 0: path else: ".ai-browser-memory" / "browser_memory.json"
  result = MemoryEngine(
    storagePath: finalPath,
    playbooks: initTable[string, DomainPlaybook](),
    handoffs: initTable[string, HandoffSession](),
    pages: @[]
  )

  if fileExists(finalPath):
    try:
      let raw = readFile(finalPath)
      let j = parseJson(raw)
      if j.hasKey("playbooks"):
        for k, v in j["playbooks"].pairs:
          var pb = DomainPlaybook(
            domain: k,
            learnedSelectors: initTable[string, string](),
            fastpaths: initTable[string, string](),
            dismissModals: @[],
            updatedAt: v.getOrDefault("updated_at").getStr()
          )
          if v.hasKey("learned_selectors"):
            for sk, sv in v["learned_selectors"].pairs:
              pb.learnedSelectors[sk] = sv.getStr()
          if v.hasKey("fastpaths"):
            for fk, fv in v["fastpaths"].pairs:
              pb.fastpaths[fk] = fv.getStr()
          if v.hasKey("dismiss_modals"):
            for dm in v["dismiss_modals"]:
              pb.dismissModals.add(dm.getStr())
          result.playbooks[k] = pb

      if j.hasKey("handoffs"):
        for k, v in j["handoffs"].pairs:
          var hist: seq[string] = @[]
          if v.hasKey("history"):
            for h in v["history"]: hist.add(h.getStr())
          result.handoffs[k] = HandoffSession(
            id: k,
            goal: v.getOrDefault("goal").getStr(),
            activeUrl: v.getOrDefault("active_url").getStr(),
            activeTitle: v.getOrDefault("active_title").getStr(),
            history: hist,
            savedAt: v.getOrDefault("saved_at").getStr()
          )

      if j.hasKey("pages"):
        for p in j["pages"]:
          result.pages.add(PageRecord(
            url: p.getOrDefault("url").getStr(),
            title: p.getOrDefault("title").getStr(),
            domain: p.getOrDefault("domain").getStr(),
            content: p.getOrDefault("content").getStr(),
            status: p.getOrDefault("status").getInt(),
            snippet: "",
            rank: 0.0
          ))
    except:
      discard

proc save*(e: MemoryEngine) =
  if e.storagePath.len == 0: return
  try:
    let dir = parentDir(e.storagePath)
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)

    var root = newJObject()
    var pbObj = newJObject()
    for k, pb in e.playbooks:
      var jpb = newJObject()
      var jls = newJObject()
      for sk, sv in pb.learnedSelectors: jls[sk] = %sv
      jpb["learned_selectors"] = jls
      var jfp = newJObject()
      for fk, fv in pb.fastpaths: jfp[fk] = %fv
      jpb["fastpaths"] = jfp
      var jdm = newJArray()
      for dm in pb.dismissModals: jdm.add(%dm)
      jpb["dismiss_modals"] = jdm
      jpb["updated_at"] = %pb.updatedAt
      pbObj[k] = jpb
    root["playbooks"] = pbObj

    var hoObj = newJObject()
    for k, ho in e.handoffs:
      var jho = newJObject()
      jho["goal"] = %ho.goal
      jho["active_url"] = %ho.activeUrl
      jho["active_title"] = %ho.activeTitle
      var jh = newJArray()
      for h in ho.history: jh.add(%h)
      jho["history"] = jh
      jho["saved_at"] = %ho.savedAt
      hoObj[k] = jho
    root["handoffs"] = hoObj

    var pgArr = newJArray()
    for pg in e.pages:
      var jpg = newJObject()
      jpg["url"] = %pg.url
      jpg["title"] = %pg.title
      jpg["domain"] = %pg.domain
      jpg["content"] = %pg.content
      jpg["status"] = %pg.status
      pgArr.add(jpg)
    root["pages"] = pgArr

    writeFile(e.storagePath, $root)
  except:
    discard

proc learnSelector*(e: MemoryEngine, domain: string, key: string, selector: string) =
  let d = domain.toLowerAscii()
  if not e.playbooks.hasKey(d):
    e.playbooks[d] = DomainPlaybook(
      domain: d,
      learnedSelectors: initTable[string, string](),
      fastpaths: initTable[string, string](),
      dismissModals: @[],
      updatedAt: $now()
    )
  e.playbooks[d].learnedSelectors[key] = selector
  e.playbooks[d].updatedAt = $now()
  e.save()

proc getLearnedSelector*(e: MemoryEngine, domain: string, key: string): Option[string] =
  let d = domain.toLowerAscii()
  if e.playbooks.hasKey(d) and e.playbooks[d].learnedSelectors.hasKey(key):
    return some(e.playbooks[d].learnedSelectors[key])
  none(string)

proc recordVisit*(e: MemoryEngine, urlStr: string, title: string, content: string, status: int = 200) =
  if urlStr.len == 0: return
  let d = extractDomain(urlStr)
  var cleanContent = content.strip()
  if cleanContent.len > 200_000:
    cleanContent.setLen(200_000)

  # Check if exists and update
  var found = false
  for i in 0 ..< e.pages.len:
    if e.pages[i].url == urlStr:
      e.pages[i].title = title
      e.pages[i].content = cleanContent
      e.pages[i].status = status
      found = true
      break
  if not found:
    e.pages.add(PageRecord(
      url: urlStr,
      title: title,
      domain: d,
      content: cleanContent,
      status: status,
      snippet: "",
      rank: 0.0
    ))
  e.save()

# BM25 Scoring & Search
proc searchMemory*(e: MemoryEngine, query: string, limit: int = 5): seq[PageRecord] =
  let queryTokens = query.toLowerAscii().splitWhitespace()
  if queryTokens.len == 0 or e.pages.len == 0:
    return @[]

  let actualLimit = if limit <= 0: 5 else: limit
  let totalDocs = e.pages.len.float
  var avgDocLen = 0.0
  for p in e.pages:
    avgDocLen += p.content.len.float
  avgDocLen /= totalDocs

  const k1 = 1.2
  const b = 0.75

  var scoredPages: seq[PageRecord] = @[]

  for page in e.pages:
    let text = (page.title & " " & page.content).toLowerAscii()
    let docLen = page.content.len.float
    var score = 0.0
    var matchedTokens = 0

    for token in queryTokens:
      if token.len == 0: continue
      var tf = 0
      var pos = 0
      while true:
        pos = text.find(token, pos)
        if pos == -1: break
        inc tf
        pos += token.len

      if tf > 0:
        inc matchedTokens
        # Document frequency
        var df = 0
        for other in e.pages:
          if other.content.toLowerAscii().contains(token) or other.title.toLowerAscii().contains(token):
            inc df
        let idf = ln((totalDocs - df.float + 0.5) / (df.float + 0.5) + 1.0)
        let num = tf.float * (k1 + 1.0)
        let denom = tf.float + k1 * (1.0 - b + b * (docLen / avgDocLen))
        score += idf * (num / denom)

    if matchedTokens > 0:
      # Generate snippet around first match
      var snippet = ""
      var firstPos = -1
      var matchedWord = ""
      for token in queryTokens:
        let pIdx = page.content.toLowerAscii().find(token)
        if pIdx != -1 and (firstPos == -1 or pIdx < firstPos):
          firstPos = pIdx
          matchedWord = token

      if firstPos != -1:
        let snipStart = max(0, firstPos - 40)
        let snipEnd = min(page.content.len, firstPos + matchedWord.len + 60)
        let prefix = if snipStart > 0: "... " else: ""
        let suffix = if snipEnd < page.content.len: " ..." else: ""
        let snippetRaw = page.content[snipStart ..< snipEnd]
        snippet = prefix & snippetRaw.replace(matchedWord, "<b>" & matchedWord & "</b>") & suffix
      else:
        let previewLen = min(page.content.len, 120)
        snippet = page.content[0 ..< previewLen] & "..."

      var rec = page
      rec.snippet = snippet
      rec.rank = -score # lower is better in BM25 ranking sorting
      scoredPages.add(rec)

  scoredPages.sort(proc(x, y: PageRecord): int = cmp(x.rank, y.rank))
  if scoredPages.len > actualLimit:
    scoredPages.setLen(actualLimit)
  scoredPages

proc exportHandoff*(e: MemoryEngine, goal: string, activeUrl: string, activeTitle: string, history: seq[string]): HandoffSession =
  let randId = "b-handoff-" & $(now().toTime().toUnix())
  let session = HandoffSession(
    id: randId,
    goal: goal,
    activeUrl: activeUrl,
    activeTitle: activeTitle,
    history: history,
    savedAt: $now()
  )
  e.handoffs[randId] = session
  e.save()
  session

proc resumeHandoff*(e: MemoryEngine, id: string): Option[HandoffSession] =
  if e.handoffs.hasKey(id):
    return some(e.handoffs[id])
  none(HandoffSession)
