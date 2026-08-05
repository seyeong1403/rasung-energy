/* =============================================================
   라성에너지(주) 홈페이지 관리자

   [편집 방식]
   이 사이트의 HTML 은 UTF-8 BOM 이고 줄바꿈이 CRLF/LF 로 섞여 있다.
   그래서 문서 전체를 다시 만들어 저장하면 고치지 않은 줄까지 전부
   바뀐 것으로 잡힌다.
   그래서 여기서는
     1) 원본 글자를 그대로 들고 있으면서
     2) 화면 구성만 파싱해서 보여주고
     3) 저장할 때는 "고친 부분의 글자 구간"만 바꿔치기한다.
   원본을 못 찾은 항목은 잠금 표시하고 편집을 막는다. (안전 우선)
   ============================================================= */
(function () {
'use strict';

/* -------------------------------------------------- 잘못 연 경우 안내 */
if (location.protocol === 'file:') {
	document.body.innerHTML =
		'<div style="max-width:620px;margin:14vh auto;padding:38px 40px;font-family:sans-serif;' +
		'background:#fff;border:1px solid #E3E7EC;border-radius:12px;line-height:1.75;word-break:keep-all">' +
		'<h1 style="font-size:22px;font-weight:700;margin-bottom:14px;color:#0C2233">이 방법으로는 열 수 없습니다</h1>' +
		'<p style="color:#57606B;font-size:15px">지금 파일을 직접 열어서(더블클릭) 들어오셨습니다. 이렇게 열면 관리자가 동작하지 않습니다.</p>' +
		'<p style="color:#57606B;font-size:15px;margin-top:14px"><b style="color:#16202A">_admin</b> 폴더의 ' +
		'<b style="color:#16202A">「관리자 실행.cmd」</b> 를 더블클릭해 주세요. 검은 창이 뜨면서 관리자가 자동으로 열립니다.</p>' +
		'<p style="margin-top:22px;padding:14px 16px;background:#F5F7F8;border-radius:8px;font-size:14px;color:#57606B">' +
		'검은 창을 이미 띄우셨다면 브라우저 주소창에 이 주소를 직접 입력하세요<br>' +
		'<b style="color:#0087BC;font-size:15px">http://localhost:8881/admin/</b></p></div>';
	return;
}

/* -------------------------------------------------- 공통 */
const $ = (s, p) => (p || document).querySelector(s);
const $$ = (s, p) => Array.prototype.slice.call((p || document).querySelectorAll(s));

/* 이 계정이 저장까지 할 수 있는지 (시작할 때 서버에 물어본다) */
let CAN_EDIT = true;

async function api(route, body) {
	const opt = body ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : {};
	opt.credentials = 'same-origin';
	let res;
	try {
		res = await fetch('/api/' + route, opt);
	} catch (e) {
		throw new Error('서버와 연결하지 못했습니다. 잠시 뒤 새로고침해 주세요.');
	}
	let json;
	try { json = await res.json(); } catch (e) { throw new Error('서버 응답을 읽을 수 없습니다.'); }
	if (json.needLogin) {
		location.href = '/admin/';
		throw new Error('로그인이 필요합니다.');
	}
	if (!json.ok) throw new Error(json.error || '알 수 없는 오류');
	return json;
}

let toastTimer;
function toast(msg, isErr) {
	const el = $('#toast');
	el.textContent = msg;
	el.className = 'toast' + (isErr ? ' err' : '');
	el.hidden = false;
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => { el.hidden = true; }, isErr ? 5600 : 2600);
}
function busy(on, msg) {
	$('#busyMsg').textContent = msg || '처리 중…';
	$('#busy').hidden = !on;
}
function fail(e) { console.error(e); toast(e.message || String(e), true); busy(false); }

function esc(s) {
	return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
/* 속성값 안에 들어갈 글자 (따옴표만 막으면 된다) */
function escAttr(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/"/g, '&quot;'); }

function confirmBox(title, msg, okLabel) {
	return new Promise(resolve => {
		$('#modalBox').innerHTML =
			'<h3>' + esc(title) + '</h3><p style="color:var(--txt-2);font-size:14.5px;line-height:1.7">' + msg + '</p>' +
			'<div class="modal-btns"><button type="button" class="btn ghost" data-r="0">취소</button>' +
			'<button type="button" class="btn primary" data-r="1">' + esc(okLabel || '확인') + '</button></div>';
		$('#modal').hidden = false;
		$('#modalBox').onclick = e => {
			const b = e.target.closest('[data-r]');
			if (!b) return;
			$('#modal').hidden = true;
			resolve(b.dataset.r === '1');
		};
	});
}
function fileToB64(file) {
	return new Promise((res, rej) => {
		const r = new FileReader();
		r.onload = () => res(String(r.result).split(',')[1]);
		r.onerror = rej;
		r.readAsDataURL(file);
	});
}
function today() {
	const d = new Date();
	return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}
const ENT_BOX = document.createElement('textarea');
function decodeEnt(s) { ENT_BOX.innerHTML = String(s); return ENT_BOX.value; }
/* 태그를 걷어낸 순수 글자 (미리보기와 맞춰 보기 위한 것) */
function plainText(html) {
	return decodeEnt(String(html).replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]*>/g, '')).replace(/\s+/g, ' ').trim();
}

/* -------------------------------------------------- 라우팅 */
let STATE = null;
const views = {};

function go(raw) {
	const parts = String(raw).split('/');
	const name = parts[0], arg = parts[1];
	$$('.side-nav button').forEach(b => b.classList.toggle('on', b.dataset.view === name));
	$$('.view').forEach(v => { v.hidden = v.dataset.view !== name; });
	if (location.hash.slice(1) !== raw) location.hash = raw;
	if (views[name]) views[name](arg);
}
$$('.side-nav button').forEach(b => b.addEventListener('click', () => go(b.dataset.view)));
$$('[data-go]').forEach(b => b.addEventListener('click', () => go(b.dataset.go)));

/* ============================================================
   1. 대시보드
   ============================================================ */
async function loadState() {
	STATE = await api('state');
	const b = $('#inqBadge');
	b.hidden = !STATE.inqNew;
	b.textContent = STATE.inqNew;
	return STATE;
}

views.dash = async function () {
	try {
		const s = await loadState();
		$('#dashStats').innerHTML = [
			['홈페이지 페이지', s.pageCount, '개'],
			['등록된 사진', s.imgCount, '장'],
			['전체 문의', s.inqTotal, '건'],
			['공지 · 자료실 글', s.postTotal, '개']
		].map(x => `<div class="stat"><p class="k">${x[0]}</p><p class="v">${x[1]}<small>${x[2]}</small></p></div>`).join('') +
			`<div class="stat${s.inqNew ? ' alert' : ''}"><p class="k">확인 안 한 문의</p><p class="v">${s.inqNew}<small>건</small></p></div>`;

		const inq = (await api('inquiries')).items || [];
		$('#dashInq').innerHTML = inq.length
			? inq.slice(0, 6).map(i => `<div class="row"><span class="d">${esc(String(i.at).slice(2, 10))}</span>
				<span class="c">${esc(i.name || '-')}</span>
				<span class="m">${esc(i.subject || i.message || '')}</span>
				<span class="st ${i.status}">${stName(i.status)}</span></div>`).join('')
			: '<p class="empty-msg">아직 접수된 문의가 없습니다.</p>';

		let wired = false;
		try { wired = (await api('inquiry-state')).on; } catch (e) {}
		const checks = [
			['상단 메뉴 · 푸터처럼 모든 페이지에 같이 들어가는 정보는 「회사 정보」에서 고쳐야 전 페이지에 반영됩니다.', true],
			['공지사항 · 자료실 목록은 자동으로 만들어집니다. 파일을 직접 고치지 마세요.', true],
			[wired
				? '문의 폼이 이 관리자로 연결되어 있습니다. (관리자를 켜 둔 동안에만 접수됩니다)'
				: '문의 폼이 아직 연결되지 않았습니다. 「문의 접수」 화면에서 연결할 수 있습니다.', wired],
			['기존 공지 15건 · 자료실 12건은 제목과 날짜만 옮겨져 있습니다. 본문을 채우면 상세 페이지가 자동으로 만들어집니다.', false]
		];
		$('#dashCheck').innerHTML = checks.map(c => `<li class="${c[1] ? 'ok' : ''}">${esc(c[0])}</li>`).join('');
	} catch (e) { fail(e); }
};

/* ============================================================
   2. 내용 수정
   ============================================================ */
const INLINE = ['B', 'STRONG', 'EM', 'I', 'U', 'SPAN', 'A', 'BR', 'SMALL', 'SUB', 'SUP', 'MARK', 'ABBR', 'WBR'];
const SKIP_TAG = ['SCRIPT', 'STYLE', 'SVG', 'IFRAME', 'NOSCRIPT', 'VIDEO', 'SOURCE', 'SELECT', 'OPTION', 'BUTTON'];
/* 모든 페이지에 똑같이 복사되어 있는 부분 — 여기서 고치면 그 페이지만 달라진다.
   그래서 편집에서 빼고 「회사 정보」에서 한 번에 바꾸게 한다. */
const SKIP_SEL = '.topbar, .hdr, .footer, .drawer, .scrim, .cursor-cross, .crumb, .sub-back, .board-head, .board-list, .board-pager, .site-toast';

let ED = null;

function buildPagePicker() {
	const groups = {};
	STATE.pages.forEach(p => { (groups[p.group] = groups[p.group] || []).push(p); });
	$('#pagePicker').innerHTML = Object.keys(groups).map(g =>
		`<div class="pp-group">${esc(g)}</div>` +
		groups[g].map(p => `<button type="button" data-id="${esc(p.id)}">${esc(p.title)}</button>`).join('')
	).join('');
	$('#pagePicker').onclick = e => {
		const b = e.target.closest('button[data-id]');
		if (b) openPage(b.dataset.id);
	};
}

views.content = async function (pageId) {
	try {
		if (!STATE) await loadState();
		if (!$('#pagePicker').children.length) buildPagePicker();
		if (pageId && (!ED || ED.page.id !== pageId)) openPage(pageId);
	} catch (e) { fail(e); }
};

async function openPage(id) {
	if (ED && ED.dirty && !(await confirmBox('저장하지 않은 수정이 있습니다', '저장하지 않고 다른 페이지로 이동할까요?', '이동'))) return;
	const page = STATE.pages.find(p => p.id === id);
	if (!page) return;
	busy(true, '페이지를 불러오는 중…');
	try {
		const r = await api('file?path=' + encodeURIComponent(page.source));
		ED = { page, src: r.content, fields: [], dirty: false };
		collectFields();
		renderFields();

		$$('#pagePicker button').forEach(b => b.classList.toggle('on', b.dataset.id === id));
		$('#edTitle').textContent = page.title;
		const locked = ED.fields.filter(f => f.locked).length;
		$('#edPath').textContent = page.source + ' · 편집 가능한 항목 ' + (ED.fields.length - locked) + '개' + (locked ? ' (자동 인식 실패 ' + locked + '개)' : '');
		$('#edSave').disabled = true;
		$('#edDirty').hidden = true;
		$('#edPrev').src = '/' + page.view + '?t=' + Date.now();
		applyPreviewWidth();
	} catch (e) { fail(e); } finally { busy(false); }
}

/* 원본 글자에서 해당 구간의 위치를 찾는다. 커서를 앞으로 밀며 순서대로 찾는다. */
function locate(needle, from) {
	if (!needle) return -1;
	let i = ED.src.indexOf(needle, from);
	if (i < 0) i = ED.src.indexOf(needle);      // 순서가 어긋난 경우 처음부터
	return i;
}

function collectFields() {
	const fields = ED.fields = [];
	const src = ED.src;
	let cursor = 0;

	/* --- 페이지 정보 (검색 · 브라우저 탭) --- */
	const mt = src.match(/<title>([\s\S]*?)<\/title>/i);
	if (mt) {
		const start = mt.index + '<title>'.length;
		fields.push({
			kind: 'tit', type: 'meta',
			group: { key: '__meta', label: '페이지 정보 (검색 · 브라우저 탭)' },
			label: '브라우저 탭에 나오는 이름',
			value: mt[1], text: '', start, end: start + mt[1].length, escape: 'text'
		});
	}
	const md = src.match(/<meta name="description" content="([\s\S]*?)">/i);
	if (md) {
		const start = md.index + md[0].indexOf('content="') + 'content="'.length;
		fields.push({
			kind: '', type: 'meta',
			group: { key: '__meta', label: '페이지 정보 (검색 · 브라우저 탭)' },
			label: '검색 결과에 표시되는 소개글',
			value: md[1], text: '', start, end: start + md[1].length, escape: 'attr'
		});
	}

	/* --- 본문 --- */
	const m = src.match(/<body[^>]*>/i);
	if (!m) return;
	const bodyStart = m.index + m[0].length;
	const bodyEnd = src.lastIndexOf('</body>');
	cursor = bodyStart;

	const doc = new DOMParser().parseFromString(
		'<!doctype html><html><body>' + src.slice(bodyStart, bodyEnd) + '</body></html>', 'text/html');

	/* 원본에서 <img …> 태그를 순서대로 모아 둔다 (alt 편집용) */
	const imgTags = [];
	const imgRe = /<img\b[^>]*>/gi;
	let im;
	while ((im = imgRe.exec(src))) { imgTags.push({ tag: im[0], at: im.index }); }
	let imgSeen = 0;

	/* placeholder 도 순서대로 */
	const phRe = /placeholder="([^"]*)"/gi;
	const phList = [];
	let pm;
	while ((pm = phRe.exec(src))) { phList.push({ val: pm[1], at: pm.index + 'placeholder="'.length }); }
	let phSeen = 0;

	walk(doc.body);

	function walk(node) {
		Array.prototype.forEach.call(node.childNodes, n => {
			/* 태그 사이에 그냥 놓인 글자 (예: <a>안전교육동영상 <svg …></a>) */
			if (n.nodeType === 3) { pushLooseText(n); return; }
			if (n.nodeType !== 1) return;
			const el = n;

			if (SKIP_TAG.indexOf(el.tagName) >= 0) return;
			if (el.matches && el.matches(SKIP_SEL)) return;
			if (el.closest && el.closest(SKIP_SEL)) return;

			if (el.tagName === 'IMG') { pushImg(el); return; }
			if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') { pushPlaceholder(el); return; }

			const kids = Array.prototype.slice.call(el.children);
			const leaf = kids.every(isInlineLeaf);
			const html = el.innerHTML;
			const txt = plainText(html);

			if (leaf && txt) { pushText(el, html, txt); return; }
			walk(el);
		});
	}

	/* 글자 한 덩어리로 볼 수 있는가.
	   <a> 안에 사진이나 칸(div)이 들어 있으면 한 덩어리가 아니므로 더 들어가야 한다.
	   (그래야 카드 묶음이 통째로 한 칸이 되어 버리지 않는다) */
	function isInlineLeaf(c) {
		if (INLINE.indexOf(c.tagName) < 0) return false;
		if (c.querySelector && c.querySelector('div, section, article, ul, ol, li, table, figure, svg, img, video, p, h1, h2, h3, h4, h5, h6, form, input, textarea')) return false;
		return true;
	}

	function pushText(el, html, txt) {
		/* <li><a href="…">글자</a></li> 처럼 링크가 내용 전부이면 링크 안의 글자만 고치게 한다 */
		while (el.children.length === 1 && el.children[0].tagName === 'A'
			&& plainText(el.innerHTML) === plainText(el.children[0].innerHTML)) {
			el = el.children[0];
			html = el.innerHTML;
		}
		let value = html;
		let at = locate(value, cursor);
		/* 원본에 & 가 맨몸으로 쓰인 곳은 브라우저가 &amp; 로 바꿔 읽는다. 한 번 되돌려 찾아본다. */
		if (at < 0 && html.indexOf('&amp;') >= 0) {
			const alt = html.replace(/&amp;/g, '&');
			const at2 = locate(alt, cursor);
			if (at2 >= 0) { value = alt; at = at2; }
		}
		const f = {
			kind: kindOf(el), type: 'html',
			group: groupOf(el),
			label: '', value: value, text: txt,
			start: at, end: at < 0 ? -1 : at + value.length,
			locked: at < 0, escape: 'html'
		};
		if (at >= 0) cursor = f.end;
		fields.push(f);
	}

	function pushLooseText(n) {
		const raw = n.nodeValue;
		if (!raw || !raw.trim()) return;
		const el = n.parentElement;
		if (!el || (el.closest && el.closest(SKIP_SEL))) return;
		const value = raw.trim();
		const at = locate(value, cursor);
		if (at < 0) return;               // 못 찾으면 조용히 넘어간다
		cursor = at + value.length;
		fields.push({
			kind: kindOf(el), type: 'html',
			group: groupOf(el),
			label: '', value: value, text: plainText(value),
			start: at, end: at + value.length, escape: 'html'
		});
	}

	function pushImg(el) {
		const t = imgTags[imgSeen++];
		if (!t) return;
		const am = t.tag.match(/\salt="([^"]*)"/i);
		const file = (el.getAttribute('src') || '').split('/').pop();
		if (!am) return;
		const start = t.at + t.tag.indexOf(am[0]) + am[0].indexOf('"') + 1;
		fields.push({
			kind: 'alt', type: 'attr',
			group: groupOf(el),
			label: '사진 설명 · ' + file,
			value: am[1], text: '',
			start, end: start + am[1].length, escape: 'attr'
		});
	}

	function pushPlaceholder(el) {
		const ph = el.getAttribute('placeholder');
		if (!ph) return;
		const t = phList[phSeen++];
		if (!t) return;
		fields.push({
			kind: 'ph', type: 'attr',
			group: groupOf(el),
			label: '입력칸 안내문 · ' + (el.getAttribute('name') || el.type || ''),
			value: t.val, text: '',
			start: t.at, end: t.at + t.val.length, escape: 'attr'
		});
	}
}

function kindOf(el) {
	if (/^H[1-6]$/.test(el.tagName) || el.classList.contains('eyebrow')) return 'tit';
	return '';
}

const GROUP_CACHE = new WeakMap();
let groupSeq = 0;
function groupOf(el) {
	let n = el;
	while (n && n.parentElement) {
		if (n.tagName === 'SECTION' || n.tagName === 'FOOTER' || n.classList.contains('sub-body') || n.classList.contains('subblock')) break;
		n = n.parentElement;
	}
	if (!n) return { key: '__etc', label: '기타 영역' };
	if (GROUP_CACHE.has(n)) return GROUP_CACHE.get(n);

	let cm = '';
	let p = n.previousSibling;
	while (p && p.nodeType === 3 && !p.textContent.trim()) p = p.previousSibling;
	if (p && p.nodeType === 8) cm = p.textContent.replace(/[*#=-]/g, '').replace(/\s+/g, ' ').trim();

	const titEl = n.querySelector('h1, h2, h3, .sec-tit, .eyebrow');
	let tit = titEl ? plainText(titEl.innerHTML) : '';
	if (tit.length > 30) tit = tit.slice(0, 30) + '…';

	/* 이름을 못 찾으면 바로 앞 제목을 빌려 쓴다. (class 이름을 그대로 보여주지 않는다) */
	let label = tit || cm || '';
	if (!label) {
		let h = n.previousElementSibling;
		while (h && !/^H[1-6]$/.test(h.tagName)) h = h.previousElementSibling;
		label = h ? plainText(h.innerHTML) + ' (이어지는 내용)' : '본문';
	}
	if (n.classList.contains('subpage-hero')) label = '페이지 상단 (큰 제목)';
	else if (n.classList.contains('sub-body')) label = '본문';

	const g = { key: 'g' + (++groupSeq), label, note: (cm && cm !== label) ? cm : '' };
	GROUP_CACHE.set(n, g);
	return g;
}

function renderFields() {
	const order = [];
	const map = new Map();
	ED.fields.forEach((f, i) => {
		f.i = i;
		if (!map.has(f.group.key)) { map.set(f.group.key, []); order.push(f.group); }
		map.get(f.group.key).push(f);
	});

	$('#edFields').innerHTML = order.map((g, gi) => {
		const list = map.get(g.key);
		return `<details class="fgroup" ${gi < 2 ? 'open' : ''}>
			<summary>${esc(g.label)}<em>${list.length}개 항목</em></summary>
			<div class="fgroup-body">${list.map(fieldHtml).join('')}</div>
		</details>`;
	}).join('') || '<p class="empty-msg">이 페이지에서 고칠 수 있는 문구가 없습니다.</p>';

	$$('#edFields textarea').forEach(ta => {
		autoGrow(ta);
		if (ta.disabled) return;
		ta.addEventListener('input', () => { autoGrow(ta); onEdit(ta); });
		ta.addEventListener('focus', () => {
			const f = ED.fields[+ta.dataset.i];
			if (f && f.text) highlightPreview(f.text);
		});
	});
	$('#edFields').onclick = e => {
		const j = e.target.closest('.jump');
		if (j) { const f = ED.fields[+j.dataset.i]; if (f && f.text) highlightPreview(f.text, true); }
	};
}

function fieldHtml(f) {
	const kindLabel = { tit: '제목', alt: '사진 설명', ph: '입력 안내' }[f.kind] || '';
	return `<div class="field ${f.kind}${f.locked ? ' locked' : ''}" data-i="${f.i}">
		<div class="field-head">
			${kindLabel ? `<span class="field-kind ${f.kind}">${esc(kindLabel)}</span>` : ''}
			${f.label ? `<span class="field-note">${esc(f.label)}</span>` : ''}
			${f.locked ? '<span class="field-note">원본 위치를 찾지 못해 잠갔습니다</span>' : ''}
			${f.text ? `<button type="button" class="jump" data-i="${f.i}">미리보기에서 보기</button>` : ''}
		</div>
		<textarea data-i="${f.i}" rows="1"${f.locked ? ' disabled' : ''}>${esc(f.value)}</textarea>
	</div>`;
}

function autoGrow(ta) {
	ta.style.height = 'auto';
	ta.style.height = Math.min(ta.scrollHeight + 2, 400) + 'px';
}
function onEdit(ta) {
	const f = ED.fields[+ta.dataset.i];
	f.next = ta.value;
	ta.closest('.field').classList.toggle('changed', ta.value !== f.value);
	ED.dirty = ED.fields.some(x => x.next != null && x.next !== x.value);
	$('#edSave').disabled = !ED.dirty;
	$('#edDirty').hidden = !ED.dirty;
}

/* --- 미리보기 연동 --- */
function previewDoc() {
	try { return $('#edPrev').contentDocument; } catch (e) { return null; }
}
function highlightPreview(text, scroll) {
	const d = previewDoc();
	if (!d || !d.body) return;
	if (!d.getElementById('__adminHl')) {
		const st = d.createElement('style');
		st.id = '__adminHl';
		st.textContent = '.__hl{outline:3px solid #0087BC !important;outline-offset:3px;background:rgba(0,135,188,.12) !important;transition:.2s}';
		d.head.appendChild(st);
	}
	$$('.__hl', d).forEach(e => e.classList.remove('__hl'));
	const all = d.querySelectorAll('h1,h2,h3,h4,h5,h6,p,li,td,th,dt,dd,strong,span,a,label,figcaption');
	for (const e of all) {
		if (e.textContent.replace(/\s+/g, ' ').trim() === text) {
			e.classList.add('__hl');
			e.scrollIntoView({ block: 'center', behavior: scroll ? 'smooth' : 'auto' });
			return;
		}
	}
}
$('#edPrev').addEventListener('load', () => {
	const d = previewDoc();
	if (!d) return;
	d.addEventListener('click', e => {
		if (!ED) return;
		const t = e.target.textContent.replace(/\s+/g, ' ').trim();
		if (!t) return;
		const f = ED.fields.find(x => x.text === t && !x.locked);
		if (!f) return;
		e.preventDefault();
		const ta = $(`#edFields textarea[data-i="${f.i}"]`);
		if (!ta) return;
		const det = ta.closest('details');
		if (det) det.open = true;
		ta.scrollIntoView({ block: 'center', behavior: 'smooth' });
		ta.focus();
	}, true);
});

/* 미리보기는 실제 화면 폭(PC 1440 등)으로 띄운 뒤 칸에 맞게 줄여서 보여준다 */
function applyPreviewWidth() {
	const b = $('.prev-btns button.on');
	if (!b) return;
	const w = +b.dataset.w;
	const stage = $('.prev-stage'), fr = $('#edPrev');
	const avail = stage.clientWidth - 2;
	const scale = Math.min(1, avail / w);
	fr.style.width = w + 'px';
	fr.style.height = (stage.clientHeight / scale) + 'px';
	fr.style.transform = 'scale(' + scale + ')';
	fr.style.marginLeft = Math.max(0, (avail - w * scale) / 2) + 'px';
}
$$('.prev-btns button').forEach(b => b.addEventListener('click', () => {
	$$('.prev-btns button').forEach(x => x.classList.remove('on'));
	b.classList.add('on');
	applyPreviewWidth();
}));
let prevResizeTimer;
window.addEventListener('resize', () => {
	clearTimeout(prevResizeTimer);
	prevResizeTimer = setTimeout(applyPreviewWidth, 150);
});

$('#edReload').addEventListener('click', async () => {
	if (!ED) return;
	if (ED.dirty && !(await confirmBox('되돌리기', '수정한 내용을 모두 버리고 저장된 상태로 되돌립니다.', '되돌리기'))) return;
	ED.dirty = false;
	openPage(ED.page.id);
});

$('#edSave').addEventListener('click', async () => {
	if (!ED || !ED.dirty) return;
	busy(true, '저장하는 중…');
	try {
		/* 뒤쪽부터 바꿔야 앞쪽 위치가 밀리지 않는다 */
		const edits = ED.fields
			.filter(f => !f.locked && f.next != null && f.next !== f.value && f.start >= 0)
			.sort((a, b) => b.start - a.start);

		let out = ED.src;
		edits.forEach(f => {
			let v = f.next;
			if (f.escape === 'attr') v = escAttr(v);
			out = out.slice(0, f.start) + v + out.slice(f.end);
		});

		await api('save', { path: ED.page.source, content: out, baseLen: ED.src.length });
		toast('저장했습니다. 미리보기를 새로 불러옵니다.');
		const id = ED.page.id;
		ED.dirty = false;
		await openPage(id);
	} catch (e) { fail(e); } finally { busy(false); }
});

window.addEventListener('beforeunload', e => {
	if (ED && ED.dirty) { e.preventDefault(); e.returnValue = ''; }
});

/* ============================================================
   3. 회사 정보 (전 페이지 공통)
   ============================================================ */
let CO = [];

views.company = async function () {
	try {
		CO = (await api('company')).items || [];
		renderCompany();
	} catch (e) { fail(e); }
};

function renderCompany() {
	$('#coForm').innerHTML = CO.map((c, i) => `
		<div class="co-row" data-i="${i}">
			<label for="co_${i}">${esc(c.label)}</label>
			${c.note ? `<p class="co-note">${esc(c.note)}</p>` : ''}
			<input type="text" id="co_${i}" data-i="${i}" value="${esc(c.value)}">
			<p class="co-pages">현재 ${c.pages}개 페이지에 들어 있습니다</p>
		</div>`).join('');
	$('#coSave').disabled = true;
	$$('#coForm input').forEach(inp => inp.addEventListener('input', () => {
		const c = CO[+inp.dataset.i];
		c.next = inp.value;
		inp.closest('.co-row').classList.toggle('changed', inp.value !== c.value);
		$('#coSave').disabled = !CO.some(x => x.next != null && x.next !== x.value);
	}));
}

$('#coReload').addEventListener('click', () => views.company());

$('#coSave').addEventListener('click', async () => {
	const items = CO.filter(c => c.next != null && c.next !== c.value)
		.map(c => ({ old: c.value, new: c.next }));
	if (!items.length) return;
	const list = items.map(i => `<b>${esc(i.old)}</b> → <b>${esc(i.new)}</b>`).join('<br>');
	if (!(await confirmBox('전체 페이지에 반영', '아래 내용을 모든 페이지에서 바꿉니다.<br><br>' + list, '반영하기'))) return;
	busy(true, '전체 페이지를 고치는 중…');
	try {
		const r = await api('company-save', { items });
		toast(`${r.files}개 페이지 · ${r.hits}곳을 바꿨습니다.`);
		await views.company();
	} catch (e) { fail(e); } finally { busy(false); }
});

/* ============================================================
   4. 사진 관리
   ============================================================ */
let MEDIA = null, MEDIA_USE = null;

views.media = async function () {
	if (MEDIA) return;
	try {
		busy(true, '사진을 모으는 중…');
		if (!STATE) await loadState();
		MEDIA = (await api('media')).items || [];

		/* 어느 페이지에서 쓰이는지 찾아 둔다 */
		MEDIA_USE = {};
		for (const p of STATE.pages) {
			const r = await api('file?path=' + encodeURIComponent(p.source));
			MEDIA.forEach(f => {
				if (r.content.indexOf(f.path) >= 0) {
					(MEDIA_USE[f.path] = MEDIA_USE[f.path] || []).push(p.title);
				}
			});
		}

		const folders = [];
		MEDIA.forEach(f => { if (folders.indexOf(f.folder) < 0) folders.push(f.folder); });
		const sel = $('#mediaFolder');
		sel.innerHTML = '<option value="">전체 폴더</option>' +
			folders.map(f => `<option value="${esc(f)}">${esc(f)}</option>`).join('');
		sel.onchange = renderImages;
		renderImages();
	} catch (e) { fail(e); } finally { busy(false); }
};

function renderImages() {
	const fd = $('#mediaFolder').value;
	const list = MEDIA.filter(f => !fd || f.folder === fd);
	$('#mediaCount').textContent = `사진 ${list.length}장`;
	$('#imgGrid').innerHTML = list.map(f => {
		const i = MEDIA.indexOf(f);
		const use = MEDIA_USE[f.path] || [];
		return `<div class="img-card" data-i="${i}">
			<div class="img-thumb">
				<img src="/${esc(f.path)}?t=${esc(String(f.mtime).replace(/\D/g, ''))}" alt="" loading="lazy">
				<div class="drop-hint">클릭하거나 사진을<br>여기로 끌어다 놓으면<br>이 자리 사진이 바뀝니다</div>
			</div>
			<div class="img-body">
				<span class="img-where">${esc(f.folder)}</span>
				<p class="img-name">${esc(f.name)}</p>
				<p class="img-meta">${f.w ? f.w + '×' + f.h + ' · ' : ''}${f.kb}KB</p>
				<p class="img-used">${use.length ? esc(use.join(', ')) : '<span class="tag-unused">사용 안 함</span>'}</p>
			</div>
		</div>`;
	}).join('') || '<p class="empty-msg">사진이 없습니다.</p>';

	$$('#imgGrid .img-card').forEach(card => {
		const i = +card.dataset.i;
		$('.img-thumb', card).addEventListener('click', () => pickFile(i));
		['dragenter', 'dragover'].forEach(ev => card.addEventListener(ev, e => { e.preventDefault(); card.classList.add('drag'); }));
		['dragleave', 'drop'].forEach(ev => card.addEventListener(ev, e => { e.preventDefault(); card.classList.remove('drag'); }));
		card.addEventListener('drop', e => {
			const f = e.dataTransfer.files[0];
			if (f) replaceImage(i, f);
		});
	});
}

function pickFile(i) {
	const inp = document.createElement('input');
	inp.type = 'file';
	inp.accept = 'image/*';
	inp.onchange = () => { if (inp.files[0]) replaceImage(i, inp.files[0]); };
	inp.click();
}

async function replaceImage(i, file) {
	const f = MEDIA[i];
	if (!/^image\//.test(file.type)) return toast('이미지 파일만 올릴 수 있습니다.', true);
	const ext = (f.name.match(/\.[^.]+$/) || [''])[0].toLowerCase();
	const newExt = (file.name.match(/\.[^.]+$/) || [''])[0].toLowerCase();
	if (ext !== newExt && !(ext === '.jpg' && newExt === '.jpeg')) {
		if (!(await confirmBox('형식이 다릅니다',
			`지금 사진은 <b>${esc(ext)}</b> 인데 올리시는 파일은 <b>${esc(newExt)}</b> 입니다.<br>` +
			'같은 파일 이름으로 저장되므로 홈페이지에는 문제없이 표시됩니다. 계속할까요?', '교체'))) return;
	}
	busy(true, '사진을 올리는 중…');
	try {
		const up = await api('media-replace', { path: f.path, data: await fileToB64(file) });
		f.w = up.w; f.h = up.h;
		f.mtime = String(Date.now());
		toast(`사진을 바꿨습니다. (${up.w}×${up.h})`);
		renderImages();
	} catch (e) { fail(e); } finally { busy(false); }
}

/* ============================================================
   5. 문의 접수
   ============================================================ */
let INQ = [], INQ_SEL = null, INQ_FILTER = '';
const ST_NAMES = { new: '신규', doing: '확인중', done: '답변완료', hold: '보류' };
function stName(s) { return ST_NAMES[s] || '신규'; }

views.inquiry = async function () {
	try {
		INQ = (await api('inquiries')).items || [];
		renderInqEndpoint();
		renderInqList();
	} catch (e) { fail(e); }
};

async function renderInqEndpoint() {
	const on = (await api('inquiry-state')).on;
	$('#inqEndpoint').innerHTML = `
		<h2 class="panel-tit">홈페이지 문의 폼 연결 상태</h2>
		<p class="panel-desc">${on
			? '<b>연결됨</b> — 관리자를 켜 둔 동안 홈페이지 온라인문의·A/S문의에 들어온 내용이 이 화면으로 바로 들어옵니다.'
			: '<b>연결 안 됨</b> — 지금은 방문자가 문의를 넣어도 접수되지 않고 안내 문구만 나옵니다. 아래 버튼을 누르면 관리자 실행 중에 실제로 접수됩니다.'}</p>
		<p class="panel-desc" style="color:var(--txt-3)">이 연결은 <b>내 PC에서 열었을 때만</b> 동작합니다. 인터넷에 올려도 방문자에게는 영향이 없습니다.
		방문자 문의를 24시간 받으려면 호스팅 업체의 접수 서버(PHP 등)나 메일 폼 서비스가 필요합니다.</p>
		<button type="button" class="btn ${on ? 'danger' : 'primary'}" id="inqToggle">${on ? '연결 끄기' : '연결 켜기'}</button>`;
	$('#inqToggle').onclick = async () => {
		busy(true, '설정을 바꾸는 중…');
		try {
			await api('inquiry-wire', { on: !on });
			toast(on ? '연결을 껐습니다.' : '연결을 켰습니다. 이제 문의가 이 화면으로 들어옵니다.');
			renderInqEndpoint();
		} catch (e) { fail(e); } finally { busy(false); }
	};
}

$('#inqFilter').addEventListener('click', e => {
	const b = e.target.closest('button');
	if (!b) return;
	$$('#inqFilter button').forEach(x => x.classList.remove('on'));
	b.classList.add('on');
	INQ_FILTER = b.dataset.st;
	renderInqList();
});

function renderInqList() {
	const list = INQ.filter(i => !INQ_FILTER || i.status === INQ_FILTER);
	$('#inqList').innerHTML = list.map(i => `
		<button type="button" class="inq-item ${INQ_SEL === i.id ? 'on' : ''}" data-id="${esc(i.id)}">
			<span class="t"><span class="co">${esc(i.name || '(이름 없음)')}</span>
			<span class="kind-tag">${esc(i.kind || '문의')}</span>
			<span class="st ${i.status}">${stName(i.status)}</span>
			<span class="dt">${esc(String(i.at).slice(5, 16))}</span></span>
			<span class="ms">${esc(i.subject || '')}${i.subject && i.message ? ' · ' : ''}${esc(i.message || '')}</span>
		</button>`).join('') || '<p class="empty-msg">해당하는 문의가 없습니다.</p>';
	$$('#inqList .inq-item').forEach(b => b.onclick = () => { INQ_SEL = b.dataset.id; renderInqList(); renderInqDetail(); });
	if (INQ_SEL) renderInqDetail();
}

function renderInqDetail() {
	const i = INQ.find(x => x.id === INQ_SEL);
	if (!i) { $('#inqDetail').innerHTML = '<p class="empty-msg">왼쪽에서 문의를 선택하세요.</p>'; return; }
	$('#inqDetail').innerHTML = `
		<h3>${esc(i.subject || '(제목 없음)')} <span class="kind-tag">${esc(i.kind || '문의')}</span> <span class="st ${i.status}">${stName(i.status)}</span></h3>
		<table class="dl-table"><tbody>
			<tr><th>접수 일시</th><td>${esc(i.at)}</td></tr>
			<tr><th>이름</th><td>${esc(i.name)}</td></tr>
			<tr><th>연락처</th><td><a href="tel:${esc(i.tel)}">${esc(i.tel)}</a></td></tr>
			<tr><th>이메일</th><td>${i.email ? `<a href="mailto:${esc(i.email)}">${esc(i.email)}</a>` : '-'}</td></tr>
			${i.product ? `<tr><th>제품명 / 모델</th><td>${esc(i.product)}</td></tr>` : ''}
		</tbody></table>
		<div class="inq-msg">${esc(i.message)}</div>
		<div class="inq-actions">
			${Object.keys(ST_NAMES).map(k => `<button type="button" class="btn ${i.status === k ? 'primary' : 'ghost'} sm" data-set="${k}">${ST_NAMES[k]}</button>`).join('')}
			${i.email ? `<a class="btn ghost sm" href="mailto:${esc(i.email)}?subject=${encodeURIComponent('[라성에너지] 문의 답변')}">메일로 답변</a>` : ''}
			<button type="button" class="btn danger sm" data-del="1" style="margin-left:auto">삭제</button>
		</div>
		<div class="form-row2"><label>내부 메모</label><textarea id="inqMemo" rows="3" style="min-height:auto">${esc(i.memo || '')}</textarea></div>
		<button type="button" class="btn ghost sm" id="inqMemoSave">메모 저장</button>`;

	$$('#inqDetail [data-set]').forEach(b => b.onclick = async () => { i.status = b.dataset.set; await saveInq(); renderInqList(); renderInqDetail(); loadState(); });
	$('#inqMemoSave').onclick = async () => { i.memo = $('#inqMemo').value; await saveInq(); toast('메모를 저장했습니다.'); };
	$('#inqDetail [data-del]').onclick = async () => {
		if (!(await confirmBox('문의 삭제', '이 문의를 지웁니다. 되돌릴 수 없습니다.', '삭제'))) return;
		INQ = INQ.filter(x => x.id !== i.id);
		INQ_SEL = null;
		await saveInq();
		renderInqList();
		$('#inqDetail').innerHTML = '<p class="empty-msg">왼쪽에서 문의를 선택하세요.</p>';
		loadState();
	};
}
async function saveInq() { await api('inquiries-save', { items: INQ }); }

$('#inqAdd').addEventListener('click', () => {
	$('#modalBox').innerHTML = `<h3>문의 직접 등록</h3>
		<p style="color:var(--txt-2);font-size:14px;margin-bottom:16px">전화나 메일로 받은 문의를 기록해 둡니다.</p>
		${['이름|name', '연락처|tel', '이메일|email', '제품명 / 모델|product', '제목|subject'].map(x => {
		const p = x.split('|');
		return `<div class="form-row2"><label>${p[0]}</label><input type="text" id="m_${p[1]}"></div>`;
	}).join('')}
		<div class="form-row2"><label>구분</label>
			<select id="m_kind"><option>온라인문의</option><option>A/S문의</option><option>전화 문의</option><option>기타</option></select></div>
		<div class="form-row2"><label>문의 내용</label><textarea id="m_message" rows="5" style="min-height:auto"></textarea></div>
		<div class="modal-btns"><button type="button" class="btn ghost" data-c="1">취소</button><button type="button" class="btn primary" id="m_ok">등록</button></div>`;
	$('#modal').hidden = false;
	$('#modalBox').querySelector('[data-c]').onclick = () => { $('#modal').hidden = true; };
	$('#m_ok').onclick = async () => {
		const now = new Date();
		INQ.unshift({
			id: String(now.getTime()),
			at: now.toISOString().slice(0, 19).replace('T', ' '),
			kind: $('#m_kind').value, name: $('#m_name').value, tel: $('#m_tel').value,
			email: $('#m_email').value, product: $('#m_product').value,
			subject: $('#m_subject').value, message: $('#m_message').value,
			status: 'new', memo: '(직접 등록)'
		});
		await saveInq();
		$('#modal').hidden = true;
		renderInqList();
		loadState();
		toast('등록했습니다.');
	};
});

$('#inqCsv').addEventListener('click', () => {
	const head = ['접수일시', '구분', '이름', '연락처', '이메일', '제품명', '제목', '내용', '상태', '메모'];
	const rows = INQ.map(i => [i.at, i.kind, i.name, i.tel, i.email, i.product, i.subject, i.message, stName(i.status), i.memo]);
	const csv = [head].concat(rows)
		.map(r => r.map(c => '"' + String(c == null ? '' : c).replace(/"/g, '""') + '"').join(',')).join('\r\n');
	const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
	const a = document.createElement('a');
	a.href = URL.createObjectURL(blob);
	a.download = '라성에너지_문의_' + today() + '.csv';
	a.click();
});

/* ============================================================
   6. 공지 · 자료실
   ============================================================ */
let POSTS = [], POST_SEL = null, BOARD = 'notice';
const BOARD_NAME = { notice: '공지사항', info: '자료실' };

views.board = async function () {
	try {
		POSTS = (await api('posts')).items || [];
		renderPostList();
	} catch (e) { fail(e); }
};

$('#boardFilter').addEventListener('click', e => {
	const b = e.target.closest('button');
	if (!b) return;
	$$('#boardFilter button').forEach(x => x.classList.remove('on'));
	b.classList.add('on');
	BOARD = b.dataset.b;
	POST_SEL = null;
	renderPostList();
	$('#postEdit').innerHTML = '<p class="empty-msg">글을 선택하거나 <b>새 글 쓰기</b>를 누르세요.</p>';
});

function renderPostList() {
	const list = POSTS.filter(p => p.board === BOARD)
		.sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0)
			|| String(b.date).localeCompare(String(a.date))
			|| (b.no || 0) - (a.no || 0));
	$('#postList').innerHTML = list.map(p => `
		<button type="button" class="post-item ${POST_SEL === p.id ? 'on' : ''}" data-id="${esc(p.id)}">
			<span class="pt">${p.pinned ? '<span class="pin">고정</span>' : ''}${p.published === false ? '<span class="draft">비공개</span>' : ''}${String(p.content || '').trim() || (p.files || []).length ? '' : '<span class="nocontent">본문 없음</span>'}${esc(p.title)}</span>
			<span class="pd">${esc(p.date)}${p.cat ? ' · ' + esc(p.cat) : ''}${(p.files || []).length ? ' · 첨부 ' + p.files.length : ''}</span>
		</button>`).join('') || '<p class="empty-msg">등록된 글이 없습니다.</p>';
	$$('#postList .post-item').forEach(b => b.onclick = () => { POST_SEL = b.dataset.id; renderPostList(); editPost(POSTS.find(p => p.id === b.dataset.id)); });
}

$('#postNew').addEventListener('click', () => {
	POST_SEL = null;
	renderPostList();
	editPost({ id: '', board: BOARD, no: 0, title: '', date: today(), cat: '', content: '', files: [], legacyFile: false, pinned: false, published: true });
});

function editPost(p) {
	const cur = JSON.parse(JSON.stringify(p));
	if (!cur.files) cur.files = [];
	const isInfo = BOARD === 'info';
	$('#postEdit').innerHTML = `
		<div class="form-row2 row-2col">
			<div><label>제목</label><input type="text" id="p_title" value="${esc(cur.title)}" placeholder="제목을 입력하세요"></div>
			<div style="flex:0 0 170px"><label>작성일</label><input type="date" id="p_date" value="${esc(cur.date)}"></div>
		</div>
		${isInfo ? `<div class="form-row2" style="max-width:240px"><label>분류</label>
			<input type="text" id="p_cat" value="${esc(cur.cat || '')}" placeholder="예) 재난방재"></div>` : ''}
		<div class="form-row2"><label>내용</label>
			<textarea id="p_content" placeholder="내용을 입력하세요.&#10;&#10;줄을 비우면 문단이 나뉩니다.">${esc(cur.content)}</textarea>
			<p class="editor-help">엔터로 줄바꿈, 빈 줄로 문단 나눔. 강조는 **굵게**, 인터넷 주소를 적으면 자동으로 연결됩니다.<br>
			내용이나 첨부파일이 있어야 목록에서 <b>제목을 눌러 열어볼 수 있는 상세 페이지</b>가 만들어집니다.</p>
		</div>
		<div class="form-row2">
			<label>첨부파일</label>
			<button type="button" class="btn ghost sm" id="p_addFile">파일 추가</button>
			<div class="attach-list" id="p_files"></div>
		</div>
		<div class="form-row2" style="display:flex;gap:20px;flex-wrap:wrap">
			<label class="chk"><input type="checkbox" id="p_pin" ${cur.pinned ? 'checked' : ''}>목록 맨 위에 고정</label>
			<label class="chk"><input type="checkbox" id="p_pub" ${cur.published !== false ? 'checked' : ''}>홈페이지에 공개</label>
			${isInfo ? `<label class="chk"><input type="checkbox" id="p_legacy" ${cur.legacyFile ? 'checked' : ''}>목록에 첨부 아이콘 표시</label>` : ''}
		</div>
		<div class="modal-btns" style="justify-content:flex-start">
			<button type="button" class="btn primary" id="p_save">저장하고 사이트에 반영</button>
			${cur.id ? '<button type="button" class="btn danger" id="p_del" style="margin-left:auto">글 삭제</button>' : ''}
		</div>`;

	const drawFiles = () => {
		$('#p_files').innerHTML = cur.files.map((f, i) =>
			`<div class="attach-row"><span>${esc(f.name)}</span><button type="button" class="btn ghost sm" data-rm="${i}">빼기</button></div>`).join('');
		$$('#p_files [data-rm]').forEach(b => b.onclick = () => { cur.files.splice(+b.dataset.rm, 1); drawFiles(); });
	};
	drawFiles();

	$('#p_addFile').onclick = () => {
		const inp = document.createElement('input');
		inp.type = 'file';
		inp.onchange = async () => {
			const f = inp.files[0];
			if (!f) return;
			busy(true, '파일을 올리는 중…');
			try {
				const up = await api('file-upload', { name: f.name, data: await fileToB64(f) });
				cur.files.push({ name: f.name, path: up.path, size: up.size });
				drawFiles();
			} catch (e) { fail(e); } finally { busy(false); }
		};
		inp.click();
	};

	$('#p_save').onclick = async () => {
		cur.title = $('#p_title').value.trim();
		cur.date = $('#p_date').value;
		cur.content = $('#p_content').value;
		cur.pinned = $('#p_pin').checked;
		cur.published = $('#p_pub').checked;
		cur.board = BOARD;
		if (isInfo) {
			cur.cat = $('#p_cat').value.trim();
			cur.legacyFile = $('#p_legacy').checked;
		}
		if (!cur.title) return toast('제목을 입력해 주세요.', true);
		busy(true, '저장하고 사이트에 반영하는 중…');
		try {
			if (!cur.id) {
				const same = POSTS.filter(x => x.board === BOARD);
				cur.no = same.reduce((m, x) => Math.max(m, +x.no || 0), 0) + 1;
				cur.id = BOARD + '-' + cur.no;
				while (POSTS.some(x => x.id === cur.id)) { cur.no++; cur.id = BOARD + '-' + cur.no; }
				POSTS.push(cur);
			} else {
				POSTS[POSTS.findIndex(x => x.id === cur.id)] = cur;
			}
			await api('posts-save', { items: POSTS, publish: true });
			POST_SEL = cur.id;
			renderPostList();
			toast('저장했습니다. 홈페이지 ' + BOARD_NAME[BOARD] + '에 반영되었습니다.');
		} catch (e) { fail(e); } finally { busy(false); }
	};

	if (cur.id) $('#p_del').onclick = async () => {
		if (!(await confirmBox('글 삭제', '이 글을 홈페이지에서 지웁니다.', '삭제'))) return;
		POSTS = POSTS.filter(x => x.id !== cur.id);
		await api('posts-save', { items: POSTS, publish: true });
		POST_SEL = null;
		renderPostList();
		$('#postEdit').innerHTML = '<p class="empty-msg">글을 선택하거나 <b>새 글 쓰기</b>를 누르세요.</p>';
		toast('삭제했습니다.');
	};
}

$('#boardPublish').addEventListener('click', async () => {
	busy(true, '게시판을 다시 만드는 중…');
	try {
		const r = await api('board-build');
		toast('게시판을 사이트에 반영했습니다.');
		console.log(r.log);
	} catch (e) { fail(e); } finally { busy(false); }
});

/* ============================================================
   7. 배포 · 백업
   ============================================================ */
views.deploy = async function () {
	try {
		const r = await api('backups');
		$('#backupList').innerHTML = r.items.length ? r.items.map(b => `
			<div class="bk-row">
				<span class="f">${esc(b.name.replace(/^\d{8}-\d{6}__/, '').replace(/__/g, ' / '))}</span>
				<span class="t">${esc(b.at)}</span>
				<button type="button" class="btn ghost sm" data-bk="${esc(b.name)}">이 시점으로 되돌리기</button>
			</div>`).join('') : '<p class="empty-msg">아직 백업이 없습니다.</p>';
		$$('#backupList [data-bk]').forEach(b => b.onclick = async () => {
			if (!(await confirmBox('되돌리기', '이 시점의 파일로 되돌립니다. 지금 상태는 새 백업으로 보관됩니다.', '되돌리기'))) return;
			busy(true, '되돌리는 중…');
			try { await api('restore', { name: b.dataset.bk }); toast('되돌렸습니다.'); views.deploy(); }
			catch (e) { fail(e); } finally { busy(false); }
		});
	} catch (e) { fail(e); }
};

$('#gitStatus').addEventListener('click', async () => {
	busy(true, '확인 중…');
	try {
		const r = await api('git-status');
		$('#statusLog').hidden = false;
		$('#statusLog').textContent = r.log.trim() || '변경된 파일이 없습니다. (모두 반영됨)';
	} catch (e) { fail(e); } finally { busy(false); }
});

$('#gitPush').addEventListener('click', async () => {
	const msg = $('#gitMsg').value.trim() || '관리자에서 콘텐츠 수정';
	if (!(await confirmBox('사이트에 올리기', '수정한 내용을 인터넷에 공개합니다.<br>1~2분 뒤 반영됩니다.', '올리기'))) return;
	busy(true, '사이트에 올리는 중…');
	try {
		const r = await api('git-push', { message: msg });
		$('#gitLog').hidden = false;
		$('#gitLog').textContent = r.log;
		$('#gitMsg').value = '';
		toast('올렸습니다. 1~2분 뒤 사이트에 반영됩니다.');
	} catch (e) { fail(e); } finally { busy(false); }
});

/* ============================================================
   7. 접속 계정
   ============================================================ */
const ROLE_NAME = { admin: '수정 가능', viewer: '보기 전용' };

views.account = async function () {
	try {
		const r = await api('users');
		$('#userPanel').hidden = !r.canEdit;
		$('#userList').innerHTML = r.items.map(u => `
			<div class="user-row">
				<span class="uid">${esc(u.id)}${u.me ? '<em>나</em>' : ''}</span>
				<span class="unm">${esc(u.name)}</span>
				<span class="urole ${u.role}">${ROLE_NAME[u.role] || u.role}</span>
				<span class="uat">${esc(u.at || '')}</span>
				<span class="ubtn">
					<button type="button" class="btn ghost sm" data-edit="${esc(u.id)}">고치기</button>
					${u.me ? '' : `<button type="button" class="btn danger sm" data-del="${esc(u.id)}">삭제</button>`}
				</span>
			</div>`).join('') || '<p class="empty-msg">계정이 없습니다.</p>';

		$$('#userList [data-edit]').forEach(b => b.onclick = () => {
			userForm(r.items.find(x => x.id === b.dataset.edit));
		});
		$$('#userList [data-del]').forEach(b => b.onclick = async () => {
			if (!(await confirmBox('계정 삭제', `<b>${esc(b.dataset.del)}</b> 계정을 지웁니다. 이 아이디로는 더 이상 들어올 수 없습니다.`, '삭제'))) return;
			busy(true, '지우는 중…');
			try { await api('user-delete', { id: b.dataset.del }); toast('지웠습니다.'); views.account(); }
			catch (e) { fail(e); } finally { busy(false); }
		});
	} catch (e) { fail(e); }
};

function userForm(u) {
	const isNew = !u;
	$('#modalBox').innerHTML = `<h3>${isNew ? '계정 추가' : '계정 고치기'}</h3>
		<div class="form-row2"><label>아이디 <span class="hint">영문·숫자 3~20자</span></label>
			<input type="text" id="u_id" value="${esc(isNew ? '' : u.id)}" ${isNew ? '' : 'readonly'}></div>
		<div class="form-row2"><label>이름</label><input type="text" id="u_name" value="${esc(isNew ? '' : u.name)}" placeholder="예) 홍길동"></div>
		<div class="form-row2"><label>권한</label>
			<select id="u_role">
				<option value="admin"${(!isNew && u.role === 'admin') ? ' selected' : ''}>수정 가능 — 모든 기능</option>
				<option value="viewer"${(!isNew && u.role === 'viewer') ? ' selected' : ''}>보기 전용 — 저장·되돌리기 잠김</option>
			</select></div>
		<div class="form-row2"><label>비밀번호 <span class="hint">${isNew ? '8자 이상' : '바꿀 때만 입력'}</span></label>
			<input type="password" id="u_pass" autocomplete="new-password"></div>
		<div class="modal-btns"><button type="button" class="btn ghost" data-c="1">취소</button>
			<button type="button" class="btn primary" id="u_ok">저장</button></div>`;
	$('#modal').hidden = false;
	$('#modalBox').querySelector('[data-c]').onclick = () => { $('#modal').hidden = true; };
	$('#u_ok').onclick = async () => {
		busy(true, '저장하는 중…');
		try {
			await api('user-save', {
				id: $('#u_id').value.trim(), name: $('#u_name').value.trim(),
				role: $('#u_role').value, pass: $('#u_pass').value
			});
			$('#modal').hidden = true;
			toast('저장했습니다.');
			views.account();
		} catch (e) { fail(e); } finally { busy(false); }
	};
}

$('#userAdd').addEventListener('click', () => userForm(null));

$('#pwSave').addEventListener('click', async () => {
	const o = $('#pwOld').value, n = $('#pwNew').value;
	if (!o || !n) return toast('비밀번호를 입력해 주세요.', true);
	busy(true, '바꾸는 중…');
	try {
		await api('password', { old: o, new: n });
		$('#pwOld').value = ''; $('#pwNew').value = '';
		toast('비밀번호를 바꿨습니다. 다음 로그인부터 적용됩니다.');
	} catch (e) { fail(e); } finally { busy(false); }
});

/* -------------------------------------------------- 시작 */
(async () => {
	try {
		const m = await api('me');
		CAN_EDIT = !!m.canEdit;
		const el = $('#sideMe');
		el.hidden = false;
		$('b', el).textContent = m.name || m.id;
		$('span', el).textContent = ROLE_NAME[m.role] || '';
		if (!CAN_EDIT) {
			document.body.classList.add('readonly');
			['#edSave', '#coSave', '#postNew', '#boardPublish', '#inqAdd', '#gitPush'].forEach(s => {
				const b = $(s);
				if (b) { b.disabled = true; b.title = '보기 전용 계정입니다.'; }
			});
		}
	} catch (e) { /* 로그인 화면으로 넘어간다 */ }
	go((location.hash || '#dash').slice(1));
})();

})();
