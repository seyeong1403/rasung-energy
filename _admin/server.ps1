<#
  라성에너지(주) — 홈페이지 관리자 로컬 서버
  ---------------------------------------------------------------
  실행 : _admin\관리자 실행.cmd   (또는)  powershell -File _admin\server.ps1
  주소 : http://localhost:8881/admin/   ← 관리자
         http://localhost:8881/         ← 실제 사이트(미리보기)

  이 서버는 내 PC 안에서만 동작한다. 외부에서는 접속할 수 없다.
  배포 폴더에는 _admin 을 포함하지 않는다.

  외부에 잠깐 보여줄 때는 _admin\외부공유 실행.cmd 를 쓴다.
      powershell -File _admin\server.ps1 -Password "원하는비번"
  아이디는 admin 이다. 비밀번호를 안 주면 로그인 없이 열린다.

  [중요] 이 사이트의 HTML 은 UTF-8 BOM 이고 줄바꿈이 CRLF/LF 섞여 있다.
  그래서 저장할 때 파일 전체를 다시 쓰지 않고, 관리자 화면이
  "원본 문자열의 해당 구간만" 바꿔서 보낸 결과를 그대로 기록한다.
  (BOM 유무만 원본에 맞춰 준다)
#>
param(
	[int]$Port = 8881,
	[string]$Root = '',
	[switch]$NoBrowser,
	[switch]$Open          # 외부 공유용. 다른 PC에서도 들어올 수 있게 연다.
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Web
try { Add-Type -AssemblyName System.Drawing } catch {}

# ---------- 경로 ----------
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
$AdminDir = Join-Path $Root '_admin'
$UiDir = Join-Path $AdminDir 'ui'
$DataDir = Join-Path $AdminDir 'data'
$BackupDir = Join-Path $AdminDir 'backups'
$UploadDir = Join-Path $Root 'files'
$BoardPs = Join-Path $AdminDir 'board.ps1'

foreach ($d in @($DataDir, $BackupDir)) {
	if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)

# ---------- 계정 ----------
# 아이디 · 비밀번호로 들어온다. 비밀번호는 되돌릴 수 없는 형태로 저장한다.
$UsersFile = Join-Path $DataDir 'users.json'
# 로그인한 사람 목록. 서버를 끄면 사라진다. (토큰 → 아이디)
$Sessions = @{}
# 비밀번호를 계속 찍어 보는 것을 막는다. (접속지 → 실패 횟수 · 시각)
$LoginFails = @{}

function New-PassHash($pass) {
	$salt = New-Object byte[] 16
	$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
	$rng.GetBytes($salt)
	$k = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 120000)
	$hash = $k.GetBytes(32)
	return 'pbkdf2:120000:' + [Convert]::ToBase64String($salt) + ':' + [Convert]::ToBase64String($hash)
}
function Test-PassHash($pass, $stored) {
	try {
		$p = ([string]$stored).Split(':')
		if ($p.Count -ne 4 -or $p[0] -ne 'pbkdf2') { return $false }
		$iter = [int]$p[1]
		$salt = [Convert]::FromBase64String($p[2])
		$want = [Convert]::FromBase64String($p[3])
		$k = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, $iter)
		$got = $k.GetBytes($want.Length)
		$diff = 0
		for ($i = 0; $i -lt $want.Length; $i++) { $diff = $diff -bor ($want[$i] -bxor $got[$i]) }
		return ($diff -eq 0)
	} catch { return $false }
}
function Get-Users {
	if (-not (Test-Path -LiteralPath $UsersFile -PathType Leaf)) { return @() }
	$raw = ([System.IO.File]::ReadAllText($UsersFile, [System.Text.Encoding]::UTF8)).Trim()
	if (-not $raw) { return @() }
	try { $parsed = ConvertFrom-Json $raw } catch { return @() }
	return @($parsed)
}
function Save-Users($users) {
	$json = ConvertTo-Json @($users) -Depth 10
	[System.IO.File]::WriteAllText($UsersFile, $json, (New-Object System.Text.UTF8Encoding($false)))
}
function Get-UserById($id) {
	foreach ($u in (Get-Users)) { if ($u.id -ceq $id) { return $u } }
	return $null
}
function Test-NeedSetup { return ((Get-Users).Count -eq 0) }

function Get-GatePage($mode, $msg) {
	# mode : 'login' 또는 'setup'
	$warn = ''
	if ($msg) { $warn = '<p class="err">' + $msg + '</p>' }

	$title = '라성에너지(주) 홈페이지 관리자'
	$head = '라성에너지(주)<span>홈페이지 관리자</span>'
	$sub = '아이디와 비밀번호를 입력해 주세요.'
	$foot = '담당자에게 받은 아이디와 비밀번호가 필요합니다.'
	$action = '/login'
	$fields = @"
  <label for="u">아이디</label>
  <input id="u" name="user" autocomplete="username" autofocus required>
  <label for="p">비밀번호</label>
  <input id="p" name="pass" type="password" autocomplete="current-password" required>
  <button type="submit">들어가기</button>
"@
	if ($mode -eq 'setup') {
		$title = '관리자 계정 만들기'
		$head = '관리자 계정 만들기<span>처음 한 번만 나오는 화면입니다</span>'
		$sub = '앞으로 홈페이지를 관리할 아이디와 비밀번호를 정해 주세요. 이 화면은 계정을 만들고 나면 다시 열리지 않습니다.'
		$foot = '직원용 계정은 나중에 관리자 화면의 「접속 계정」에서 추가할 수 있습니다.'
		$action = '/setup'
		$fields = @"
  <label for="u">아이디 <em>영문 · 숫자 3~20자</em></label>
  <input id="u" name="user" autofocus required placeholder="예) lasung">
  <label for="n">이름 <em>화면에 표시됩니다</em></label>
  <input id="n" name="name" placeholder="예) 홍길동">
  <label for="p">비밀번호 <em>8자 이상</em></label>
  <input id="p" name="pass" type="password" required>
  <label for="p2">비밀번호 확인</label>
  <input id="p2" name="pass2" type="password" required>
  <button type="submit">계정 만들고 시작하기</button>
"@
	}

	return @"
<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>$title</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{min-height:100vh;display:flex;align-items:center;justify-content:center;
 background:#0C2233;font:16px/1.7 'Pretendard','Malgun Gothic',system-ui,sans-serif;word-break:keep-all;padding:24px;color:#16202A}
.box{width:100%;max-width:420px;background:#fff;border-radius:14px;padding:40px 34px;
 box-shadow:0 20px 60px rgba(0,0,0,.35)}
h1{font-size:20px;font-weight:700;color:#0C2233;letter-spacing:-.02em;line-height:1.4}
h1 span{display:block;font-size:14px;font-weight:500;color:#0087BC;margin-top:2px}
.sub{margin:14px 0 26px;font-size:14px;color:#57606B}
label{display:block;font-size:14px;font-weight:700;color:#334155;margin:0 0 7px}
label em{font-style:normal;font-weight:500;color:#8A929B;font-size:13px;margin-left:6px}
input{width:100%;padding:12px 14px;font-size:16px;border:1px solid #CFD6DD;border-radius:8px;
 margin-bottom:18px;font-family:inherit;color:inherit}
input:focus{outline:none;border-color:#0087BC;box-shadow:0 0 0 3px rgba(0,135,188,.16)}
button{width:100%;padding:13px;font-size:16px;font-weight:700;color:#fff;background:#0087BC;
 border:0;border-radius:8px;cursor:pointer;font-family:inherit}
button:hover{background:#0076A4}
.err{margin:0 0 18px;padding:11px 14px;background:#FEF3F2;border:1px solid #FDA29B;
 border-radius:8px;color:#B42318;font-size:14px}
.foot{margin:24px 0 0;font-size:13px;color:#98A2B3;text-align:center;line-height:1.6}
</style></head><body>
<div class="box">
 <h1>$head</h1>
 <p class="sub">$sub</p>
 $warn
 <form method="post" action="$action" autocomplete="on">
$fields
 </form>
 <p class="foot">$foot</p>
</div></body></html>
"@
}

# ---------- 파일 읽기 / 쓰기 ----------
function Read-TextFile($path) {
	# UTF8 로 읽으면 BOM 은 자동으로 걷힌다.
	return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}
function Test-Bom($path) {
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
	$head = New-Object byte[] 3
	$fs = [System.IO.File]::OpenRead($path)
	try { $n = $fs.Read($head, 0, 3) } finally { $fs.Dispose() }
	return ($n -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)
}
function Write-TextFile($path, $text) {
	$dir = Split-Path $path -Parent
	if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
	# 줄바꿈은 손대지 않는다. BOM 유무만 원본에 맞춘다.
	$enc = $Utf8NoBom
	if (Test-Bom $path) { $enc = $Utf8Bom }
	[System.IO.File]::WriteAllText($path, $text, $enc)
}
function Resolve-Safe($rel) {
	if (-not $rel) { throw '경로가 비어 있습니다.' }
	$rel = ($rel -replace '\\', '/').TrimStart('/')
	if ($rel -match '(^|/)\.\.(/|$)') { throw "허용되지 않는 경로입니다 : $rel" }
	$full = [System.IO.Path]::GetFullPath((Join-Path $Root ($rel -replace '/', '\')))
	if (-not $full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) { throw "작업 폴더 밖입니다 : $rel" }
	return $full
}
function Get-Stamp { return (Get-Date).ToString('yyyyMMdd-HHmmss') }

function Backup-File($rel) {
	$full = Resolve-Safe $rel
	if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return '' }
	$safeName = ($rel -replace '[\\/]', '__')
	$dest = Join-Path $BackupDir ((Get-Stamp) + '__' + $safeName)
	Copy-Item -LiteralPath $full -Destination $dest -Force
	return (Split-Path $dest -Leaf)
}

# 항상 배열로 돌려준다. (ConvertFrom-Json 결과를 바로 @() 로 감싸면 배열 전체가 원소 1개가 된다)
function Read-JsonArray($path) {
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
	$raw = (Read-TextFile $path).Trim()
	if (-not $raw) { return @() }
	try { $parsed = ConvertFrom-Json $raw } catch { return @() }
	return @($parsed)
}
function Save-Json($path, $obj) {
	$json = ConvertTo-Json $obj -Depth 20
	[System.IO.File]::WriteAllText($path, $json, $Utf8NoBom)
}

# ---------- 페이지 목록 ----------
# 이 사이트는 루트의 HTML 파일이 곧 페이지다. (조각 · 빌드 구조가 없다)
$PAGE_DEFS = @(
	@('index.html', '메인 (홈)', '메인'),
	@('village-alert.html', '마을재난비상경보시스템', '재난방재시스템'),
	@('quake-alert.html', '지진경보시스템', '재난방재시스템'),
	@('quake-evac.html', '지진대피시스템', '재난방재시스템'),
	@('ai-watch.html', 'AI감시시스템', '재난방재시스템'),
	@('social-disaster.html', '사회재난시스템', '재난방재시스템'),
	@('rescue-equipment.html', '재난구조장비', '재난구조장비'),
	@('rescue-robot.html', '재난구조로봇', '재난구조장비'),
	@('edu-system.html', '재난안전교육시스템', '재난안전교육'),
	@('edu-quake.html', '지진안전교육프로그램', '재난안전교육'),
	@('edu-fire.html', '화재안전교육프로그램', '재난안전교육'),
	@('forest.html', '산림사업', '산림사업'),
	@('about.html', '회사소개', '회사소개'),
	@('notice.html', '공지사항', '고객센터'),
	@('info.html', '자료실', '고객센터'),
	@('qa.html', '온라인문의', '고객센터'),
	@('as.html', 'A/S문의', '고객센터')
)
function Get-PageList {
	$list = New-Object System.Collections.ArrayList
	foreach ($d in $PAGE_DEFS) {
		$file = $d[0]
		if (-not (Test-Path -LiteralPath (Join-Path $Root $file))) { continue }
		[void]$list.Add([ordered]@{
				id     = [System.IO.Path]::GetFileNameWithoutExtension($file)
				source = $file
				view   = $file
				title  = $d[1]
				group  = $d[2]
			})
	}
	return $list.ToArray()
}
function Get-PageById($id) {
	foreach ($p in (Get-PageList)) { if ($p.id -eq $id) { return $p } }
	return $null
}

# ---------- 이미지 ----------
function Get-ImageSize($path) {
	$res = [ordered]@{ w = 0; h = 0 }
	try {
		$fs = [System.IO.File]::Open($path, 'Open', 'Read', 'Read')
		try {
			$img = [System.Drawing.Image]::FromStream($fs, $false, $false)
			$res.w = $img.Width; $res.h = $img.Height
			$img.Dispose()
		} finally { $fs.Dispose() }
	} catch {}
	return $res
}
# assets/sub/** 와 assets/cases 의 사진을 모은다. (로고 · SVG 아이콘은 제외)
function Get-MediaList {
	$out = New-Object System.Collections.ArrayList
	$dirs = New-Object System.Collections.ArrayList
	$subRoot = Join-Path $Root 'assets\sub'
	if (Test-Path -LiteralPath $subRoot) {
		foreach ($d in (Get-ChildItem $subRoot -Directory | Sort-Object Name)) { [void]$dirs.Add($d.FullName) }
	}
	$caseDir = Join-Path $Root 'assets\cases'
	if (Test-Path -LiteralPath $caseDir) { [void]$dirs.Add($caseDir) }

	foreach ($dir in $dirs) {
		foreach ($f in (Get-ChildItem $dir -File | Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|gif|webp)$' } | Sort-Object Name)) {
			$rel = $f.FullName.Substring($Root.Length + 1) -replace '\\', '/'
			$sz = Get-ImageSize $f.FullName
			[void]$out.Add([ordered]@{
					name   = $f.Name
					path   = $rel
					folder = (Split-Path $dir -Leaf)
					size   = $f.Length
					kb     = [math]::Round($f.Length / 1KB)
					w      = $sz.w
					h      = $sz.h
					mtime  = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
				})
		}
	}
	return , $out.ToArray()
}

# ---------- 회사 정보 (모든 페이지 공통) ----------
# 헤더 · 푸터는 17개 파일에 그대로 복사되어 있다.
# 그래서 값 하나를 고치면 전체 파일에서 같이 바꿔 준다.
$COMPANY_FIELDS = @(
	[ordered]@{ key = 'tel'; label = '대표 전화'; note = '상단 띠 · 푸터 · 문의 안내에 함께 쓰입니다'; pattern = '054-\d{3}-\d{4}' },
	[ordered]@{ key = 'fax'; label = '팩스'; note = ''; pattern = 'F\. (054-\d{3}-\d{4})' },
	[ordered]@{ key = 'addr'; label = '주소'; note = '푸터와 회사소개 오시는 길에 쓰입니다'; pattern = '주소 : ([^<]+)<br>' },
	[ordered]@{ key = 'biz'; label = '사업자등록번호'; note = ''; pattern = '사업자등록번호 : ([\d-]+)' },
	[ordered]@{ key = 'email'; label = '이메일'; note = ''; pattern = '[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' },
	[ordered]@{ key = 'slogan'; label = '상단 띠 문구'; note = '모든 페이지 맨 위 가로 띠'; pattern = '<div class="tb-left">([^<]*)</div>' },
	[ordered]@{ key = 'copy'; label = '저작권 표기'; note = '푸터 맨 아래'; pattern = '<div>(Copyright[^<]*)</div>' }
)
function Get-CompanyInfo {
	$src = Read-TextFile (Join-Path $Root 'index.html')
	$out = New-Object System.Collections.ArrayList
	foreach ($f in $COMPANY_FIELDS) {
		$m = [regex]::Match($src, $f.pattern)
		$val = ''
		if ($m.Success) {
			if ($m.Groups.Count -gt 1 -and $m.Groups[1].Success) { $val = $m.Groups[1].Value } else { $val = $m.Value }
		}
		# 몇 개 파일에 들어 있는지 세어 둔다 (바꿀 때 몇 곳이 영향받는지 보여주기 위함)
		$hit = 0
		if ($val) {
			foreach ($p in (Get-PageList)) {
				$t = Read-TextFile (Join-Path $Root $p.source)
				if ($t.Contains($val)) { $hit++ }
			}
		}
		[void]$out.Add([ordered]@{
				key = $f.key; label = $f.label; note = $f.note; value = $val; pages = $hit
			})
	}
	return , $out.ToArray()
}
function Set-CompanyInfo($items) {
	$changes = @()
	foreach ($it in @($items)) {
		$old = [string]$it.old
		$new = [string]$it.new
		if (-not $old -or $old -eq $new) { continue }
		$changes += , @($old, $new)
	}
	if ($changes.Count -eq 0) { return [ordered]@{ files = 0; hits = 0 } }

	$files = 0; $hits = 0
	foreach ($p in (Get-PageList)) {
		$full = Join-Path $Root $p.source
		$src = Read-TextFile $full
		$new = $src
		foreach ($c in $changes) {
			if ($new.Contains($c[0])) {
				$cnt = ([regex]::Matches($new, [regex]::Escape($c[0]))).Count
				$new = $new.Replace($c[0], $c[1])
				$hits += $cnt
			}
		}
		if ($new -ne $src) {
			Backup-File $p.source | Out-Null
			Write-TextFile $full $new
			$files++
		}
	}
	return [ordered]@{ files = $files; hits = $hits }
}

# ---------- 게시판 생성기 ----------
function Invoke-BoardBuild {
	if (-not (Test-Path -LiteralPath $BoardPs)) { return '(board.ps1 없음)' }
	$log = & $BoardPs -Root $Root 2>&1 | Out-String
	return $log
}

# ---------- MIME ----------
$mime = @{
	'.html' = 'text/html; charset=utf-8'; '.htm' = 'text/html; charset=utf-8'
	'.css' = 'text/css; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
	'.json' = 'application/json; charset=utf-8'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'
	'.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp'
	'.mp4' = 'video/mp4'; '.ico' = 'image/x-icon'; '.woff' = 'font/woff'; '.woff2' = 'font/woff2'
	'.ttf' = 'font/ttf'; '.otf' = 'font/otf'; '.pdf' = 'application/pdf'; '.txt' = 'text/plain; charset=utf-8'
	'.zip' = 'application/zip'; '.xlsx' = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
	'.docx' = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
	'.hwp' = 'application/x-hwp'; '.csv' = 'text/csv; charset=utf-8'
}

# ---------- 응답 ----------
function Send-Bytes($ctx, [byte[]]$bytes, $type, $code) {
	$ctx.Response.StatusCode = $code
	$ctx.Response.ContentType = $type
	$ctx.Response.Headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
	$ctx.Response.Headers['Pragma'] = 'no-cache'
	$ctx.Response.Headers['Expires'] = '0'
	$ctx.Response.ContentLength64 = $bytes.Length
	$ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}
function Send-Json($ctx, $obj, $code = 200) {
	$json = ConvertTo-Json $obj -Depth 25
	Send-Bytes $ctx ([System.Text.Encoding]::UTF8.GetBytes($json)) 'application/json; charset=utf-8' $code
}
function Send-Text($ctx, $text, $type = 'text/plain; charset=utf-8', $code = 200) {
	Send-Bytes $ctx ([System.Text.Encoding]::UTF8.GetBytes($text)) $type $code
}
function Send-FileOnDisk($ctx, $file) {
	$ext = [System.IO.Path]::GetExtension($file).ToLower()
	$ct = $mime[$ext]; if (-not $ct) { $ct = 'application/octet-stream' }
	Send-Bytes $ctx ([System.IO.File]::ReadAllBytes($file)) $ct 200
}
function Get-Body($ctx) {
	$sr = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
	$txt = $sr.ReadToEnd()
	$sr.Close()
	if (-not $txt) { return $null }
	return (ConvertFrom-Json $txt)
}

# ---------- 서버 시작 ----------
function Test-AdminAlive($p) {
	try {
		$req = [System.Net.WebRequest]::Create("http://localhost:$p/api/ping")
		$req.Timeout = 1200
		$res = $req.GetResponse()
		$txt = (New-Object System.IO.StreamReader($res.GetResponseStream())).ReadToEnd()
		$res.Close()
		return ($txt -match '"ok"')
	} catch { return $false }
}

if (Test-AdminAlive $Port) {
	Write-Host ""
	Write-Host "  관리자가 이미 실행 중입니다. 그 창을 그대로 쓰시면 됩니다." -ForegroundColor Yellow
	Write-Host "  주소 : http://localhost:$Port/admin/" -ForegroundColor White
	Write-Host ""
	if (-not $NoBrowser) { Start-Process "http://localhost:$Port/admin/" | Out-Null }
	Start-Sleep -Seconds 4
	exit 0
}

# 포트가 막혀 있으면 다음 번호로 자동으로 옮겨 간다.
$listener = $null
$startPort = $Port
foreach ($try in $startPort..($startPort + 9)) {
	$l = New-Object System.Net.HttpListener
	$l.Prefixes.Add("http://localhost:$try/")
	$l.Prefixes.Add("http://127.0.0.1:$try/")
	try {
		$l.Start()
		$listener = $l
		$Port = $try
		break
	} catch {
		try { $l.Close() } catch {}
	}
}
if (-not $listener) {
	Write-Host ""
	Write-Host "  [오류] $startPort ~ $($startPort + 9) 번 포트를 모두 열 수 없습니다." -ForegroundColor Red
	Write-Host "  PC를 다시 시작한 뒤 실행해 보세요." -ForegroundColor Yellow
	Write-Host ""
	Read-Host "  엔터를 누르면 닫힙니다"
	exit 1
}
if ($Port -ne $startPort) {
	Write-Host ""
	Write-Host "  ※ $startPort 번 포트가 사용 중이라 $Port 번으로 열었습니다." -ForegroundColor Yellow
}

$adminUrl = "http://localhost:$Port/admin/"
Write-Host ""
Write-Host "  ┌────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │  라성에너지(주) 홈페이지 관리자                  │" -ForegroundColor Cyan
Write-Host "  └────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
Write-Host "   관리자   $adminUrl" -ForegroundColor White
Write-Host "   사이트   http://localhost:$Port/" -ForegroundColor Gray
Write-Host "   폴더     $Root" -ForegroundColor DarkGray
if (Test-NeedSetup) {
	Write-Host ""
	Write-Host "   처음 실행입니다. 화면에서 아이디와 비밀번호를 정해 주세요." -ForegroundColor Yellow
} else {
	Write-Host "   계정     " -NoNewline -ForegroundColor DarkGray
	Write-Host (((Get-Users) | ForEach-Object { $_.id }) -join ', ') -ForegroundColor Gray
}
Write-Host ""
Write-Host "   ※ 이 창을 닫으면 관리자가 종료됩니다." -ForegroundColor DarkYellow
Write-Host ""

if (-not $NoBrowser) { Start-Process $adminUrl | Out-Null }

# ---------- 요청 루프 ----------
while ($listener.IsListening) {
	$ctx = $null
	try { $ctx = $listener.GetContext() } catch { break }
	if (-not $ctx) { continue }

	try {
		$req = $ctx.Request
		$path = [System.Web.HttpUtility]::UrlDecode($req.Url.AbsolutePath)
		$q = $req.QueryString
		$method = $req.HttpMethod

		$ctx.Response.Headers['Access-Control-Allow-Origin'] = '*'
		$ctx.Response.Headers['Access-Control-Allow-Headers'] = 'Content-Type'
		if ($method -eq 'OPTIONS') { $ctx.Response.StatusCode = 204; $ctx.Response.OutputStream.Close(); continue }

		# ---------- 로그인 ----------
		# 방문자 문의 접수와 사이트 화면은 로그인 없이 열어 둔다.
		$isSiteFile = -not ($path.StartsWith('/admin') -or $path.StartsWith('/api/') -or $path -eq '/login' -or $path -eq '/setup' -or $path -eq '/logout')
		$isPublicApi = ($path -eq '/api/inquiry' -or $path -eq '/api/ping')

		$me = $null
		$ck = $req.Headers['Cookie']
		if ($ck -and $ck -match 'lsadmin=([0-9a-f]{32})') {
			$tok = $Matches[1]
			if ($Sessions.ContainsKey($tok)) { $me = Get-UserById $Sessions[$tok] }
		}

		if (-not $isSiteFile -and -not $isPublicApi) {

			# --- 계정 만들기 (처음 한 번) ---
			if (Test-NeedSetup) {
				if ($path -eq '/setup' -and $method -eq 'POST') {
					$rawForm = ''
					try {
						$sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
						$rawForm = $sr.ReadToEnd()
					} catch {}
					$form = [System.Web.HttpUtility]::ParseQueryString($rawForm)
					$nid = ([string]$form['user']).Trim()
					$nnm = ([string]$form['name']).Trim()
					$np = [string]$form['pass']
					$np2 = [string]$form['pass2']
					$err = ''
					if ($nid -notmatch '^[A-Za-z0-9_-]{3,20}$') { $err = '아이디는 영문 · 숫자 3~20자로 지어 주세요.' }
					elseif ($np.Length -lt 8) { $err = '비밀번호는 8자 이상으로 정해 주세요.' }
					elseif ($np -cne $np2) { $err = '비밀번호 확인이 일치하지 않습니다.' }

					if (-not $err) {
						if (-not $nnm) { $nnm = $nid }
						Save-Users @(, ([ordered]@{ id = $nid; name = $nnm; role = 'admin'; pass = (New-PassHash $np); at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }))
						$tok = [Guid]::NewGuid().ToString('N')
						$Sessions[$tok] = $nid
						$ctx.Response.AddHeader('Set-Cookie', "lsadmin=$tok; Path=/; HttpOnly; SameSite=Lax")
						$ctx.Response.StatusCode = 302
						$ctx.Response.AddHeader('Location', '/admin/')
						$ctx.Response.OutputStream.Close()
						continue
					}
					$bz = $Utf8NoBom.GetBytes((Get-GatePage 'setup' $err))
					$ctx.Response.StatusCode = 200
					$ctx.Response.ContentType = 'text/html; charset=utf-8'
					$ctx.Response.OutputStream.Write($bz, 0, $bz.Length)
					$ctx.Response.OutputStream.Close()
					continue
				}
				if ($path.StartsWith('/api/')) {
					$ctx.Response.StatusCode = 401
					$ctx.Response.ContentType = 'application/json; charset=utf-8'
					$bz = $Utf8NoBom.GetBytes('{"ok":false,"error":"관리자 계정을 먼저 만들어 주세요.","needLogin":true}')
				} else {
					$ctx.Response.StatusCode = 200
					$ctx.Response.ContentType = 'text/html; charset=utf-8'
					$bz = $Utf8NoBom.GetBytes((Get-GatePage 'setup' ''))
				}
				$ctx.Response.OutputStream.Write($bz, 0, $bz.Length)
				$ctx.Response.OutputStream.Close()
				continue
			}

			# --- 로그아웃 ---
			if ($path -eq '/logout') {
				if ($ck -and $ck -match 'lsadmin=([0-9a-f]{32})') { $Sessions.Remove($Matches[1]) }
				$ctx.Response.AddHeader('Set-Cookie', 'lsadmin=; Path=/; HttpOnly; Max-Age=0')
				$ctx.Response.StatusCode = 302
				$ctx.Response.AddHeader('Location', '/admin/')
				$ctx.Response.OutputStream.Close()
				continue
			}

			# --- 로그인 처리 ---
			if (-not $me) {
				if ($path -eq '/login' -and $method -eq 'POST') {
					$ip = $req.RemoteEndPoint.Address.ToString()
					$wait = 0
					if ($LoginFails.ContainsKey($ip)) {
						$f = $LoginFails[$ip]
						if ($f.n -ge 5) {
							$left = 300 - [int]((Get-Date) - $f.t).TotalSeconds
							if ($left -gt 0) { $wait = $left } else { $LoginFails.Remove($ip) }
						}
					}

					$rawForm = ''
					try {
						$sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
						$rawForm = $sr.ReadToEnd()
					} catch {}
					$form = [System.Web.HttpUtility]::ParseQueryString($rawForm)

					if ($wait -gt 0) {
						$bz = $Utf8NoBom.GetBytes((Get-GatePage 'login' ("비밀번호를 여러 번 잘못 입력했습니다. " + [math]::Ceiling($wait / 60) + "분 뒤에 다시 시도해 주세요.")))
					} else {
						$u = Get-UserById (([string]$form['user']).Trim())
						if ($u -and (Test-PassHash ([string]$form['pass']) $u.pass)) {
							$LoginFails.Remove($ip)
							$tok = [Guid]::NewGuid().ToString('N')
							$Sessions[$tok] = $u.id
							$ctx.Response.AddHeader('Set-Cookie', "lsadmin=$tok; Path=/; HttpOnly; SameSite=Lax")
							$ctx.Response.StatusCode = 302
							$ctx.Response.AddHeader('Location', '/admin/')
							$ctx.Response.OutputStream.Close()
							Write-Host ("  [로그인] " + $u.id + "  (" + $ip + ")") -ForegroundColor DarkGreen
							continue
						}
						$n = 1
						if ($LoginFails.ContainsKey($ip) -and ((Get-Date) - $LoginFails[$ip].t).TotalSeconds -lt 300) { $n = $LoginFails[$ip].n + 1 }
						$LoginFails[$ip] = @{ n = $n; t = (Get-Date) }
						$bz = $Utf8NoBom.GetBytes((Get-GatePage 'login' '아이디 또는 비밀번호가 맞지 않습니다.'))
					}
					$ctx.Response.StatusCode = 401
					$ctx.Response.ContentType = 'text/html; charset=utf-8'
					$ctx.Response.OutputStream.Write($bz, 0, $bz.Length)
					$ctx.Response.OutputStream.Close()
					continue
				}

				if ($path.StartsWith('/api/')) {
					$ctx.Response.StatusCode = 401
					$ctx.Response.ContentType = 'application/json; charset=utf-8'
					$bz = $Utf8NoBom.GetBytes('{"ok":false,"error":"로그인이 필요합니다.","needLogin":true}')
				} else {
					$ctx.Response.StatusCode = 200
					$ctx.Response.ContentType = 'text/html; charset=utf-8'
					$bz = $Utf8NoBom.GetBytes((Get-GatePage 'login' ''))
				}
				$ctx.Response.OutputStream.Write($bz, 0, $bz.Length)
				$ctx.Response.OutputStream.Close()
				continue
			}
		}

		# ---------- 권한 ----------
		# 보기 전용 계정은 저장 · 변경을 할 수 없다. (버튼뿐 아니라 여기서도 막는다)
		$canEdit = ($me -and $me.role -eq 'admin')
		# 자기 비밀번호 바꾸기는 보기 전용 계정도 할 수 있다.
		if ($method -eq 'POST' -and -not $canEdit -and -not $isPublicApi -and $path -ne '/api/password') {
			$ctx.Response.StatusCode = 403
			$ctx.Response.ContentType = 'application/json; charset=utf-8'
			$bz = $Utf8NoBom.GetBytes('{"ok":false,"error":"이 계정은 보기 전용입니다. 저장 권한이 없습니다."}')
			$ctx.Response.OutputStream.Write($bz, 0, $bz.Length)
			$ctx.Response.OutputStream.Close()
			continue
		}

		# ============================ API ============================
		if ($path.StartsWith('/api/')) {
			$route = $path.Substring(5).TrimEnd('/')
			$body = $null
			if ($method -eq 'POST') { $body = Get-Body $ctx }

			switch ($route) {

				# --- 상태 ---
				'ping' { Send-Json $ctx ([ordered]@{ ok = $true; root = $Root }) }

				'state' {
					$inq = @(Read-JsonArray (Join-Path $DataDir 'inquiries.json'))
					$posts = @(Read-JsonArray (Join-Path $DataDir 'posts.json'))
					$newCnt = @($inq | Where-Object { $_.status -eq 'new' }).Count
					$pages = @(Get-PageList)
					$imgs = Get-MediaList
					Send-Json $ctx ([ordered]@{
							ok        = $true
							root      = $Root
							pages     = $pages
							pageCount = $pages.Count
							imgCount  = $imgs.Count
							inqTotal  = $inq.Count
							inqNew    = $newCnt
							postTotal = $posts.Count
							port      = $Port
							canEdit   = $canEdit
							user      = [ordered]@{ id = $me.id; name = $me.name; role = $me.role }
						})
				}

				# --- 계정 ---
				'me' {
					Send-Json $ctx ([ordered]@{ ok = $true; id = $me.id; name = $me.name; role = $me.role; canEdit = $canEdit })
				}

				'users' {
					$items = New-Object System.Collections.ArrayList
					foreach ($u in (Get-Users)) {
						[void]$items.Add([ordered]@{ id = $u.id; name = $u.name; role = $u.role; at = $u.at; me = ($u.id -ceq $me.id) })
					}
					Send-Json $ctx ([ordered]@{ ok = $true; items = @($items.ToArray()); canEdit = $canEdit })
				}

				'user-save' {
					$uid = ([string]$body.id).Trim()
					$unm = ([string]$body.name).Trim()
					$role = 'viewer'
					if ($body.role -eq 'admin') { $role = 'admin' }
					$pw = [string]$body.pass
					if ($uid -notmatch '^[A-Za-z0-9_-]{3,20}$') { throw '아이디는 영문 · 숫자 3~20자로 지어 주세요.' }

					$users = @(Get-Users)
					$idx = -1
					for ($i = 0; $i -lt $users.Count; $i++) { if ($users[$i].id -ceq $uid) { $idx = $i; break } }

					if ($idx -lt 0) {
						if ($pw.Length -lt 8) { throw '비밀번호는 8자 이상으로 정해 주세요.' }
						if (-not $unm) { $unm = $uid }
						$users = @($users) + @([ordered]@{ id = $uid; name = $unm; role = $role; pass = (New-PassHash $pw); at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') })
					} else {
						if ($uid -ceq $me.id -and $role -ne 'admin') { throw '지금 로그인한 계정의 권한은 낮출 수 없습니다.' }
						$keep = $users[$idx].pass
						if ($pw) {
							if ($pw.Length -lt 8) { throw '비밀번호는 8자 이상으로 정해 주세요.' }
							$keep = New-PassHash $pw
						}
						if (-not $unm) { $unm = $uid }
						$users[$idx] = [ordered]@{ id = $uid; name = $unm; role = $role; pass = $keep; at = $users[$idx].at }
					}
					Save-Users $users
					Send-Json $ctx ([ordered]@{ ok = $true })
				}

				'user-delete' {
					$uid = [string]$body.id
					if ($uid -ceq $me.id) { throw '지금 로그인한 계정은 지울 수 없습니다.' }
					$left = New-Object System.Collections.ArrayList
					$adminLeft = 0
					foreach ($u in (Get-Users)) {
						if ($u.id -ceq $uid) { continue }
						[void]$left.Add($u)
						if ($u.role -eq 'admin') { $adminLeft++ }
					}
					if ($adminLeft -lt 1) { throw '관리자 계정이 하나도 남지 않게 됩니다.' }
					Save-Users @($left.ToArray())
					# 그 사람이 들어와 있었다면 바로 내보낸다
					foreach ($k in @($Sessions.Keys)) { if ($Sessions[$k] -ceq $uid) { $Sessions.Remove($k) } }
					Send-Json $ctx ([ordered]@{ ok = $true })
				}

				'password' {
					$old = [string]$body.old
					$new = [string]$body.new
					if (-not (Test-PassHash $old $me.pass)) { throw '지금 쓰는 비밀번호가 맞지 않습니다.' }
					if ($new.Length -lt 8) { throw '새 비밀번호는 8자 이상으로 정해 주세요.' }
					$users = @(Get-Users)
					for ($i = 0; $i -lt $users.Count; $i++) {
						if ($users[$i].id -ceq $me.id) {
							$users[$i] = [ordered]@{ id = $users[$i].id; name = $users[$i].name; role = $users[$i].role; pass = (New-PassHash $new); at = $users[$i].at }
						}
					}
					Save-Users $users
					Send-Json $ctx ([ordered]@{ ok = $true })
				}

				# --- 파일 읽기/쓰기 ---
				'file' {
					$rel = $q['path']
					$full = Resolve-Safe $rel
					if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { Send-Json $ctx ([ordered]@{ ok = $false; error = "파일이 없습니다 : $rel" }) 404; break }
					Send-Json $ctx ([ordered]@{ ok = $true; path = $rel; content = (Read-TextFile $full) })
				}

				# 관리자 화면이 "원본에서 필요한 구간만 바꾼" 전체 문자열을 보낸다.
				# 서버는 그대로 기록한다. (BOM 유무만 원본에 맞춤)
				'save' {
					$rel = $body.path
					$full = Resolve-Safe $rel
					if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "파일이 없습니다 : $rel" }
					# 편집하는 동안 파일이 바뀌지 않았는지 확인한다.
					if ($body.baseLen -and ((Read-TextFile $full).Length -ne [int]$body.baseLen)) {
						throw '편집하는 동안 파일이 다른 곳에서 바뀌었습니다. 되돌리기를 눌러 다시 불러와 주세요.'
					}
					$bk = Backup-File $rel
					Write-TextFile $full $body.content
					Send-Json $ctx ([ordered]@{ ok = $true; backup = $bk })
				}

				# --- 회사 정보(전 페이지 공통) ---
				'company' { Send-Json $ctx ([ordered]@{ ok = $true; items = (Get-CompanyInfo) }) }

				'company-save' {
					$r = Set-CompanyInfo $body.items
					Send-Json $ctx ([ordered]@{ ok = $true; files = $r.files; hits = $r.hits })
				}

				# --- 이미지 ---
				'media' { Send-Json $ctx ([ordered]@{ ok = $true; items = (Get-MediaList) }) }

				# 기존 이미지를 같은 경로에 덮어쓴다. (원본은 백업 폴더로)
				'media-replace' {
					$rel = ($body.path -replace '\\', '/')
					if ($rel -notmatch '^assets/(sub|cases)/') { throw '교체할 수 있는 위치가 아닙니다 : ' + $rel }
					$full = Resolve-Safe $rel
					if (Test-Path -LiteralPath $full -PathType Leaf) {
						Copy-Item -LiteralPath $full -Destination (Join-Path $BackupDir ((Get-Stamp) + '__' + ($rel -replace '[\\/]', '__'))) -Force
					}
					[System.IO.File]::WriteAllBytes($full, [Convert]::FromBase64String($body.data))
					$sz = Get-ImageSize $full
					Send-Json $ctx ([ordered]@{ ok = $true; path = $rel; w = $sz.w; h = $sz.h })
				}

				# --- 첨부파일(게시판) ---
				'file-upload' {
					$name = $body.name
					$name = $name -replace '[\\/:*?"<>|]', '_'
					if (-not (Test-Path -LiteralPath $UploadDir)) { New-Item -ItemType Directory -Force -Path $UploadDir | Out-Null }
					$dest = Join-Path $UploadDir $name
					$base = [System.IO.Path]::GetFileNameWithoutExtension($name)
					$ext = [System.IO.Path]::GetExtension($name)
					$i = 2
					while (Test-Path -LiteralPath $dest) { $name = "$base`_$i$ext"; $dest = Join-Path $UploadDir $name; $i++ }
					[System.IO.File]::WriteAllBytes($dest, [Convert]::FromBase64String($body.data))
					Send-Json $ctx ([ordered]@{ ok = $true; name = $name; path = 'files/' + $name; size = (Get-Item -LiteralPath $dest).Length })
				}

				# --- 문의 ---
				'inquiries' {
					Send-Json $ctx ([ordered]@{ ok = $true; items = @(Read-JsonArray (Join-Path $DataDir 'inquiries.json')) })
				}

				'inquiries-save' {
					Save-Json (Join-Path $DataDir 'inquiries.json') @($body.items)
					Send-Json $ctx ([ordered]@{ ok = $true })
				}

				# 사이트 문의 폼(qa.html · as.html)이 실제로 부르는 접수 주소
				'inquiry' {
					$file = Join-Path $DataDir 'inquiries.json'
					$items = @(Read-JsonArray $file)
					$id = (Get-Date).ToString('yyyyMMddHHmmssfff')
					$new = [ordered]@{
						id      = $id
						at      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
						kind    = [string]$body.kind
						name    = [string]$body.name
						tel     = [string]$body.tel
						email   = [string]$body.email
						product = [string]$body.product
						subject = [string]$body.subject
						message = [string]$body.message
						status  = 'new'
						memo    = ''
					}
					$items = @($new) + $items
					Save-Json $file $items
					Write-Host ("  [문의 접수] {0} / {1} / {2}" -f $new.kind, $new.name, $new.subject) -ForegroundColor Green
					Send-Json $ctx ([ordered]@{ ok = $true; id = $id })
				}

				# 문의 폼 연결 켜기/끄기 (qa.html · as.html 의 data-endpoint)
				'inquiry-wire' {
					$on = [bool]$body.on
					$val = ''
					if ($on) { $val = '/api/inquiry' }
					$done = 0
					foreach ($f in @('qa.html', 'as.html')) {
						$full = Join-Path $Root $f
						if (-not (Test-Path -LiteralPath $full)) { continue }
						$src = Read-TextFile $full
						$new = [regex]::Replace($src, 'data-endpoint="[^"]*"', 'data-endpoint="' + $val + '"')
						if ($new -ne $src) {
							Backup-File $f | Out-Null
							Write-TextFile $full $new
							$done++
						}
					}
					Send-Json $ctx ([ordered]@{ ok = $true; files = $done; on = $on })
				}

				'inquiry-state' {
					$src = Read-TextFile (Join-Path $Root 'qa.html')
					$on = ($src -match 'data-endpoint="[^"]+"')
					Send-Json $ctx ([ordered]@{ ok = $true; on = $on })
				}

				# --- 게시판 ---
				'posts' {
					Send-Json $ctx ([ordered]@{ ok = $true; items = @(Read-JsonArray (Join-Path $DataDir 'posts.json')) })
				}

				'posts-save' {
					Save-Json (Join-Path $DataDir 'posts.json') @($body.items)
					$log = ''
					if ($body.publish) { $log = Invoke-BoardBuild }
					Send-Json $ctx ([ordered]@{ ok = $true; log = $log })
				}

				'board-build' { Send-Json $ctx ([ordered]@{ ok = $true; log = (Invoke-BoardBuild) }) }

				# --- 백업 ---
				'backups' {
					$items = New-Object System.Collections.ArrayList
					foreach ($f in (Get-ChildItem $BackupDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 200)) {
						[void]$items.Add([ordered]@{ name = $f.Name; at = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'); kb = [math]::Round($f.Length / 1KB, 1) })
					}
					Send-Json $ctx ([ordered]@{ ok = $true; items = @($items.ToArray()) })
				}

				'restore' {
					$name = $body.name
					$src = Join-Path $BackupDir $name
					if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw '백업 파일이 없습니다.' }
					$rel = ($name -replace '^\d{8}-\d{6}__', '') -replace '__', '/'
					$dest = Resolve-Safe $rel
					Backup-File $rel | Out-Null
					Copy-Item -LiteralPath $src -Destination $dest -Force
					Send-Json $ctx ([ordered]@{ ok = $true; restored = $rel })
				}

				# --- Git ---
				'git-status' {
					Push-Location $Root
					try { $out = (git status --porcelain 2>&1 | Out-String) } catch { $out = 'git 사용 불가' }
					Pop-Location
					Send-Json $ctx ([ordered]@{ ok = $true; log = $out })
				}

				'git-push' {
					$msg = $body.message; if (-not $msg) { $msg = '관리자에서 콘텐츠 수정' }
					Push-Location $Root
					$out = ''
					try {
						$out += (git add -A 2>&1 | Out-String)
						$out += (git commit -m $msg 2>&1 | Out-String)
						$out += (git push 2>&1 | Out-String)
					} catch { $out += $_.Exception.Message }
					Pop-Location
					Send-Json $ctx ([ordered]@{ ok = $true; log = $out })
				}

				default { Send-Json $ctx ([ordered]@{ ok = $false; error = "없는 API : $route" }) 404 }
			}
			$ctx.Response.OutputStream.Close()
			continue
		}

		# ======================== 관리자 UI ========================
		# 상대 주소로 보낸다. (localhost 절대주소로 보내면 외부에서 열었을 때 깨진다)
		if ($path -eq '/admin' ) { $ctx.Response.StatusCode = 302; $ctx.Response.AddHeader('Location', '/admin/'); $ctx.Response.OutputStream.Close(); continue }
		if ($path.StartsWith('/admin/')) {
			$sub = $path.Substring(7)
			if (-not $sub) { $sub = 'index.html' }
			$file = Join-Path $UiDir ($sub -replace '/', '\')
			if (Test-Path -LiteralPath $file -PathType Leaf) { Send-FileOnDisk $ctx $file }
			else { Send-Text $ctx "관리자 파일 없음 : $sub" 'text/plain; charset=utf-8' 404 }
			$ctx.Response.OutputStream.Close()
			continue
		}

		# ========================= 사이트 =========================
		$p = $path
		if ($p.EndsWith('/')) { $p += 'index.html' }
		$file = Join-Path $Root ($p.TrimStart('/') -replace '/', '\')
		if (Test-Path -LiteralPath $file -PathType Leaf) { Send-FileOnDisk $ctx $file }
		else { Send-Text $ctx "404 Not Found : $path" 'text/plain; charset=utf-8' 404 }
		$ctx.Response.OutputStream.Close()

	} catch {
		try {
			Send-Json $ctx ([ordered]@{ ok = $false; error = $_.Exception.Message }) 500
			$ctx.Response.OutputStream.Close()
		} catch {}
		Write-Host ("  [오류] " + $_.Exception.Message) -ForegroundColor Red
	}
}
