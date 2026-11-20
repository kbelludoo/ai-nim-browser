#ifndef QUICKJS_BRIDGE_H
#define QUICKJS_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QJSContext QJSContext;

// Create a new QuickJS runtime and context with standard browser shims
QJSContext* qjs_create(void);

// Destroy the context and its runtime
void qjs_destroy(QJSContext *ctx);

// Set document title in the JS environment
void qjs_set_document_title(QJSContext *ctx, const char *title);

// Get current document title after script execution
const char* qjs_get_document_title(QJSContext *ctx);

// Register a DOM node into document.getElementById() lookup
void qjs_register_node(QJSContext *ctx, const char *id, const char *tag, const char *text, const char *val);

// Get modified text for a registered node (or NULL if unchanged)
const char* qjs_get_node_text(QJSContext *ctx, const char *id);

// Evaluate JavaScript code and return result string (free with free())
char* qjs_eval(QJSContext *ctx, const char *code, int *out_is_error);

#ifdef __cplusplus
}
#endif

#endif // QUICKJS_BRIDGE_H
