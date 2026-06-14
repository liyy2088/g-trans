# G-Trans MVP 设计文档

## 结论

G-Trans 的 MVP 是一个 macOS 13+ 原生菜单栏翻译 App。用户通过 `Option + Space` 全局快捷键触发翻译：App 优先读取当前选中文本，读取失败时打开手动输入框；翻译结果在普通层级的可聚焦面板中流式显示，并支持围绕本次翻译继续追问。LLM 能力先只支持一套 OpenAI-compatible API 配置。

MVP 的目标不是做完整聊天应用、历史翻译库或多平台翻译器，而是验证一条最短闭环：全局唤起、拿到文本、调用 LLM、显示译文、允许轻量追问。本版本已完成本机 MVP 验收。

## 外部依据

- Apple `MenuBarExtra` 支持 macOS 菜单栏入口，适合常驻轻量 App：<https://developer.apple.com/documentation/swiftui/menubarextra>
- Apple `NSPanel` 适合承载可聚焦的翻译面板：<https://developer.apple.com/documentation/appkit/nspanel>
- Apple Accessibility API 提供选中文本读取能力，例如 `kAXSelectedTextAttribute`：<https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute>
- Apple `NSPasteboard` 是 macOS 剪贴板接口，可作为选区读取兜底：<https://developer.apple.com/documentation/appkit/nspasteboard>
- Apple Keychain Services 适合保存 API Key 这类敏感凭据，但 MVP 实测中会反复触发系统授权弹窗，本版默认改为本机偏好保存，后续再评估可选 Keychain：<https://developer.apple.com/documentation/security/keychain-services>
- OpenAI API reference 可作为 OpenAI-compatible 调用形态的基线：<https://platform.openai.com/docs/api-reference>
- Apple Carbon Hot Key API 可注册全局快捷键，当前实现直接注册 `Option + Space`，未引入第三方快捷键依赖。
- Apple notarization 是站外分发 macOS App 的可信安装链路：<https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>

## 产品范围

### 支持范围

- 平台：macOS。
- 最低系统版本：macOS 13 Ventura。
- 产品形态：原生菜单栏 App。
- 主入口：全局快捷键 `Option + Space`。
- 主流程：选中文本翻译；未读到选中文本时打开手动输入框。
- LLM：一套 OpenAI-compatible 配置。
- 交互：翻译、复制译文、重新生成、快捷追问、自由追问。
- 语言：用户界面先只支持简体中文。

### 不在 MVP 范围

- Windows、iOS、浏览器插件。
- Electron、Tauri 或 Web 外壳。
- Mac App Store 首发。
- 历史记录、多会话管理、跨文本记忆。
- 多 provider profile、多模型快速切换。
- 自定义 prompt 编辑器、术语表、风格市场。
- 一键替换原文、自动粘贴回当前 App。
- 遥测、埋点、崩溃上报。
- 自动更新、付费、账号、订阅。

## 用户流程

### 首次启动

首次启动进入引导/设置页，完成以下检查：

- 辅助功能权限：显示状态，并提供 `请求权限` 操作。
- LLM 配置：填写 `base_url`、`api_key`、`model`，保存后立即用于翻译。
- 快捷键：固定 `Option + Space`。
- 默认目标语言：默认简体中文，允许修改。
- 隐私提示：明确说明翻译文本会发送到用户配置的 LLM API endpoint。

未完成必要配置时，快捷键触发只打开引导/设置页，不静默失败。

### 快捷键触发

1. 用户按 `Option + Space`。
2. App 尝试通过 Accessibility API 读取当前选中文本。
3. 如果读取成功，立即打开翻译面板并开始翻译。
4. 如果读取失败，保存当前剪贴板，模拟 `Command + C`，短暂等待剪贴板变化。
5. 如果剪贴板兜底读取成功，恢复原剪贴板并开始翻译。
6. 如果仍未读到文本，打开手动输入模式并自动聚焦输入框。
7. 如果翻译窗口已经存在，再次按快捷键会读取当前前台 App 的新选区并替换为新翻译，不只聚焦旧窗口。

### 手动输入

- 用户可以在无选中文本时直接通过同一个快捷键打开输入框。
- 输入文本后提交翻译。
- 手动输入和选区翻译共用同一个翻译面板和会话模型。
- 结果页提供 `新翻译` 入口，可清空当前会话并回到手动输入模式。

### 翻译和追问

- 翻译结果流式显示。
- 追问仅绑定当前翻译会话。
- 关闭面板后丢弃当前上下文。
- 追问上下文包含原文、译文、目标语言和最近若干轮追问。

## UI 设计

### 菜单栏

菜单栏只作为入口和状态展示，不承载复杂翻译操作。

菜单项：

- `打开翻译`
- `打开日志目录`
- `设置...`
- `辅助功能权限：已开启/未开启`
- `API 配置：已完成/未完成`
- `退出`

不放历史记录、模型切换、目标语言切换或调试菜单。日志目录入口用于本机问题排查。

### 浮动面板

主交互使用可聚焦 `NSPanel`，不使用菜单栏 popover 承载翻译和追问。

布局采用单列紧凑结构：

- 顶部：原文预览，长文本折叠；展开后在独立滚动区内预读，避免撑爆面板。
- 中部：译文区域，支持流式显示和文本选择。
- 操作工具条：复制译文、重新生成、新翻译、关闭。工具条使用图标 + 短标签的紧凑样式，`新翻译` 使用强调状态。
- 快捷追问：解释用法、给例句、更自然表达、语法分析。
- 底部：自由追问输入框。

面板行为：

- `Esc` 或 `关闭` 关闭面板，并取消当前请求。
- 面板不强制置顶；切到其他 App 后可通过快捷键或菜单重新唤起。
- 网络请求中关闭面板不弹错误。
- 复制成功后在面板内短暂反馈。
- 错误提示留在面板内，不使用系统通知或声音。
- 译文和追问输出超过可见区时自动滚动到最新内容。

## 语言规则

默认语言策略：

- 自动识别源语言。
- 翻译到用户设置的默认目标语言。
- 首版默认目标语言为简体中文。

同语言切换规则：

- 如果默认目标语言是简体中文，输入非中文时翻译成简体中文。
- 如果输入已经是简体中文，主翻译动作自动切换为英文。
- 如果默认目标语言是英文，输入英文时翻译成简体中文。
- 追问沿用本次翻译语言，除非用户明确要求其他语言。

内部可使用 BCP 47 风格标签，例如 `zh-Hans`、`en`、`ja`、`zh-Hant`。

## LLM 配置

MVP 只支持一套 OpenAI-compatible 配置：

- `base_url`：默认 `https://api.openai.com/v1`
- `api_key`：必填，MVP 默认保存到本机偏好设置，避免翻译时反复触发系统密码弹窗。
- `model`：必填或提供默认可编辑值。

开发测试配置：

- `base_url`: `http://localhost:11434/v1/`
- `api_key`: `ollama`
- `model`: `qwen3.5:2b-mlx`

这组配置仅用于本机测试，不作为生产默认值。Ollama 的 OpenAI-compatible 文档说明本地 `/v1/chat/completions` 可使用 `http://localhost:11434/v1/`，`api_key` 字段必填但会被本地服务忽略。

不暴露给用户配置：

- `temperature`：代码内固定为 `0`。
- `timeout`：代码内固定为 `120s`。
- `top_p`
- `max_tokens`：代码内固定为 `512`。
- `reasoning`：本地 `localhost` / `127.0.0.1` endpoint 自动发送 `{"effort":"none"}`，避免本地推理模型输出无关 reasoning 或 `<pad>`。
- 自定义 headers
- 自定义 system prompt
- 多 profile

### 输出格式

- 翻译和追问主链路使用纯文本输出。
- 优先使用 streaming。
- 如果 provider 不支持 streaming 或请求失败，降级到非流式请求。
- 不要求模型返回 JSON。

### Prompt 边界

MVP 内置固定 prompt：

- 翻译 prompt：只输出译文，不解释，不加引号。
- 追问 prompt：带上原文、译文、目标语言和最近若干轮追问。
- 快捷追问固定为：解释用法、给例句、更自然表达、语法分析。

不提供 prompt 编辑器、自定义快捷按钮、术语表或风格预设。

## 本地数据与隐私

保存：

- `base_url`
- `model`
- 目标语言
- 是否流式
- 窗口位置等普通偏好

保存：

- `api_key` 存本机偏好设置。MVP 阶段优先降低系统授权打扰；后续如进入正式分发，再评估是否提供 Keychain 开关。

诊断：

- 本地保留滚动日志：`~/Library/Application Support/GTrans/Logs/gtrans.log`。
- 日志记录启动、快捷键、选区读取、LLM 请求、复制、关闭和错误事件。
- 日志文件超过约 512 KB 后轮转为 `gtrans.previous.log`。
- 不自动上传日志；用户可从状态栏菜单打开日志目录并自行提供。

不保存：

- 选中文本
- 译文
- 追问内容
- LLM 响应
- 翻译历史

网络与隐私边界：

- 不做遥测。
- 不做埋点。
- 不上传崩溃日志。
- 没有自有后端代理。
- 每次请求只发送本次原文、目标语言和当前临时追问上下文到用户配置的 `base_url`。

## 技术架构

### 技术栈

- Swift + SwiftUI + AppKit。
- Swift Package Manager 项目，手动脚本构建 `.app`。
- Swift Package Manager 管理依赖。
- 当前不引入第三方依赖；全局快捷键用 Carbon Hot Key API 直接注册。
- 使用 `URLSession` 调用 LLM API。
- 使用本机偏好保存 API Key，避免 MVP 阶段反复系统授权弹窗。
- 使用 `SMAppService` 管理开机自动启动。
- 生成 `.icns` 应用图标和状态栏 template 图标，随构建脚本打包。

### 模块划分

- `SelectionService`：读取当前选中文本；先 Accessibility API，失败走剪贴板兜底。
- `HotkeyService`：注册主快捷键并触发翻译入口。
- `TranslationSession`：管理一次临时翻译会话，包括原文、译文、目标语言、追问上下文和取消状态。
- `LLMClient`：OpenAI-compatible API 调用，支持 streaming 和非 streaming fallback。
- `PanelCoordinator`：管理 `NSPanel` 展示、聚焦、关闭、输入模式和结果模式切换。
- `StatusBarController`：管理状态栏图标、菜单顺序、权限/API 状态和日志入口。
- `AppDiagnostics`：写入本机诊断日志和未捕获异常信息。

不在 MVP 中引入 provider 插件系统、多窗口多会话管理、历史数据库或账号体系。

## 系统权限与分发

### 权限

MVP 接受申请辅助功能权限，并允许剪贴板兜底。

权限请求：

- 设置页按钮为 `请求权限`，只调用系统 Accessibility 授权 prompt。
- 系统弹窗由 macOS 负责提供 `Open System Settings` 入口，避免 App 同时主动打开系统设置导致双窗口。
- 如果系统设置显示已开启但 App 仍显示未开启，验收中确认删除旧 TCC 项并重新授权可恢复。

剪贴板兜底要求：

- 先保存原剪贴板内容。
- 模拟 `Command + C`。
- 读取新剪贴板文本。
- 尽力恢复原剪贴板。
- 恢复失败时明确提示。
- 不模拟粘贴，不写回当前 App。

### 开机启动

- 提供 `开机自动启动` 设置。
- 默认关闭。
- 用户开启后使用 `SMAppService` 注册登录项。

### 签名和分发

- 首发目标：站外分发。
- MVP 验收包通过 `scripts/build_app.sh` 生成并 ad-hoc 签名，安装到 `/Applications/GTrans.app` 本机验证。
- 正式内测或站外分发前再切换到 Developer ID 签名、Hardened Runtime 和 notarization。
- 不首发 Mac App Store。
- 不强制启用 App Sandbox；如后续进入 Mac App Store，再单独做 sandbox compatibility spike。
- 自动更新放到 MVP 后再评估，例如 Sparkle。

## 错误处理

策略：清晰提示优先，少量重试，不隐藏失败。

- `401/403`：提示 API Key 或权限错误，提供打开设置入口。
- `404/model_not_found`：提示模型名或 `base_url` 可能错误。
- `429`：提示限流，不频繁自动重试。
- `5xx/网络断开`：自动重试 1 次，仍失败则显示错误。
- streaming 中断：保留已生成内容，标记响应中断，允许重新生成。
- 用户关闭面板：取消请求，不再显示错误。

## 开发顺序

1. 创建 Swift macOS 菜单栏 App 骨架。
2. 做配置页：`base_url`、`api_key`、`model`、目标语言，API Key 存本机偏好。
3. 实现 `LLMClient`，先支持非流式，再支持 streaming。
4. 实现手动输入浮窗：快捷键唤起输入框，输入文本后翻译。
5. 实现选中文本读取：Accessibility API 优先，剪贴板兜底。
6. 实现追问临时会话。
7. 补自动测试和真机验收清单。
8. 最后处理签名、公证和手动安装包。

## 验证策略

自动测试覆盖：

- 语言方向规则。
- LLM request builder：`base_url`、`model`、stream 参数、messages。
- streaming parser：正常 chunk、`[DONE]`、异常 JSON、网络中断。
- `TranslationSession`：取消、追问上下文、关闭后清空。
- 配置读写：普通配置和 API Key 偏好存储。

手工真机验收覆盖：

- Safari、Chrome、Notes、VS Code 等至少 3 类 App 的选区读取。
- 读取失败时打开输入框。
- 剪贴板原内容恢复。
- `Esc` 关闭并取消请求。
- API 配置错误时提示明确。

## MVP 完成标准

- 首次启动能完成权限、API 和模型配置。
- `Option + Space` 在无选中文本时打开输入框。
- `Option + Space` 在至少 3 类 App 中能读取选中文本并翻译。
- Accessibility API 读取失败时能走剪贴板兜底，并尽力恢复原剪贴板。
- 翻译结果流式显示，失败时可读报错。
- 用户能复制译文。
- 用户能围绕当前翻译追问。
- 关闭面板后上下文丢弃。
- API Key 和普通配置存本地偏好。
- 不保存翻译历史，不做遥测。
- 自动测试覆盖语言规则、LLM request builder、stream parser 和会话取消。
- 能导出一个手动安装包；进入内测时签名并公证。
