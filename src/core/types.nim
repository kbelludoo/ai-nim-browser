import std/[options]

type
  Heading* = object
    level*: int
    text*: string

  Link* = object
    reference*: string
    label*: string
    url*: string

  Button* = object
    reference*: string
    id*: string
    label*: string
    kind*: string
    name*: string
    value*: string
    disabled*: bool
    formRef*: Option[string]

  Choice* = object
    value*: string
    label*: string
    selected*: bool
    disabled*: bool

  Field* = object
    reference*: string
    id*: string
    name*: string
    kind*: string
    value*: string
    label*: string
    disabled*: bool
    readonly*: bool
    checked*: bool
    multiple*: bool
    required*: bool
    pattern*: string
    options*: seq[Choice]

  Form* = object
    reference*: string
    action*: string
    `method`*: string
    enctype*: string
    submitRef*: Option[string]
    submitLabel*: string
    novalidate*: bool
    fields*: seq[Field]

  Page* = object
    url*: string
    title*: string
    headings*: seq[Heading]
    links*: seq[Link]
    buttons*: seq[Button]
    inputs*: seq[Field]
    forms*: seq[Form]
    text*: string

  ActionRef* = object
    id*: string
    label*: string

  SemanticElement* = object
    tag*: string
    role*: Option[string]
    name*: Option[string]
    text*: Option[string]
    href*: Option[string]
    action*: Option[ActionRef]

  SemanticSnapshot* = object
    url*: string
    title*: string
    elements*: seq[SemanticElement]

proc newActionRef*(id: string, label: string): Option[ActionRef] =
  if id.len == 0 or label.len == 0:
    return none(ActionRef)
  var cleanId = ""
  for c in id:
    if c notin {' ', '\t', '\r', '\n'}: cleanId.add(c)
  if cleanId.len == 0:
    return none(ActionRef)
  var cleanLabel = ""
  for c in label:
    if c notin {' ', '\t', '\r', '\n'}: cleanLabel.add(c)
  if cleanLabel.len == 0:
    return none(ActionRef)
  some(ActionRef(id: id, label: label))

proc accessibleName*(el: SemanticElement): Option[string] =
  if el.name.isSome and el.name.get.len > 0:
    return el.name
  if el.text.isSome and el.text.get.len > 0:
    return el.text
  none(string)
