# Extract Dashboard HTML to SPM Resource

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the inline Dashboard HTML/JS string out of Swift source into a standalone file loaded via `Bundle.module`, eliminating Swift string escape bugs and enabling JS syntax checking.

**Architecture:** `Sources/Voxtv/Resources/dashboard.html` → `Bundle.module` → `DashboardServer` reads once at init → cached for all requests.

**Tech Stack:** SPM `.process(.resources)`, `Bundle.module`

---

### Task 1: Create standalone dashboard.html

**Files:**
- Create: `Sources/Voxtv/Resources/dashboard.html`

- [ ] **Step 1: Create the Resources directory**

```bash
mkdir -p Sources/Voxtv/Resources
```

- [ ] **Step 2: Extract the exact HTML from DashboardServer.swift and write to file**

Run:
```bash
python3 -c "
with open('Sources/Voxtv/DashboardServer.swift') as f:
    lines = f.readlines()
# Find the dashboardHTML block
start = None
for i, line in enumerate(lines):
    if line.strip().startswith('let dashboardHTML = '):
        start = i
        break
# Skip the first line and closing """
for j in range(start + 1, len(lines)):
    if lines[j].strip() == '\"\"\"':
        end = j
        break
html = ''.join(lines[start+1:end])
with open('Sources/Voxtv/Resources/dashboard.html', 'w') as f:
    f.write(html)
print(f'Wrote {len(html)} chars')
"
```

Expected: `Wrote 12203 chars`

- [ ] **Step 3: Fix the `\n` escape bug in the HTML file**

Find the line with `split('\n')` — in the standalone HTML file, `\n` is a literal backslash-n (correct JS escape). Verify the line reads:

```javascript
    const keywords = kwsKeywords.value.split('\n').filter(k => k.trim());
```

- [ ] **Step 4: Verify the HTML file is valid**

```bash
# Check it starts and ends correctly
head -3 Sources/Voxtv/Resources/dashboard.html
tail -3 Sources/Voxtv/Resources/dashboard.html

# Validate embedded JS syntax
python3 -c "
import re
html = open('Sources/Voxtv/Resources/dashboard.html').read()
m = re.search(r'<script>(.*?)</script>', html, re.DOTALL)
js = m.group(1)
open('/tmp/dashboard_check.js', 'w').write(js)
"
node --check /tmp/dashboard_check.js
```

Expected: `head` shows `<!DOCTYPE html>`, `tail` shows `</html>`, node exits 0

- [ ] **Step 5: Commit**

```bash
git add Sources/Voxtv/Resources/dashboard.html
git commit -m "feat: extract dashboard HTML to standalone resource file"
```

---

### Task 2: Add SPM resources to Package.swift

**Files:**
- Modify: `Package.swift:8-13`

- [ ] **Step 1: Add `.process("Resources")` to the executable target**

Edit `Package.swift` — change the executable target from:

```swift
        .executableTarget(
            name: "Voxtv",
            dependencies: [
                "CSherpaOnnx",
                "COnnxRuntime",
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "Libraries/CSherpaOnnx", "-lsherpa-onnx"]),
                .unsafeFlags(["-L", "Libraries/COnnxRuntime", "-lonnxruntime"]),
                .linkedLibrary("c++"),
            ]
        ),
```

to:

```swift
        .executableTarget(
            name: "Voxtv",
            dependencies: [
                "CSherpaOnnx",
                "COnnxRuntime",
            ],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags(["-L", "Libraries/CSherpaOnnx", "-lsherpa-onnx"]),
                .unsafeFlags(["-L", "Libraries/COnnxRuntime", "-lonnxruntime"]),
                .linkedLibrary("c++"),
            ]
        ),
```

- [ ] **Step 2: Build to verify resource is included**

```bash
swift build 2>&1
```

Expected: Build output includes `Copying dashboard.html` or similar resource processing message. Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "feat: add SPM resource bundle for dashboard HTML"
```

---

### Task 3: Load dashboard from Bundle.module in DashboardServer

**Files:**
- Modify: `Sources/Voxtv/DashboardServer.swift:163,357-675`

- [ ] **Step 1: Replace the inline dashboardHTML constant with a cached property**

Remove lines 355–675 (the entire `let dashboardHTML = """..."""` block) and replace with:

```swift
    // MARK: - Dashboard HTML (loaded from bundle resource)

    /// Cached dashboard HTML loaded once from Bundle.module.
    private static let dashboardHTML: String = {
        guard let url = Bundle.module.url(forResource: "dashboard", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("dashboard.html not found in Bundle.module — check Package.swift resources")
        }
        return html
    }()
```

- [ ] **Step 2: Build and verify**

```bash
swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Start the app and verify the Dashboard page still works**

```bash
.build/debug/Voxtv &
sleep 2
# Check the page is served
curl -s http://localhost:8765/ | head -c 100
echo ""
# Check API still works
curl -s http://localhost:8765/api/status
echo ""
# Check logs
curl -s http://localhost:8765/api/logs
kill %1 2>/dev/null
```

Expected: HTML page starts with `<!DOCTYPE html>`, `/api/status` returns JSON, `/api/logs` returns JSON array.

- [ ] **Step 4: Run the test suite**

```bash
swift test 2>&1
```

Expected: All tests pass, including `testDashboardHTML`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Voxtv/DashboardServer.swift
git commit -m "refactor: load dashboard HTML from Bundle.module instead of inline string"
```

---

## Verification

| Check | Method |
|-------|--------|
| Build succeeds | `swift build` |
| All tests pass | `swift test` |
| Dashboard page loads in browser | Open http://localhost:8765/ |
| JS executes (logs update, buttons work) | Check "连接中..." changes to logs |
| API endpoints still work | curl test all endpoints |
