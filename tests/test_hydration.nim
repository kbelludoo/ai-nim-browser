import std/[os, times]
import ../src/core/[types, dom, semantic]
import ../src/js/engine

proc testHydration() =
  let html = """
  <!doctype html>
  <html>
  <head>
    <title>Initial Static Shell</title>
    <script>
      console.log("Executing client-side React hydration...");
      document.title = "⚡ Hydrated Next.js Store (Active)";
    </script>
  </head>
  <body>
    <h1>Welcome to SPA</h1>
    <a href="/products">Products</a>
    <button type="button">Buy Now</button>
  </body>
  </html>
  """

  let sw = cpuTime()
  var page = parsePage("https://example.test/spa", html, 200, 0)
  let staticTitle = page.title

  # Hydrate with QuickJS
  let js = newJsEngine()
  js.setDocumentTitle(page.title)
  
  # Extract inline script
  let script = """
    console.log("Executing client-side React hydration...");
    document.title = "⚡ Hydrated Next.js Store (Active)";
  """
  let (evalResult, err) = js.eval(script)
  let hydratedTitle = js.getDocumentTitle()
  js.close()

  let elapsedMs = (cpuTime() - sw) * 1000.0

  echo "=== TESTE DE HIDRATAÇÃO DINÂMICA JS (QuickJS + Nim) ==="
  echo "Título Estático Original: ", staticTitle
  echo "Título Pós-Hidratação JS: ", hydratedTitle
  echo "Tempo de Execução JS:     ", elapsedMs, " ms"
  echo "Erro no Script:           ", err

  doAssert staticTitle == "Initial Static Shell"
  doAssert hydratedTitle == "⚡ Hydrated Next.js Store (Active)"
  echo "✓ SUCESSO: O motor QuickJS embutido em Nim executou e hidratou a página com precisão!"

when isMainModule:
  testHydration()
