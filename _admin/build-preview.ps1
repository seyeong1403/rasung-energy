<#
  라성에너지(주) — 보고용 관리자(읽기 전용) 자료 만들기
  ---------------------------------------------------------------
  관리자 화면을 GitHub Pages 처럼 프로그램이 돌지 않는 곳에서도
  그대로 보여주기 위해, 화면이 필요로 하는 자료를 미리 파일로 뽑아 둔다.

      admin/data/state.json    페이지 목록 · 현황 숫자
      admin/data/company.json  회사 정보
      admin/data/media.json    사진 목록
      admin/data/posts.json    공지 · 자료실 글

  사이트 내용을 고친 뒤 이 스크립트를 다시 돌리면 보고용 화면도 최신이 된다.
#>
param(
	[string]$Root = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { Add-Type -AssemblyName System.Drawing } catch {}

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
$OutDir = Join-Path $Root 'admin\data'
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Read-Text($p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Save-Json($path, $obj) {
	[System.IO.File]::WriteAllText($path, (ConvertTo-Json $obj -Depth 20), $Utf8NoBom)
}

# ---------- 페이지 목록 ----------
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
$pages = New-Object System.Collections.ArrayList
foreach ($d in $PAGE_DEFS) {
	if (-not (Test-Path -LiteralPath (Join-Path $Root $d[0]))) { continue }
	[void]$pages.Add([ordered]@{
			id     = [System.IO.Path]::GetFileNameWithoutExtension($d[0])
			source = $d[0]
			view   = $d[0]
			title  = $d[1]
			group  = $d[2]
		})
}

# ---------- 사진 ----------
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
$media = New-Object System.Collections.ArrayList
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
		[void]$media.Add([ordered]@{
				name   = $f.Name
				path   = $rel
				folder = (Split-Path $dir -Leaf)
				kb     = [math]::Round($f.Length / 1KB)
				w      = $sz.w
				h      = $sz.h
				mtime  = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
			})
	}
}

# 어느 페이지에서 쓰이는지 미리 찾아 둔다
$useMap = [ordered]@{}
foreach ($p in $pages) {
	$t = Read-Text (Join-Path $Root $p.source)
	foreach ($m in $media) {
		if ($t.Contains($m.path)) {
			if (-not $useMap.Contains($m.path)) { $useMap[$m.path] = New-Object System.Collections.ArrayList }
			[void]$useMap[$m.path].Add($p.title)
		}
	}
}
foreach ($m in $media) {
	$u = @()
	if ($useMap.Contains($m.path)) { $u = @($useMap[$m.path].ToArray()) }
	$m['used'] = $u
}

# ---------- 회사 정보 ----------
$COMPANY_DEFS = @(
	@{ key = 'tel'; label = '대표 전화'; note = '상단 띠 · 푸터 · 문의 안내에 함께 쓰입니다'; pattern = '054-\d{3}-\d{4}' },
	@{ key = 'fax'; label = '팩스'; note = ''; pattern = 'F\. (054-\d{3}-\d{4})' },
	@{ key = 'addr'; label = '주소'; note = '푸터와 회사소개 오시는 길에 쓰입니다'; pattern = '주소 : ([^<]+)<br>' },
	@{ key = 'biz'; label = '사업자등록번호'; note = ''; pattern = '사업자등록번호 : ([\d-]+)' },
	@{ key = 'email'; label = '이메일'; note = ''; pattern = '[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' },
	@{ key = 'slogan'; label = '상단 띠 문구'; note = '모든 페이지 맨 위 가로 띠'; pattern = '<div class="tb-left">([^<]*)</div>' },
	@{ key = 'copy'; label = '저작권 표기'; note = '푸터 맨 아래'; pattern = '<div>(Copyright[^<]*)</div>' }
)
$idxSrc = Read-Text (Join-Path $Root 'index.html')
$companyOut = New-Object System.Collections.ArrayList
foreach ($f in $COMPANY_DEFS) {
	$m = [regex]::Match($idxSrc, $f.pattern)
	$val = ''
	if ($m.Success) {
		if ($m.Groups.Count -gt 1 -and $m.Groups[1].Success) { $val = $m.Groups[1].Value } else { $val = $m.Value }
	}
	$hit = 0
	if ($val) {
		foreach ($p in $pages) {
			if ((Read-Text (Join-Path $Root $p.source)).Contains($val)) { $hit++ }
		}
	}
	[void]$companyOut.Add([ordered]@{ key = $f.key; label = $f.label; note = $f.note; value = $val; pages = $hit })
}

# ---------- 게시글 ----------
$posts = @()
$postSrc = Join-Path $Root '_admin\data\posts.json'
if (Test-Path -LiteralPath $postSrc) {
	$raw = (Read-Text $postSrc).Trim()
	if ($raw) { $parsed = ConvertFrom-Json $raw; $posts = @($parsed) }
}

# ---------- 저장 ----------
Save-Json (Join-Path $OutDir 'state.json') ([ordered]@{
		pages     = @($pages.ToArray())
		pageCount = $pages.Count
		imgCount  = $media.Count
		postTotal = @($posts).Count
		inqTotal  = 0
		inqNew    = 0
		builtAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm')
	})
Save-Json (Join-Path $OutDir 'company.json') @($companyOut.ToArray())
Save-Json (Join-Path $OutDir 'media.json') @($media.ToArray())
Save-Json (Join-Path $OutDir 'posts.json') @($posts)

Write-Output ("=== 보고용 자료 생성 : 페이지 {0} · 사진 {1} · 글 {2} ===" -f $pages.Count, $media.Count, @($posts).Count)
