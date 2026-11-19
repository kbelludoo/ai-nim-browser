import std/[strutils, tables, options, uri]
import std/unicode except splitWhitespace
import types, html_parser

const HiddenTags* = [
  "script", "style", "noscript", "template", "svg", "head", "title"
]

const ControlSkipTags* = [
  "template", "script", "style", "noscript", "head", "datalist"
]

const NonControlTags* = [
  "#text", "#document", "input", "textarea", "select", "button"
]

const InputTypes* = [
  "hidden", "text", "search", "tel", "url", "email", "password",
  "date", "month", "week", "time", "datetime-local", "number",
  "range", "color", "checkbox", "radio", "file", "submit", "image", "reset"
]

const TextLikeTypes* = [
  "contenteditable", "textarea", "text", "search", "tel", "url",
  "email", "password", "date", "month", "week"
]

type
  TextBuilder* = object
    outStr*: string
    runes*: int
    limit*: int
    truncated*: bool

proc newTextBuilder*(limit: int = 0): TextBuilder =
  TextBuilder(outStr: "", runes: 0, limit: limit, truncated: false)

proc isDone*(tb: TextBuilder): bool = tb.truncated
proc isEmpty*(tb: TextBuilder): bool = tb.outStr.len == 0

proc writeChar(tb: var TextBuilder, c: Rune): bool =
  if tb.limit > 0 and tb.runes >= tb.limit:
    tb.truncated = true
    return false
  tb.outStr.add(c.toUTF8())
  inc tb.runes
  true

proc add*(tb: var TextBuilder, input: string) =
  if tb.truncated: return
  var pendingSpace = tb.outStr.len > 0
  for r in input.runes:
    let s = r.toUTF8()
    if s.len == 1 and s[0] in {' ', '\t', '\r', '\n'}:
      pendingSpace = tb.outStr.len > 0
      continue
    if pendingSpace:
      if not tb.writeChar(Rune(32)): # ' '
        return
      pendingSpace = false
    if not tb.writeChar(r):
      return

proc finish*(tb: var TextBuilder): string =
  tb.outStr

proc normalize*(s: string): string =
  s.splitWhitespace().join(" ")

proc resolveUrl*(baseStr: string, refStr: string): string =
  let refTrimmed = refStr.strip()
  if refTrimmed.len == 0 or baseStr.len == 0:
    return ""

  try:
    let baseUri = parseUri(baseStr)
    let refUri = parseUri(refTrimmed)
    let combined = baseUri.combine(refUri)
    if combined.scheme.toLowerAscii() in ["http", "https"]:
      return $combined
    else:
      return ""
  except:
    return ""

# Document helper methods
proc node*(doc: Document, idx: int): Node =
  doc.nodes[idx]

proc tag*(doc: Document, idx: int): string =
  doc.nodes[idx].tag

proc prop*(doc: Document, idx: int, name: string): string =
  doc.nodes[idx].attrs.getOrDefault(name, "")

proc has*(doc: Document, idx: int, name: string): bool =
  doc.nodes[idx].attrs.hasKey(name)

proc hidden*(doc: Document, idx: int): bool =
  let t = doc.tag(idx)
  for ht in HiddenTags:
    if t == ht: return true
  if doc.has(idx, "hidden"):
    return true
  if doc.prop(idx, "aria-hidden").toLowerAscii() == "true":
    return true
  let style = doc.prop(idx, "style").toLowerAscii().replace(" ", "")
  if style.contains("display:none") or style.contains("visibility:hidden"):
    return true
  false

proc visible*(doc: Document, idx: int): bool =
  var cur = idx
  while cur != -1:
    if doc.hidden(cur):
      return false
    cur = doc.nodes[cur].parent
  true

proc contentEditable*(doc: Document, idx: int): bool =
  var cur = idx
  while cur != -1:
    if doc.has(cur, "contenteditable"):
      let val = doc.prop(cur, "contenteditable").toLowerAscii()
      case val
      of "", "true", "plaintext-only": return true
      of "false": return false
      else: discard
    cur = doc.nodes[cur].parent
  false

proc hasRole*(doc: Document, idx: int, role: string): bool =
  let roles = doc.prop(idx, "role").splitWhitespace()
  for r in roles:
    if r.toLowerAscii() == role.toLowerAscii():
      return true
  false

proc editableControl*(doc: Document, idx: int): bool =
  let t = doc.tag(idx)
  for nct in NonControlTags:
    if t == nct: return false
  if doc.hasRole(idx, "textbox"):
    return true
  if not doc.contentEditable(idx):
    return false
  let parent = doc.nodes[idx].parent
  if parent == -1 or not doc.contentEditable(parent):
    return true
  false

proc genericButton*(doc: Document, idx: int): bool =
  let t = doc.tag(idx)
  for nct in NonControlTags:
    if t == nct: return false
  if doc.hasRole(idx, "button") or (t == "a" and not doc.has(idx, "href")):
    return true
  false

proc controlType*(doc: Document, idx: int): string =
  if doc.editableControl(idx):
    return "contenteditable"
  if doc.genericButton(idx):
    return "button"
  let t = doc.tag(idx)
  if t != "input" and t != "button":
    return t
  let kind = doc.prop(idx, "type").toLowerAscii()
  if t == "button":
    if kind in ["button", "reset"]:
      return kind
    return "submit"
  if kind in InputTypes or kind == "button":
    return kind
  "text"

proc isDescendant*(doc: Document, idx: int, ancestor: int): bool =
  var cur = idx
  while cur != -1:
    if cur == ancestor: return true
    cur = doc.nodes[cur].parent
  false

proc disabled*(doc: Document, idx: int): bool =
  if doc.has(idx, "disabled"):
    return true
  var cur = idx
  while cur != -1:
    if doc.prop(cur, "aria-disabled").strip().toLowerAscii() == "true":
      return true
    cur = doc.nodes[cur].parent

  var parent = doc.nodes[idx].parent
  while parent != -1:
    if doc.tag(parent) == "fieldset" and doc.has(parent, "disabled"):
      var legendIdx = -1
      for ch in doc.nodes[parent].children:
        if doc.tag(ch) == "legend":
          legendIdx = ch
          break
      if legendIdx == -1 or not doc.isDescendant(idx, legendIdx):
        return true
    parent = doc.nodes[parent].parent
  false

proc readOnly*(doc: Document, idx: int): bool =
  if doc.editableControl(idx) and not doc.contentEditable(idx):
    return true
  var cur = idx
  while cur != -1:
    if doc.prop(cur, "aria-readonly").strip().toLowerAscii() == "true":
      return true
    cur = doc.nodes[cur].parent
  if not doc.has(idx, "readonly"):
    return false
  let ct = doc.controlType(idx)
  ct in TextLikeTypes

proc formOwner*(doc: Document, idx: int, ids: Table[string, int], markers: Table[string, int]): Option[int] =
  let marker = doc.prop(idx, "data-aigobrowser-form")
  if marker.len > 0 and markers.hasKey(marker):
    return some(markers[marker])
  let formId = doc.prop(idx, "form")
  if formId.len > 0 and ids.hasKey(formId):
    let owner = ids[formId]
    if doc.tag(owner) == "form":
      return some(owner)
  var parent = doc.nodes[idx].parent
  while parent != -1:
    if doc.tag(parent) == "form":
      return some(parent)
    parent = doc.nodes[parent].parent
  none(int)

proc rawText*(doc: Document, idx: int, limit: int = 0): string =
  var outStr = ""
  var stack = @[idx]
  while stack.len > 0:
    let cur = stack.pop()
    if limit > 0 and outStr.len > limit:
      break
    let n = doc.nodes[cur]
    if n.tag == "#text":
      outStr.add(n.text)
    for chIdx in countdown(n.children.len - 1, 0):
      stack.add(n.children[chIdx])
  outStr

proc collectText*(doc: Document, idx: int, builder: var TextBuilder) =
  if builder.isDone() or doc.hidden(idx):
    return
  let n = doc.nodes[idx]
  if n.tag == "#text":
    builder.add(n.text)
    return
  if n.tag == "img":
    builder.add(doc.prop(idx, "alt"))
  for ch in n.children:
    doc.collectText(ch, builder)
    if builder.isDone():
      return

proc innerText*(doc: Document, idx: int, limit: int = 1200): string =
  if limit == 0 and doc.visible(idx):
    var builder = newTextBuilder(0)
    doc.collectText(idx, builder)
    return builder.finish()
  var builder = newTextBuilder(limit)
  doc.collectText(idx, builder)
  builder.finish()

proc controlLabel*(doc: Document, idx: int, ids: Table[string, int], labels: Table[string, seq[int]]): string =
  let aria = normalize(doc.prop(idx, "aria-label"))
  if aria.len > 0:
    return aria

  var builder = newTextBuilder(512)
  for id in doc.prop(idx, "aria-labelledby").splitWhitespace():
    if ids.hasKey(id):
      builder.add(doc.innerText(ids[id], 512))
  if not builder.isEmpty():
    return builder.finish()

  let elemId = doc.prop(idx, "id")
  if elemId.len > 0 and labels.hasKey(elemId):
    for lblIdx in labels[elemId]:
      builder.add(doc.innerText(lblIdx, 512))
  if not builder.isEmpty():
    return builder.finish()

  var parent = doc.nodes[idx].parent
  while parent != -1:
    if doc.tag(parent) == "label" and not doc.has(parent, "for"):
      builder.add(doc.innerText(parent, 512))
      break
    parent = doc.nodes[parent].parent
  if not builder.isEmpty():
    return builder.finish()

  doc.prop(idx, "placeholder")

proc optionNodes*(doc: Document, idx: int): seq[int] =
  var options: seq[int] = @[]
  var stack = @[idx]
  while stack.len > 0:
    let cur = stack.pop()
    if cur != idx and doc.tag(cur) == "select":
      continue
    if doc.tag(cur) == "option":
      options.add(cur)
      continue
    for chIdx in countdown(doc.nodes[cur].children.len - 1, 0):
      stack.add(doc.nodes[cur].children[chIdx])
  options

proc optionValue*(doc: Document, idx: int): string =
  if doc.has(idx, "value"):
    doc.prop(idx, "value")
  else:
    normalize(doc.rawText(idx, 0))

proc selectState*(doc: Document, idx: int): (seq[Choice], string) =
  let multiple = doc.has(idx, "multiple")
  var choices: seq[Choice] = @[]
  var selectedIdx: Option[int] = none(int)
  var firstEnabled: Option[int] = none(int)

  for opt in doc.optionNodes(idx):
    var optDisabled = doc.has(opt, "disabled")
    var parent = doc.nodes[opt].parent
    while parent != -1 and parent != idx:
      if doc.tag(parent) == "optgroup" and doc.has(parent, "disabled"):
        optDisabled = true
      parent = doc.nodes[parent].parent

    let explicitLabel = doc.prop(opt, "label")
    let label = if explicitLabel.len > 0: explicitLabel else: doc.innerText(opt, 512)
    let isSelected = doc.has(opt, "selected")
    if firstEnabled.isNone and not optDisabled:
      firstEnabled = some(choices.len)
    if isSelected and not multiple:
      if selectedIdx.isSome:
        choices[selectedIdx.get].selected = false
      selectedIdx = some(choices.len)
    choices.add(Choice(
      value: doc.optionValue(opt),
      label: label,
      selected: isSelected,
      disabled: optDisabled
    ))

  if not multiple and selectedIdx.isNone and firstEnabled.isSome:
    var size = 0
    try:
      size = parseInt(doc.prop(idx, "size"))
    except ValueError:
      size = 0
    if size <= 1:
      choices[firstEnabled.get].selected = true

  var val = ""
  for c in choices:
    if c.selected:
      val = c.value
      break
  (choices, val)

proc controlValue*(doc: Document, idx: int): string =
  let t = doc.tag(idx)
  if t == "textarea" or doc.editableControl(idx):
    return doc.rawText(idx, 0)
  if t == "select":
    let (_, val) = doc.selectState(idx)
    return val
  if doc.has(idx, "value"):
    return doc.prop(idx, "value")
  let kind = doc.controlType(idx)
  if kind == "checkbox" or kind == "radio":
    return "on"
  ""

proc walkVisible*(doc: Document, visit: proc(idx: int)) =
  var stack = @[doc.root]
  while stack.len > 0:
    let cur = stack.pop()
    if doc.hidden(cur):
      continue
    visit(cur)
    for chIdx in countdown(doc.nodes[cur].children.len - 1, 0):
      stack.add(doc.nodes[cur].children[chIdx])

proc walkControls*(doc: Document, visit: proc(idx: int)) =
  var stack = @[doc.root]
  while stack.len > 0:
    let cur = stack.pop()
    let t = doc.tag(cur)
    if t in ControlSkipTags:
      continue
    visit(cur)
    for chIdx in countdown(doc.nodes[cur].children.len - 1, 0):
      stack.add(doc.nodes[cur].children[chIdx])

proc findTitle*(doc: Document): string =
  var stack = @[doc.root]
  while stack.len > 0:
    let cur = stack.pop()
    if doc.tag(cur) == "title":
      return normalize(doc.rawText(cur, 4096))
    for chIdx in countdown(doc.nodes[cur].children.len - 1, 0):
      stack.add(doc.nodes[cur].children[chIdx])
  ""

proc hasControls*(doc: Document): bool =
  var stack = @[doc.root]
  while stack.len > 0:
    let cur = stack.pop()
    let t = doc.tag(cur)
    if t in ["form", "input", "select", "textarea", "button"] or
       doc.editableControl(cur) or doc.genericButton(cur):
      return true
    for chIdx in countdown(doc.nodes[cur].children.len - 1, 0):
      stack.add(doc.nodes[cur].children[chIdx])
  false

proc collectForms*(doc: Document): (seq[Form], seq[Button], seq[Field]) =
  var ids = initTable[string, int]()
  var markers = initTable[string, int]()
  var labels = initTable[string, seq[int]]()
  var forms: seq[Form] = @[]
  var formIndexes = initTable[int, int]()

  doc.walkControls(proc(idx: int) =
    let elemId = doc.prop(idx, "id")
    if elemId.len > 0 and not ids.hasKey(elemId):
      ids[elemId] = idx
    if doc.tag(idx) == "label":
      let target = doc.prop(idx, "for")
      if target.len > 0:
        if not labels.hasKey(target):
          labels[target] = @[]
        labels[target].add(idx)
    if doc.tag(idx) != "form":
      return

    let marker = doc.prop(idx, "data-aigobrowser")
    if marker.len > 0:
      markers[marker] = idx

    var formMethod = doc.prop(idx, "method").toUpperAscii()
    if formMethod notin ["POST", "DIALOG"]:
      formMethod = "GET"
    var enctype = doc.prop(idx, "enctype").toLowerAscii()
    if enctype notin ["multipart/form-data", "text/plain"]:
      enctype = "application/x-www-form-urlencoded"

    let rawAction = doc.prop(idx, "action")
    var action = doc.url
    if rawAction.len > 0:
      let resolved = resolveUrl(doc.url, rawAction)
      if resolved.len > 0:
        action = resolved

    formIndexes[idx] = forms.len
    forms.add(Form(
      reference: "f" & $(forms.len + 1),
      action: action,
      `method`: formMethod,
      enctype: enctype,
      submitRef: none(string),
      submitLabel: "Enviar",
      novalidate: doc.has(idx, "novalidate"),
      fields: @[]
    ))
  )

  var buttons: seq[Button] = @[]
  var inputs: seq[Field] = @[]
  var fieldCount = 0
  var radios = initTable[string, (Option[int], int)]()

  doc.walkControls(proc(idx: int) =
    let editable = doc.editableControl(idx)
    let generic = doc.genericButton(idx)
    let t = doc.tag(idx)
    if t notin ["input", "textarea", "select", "button"] and not editable and not generic:
      return
    if (editable or generic) and not doc.visible(idx):
      return

    let owner = doc.formOwner(idx, ids, markers)
    var associated: Option[int] = none(int)
    if owner.isSome and formIndexes.hasKey(owner.get):
      associated = some(formIndexes[owner.get])
    if editable or generic:
      associated = none(int)

    let kind = doc.controlType(idx)

    if t == "button" or kind in ["button", "submit", "reset", "image"]:
      var label = doc.controlLabel(idx, ids, labels)
      if label.len == 0:
        label = doc.innerText(idx, 256)
      if label.len == 0:
        label = doc.prop(idx, "value")
      if label.len == 0:
        label = "(button)"

      var btn = Button(
        reference: "b" & $(buttons.len + 1),
        id: doc.prop(idx, "id"),
        label: label,
        kind: kind,
        name: doc.prop(idx, "name"),
        value: doc.prop(idx, "value"),
        disabled: doc.disabled(idx),
        formRef: none(string)
      )

      if associated.isSome:
        let fIdx = associated.get
        btn.formRef = some(forms[fIdx].reference)
        if kind == "submit" and not btn.disabled and forms[fIdx].submitRef.isNone:
          forms[fIdx].submitRef = some(btn.reference)
          forms[fIdx].submitLabel = btn.label
      buttons.add(btn)
      return

    inc fieldCount
    var fld = Field(
      reference: "i" & $fieldCount,
      id: doc.prop(idx, "id"),
      name: doc.prop(idx, "name"),
      kind: kind,
      value: "",
      label: doc.controlLabel(idx, ids, labels),
      disabled: doc.disabled(idx),
      readonly: doc.readOnly(idx),
      checked: (kind in ["checkbox", "radio"]) and doc.has(idx, "checked"),
      multiple: t == "select" and doc.has(idx, "multiple"),
      required: doc.has(idx, "required"),
      pattern: doc.prop(idx, "pattern"),
      options: @[]
    )

    if t == "select":
      let (options, val) = doc.selectState(idx)
      fld.options = options
      fld.value = val
    else:
      fld.value = doc.controlValue(idx)

    if kind == "radio" and fld.checked and fld.name.len > 0:
      let group = if associated.isSome:
        forms[associated.get].reference & "\0" & fld.name
      else:
        "standalone\0" & fld.name

      if radios.hasKey(group):
        let (prevForm, prevField) = radios[group]
        if prevForm.isSome:
          if prevField < forms[prevForm.get].fields.len:
            forms[prevForm.get].fields[prevField].checked = false
        else:
          if prevField < inputs.len:
            inputs[prevField].checked = false

      let slot = if associated.isSome: forms[associated.get].fields.len else: inputs.len
      radios[group] = (associated, slot)

    if associated.isSome:
      forms[associated.get].fields.add(fld)
    else:
      inputs.add(fld)
  )

  (forms, buttons, inputs)

proc parsePage*(url: string, html: string, status: int = 200, textLimit: int = 0): Page =
  let doc = parseHtmlDocument(html, url)
  var page = Page(
    url: url,
    title: doc.findTitle(),
    headings: @[],
    links: @[],
    buttons: @[],
    inputs: @[],
    forms: @[],
    text: ""
  )

  var textBuilder = newTextBuilder(textLimit)
  doc.walkVisible(proc(idx: int) =
    let n = doc.nodes[idx]
    if n.tag == "#text":
      textBuilder.add(n.text)
      return
    if n.tag == "a" and doc.has(idx, "href"):
      let href = resolveUrl(url, doc.prop(idx, "href"))
      if href.len > 0:
        let aria = doc.prop(idx, "aria-label")
        var label = if aria.len == 0: doc.innerText(idx, 1200) else: aria
        if label.len == 0:
          label = "(link)"
        page.links.add(Link(
          reference: "l" & $(page.links.len + 1),
          label: label,
          url: href
        ))
    if n.tag.len == 2 and n.tag[0] == 'h' and n.tag[1] in {'1' .. '6'}:
      page.headings.add(Heading(
        level: ord(n.tag[1]) - ord('0'),
        text: doc.innerText(idx, 1200)
      ))
  )

  if doc.hasControls():
    let (forms, buttons, inputs) = doc.collectForms()
    page.forms = forms
    page.buttons = buttons
    page.inputs = inputs

  page.text = textBuilder.finish()
  page
