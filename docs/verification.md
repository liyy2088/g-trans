# G-Trans MVP 验证清单

## 自动验证

- `swift test`
  - 覆盖语言方向规则。
  - 覆盖 OpenAI-compatible request builder。
  - 覆盖 SSE streaming parser。
  - 覆盖 `TranslationSession` 关闭后清空上下文。
  - 覆盖配置和 API Key 偏好读写。

> 当前机器的 Command Line Tools SwiftPM manifest 链接失败，已提供 `scripts/check.sh` 作为临时验证入口。换到完整且匹配的 Xcode/Command Line Tools 后应优先跑 `swift test`。

## 编译验证

- `swift build`
- `scripts/check.sh`
- `swiftc -parse-as-library -typecheck Sources/GTransCore/*.swift`
- 先构建 `GTransCore` module 后 typecheck `Sources/GTrans/*.swift`

## 真机验收

1. 首次启动打开设置页，确认辅助功能权限状态、API 配置、默认目标语言和隐私提示可见。
2. 未配置 API Key 或 model 时按 `Option + Space`，应打开设置页，不静默失败。
3. 配置本地测试 endpoint：
   - `base_url`: `http://localhost:11434/v1/`
   - `api_key`: `ollama`
   - `model`: `gemma4:12b-mlx`
4. 在 Safari 选中文本后按 `Option + Space`，应打开浮动面板并开始翻译。
5. 在 Chrome 选中文本后按 `Option + Space`，应打开浮动面板并开始翻译。
6. 在 Notes 或 VS Code 选中文本后按 `Option + Space`，应打开浮动面板并开始翻译。
7. 在无选中文本时按 `Option + Space`，应打开手动输入框并自动聚焦。
8. Accessibility API 读取失败时，应走剪贴板兜底，并在翻译后恢复原剪贴板内容。
9. 翻译过程中按 `Esc` 或关闭面板，应取消当前请求且不弹系统通知。
10. 点击“复制译文”，剪贴板应写入译文，面板内短暂显示“已复制”。
11. 点击“重新生成”，应重新发起本次翻译。
12. 点击“解释用法 / 给例句 / 更自然表达 / 语法分析”，应默认针对原文追问，译文仅作为参考。
13. 在底部输入自由追问并发送，应默认针对原文追问；明确询问译文时才分析译文。
14. 关闭面板后再次翻译，上一轮追问上下文不应保留。
15. 使用错误 API Key，应在面板内提示 API Key 或权限错误。
16. 使用错误 model，应在面板内提示模型名或 `base_url` 可能错误。
