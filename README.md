# ⚡ AI-Nim-Browser & Autonomous Cognitive Web Engine

Ultra-lightweight, zero-GC (ARC/ORC) headless browser, JavaScript dynamic execution engine, native desktop viewer, and Model Context Protocol (MCP) server written in native **Nim 2.2**.
Achieves **100% behavioral parity** with the Rust and Go reference implementations.

## 🚀 Key Highlights & Empirical Benchmarks

| Metric / Feature | Go Reference | Rust (`ai-rust-browser`) | Nim (`ai-nim-browser`) | Winner |
| :--- | :--- | :--- | :--- | :--- |
| **Executable Size** | 13.16 MB | 6.77 MB | **1.43 MB** (with QuickJS + WebView2) | 🏆 **Nim (4.7x smaller than Rust)** |
| **RAM Footprint (WorkingSet)** | 7.42 MiB | 4.93 MiB | **3.91 MiB** | 🏆 **Nim (20% less than Rust, 47% less than Go)** |
| **Cold Start Latency** | 9.69 ms | 8.32 ms | **7.32 ms** | 🏆 **Nim (~7 ms)** |
| **JS Engine Execution** | External worker | None (static only) | **In-process QuickJS (1-3 ms)** | 🏆 **Nim** |
| **Differential Parity** | 6/6 (Base) | 6/6 (0 diffs) | **6/6 (0 diffs)** | 🤝 **100% Parity** |
| **Native Desktop UI** | External Chrome | None | **Native WebView2 Window (`ui`)** | 🏆 **Nim** |
| **MCP 2.0 Tools** | 10 tools | 10 tools | **10 tools** | 🤝 **100% Compatible** |

---

## 🛠️ Build & Run

### 1. Run Complete Verification & Benchmark Suite
```bash
nim c -r -d:release tests/verify_all.nim
```

### 2. Run Differential Parity Test (6/6 Golden Fixtures)
```bash
nim c -r -d:release tests/parity_report.nim
```

### 3. Run Client-side React/SPA Hydration Test
```bash
nim c -r -d:release tests/test_hydration.nim
```

### 4. Compile Release Binary
```bash
nim c -d:release --opt:size -o:ai-nim-browser.exe src/cli/main.nim
```

### 5. Run Interactive Terminal / REPL
```bash
.\ai-nim-browser.exe
```

### 6. Run Native Desktop Window (WebView2 / Chromium)
```bash
.\ai-nim-browser.exe ui https://example.com
```

### 7. Run MCP Server (over STDIN/STDOUT)
```bash
.\ai-nim-browser.exe mcp
```
