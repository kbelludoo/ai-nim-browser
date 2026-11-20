import webview

proc openDesktopBrowser*(url: string = "https://example.com", title: string = "AI Nim Browser - Desktop Window", width: int = 1200, height: int = 800) =
  let w = newWebview(title, url, width, height)
  try:
    echo "Opening native Desktop Webview: ", url
    w.run()
  finally:
    w.exit()
