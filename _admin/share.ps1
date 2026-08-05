<#
  라성에너지(주) — 관리자 외부 접속 열기
  ---------------------------------------------------------------
  실행 : _admin\외부공유 실행.cmd
  하는 일
    1) 관리자 서버를 켠다
    2) 인터넷 주소(터널)를 만든다
    3) 그 주소를 화면과 「접속주소.txt」에 적어 준다

  아이디 · 비밀번호는 관리자 화면의 「접속 계정」에서 만든 것을 그대로 쓴다.
  (이 창에서 따로 만들지 않는다)

  이 창을 닫으면 주소가 닫힌다. 내 PC가 켜져 있는 동안만 열린다.
#>
param(
	[int]$Port = 8881
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$here = $PSScriptRoot
$serverPs = Join-Path $here 'server.ps1'
$usersFile = Join-Path $here 'data\users.json'

# 이 창이 열려 있는 동안 PC가 절전으로 들어가지 않게 한다.
# (절전에 들어가면 상대방 접속이 끊긴다. 화면은 꺼져도 된다)
try {
	Add-Type -Namespace Win32 -Name Power -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@ -ErrorAction Stop
	# ES_CONTINUOUS | ES_SYSTEM_REQUIRED
	[void][Win32.Power]::SetThreadExecutionState(0x80000001)
	$sleepBlocked = $true
} catch { $sleepBlocked = $false }

# ---------- 계정 확인 ----------
$hasUser = $false
if (Test-Path -LiteralPath $usersFile) {
	try {
		$raw = ([System.IO.File]::ReadAllText($usersFile, [System.Text.Encoding]::UTF8)).Trim()
		if ($raw) { $hasUser = (@(ConvertFrom-Json $raw).Count -gt 0) }
	} catch {}
}
if (-not $hasUser) {
	Write-Host ''
	Write-Host '  아직 접속 계정이 없습니다.' -ForegroundColor Yellow
	Write-Host '  먼저 「관리자 실행.cmd」 로 관리자를 열어 아이디와 비밀번호를 만들어 주세요.' -ForegroundColor White
	Write-Host '  계정을 만든 뒤 이 창을 다시 실행하시면 됩니다.' -ForegroundColor Gray
	Write-Host ''
	Read-Host '  엔터를 누르면 닫힙니다'
	exit 1
}

# ---------- cloudflared 찾기 ----------
$cf = (Get-Command cloudflared -ErrorAction SilentlyContinue).Source
if (-not $cf) {
	foreach ($p in @(
			'C:\Program Files (x86)\cloudflared\cloudflared.exe',
			'C:\Program Files\cloudflared\cloudflared.exe')) {
		if (Test-Path -LiteralPath $p) { $cf = $p; break }
	}
}
if (-not $cf) {
	Write-Host ''
	Write-Host '  [오류] cloudflared 를 찾을 수 없습니다.' -ForegroundColor Red
	Write-Host '  아래 명령으로 설치한 뒤 다시 실행하세요.' -ForegroundColor Yellow
	Write-Host '      winget install --id Cloudflare.cloudflared' -ForegroundColor White
	Write-Host ''
	Read-Host '  엔터를 누르면 닫힙니다'
	exit 1
}

# ---------- 1. 관리자 서버 ----------
Write-Host ''
Write-Host '  관리자 서버를 켜는 중...' -ForegroundColor DarkGray

$srv = $null
$alive = $false
try {
	$r = Invoke-WebRequest "http://localhost:$Port/api/ping" -UseBasicParsing -TimeoutSec 2
	if ($r.StatusCode -eq 200) { $alive = $true }
} catch {}

if ($alive) {
	Write-Host '  이미 켜져 있는 관리자를 그대로 씁니다.' -ForegroundColor DarkGreen
} else {
	$srv = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $serverPs, '-NoBrowser', '-Port', $Port) -WindowStyle Minimized -PassThru
	foreach ($i in 1..30) {
		Start-Sleep -Milliseconds 500
		try {
			$r = Invoke-WebRequest "http://localhost:$Port/api/ping" -UseBasicParsing -TimeoutSec 3
			if ($r.StatusCode -eq 200) { $alive = $true; break }
		} catch {}
	}
	if (-not $alive) {
		Write-Host '  [오류] 관리자 서버가 응답하지 않습니다.' -ForegroundColor Red
		Read-Host '  엔터를 누르면 닫힙니다'
		exit 1
	}
	Write-Host '  관리자 서버 준비 완료' -ForegroundColor DarkGreen
}

# ---------- 2. 터널 ----------
Write-Host '  인터넷 주소를 만드는 중... (20~40초 걸립니다)' -ForegroundColor DarkGray

$logFile = Join-Path $env:TEMP ('lasung-tunnel-' + (Get-Date).ToString('HHmmss') + '.log')
# --http-host-header : 이걸 안 주면 서버가 낯선 주소라고 400 으로 되돌려 보낸다.
$tun = Start-Process $cf `
	-ArgumentList @('tunnel', '--url', "http://localhost:$Port", '--http-host-header', "localhost:$Port", '--logfile', $logFile, '--loglevel', 'info') `
	-WindowStyle Hidden -PassThru

$publicUrl = ''
foreach ($i in 1..120) {
	Start-Sleep -Milliseconds 700
	if (Test-Path -LiteralPath $logFile) {
		$m = [regex]::Match((Get-Content $logFile -Raw -ErrorAction SilentlyContinue), 'https://[a-z0-9-]+\.trycloudflare\.com')
		if ($m.Success) { $publicUrl = $m.Value; break }
	}
	if ($tun.HasExited) { break }
}

if (-not $publicUrl) {
	Write-Host ''
	Write-Host '  [오류] 인터넷 주소를 만들지 못했습니다.' -ForegroundColor Red
	Write-Host "  기록 : $logFile" -ForegroundColor DarkGray
	if ($srv) { try { $srv.Kill() } catch {} }
	try { $tun.Kill() } catch {}
	Read-Host '  엔터를 누르면 닫힙니다'
	exit 1
}

$adminUrl = "$publicUrl/admin/"

# 주소가 생겨도 DNS 에 퍼지기까지 30~60초 걸린다. 실제로 열릴 때까지 기다린다.
Write-Host '  주소가 열리기를 기다리는 중... (30~60초)' -ForegroundColor DarkGray
$live = $false
foreach ($i in 1..80) {
	Start-Sleep -Milliseconds 1200
	try {
		$null = Invoke-WebRequest $adminUrl -UseBasicParsing -TimeoutSec 10
		$live = $true; break
	} catch {
		# 401 = 로그인 화면이 떴다는 뜻이므로 준비된 것이다.
		if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 401) { $live = $true; break }
	}
}
if ($live) {
	Write-Host '  주소 준비 완료' -ForegroundColor DarkGreen
} else {
	Write-Host '  ※ 아직 응답이 없습니다. 1~2분 뒤 다시 열어 보세요.' -ForegroundColor Yellow
}

# ---------- 3. 안내 ----------
Write-Host ''
Write-Host '  ================================================================'
Write-Host '   라성에너지(주) 홈페이지 관리자 - 접속 주소' -ForegroundColor Cyan
Write-Host '  ================================================================'
Write-Host ''
Write-Host '   주소   ' -NoNewline -ForegroundColor Gray
Write-Host $adminUrl -ForegroundColor White
Write-Host ''
Write-Host '   아이디와 비밀번호는 「접속 계정」에서 만든 것을 알려주시면 됩니다.' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  ----------------------------------------------------------------'
Write-Host '   ※ 이 창을 닫으면 접속이 끊깁니다. 열어 두세요.' -ForegroundColor DarkYellow
if ($sleepBlocked) {
	Write-Host '   ※ 이 창이 열려 있는 동안 PC는 절전으로 들어가지 않습니다.' -ForegroundColor DarkGreen
} else {
	Write-Host '   ※ PC가 절전으로 들어가면 접속이 끊깁니다. 절전을 꺼 두세요.' -ForegroundColor DarkYellow
}
Write-Host '  ----------------------------------------------------------------'
Write-Host ''

# 전달하기 쉽게 메모장에도 남긴다.
$noteFile = Join-Path $here '접속주소.txt'
@(
	'라성에너지(주) 홈페이지 관리자',
	'',
	"주소   $adminUrl",
	'',
	'아이디 · 비밀번호는 담당자에게 받으세요.',
	'',
	'* 담당자 PC가 켜져 있는 동안 접속할 수 있습니다.',
	'* 주소는 열 때마다 새로 바뀝니다.'
) -join "`r`n" | Out-File -LiteralPath $noteFile -Encoding utf8
Write-Host "   메모 : $noteFile" -ForegroundColor DarkGray
Write-Host ''

try { Set-Clipboard -Value $adminUrl; Write-Host '   주소를 클립보드에 복사했습니다. 바로 붙여넣기 하세요.' -ForegroundColor DarkGreen } catch {}
Write-Host ''

# ---------- 종료까지 대기 ----------
try {
	while (-not $tun.HasExited) {
		if ($srv -and $srv.HasExited) { break }
		Start-Sleep -Seconds 2
	}
} finally {
	Write-Host ''
	Write-Host '  접속을 닫는 중...' -ForegroundColor DarkGray
	if ($srv) { try { $srv.Kill() } catch {} }
	try { $tun.Kill() } catch {}
	try { Remove-Item -LiteralPath $noteFile -Force -ErrorAction SilentlyContinue } catch {}
	# 안내 페이지를 "닫힘" 으로 바꿔 둔다. (상대방이 헛걸음하지 않도록)
	# 절전 방지 해제
	try { [void][Win32.Power]::SetThreadExecutionState(0x80000000) } catch {}
	Write-Host '  닫혔습니다. 이제 외부에서 접속할 수 없습니다.' -ForegroundColor DarkGreen
	Write-Host ''
}
