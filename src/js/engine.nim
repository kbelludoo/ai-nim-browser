import std/[os]

const currentDir = currentSourcePath().parentDir()

{.passC: "-I" & currentDir & " -I" & currentDir & "/quickjs -DCONFIG_VERSION=\\\"2021\\\" -D_GNU_SOURCE".}
{.compile: "quickjs/cutils.c".}
{.compile: "quickjs/libregexp.c".}
{.compile: "quickjs/libunicode.c".}
{.compile: "quickjs/quickjs.c".}
{.compile: "quickjs_bridge.c".}

type
  QJSContext = pointer

proc qjs_create(): QJSContext {.importc: "qjs_create", header: "quickjs_bridge.h".}
proc qjs_destroy(ctx: QJSContext) {.importc: "qjs_destroy", header: "quickjs_bridge.h".}
proc qjs_set_document_title(ctx: QJSContext, title: cstring) {.importc: "qjs_set_document_title", header: "quickjs_bridge.h".}
proc qjs_get_document_title(ctx: QJSContext): cstring {.importc: "qjs_get_document_title", header: "quickjs_bridge.h".}
proc qjs_register_node(ctx: QJSContext, id: cstring, tag: cstring, text: cstring, val: cstring) {.importc: "qjs_register_node", header: "quickjs_bridge.h".}
proc qjs_eval(ctx: QJSContext, code: cstring, out_is_error: ptr cint): cstring {.importc: "qjs_eval", header: "quickjs_bridge.h".}

type
  JsEngine* = ref object
    ctx: QJSContext

proc newJsEngine*(): JsEngine =
  let c = qjs_create()
  if c == nil:
    raise newException(ValueError, "Failed to initialize QuickJS engine")
  JsEngine(ctx: c)

proc close*(js: JsEngine) =
  if js.ctx != nil:
    qjs_destroy(js.ctx)
    js.ctx = nil

proc setDocumentTitle*(js: JsEngine, title: string) =
  qjs_set_document_title(js.ctx, title.cstring)

proc getDocumentTitle*(js: JsEngine): string =
  $qjs_get_document_title(js.ctx)

proc registerNode*(js: JsEngine, id: string, tag: string, text: string, val: string = "") =
  qjs_register_node(js.ctx, id.cstring, tag.cstring, text.cstring, val.cstring)

proc eval*(js: JsEngine, code: string): (string, bool) =
  var isErr: cint = 0
  let res = qjs_eval(js.ctx, code.cstring, addr isErr)
  let s = if res != nil: $res else: ""
  (s, isErr != 0)

when isMainModule:
  let engine = newJsEngine()
  engine.setDocumentTitle("Initial Title")
  echo "Before script title: ", engine.getDocumentTitle()

  let script = """
    console.log("Hello from inside QuickJS!");
    document.title = "Hydrated Dynamic SPA Title";
    var sum = 0;
    for (var i = 1; i <= 10; i++) { sum += i; }
    sum;
  """
  let (output, err) = engine.eval(script)
  echo "Script Eval Output: ", output, " (Error: ", err, ")"
  echo "After script title: ", engine.getDocumentTitle()
  engine.close()
