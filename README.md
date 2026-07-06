# TokenMonitor

Windows taskbar tray monitor for local AI coding-tool token usage.
Windows 缁崵绮洪幍妯兼磸娑擃厾娈戦張顒€婀?AI 缂傛牜鈻煎銉ュ徔 Token 娴ｈ法鏁ら柌蹇曟磧鐟欏棗娅掗妴?
## What it does / 閸旂喕鍏橀悧瑙勨偓?
- Runs as a Windows tray icon.
  娴?Windows 缁崵绮洪幍妯兼磸閸ョ偓鐖ｉ惃鍕埌瀵繗绻嶇悰灞烩偓?- Shows an always-visible status strip docked above the Windows taskbar.
  閸?Windows 娴犺濮熼弽蹇庣瑐閺傝妯夌粈杞扮娑擃亜鐖堕弰鍓ф畱閻樿埖鈧焦娼敍鍦玹atus Strip閿涘鈧?- Shows a dashboard for Antigravity, Codex/ChatGPT, and Claude Code.
  娑?Antigravity閵嗕竼odex/ChatGPT 閸?Claude Code 閹绘劒绶垫稉鎾舵暏閻ㄥ嫭甯堕崚鍫曟桨閺夊尅绱橠ashboard閿涘鈧?- Calculates rolling 5-hour and 7-day usage from local JSON/JSONL logs (for providers without a query command configured, e.g. Antigravity).
  娴犲孩婀伴崷鎵畱 JSON/JSONL 閺冦儱绻旀稉顓☆吀缁?5 鐏忓繑妞傞崪?7 婢垛晜绮撮崝銊х崶閸欙絿娈戞担璺ㄦ暏闁插骏绱欓柅鍌滄暏娴滃孩婀柊宥囩枂 API 閺屻儴顕楅崨鎴掓姢閻?Provider閿涘奔绶ユ俊?Antigravity閿涘鈧?- Converts usage to remaining percentages using quotas that you configure.
  閺嶈宓侀幃銊╁帳缂冾喚娈戞０婵嗗閿涘湨uota閿涘绱濋懛顏勫З鐏忓棔濞囬悽銊╁櫤鏉烆剚宕叉稉鍝勫⒖娴ｆ瑧娅ㄩ崚鍡樼槷閵?- For providers with a query command configured (such as Antigravity, Codex/ChatGPT, and Claude Code), queries the relevant live usage endpoint directly, bypassing local log scanning.
  鐎甸€涚艾闁板秶鐤嗘禍鍡樼叀鐠囥垹鎳℃禒銈忕礄Command閿涘娈?Provider閿涘牅绶ユ俊?Antigravity閵嗕竼odex/ChatGPT 閸?Claude Code閿涘绱濋惄瀛樺复閺屻儴顕楃€电懓绨查惃鍕杽閺冨爼顤傛惔锔藉复閸欙綇绱濋獮鎯扮儲鏉╁洦婀伴崷鐗堟）韫囨鏋冩禒鑸靛閹诲繈鈧?- Stores settings in `%APPDATA%\TokenMonitor\settings.json`.
  鐠佸墽鐤嗙€涙ê鍋嶉崷?`%APPDATA%\TokenMonitor\settings.json`閵?- Stores the last visible Antigravity quota in `%APPDATA%\TokenMonitor\quota-cache.json`, so the tray can show the cached quota and reset time while Antigravity is closed.
  娴兼艾鐨㈤張鈧崥搴濈濞嗏€冲讲鐟欎胶娈?Antigravity 妫版繂瀹崇€涙ê鍋嶉崷?`%APPDATA%\TokenMonitor\quota-cache.json`閿涘苯娲滃?Antigravity 閸忔娊妫撮弮鑸靛閻╂ü绮涢崣顖涙▔缁€铏圭处鐎涙﹢顤傛惔锕€鎷伴幁銏狀槻閺冨爼妫块妴?
This is a local monitor and query tool. For providers without a query command configured, remaining quota is computed as:
閺堫剝钂嬫禒鑸垫Ц娑撯偓娑擃亝婀伴崷鎵磧鐟欏棗鎷伴弻銉嚄瀹搞儱鍙块妴鍌氼嚠娴滃孩婀柊宥囩枂閺屻儴顕楅崨鎴掓姢閻?Provider閿涘苯鍙鹃崜鈺€缍戦柊宥夘杺鐠侊紕鐣婚崗顒€绱℃稉鐚寸窗

```text
remaining % = max(0, quota - locally observed usage) / quota
```

For providers with a query command configured, it queries the official usage APIs in the background using your local credentials/session tokens to fetch real-time remaining quota percentages, skipping local calculations. If the command fails, it reports the error directly.
鐎甸€涚艾闁板秶鐤嗘禍鍡樼叀鐠囥垹鎳℃禒銈囨畱 Provider閿涘苯鐣犳导姘躬閸氬骸褰存担璺ㄦ暏閹劎娈戦張顒€婀撮崙顓熷祦/娴兼俺鐦?Token 閻╁瓨甯撮弻銉嚄鐎规ɑ鏌熼惃鍕▏閻劑鍣?API閿涘矁骞忛崣鏍х杽閺冨墎娈戦柊宥夘杺閸撯晙缍戦惂鎯у瀻濮ｆ棑绱濈捄瀹犵箖娴犺缍嶉張顒€婀寸拋锛勭暬閵嗗倸顩ч弸婊冩嚒娴犮倖澧界悰灞姐亼鐠愩儻绱濋崚娆戞纯閹恒儲濮ら崨濠囨晩鐠囶垬鈧?
## Run / 鏉╂劘顢?

From this folder:
閸︺劍顒濋惄顔肩秿娑撳澧界悰宀嬬窗

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\start-token-monitor.ps1
```

Double-click the tray icon or the status strip to open the dashboard. Right-click either one for Dashboard, Refresh, Settings, status strip visibility, and Exit.
閸欏苯鍤幍妯兼磸閸ョ偓鐖ｉ幋鏍Ц閹焦娼崣顖欎簰閹垫挸绱戦幒褍鍩楅棃銏℃緲閿涘湒ashboard閿涘鈧倸褰搁柨顔惧仯閸戣鐣犳禒顒€褰叉禒銉ヨ剨閸戦缚褰嶉崡鏇窗閹貉冨煑闂堛垺婢橀妴浣瑰閸斻劌鍩涢弬鑸偓浣筋啎缂冾喓鈧礁鍨忛幑銏㈠Ц閹焦娼弰楣冩娴犮儱寮烽柅鈧崙鎭掆偓?
By default it refreshes every 1 minute.
姒涙顓诲В?1 閸掑棝鎸撻崚閿嬫煀娑撯偓濞喡扳偓?
## Release and Build / 鍙戝竷涓庢瀯寤?

The compilation of `TokenMonitor.exe` is automated on GitHub Actions using `ps2exe` on Windows runners. We do not track or build the executable locally.
`TokenMonitor.exe` 鐨勭紪璇戝拰鍙戝竷杩囩▼宸插畬鍏ㄦ墭绠¤嚦 GitHub Actions锛堝湪 `windows-latest` 杩愯鍣ㄤ笂浣跨敤 `ps2exe` 缂栬瘧锛夛紝鏈湴涓嶅啀璺熻釜缂栬瘧鍑虹殑浜岃繘鍒舵枃浠躲€?

### How to trigger a new release / 濡備綍瑙﹀彂鏂扮増鏈彂甯?

Run the release script locally to automatically increment the version, commit, tag, and trigger the GitHub Actions build workflow:
鍦ㄦ湰鍦拌繍琛屽彂甯冭剼鏈紝瀹冨皢鑷姩閫掑鐗堟湰鍙枫€佹彁浜ゆ洿鏀广€佸垱寤?Git 鏍囩骞舵帹閫佸埌 GitHub 瑙﹀彂鑷姩鏋勫缓宸ヤ綔娴侊細

```powershell
.\release.ps1
```

Once triggered, GitHub Actions will:
- Check out the codebase
- Install the `ps2exe` tool
- Compile `bin/TokenMonitor.exe` using `.\build.ps1`
- Publish a new GitHub Release with the compiled binary attached as a release asset.

瑙﹀彂鍚庯紝GitHub Actions 浼氳嚜鍔ㄦ墽琛屼互涓嬫楠わ細
- 妫€鍑轰唬鐮佸簱
- 瀹夎 `ps2exe` 宸ュ叿
- 杩愯 `.\build.ps1` 缂栬瘧鍑?`bin/TokenMonitor.exe`
- 鍒涘缓鏂扮殑 GitHub Release锛屽苟灏嗙紪璇戝ソ鐨?`TokenMonitor.exe` 浣滀负鍙戝竷浜х墿涓婁紶銆?
## Configure quotas / 闁板秶鐤嗘０婵嗗

Open Settings from the tray menu.
娴犲孩澧惄妯垮綅閸楁洑鑵戦幍鎾崇磻 Settings閿涘牐顔曠純顕嗙礆閵?
- `5h quota`: token budget for the rolling 5-hour window.
  `5h quota`閿? 鐏忓繑妞傚姘З缁愭褰涢崘鍛畱 Token 闂勬劙顤傛０鍕暬閵?- `7d quota`: token budget for the rolling 7-day window.
  `7d quota`閿? 婢垛晪绱欏В蹇撴噯閿涘绮撮崝銊х崶閸欙絽鍞撮惃?Token 闂勬劙顤傛０鍕暬閵?- `Scan roots`: semicolon-separated files or folders to scan.
  `Scan roots`閿涙艾鍨庨崣鐑芥瀵偓閻ㄥ嫭婀伴崷鐗堟）韫囨澹傞幓蹇旂壌閻╊喖缍嶉幋鏍ㄦ瀮娴犳儼鐭惧鍕┾偓?- `File patterns`: usually `*.jsonl; *.json`.
  `File patterns`閿涙碍澹傞幓蹇曟畱閺傚洣娆㈢猾璇茬€烽崠褰掑帳閿涘矂鈧艾鐖堕弰?`*.jsonl; *.json`閵?- `Max file MB`: logs larger than this are skipped during tray refresh.
  `Max file MB`閿涙碍澧惄妯哄煕閺傜増妞傞敍宀冪Т閸戦缚顕氭径褍鐨惃鍕）韫囨鏋冩禒璺虹殺鐞氼偉鐑︽潻鍥︾瑝鏉╂稖顢戦幍顐ｅ伎閵?- `Command JSON source`: optional PowerShell command. If set, it must print JSON and can override locally scanned values.
  `Command JSON source`閿涙艾褰查柅澶屾畱 PowerShell 閺屻儴顕楅崨鎴掓姢閵嗗倸顩ч弸婊嗩啎缂冾喕绨″銈呮嚒娴犮倧绱濈€瑰啫绻€妞ゆ槒绶崙?JSON 閺嶇厧绱￠惃鍕敶鐎圭櫢绱濋悽銊︽降鐟曞棛娲婇幋鏍ㄦ禌娴狅絾婀伴崷鐗堝閹诲繗顓哥粻妤€鍤惃鍕殶閸婄鈧?- `0` quota means unknown, so the percentage is displayed as `n/a`.
  闂勬劙顤傜拋鍙ヨ礋 `0` 娴狅綀銆冮柊宥夘杺閺堫亞鐓￠敍宀€娅ㄩ崚鍡樼槷鐏忓棙妯夌粈杞拌礋 `n/a`閵?
Command JSON output can use any of these fields:
閼奉亜鐣炬稊澶婃嚒娴犮倛绶崙铏规畱 JSON 閸欘垯浜掗崠鍛儓娴犮儰绗呮禒璁崇鐎涙顔岄敍?
```json
{
  "fiveHourUsed": 123456,
  "weeklyUsed": 456789,
  "fiveHourRemainingPercent": 87.5,
  "weeklyRemainingPercent": 64.0
}
```

You can also emit `fiveHourUsedPercent` and `weeklyUsedPercent`; the app will convert them to remaining percentages.
閹劋绡冮崣顖欎簰鏉堟挸鍤?`fiveHourUsedPercent`閿?鐏忓繑妞傚鑼暏閻ф儳鍨庡В鏃撶礆閸?`weeklyUsedPercent`閿涘牊鐦￠崨銊ュ嚒閻劎娅ㄩ崚鍡樼槷閿涘绱濇惔鏃傛暏缁嬪绨导姘冲殰閸斻劌鐨㈤崗鎯版祮閹诡澀璐熼崜鈺€缍戦惂鎯у瀻濮ｆ柣鈧?
Default scan roots:
姒涙顓婚張顒€婀撮弮銉ョ箶閹殿偅寮块弽鍦窗瑜版洩绱?

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

### Credentials setup / 閸戭厽宓佺拋鍓х枂

For providers using query commands, you must configure local authorization files:
鐎甸€涚艾娴ｈ法鏁ら弻銉嚄閸涙垝鎶ら敍鍦昽mmand閿涘濯洪崣鏍х暭閺傝鏆熼幑顔炬畱 Provider閿涘本鍋嶉棁鈧憰渚€鍘ょ純顔芥拱閸︽壆娈戦幒鍫熸綀/閸戭厽宓侀弬鍥︽閿?
- **Codex / ChatGPT**: Automatically created at `~/.codex/auth.json` when you log in through the Codex CLI.
  **Codex / ChatGPT**閿涙艾缍嬮幃銊ユ躬缂佸牏顏稉顓濆▏閻?Codex CLI 閻ц缍嶉崥搴礉娴兼俺鍤滈崝銊ユ躬 `~/.codex/auth.json` 閻㈢喐鍨氱拠銉︽瀮娴犺翰鈧?- **Claude Code**: Automatically created at `~/.claude/.credentials.json` when you log in through the Claude CLI.
  **Claude Code**閿涙艾缍嬮幃銊ユ躬缂佸牏顏稉顓濆▏閻?Claude CLI 閻ц缍嶉崥搴礉娴兼俺鍤滈崝銊ユ躬 `~/.claude/.credentials.json` 閻㈢喐鍨氱拠銉ュ殶閹诡喓鈧?- **Antigravity**: No Gemini web cookies are required. Start Antigravity or Antigravity IDE and TokenMonitor queries Antigravity's local language-server RPC (`RetrieveUserQuotaSummary`) using the CSRF token and localhost port written to `%APPDATA%\Antigravity\logs\main.log` or `%APPDATA%\Antigravity IDE\logs\**\ls-main.log`.
  **Antigravity**閿涙矮绗夐棁鈧憰?Gemini 缂冩垿銆?Cookie閵嗗倸鎯庨崝?Antigravity 閹?Antigravity IDE 閸氬函绱漈okenMonitor 娴兼俺顕伴崣?`%APPDATA%\Antigravity\logs\main.log` 閹?`%APPDATA%\Antigravity IDE\logs\**\ls-main.log` 娑擃厾娈戦張顒€婀寸粩顖氬經閸?CSRF token閿涘苯鑻熺拫鍐暏 Antigravity 閺堫剙婀?language-server RPC閿涘潉RetrieveUserQuotaSummary`閿涘鈧?
  This intentionally does not call `https://gemini.google.com/usage`, because Gemini web quota and Antigravity quota are separate.
  鏉╂瑩鍣烽張澶嬪壈娑撳秷鐨熼悽?`https://gemini.google.com/usage`閿涘苯娲滄稉?Gemini 缂冩垿銆夋０婵嗗閸?Antigravity 妫版繂瀹抽弰顖欒⒈婵傛ぞ绗夐崥宀€娈戦梽鎰煑閵?
## CLI checks / 閸涙垝鎶ょ悰灞绢梾閺?
Print current local usage summary without opening the tray app:
娑撳秴鎯庨崝銊﹀閻╂鈻兼惔蹇ョ礉閻╁瓨甯撮崷銊х矒缁旑垱澧﹂崡鏉跨秼閸撳秶娈戦張顒€婀存担璺ㄦ暏閹芥顩﹂敍?
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -Dump
```

Create/default-check settings and print their path:
閸掓稑缂?濡偓閺屻儵绮拋銈夊帳缂冾喗鏋冩禒鍓佹畱閻樿埖鈧緤绱濋獮鎯扮翻閸戞椽鍘ょ純顔芥瀮娴犲墎娈戠捄顖氱窞閿?
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\TokenMonitor.ps1 -SelfTest
```

## Limits / 闂勬劙顤傜拠瀛樻

Claude Code has documented local session transcripts under `~/.claude/projects/`; Claude's `/usage` screen also uses local history for approximate plan usage. For Antigravity, when no query command is configured, this tool treats local JSON/JSONL token logs as the source of truth.
Claude Code 閸?`~/.claude/projects/` 閻╊喖缍嶆稉瀣摠閺堝婀伴崷棰佺窗鐠囨繆顔囪ぐ鏇幢Claude 閻ㄥ嫬鎳℃禒銈堫攽 `/usage` 閹稿洣鎶ゆ稊鐔剁窗娴ｈ法鏁ゆ潻娆庣昂閺堫剙婀撮崢鍡楀蕉鐠佹澘缍嶉弶銉╊暕娴兼澘顨滄鎰▏閻劍鍎忛崘鐐光偓鍌氼嚠娴?Antigravity閿涘苯顩ч弸婊勬弓闁板秶鐤嗛弻銉嚄閸涙垝鎶ら敍宀冾嚉瀹搞儱鍙跨亸鍡曚簰閺堫剙婀撮幍顐ｅ伎閸掓壆娈?JSON/JSONL Token 閺冦儱绻旀担婊€璐熼弫鐗堝祦濠ф劑鈧?
For Codex / ChatGPT, the tool fetches real-time rolling usage directly from the cloud analytics page (`https://chatgpt.com/codex/cloud/settings/analytics#usage`) using an automated background query command that retrieves remaining limit percentages using the session token in your local `~/.codex/auth.json` config, bypassing local logs.
鐎甸€涚艾 Codex / ChatGPT閿涘矁顕氬銉ュ徔闁俺绻冮懛顏勫З閸栨牜娈戦崥搴″酱閺屻儴顕楅崨鎴掓姢閿涘苯鍩勯悽銊﹀亶閺堫剙婀?`~/.codex/auth.json` 闁板秶鐤嗘稉顓犳畱娴兼俺鐦?Token閿涘瞼娲块幒銉ょ矤娴滄垹顏崚鍡樼€芥い鐢告桨 (`https://chatgpt.com/codex/cloud/settings/analytics#usage`) 閼惧嘲褰囩€圭偞妞傞惃鍕泊閸斻劑顤傛惔锕€澧挎担娆戞閸掑棙鐦敍灞肩矤閼板矁鐑︽潻鍥ㄦ拱閸︾増妫╄箛妤勑掗弸鎰┾偓?
For Claude Code, the tool fetches real-time rolling usage statistics (corresponding to the web-based usage settings page `https://claude.ai/new#settings/usage`) using the OAuth access token stored in your local `~/.claude/.credentials.json` to query the `https://api.anthropic.com/api/oauth/usage` endpoint, bypassing local logs.
鐎甸€涚艾 Claude Code閿涘矁顕氬銉ュ徔閸掆晝鏁ら幃銊︽拱閸?`~/.claude/.credentials.json` 娑擃厾娈?OAuth 鐠佸潡妫?Token閿涘苯鎮?`https://api.anthropic.com/api/oauth/usage` 閸欐垼鎹ｇ拠閿嬬湴閿涘矁骞忛崣鏍х杽閺冨墎娈戝姘З娴ｈ法鏁ょ紒鐔活吀閺佺増宓侀敍鍫滅瑢缂冩垿銆夐悧?`https://claude.ai/new#settings/usage` 閻ㄥ嫰鍘ゆ０婵嬫閸掓湹绔撮懛杈剧礆閿涘矁鐑︽潻鍥ㄦ拱閸︾増妫╄箛妤佹瀮娴犺埖澹傞幓蹇嬧偓?
For Antigravity, the tool fetches real-time rolling compute limits from the running Antigravity or Antigravity IDE local language server and currently reports the Gemini Models quota group only.
鐎甸€涚艾 Antigravity閿涘矁顕氬銉ュ徔娴兼矮绮犲锝呮躬鏉╂劘顢戦惃?Antigravity 閹?Antigravity IDE 閺堫剙婀?language server 閼惧嘲褰囩€圭偞妞傚姘З妫版繂瀹抽敍宀€娲伴崜宥呭涧缂佺喕顓搁崗鏈佃厬閻?Gemini Models 闁板秹顤傜紒鍕┾偓?
When Antigravity is not running, TokenMonitor uses the last visible Antigravity quota and bucket reset times from cache until the next live query succeeds. Cached quota percentages are not estimated upward over time.
瑜?Antigravity 閺堫亣绻嶇悰灞炬閿涘okenMonitor 娴兼矮濞囬悽銊х处鐎涙ü鑵戦惃鍕付閸氬簼绔村▎鈥冲讲鐟?Antigravity 妫版繂瀹抽崪灞俱€婇幁銏狀槻閺冨爼妫块敍宀€娲块崚棰佺瑓娑撯偓濞嗏€崇杽閺冭埖鐓＄拠銏″灇閸旂喆鈧倻绱︾€涙﹢顤傛惔锔炬閸掑棙鐦稉宥勭窗闂呭繑妞傞梻鏉戞倻娑撳﹣鍙婄粻妞尖偓?



