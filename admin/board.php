<?php
/* =============================================================
   라성에너지(주) — 공지사항 / 자료실 생성기
   -------------------------------------------------------------
   입력 : admin/data/posts.json
   출력 : notice.html · info.html 의 게시판 구간
          post/<글번호>.html   (내용이나 첨부가 있는 글만)

   · 목록 페이지는 <!-- #BOARD:xxx# --> ~ <!-- #/BOARD# --> 구간만 갈아 끼운다.
     헤더 · 푸터 · 나머지 디자인은 손대지 않는다.
   · 상세 페이지는 notice.html 을 그대로 본떠 만들기 때문에
     디자인이 바뀌어도 자동으로 따라간다.
   ============================================================= */
require_once __DIR__ . '/lib.php';

function bd_enc($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

/* 2023-03-02 -> 23.03.02  (원래 목록의 표기 방식) */
function bd_date($d) {
	if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', (string)$d, $m)) {
		return substr($m[1], 2) . '.' . $m[2] . '.' . $m[3];
	}
	return (string)$d;
}
function bd_size($n) {
	$n = (int)$n;
	if ($n <= 0) { return ''; }
	if ($n >= 1048576) { return number_format($n / 1048576, 1) . 'MB'; }
	return number_format(max(1, $n / 1024), 0) . 'KB';
}
function bd_has_detail($p) {
	$c = trim((string)(isset($p['content']) ? $p['content'] : ''));
	$f = isset($p['files']) && is_array($p['files']) ? count($p['files']) : 0;
	return ($c !== '' || $f > 0);
}
function bd_body($text) {
	$text = (string)$text;
	if (trim($text) === '') { return ''; }
	$t = str_replace("\r\n", "\n", bd_enc($text));
	$t = preg_replace('/\*\*(.+?)\*\*/u', '<strong>$1</strong>', $t);
	/* 인코딩을 마친 뒤라 여기서는 < 가 나올 수 없다. 공백까지를 주소로 본다. */
	$t = preg_replace('#(https?://\S+)#u', '<a href="$1" target="_blank" rel="noopener">$1</a>', $t);
	$out = array();
	foreach (preg_split('/\n[ \t]*\n/', $t) as $b) {
		$b = trim($b);
		if ($b !== '') { $out[] = '    <p>' . str_replace("\n", '<br>', $b) . '</p>'; }
	}
	return implode("\n", $out);
}
/* 상세 페이지는 post/ 폴더에 있으므로 사이트 안쪽 경로 앞에 ../ 를 붙인다.
   구분자로 # 을 쓰면 패턴 안의 # 과 부딪히므로 ~ 를 쓴다. */
function bd_up_path($block) {
	return preg_replace('~(href|src)="(?!#|https?:|mailto:|tel:|//|\.\./|/)([^"]*)"~', '$1="../$2"', $block);
}

function board_build() {
	$BOARDS = array(
		array('key' => 'notice', 'name' => '공지사항', 'file' => 'notice.html', 'hasCat' => false, 'hasFile' => false),
		array('key' => 'info', 'name' => '자료실', 'file' => 'info.html', 'hasCat' => true, 'hasFile' => true),
	);
	$FILE_IC = '<span class="file-ic" aria-label="첨부파일"><svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/></svg></span>';

	$posts = read_json_array(data_file('posts'));
	$posts = array_values(array_filter($posts, function ($p) {
		return is_array($p) && (!isset($p['published']) || $p['published'] !== false);
	}));

	/* ---------- 상세 페이지 틀 ---------- */
	$shellFile = SITE_ROOT . '/notice.html';
	$shellSrc = read_text($shellFile);
	$sBody = strpos($shellSrc, '<div class="sub-body">');
	$sBack = strpos($shellSrc, '<div class="sub-back">');
	if ($sBody === false || $sBack === false) { throw new Exception('notice.html 에서 본문 구간을 찾지 못했습니다.'); }
	$shellTop = substr($shellSrc, 0, $sBody);
	$shellBot = substr($shellSrc, $sBack);
	$shellBom = has_bom($shellFile);

	$postDir = SITE_ROOT . '/post';
	if (is_dir($postDir)) {
		foreach (glob($postDir . '/*.html') as $f) { @unlink($f); }
	}

	$madeList = 0; $madeView = 0;

	foreach ($BOARDS as $b) {
		$items = array_values(array_filter($posts, function ($p) use ($b) {
			return isset($p['board']) && $p['board'] === $b['key'];
		}));
		usort($items, function ($x, $y) {
			$px = empty($x['pinned']) ? 1 : 0;
			$py = empty($y['pinned']) ? 1 : 0;
			if ($px !== $py) { return $px - $py; }
			$c = strcmp((string)(isset($y['date']) ? $y['date'] : ''), (string)(isset($x['date']) ? $x['date'] : ''));
			if ($c !== 0) { return $c; }
			return (int)(isset($y['no']) ? $y['no'] : 0) - (int)(isset($x['no']) ? $x['no'] : 0);
		});

		/* ---- 목록 갈아 끼우기 ---- */
		$listFile = SITE_ROOT . '/' . $b['file'];
		$src = read_text($listFile);
		$openMark = '<!-- #BOARD:' . $b['key'] . '#';
		$closeMark = '<!-- #/BOARD# -->';
		$s = strpos($src, $openMark);
		$e = strpos($src, $closeMark);
		if ($s === false || $e === false) { throw new Exception($b['file'] . ' 에서 게시판 마커를 찾지 못했습니다.'); }
		$sEnd = strpos($src, '-->', $s) + 3;

		$block = "\n" . bd_list_block($b, $items, $FILE_IC) . "\n  ";
		/* 갈아 끼울 자리의 줄바꿈이 CRLF 인지 LF 인지 보고 똑같이 맞춘다.
		   (이 사이트는 파일 안에 두 가지가 섞여 있어서, 안 맞추면 안 고친 줄까지 바뀐 것으로 잡힌다) */
		$oldBlock = substr($src, $sEnd, $e - $sEnd);
		$block = str_replace("\r\n", "\n", $block);
		if (strpos($oldBlock, "\r\n") !== false) { $block = str_replace("\n", "\r\n", $block); }

		$new = substr($src, 0, $sEnd) . $block . substr($src, $e);
		if ($new !== $src) { write_text($listFile, $new); }
		$madeList++;

		/* ---- 상세 페이지 ---- */
		$detail = array_values(array_filter($items, 'bd_has_detail'));
		for ($i = 0; $i < count($detail); $i++) {
			$p = $detail[$i];
			$prev = $i > 0 ? $detail[$i - 1] : null;
			$next = $i < count($detail) - 1 ? $detail[$i + 1] : null;
			$html = bd_detail_page($b, $p, $prev, $next, $shellTop, $shellBot);
			$dest = $postDir . '/' . preg_replace('/[^A-Za-z0-9_-]/', '', (string)$p['id']) . '.html';
			if (!is_dir($postDir)) { @mkdir($postDir, 0755, true); }
			file_put_contents($dest, ($shellBom ? "\xEF\xBB\xBF" : '') . $html, LOCK_EX);
			@chmod($dest, 0644);
			$madeView++;
		}
	}

	return "=== board : 목록 {$madeList} · 상세 {$madeView} ===";
}

function bd_list_block($b, $items, $FILE_IC) {
	$total = count($items);
	$head = '  <div class="board-head">' . "\n"
		. '    <div class="total">전체 <b>' . $total . '</b>건</div>' . "\n"
		. '    <form class="board-search" onsubmit="return false">' . "\n"
		. '      <input type="text" placeholder="검색어를 입력하세요" aria-label="검색어">' . "\n"
		. '      <button type="submit">검색</button>' . "\n"
		. '    </form>' . "\n"
		. '  </div>' . "\n\n";

	$cols = '<tr><th class="col-no">번호</th><th>제목</th><th class="col-date">작성일</th>';
	if ($b['hasFile']) { $cols .= '<th class="col-file">첨부</th>'; }
	$cols .= '</tr>';

	$rows = array();
	foreach ($items as $p) {
		$no = isset($p['no']) ? $p['no'] : '';
		if (!empty($p['pinned'])) { $no = '<span class="bl-pin">공지</span>'; }

		$link = '#';
		if (bd_has_detail($p)) { $link = 'post/' . preg_replace('/[^A-Za-z0-9_-]/', '', (string)$p['id']) . '.html'; }

		$cat = '';
		if ($b['hasCat'] && !empty($p['cat'])) { $cat = '<span class="cat-badge">' . bd_enc($p['cat']) . '</span>'; }

		$row = '      <tr><td class="col-no">' . $no . '</td>'
			. '<td class="subject"><a href="' . $link . '">' . $cat . bd_enc($p['title']) . '</a></td>'
			. '<td class="col-date">' . bd_date(isset($p['date']) ? $p['date'] : '') . '</td>';
		if ($b['hasFile']) {
			$ic = '';
			$fn = isset($p['files']) && is_array($p['files']) ? count($p['files']) : 0;
			if ($fn > 0 || !empty($p['legacyFile'])) { $ic = $FILE_IC; }
			$row .= '<td class="col-file">' . $ic . '</td>';
		}
		$row .= '</tr>';
		$rows[] = $row;
	}
	if (!$rows) {
		$span = $b['hasFile'] ? 4 : 3;
		$rows[] = '      <tr><td class="board-empty" colspan="' . $span . '">등록된 글이 없습니다.</td></tr>';
	}

	$table = '  <table class="board-list">' . "\n"
		. '    <thead>' . "\n"
		. '      ' . $cols . "\n"
		. '    </thead>' . "\n"
		. '    <tbody>' . "\n"
		. implode("\n", $rows) . "\n"
		. '    </tbody>' . "\n"
		. '  </table>' . "\n\n"
		. '  <div class="board-pager">' . "\n"
		. '    <a href="#" class="on">1</a>' . "\n"
		. '  </div>';

	return $head . $table;
}

function bd_detail_page($b, $p, $prev, $next, $shellTop, $shellBot) {
	$top = bd_up_path($shellTop);
	$bot = bd_up_path($shellBot);

	/* <title> · 설명 · 히어로 제목 · 이동 경로를 이 글에 맞게 바꾼다 */
	$top = preg_replace('#<title>[\s\S]*?</title>#u', '<title>' . bd_enc($p['title']) . ' — 라성에너지(주)</title>', $top, 1);
	$top = preg_replace('#<meta name="description" content="[^"]*">#u',
		'<meta name="description" content="라성에너지(주) 고객센터 — ' . bd_enc($b['name']) . '">', $top, 1);
	$top = preg_replace('#<h1>[\s\S]*?</h1>#u', '<h1>' . bd_enc($b['name']) . '</h1>', $top, 1);
	$top = preg_replace('#<div class="crumb">[\s\S]*?</div>#u',
		'<div class="crumb"><a href="../index.html">홈</a> · 고객센터 · <a href="../' . $b['file'] . '">' . bd_enc($b['name']) . '</a></div>', $top, 1);

	$catTag = '';
	if ($b['hasCat'] && !empty($p['cat'])) { $catTag = '<span class="cat-badge">' . bd_enc($p['cat']) . '</span>'; }

	$bodyHtml = bd_body(isset($p['content']) ? $p['content'] : '');
	if ($bodyHtml === '') { $bodyHtml = '    <p class="pv-none">본문 내용은 등록되어 있지 않습니다. 첨부파일을 확인해 주세요.</p>'; }

	$fileHtml = '';
	if (!empty($p['files']) && is_array($p['files'])) {
		$fr = array();
		foreach ($p['files'] as $f) {
			$fr[] = '      <li><a href="../' . bd_enc($f['path']) . '" download>' . bd_enc($f['name'])
				. '<span class="fsize">' . bd_size(isset($f['size']) ? $f['size'] : 0) . '</span></a></li>';
		}
		$fileHtml = "\n" . '    <div class="pv-files">' . "\n"
			. '      <span class="pv-files-tit">첨부파일</span>' . "\n"
			. '      <ul>' . "\n" . implode("\n", $fr) . "\n"
			. '      </ul>' . "\n" . '    </div>';
	}

	$prevHtml = '<span class="none">이전 글이 없습니다.</span>';
	if ($prev) { $prevHtml = '<a href="' . preg_replace('/[^A-Za-z0-9_-]/', '', (string)$prev['id']) . '.html">' . bd_enc($prev['title']) . '</a>'; }
	$nextHtml = '<span class="none">다음 글이 없습니다.</span>';
	if ($next) { $nextHtml = '<a href="' . preg_replace('/[^A-Za-z0-9_-]/', '', (string)$next['id']) . '.html">' . bd_enc($next['title']) . '</a>'; }

	$main = '<div class="sub-body">' . "\n"
		. '  <div class="post-view">' . "\n"
		. '    <div class="pv-head">' . "\n"
		. '      <h2 class="pv-tit">' . $catTag . bd_enc($p['title']) . '</h2>' . "\n"
		. '      <div class="pv-meta"><span>' . bd_enc($b['name']) . '</span><span>' . bd_date(isset($p['date']) ? $p['date'] : '') . '</span></div>' . "\n"
		. '    </div>' . "\n"
		. '    <div class="pv-body">' . "\n" . $bodyHtml . "\n" . '    </div>' . $fileHtml . "\n"
		. '    <ul class="pv-nav">' . "\n"
		. '      <li><span class="lb">이전 글</span>' . $prevHtml . '</li>' . "\n"
		. '      <li><span class="lb">다음 글</span>' . $nextHtml . '</li>' . "\n"
		. '    </ul>' . "\n"
		. '    <div class="pv-actions"><a href="../' . $b['file'] . '" class="btn btn-line">목록으로</a></div>' . "\n"
		. '  </div>' . "\n"
		. '</div>' . "\n\n";

	return $top . $main . $bot;
}
