<#
  라성에너지(주) — 홈페이지 + 관리자 호스팅 업로드
  ---------------------------------------------------------------
  무료호스팅(닷홈 등)에 FTP 로 통째로 올린다.

  쓰는 법
      powershell -File "_admin\호스팅 올리기.ps1"
    실행하면 FTP 주소 · 아이디 · 비밀번호를 물어본다.

  옵션
      -FtpHost  ftp.계정명.dothome.co.kr
      -User     계정명
      -RemoteDir /html      (닷홈 기준 웹 폴더. 업체마다 다르면 바꿔 준다)
      -Only     admin       (관리자 폴더만 다시 올릴 때)
      -SkipVideo            (동영상을 빼고 올린다 — 트래픽 아낄 때)

  올리지 않는 것 : .git, _admin, _config.yml, serve.ps1, .gitignore,
                   관리자 계정 · 문의 내용 · 백업 (서버에서 새로 만든다)
#>
param(
	[string]$FtpHost = '',
	[string]$User = '',
	[string]$Password = '',
	[string]$RemoteDir = '/html',
	[string]$Only = '',
	[switch]$SkipVideo,
	[string]$Root = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')

# ---------- 접속 정보 ----------
if (-not $FtpHost) { $FtpHost = Read-Host '  FTP 주소 (예: ftp.계정명.dothome.co.kr)' }
if (-not $User) { $User = Read-Host '  FTP 아이디' }
if (-not $Password) {
	$sec = Read-Host '  FTP 비밀번호' -AsSecureString
	$Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
		[Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$FtpHost = $FtpHost -replace '^ftp://', '' -replace '/$', ''
$RemoteDir = '/' + $RemoteDir.Trim('/')

# ---------- 올릴 목록 ----------
# 폴더 통째로 빼는 것
$skipDirs = @('.git', '_admin', 'node_modules', '.claude')
# 파일 하나씩 빼는 것
$skipFiles = @('_config.yml', 'serve.ps1', '.gitignore', '.nojekyll', 'connect.html')
# 관리자 안에서 빼는 것 (서버에서 새로 만들어진다)
$skipRel = @('admin/data/users.php', 'admin/data/inquiries.php', 'admin/data/lockout.php')

function Should-Skip($full) {
	$rel = $full.Substring($Root.Length).TrimStart('\') -replace '\\', '/'
	foreach ($d in $skipDirs) { if ($rel -eq $d -or $rel.StartsWith($d + '/')) { return $true } }
	foreach ($f in $skipFiles) { if ($rel -eq $f) { return $true } }
	foreach ($r in $skipRel) { if ($rel -eq $r) { return $true } }
	if ($rel.StartsWith('admin/backups/') -and $rel -ne 'admin/backups/.htaccess') { return $true }
	if ($SkipVideo -and $rel.StartsWith('assets/video/')) { return $true }
	if ($Only -and -not $rel.StartsWith($Only.Trim('/') + '/') -and $rel -ne $Only.Trim('/')) { return $true }
	return $false
}

$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { -not (Should-Skip $_.FullName) })
if ($files.Count -eq 0) {
	Write-Host '  올릴 파일이 없습니다.' -ForegroundColor Yellow
	exit 1
}
$totalMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)

Write-Host ''
Write-Host '  ================================================================'
Write-Host '   홈페이지 업로드' -ForegroundColor Cyan
Write-Host '  ================================================================'
Write-Host "   서버     ftp://$FtpHost$RemoteDir" -ForegroundColor Gray
Write-Host "   파일     $($files.Count)개 · $totalMB MB" -ForegroundColor Gray
if ($SkipVideo) { Write-Host '   동영상은 빼고 올립니다.' -ForegroundColor DarkYellow }
if ($Only) { Write-Host "   $Only 폴더만 올립니다." -ForegroundColor DarkYellow }
Write-Host ''

# ---------- FTP 도구 ----------
$cred = New-Object System.Net.NetworkCredential($User, $Password)
$madeDirs = New-Object 'System.Collections.Generic.HashSet[string]'

function Ftp-Request($uri, $method) {
	$r = [System.Net.FtpWebRequest]::Create($uri)
	$r.Credentials = $cred
	$r.Method = $method
	$r.UseBinary = $true
	$r.UsePassive = $true
	$r.KeepAlive = $false
	$r.Timeout = 120000
	$r.ReadWriteTimeout = 300000
	return $r
}
function Ensure-Dir($remotePath) {
	if ($remotePath -eq '' -or $remotePath -eq '/') { return }
	if ($madeDirs.Contains($remotePath)) { return }
	$parent = $remotePath.Substring(0, $remotePath.LastIndexOf('/'))
	if ($parent) { Ensure-Dir $parent }
	try {
		$req = Ftp-Request ("ftp://$FtpHost" + $remotePath) ([System.Net.WebRequestMethods+Ftp]::MakeDirectory)
		$res = $req.GetResponse(); $res.Close()
	} catch {
		# 이미 있으면 그냥 넘어간다
	}
	[void]$madeDirs.Add($remotePath)
}
function Upload-File($localPath, $remotePath) {
	$req = Ftp-Request ("ftp://$FtpHost" + $remotePath) ([System.Net.WebRequestMethods+Ftp]::UploadFile)
	$bytes = [System.IO.File]::ReadAllBytes($localPath)
	$req.ContentLength = $bytes.Length
	$s = $req.GetRequestStream()
	$s.Write($bytes, 0, $bytes.Length)
	$s.Close()
	$res = $req.GetResponse(); $res.Close()
}

# ---------- 업로드 ----------
Ensure-Dir $RemoteDir
$n = 0; $fail = 0; $failList = @()
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($f in $files) {
	$n++
	$rel = $f.FullName.Substring($Root.Length).TrimStart('\') -replace '\\', '/'
	$remote = $RemoteDir + '/' + $rel
	$dir = $remote.Substring(0, $remote.LastIndexOf('/'))
	$sizeTxt = if ($f.Length -ge 1MB) { "$([math]::Round($f.Length/1MB,1))MB" } else { "$([math]::Round($f.Length/1KB))KB" }

	Write-Host ("  [{0,3}/{1}] {2} ({3})" -f $n, $files.Count, $rel, $sizeTxt) -NoNewline
	try {
		Ensure-Dir $dir
		Upload-File $f.FullName $remote
		Write-Host '  OK' -ForegroundColor DarkGreen
	} catch {
		$fail++
		$failList += $rel
		Write-Host ('  실패 : ' + $_.Exception.Message.Split([Environment]::NewLine)[0]) -ForegroundColor Red
	}
}
$sw.Stop()

Write-Host ''
Write-Host '  ----------------------------------------------------------------'
Write-Host ("   올린 파일 {0}개 · 실패 {1}개 · {2}분 걸림" -f ($n - $fail), $fail, [math]::Round($sw.Elapsed.TotalMinutes, 1)) -ForegroundColor White
if ($fail -gt 0) {
	Write-Host '   실패한 파일 :' -ForegroundColor Yellow
	$failList | Select-Object -First 20 | ForEach-Object { Write-Host ("     " + $_) -ForegroundColor DarkYellow }
	Write-Host '   다시 실행하면 실패한 것만 덮어써집니다.' -ForegroundColor DarkGray
} else {
	Write-Host ''
	Write-Host '   다 올렸습니다. 이제 아래 주소로 들어가 보세요.' -ForegroundColor DarkGreen
	$site = $FtpHost -replace '^ftp\.', ''
	Write-Host ("   홈페이지  http://$site/") -ForegroundColor White
	Write-Host ("   관리자    http://$site/admin/") -ForegroundColor White
	Write-Host ''
	Write-Host '   관리자에 처음 들어가면 아이디 · 비밀번호를 정하는 화면이 나옵니다.' -ForegroundColor Gray
}
Write-Host '  ----------------------------------------------------------------'
Write-Host ''
