# G-Trans

G-Trans 是一个原生 macOS 菜单栏翻译 App。它通过 `Option + Space` 翻译当前选中文本；无法读取选区时回退到手动输入；翻译结果支持复制、重新生成、新翻译和围绕本次翻译继续追问。

当前版本已完成本机 MVP 验收。

## 运行要求

- macOS 13 Ventura 或更高版本
- Swift toolchain / Command Line Tools
- 一个 OpenAI-compatible chat completions endpoint
- 辅助功能权限，用于读取选中文本和剪贴板兜底

## 构建

```bash
./scripts/check.sh
./scripts/build_app.sh
```

构建产物：

```text
.build/manual/GTrans.app
```

本机安装：

```bash
ditto .build/manual/GTrans.app /Applications/GTrans.app
open -a /Applications/GTrans.app
```

MVP 构建包使用 ad-hoc 签名，面向本机验证。Developer ID 签名和 notarization 留到正式分发阶段处理。

## 配置

从状态栏菜单打开 `设置...`。

需要配置：

- `base_url`：OpenAI-compatible API base URL
- `api_key`：必填；Ollama 本地服务可填任意非空值，例如 `ollama`
- `model`：模型名
- `使用流式输出`：默认开启
- `默认目标语言`：默认简体中文

已验收的本地 Ollama 配置：

```text
base_url: http://localhost:11434/v1/
api_key: ollama
model: qwen3.5:2b-mlx
```

本地 `localhost` / `127.0.0.1` endpoint 会自动带上：

```json
{
  "temperature": 0,
  "max_tokens": 2048,
  "reasoning": { "effort": "none" }
}
```

## 权限

G-Trans 需要 macOS 辅助功能权限读取选中文本，并在必要时模拟 `Command + C` 做剪贴板兜底。

在设置页点击 `请求权限`。macOS 会弹出 Accessibility 授权提示；从系统弹窗进入 System Settings 后开启 GTrans。

如果系统设置里显示 GTrans 已开启，但 App 仍显示未开启，请在辅助功能列表中删除 GTrans，然后重新授权 `/Applications/GTrans.app`。这会刷新 macOS TCC 授权记录。

## 使用

- 在其他 App 中选中文本，按 `Option + Space` 翻译。
- 未读取到选中文本时，G-Trans 会打开手动输入框。
- 结果页工具条包含：`复制译文`、`重新生成`、`新翻译`、`关闭`。
- 可以使用快捷追问按钮，或在 `继续追问` 输入框中自由追问。
- 关闭面板后，本次翻译上下文会被丢弃。

G-Trans 不保存翻译历史，不做遥测。

## 状态栏菜单

菜单顺序：

- `打开翻译`
- `打开日志目录`
- `设置...`
- 权限和 API 状态
- `退出`

## 日志

本地日志路径：

```text
~/Library/Application Support/GTrans/Logs/gtrans.log
```

日志记录启动、快捷键、选区读取、LLM 请求、复制、关闭和错误事件。日志超过约 512 KB 后轮转为 `gtrans.previous.log`。

G-Trans 不会自动上传日志。

## 项目结构

```text
Sources/GTrans/        macOS App、面板、状态栏、快捷键
Sources/GTransCore/    选区读取、LLM client、会话、配置、诊断日志
Tests/GTransCoreTests/ Core 单元测试
scripts/check.sh       直接编译和核心逻辑检查
scripts/build_app.sh   本地 .app 打包
docs/                  MVP 设计和验收记录
```
