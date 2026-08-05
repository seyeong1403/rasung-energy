<?php
/* =============================================================
   라성에너지(주) 홈페이지 관리자 — API
   -------------------------------------------------------------
   호출 : admin/api.php?r=<이름>
   · 문의 접수(r=inquiry)만 로그인 없이 받는다. (방문자 폼)
   · 저장 · 배포는 role 이 admin 인 계정만 할 수 있다.
   ============================================================= */
require_once __DIR__ . '/lib.php';

$route = isset($_GET['r']) ? $_GET['r'] : '';
$method = $_SERVER['REQUEST_METHOD'];

header('Cache-Control: no-store, no-cache, must-revalidate');

try {

	/* ---------- 방문자 문의 접수 (로그인 불필요) ---------- */
	if ($route === 'inquiry') {
		if ($method !== 'POST') { json_out(array('ok' => false, 'error' => '잘못된 요청입니다.'), 405); }
		$b = json_body();

		$name = trim((string)(isset($b['name']) ? $b['name'] : ''));
		$msg = trim((string)(isset($b['message']) ? $b['message'] : ''));
		if ($name === '' || $msg === '') { json_out(array('ok' => false, 'error' => '이름과 내용을 입력해 주세요.'), 400); }

		/* 같은 사람이 연속으로 눌러 쌓이는 것만 막는다 */
		$file = data_file('inquiries');
		$items = read_json_array($file);
		if ($items && isset($items[0]['at'])) {
			$last = strtotime($items[0]['at']);
			if ($last && (time() - $last) < 5 && isset($items[0]['name']) && $items[0]['name'] === $name) {
				json_out(array('ok' => true, 'id' => $items[0]['id']));
			}
		}

		$cut = function ($s, $n) { return mb_substr(trim((string)$s), 0, $n); };
		$new = array(
			'id' => date('YmdHis') . substr((string)microtime(true), -3),
			'at' => date('Y-m-d H:i:s'),
			'kind' => $cut(isset($b['kind']) ? $b['kind'] : '문의', 20),
			'name' => $cut($name, 40),
			'tel' => $cut(isset($b['tel']) ? $b['tel'] : '', 40),
			'email' => $cut(isset($b['email']) ? $b['email'] : '', 120),
			'product' => $cut(isset($b['product']) ? $b['product'] : '', 120),
			'subject' => $cut(isset($b['subject']) ? $b['subject'] : '', 200),
			'message' => $cut($msg, 5000),
			'page' => $cut(isset($b['page']) ? $b['page'] : '', 60),
			'status' => 'new',
			'memo' => '',
		);
		array_unshift($items, $new);
		write_json($file, $items);
		json_out(array('ok' => true, 'id' => $new['id']));
	}

	/* ---------- 여기서부터는 로그인이 필요하다 ---------- */
	$me = current_user();
	if (!$me) { json_out(array('ok' => false, 'error' => '로그인이 필요합니다.', 'needLogin' => true), 401); }

	$editor = can_edit($me);
	/* 저장 · 변경은 관리자 계정만 */
	$writeRoutes = array('save', 'company-save', 'media-replace', 'file-upload',
		'inquiries-save', 'inquiry-wire', 'posts-save', 'board-build', 'restore',
		'user-save', 'user-delete', 'password');
	if (in_array($route, $writeRoutes, true) && !$editor && $route !== 'password') {
		json_out(array('ok' => false, 'error' => '이 계정은 보기 전용입니다. 저장 권한이 없습니다.'), 403);
	}

	switch ($route) {

		case 'ping':
			json_out(array('ok' => true, 'root' => SITE_ROOT));

		case 'me':
			json_out(array('ok' => true, 'id' => $me['id'], 'name' => isset($me['name']) ? $me['name'] : $me['id'], 'role' => $me['role'], 'canEdit' => $editor));

		case 'state':
			$inq = read_json_array(data_file('inquiries'));
			$posts = read_json_array(data_file('posts'));
			$newCnt = 0;
			foreach ($inq as $i) { if (isset($i['status']) && $i['status'] === 'new') { $newCnt++; } }
			$pages = page_list();
			json_out(array(
				'ok' => true,
				'pages' => $pages,
				'pageCount' => count($pages),
				'imgCount' => count(media_list()),
				'inqTotal' => count($inq),
				'inqNew' => $newCnt,
				'postTotal' => count($posts),
				'canEdit' => $editor,
				'user' => array('id' => $me['id'], 'name' => isset($me['name']) ? $me['name'] : $me['id'], 'role' => $me['role']),
			));

		/* ---------- 파일 ---------- */
		case 'file':
			$rel = isset($_GET['path']) ? $_GET['path'] : '';
			$full = resolve_safe($rel);
			if (!is_file($full)) { json_out(array('ok' => false, 'error' => '파일이 없습니다 : ' . $rel), 404); }
			$txt = read_text($full);
			/* sig = 지금 파일 상태. 저장할 때 이 값이 그대로면 그 사이 아무도 안 고친 것이다.
			   (글자 수로 비교하면 브라우저와 PHP 의 세는 방식이 달라 잘못 걸린다) */
			json_out(array('ok' => true, 'path' => $rel, 'content' => $txt, 'sig' => md5($txt)));

		/* 화면이 "원본에서 고친 구간만" 바꾼 전체 글자를 보낸다. 그대로 기록한다. */
		case 'save':
			$b = json_body();
			$rel = isset($b['path']) ? $b['path'] : '';
			$full = resolve_safe($rel);
			if (!is_file($full)) { throw new Exception('파일이 없습니다 : ' . $rel); }
			if (!isset($b['content'])) { throw new Exception('저장할 내용이 비었습니다.'); }
			if (!empty($b['baseSig']) && md5(read_text($full)) !== $b['baseSig']) {
				throw new Exception('편집하는 동안 다른 사람이 이 페이지를 고쳤습니다. 되돌리기를 눌러 다시 불러와 주세요.');
			}
			$bk = backup_file($rel);
			write_text($full, $b['content']);
			json_out(array('ok' => true, 'backup' => $bk));

		/* ---------- 회사 정보 ---------- */
		case 'company':
			json_out(array('ok' => true, 'items' => company_info()));

		case 'company-save':
			$b = json_body();
			$r = company_save(isset($b['items']) ? $b['items'] : array());
			json_out(array('ok' => true, 'files' => $r['files'], 'hits' => $r['hits']));

		/* ---------- 사진 ---------- */
		case 'media':
			json_out(array('ok' => true, 'items' => media_list()));

		case 'media-replace':
			$b = json_body();
			$rel = str_replace('\\', '/', isset($b['path']) ? $b['path'] : '');
			if (!preg_match('#^assets/(sub|cases)/#', $rel)) { throw new Exception('교체할 수 있는 위치가 아닙니다 : ' . $rel); }
			if (empty($b['data'])) { throw new Exception('사진 파일이 도착하지 않았습니다. 용량이 너무 크면 서버가 잘라 버립니다. (권장 2MB 이하)'); }
			$full = resolve_safe($rel);
			$bin = base64_decode($b['data'], true);
			if ($bin === false || strlen($bin) < 100) { throw new Exception('사진 파일을 읽지 못했습니다.'); }
			if (is_file($full)) {
				@copy($full, BACKUP_DIR . '/' . stamp() . '__' . str_replace('/', '__', $rel));
				prune_backups();
			}
			if (file_put_contents($full, $bin, LOCK_EX) === false) { throw new Exception('사진을 저장하지 못했습니다. 폴더 권한을 확인해 주세요.'); }
			@chmod($full, 0644);
			$sz = @getimagesize($full);
			json_out(array('ok' => true, 'path' => $rel, 'w' => $sz ? $sz[0] : 0, 'h' => $sz ? $sz[1] : 0));

		/* ---------- 게시판 첨부파일 ---------- */
		case 'file-upload':
			$b = json_body();
			$name = preg_replace('/[\\\\\/:*?"<>|]/', '_', (string)(isset($b['name']) ? $b['name'] : ''));
			if ($name === '') { throw new Exception('파일명이 없습니다.'); }
			if (preg_match('/\.(php\d?|phtml|phar|cgi|pl|py|sh|exe|htaccess)$/i', $name)) {
				throw new Exception('이 형식은 올릴 수 없습니다 : ' . $name);
			}
			if (empty($b['data'])) { throw new Exception('파일이 도착하지 않았습니다. 용량이 너무 크면 서버가 잘라 버립니다.'); }
			if (!is_dir(UPLOAD_DIR)) { @mkdir(UPLOAD_DIR, 0755, true); }
			$dest = UPLOAD_DIR . '/' . $name;
			$base = pathinfo($name, PATHINFO_FILENAME);
			$ext = pathinfo($name, PATHINFO_EXTENSION);
			$i = 2;
			while (is_file($dest)) {
				$name = $base . '_' . $i . ($ext ? '.' . $ext : '');
				$dest = UPLOAD_DIR . '/' . $name;
				$i++;
			}
			$bin = base64_decode($b['data'], true);
			if ($bin === false) { throw new Exception('파일을 읽지 못했습니다.'); }
			file_put_contents($dest, $bin, LOCK_EX);
			@chmod($dest, 0644);
			json_out(array('ok' => true, 'name' => $name, 'path' => 'files/' . $name, 'size' => filesize($dest)));

		/* ---------- 문의 ---------- */
		case 'inquiries':
			json_out(array('ok' => true, 'items' => read_json_array(data_file('inquiries'))));

		case 'inquiries-save':
			$b = json_body();
			write_json(data_file('inquiries'), isset($b['items']) ? array_values($b['items']) : array());
			json_out(array('ok' => true));

		case 'inquiry-state':
			$src = read_text(SITE_ROOT . '/qa.html');
			json_out(array('ok' => true, 'on' => (bool)preg_match('/data-endpoint="[^"]+"/', $src)));

		case 'inquiry-wire':
			$b = json_body();
			$on = !empty($b['on']);
			$val = $on ? 'admin/api.php?r=inquiry' : '';
			$done = 0;
			foreach (array('qa.html', 'as.html') as $f) {
				$full = SITE_ROOT . '/' . $f;
				if (!is_file($full)) { continue; }
				$src = read_text($full);
				$new = preg_replace('/data-endpoint="[^"]*"/', 'data-endpoint="' . $val . '"', $src);
				if ($new !== $src) {
					backup_file($f);
					write_text($full, $new);
					$done++;
				}
			}
			json_out(array('ok' => true, 'files' => $done, 'on' => $on));

		/* ---------- 공지 · 자료실 ---------- */
		case 'posts':
			json_out(array('ok' => true, 'items' => read_json_array(data_file('posts'))));

		case 'posts-save':
			$b = json_body();
			write_json(data_file('posts'), isset($b['items']) ? array_values($b['items']) : array());
			$log = '';
			if (!empty($b['publish'])) {
				require_once __DIR__ . '/board.php';
				$log = board_build();
			}
			json_out(array('ok' => true, 'log' => $log));

		case 'board-build':
			require_once __DIR__ . '/board.php';
			json_out(array('ok' => true, 'log' => board_build()));

		/* ---------- 백업 ---------- */
		case 'backups':
			$items = array();
			$files = glob(BACKUP_DIR . '/*');
			if ($files) {
				usort($files, function ($a, $b) { return filemtime($b) - filemtime($a); });
				foreach (array_slice($files, 0, 200) as $f) {
					$items[] = array(
						'name' => basename($f),
						'at' => date('Y-m-d H:i:s', filemtime($f)),
						'kb' => round(filesize($f) / 1024, 1),
					);
				}
			}
			json_out(array('ok' => true, 'items' => $items));

		case 'restore':
			$b = json_body();
			$name = basename((string)(isset($b['name']) ? $b['name'] : ''));
			$src = BACKUP_DIR . '/' . $name;
			if (!is_file($src)) { throw new Exception('백업 파일이 없습니다.'); }
			$rel = str_replace('__', '/', preg_replace('/^\d{8}-\d{6}__/', '', $name));
			$dest = resolve_safe($rel);
			backup_file($rel);
			if (!@copy($src, $dest)) { throw new Exception('되돌리지 못했습니다 : ' . $rel); }
			json_out(array('ok' => true, 'restored' => $rel));

		/* ---------- 계정 ---------- */
		case 'users':
			$out = array();
			foreach (load_users() as $u) {
				$out[] = array('id' => $u['id'], 'name' => isset($u['name']) ? $u['name'] : $u['id'], 'role' => $u['role'],
					'at' => isset($u['at']) ? $u['at'] : '', 'me' => ($u['id'] === $me['id']));
			}
			json_out(array('ok' => true, 'items' => $out, 'canEdit' => $editor));

		case 'user-save':
			$b = json_body();
			$id = trim((string)(isset($b['id']) ? $b['id'] : ''));
			$name = trim((string)(isset($b['name']) ? $b['name'] : ''));
			$role = (isset($b['role']) && $b['role'] === 'admin') ? 'admin' : 'viewer';
			$pass = (string)(isset($b['pass']) ? $b['pass'] : '');
			if (!preg_match('/^[A-Za-z0-9_-]{3,20}$/', $id)) { throw new Exception('아이디는 영문·숫자 3~20자로 지어 주세요.'); }

			$users = load_users();
			$idx = -1;
			foreach ($users as $k => $u) { if ($u['id'] === $id) { $idx = $k; break; } }

			if ($idx < 0) {
				if (strlen($pass) < 8) { throw new Exception('비밀번호는 8자 이상으로 정해 주세요.'); }
				$users[] = array('id' => $id, 'name' => ($name !== '' ? $name : $id), 'role' => $role,
					'pass' => password_hash($pass, PASSWORD_DEFAULT), 'at' => date('Y-m-d H:i:s'));
			} else {
				$users[$idx]['name'] = ($name !== '' ? $name : $id);
				/* 관리자가 자기 자신을 보기 전용으로 바꿔 잠기는 것을 막는다 */
				if ($id === $me['id'] && $role !== 'admin') { throw new Exception('지금 로그인한 계정의 권한은 낮출 수 없습니다.'); }
				$users[$idx]['role'] = $role;
				if ($pass !== '') {
					if (strlen($pass) < 8) { throw new Exception('비밀번호는 8자 이상으로 정해 주세요.'); }
					$users[$idx]['pass'] = password_hash($pass, PASSWORD_DEFAULT);
				}
			}
			save_users($users);
			json_out(array('ok' => true));

		case 'user-delete':
			$b = json_body();
			$id = (string)(isset($b['id']) ? $b['id'] : '');
			if ($id === $me['id']) { throw new Exception('지금 로그인한 계정은 지울 수 없습니다.'); }
			$users = load_users();
			$left = array();
			$adminLeft = 0;
			foreach ($users as $u) {
				if ($u['id'] === $id) { continue; }
				$left[] = $u;
				if ($u['role'] === 'admin') { $adminLeft++; }
			}
			if ($adminLeft < 1) { throw new Exception('관리자 계정이 하나도 남지 않게 됩니다.'); }
			save_users($left);
			json_out(array('ok' => true));

		/* 내 비밀번호 바꾸기 — 보기 전용 계정도 가능 */
		case 'password':
			$b = json_body();
			$old = (string)(isset($b['old']) ? $b['old'] : '');
			$new = (string)(isset($b['new']) ? $b['new'] : '');
			if (!password_verify($old, $me['pass'])) { throw new Exception('지금 쓰는 비밀번호가 맞지 않습니다.'); }
			if (strlen($new) < 8) { throw new Exception('새 비밀번호는 8자 이상으로 정해 주세요.'); }
			$users = load_users();
			foreach ($users as $k => $u) {
				if ($u['id'] === $me['id']) { $users[$k]['pass'] = password_hash($new, PASSWORD_DEFAULT); }
			}
			save_users($users);
			json_out(array('ok' => true));

		default:
			json_out(array('ok' => false, 'error' => '없는 기능입니다 : ' . $route), 404);
	}

} catch (Exception $e) {
	json_out(array('ok' => false, 'error' => $e->getMessage()), 500);
}
