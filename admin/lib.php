<?php
/* =============================================================
   라성에너지(주) 홈페이지 관리자 — 공통 기능
   -------------------------------------------------------------
   · 웹호스팅(PHP)에서 동작한다. 담당자 PC를 켜 둘 필요가 없다.
   · PHP 7.4 에서 동작하도록 작성했다. (호스팅 서버 기준)

   [중요] 이 사이트의 HTML 은 UTF-8 BOM 이고 줄바꿈이 CRLF/LF 로 섞여 있다.
   그래서 저장할 때 파일 전체를 다시 만들지 않고, 관리자 화면이
   "원본 글자에서 고친 구간만" 바꿔서 보낸 결과를 그대로 기록한다.
   (BOM 유무만 원본에 맞춰 준다)
   ============================================================= */

if (!defined('LASUNG_ADMIN')) { define('LASUNG_ADMIN', 1); }

date_default_timezone_set('Asia/Seoul');
mb_internal_encoding('UTF-8');

define('ADMIN_DIR', __DIR__);
define('SITE_ROOT', dirname(__DIR__));
define('DATA_DIR', ADMIN_DIR . '/data');
define('BACKUP_DIR', ADMIN_DIR . '/backups');
define('UPLOAD_DIR', SITE_ROOT . '/files');

foreach (array(DATA_DIR, BACKUP_DIR) as $d) {
	if (!is_dir($d)) { @mkdir($d, 0755, true); }
}

/* ---------------- 세션 ---------------- */
function admin_session_start() {
	if (session_status() === PHP_SESSION_ACTIVE) { return; }
	session_name('lasungadmin');
	$secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
	if (PHP_VERSION_ID >= 70300) {
		session_set_cookie_params(array(
			'lifetime' => 0, 'path' => '/', 'httponly' => true,
			'samesite' => 'Lax', 'secure' => $secure,
		));
	} else {
		session_set_cookie_params(0, '/', '', $secure, true);
	}
	session_start();
}

/* ---------------- 자료 파일 ----------------
   계정 · 문의 내용은 절대 웹에서 열려서는 안 된다.
   .htaccess 로도 막지만, 그것을 못 쓰는 서버(nginx 등)가 있으므로
   파일 자체를 .php 로 두고 맨 앞에 종료 코드를 넣는다.
   주소로 직접 열어도 빈 화면만 나오고 내용은 보이지 않는다. */
define('JSON_GUARD', "<?php exit; ?>\n");

function data_file($name) { return DATA_DIR . '/' . $name . '.php'; }

/* ---------------- 계정 ---------------- */
function users_file() { return data_file('users'); }

function load_users() {
	return read_json_array(users_file());
}
function save_users($users) {
	write_json(users_file(), array_values($users));
}
function find_user($id) {
	foreach (load_users() as $u) {
		if (isset($u['id']) && $u['id'] === $id) { return $u; }
	}
	return null;
}
/* 계정이 하나도 없으면 최초 설정 화면으로 보낸다 */
function needs_setup() { return count(load_users()) === 0; }

function current_user() {
	admin_session_start();
	if (empty($_SESSION['uid'])) { return null; }
	return find_user($_SESSION['uid']);
}
function require_login() {
	$u = current_user();
	if (!$u) {
		header('Location: login.php');
		exit;
	}
	return $u;
}
function can_edit($u) {
	return $u && isset($u['role']) && $u['role'] === 'admin';
}

/* ---------------- 파일 읽기 / 쓰기 ---------------- */
function has_bom($path) {
	if (!is_file($path)) { return false; }
	$fh = fopen($path, 'rb');
	if (!$fh) { return false; }
	$head = fread($fh, 3);
	fclose($fh);
	return ($head === "\xEF\xBB\xBF");
}
/* BOM 은 걷어내고 돌려준다 (화면에서 다루기 쉽게) */
function read_text($path) {
	$s = file_get_contents($path);
	if ($s === false) { return ''; }
	if (substr($s, 0, 3) === "\xEF\xBB\xBF") { $s = substr($s, 3); }
	return $s;
}
/* 줄바꿈은 손대지 않는다. BOM 유무만 원본에 맞춘다. */
function write_text($path, $text) {
	$dir = dirname($path);
	if (!is_dir($dir)) { @mkdir($dir, 0755, true); }
	$bom = has_bom($path);
	$out = ($bom ? "\xEF\xBB\xBF" : '') . $text;
	$tmp = $path . '.tmp' . getmypid();
	if (file_put_contents($tmp, $out, LOCK_EX) === false) {
		throw new Exception('파일을 저장하지 못했습니다. 폴더 쓰기 권한을 확인해 주세요 : ' . rel_path($path));
	}
	if (!@rename($tmp, $path)) {
		@unlink($tmp);
		if (file_put_contents($path, $out, LOCK_EX) === false) {
			throw new Exception('파일을 저장하지 못했습니다 : ' . rel_path($path));
		}
	}
	@chmod($path, 0644);
}
function write_json($path, $obj) {
	$flags = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES;
	if (defined('JSON_PRETTY_PRINT')) { $flags |= JSON_PRETTY_PRINT; }
	$dir = dirname($path);
	if (!is_dir($dir)) { @mkdir($dir, 0755, true); }
	$body = JSON_GUARD . json_encode($obj, $flags);
	if (file_put_contents($path, $body, LOCK_EX) === false) {
		throw new Exception('데이터를 저장하지 못했습니다 : ' . rel_path($path) . ' (폴더 쓰기 권한을 확인해 주세요)');
	}
	@chmod($path, 0644);
}
function read_json_array($path) {
	if (!is_file($path)) { return array(); }
	$raw = read_text($path);
	/* 맨 앞의 보호용 코드를 걷어낸다 */
	if (strpos($raw, '<?php') === 0) {
		$nl = strpos($raw, "\n");
		$raw = ($nl === false) ? '' : substr($raw, $nl + 1);
	}
	$raw = trim($raw);
	if ($raw === '') { return array(); }
	$j = json_decode($raw, true);
	return is_array($j) ? $j : array();
}
function rel_path($full) {
	$full = str_replace('\\', '/', $full);
	$root = str_replace('\\', '/', SITE_ROOT);
	if (strpos($full, $root) === 0) { return ltrim(substr($full, strlen($root)), '/'); }
	return $full;
}

/* 사이트 폴더 밖으로 나가지 못하게 막는다 */
function resolve_safe($rel) {
	$rel = trim((string)$rel);
	if ($rel === '') { throw new Exception('경로가 비어 있습니다.'); }
	$rel = ltrim(str_replace('\\', '/', $rel), '/');
	if (preg_match('#(^|/)\.\.(/|$)#', $rel)) { throw new Exception('허용되지 않는 경로입니다 : ' . $rel); }
	$full = SITE_ROOT . '/' . $rel;
	$dir = realpath(dirname($full));
	$rootReal = realpath(SITE_ROOT);
	if ($dir === false || $rootReal === false || strpos($dir, $rootReal) !== 0) {
		throw new Exception('작업 폴더 밖입니다 : ' . $rel);
	}
	return $full;
}

/* ---------------- 백업 ---------------- */
function stamp() { return date('Ymd-His'); }

function backup_file($rel) {
	$full = resolve_safe($rel);
	if (!is_file($full)) { return ''; }
	$safe = str_replace(array('/', '\\'), '__', ltrim($rel, '/'));
	$name = stamp() . '__' . $safe;
	@copy($full, BACKUP_DIR . '/' . $name);
	prune_backups();
	return $name;
}
/* 백업이 너무 쌓이면 호스팅 용량을 잡아먹는다. 최근 300개만 남긴다. */
function prune_backups($keep = 300) {
	$files = glob(BACKUP_DIR . '/*');
	if (!$files || count($files) <= $keep) { return; }
	usort($files, function ($a, $b) { return filemtime($b) - filemtime($a); });
	foreach (array_slice($files, $keep) as $f) { @unlink($f); }
}

/* ---------------- 페이지 목록 ---------------- */
function page_defs() {
	return array(
		array('index.html', '메인 (홈)', '메인'),
		array('village-alert.html', '마을재난비상경보시스템', '재난방재시스템'),
		array('quake-alert.html', '지진경보시스템', '재난방재시스템'),
		array('quake-evac.html', '지진대피시스템', '재난방재시스템'),
		array('ai-watch.html', 'AI감시시스템', '재난방재시스템'),
		array('social-disaster.html', '사회재난시스템', '재난방재시스템'),
		array('rescue-equipment.html', '재난구조장비', '재난구조장비'),
		array('rescue-robot.html', '재난구조로봇', '재난구조장비'),
		array('edu-system.html', '재난안전교육시스템', '재난안전교육'),
		array('edu-quake.html', '지진안전교육프로그램', '재난안전교육'),
		array('edu-fire.html', '화재안전교육프로그램', '재난안전교육'),
		array('forest.html', '산림사업', '산림사업'),
		array('about.html', '회사소개', '회사소개'),
		array('notice.html', '공지사항', '고객센터'),
		array('info.html', '자료실', '고객센터'),
		array('qa.html', '온라인문의', '고객센터'),
		array('as.html', 'A/S문의', '고객센터'),
	);
}
function page_list() {
	$out = array();
	foreach (page_defs() as $d) {
		if (!is_file(SITE_ROOT . '/' . $d[0])) { continue; }
		$out[] = array(
			'id' => preg_replace('/\.html$/', '', $d[0]),
			'source' => $d[0],
			'view' => $d[0],
			'title' => $d[1],
			'group' => $d[2],
		);
	}
	return $out;
}

/* ---------------- 사진 ---------------- */
function media_list() {
	$out = array();
	$dirs = array();
	$subRoot = SITE_ROOT . '/assets/sub';
	if (is_dir($subRoot)) {
		foreach (scandir($subRoot) as $d) {
			if ($d === '.' || $d === '..') { continue; }
			if (is_dir($subRoot . '/' . $d)) { $dirs[] = $subRoot . '/' . $d; }
		}
	}
	sort($dirs);
	if (is_dir(SITE_ROOT . '/assets/cases')) { $dirs[] = SITE_ROOT . '/assets/cases'; }

	foreach ($dirs as $dir) {
		$files = scandir($dir);
		sort($files);
		foreach ($files as $f) {
			if (!preg_match('/\.(jpg|jpeg|png|gif|webp)$/i', $f)) { continue; }
			$full = $dir . '/' . $f;
			if (!is_file($full)) { continue; }
			$w = 0; $h = 0;
			$sz = @getimagesize($full);
			if ($sz) { $w = $sz[0]; $h = $sz[1]; }
			$out[] = array(
				'name' => $f,
				'path' => rel_path($full),
				'folder' => basename($dir),
				'size' => filesize($full),
				'kb' => (int)round(filesize($full) / 1024),
				'w' => $w, 'h' => $h,
				'mtime' => date('Y-m-d H:i', filemtime($full)),
			);
		}
	}
	return $out;
}

/* ---------------- 회사 정보 (모든 페이지 공통) ---------------- */
/* 헤더 · 푸터가 17개 파일에 그대로 복사되어 있어서,
   값 하나를 고치면 전체 파일에서 같이 바꿔 준다. */
function company_fields() {
	return array(
		array('key' => 'tel', 'label' => '대표 전화', 'note' => '상단 띠 · 푸터 · 문의 안내에 함께 쓰입니다', 'pattern' => '/054-\d{3}-\d{4}/u'),
		array('key' => 'fax', 'label' => '팩스', 'note' => '', 'pattern' => '/F\. (054-\d{3}-\d{4})/u'),
		array('key' => 'addr', 'label' => '주소', 'note' => '푸터와 회사소개 오시는 길에 쓰입니다', 'pattern' => '/주소 : ([^<]+)<br>/u'),
		array('key' => 'biz', 'label' => '사업자등록번호', 'note' => '', 'pattern' => '/사업자등록번호 : ([\d-]+)/u'),
		array('key' => 'email', 'label' => '이메일', 'note' => '', 'pattern' => '/[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/u'),
		array('key' => 'slogan', 'label' => '상단 띠 문구', 'note' => '모든 페이지 맨 위 가로 띠', 'pattern' => '/<div class="tb-left">([^<]*)<\/div>/u'),
		array('key' => 'copy', 'label' => '저작권 표기', 'note' => '푸터 맨 아래', 'pattern' => '/<div>(Copyright[^<]*)<\/div>/u'),
	);
}
function company_info() {
	$src = read_text(SITE_ROOT . '/index.html');
	$pages = page_list();
	$out = array();
	foreach (company_fields() as $f) {
		$val = '';
		if (preg_match($f['pattern'], $src, $m)) {
			$val = isset($m[1]) ? $m[1] : $m[0];
		}
		$hit = 0;
		if ($val !== '') {
			foreach ($pages as $p) {
				$t = read_text(SITE_ROOT . '/' . $p['source']);
				if (strpos($t, $val) !== false) { $hit++; }
			}
		}
		$out[] = array('key' => $f['key'], 'label' => $f['label'], 'note' => $f['note'], 'value' => $val, 'pages' => $hit);
	}
	return $out;
}
function company_save($items) {
	$changes = array();
	foreach ($items as $it) {
		$old = isset($it['old']) ? (string)$it['old'] : '';
		$new = isset($it['new']) ? (string)$it['new'] : '';
		if ($old === '' || $old === $new) { continue; }
		$changes[] = array($old, $new);
	}
	if (!$changes) { return array('files' => 0, 'hits' => 0); }

	$files = 0; $hits = 0;
	foreach (page_list() as $p) {
		$full = SITE_ROOT . '/' . $p['source'];
		$src = read_text($full);
		$new = $src;
		foreach ($changes as $c) {
			$cnt = 0;
			$new = str_replace($c[0], $c[1], $new, $cnt);
			$hits += $cnt;
		}
		if ($new !== $src) {
			backup_file($p['source']);
			write_text($full, $new);
			$files++;
		}
	}
	return array('files' => $files, 'hits' => $hits);
}

/* ---------------- 응답 ---------------- */
function json_out($obj, $code = 200) {
	http_response_code($code);
	header('Content-Type: application/json; charset=utf-8');
	header('Cache-Control: no-store, no-cache, must-revalidate');
	echo json_encode($obj, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	exit;
}
function json_body() {
	$raw = file_get_contents('php://input');
	if ($raw === '' || $raw === false) { return array(); }
	$j = json_decode($raw, true);
	return is_array($j) ? $j : array();
}
