import std/[strutils, tables, parseutils, unicode]

const VoidTags* = [
  "area", "base", "br", "col", "embed", "hr", "img", "input",
  "link", "meta", "param", "source", "track", "wbr"
]

const RawTextTags* = ["script", "style"]

type
  Node* = object
    tag*: string
    attrs*: Table[string, string]
    text*: string
    parent*: int
    children*: seq[int]

  Document* = object
    url*: string
    nodes*: seq[Node]
    root*: int

proc attr*(node: Node, name: string): string =
  node.attrs.getOrDefault(name, "")

proc has*(node: Node, name: string): bool =
  node.attrs.hasKey(name)

proc decodeHtmlEntities*(s: string): string =
  var i = 0
  var res = ""
  while i < s.len:
    if s[i] == '&':
      let semi = s.find(';', i)
      if semi != -1 and semi - i <= 10:
        let entity = s[i+1 ..< semi].toLowerAscii()
        case entity
        of "amp": res.add('&'); i = semi + 1; continue
        of "lt": res.add('<'); i = semi + 1; continue
        of "gt": res.add('>'); i = semi + 1; continue
        of "quot": res.add('"'); i = semi + 1; continue
        of "apos": res.add('\''); i = semi + 1; continue
        of "nbsp": res.add(' '); i = semi + 1; continue
        else:
          if entity.startsWith("#x"):
            var code = 0
            if parseHex(entity[2..^1], code) > 0 and code > 0:
              res.add(Rune(code).toUTF8())
              i = semi + 1
              continue
          elif entity.startsWith("#"):
            var code = 0
            if parseInt(entity[1..^1], code) > 0 and code > 0:
              res.add(Rune(code).toUTF8())
              i = semi + 1
              continue
    res.add(s[i])
    inc i
  res

proc parseHtmlDocument*(html: string, url: string = ""): Document =
  var doc = Document(url: url, nodes: @[], root: 0)
  # Root node #document
  doc.nodes.add(Node(tag: "#document", attrs: initTable[string, string](), text: "", parent: -1, children: @[]))
  
  var stack: seq[int] = @[0]
  var i = 0
  let n = html.len

  proc addTextNode(text: string) =
    if text.len == 0 or stack.len == 0: return
    let currentParent = stack[^1]
    let nodeIdx = doc.nodes.len
    doc.nodes.add(Node(tag: "#text", attrs: initTable[string, string](), text: text, parent: currentParent, children: @[]))
    doc.nodes[currentParent].children.add(nodeIdx)

  while i < n:
    if html[i] == '<':
      # Comment or doctype
      if i + 3 < n and html[i .. i+3] == "<!--":
        let endComment = html.find("-->", i + 4)
        if endComment != -1:
          i = endComment + 3
        else:
          i = n
        continue

      if i + 1 < n and html[i+1] == '!':
        let closeTag = html.find('>', i + 2)
        if closeTag != -1:
          i = closeTag + 1
        else:
          i = n
        continue

      # Closing tag
      if i + 1 < n and html[i+1] == '/':
        let closeTag = html.find('>', i + 2)
        if closeTag != -1:
          let rawTag = html[i+2 ..< closeTag].strip().toLowerAscii()
          # Pop stack until we find matching tag
          var foundIdx = -1
          for sIdx in countdown(stack.len - 1, 1):
            if doc.nodes[stack[sIdx]].tag == rawTag:
              foundIdx = sIdx
              break
          if foundIdx != -1:
            stack.setLen(foundIdx)
          i = closeTag + 1
        else:
          i = n
        continue

      # Opening tag or self-closing tag
      let tagStart = i + 1
      var tagEnd = tagStart
      while tagEnd < n and html[tagEnd] notin {' ', '\t', '\r', '\n', '/', '>'}:
        inc tagEnd

      let tagName = html[tagStart ..< tagEnd].toLowerAscii()
      if tagName.len == 0:
        inc i
        continue

      # Parse attributes
      var attrs = initTable[string, string]()
      var p = tagEnd
      var isSelfClosing = false

      while p < n:
        while p < n and html[p] in {' ', '\t', '\r', '\n'}: inc p
        if p >= n: break
        if html[p] == '>':
          inc p
          break
        if html[p] == '/' and p + 1 < n and html[p+1] == '>':
          isSelfClosing = true
          p += 2
          break

        # Attribute name
        var attrNameStart = p
        while p < n and html[p] notin {'=', ' ', '\t', '\r', '\n', '/', '>'}:
          inc p
        let attrName = html[attrNameStart ..< p].toLowerAscii()

        while p < n and html[p] in {' ', '\t', '\r', '\n'}: inc p
        var attrVal = ""
        if p < n and html[p] == '=':
          inc p
          while p < n and html[p] in {' ', '\t', '\r', '\n'}: inc p
          if p < n:
            if html[p] in {'"', '\''}:
              let quote = html[p]
              inc p
              let valStart = p
              while p < n and html[p] != quote:
                inc p
              attrVal = decodeHtmlEntities(html[valStart ..< p])
              if p < n and html[p] == quote:
                inc p
            else:
              let valStart = p
              while p < n and html[p] notin {' ', '\t', '\r', '\n', '>'}:
                inc p
              attrVal = decodeHtmlEntities(html[valStart ..< p])
        if attrName.len > 0:
          attrs[attrName] = attrVal

      let currentParent = stack[^1]
      let nodeIdx = doc.nodes.len
      doc.nodes.add(Node(tag: tagName, attrs: attrs, text: "", parent: currentParent, children: @[]))
      doc.nodes[currentParent].children.add(nodeIdx)

      let isVoid = isSelfClosing or (tagName in VoidTags)
      if not isVoid:
        stack.add(nodeIdx)
        # If script or style, read until closing tag
        if tagName in RawTextTags:
          let closeMarker = "</" & tagName
          let endIdx = html.toLowerAscii().find(closeMarker, p)
          if endIdx != -1:
            let rawContent = html[p ..< endIdx]
            doc.nodes[nodeIdx].text = rawContent
            let closeTag = html.find('>', endIdx + closeMarker.len)
            if closeTag != -1:
              p = closeTag + 1
            else:
              p = endIdx + closeMarker.len
            discard stack.pop()
          else:
            doc.nodes[nodeIdx].text = html[p .. ^1]
            p = n
            discard stack.pop()

      i = p
    else:
      # Text content
      let textStart = i
      while i < n and html[i] != '<':
        inc i
      let rawText = html[textStart ..< i]
      addTextNode(decodeHtmlEntities(rawText))

  doc
