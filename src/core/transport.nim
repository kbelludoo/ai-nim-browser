import std/[httpclient, uri, strutils, tables]
import url_policy

const
  MaxBody* = 5 * 1024 * 1024 # 5 MiB
  MaxRedirects* = 10
  DefaultUserAgent* = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 ai-nim-browser/1.0"

type
  HttpResponse* = object
    status*: int
    finalUrl*: string
    body*: string
    contentType*: string

  SafeHttpTransport* = object
    maxBody*: int
    maxRedirects*: int
    timeoutMs*: int
    userAgent*: string
    validateSsrf*: bool

proc newSafeHttpTransport*(
  maxBody: int = MaxBody,
  maxRedirects: int = MaxRedirects,
  timeoutMs: int = 15000,
  validateSsrf: bool = true
): SafeHttpTransport =
  SafeHttpTransport(
    maxBody: maxBody,
    maxRedirects: maxRedirects,
    timeoutMs: timeoutMs,
    userAgent: DefaultUserAgent,
    validateSsrf: validateSsrf
  )

proc get*(t: SafeHttpTransport, targetUrl: string): Result[HttpResponse, string] =
  if t.validateSsrf:
    let check = validateUrl(targetUrl)
    if not check.isOk:
      return err[HttpResponse, string]($check.err)

  var client = newHttpClient(
    userAgent = t.userAgent,
    maxRedirects = t.maxRedirects,
    timeout = t.timeoutMs
  )
  client.headers = newHttpHeaders({
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "User-Agent": t.userAgent
  })

  try:
    let resp = client.get(targetUrl)
    var ct = ""
    if resp.headers.hasKey("content-type"):
      ct = $resp.headers["content-type"]
    var body = resp.body
    if body.len > t.maxBody:
      body.setLen(t.maxBody)
    ok[HttpResponse, string](HttpResponse(
      status: resp.code.int,
      finalUrl: targetUrl,
      body: body,
      contentType: ct
    ))
  except Exception as e:
    err[HttpResponse, string]("HTTP error: " & e.msg)
  finally:
    client.close()
