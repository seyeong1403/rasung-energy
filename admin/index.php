<?php
/* 라성에너지(주) 관리자 — 메인 화면 (로그인한 사람만) */
require_once __DIR__ . '/lib.php';
admin_session_start();
if (needs_setup()) { header('Location: setup.php'); exit; }
$me = require_login();
$canEdit = can_edit($me);
$meName = htmlspecialchars(isset($me['name']) ? $me['name'] : $me['id'], ENT_QUOTES, 'UTF-8');
$meRole = $canEdit ? '수정 가능' : '보기 전용';
?>
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>라성에너지(주) 홈페이지 관리자</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<link rel="stylesheet" href="admin.css">
</head>
<body<?php echo $canEdit ? '' : ' class="readonly"'; ?>>

<div id="app">

	<!-- ============ 사이드바 ============ -->
	<aside id="side">
		<div class="side-head">
			<p class="brand">라성에너지<span>(주)</span></p>
			<p class="brand-sub">홈페이지 관리자</p>
		</div>
		<nav class="side-nav">
			<button type="button" data-view="dash" class="on"><span class="ic">■</span>대시보드</button>
			<button type="button" data-view="content"><span class="ic">✎</span>내용 수정</button>
			<button type="button" data-view="company"><span class="ic">☎</span>회사 정보</button>
			<button type="button" data-view="media"><span class="ic">▣</span>사진 관리</button>
			<button type="button" data-view="inquiry"><span class="ic">✉</span>문의 접수<em class="badge" id="inqBadge" hidden>0</em></button>
			<button type="button" data-view="board"><span class="ic">▤</span>공지 · 자료실</button>
			<button type="button" data-view="account"><span class="ic">☺</span>접속 계정</button>
			<button type="button" data-view="backup"><span class="ic">↺</span>백업 · 되돌리기</button>
		</nav>
		<div class="side-foot">
			<p class="side-me"><b><?php echo $meName; ?></b><span><?php echo $meRole; ?></span></p>
			<a href="../index.html" target="_blank" rel="noopener" class="side-link">사이트 새 창으로 열기</a>
			<a href="logout.php" class="side-link out">로그아웃</a>
		</div>
	</aside>

	<!-- ============ 본문 ============ -->
	<main id="main">

		<!-- ---------- 대시보드 ---------- -->
		<section class="view" data-view="dash">
			<header class="view-head">
				<h1>대시보드</h1>
				<p class="view-desc">홈페이지 현황을 한눈에 확인합니다.</p>
			</header>
			<div class="stat-row" id="dashStats"></div>
			<div class="panel">
				<h2 class="panel-tit">바로 하기</h2>
				<div class="quick-row">
					<button type="button" class="quick" data-go="content"><b>글 고치기</b><span>각 페이지의 문구를 수정합니다</span></button>
					<button type="button" class="quick" data-go="company"><b>회사 정보 바꾸기</b><span>전화·주소를 모든 페이지에서 한 번에 바꿉니다</span></button>
					<button type="button" class="quick" data-go="board"><b>공지 올리기</b><span>공지사항·자료실에 글을 등록합니다</span></button>
					<button type="button" class="quick" data-go="inquiry"><b>문의 확인</b><span>홈페이지로 들어온 문의를 봅니다</span></button>
				</div>
			</div>
			<div class="panel">
				<h2 class="panel-tit">최근 문의</h2>
				<div id="dashInq" class="dash-inq"></div>
			</div>
			<div class="panel warn-panel">
				<h2 class="panel-tit">알아두실 점</h2>
				<ul class="check-list" id="dashCheck"></ul>
			</div>
		</section>

		<!-- ---------- 내용 수정 ---------- -->
		<section class="view" data-view="content" hidden>
			<header class="view-head">
				<h1>내용 수정</h1>
				<p class="view-desc">페이지를 고르고 왼쪽 문구를 고친 뒤 <b>저장하기</b>를 누르면 홈페이지에 바로 반영됩니다. 상단 메뉴·푸터처럼 모든 페이지에 같이 들어가는 부분은 <b>회사 정보</b>에서 한 번에 바꿉니다.</p>
			</header>

			<div class="edit-layout">
				<div class="edit-side">
					<div class="page-picker" id="pagePicker"></div>
				</div>

				<div class="edit-body">
					<div class="edit-bar">
						<div class="edit-bar-l">
							<strong id="edTitle">페이지를 선택하세요</strong>
							<span id="edPath" class="edit-path"></span>
						</div>
						<div class="edit-bar-r">
							<span id="edDirty" class="dirty-tag" hidden>수정됨</span>
							<button type="button" id="edReload" class="btn ghost">되돌리기</button>
							<button type="button" id="edSave" class="btn primary" disabled>저장하기</button>
						</div>
					</div>

					<div class="edit-split">
						<div class="edit-fields" id="edFields">
							<p class="empty-msg">왼쪽 목록에서 수정할 페이지를 선택해 주세요.</p>
						</div>
						<div class="edit-preview">
							<div class="prev-bar">
								<span>미리보기</span>
								<div class="prev-btns">
									<button type="button" data-w="1440" class="on">PC</button>
									<button type="button" data-w="768">태블릿</button>
									<button type="button" data-w="390">모바일</button>
								</div>
							</div>
							<div class="prev-stage"><iframe id="edPrev" title="미리보기"></iframe></div>
						</div>
					</div>
				</div>
			</div>
		</section>

		<!-- ---------- 회사 정보 ---------- -->
		<section class="view" data-view="company" hidden>
			<header class="view-head">
				<h1>회사 정보</h1>
				<p class="view-desc">전화번호·주소처럼 <b>모든 페이지에 함께 들어가는 정보</b>입니다. 여기서 한 번 고치면 17개 페이지 전부에 반영됩니다.</p>
			</header>
			<div class="panel">
				<div class="co-form" id="coForm"><p class="empty-msg">불러오는 중…</p></div>
				<div class="modal-btns" style="justify-content:flex-start">
					<button type="button" class="btn primary" id="coSave" disabled>전체 페이지에 반영</button>
					<button type="button" class="btn ghost" id="coReload">되돌리기</button>
				</div>
			</div>
		</section>

		<!-- ---------- 사진 관리 ---------- -->
		<section class="view" data-view="media" hidden>
			<header class="view-head">
				<h1>사진 관리</h1>
				<p class="view-desc">사진 위에 새 파일을 <b>끌어다 놓거나 클릭</b>하면 같은 자리의 사진이 교체됩니다. 원본은 자동으로 백업됩니다.</p>
			</header>
			<div class="filter-bar">
				<label class="sel-wrap">폴더
					<select id="mediaFolder"><option value="">전체</option></select>
				</label>
				<span class="hint" id="mediaCount"></span>
			</div>
			<div id="imgGrid" class="img-grid"><p class="empty-msg">불러오는 중…</p></div>
		</section>

		<!-- ---------- 문의 ---------- -->
		<section class="view" data-view="inquiry" hidden>
			<header class="view-head">
				<h1>문의 접수</h1>
				<p class="view-desc">온라인문의·A/S문의로 들어온 내용과, 전화·메일로 받은 문의를 함께 관리합니다.</p>
			</header>

			<div class="panel notice-panel" id="inqEndpoint"></div>

			<div class="filter-bar">
				<div class="chip-row" id="inqFilter">
					<button type="button" data-st="" class="on">전체</button>
					<button type="button" data-st="new">신규</button>
					<button type="button" data-st="doing">확인중</button>
					<button type="button" data-st="done">답변완료</button>
					<button type="button" data-st="hold">보류</button>
				</div>
				<div class="filter-right">
					<button type="button" id="inqAdd" class="btn ghost">직접 등록</button>
					<button type="button" id="inqCsv" class="btn ghost">엑셀(CSV) 내려받기</button>
				</div>
			</div>

			<div class="inq-layout">
				<div class="inq-list" id="inqList"></div>
				<div class="inq-detail" id="inqDetail"><p class="empty-msg">왼쪽에서 문의를 선택하세요.</p></div>
			</div>
		</section>

		<!-- ---------- 게시판 ---------- -->
		<section class="view" data-view="board" hidden>
			<header class="view-head">
				<h1>공지 · 자료실</h1>
				<p class="view-desc">여기에 등록한 글은 홈페이지 <b>고객센터</b>의 공지사항·자료실에 그대로 올라갑니다.</p>
			</header>

			<div class="filter-bar">
				<div class="chip-row" id="boardFilter">
					<button type="button" data-b="notice" class="on">공지사항</button>
					<button type="button" data-b="info">자료실</button>
				</div>
				<div class="filter-right">
					<button type="button" id="postNew" class="btn primary">새 글 쓰기</button>
					<button type="button" id="boardPublish" class="btn ghost">사이트에 다시 반영</button>
				</div>
			</div>

			<div class="board-layout">
				<div class="post-list" id="postList"></div>
				<div class="post-edit" id="postEdit"><p class="empty-msg">글을 선택하거나 <b>새 글 쓰기</b>를 누르세요.</p></div>
			</div>
		</section>

		<!-- ---------- 접속 계정 ---------- -->
		<section class="view" data-view="account" hidden>
			<header class="view-head">
				<h1>접속 계정</h1>
				<p class="view-desc">이 관리자에 들어올 수 있는 사람을 관리합니다. 아이디와 비밀번호를 알려주면 어느 PC에서든 접속할 수 있습니다.</p>
			</header>

			<div class="panel">
				<h2 class="panel-tit">내 비밀번호 바꾸기</h2>
				<div class="co-form" style="max-width:420px">
					<div class="form-row2"><label>지금 쓰는 비밀번호</label><input type="password" id="pwOld"></div>
					<div class="form-row2"><label>새 비밀번호 <span class="hint">8자 이상</span></label><input type="password" id="pwNew"></div>
					<button type="button" class="btn primary" id="pwSave">비밀번호 바꾸기</button>
				</div>
			</div>

			<div class="panel" id="userPanel">
				<h2 class="panel-tit">계정 목록</h2>
				<p class="panel-desc"><b>수정 가능</b>은 세영님과 똑같이 모든 기능을 씁니다. <b>보기 전용</b>은 내용을 볼 수만 있고 저장·되돌리기가 잠깁니다.</p>
				<div class="user-list" id="userList"></div>
				<button type="button" class="btn primary" id="userAdd" style="margin-top:14px">계정 추가</button>
			</div>
		</section>

		<!-- ---------- 백업 ---------- -->
		<section class="view" data-view="backup" hidden>
			<header class="view-head">
				<h1>백업 · 되돌리기</h1>
				<p class="view-desc">저장할 때마다 고치기 전 파일이 자동으로 보관됩니다. 잘못 고쳤을 때 그 시점으로 되돌릴 수 있습니다.</p>
			</header>

			<div class="panel notice-panel">
				<h2 class="panel-tit">저장하면 바로 반영됩니다</h2>
				<p class="panel-desc">이 관리자는 홈페이지가 올라가 있는 서버에서 직접 동작합니다.
					따로 <b>올리기</b> 과정이 없고, 저장하는 즉시 방문자에게 보이는 화면이 바뀝니다.</p>
			</div>

			<div class="panel">
				<h2 class="panel-tit">자동 백업</h2>
				<div id="backupList" class="backup-list"></div>
			</div>
		</section>

	</main>
</div>

<div id="toast" class="toast" hidden></div>
<div id="modal" class="modal" hidden><div class="modal-box" id="modalBox"></div></div>
<div id="busy" class="busy" hidden><div class="busy-box"><span class="spin"></span><p id="busyMsg">처리 중…</p></div></div>

<script>window.CAN_EDIT = <?php echo $canEdit ? 'true' : 'false'; ?>;</script>
<script src="admin.js"></script>
</body>
</html>
