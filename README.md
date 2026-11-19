# ⚡ AI-Nim-Browser & Autonomous Cognitive Web Engine

Ultra-lightweight, zero-GC (ARC/ORC) headless browser and Model Context Protocol (MCP) server written in native **Nim 2.2**.
Achieves **100% behavioral parity** with the Rust and Go reference implementations.

## 🚀 Key Highlights & Comparison

- **100% Differential Parity:** Verified with `parity_report` across all fixtures (`aria`, `basic`, `forms`, `hidden`, `spa`, `tables`), matching 6/6 fixtures with **0 differences**.
- **Micro-Executable Footprint:** **~733 KB** stripped binary size (**nearly 10x smaller** than Rust's 7.1 MiB).
- **Ultra-Low Memory:** Consumes **~3.5 to 4.2 MiB RAM** idle/active using Nim's ORC deterministic reference counting (no stop-the-world tracing GC).
- **Native MCP Server:** Implements standard JSON-RPC 2.0 with all 10 tools (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_status`, `browser_search`, `browser_memory_*`).
- **Cognitive Offline Memory:** BM25 scoring with TF-IDF keyword extraction, dynamic snippets with `<b>` highlights, domain playbooks, and handoff session export/resume.
- **SSRF Fail-Closed Protection:** Rejects local hostnames, private IPv4/IPv6, loopback, and cloud metadata (169.254.169.254).

## 🛠️ Build & Run

### 1. Run Differential Parity Test
```bash
nim c -r -d:release tests/parity_report.nim
```

### 2. Compile Release Binary
```bash
nim c -d:release --opt:size -o:ai-nim-browser.exe src/cli/main.nim
```

### 3. Run Interactive Terminal / REPL
```bash
.\ai-nim-browser.exe
```

### 4. Run MCP Server (over STDIN/STDOUT)
```bash
.\ai-nim-browser.exe mcp
```
