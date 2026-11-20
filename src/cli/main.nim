import std/[os, strutils, syncio, options]
import ../core/[types, dom, semantic, transport, browser]
import ../mcp/server as mcpserver
import ../ui/window as uiwindow

proc main() =
  let args = commandLineParams()

  if args.len > 0 and (args[0] == "--version" or args[0] == "-v"):
    echo "ai-nim-browser v1.1.0 (hybrid: headless + QuickJS + WebView2)"
    quit(0)

  if args.len > 0 and args[0] == "mcp":
    let s = newMcpServer()
    s.serve()
    quit(0)

  if args.len > 0 and args[0] == "ui":
    let target = if args.len > 1: args[1] else: "https://example.com"
    uiwindow.openDesktopBrowser(target)
    quit(0)

  let b = newHttpSnapshotBrowser()
  echo "AI Nim Browser REPL / CLI (Type 'help' or commands: open <url> [--render-js], ui <url>, snapshot, text, mcp, quit)"

  var line: string
  while true:
    stdout.write("> ")
    stdout.flushFile()
    if not readLine(stdin, line):
      break

    let trimmed = line.strip()
    if trimmed.len == 0: continue

    let parts = trimmed.splitWhitespace()
    let cmd = parts[0].toLowerAscii()

    case cmd
    of "quit", "exit":
      break
    of "help":
      echo "Comandos disponíveis:"
      echo "  open <url> [--render-js] - Abre e renderiza a página (com QuickJS se solicitado)"
      echo "  ui [url]                 - Abre a janela gráfica nativa (WebView2/Chromium)"
      echo "  snapshot                 - Mostra o snapshot de acessibilidade e ações"
      echo "  text                     - Extrai o texto limpo da página"
      echo "  click <ref>              - Clica no elemento (#ref ou l*/b*)"
      echo "  fill <ref> <valor>       - Preenche o campo de formulário"
      echo "  back                     - Volta no histórico"
      echo "  forward                  - Avança no histórico"
      echo "  mcp                      - Inicia o servidor MCP sobre stdin/stdout"
      echo "  quit                     - Sai do programa"
    of "ui":
      let target = if parts.len > 1: parts[1] else: "https://example.com"
      uiwindow.openDesktopBrowser(target)
    of "open":
      if parts.len < 2:
        echo "Uso: open <url> [--render-js]"
        continue
      let url = parts[1]
      let renderJs = parts.len > 2 and parts[2] == "--render-js"
      try:
        let snap = b.navigate(url, renderJs = renderJs)
        echo "\n=== ", snap.title, " ==="
        echo "URL: ", snap.url
        echo "Elementos interativos detectados: ", snap.elements.len
        if renderJs:
          echo "(Renderizado e hidratado via motor QuickJS embutido)"
      except Exception as e:
        echo "Erro ao navegar: ", e.msg
    of "snapshot":
      let snapOpt = b.currentSnapshot()
      if snapOpt.isSome:
        let snap = snapOpt.get
        echo "\n# ", snap.title
        echo "URL: ", snap.url, "\n"
        for el in snap.elements:
          let refId = if el.action.isSome: el.action.get.id else: "-"
          let name = if el.accessibleName().isSome: el.accessibleName().get else: "elemento"
          echo "  [", refId, "] ", name
      else:
        echo "Nenhuma página carregada. Use: open <url>"
    of "text":
      let txtOpt = b.currentText()
      if txtOpt.isSome:
        echo "\n=== Texto da Página ===\n"
        echo txtOpt.get
      else:
        echo "Nenhuma página carregada."
    of "click":
      if parts.len < 2:
        echo "Uso: click <ref>"
        continue
      let r = parts[1]
      try:
        discard b.perform(BrowserAction(kind: ActionClick, clickRef: r))
        echo "Clicou em: ", r
      except Exception as e:
        echo "Ação não suportada no modo estático: ", e.msg
    of "fill":
      if parts.len < 3:
        echo "Uso: fill <ref> <valor>"
        continue
      let r = parts[1]
      let val = parts[2 .. ^1].join(" ")
      try:
        discard b.perform(BrowserAction(kind: ActionFill, fillRef: r, fillValue: val))
        echo "Preencheu ", r, " com: ", val
      except Exception as e:
        echo "Ação não suportada no modo estático: ", e.msg
    of "back":
      try:
        let outSnap = b.perform(BrowserAction(kind: ActionBack))
        if outSnap.snapshot.isSome:
          echo "Voltou para: ", outSnap.snapshot.get.url
      except Exception as e:
        echo "Erro: ", e.msg
    of "forward":
      try:
        let outSnap = b.perform(BrowserAction(kind: ActionForward))
        if outSnap.snapshot.isSome:
          echo "Avançou para: ", outSnap.snapshot.get.url
      except Exception as e:
        echo "Erro: ", e.msg
    of "mcp":
      let s = newMcpServer()
      s.serve()
      break
    else:
      echo "Comando desconhecido. Digite 'help' para ajuda."

when isMainModule:
  main()
