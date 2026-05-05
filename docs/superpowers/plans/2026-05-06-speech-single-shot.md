# Single-Shot Speech Recognition

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One click → one recognition → one result. Simple, no loops, Safari-reliable.

**Architecture:** `continuous = false`, `interimResults = true`. Recognition auto-ends when user stops speaking (Safari endpoint detection). Result auto-sends to Apple TV. User clicks again for next utterance.

**Tech Stack:** Web Speech API / No server changes

---

## File Map

| File | Action |
|------|--------|
| `Sources/Voxtv/DashboardServer.swift` | Replace entire speech JS block |

---

### Task 1: Replace speech JS with single-shot

**Files:**
- Modify: `Sources/Voxtv/DashboardServer.swift` — `dashboardHTML` string

- [ ] **Step 1: Read file to find speech block boundaries**

Read `Sources/Voxtv/DashboardServer.swift`. Find `// --- Speech recognition` through end of `resetSpeechButton()`.

- [ ] **Step 2: Replace with single-shot code**

Delete old block, insert:

```javascript
// --- Speech recognition (single-shot, Safari-reliable) ---
const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
let recognition = null;
const speechStatus = document.getElementById('speech-status');

function startRecognition() {
  if (!SpeechRecognition) {
    speechStatus.innerHTML = '<span style="color:#e94560">浏览器不支持语音识别</span>';
    return;
  }

  recognition = new SpeechRecognition();
  recognition.lang = 'zh-CN';
  recognition.interimResults = true;
  recognition.continuous = false;

  recognition.onstart = () => {
    pttBtn.textContent = '识别中...';
    pttBtn.style.background = '#c73d54';
    pttBtn.disabled = true;
    speechStatus.textContent = '正在听...';
    statusCard.classList.add('listening');
  };

  recognition.onresult = (event) => {
    let final = '';
    let interim = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const t = event.results[i][0].transcript.trim();
      if (event.results[i].isFinal) { final += t; } else { interim += t; }
    }
    if (final) {
      speechStatus.innerHTML = '<span style="color:#4caf84">识别结果: ' + final + '</span>';
      fetch('/api/apple-tv/send-text', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: final })
      });
    } else if (interim) {
      speechStatus.textContent = interim;
    }
  };

  recognition.onerror = (event) => {
    if (event.error === 'no-speech') {
      speechStatus.innerHTML = '<span style="color:#e94560">未检测到语音</span>';
    } else if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
      speechStatus.innerHTML = '<span style="color:#e94560">语音识别不可用</span>';
    } else if (event.error !== 'aborted') {
      speechStatus.innerHTML = '<span style="color:#e94560">识别错误: ' + event.error + '</span>';
    }
    resetSpeechButton();
  };

  recognition.onend = () => {
    // If no result arrived, show message
    if (pttBtn.disabled) {
      // Button still disabled = no onresult fired with final
    }
    resetSpeechButton();
  };

  try {
    recognition.start();
  } catch(e) {
    speechStatus.innerHTML = '<span style="color:#e94560">启动失败</span>';
    resetSpeechButton();
  }
}

function stopRecognition() {
  if (recognition) {
    recognition.stop();
  }
}

pttBtn.addEventListener('click', () => {
  if (pttBtn.disabled) {
    // Already recognizing — clicking stops it
    stopRecognition();
  } else {
    startRecognition();
  }
});

function resetSpeechButton() {
  recognition = null;
  pttBtn.textContent = '点击开始语音识别';
  pttBtn.style.background = '#e94560';
  pttBtn.disabled = false;
  statusCard.classList.remove('listening');
}
```

- [ ] **Step 3: Build and test**

```bash
swift build 2>&1 && swift test 2>&1 | grep "Executed" | tail -1
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Voxtv/DashboardServer.swift
git commit -m "feat: single-shot speech recognition — Safari-reliable"
```

---

### Task 2: Verification

- [ ] **Step 1: `swift test` — 15 tests**
- [ ] **Step 2: iPhone Safari manual test**

| 步骤 | 预期 |
|------|------|
| 点"点击开始语音识别" | 按钮变灰色"识别中..." |
| 说"三体" | 实时显示中间结果 |
| 说完停顿 | 自动结束，显示"识别结果: 三体"，发送到 Apple TV |
| 按钮恢复"点击开始" | 可再次点击 |
| 点按钮在识别中 | 提前结束识别 |

---
