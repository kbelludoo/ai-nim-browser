import std/[os, json, strformat, strutils, options, algorithm]
import ../src/core/[types, dom]

type
  HeadingGolden = object
    level: int
    text: string

  LinkGolden = object
    reference: string
    label: string
    url: string

  ButtonGolden = object
    reference: string
    label: string
    kind: string
    disabled: bool
    form_ref: Option[string]

  FieldGolden = object
    reference: string
    name: string
    kind: string
    label: Option[string]

  FormGolden = object
    reference: string
    action: string
    `method`: string
    enctype: string
    submit_ref: Option[string]
    submit_label: Option[string]
    fields: seq[FieldGolden]

  Golden = object
    fixture: string
    url: string
    title: string
    headings: seq[HeadingGolden]
    links: seq[LinkGolden]
    buttons: seq[ButtonGolden]
    inputs: seq[FieldGolden]
    forms: seq[FormGolden]

proc parseGolden(jsonNode: JsonNode): Golden =
  result.fixture = jsonNode["fixture"].getStr()
  result.url = jsonNode["url"].getStr()
  result.title = jsonNode["title"].getStr()
  
  if jsonNode.hasKey("headings"):
    for h in jsonNode["headings"]:
      result.headings.add(HeadingGolden(level: h["level"].getInt(), text: h["text"].getStr()))

  if jsonNode.hasKey("links"):
    for l in jsonNode["links"]:
      result.links.add(LinkGolden(reference: l["ref"].getStr(), label: l["label"].getStr(), url: l["url"].getStr()))

  if jsonNode.hasKey("buttons"):
    for b in jsonNode["buttons"]:
      var formRef: Option[string] = none(string)
      if b.hasKey("form_ref"):
        formRef = some(b["form_ref"].getStr())
      let k = if b.hasKey("type"): b["type"].getStr() else: "button"
      let d = if b.hasKey("disabled"): b["disabled"].getBool() else: false
      result.buttons.add(ButtonGolden(
        reference: b["ref"].getStr(),
        label: b["label"].getStr(),
        kind: k,
        disabled: d,
        form_ref: formRef
      ))

  if jsonNode.hasKey("inputs"):
    for inp in jsonNode["inputs"]:
      let name = if inp.hasKey("name"): inp["name"].getStr() else: ""
      let k = if inp.hasKey("type"): inp["type"].getStr() else: "text"
      var label: Option[string] = none(string)
      if inp.hasKey("label") and inp["label"].getStr().len > 0:
        label = some(inp["label"].getStr())
      result.inputs.add(FieldGolden(reference: inp["ref"].getStr(), name: name, kind: k, label: label))

  if jsonNode.hasKey("forms"):
    for f in jsonNode["forms"]:
      var subRef: Option[string] = none(string)
      if f.hasKey("submit_ref"): subRef = some(f["submit_ref"].getStr())
      var subLbl: Option[string] = none(string)
      if f.hasKey("submit_label") and f["submit_label"].getStr().len > 0:
        subLbl = some(f["submit_label"].getStr())
      var fields: seq[FieldGolden] = @[]
      if f.hasKey("fields"):
        for fld in f["fields"]:
          let name = if fld.hasKey("name"): fld["name"].getStr() else: ""
          let k = if fld.hasKey("type"): fld["type"].getStr() else: "text"
          var label: Option[string] = none(string)
          if fld.hasKey("label") and fld["label"].getStr().len > 0:
            label = some(fld["label"].getStr())
          fields.add(FieldGolden(reference: fld["ref"].getStr(), name: name, kind: k, label: label))
      result.forms.add(FormGolden(
        reference: f["ref"].getStr(),
        action: f["action"].getStr(),
        `method`: f["method"].getStr(),
        enctype: f["enctype"].getStr(),
        submit_ref: subRef,
        submit_label: subLbl,
        fields: fields
      ))

proc compareLen(label: string, expected: int, actual: int, diffs: var seq[string]) =
  if expected != actual:
    diffs.add(&"{label} {actual} != {expected}")

proc present(s: string): Option[string] =
  if s.len == 0: none(string) else: some(s)

proc compare(golden: Golden, page: Page): seq[string] =
  var diffs: seq[string] = @[]

  if page.title != golden.title:
    diffs.add(&"title {page.title.repr} != {golden.title.repr}")

  compareLen("headings", golden.headings.len, page.headings.len, diffs)
  for index, expected in golden.headings:
    if index < page.headings.len:
      let actual = page.headings[index]
      if actual.level != expected.level or actual.text != expected.text:
        diffs.add(&"h{index} {actual.text.repr}:{actual.level} != {expected.text.repr}:{expected.level}")

  compareLen("links", golden.links.len, page.links.len, diffs)
  for index, expected in golden.links:
    if index < page.links.len:
      let actual = page.links[index]
      if actual.reference != expected.reference or actual.label != expected.label or actual.url != expected.url:
        diffs.add(&"link{index} ({actual.reference} {actual.label.repr} {actual.url}) != ({expected.reference} {expected.label.repr} {expected.url})")

  compareLen("buttons", golden.buttons.len, page.buttons.len, diffs)
  for index, expected in golden.buttons:
    if index < page.buttons.len:
      let actual = page.buttons[index]
      if actual.reference != expected.reference or
         actual.label != expected.label or
         actual.kind != expected.kind or
         actual.disabled != expected.disabled or
         actual.formRef != expected.form_ref:
        diffs.add(&"button{index} ({actual.reference} {actual.label.repr} {actual.kind} disabled={actual.disabled} form_ref={actual.formRef}) != ({expected.reference} {expected.label.repr} {expected.kind} disabled={expected.disabled} form_ref={expected.form_ref})")

  compareLen("inputs", golden.inputs.len, page.inputs.len, diffs)
  for index, expected in golden.inputs:
    if index < page.inputs.len:
      let actual = page.inputs[index]
      if actual.reference != expected.reference or
         actual.name != expected.name or
         actual.kind != expected.kind or
         present(actual.label) != expected.label:
        diffs.add(&"input{index} ({actual.reference} {actual.label.repr} {actual.kind}) != ({expected.reference} {expected.label} {expected.kind})")

  compareLen("forms", golden.forms.len, page.forms.len, diffs)
  for index, expected in golden.forms:
    if index < page.forms.len:
      let actual = page.forms[index]
      if actual.reference != expected.reference or
         actual.action != expected.action or
         actual.`method` != expected.`method` or
         actual.enctype != expected.enctype or
         actual.submitRef != expected.submit_ref or
         present(actual.submitLabel) != expected.submit_label:
        diffs.add(&"form{index} ({actual.reference} {actual.`method`} {actual.action} submit={actual.submitRef} {actual.submitLabel.repr}) != ({expected.reference} {expected.`method`} {expected.action} submit={expected.submit_ref} {expected.submit_label})")

      var actualRefs: seq[string] = @[]
      for f in actual.fields: actualRefs.add(f.reference)
      var expectedRefs: seq[string] = @[]
      for f in expected.fields: expectedRefs.add(f.reference)
      if actualRefs != expectedRefs:
        diffs.add(&"form{index} fields {actualRefs} != {expectedRefs}")

  diffs

proc main() =
  let fixturesDir = "parity/fixtures"
  let goldenDir = "parity/golden"

  var goldenFiles: seq[string] = @[]
  for file in walkFiles(goldenDir / "*.json"):
    goldenFiles.add(file)
  goldenFiles.sort()

  if goldenFiles.len == 0:
    echo "No golden files found in ", goldenDir
    quit(1)

  var matched = 0
  var totalDiffs = 0

  for path in goldenFiles:
    let raw = readFile(path)
    let golden = parseGolden(parseJson(raw))
    let htmlPath = fixturesDir / golden.fixture
    let html = readFile(htmlPath)
    let page = parsePage(golden.url, html, 200, 0)

    let diffs = compare(golden, page)
    if diffs.len == 0:
      inc matched
      echo alignLeft(golden.fixture, 16), " match"
    else:
      totalDiffs += diffs.len
      var summary = ""
      if diffs.len > 3:
        summary = ": " & diffs[0 .. 2].join("; ") & "; ..."
      else:
        summary = ": " & diffs.join("; ")
      echo alignLeft(golden.fixture, 16), " ", diffs.len, " diffs", summary

  echo ""
  echo &"{matched}/{goldenFiles.len} fixtures match, {totalDiffs} differences"

  if matched == goldenFiles.len:
    quit(0)
  else:
    quit(1)

when isMainModule:
  main()
