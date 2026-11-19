import std/[uri, strutils, parseutils]

type
  UrlPolicyError* = enum
    MissingScheme = "missing scheme"
    UnsupportedScheme = "unsupported scheme (only http and https allowed)"
    MissingHost = "missing host"
    Credentials = "userinfo/credentials in URL are forbidden"
    LocalHost = "localhost and local domain names are blocked"
    PrivateAddress = "private, link-local, or metadata addresses are blocked"

  Result*[T, E] = object
    case isOk*: bool
    of true:
      val*: T
    of false:
      err*: E

proc ok*[T, E](v: T): Result[T, E] = Result[T, E](isOk: true, val: v)
proc err*[T, E](e: E): Result[T, E] = Result[T, E](isOk: false, err: e)

proc isPrivateIpv4*(ipStr: string): bool =
  var parts = ipStr.split('.')
  if parts.len != 4: return false
  var octets: array[4, int]
  for i in 0 .. 3:
    if parseInt(parts[i], octets[i]) == 0 or octets[i] < 0 or octets[i] > 255:
      return false

  let a = octets[0]
  let b = octets[1]
  let c = octets[2]

  # 0.0.0.0/8
  if a == 0: return true
  # 127.0.0.0/8 (loopback)
  if a == 127: return true
  # 10.0.0.0/8 (private)
  if a == 10: return true
  # 172.16.0.0/12 (private)
  if a == 172 and b in 16 .. 31: return true
  # 192.168.0.0/16 (private)
  if a == 192 and b == 168: return true
  # 169.254.0.0/16 (link-local / cloud metadata)
  if a == 169 and b == 254: return true
  # 224.0.0.0/4 (multicast)
  if a in 224 .. 239: return true
  # 240.0.0.0/4 (reserved / broadcast)
  if a >= 240: return true
  # 100.64.0.0/10 (carrier-grade NAT RFC 6598)
  if a == 100 and b in 64 .. 127: return true
  # Documentation & benchmark ranges
  if a == 198 and (b == 18 or b == 19): return true
  if a == 192 and b == 0 and (c == 0 or c == 2): return true
  if a == 192 and b == 88 and c == 99: return true
  if a == 198 and b == 51 and c == 100: return true
  if a == 203 and b == 0 and c == 113: return true

  false

proc isPrivateIpv6*(ipStr: string): bool =
  let clean = ipStr.strip(chars = {'[', ']'}).toLowerAscii()
  if clean == "::1" or clean == "::":
    return true
  if clean.startsWith("fe80:") or clean.startsWith("fe8") or clean.startsWith("fe9") or
     clean.startsWith("fea") or clean.startsWith("feb"):
    return true # link-local
  if clean.startsWith("fc00:") or clean.startsWith("fd"):
    return true # unique local
  if clean.startsWith("::ffff:"):
    let ipv4Part = clean["--ffff:".len .. ^1]
    return isPrivateIpv4(ipv4Part)
  false

proc validateUrl*(input: string): Result[Uri, UrlPolicyError] =
  if ':' notin input:
    return Result[Uri, UrlPolicyError](isOk: false, err: MissingScheme)

  var u: Uri
  try:
    u = parseUri(input)
  except:
    return Result[Uri, UrlPolicyError](isOk: false, err: MissingScheme)

  let scheme = u.scheme.toLowerAscii()
  if scheme notin ["http", "https"]:
    return Result[Uri, UrlPolicyError](isOk: false, err: UnsupportedScheme)

  if u.username.len > 0 or u.password.len > 0:
    return Result[Uri, UrlPolicyError](isOk: false, err: Credentials)

  if u.hostname.len == 0:
    return Result[Uri, UrlPolicyError](isOk: false, err: MissingHost)

  let host = u.hostname.strip(chars = {'.'}).toLowerAscii()
  if host in ["localhost", "localhost.localdomain"] or
     host.endsWith(".localhost") or host.endsWith(".local"):
    return Result[Uri, UrlPolicyError](isOk: false, err: LocalHost)

  if isPrivateIpv4(host) or isPrivateIpv6(host):
    return Result[Uri, UrlPolicyError](isOk: false, err: PrivateAddress)

  Result[Uri, UrlPolicyError](isOk: true, val: u)
