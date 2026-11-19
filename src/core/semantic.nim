import std/[options, strutils]
import types, dom

proc parseSemanticHtml*(url: string, html: string): SemanticSnapshot =
  let page = parsePage(url, html, 200, 0)
  var elements: seq[SemanticElement] = @[]

  for link in page.links:
    var el = SemanticElement(
      tag: "a",
      role: none(string),
      name: some(link.label),
      text: none(string),
      href: some(link.url),
      action: newActionRef(link.reference, link.label)
    )
    elements.add(el)

  for btn in page.buttons:
    var el = SemanticElement(
      tag: "button",
      role: none(string),
      name: some(btn.label),
      text: some(btn.label),
      href: none(string),
      action: newActionRef(btn.reference, btn.label)
    )
    elements.add(el)

  for fld in page.inputs:
    let tag = case fld.kind
    of "textarea": "textarea"
    of "select": "select"
    of "contenteditable": "div"
    else: "input"

    var actionOpt: Option[ActionRef] = none(ActionRef)
    var nameOpt: Option[string] = none(string)
    if fld.label.len > 0:
      nameOpt = some(fld.label)
      actionOpt = newActionRef(fld.reference, fld.label)

    var textOpt = if fld.value.len > 0: some(fld.value) else: none(string)

    elements.add(SemanticElement(
      tag: tag,
      role: none(string),
      name: nameOpt,
      text: textOpt,
      href: none(string),
      action: actionOpt
    ))

  for form in page.forms:
    for fld in form.fields:
      let tag = case fld.kind
      of "textarea": "textarea"
      of "select": "select"
      of "contenteditable": "div"
      else: "input"

      var actionOpt: Option[ActionRef] = none(ActionRef)
      var nameOpt: Option[string] = none(string)
      if fld.label.len > 0:
        nameOpt = some(fld.label)
        actionOpt = newActionRef(fld.reference, fld.label)

      var textOpt = if fld.value.len > 0: some(fld.value) else: none(string)

      elements.add(SemanticElement(
        tag: tag,
        role: none(string),
        name: nameOpt,
        text: textOpt,
        href: none(string),
        action: actionOpt
      ))

  SemanticSnapshot(
    url: url,
    title: page.title,
    elements: elements
  )

proc findAction*(snap: SemanticSnapshot, id: string): Option[SemanticElement] =
  for el in snap.elements:
    if el.action.isSome and el.action.get.id == id:
      return some(el)
  none(SemanticElement)
