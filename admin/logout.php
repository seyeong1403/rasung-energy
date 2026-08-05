<?php
/* 라성에너지(주) 관리자 — 로그아웃 */
require_once __DIR__ . '/lib.php';
admin_session_start();
$_SESSION = array();
if (ini_get('session.use_cookies')) {
	$p = session_get_cookie_params();
	setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
}
session_destroy();
header('Location: login.php');
exit;
