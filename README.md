# TokenMonitor

Windows taskbar tray monitor for local AI coding-tool token usage.

## What it does

- Runs as a Windows tray icon.
- Shows an always-visible status strip docked above the Windows taskbar.
- Shows a dashboard for Antigravity/Gemini, Codex/ChatGPT, and Claude Code.
- Calculates rolling 5-hour and 7-day usage from local JSON/JSONL logs (for providers without a query command configured, e.g. Gemini/Antigravity).
- Converts usage to remaining percentages using quotas that you configure.
- For providers with a query command configured (such as Codex/ChatGPT and Claude Code), queries the official endpoints directly for real-time live usage percentages, bypassing local log scanning.
- Stores settings in `%APPDATA%\TokenMonitor\settings.json`.

This is a local monitor and query tool. For providers without a query command configured, remaining quota is computed as:

```text
remaining % = max(0, quota - locally observed usage) / quota
```

For providers with a query command configured (e.g. Codex/ChatGPT and Claude Code), it queries the official usage APIs in the background using your local credentials/session tokens to fetch real-time remaining quota percentages, skipping local calculations. If the command fails, it reports the error directly.

## Run

From this folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\start-token-monitor.ps1
```

Double-click the tray icon or the status strip to open the dashboard. Right-click either one for Dashboard, Refresh, Settings, status strip visibility, and Exit.

## Configure quotas

Open Settings from the tray menu.

- `5h quota`: token budget for the rolling 5-hour window.
- `7d quota`: token budget for the rolling 7-day window.
- `Scan roots`: semicolon-separated files or folders to scan.
- `File patterns`: usually `*.jsonl; *.json`.
- `Max file MB`: logs larger than this are skipped during tray refresh.
- `Command JSON source`: optional PowerShell command. If set, it must print JSON and can override locally scanned values.
- `0` quota means unknown, so the percentage is displayed as `n/a`.

Command JSON output can use any of these fields:

```json
{
  "fiveHourUsed": 123456,
  "weeklyUsed": 456789,
  "fiveHourRemainingPercent": 87.5,
  "weeklyRemainingPercent": 64.0
}
```

You can also emit `fiveHourUsedPercent` and `weeklyUsedPercent`; the app will convert them to remaining percentages.

Default scan roots:

```text
Antigravity / Gemini:
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

## CLI checks

Print current local usage summary without opening the tray app:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -Dump
```

Create/default-check settings and print their path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -SelfTest
```

## Limits

Claude Code has documented local session transcripts under `~/.claude/projects/`; Claude's `/usage` screen also uses local history for approximate plan usage. Antigravity account-wide quota details may not be available from stable public local APIs, so this tool treats local JSON/JSONL token logs as the source of truth.

For Codex / ChatGPT, the tool fetches real-time rolling usage directly from the cloud analytics page (`https://chatgpt.com/codex/cloud/settings/analytics#usage`) using an automated background query command that retrieves remaining limit percentages using the session token in your local `~/.codex/auth.json` config, bypassing local logs.

For Claude Code, the tool fetches real-time rolling usage statistics (corresponding to the web-based usage settings page `https://claude.ai/new#settings/usage`) using the OAuth access token stored in your local `~/.claude/.credentials.json` to query the `https://api.anthropic.com/api/oauth/usage` endpoint, bypassing local logs.

