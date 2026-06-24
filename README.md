# TokenMonitor

Windows taskbar tray monitor for local AI coding-tool token usage.
Windows 绯荤粺鎵樼洏涓殑鏈湴 AI 缂栫▼宸ュ叿 Token 浣跨敤閲忕洃瑙嗗櫒銆?
## What it does / 鍔熻兘鐗规€?
- Runs as a Windows tray icon.
  浠?Windows 绯荤粺鎵樼洏鍥炬爣鐨勫舰寮忚繍琛屻€?- Shows an always-visible status strip docked above the Windows taskbar.
  鍦?Windows 浠诲姟鏍忎笂鏂规樉绀轰竴涓父鏄剧殑鐘舵€佹潯锛圫tatus Strip锛夈€?- Shows a dashboard for Antigravity, Codex/ChatGPT, and Claude Code.
  涓?Antigravity銆丆odex/ChatGPT 鍜?Claude Code 鎻愪緵涓撶敤鐨勬帶鍒堕潰鏉匡紙Dashboard锛夈€?- Calculates rolling 5-hour and 7-day usage from local JSON/JSONL logs (for providers without a query command configured, e.g. Antigravity).
  浠庢湰鍦扮殑 JSON/JSONL 鏃ュ織涓绠?5 灏忔椂鍜?7 澶╂粴鍔ㄧ獥鍙ｇ殑浣跨敤閲忥紙閫傜敤浜庢湭閰嶇疆 API 鏌ヨ鍛戒护鐨?Provider锛屼緥濡?Antigravity锛夈€?- Converts usage to remaining percentages using quotas that you configure.
  鏍规嵁鎮ㄩ厤缃殑棰濆害锛圦uota锛夛紝鑷姩灏嗕娇鐢ㄩ噺杞崲涓哄墿浣欑櫨鍒嗘瘮銆?- For providers with a query command configured (such as Antigravity, Codex/ChatGPT, and Claude Code), queries the relevant live usage endpoint directly, bypassing local log scanning.
  瀵逛簬閰嶇疆浜嗘煡璇㈠懡浠わ紙Command锛夌殑 Provider锛堜緥濡?Antigravity銆丆odex/ChatGPT 鍜?Claude Code锛夛紝鐩存帴鏌ヨ瀵瑰簲鐨勫疄鏃堕搴︽帴鍙ｏ紝骞惰烦杩囨湰鍦版棩蹇楁枃浠舵壂鎻忋€?- Stores settings in `%APPDATA%\TokenMonitor\settings.json`.
  璁剧疆瀛樺偍鍦?`%APPDATA%\TokenMonitor\settings.json`銆?- Stores the last visible Antigravity quota in `%APPDATA%\TokenMonitor\quota-cache.json`, so the tray can show the cached quota and reset time while Antigravity is closed.
  浼氬皢鏈€鍚庝竴娆″彲瑙佺殑 Antigravity 棰濆害瀛樺偍鍦?`%APPDATA%\TokenMonitor\quota-cache.json`锛屽洜姝?Antigravity 鍏抽棴鏃舵墭鐩樹粛鍙樉绀虹紦瀛橀搴﹀拰鎭㈠鏃堕棿銆?
This is a local monitor and query tool. For providers without a query command configured, remaining quota is computed as:
鏈蒋浠舵槸涓€涓湰鍦扮洃瑙嗗拰鏌ヨ宸ュ叿銆傚浜庢湭閰嶇疆鏌ヨ鍛戒护鐨?Provider锛屽叾鍓╀綑閰嶉璁＄畻鍏紡涓猴細

```text
remaining % = max(0, quota - locally observed usage) / quota
```

For providers with a query command configured, it queries the official usage APIs in the background using your local credentials/session tokens to fetch real-time remaining quota percentages, skipping local calculations. If the command fails, it reports the error directly.
瀵逛簬閰嶇疆浜嗘煡璇㈠懡浠ょ殑 Provider锛屽畠浼氬湪鍚庡彴浣跨敤鎮ㄧ殑鏈湴鍑嵁/浼氳瘽 Token 鐩存帴鏌ヨ瀹樻柟鐨勪娇鐢ㄩ噺 API锛岃幏鍙栧疄鏃剁殑閰嶉鍓╀綑鐧惧垎姣旓紝璺宠繃浠讳綍鏈湴璁＄畻銆傚鏋滃懡浠ゆ墽琛屽け璐ワ紝鍒欑洿鎺ユ姤鍛婇敊璇€?
## Run / 杩愯

From this folder:
鍦ㄦ鐩綍涓嬫墽琛岋細

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\start-token-monitor.ps1
```

Double-click the tray icon or the status strip to open the dashboard. Right-click either one for Dashboard, Refresh, Settings, status strip visibility, and Exit.
鍙屽嚮鎵樼洏鍥炬爣鎴栫姸鎬佹潯鍙互鎵撳紑鎺у埗闈㈡澘锛圖ashboard锛夈€傚彸閿偣鍑诲畠浠彲浠ュ脊鍑鸿彍鍗曪細鎺у埗闈㈡澘銆佹墜鍔ㄥ埛鏂般€佽缃€佸垏鎹㈢姸鎬佹潯鏄鹃殣浠ュ強閫€鍑恒€?
By default it refreshes every 1 minute.
榛樿姣?1 鍒嗛挓鍒锋柊涓€娆°€?
## Build / 鏋勫缓

Install `ps2exe`, then build the Windows tray executable from the repository root:
瀹夎 `ps2exe` 鍚庯紝鍦ㄤ粨搴撴牴鐩綍鎵ц浠ヤ笅鍛戒护鏋勫缓 Windows 鎵樼洏绋嬪簭锛?
```powershell
Install-Module ps2exe -Scope CurrentUser
ps2exe .\src\TokenMonitor.ps1 .\bin\TokenMonitor.exe -STA -noConsole -title TokenMonitor -product TokenMonitor -version 1.3.1 -embedFiles @{'.\TokenUsage.psm1'='.\src\TokenUsage.psm1'}
```

The generated release executable is `bin\TokenMonitor.exe`. It embeds `src\TokenUsage.psm1` and extracts it as `TokenUsage.psm1` beside the executable on first run.
鐢熸垚鐨?release 鎵ц绋嬪簭浣嶄簬 `bin\TokenMonitor.exe`銆傚畠浼氬祵鍏?`src\TokenUsage.psm1`锛岄娆¤繍琛屾椂浼氬湪 exe 鎵€鍦ㄧ洰褰曟梺閲婃斁涓?`TokenUsage.psm1`銆?
## Configure quotas / 閰嶇疆棰濆害

Open Settings from the tray menu.
浠庢墭鐩樿彍鍗曚腑鎵撳紑 Settings锛堣缃級銆?
- `5h quota`: token budget for the rolling 5-hour window.
  `5h quota`锛? 灏忔椂婊氬姩绐楀彛鍐呯殑 Token 闄愰棰勭畻銆?- `7d quota`: token budget for the rolling 7-day window.
  `7d quota`锛? 澶╋紙姣忓懆锛夋粴鍔ㄧ獥鍙ｅ唴鐨?Token 闄愰棰勭畻銆?- `Scan roots`: semicolon-separated files or folders to scan.
  `Scan roots`锛氬垎鍙烽殧寮€鐨勬湰鍦版棩蹇楁壂鎻忔牴鐩綍鎴栨枃浠惰矾寰勩€?- `File patterns`: usually `*.jsonl; *.json`.
  `File patterns`锛氭壂鎻忕殑鏂囦欢绫诲瀷鍖归厤锛岄€氬父鏄?`*.jsonl; *.json`銆?- `Max file MB`: logs larger than this are skipped during tray refresh.
  `Max file MB`锛氭墭鐩樺埛鏂版椂锛岃秴鍑鸿澶у皬鐨勬棩蹇楁枃浠跺皢琚烦杩囦笉杩涜鎵弿銆?- `Command JSON source`: optional PowerShell command. If set, it must print JSON and can override locally scanned values.
  `Command JSON source`锛氬彲閫夌殑 PowerShell 鏌ヨ鍛戒护銆傚鏋滆缃簡姝ゅ懡浠わ紝瀹冨繀椤昏緭鍑?JSON 鏍煎紡鐨勫唴瀹癸紝鐢ㄦ潵瑕嗙洊鎴栨浛浠ｆ湰鍦版壂鎻忚绠楀嚭鐨勬暟鍊笺€?- `0` quota means unknown, so the percentage is displayed as `n/a`.
  闄愰璁句负 `0` 浠ｈ〃閰嶉鏈煡锛岀櫨鍒嗘瘮灏嗘樉绀轰负 `n/a`銆?
Command JSON output can use any of these fields:
鑷畾涔夊懡浠よ緭鍑虹殑 JSON 鍙互鍖呭惈浠ヤ笅浠讳竴瀛楁锛?
```json
{
  "fiveHourUsed": 123456,
  "weeklyUsed": 456789,
  "fiveHourRemainingPercent": 87.5,
  "weeklyRemainingPercent": 64.0
}
```

You can also emit `fiveHourUsedPercent` and `weeklyUsedPercent`; the app will convert them to remaining percentages.
鎮ㄤ篃鍙互杈撳嚭 `fiveHourUsedPercent`锛?灏忔椂宸茬敤鐧惧垎姣旓級鍜?`weeklyUsedPercent`锛堟瘡鍛ㄥ凡鐢ㄧ櫨鍒嗘瘮锛夛紝搴旂敤绋嬪簭浼氳嚜鍔ㄥ皢鍏惰浆鎹负鍓╀綑鐧惧垎姣斻€?
Default scan roots:
榛樿鏈湴鏃ュ織鎵弿鏍圭洰褰曪細

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

### Credentials setup / 鍑嵁璁剧疆

For providers using query commands, you must configure local authorization files:
瀵逛簬浣跨敤鏌ヨ鍛戒护锛圕ommand锛夋媺鍙栧畼鏂规暟鎹殑 Provider锛屾偍闇€瑕侀厤缃湰鍦扮殑鎺堟潈/鍑嵁鏂囦欢锛?
- **Codex / ChatGPT**: Automatically created at `~/.codex/auth.json` when you log in through the Codex CLI.
  **Codex / ChatGPT**锛氬綋鎮ㄥ湪缁堢涓娇鐢?Codex CLI 鐧诲綍鍚庯紝浼氳嚜鍔ㄥ湪 `~/.codex/auth.json` 鐢熸垚璇ユ枃浠躲€?- **Claude Code**: Automatically created at `~/.claude/.credentials.json` when you log in through the Claude CLI.
  **Claude Code**锛氬綋鎮ㄥ湪缁堢涓娇鐢?Claude CLI 鐧诲綍鍚庯紝浼氳嚜鍔ㄥ湪 `~/.claude/.credentials.json` 鐢熸垚璇ュ嚟鎹€?- **Antigravity**: No Gemini web cookies are required. Start Antigravity or Antigravity IDE and TokenMonitor queries Antigravity's local language-server RPC (`RetrieveUserQuotaSummary`) using the CSRF token and localhost port written to `%APPDATA%\Antigravity\logs\main.log` or `%APPDATA%\Antigravity IDE\logs\**\ls-main.log`.
  **Antigravity**锛氫笉闇€瑕?Gemini 缃戦〉 Cookie銆傚惎鍔?Antigravity 鎴?Antigravity IDE 鍚庯紝TokenMonitor 浼氳鍙?`%APPDATA%\Antigravity\logs\main.log` 鎴?`%APPDATA%\Antigravity IDE\logs\**\ls-main.log` 涓殑鏈湴绔彛鍜?CSRF token锛屽苟璋冪敤 Antigravity 鏈湴 language-server RPC锛坄RetrieveUserQuotaSummary`锛夈€?
  This intentionally does not call `https://gemini.google.com/usage`, because Gemini web quota and Antigravity quota are separate.
  杩欓噷鏈夋剰涓嶈皟鐢?`https://gemini.google.com/usage`锛屽洜涓?Gemini 缃戦〉棰濆害鍜?Antigravity 棰濆害鏄袱濂椾笉鍚岀殑闄愬埗銆?
## CLI checks / 鍛戒护琛屾鏌?
Print current local usage summary without opening the tray app:
涓嶅惎鍔ㄦ墭鐩樼▼搴忥紝鐩存帴鍦ㄧ粓绔墦鍗板綋鍓嶇殑鏈湴浣跨敤鎽樿锛?
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -Dump
```

Create/default-check settings and print their path:
鍒涘缓/妫€鏌ラ粯璁ら厤缃枃浠剁殑鐘舵€侊紝骞惰緭鍑洪厤缃枃浠剁殑璺緞锛?
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -SelfTest
```

## Limits / 闄愰璇存槑

Claude Code has documented local session transcripts under `~/.claude/projects/`; Claude's `/usage` screen also uses local history for approximate plan usage. For Antigravity, when no query command is configured, this tool treats local JSON/JSONL token logs as the source of truth.
Claude Code 鍦?`~/.claude/projects/` 鐩綍涓嬪瓨鏈夋湰鍦颁細璇濊褰曪紱Claude 鐨勫懡浠よ `/usage` 鎸囦护涔熶細浣跨敤杩欎簺鏈湴鍘嗗彶璁板綍鏉ラ浼板椁愪娇鐢ㄦ儏鍐点€傚浜?Antigravity锛屽鏋滄湭閰嶇疆鏌ヨ鍛戒护锛岃宸ュ叿灏嗕互鏈湴鎵弿鍒扮殑 JSON/JSONL Token 鏃ュ織浣滀负鏁版嵁婧愩€?
For Codex / ChatGPT, the tool fetches real-time rolling usage directly from the cloud analytics page (`https://chatgpt.com/codex/cloud/settings/analytics#usage`) using an automated background query command that retrieves remaining limit percentages using the session token in your local `~/.codex/auth.json` config, bypassing local logs.
瀵逛簬 Codex / ChatGPT锛岃宸ュ叿閫氳繃鑷姩鍖栫殑鍚庡彴鏌ヨ鍛戒护锛屽埄鐢ㄦ偍鏈湴 `~/.codex/auth.json` 閰嶇疆涓殑浼氳瘽 Token锛岀洿鎺ヤ粠浜戠鍒嗘瀽椤甸潰 (`https://chatgpt.com/codex/cloud/settings/analytics#usage`) 鑾峰彇瀹炴椂鐨勬粴鍔ㄩ搴﹀墿浣欑櫨鍒嗘瘮锛屼粠鑰岃烦杩囨湰鍦版棩蹇楄В鏋愩€?
For Claude Code, the tool fetches real-time rolling usage statistics (corresponding to the web-based usage settings page `https://claude.ai/new#settings/usage`) using the OAuth access token stored in your local `~/.claude/.credentials.json` to query the `https://api.anthropic.com/api/oauth/usage` endpoint, bypassing local logs.
瀵逛簬 Claude Code锛岃宸ュ叿鍒╃敤鎮ㄦ湰鍦?`~/.claude/.credentials.json` 涓殑 OAuth 璁块棶 Token锛屽悜 `https://api.anthropic.com/api/oauth/usage` 鍙戣捣璇锋眰锛岃幏鍙栧疄鏃剁殑婊氬姩浣跨敤缁熻鏁版嵁锛堜笌缃戦〉鐗?`https://claude.ai/new#settings/usage` 鐨勯厤棰濋檺鍒朵竴鑷达級锛岃烦杩囨湰鍦版棩蹇楁枃浠舵壂鎻忋€?
For Antigravity, the tool fetches real-time rolling compute limits from the running Antigravity or Antigravity IDE local language server and currently reports the Gemini Models quota group only.
瀵逛簬 Antigravity锛岃宸ュ叿浼氫粠姝ｅ湪杩愯鐨?Antigravity 鎴?Antigravity IDE 鏈湴 language server 鑾峰彇瀹炴椂婊氬姩棰濆害锛岀洰鍓嶅彧缁熻鍏朵腑鐨?Gemini Models 閰嶉缁勩€?
When Antigravity is not running, TokenMonitor uses the last visible Antigravity quota and bucket reset times from cache until the next live query succeeds. Cached quota percentages are not estimated upward over time.
褰?Antigravity 鏈繍琛屾椂锛孴okenMonitor 浼氫娇鐢ㄧ紦瀛樹腑鐨勬渶鍚庝竴娆″彲瑙?Antigravity 棰濆害鍜屾《鎭㈠鏃堕棿锛岀洿鍒颁笅涓€娆″疄鏃舵煡璇㈡垚鍔熴€傜紦瀛橀搴︾櫨鍒嗘瘮涓嶄細闅忔椂闂村悜涓婁及绠椼€?
