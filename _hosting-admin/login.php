<?php
/* 라성에너지(주) 관리자 — 로그인 */
require_once __DIR__ . '/lib.php';
admin_session_start();

if (needs_setup()) { header('Location: setup.php'); exit; }
if (current_user()) { header('Location: index.php'); exit; }

if (empty($_SESSION['csrf'])) { $_SESSION['csrf'] = bin2hex(random_bytes(16)); }

$err = '';
$lockFile = data_file('lockout');

/* 비밀번호를 계속 찍어 보는 것을 막는다 (같은 접속지 5회 실패 → 5분 대기) */
function lock_key() {
	$ip = isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : 'unknown';
	return substr(hash('sha256', $ip), 0, 16);
}
function lock_get($file) {
	$j = read_json_array($file);
	return is_array($j) ? $j : array();
}
function lock_left($file) {
	$all = lock_get($file);
	$k = lock_key();
	if (empty($all[$k])) { return 0; }
	$r = $all[$k];
	if (!isset($r['n']) || $r['n'] < 5) { return 0; }
	$left = 300 - (time() - (int)$r['t']);
	return $left > 0 ? $left : 0;
}
function lock_fail($file) {
	$all = lock_get($file);
	$k = lock_key();
	$n = (isset($all[$k]['n']) && (time() - (int)$all[$k]['t']) < 300) ? (int)$all[$k]['n'] : 0;
	$all[$k] = array('n' => $n + 1, 't' => time());
	/* 오래된 기록은 버린다 */
	foreach ($all as $kk => $vv) { if (time() - (int)$vv['t'] > 3600) { unset($all[$kk]); } }
	try { write_json($file, $all); } catch (Exception $e) {}
}
function lock_clear($file) {
	$all = lock_get($file);
	unset($all[lock_key()]);
	try { write_json($file, $all); } catch (Exception $e) {}
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	$wait = lock_left($lockFile);
	if ($wait > 0) {
		$err = '비밀번호를 여러 번 잘못 입력했습니다. ' . ceil($wait / 60) . '분 뒤에 다시 시도해 주세요.';
	} elseif (!isset($_POST['csrf']) || !hash_equals($_SESSION['csrf'], $_POST['csrf'])) {
		$err = '요청이 만료되었습니다. 다시 시도해 주세요.';
	} else {
		$id = isset($_POST['user']) ? trim($_POST['user']) : '';
		$pw = isset($_POST['pass']) ? (string)$_POST['pass'] : '';
		$u = find_user($id);
		if ($u && password_verify($pw, $u['pass'])) {
			lock_clear($lockFile);
			session_regenerate_id(true);
			$_SESSION['uid'] = $u['id'];
			header('Location: index.php');
			exit;
		}
		lock_fail($lockFile);
		$err = '아이디 또는 비밀번호가 맞지 않습니다.';
	}
}
?>
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>라성에너지(주) 홈페이지 관리자</title>
<link rel="stylesheet" href="gate.css">
</head>
<body>
<div class="box">
	<h1>라성에너지(주)<span>홈페이지 관리자</span></h1>
	<p class="sub">아이디와 비밀번호를 입력해 주세요.</p>
	<?php if ($err !== '') { echo '<p class="err">' . htmlspecialchars($err, ENT_QUOTES, 'UTF-8') . '</p>'; } ?>
	<form method="post" action="login.php" autocomplete="on">
		<input type="hidden" name="csrf" value="<?php echo htmlspecialchars($_SESSION['csrf'], ENT_QUOTES, 'UTF-8'); ?>">
		<label for="u">아이디</label>
		<input id="u" name="user" autocomplete="username" autofocus required>
		<label for="p">비밀번호</label>
		<input id="p" name="pass" type="password" autocomplete="current-password" required>
		<button type="submit">들어가기</button>
	</form>
	<p class="foot">담당자에게 받은 아이디와 비밀번호가 필요합니다.</p>
</div>
</body>
</html>
