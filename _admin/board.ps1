<#
  라성에너지(주) — 공지사항 / 자료실 생성기
  ---------------------------------------------------------------
  입력 : _admin/data/posts.json          (관리자에서 저장)
  출력 : notice.html · info.html 의 게시판 구간
         post/<글번호>.html               (내용이나 첨부가 있는 글만)

  · 목록 페이지는 <!-- #BOARD:xxx# --> ~ <!-- #/BOARD# --> 구간만 갈아 끼운다.
    헤더 · 푸터 · 나머지 디자인은 손대지 않는다.
  · 상세 페이지는 notice.html 을 그대로 본떠 만들기 때문에
    디자인이 바뀌어도 자동으로 따라간다.
#>
param(
	[string]$Root = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Web

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
# 블록은 항상 LF 로 만들고, 파일에 끼워 넣을 때 원본 줄바꿈에 맞춰 준다.
$nl = "`n"

function Read-Text($path) { [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) }
function Test-Bom($path) {
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
	$head = New-Object byte[] 3
	$fs = [System.IO.File]::OpenRead($path)
	try { $n = $fs.Read($head, 0, 3) } finally { $fs.Dispose() }
	return ($n -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)
}
function Write-Text($path, $text, $bom) {
	$dir = Split-Path $path -Parent
	if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
	[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($bom)))
}
function Enc($s) { return [System.Web.HttpUtility]::HtmlEncode([string]$s) }
function Fmt-Date($d) {
	# 2023-03-02 -> 23.03.02   (원래 목록의 표기 방식)
	$m = [regex]::Match([string]$d, '^(\d{4})-(\d{2})-(\d{2})$')
	if (-not $m.Success) { return [string]$d }
	return $m.Groups[1].Value.Substring(2) + '.' + $m.Groups[2].Value + '.' + $m.Groups[3].Value
}
function Fmt-Size($n) {
	if (-not $n) { return '' }
	if ($n -ge 1MB) { return ('{0:N1}MB' -f ($n / 1MB)) }
	return ('{0:N0}KB' -f [math]::Max(1, $n / 1KB))
}
function Convert-Body($text) {
	if (-not $text) { return '' }
	$t = (Enc $text) -replace "`r`n", "`n"
	$t = [regex]::Replace($t, '\*\*(.+?)\*\*', '<strong>$1</strong>')
	# 인코딩을 마친 뒤라 여기서는 < 가 나올 수 없다. 공백까지를 주소로 본다.
	$t = [regex]::Replace($t, '(https?://\S+)', '<a href="$1" target="_blank" rel="noopener">$1</a>')
	$blocks = [regex]::Split($t, '\n[ \t]*\n')
	$out = foreach ($b in $blocks) {
		$b = $b.Trim()
		if ($b) { '    <p>' + ($b -replace '\n', '<br>') + '</p>' }
	}
	return ($out -join $nl)
}
function Has-Detail($p) {
	return ([string]$p.content).Trim() -or (@($p.files).Count -gt 0)
}

# ---------- 글 데이터 ----------
$postFile = Join-Path $Root '_admin\data\posts.json'
$posts = @()
if (Test-Path -LiteralPath $postFile) {
	$raw = (Read-Text $postFile).Trim()
	# ConvertFrom-Json 결과를 바로 @() 로 감싸면 배열 전체가 원소 1개가 된다. 반드시 먼저 변수에 담을 것.
	if ($raw) { $parsed = ConvertFrom-Json $raw; $posts = @($parsed) }
}
$posts = @($posts | Where-Object { $_ -and $_.published -ne $false })

$BOARDS = @(
	[ordered]@{ key = 'notice'; name = '공지사항'; file = 'notice.html'; hasCat = $false; hasFile = $false },
	[ordered]@{ key = 'info'; name = '자료실'; file = 'info.html'; hasCat = $true; hasFile = $true }
)

$FILE_IC = '<span class="file-ic" aria-label="첨부파일"><svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/></svg></span>'

# ---------- 상세 페이지 틀 ----------
# notice.html 을 본떠 만든다. post/ 폴더에 두므로 경로 앞에 ../ 를 붙인다.
$shellSrc = Read-Text (Join-Path $Root 'notice.html')
$shellBom = Test-Bom (Join-Path $Root 'notice.html')

function Add-UpPath($block) {
	return [regex]::Replace($block, '(href|src)="(?!#|https?:|mailto:|tel:|//|\.\./|/)([^"]*)"', '$1="../$2"')
}

$sBody = $shellSrc.IndexOf('<div class="sub-body">')
$sBack = $shellSrc.IndexOf('<div class="sub-back">')
if ($sBody -lt 0 -or $sBack -lt 0) { throw 'notice.html 에서 본문 구간을 찾지 못했습니다.' }
$shellTop = $shellSrc.Substring(0, $sBody)                       # <head> · 헤더 · 히어로
$shellBot = $shellSrc.Substring($sBack)                          # 메인으로 · 푸터 · 스크립트

function New-DetailPage($board, $post, $prev, $next) {
	$top = Add-UpPath $shellTop
	$bot = Add-UpPath $shellBot

	# <title> · 설명 · 히어로 제목 · 이동 경로를 이 글에 맞게 바꾼다
	$top = [regex]::Replace($top, '<title>[\s\S]*?</title>', ('<title>' + (Enc $post.title) + ' — 라성에너지(주)</title>'))
	$top = [regex]::Replace($top, '<meta name="description" content="[^"]*">', ('<meta name="description" content="라성에너지(주) 고객센터 — ' + (Enc $board.name) + '">'))
	$top = [regex]::Replace($top, '<h1>[\s\S]*?</h1>', ('<h1>' + (Enc $board.name) + '</h1>'))
	$top = [regex]::Replace($top, '<div class="crumb">[\s\S]*?</div>',
		('<div class="crumb"><a href="../index.html">홈</a> · 고객센터 · <a href="../' + $board.file + '">' + (Enc $board.name) + '</a></div>'))

	$catTag = ''
	if ($board.hasCat -and $post.cat) { $catTag = '<span class="cat-badge">' + (Enc $post.cat) + '</span>' }

	$bodyHtml = Convert-Body $post.content
	if (-not $bodyHtml) { $bodyHtml = '    <p class="pv-none">본문 내용은 등록되어 있지 않습니다. 첨부파일을 확인해 주세요.</p>' }

	$fileHtml = ''
	if (@($post.files).Count -gt 0) {
		$rows = foreach ($f in @($post.files)) {
			'      <li><a href="../' + $f.path + '" download>' + (Enc $f.name) + '<span class="fsize">' + (Fmt-Size $f.size) + '</span></a></li>'
		}
		$fileHtml = $nl + '    <div class="pv-files">' + $nl + '      <span class="pv-files-tit">첨부파일</span>' + $nl + '      <ul>' + $nl + ($rows -join $nl) + $nl + '      </ul>' + $nl + '    </div>'
	}

	$prevHtml = '<span class="none">이전 글이 없습니다.</span>'
	if ($prev) { $prevHtml = '<a href="' + $prev.id + '.html">' + (Enc $prev.title) + '</a>' }
	$nextHtml = '<span class="none">다음 글이 없습니다.</span>'
	if ($next) { $nextHtml = '<a href="' + $next.id + '.html">' + (Enc $next.title) + '</a>' }

	$main = @"
<div class="sub-body">
  <div class="post-view">
    <div class="pv-head">
      <h2 class="pv-tit">$catTag$(Enc $post.title)</h2>
      <div class="pv-meta"><span>$(Enc $board.name)</span><span>$(Fmt-Date $post.date)</span></div>
    </div>
    <div class="pv-body">
$bodyHtml
    </div>$fileHtml
    <ul class="pv-nav">
      <li><span class="lb">이전 글</span>$prevHtml</li>
      <li><span class="lb">다음 글</span>$nextHtml</li>
    </ul>
    <div class="pv-actions"><a href="../$($board.file)" class="btn btn-line">목록으로</a></div>
  </div>
</div>

"@
	return $top + $main + $bot
}

# ---------- 목록 구간 ----------
function New-ListBlock($board, $items) {
	$total = @($items).Count
	$head = @"
  <div class="board-head">
    <div class="total">전체 <b>$total</b>건</div>
    <form class="board-search" onsubmit="return false">
      <input type="text" placeholder="검색어를 입력하세요" aria-label="검색어">
      <button type="submit">검색</button>
    </form>
  </div>
$nl
"@
	$cols = '<tr><th class="col-no">번호</th><th>제목</th><th class="col-date">작성일</th>'
	if ($board.hasFile) { $cols += '<th class="col-file">첨부</th>' }
	$cols += '</tr>'

	$rows = New-Object System.Collections.ArrayList
	foreach ($p in $items) {
		$no = $p.no
		if ($p.pinned) { $no = '<span class="bl-pin">공지</span>' }

		$link = '#'
		if (Has-Detail $p) { $link = 'post/' + $p.id + '.html' }

		$cat = ''
		if ($board.hasCat -and $p.cat) { $cat = '<span class="cat-badge">' + (Enc $p.cat) + '</span>' }

		$row = '      <tr><td class="col-no">' + $no + '</td><td class="subject"><a href="' + $link + '">' + $cat + (Enc $p.title) + '</a></td><td class="col-date">' + (Fmt-Date $p.date) + '</td>'
		if ($board.hasFile) {
			$ic = ''
			if ((@($p.files).Count -gt 0) -or $p.legacyFile) { $ic = $FILE_IC }
			$row += '<td class="col-file">' + $ic + '</td>'
		}
		$row += '</tr>'
		[void]$rows.Add($row)
	}
	if ($rows.Count -eq 0) {
		$colspan = 3
		if ($board.hasFile) { $colspan = 4 }
		[void]$rows.Add('      <tr><td class="board-empty" colspan="' + $colspan + '">등록된 글이 없습니다.</td></tr>')
	}

	$table = @"
  <table class="board-list">
    <thead>
      $cols
    </thead>
    <tbody>
$($rows.ToArray() -join $nl)
    </tbody>
  </table>

  <div class="board-pager">
    <a href="#" class="on">1</a>
  </div>
"@
	return $head + $table
}

# ---------- 실행 ----------
$postDir = Join-Path $Root 'post'
if (Test-Path -LiteralPath $postDir) {
	Get-ChildItem $postDir -Filter '*.html' -ErrorAction SilentlyContinue | Remove-Item -Force
}

$madeList = 0; $madeView = 0

foreach ($b in $BOARDS) {
	$items = @($posts | Where-Object { $_.board -eq $b.key })
	$items = @($items | Sort-Object @{E = { if ($_.pinned) { 0 } else { 1 } } }, @{E = { [string]$_.date }; Descending = $true }, @{E = { [int]$_.no }; Descending = $true })

	# --- 목록 갈아 끼우기 ---
	$listFile = Join-Path $Root $b.file
	$src = Read-Text $listFile
	$openMark = '<!-- #BOARD:' + $b.key + '#'
	$s = $src.IndexOf($openMark)
	$closeMark = '<!-- #/BOARD# -->'
	$e = $src.IndexOf($closeMark)
	if ($s -lt 0 -or $e -lt 0) { throw ($b.file + ' 에서 게시판 마커를 찾지 못했습니다.') }
	$sEnd = $src.IndexOf('-->', $s) + 3          # 여는 주석의 끝

	# 갈아 끼울 자리의 줄바꿈이 CRLF 인지 LF 인지 보고 똑같이 맞춘다.
	# (이 사이트는 파일 안에 두 가지가 섞여 있어서, 안 맞추면 안 고친 줄까지 바뀐 것으로 잡힌다)
	$oldBlock = $src.Substring($sEnd, $e - $sEnd)
	$block = $nl + (New-ListBlock $b $items) + $nl + '  '
	$block = $block -replace "`r`n", "`n"
	if ($oldBlock.Contains("`r`n")) { $block = $block -replace "`n", "`r`n" }
	$new = $src.Substring(0, $sEnd) + $block + $src.Substring($e)
	if ($new -ne $src) { Write-Text $listFile $new (Test-Bom $listFile) }
	$madeList++

	# --- 상세 페이지 ---
	$detail = @($items | Where-Object { Has-Detail $_ })
	for ($i = 0; $i -lt $detail.Count; $i++) {
		$p = $detail[$i]
		$prev = $null; $next = $null
		if ($i -gt 0) { $prev = $detail[$i - 1] }
		if ($i -lt $detail.Count - 1) { $next = $detail[$i + 1] }
		Write-Text (Join-Path $postDir ($p.id + '.html')) (New-DetailPage $b $p $prev $next) $shellBom
		$madeView++
	}
}

Write-Output "=== board : 목록 $madeList · 상세 $madeView ==="
