<#
  라성에너지(주) — 관리자 외부 공유
  ---------------------------------------------------------------
  실행 : _admin\외부공유 실행.cmd
  하는 일
    1) 관리자 서버를 비밀번호를 걸고 띄운다
    2) 임시 인터넷 주소(터널)를 만든다
    3) 주소 · 아이디 · 비밀번호를 화면에 띄운다

  이 창을 닫으면 주소가 사라진다. 내 PC가 켜져 있는 동안만 열린다.

  옵션
    -Password "직접정할비번"   비번을 직접 정한다 (안 주면 자동 생성)
    -Editable                  상대방이 저장 · 배포까지 할 수 있게 한다
                               (기본은 구경만 — 저장 · 배포 잠김)
#>
param(
	[string]$Password = '',
	[string]$User = 'admin',
	[switch]$Editable,
	[int]$Port = 8881
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$here = $PSScriptRoot
$serverPs = Join-Path $here 'server.ps1'

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

# ---------- 비밀번호 ----------
if (-not $Password) {
	# 헷갈리는 글자(0/O, 1/l/I)는 빼고 만든다.
	$chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
	$rnd = New-Object System.Random
	$Password = -join (1..12 | ForEach-Object { $chars[$rnd.Next(0, $chars.Length)] })
}

# ---------- 1. 관리자 서버 ----------
Write-Host ''
Write-Host '  관리자 서버를 켜는 중...' -ForegroundColor DarkGray

$srvArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $serverPs, '-NoBrowser', '-Port', $Port, '-Password', $Password, '-User', $User)
if (-not $Editable) { $srvArgs += '-ReadOnly' }
$srv = Start-Process powershell -ArgumentList $srvArgs -WindowStyle Minimized -PassThru

$hdr = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${User}:${Password}")) }
$ready = $false
foreach ($i in 1..30) {
	Start-Sleep -Milliseconds 500
	try {
		$r = Invoke-WebRequest "http://localhost:$Port/api/ping" -UseBasicParsing -TimeoutSec 3 -Headers $hdr
		if ($r.StatusCode -eq 200) { $ready = $true; break }
	} catch {}
}
if (-not $ready) {
	Write-Host '  [오류] 관리자 서버가 응답하지 않습니다.' -ForegroundColor Red
	Read-Host '  엔터를 누르면 닫힙니다'
	exit 1
}
Write-Host '  관리자 서버 준비 완료' -ForegroundColor DarkGreen

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
	try { $srv.Kill() } catch {}
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
$mode = '구경만 가능 (저장 · 배포 잠김)'
if ($Editable) { $mode = '수정 · 배포까지 가능' }

Write-Host ''
Write-Host '  ================================================================'
Write-Host '   라성에너지(주) 관리자 - 외부 공유 주소' -ForegroundColor Cyan
Write-Host '  ================================================================'
Write-Host ''
Write-Host '   주소       ' -NoNewline -ForegroundColor Gray
Write-Host $adminUrl -ForegroundColor White
Write-Host '   아이디     ' -NoNewline -ForegroundColor Gray
Write-Host $User -ForegroundColor Yellow
Write-Host '   비밀번호   ' -NoNewline -ForegroundColor Gray
Write-Host $Password -ForegroundColor Yellow
Write-Host '   권한       ' -NoNewline -ForegroundColor Gray
Write-Host $mode -ForegroundColor Gray
Write-Host ''
Write-Host '  ----------------------------------------------------------------'
Write-Host '   ※ 이 창을 닫으면 주소가 사라집니다.' -ForegroundColor DarkYellow
Write-Host '   ※ 내 PC가 켜져 있는 동안만 열립니다.' -ForegroundColor DarkYellow
Write-Host '   ※ 주소는 실행할 때마다 새로 바뀝니다.' -ForegroundColor DarkYellow
Write-Host '  ----------------------------------------------------------------'
Write-Host ''

# 전달하기 쉽게 메모장에도 남긴다.
$noteFile = Join-Path $here '공유주소.txt'
@(
	'라성에너지(주) 홈페이지 관리자',
	'',
	"주소      $adminUrl",
	"아이디    $User",
	"비밀번호  $Password",
	"권한      $mode",
	'',
	'* 이 주소는 담당자 PC가 켜져 있는 동안만 열립니다.',
	'* 창을 닫으면 주소가 사라집니다.'
) -join "`r`n" | Out-File -LiteralPath $noteFile -Encoding utf8
Write-Host "   메모 : $noteFile" -ForegroundColor DarkGray
Write-Host ''

try { Set-Clipboard -Value $adminUrl; Write-Host '   주소를 클립보드에 복사했습니다. 바로 붙여넣기 하세요.' -ForegroundColor DarkGreen } catch {}
Write-Host ''

# ---------- 종료까지 대기 ----------
try {
	while (-not $srv.HasExited -and -not $tun.HasExited) { Start-Sleep -Seconds 2 }
} finally {
	Write-Host ''
	Write-Host '  주소를 닫는 중...' -ForegroundColor DarkGray
	try { $srv.Kill() } catch {}
	try { $tun.Kill() } catch {}
	try { Remove-Item -LiteralPath $noteFile -Force -ErrorAction SilentlyContinue } catch {}
	Write-Host '  닫혔습니다. 이제 외부에서 접속할 수 없습니다.' -ForegroundColor DarkGreen
	Write-Host ''
}
