# 环境搭建

Mac mini 上首次运行前的准备步骤。

## 1. 安装 pyatv

```bash
pipx install pyatv
pipx ensurepath
```

需要 Python ≤ 3.13。

## 2. 配对 Apple TV

首先确保 Apple TV 开机且在同一个局域网。

扫描设备：

```bash
atvremote scan
```

记录输出中的 device id（例如 `xxx@xxx`）。

配对：

```bash
atvremote wizard
```

按提示选择设备，在 Apple TV 上查看 PIN 码，输入终端。

## 3. 验证

```bash
atvremote --id <你的device_id> text_set="测试"
```

如果 Apple TV 当前输入框出现"测试"，配对成功。

## 4. 配置 Agent

启动 Agent 后，通过菜单栏 UI 或 Dashboard 输入 Apple TV device id。
