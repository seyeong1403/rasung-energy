<?php
/* 라성에너지(주) 관리자 — 최초 1회, 관리자 계정 만들기
   계정이 하나라도 있으면 이 화면은 더 이상 열리지 않는다. */
require_once __DIR__ . '/lib.php';
admin_session_start();

if (!needs_setup()) { header('Location: login.php'); exit; }
if (empty($_SESSION['csrf'])) { $_SESSION['csrf'] = bin2hex(random_bytes(16)); }

$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	if (!isset($_POST['csrf']) || !hash_equals($_SESSION['csrf'], $_POST['csrf'])) {
		$err = '요청이 만료되었습니다. 새로고침 후 다시 시도해 주세요.';
	} else {
		$id = trim(isset($_POST['user']) ? $_POST['user'] : '');
		$name = trim(isset($_POST['name']) ? $_POST['name'] : '');
		$pw = (string)(isset($_POST['pass']) ? $_POST['pass'] : '');
		$pw2 = (string)(isset($_POST['pass2']) ? $_POST['pass2'] : '');

		if (!preg_match('/^[A-Za-z0-9_-]{3,20}$/', $id)) {
			$err = '아이디는 영문 · 숫자 3~20자로 지어 주세요.';
		} elseif (strlen($pw) < 8) {
			$err = '비밀번호는 8자 이상으로 정해 주세요.';
		} elseif ($pw !== $pw2) {
			$err = '비밀번호 확인이 일치하지 않습니다.';
		} else {
			save_users(array(array(
				'id' => $id,
				'name' => ($name !== '' ? $name : $id),
				'role' => 'admin',
				'pass' => password_hash($pw, PASSWORD_DEFAULT),
				'at' => date('Y-m-d H:i:s'),
			)));
			session_regenerate_id(true);
			$_SESSION['uid'] = $id;
			header('Location: index.php');
			exit;
		}
	}
}
?>
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>관리자 계정 만들기 — 라성에너지(주)</title>
<link rel="stylesheet" href="gate.css">
</head>
<body>
<div class="box wide">
	<h1>관리자 계정 만들기<span>처음 한 번만 나오는 화면입니다</span></h1>
	<p class="sub">앞으로 홈페이지를 관리할 아이디와 비밀번호를 정해 주세요.
		이 화면은 계정을 만들고 나면 다시 열리지 않습니다.</p>
	<?php if ($err !== '') { echo '<p class="err">' . htmlspecialchars($err, ENT_QUOTES, 'UTF-8') . '</p>'; } ?>
	<form method="post" action="setup.php" autocomplete="off">
		<input type="hidden" name="csrf" value="<?php echo htmlspecialchars($_SESSION['csrf'], ENT_QUOTES, 'UTF-8'); ?>">
		<label for="u">아이디 <em>영문 · 숫자 3~20자</em></label>
		<input id="u" name="user" autofocus required placeholder="예) lasung">
		<label for="n">이름 <em>화면에 표시됩니다</em></label>
		<input id="n" name="name" placeholder="예) 홍길동">
		<label for="p">비밀번호 <em>8자 이상</em></label>
		<input id="p" name="pass" type="password" required>
		<label for="p2">비밀번호 확인</label>
		<input id="p2" name="pass2" type="password" required>
		<button type="submit">계정 만들고 시작하기</button>
	</form>
	<p class="foot">직원용 계정은 나중에 관리자 화면의 「접속 계정」에서 추가할 수 있습니다.</p>
</div>
</body>
</html>
