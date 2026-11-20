import webview
when defined(windows):
  import std/osproc

proc openDesktopBrowser*(url: string = "https://example.com", title: string = "AI Nim Browser - Desktop Window", width: int = 1200, height: int = 800) =
  when defined(windows):
    try:
      discard execCmd("reg add \"HKCU\\Software\\Microsoft\\Internet Explorer\\Main\\FeatureControl\\FEATURE_BROWSER_EMULATION\" /v \"ai-nim-browser.exe\" /t REG_DWORD /d 11001 /f >nul 2>&1")
    except:
      discard
  let w = newWebview(title, url, width, height)
  try:
    echo "Opening native Desktop Webview: ", url
    w.run()
  finally:
    w.exit()
