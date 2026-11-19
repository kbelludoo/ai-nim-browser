import std/[os, strutils, syncio, options]
import ../core/[types, dom, semantic, transport, browser]
import ../mcp/server as mcpserver

proc main() =
  let args = commandLineParams()

  if args.len > 0 and (args[0] == "--version" or args[0] == "-v"):
    echo "ai-nim-browser v1.0.0 (parity track)"
    quit(0)

  if args.len > 0 and args[0] == "mcp":
    let s = newMcpServer()
    s.serve()
    quit(0)

  let b = newHttpSnapshotBrowser()
  echo "AI Nim Browser REPL / CLI (Type 'help' or commands: open <url>, snapshot, text, click <ref>, fill <ref> <val>, back, forward, mcp, quit)"

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
      echo "  open <url>               - Abre e renderiza semanticamente a página"
      echo "  snapshot                 - Mostra o snapshot de acessibilidade e ações"
      echo "  text                     - Extrai o texto limpo da página"
      echo "  click <ref>              - Clica no elemento (#ref ou l*/b*)"
      echo "  fill <ref> <valor>       - Preenche o campo de formulário"
      echo "  back                     - Volta no histórico"
      echo "  forward                  - Avança no histórico"
      echo "  mcp                      - Inicia o servidor MCP sobre stdin/stdout"
      echo "  quit                     - Sai do programa"
    of "open":
      if parts.len < 2:
        echo "Uso: open <url>"
        continue
      let url = parts[1]
      try:
        let snap = b.navigate(url)
        echo "\n=== ", snap.title, " ==="
        echo "URL: ", snap.url
        echo "Elementos interativos detectados: ", snap.elements.len
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
