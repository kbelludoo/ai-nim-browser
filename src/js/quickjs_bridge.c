#include "quickjs_bridge.h"
#include "quickjs/quickjs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 256

typedef struct {
    char id[64];
    char tag[32];
    char text[4096];
    char value[1024];
    int modified;
} NodeItem;

struct QJSContext {
    JSRuntime *rt;
    JSContext *ctx;
    char title[512];
    NodeItem nodes[MAX_NODES];
    int node_count;
};

// Console.log
static JSValue js_console_log(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    for (int i = 0; i < argc; i++) {
        const char *str = JS_ToCString(ctx, argv[i]);
        if (str) {
            // output to stdout or keep in buffer
            if (i > 0) printf(" ");
            printf("%s", str);
            JS_FreeCString(ctx, str);
        }
    }
    printf("\n");
    return JS_UNDEFINED;
}

// document.getElementById
static JSValue js_document_get_element_by_id(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NULL;
    const char *id = JS_ToCString(ctx, argv[0]);
    if (!id) return JS_NULL;

    QJSContext *qctx = (QJSContext*)JS_GetContextOpaque(ctx);
    NodeItem *target = NULL;
    for (int i = 0; i < qctx->node_count; i++) {
        if (strcmp(qctx->nodes[i].id, id) == 0) {
            target = &qctx->nodes[i];
            break;
        }
    }
    JS_FreeCString(ctx, id);

    if (!target) return JS_NULL;

    JSValue obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "id", JS_NewString(ctx, target->id));
    JS_SetPropertyStr(ctx, obj, "tagName", JS_NewString(ctx, target->tag));
    JS_SetPropertyStr(ctx, obj, "textContent", JS_NewString(ctx, target->text));
    JS_SetPropertyStr(ctx, obj, "innerText", JS_NewString(ctx, target->text));
    JS_SetPropertyStr(ctx, obj, "value", JS_NewString(ctx, target->value));
    return obj;
}

QJSContext* qjs_create(void) {
    JSRuntime *rt = JS_NewRuntime();
    if (!rt) return NULL;

    JSContext *ctx = JS_NewContext(rt);
    if (!ctx) {
        JS_FreeRuntime(rt);
        return NULL;
    }

    QJSContext *qctx = (QJSContext*)calloc(1, sizeof(QJSContext));
    qctx->rt = rt;
    qctx->ctx = ctx;
    JS_SetContextOpaque(ctx, qctx);

    JSValue global = JS_GetGlobalObject(ctx);

    // window & globalThis
    JS_SetPropertyStr(ctx, global, "window", JS_DupValue(ctx, global));
    JS_SetPropertyStr(ctx, global, "self", JS_DupValue(ctx, global));

    // console
    JSValue console = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, console, "log", JS_NewCFunction(ctx, js_console_log, "log", 1));
    JS_SetPropertyStr(ctx, console, "warn", JS_NewCFunction(ctx, js_console_log, "warn", 1));
    JS_SetPropertyStr(ctx, console, "error", JS_NewCFunction(ctx, js_console_log, "error", 1));
    JS_SetPropertyStr(ctx, global, "console", console);

    // document
    JSValue doc = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, doc, "getElementById", JS_NewCFunction(ctx, js_document_get_element_by_id, "getElementById", 1));
    JS_SetPropertyStr(ctx, global, "document", doc);

    JS_FreeValue(ctx, global);

    // Base DOM Shim script
    const char *shim = 
        "document.createElement = function(tag) {\n"
        "  return { tagName: tag, textContent: '', appendChild: function(){} };\n"
        "};\n"
        "document.addEventListener = function(evt, fn) {};\n"
        "window.addEventListener = function(evt, fn) {};\n"
        "window.setTimeout = function(fn, ms) { try { fn(); } catch(e){} return 1; };\n";

    JSValue shimVal = JS_Eval(ctx, shim, strlen(shim), "<shim>", JS_EVAL_TYPE_GLOBAL);
    JS_FreeValue(ctx, shimVal);

    return qctx;
}

void qjs_destroy(QJSContext *ctx) {
    if (!ctx) return;
    if (ctx->ctx) JS_FreeContext(ctx->ctx);
    if (ctx->rt) JS_FreeRuntime(ctx->rt);
    free(ctx);
}

void qjs_set_document_title(QJSContext *ctx, const char *title) {
    if (!ctx) return;
    strncpy(ctx->title, title ? title : "", sizeof(ctx->title) - 1);
    
    JSValue global = JS_GetGlobalObject(ctx->ctx);
    JSValue doc = JS_GetPropertyStr(ctx->ctx, global, "document");
    JS_SetPropertyStr(ctx->ctx, doc, "title", JS_NewString(ctx->ctx, ctx->title));
    JS_FreeValue(ctx->ctx, doc);
    JS_FreeValue(ctx->ctx, global);
}

const char* qjs_get_document_title(QJSContext *ctx) {
    if (!ctx) return "";
    JSValue global = JS_GetGlobalObject(ctx->ctx);
    JSValue doc = JS_GetPropertyStr(ctx->ctx, global, "document");
    JSValue titleVal = JS_GetPropertyStr(ctx->ctx, doc, "title");
    const char *str = JS_ToCString(ctx->ctx, titleVal);
    if (str) {
        strncpy(ctx->title, str, sizeof(ctx->title) - 1);
        JS_FreeCString(ctx->ctx, str);
    }
    JS_FreeValue(ctx->ctx, titleVal);
    JS_FreeValue(ctx->ctx, doc);
    JS_FreeValue(ctx->ctx, global);
    return ctx->title;
}

void qjs_register_node(QJSContext *ctx, const char *id, const char *tag, const char *text, const char *val) {
    if (!ctx || ctx->node_count >= MAX_NODES) return;
    NodeItem *n = &ctx->nodes[ctx->node_count++];
    strncpy(n->id, id ? id : "", sizeof(n->id) - 1);
    strncpy(n->tag, tag ? tag : "div", sizeof(n->tag) - 1);
    strncpy(n->text, text ? text : "", sizeof(n->text) - 1);
    strncpy(n->value, val ? val : "", sizeof(n->value) - 1);
    n->modified = 0;
}

const char* qjs_get_node_text(QJSContext *ctx, const char *id) {
    if (!ctx) return NULL;
    for (int i = 0; i < ctx->node_count; i++) {
        if (strcmp(ctx->nodes[i].id, id) == 0) {
            return ctx->nodes[i].text;
        }
    }
    return NULL;
}

char* qjs_eval(QJSContext *ctx, const char *code, int *out_is_error) {
    if (!ctx || !code) {
        if (out_is_error) *out_is_error = 1;
        return strdup("Invalid context or code");
    }

    JSValue val = JS_Eval(ctx->ctx, code, strlen(code), "<eval>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(val)) {
        if (out_is_error) *out_is_error = 1;
        JSValue exc = JS_GetException(ctx->ctx);
        const char *str = JS_ToCString(ctx->ctx, exc);
        char *res = strdup(str ? str : "Exception in JS");
        JS_FreeCString(ctx->ctx, str);
        JS_FreeValue(ctx->ctx, exc);
        JS_FreeValue(ctx->ctx, val);
        return res;
    }

    if (out_is_error) *out_is_error = 0;
    const char *str = JS_ToCString(ctx->ctx, val);
    char *res = strdup(str ? str : "");
    JS_FreeCString(ctx->ctx, str);
    JS_FreeValue(ctx->ctx, val);
    return res;
}
