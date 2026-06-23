# TokenMonitor

Windows taskbar tray monitor for local AI coding-tool token usage.
Windows 系统托盘中的本地 AI 编程工具 Token 使用量监视器。

## What it does / 功能特性

- Runs as a Windows tray icon.
  以 Windows 系统托盘图标的形式运行。
- Shows an always-visible status strip docked above the Windows taskbar.
  在 Windows 任务栏上方显示一个常显的状态条（Status Strip）。
- Shows a dashboard for Antigravity, Codex/ChatGPT, and Claude Code.
  为 Antigravity、Codex/ChatGPT 和 Claude Code 提供专用的控制面板（Dashboard）。
- Calculates rolling 5-hour and 7-day usage from local JSON/JSONL logs (for providers without a query command configured, e.g. Antigravity).
  从本地的 JSON/JSONL 日志中计算 5 小时和 7 天滚动窗口的使用量（适用于未配置 API 查询命令的 Provider，例如 Antigravity）。
- Converts usage to remaining percentages using quotas that you configure.
  根据您配置的额度（Quota），自动将使用量转换为剩余百分比。
- For providers with a query command configured (such as Antigravity, Codex/ChatGPT, and Claude Code), queries the relevant live usage endpoint directly, bypassing local log scanning.
  对于配置了查询命令（Command）的 Provider（例如 Antigravity、Codex/ChatGPT 和 Claude Code），直接查询对应的实时额度接口，并跳过本地日志文件扫描。
- Stores settings in `%APPDATA%\TokenMonitor\settings.json`.
  设置存储在 `%APPDATA%\TokenMonitor\settings.json`。

This is a local monitor and query tool. For providers without a query command configured, remaining quota is computed as:
本软件是一个本地监视和查询工具。对于未配置查询命令的 Provider，其剩余配额计算公式为：

```text
remaining % = max(0, quota - locally observed usage) / quota
```

For providers with a query command configured, it queries the official usage APIs in the background using your local credentials/session tokens to fetch real-time remaining quota percentages, skipping local calculations. If the command fails, it reports the error directly.
对于配置了查询命令的 Provider，它会在后台使用您的本地凭据/会话 Token 直接查询官方的使用量 API，获取实时的配额剩余百分比，跳过任何本地计算。如果命令执行失败，则直接报告错误。

## Run / 运行

From this folder:
在此目录下执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\start-token-monitor.ps1
```

Double-click the tray icon or the status strip to open the dashboard. Right-click either one for Dashboard, Refresh, Settings, status strip visibility, and Exit.
双击托盘图标或状态条可以打开控制面板（Dashboard）。右键点击它们可以弹出菜单：控制面板、手动刷新、设置、切换状态条显隐以及退出。

## Build / 构建

Install `ps2exe`, then build the Windows tray executable from the repository root:
安装 `ps2exe` 后，在仓库根目录执行以下命令构建 Windows 托盘程序：

```powershell
Install-Module ps2exe -Scope CurrentUser
ps2exe .\src\TokenMonitor.ps1 .\bin\TokenMonitor.exe -STA -noConsole -title TokenMonitor -product TokenMonitor -version 1.2.7 -embedFiles @{'.\TokenUsage.psm1'='.\src\TokenUsage.psm1'}
```

The generated release executable is `bin\TokenMonitor.exe`. It embeds `src\TokenUsage.psm1` and extracts it as `TokenUsage.psm1` beside the executable on first run.
生成的 release 执行程序位于 `bin\TokenMonitor.exe`。它会嵌入 `src\TokenUsage.psm1`，首次运行时会在 exe 所在目录旁释放为 `TokenUsage.psm1`。

## Configure quotas / 配置额度

Open Settings from the tray menu.
从托盘菜单中打开 Settings（设置）。

- `5h quota`: token budget for the rolling 5-hour window.
  `5h quota`：5 小时滚动窗口内的 Token 限额预算。
- `7d quota`: token budget for the rolling 7-day window.
  `7d quota`：7 天（每周）滚动窗口内的 Token 限额预算。
- `Scan roots`: semicolon-separated files or folders to scan.
  `Scan roots`：分号隔开的本地日志扫描根目录或文件路径。
- `File patterns`: usually `*.jsonl; *.json`.
  `File patterns`：扫描的文件类型匹配，通常是 `*.jsonl; *.json`。
- `Max file MB`: logs larger than this are skipped during tray refresh.
  `Max file MB`：托盘刷新时，超出该大小的日志文件将被跳过不进行扫描。
- `Command JSON source`: optional PowerShell command. If set, it must print JSON and can override locally scanned values.
  `Command JSON source`：可选的 PowerShell 查询命令。如果设置了此命令，它必须输出 JSON 格式的内容，用来覆盖或替代本地扫描计算出的数值。
- `0` quota means unknown, so the percentage is displayed as `n/a`.
  限额设为 `0` 代表配额未知，百分比将显示为 `n/a`。

Command JSON output can use any of these fields:
自定义命令输出的 JSON 可以包含以下任一字段：

```json
{
  "fiveHourUsed": 123456,
  "weeklyUsed": 456789,
  "fiveHourRemainingPercent": 87.5,
  "weeklyRemainingPercent": 64.0
}
```

You can also emit `fiveHourUsedPercent` and `weeklyUsedPercent`; the app will convert them to remaining percentages.
您也可以输出 `fiveHourUsedPercent`（5小时已用百分比）和 `weeklyUsedPercent`（每周已用百分比），应用程序会自动将其转换为剩余百分比。

Default scan roots:
默认本地日志扫描根目录：

```text
Antigravity:
%APPDATA%\Google\Antigravity
%LOCALAPPDATA%\Google\Antigravity
%APPDATA%\Antigravity

Codex / ChatGPT:
%USERPROFILE%\.codex\sessions
%USERPROFILE%\.codex\session_index.jsonl

Claude Code:
%USERPROFILE%\.claude\projects
%USERPROFILE%\.claude\sessions
```

### Credentials setup / 凭据设置

For providers using query commands, you must configure local authorization files:
对于使用查询命令（Command）拉取官方数据的 Provider，您需要配置本地的授权/凭据文件：

- **Codex / ChatGPT**: Automatically created at `~/.codex/auth.json` when you log in through the Codex CLI.
  **Codex / ChatGPT**：当您在终端中使用 Codex CLI 登录后，会自动在 `~/.codex/auth.json` 生成该文件。
- **Claude Code**: Automatically created at `~/.claude/.credentials.json` when you log in through the Claude CLI.
  **Claude Code**：当您在终端中使用 Claude CLI 登录后，会自动在 `~/.claude/.credentials.json` 生成该凭据。
- **Antigravity**: No Gemini web cookies are required. Start Antigravity or Antigravity IDE and TokenMonitor queries Antigravity's local language-server RPC (`RetrieveUserQuotaSummary`) using the CSRF token and localhost port written to `%APPDATA%\Antigravity\logs\main.log` or `%APPDATA%\Antigravity IDE\logs\**\ls-main.log`.
  **Antigravity**：不需要 Gemini 网页 Cookie。启动 Antigravity 或 Antigravity IDE 后，TokenMonitor 会读取 `%APPDATA%\Antigravity\logs\main.log` 或 `%APPDATA%\Antigravity IDE\logs\**\ls-main.log` 中的本地端口和 CSRF token，并调用 Antigravity 本地 language-server RPC（`RetrieveUserQuotaSummary`）。

  This intentionally does not call `https://gemini.google.com/usage`, because Gemini web quota and Antigravity quota are separate.
  这里有意不调用 `https://gemini.google.com/usage`，因为 Gemini 网页额度和 Antigravity 额度是两套不同的限制。

## CLI checks / 命令行检查

Print current local usage summary without opening the tray app:
不启动托盘程序，直接在终端打印当前的本地使用摘要：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -Dump
```

Create/default-check settings and print their path:
创建/检查默认配置文件的状态，并输出配置文件的路径：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -SelfTest
```

## Limits / 限额说明

Claude Code has documented local session transcripts under `~/.claude/projects/`; Claude's `/usage` screen also uses local history for approximate plan usage. For Antigravity, when no query command is configured, this tool treats local JSON/JSONL token logs as the source of truth.
Claude Code 在 `~/.claude/projects/` 目录下存有本地会话记录；Claude 的命令行 `/usage` 指令也会使用这些本地历史记录来预估套餐使用情况。对于 Antigravity，如果未配置查询命令，该工具将以本地扫描到的 JSON/JSONL Token 日志作为数据源。

For Codex / ChatGPT, the tool fetches real-time rolling usage directly from the cloud analytics page (`https://chatgpt.com/codex/cloud/settings/analytics#usage`) using an automated background query command that retrieves remaining limit percentages using the session token in your local `~/.codex/auth.json` config, bypassing local logs.
对于 Codex / ChatGPT，该工具通过自动化的后台查询命令，利用您本地 `~/.codex/auth.json` 配置中的会话 Token，直接从云端分析页面 (`https://chatgpt.com/codex/cloud/settings/analytics#usage`) 获取实时的滚动额度剩余百分比，从而跳过本地日志解析。

For Claude Code, the tool fetches real-time rolling usage statistics (corresponding to the web-based usage settings page `https://claude.ai/new#settings/usage`) using the OAuth access token stored in your local `~/.claude/.credentials.json` to query the `https://api.anthropic.com/api/oauth/usage` endpoint, bypassing local logs.
对于 Claude Code，该工具利用您本地 `~/.claude/.credentials.json` 中的 OAuth 访问 Token，向 `https://api.anthropic.com/api/oauth/usage` 发起请求，获取实时的滚动使用统计数据（与网页版 `https://claude.ai/new#settings/usage` 的配额限制一致），跳过本地日志文件扫描。

For Antigravity, the tool fetches real-time rolling compute limits from the running Antigravity or Antigravity IDE local language server and currently reports the Gemini Models quota group only.
对于 Antigravity，该工具会从正在运行的 Antigravity 或 Antigravity IDE 本地 language server 获取实时滚动额度，目前只统计其中的 Gemini Models 配额组。
