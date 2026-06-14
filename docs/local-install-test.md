# 本机安装实测记录

日期：2026-06-14

## 结论

`GTrans.app` 已在本机生成、签名、安装到 `/Applications/GTrans.app` 并成功启动。设置页可见且可通过 GUI 写入配置；普通配置和 API Key 落盘到 `UserDefaults`。全局快捷键 `Option + Space` 的 Carbon 注册状态为 `0`，表示注册成功。

本机 `http://localhost:11434` 的 Ollama OpenAI-compatible endpoint 已可用，模型 `gemma4:12b-mlx` 已通过真实 App UI 完成 `Hello -> 你好` 翻译实测。翻译面板已改为普通窗口层级，不再强制停留在桌面最上面。

自动化发送 `Option + Space` 没有触发窗口，当前只能证明热键注册成功；仍需要人工按物理键盘复测快捷键触发。

2026-06-14 追加修正：API Key 默认改为 `UserDefaults` 保存，不再使用 Keychain，避免翻译时出现 “GTrans wants to use your confidential information stored in GTrans.OpenAICompatible” 系统密码弹窗。旧 Keychain 条目已删除，`security find-generic-password` 返回 status `44`。

2026-06-14 追加修正：辅助功能权限状态从 computed value 改为 `@Published` 状态，并在设置页显示期间每秒刷新一次；“打开系统设置”按钮同时打开 `Privacy_Accessibility` 设置页。系统 API 当前返回 `true`，用于修复“已经开启但 UI 一直显示未开启”的问题。

2026-06-14 追加修正：开发期 ad-hoc 签名原本生成 `cdhash` designated requirement，导致每次重装后 macOS TCC 辅助功能授权可能仍显示旧 `GTrans` 已开启，但当前二进制实际不匹配。打包脚本已改为稳定 requirement：`designated => identifier "local.g-trans.GTrans"`。如果 App 日志仍显示 `accessibility=false`，需要在系统设置的辅助功能列表中删除旧 `GTrans`，再重新添加当前 `/Applications/GTrans.app`。

2026-06-14 追加修正：加入本地诊断日志。App 同时写入 macOS unified logging 和 `~/Library/Application Support/GTrans/Logs/gtrans.log`，菜单栏提供“打开日志目录”。日志只记录事件、长度、状态和错误类型，不记录原文或译文内容。

## 安装产物

- 生成位置：`.build/manual/GTrans.app`
- 安装位置：`/Applications/GTrans.app`
- Bundle ID：`local.g-trans.GTrans`
- 签名方式：本机 ad-hoc codesign

## 已执行验证

### Bundle 和签名

```sh
scripts/build_app.sh
codesign --verify --deep --strict --verbose=2 /Applications/GTrans.app
```

结果：

- `/Applications/GTrans.app: valid on disk`
- `/Applications/GTrans.app: satisfies its Designated Requirement`

### 启动

```sh
open -a /Applications/GTrans.app
pgrep -fl GTrans
```

结果：

- 进程启动成功：`/Applications/GTrans.app/Contents/MacOS/GTrans`

### 设置页

通过 Computer Use 读取到窗口：

- 窗口标题：`G-Trans 设置`
- 可见字段：`base_url`、`api_key`、`model`
- 可见控制：`使用流式输出`、`默认目标语言`、`开机自动启动`
- 可见文案：`快捷键：Option + Space`
- 可见隐私提示：翻译文本会发送到用户配置的 LLM API endpoint，且不保存翻译历史、不做遥测

### 配置保存

通过 GUI 写入：

- `base_url`: `http://localhost:11434/v1/`
- `api_key`: 测试值
- `model`: `gemma4:12b-mlx`

`UserDefaults` 验证：

```sh
defaults read local.g-trans.GTrans
```

结果包含：

- `apiKey = ollama;`
- `baseURL = "http://localhost:11434/v1/";`
- `model = "gemma4:12b-mlx";`
- `streamingEnabled = 1;`
- `targetLanguage = "zh-Hans";`

API Key 验证：

- `defaults read local.g-trans.GTrans` 包含 `apiKey`。
- 不再默认使用 Keychain，避免翻译时出现系统密码弹窗。
- 旧 Keychain 条目已删除，`security find-generic-password -s GTrans.OpenAICompatible -a api_key` 返回 status `44`。

### 快捷键注册

App 启动后写入：

```sh
defaults read local.g-trans.GTrans hotkeyRegistrationStatus
```

结果：

- `0`

### 本机 LLM endpoint

```sh
curl -sS --max-time 10 http://localhost:11434/v1/models
curl -sS --max-time 30 http://localhost:11434/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer ollama' \
  -d '{"model":"gemma4:12b-mlx","messages":[{"role":"user","content":"Translate to Simplified Chinese: Hello"}],"stream":false}'
```

结果：

- `/v1/models` 返回 `gemma4:12b-mlx`
- `/v1/chat/completions` 返回 `你好 (nǐ hǎo)`

### 真实 App 翻译

最终安装版通过启动参数触发同一套 App 翻译流程：

```sh
open -a /Applications/GTrans.app --args --translate-text Hello
```

GUI 读取结果：

- 窗口标题：`G-Trans`
- 原文：`Hello`
- 译文：`你好`
- 可见按钮：`复制译文`、`重新生成`、`关闭`、`解释用法`、`给例句`、`更自然表达`、`语法分析`
- 可见自由追问输入框：`继续追问`

### 复制译文

用户已允许覆盖剪贴板做复制验证。验证步骤：

```sh
printf 'GTRANS_SENTINEL' | pbcopy
osascript -e 'tell application "System Events" to tell process "GTrans" to click button 2 of group 1 of window "G-Trans"'
pbpaste
```

结果：

- `pbpaste` 返回 `你好`

### 快捷追问

点击 `解释用法` 后，面板中出现追问标题 `解释用法` 和模型回答内容，证明当前翻译会话的追问链路可用。

### 窗口层级

翻译面板已从：

- `panel.isFloatingPanel = true`
- `panel.level = .floating`

调整为：

- `panel.isFloatingPanel = false`
- `panel.level = .normal`

因此不再强制停留在桌面最上面。

2026-06-14 追加修正：翻译面板打开时调用 `NSApp.setActivationPolicy(.regular)`，关闭时回到 `.accessory`，修复切换到其他窗口后无法再切回 GTrans 窗口的问题。

2026-06-14 追加修正：已有翻译窗口时再次按 `Option + Space` 不再重新读取选区或重建 SwiftUI 内容，而是直接调用 `makeKeyAndOrderFront` 并激活 App。验证日志出现 `translate_shortcut_focus_existing_panel`。

2026-06-14 追加修正：翻译窗口内 `关闭` 按钮不再在 SwiftUI Button action 中同步关闭窗口和修改会话状态，而是先记录 `panel_close_requested`，再在下一轮主线程执行实际 `panel_close`。验证点击关闭后窗口消失、GTrans 进程仍运行，且没有新增 crash report。

2026-06-14 追加修正：关闭窗口后不再把 App activation policy 切回 `.accessory`，避免菜单栏 App 在无窗口状态下无法被快捷键或菜单重新激活。状态栏菜单动作改为同步调用 `openManualInput()`，快捷键在 App 未识别到辅助功能权限时直接打开手动输入窗口，避免选区读取卡住导致窗口不出现。验证日志出现 `selected_text_failed reason=accessibility_permission_missing_before_read` 后窗口显示手动输入页。

### 选中文本读取

2026-06-14 追加修正：选中文本读取流程调整为先尝试 Accessibility API；如果未读到文本，再走剪贴板兜底。即使辅助功能权限未开启，也会尝试剪贴板兜底；只有两种方式都失败时才进入手动输入并显示明确提示。

## 未完成的实测项

- AppleScript 和 CoreGraphics 合成 `Option + Space` 均未触发面板。由于 App 写入的 Carbon 注册状态为 `0`，当前只能确认热键注册成功；仍需要人工按物理键盘 `Option + Space` 或在可触发系统热键的 UI 自动化环境中复测。
- 物理键盘 `Option + Space` 已由用户反馈确认能唤起窗口。

## 闪退诊断

App 内日志：

- 路径：`~/Library/Application Support/GTrans/Logs/gtrans.log`
- 滚动备份：`gtrans.previous.log`
- 菜单栏入口：`打开日志目录`

诊断收集：

```sh
scripts/collect_diagnostics.sh
```

输出目录位于 `.local/diagnostics/<timestamp>`，包含：

- App 本地日志
- 最近 14 天内匹配 `GTrans*.ips`、`GTrans*.crash`、`G-Trans*.ips`、`G-Trans*.crash` 的 macOS 崩溃报告

排查顺序：

1. 先看最新 `.ips` 或 `.crash`，这是 macOS 对闪退原因的权威记录。
2. 再按时间戳对照 `gtrans.log`，看崩溃前最后一个 App 事件，例如快捷键、选区读取、请求开始、请求失败、复制、关闭面板。
3. 如没有 `.ips/.crash`，但 App 消失，优先检查 `gtrans.log` 的最后一行和 Console.app 中 subsystem `local.g-trans.GTrans` 的日志。

2026-06-14 追加修正：多次从状态栏菜单点击 `打开翻译` 后闪退，最新 `.ips` 崩溃线程落在 SwiftUI `MenuBarExtra` 菜单动作回调链路。状态栏入口已改为 AppKit `NSStatusItem` + `NSMenu`，避免通过 SwiftUI `MenuBarExtra` 执行菜单动作。新版启动日志应出现：

```text
event=status_item_installed
```

再次复现时优先确认最新崩溃报告时间是否晚于该日志时间；如果晚于该时间，再把最新 `.ips` 和 `gtrans.log` 一起作为证据。

## 本机 Ollama 超时诊断

2026-06-14 追加修正：当前本机配置曾使用：

- `base_url`: `http://localhost:11434/v1/`
- `model`: `qwen3.5:2b-mlx`
- `streamingEnabled`: `true`

真实排查结果：

- `curl /v1/models` 能立即返回，说明 endpoint 可达。
- `qwen3.5:2b-mlx` 在当前 Ollama 运行状态下会长时间只输出 `reasoning`，不输出 `content`，不适合作为 GTrans 当前翻译模型。
- Ollama runner 一度以 `262144` context 加载并卡在 `Stopping...`，导致 App 30 秒请求超时。
- `gemma4:12b-mlx` 在重启 Ollama 后可用，但首次加载和本机推理可能超过 30 秒。

修复：

- GTrans 请求体加入 `max_tokens = 512`，避免本地模型无限生成。
- GTrans 请求超时从 `30s` 调整为 `120s`，覆盖本机 Ollama 模型冷启动和大 context 首轮推理。
- 当前本机偏好已改为 `model = gemma4:12b-mlx`、`streamingEnabled = false`。

验证：

- `open -a /Applications/GTrans.app --args --translate-text Hello`
- 日志显示请求从 `2026-06-14T05:37:11Z` 到 `2026-06-14T05:37:19Z` 完成。
- 翻译窗口显示 `Hello -> 你好`。
