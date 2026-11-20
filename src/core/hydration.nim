import std/[strutils]
import types
import ../js/engine

proc extractInlineScripts*(html: string): seq[string] =
  var scripts: seq[string] = @[]
  var pos = 0
  let lower = html.toLowerAscii()

  while pos < html.len:
    let scriptStart = lower.find("<script", pos)
    if scriptStart == -1: break

    let tagEnd = html.find('>', scriptStart)
    if tagEnd == -1: break

    let tagHeader = lower[scriptStart ..< tagEnd]
    let scriptClose = lower.find("</script", tagEnd)
    if scriptClose == -1: break

    # Check if script type is javascript or inline (skip json/ld+json)
    var isExecutable = true
    if "type=" in tagHeader or "type =" in tagHeader:
      if "application/json" in tagHeader or "application/ld+json" in tagHeader:
        isExecutable = false

    if isExecutable:
      let code = html[tagEnd + 1 ..< scriptClose].strip()
      if code.len > 0:
        scripts.add(code)

    pos = scriptClose + 8

  scripts

proc hydratePage*(page: var Page, html: string, url: string = "") =
  let scripts = extractInlineScripts(html)
  if scripts.len == 0: return

  let js = newJsEngine()
  try:
    js.setDocumentTitle(page.title)

    for script in scripts:
      discard js.eval(script)

    let updatedTitle = js.getDocumentTitle()
    if updatedTitle.len > 0 and updatedTitle != page.title:
      page.title = updatedTitle
  finally:
    js.close()
