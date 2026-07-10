/* 라성에너지(주) 리디자인 시안 — 공용 인터랙션
   - 서버가 필요한 버튼(로그인/회원가입/약관/브로셔/게시글 상세 등)은 "준비 중" 토스트
   - 클라이언트로 가능한 기능(게시판 검색 필터, 문의 폼 접수)은 실제 동작 */
(function () {
  'use strict';

  // ---- 토스트 ----
  var toastTimer;
  function toast(msg) {
    var el = document.getElementById('siteToast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'siteToast';
      el.className = 'site-toast';
      el.setAttribute('role', 'status');
      document.body.appendChild(el);
    }
    el.textContent = msg;
    // 리플로우 후 표시(연속 호출 시 애니메이션 재생)
    void el.offsetWidth;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.classList.remove('show'); }, 2200);
  }
  window.__toast = toast;

  document.addEventListener('DOMContentLoaded', function () {

    // ---- 비활성(#) 링크: 클릭 시 안내 ----
    document.addEventListener('click', function (e) {
      var a = e.target.closest('a');
      if (!a) return;
      if (a.getAttribute('href') !== '#') return;   // 실제 링크/앵커(#xxx)는 통과
      e.preventDefault();
      if (a.closest('.board-pager')) return;         // 현재 페이지 번호 — 무동작
      if (a.closest('.subject')) { toast('게시글 상세 페이지는 준비 중입니다.'); return; }
      if (a.classList.contains('tb-search')) { toast('통합 검색은 준비 중입니다.'); return; }
      toast('준비 중입니다.');
    });

    // ---- 게시판 검색: 실시간 필터 ----
    document.querySelectorAll('.board-search').forEach(function (form) {
      var input = form.querySelector('input');
      var table = document.querySelector('.board-list');
      var totalB = document.querySelector('.board-head .total b');
      var totalAll = totalB ? totalB.textContent : null;
      if (!input || !table) return;
      function apply() {
        var q = input.value.trim().toLowerCase();
        var shown = 0;
        table.querySelectorAll('tbody tr').forEach(function (tr) {
          var subj = tr.querySelector('.subject');
          var t = (subj ? subj.textContent : tr.textContent).toLowerCase();
          var hit = !q || t.indexOf(q) !== -1;
          tr.style.display = hit ? '' : 'none';
          if (hit) shown++;
        });
        if (totalB) totalB.textContent = q ? shown : totalAll;
      }
      input.addEventListener('input', apply);
      form.addEventListener('submit', function (e) { e.preventDefault(); apply(); });
    });

    // ---- 문의/AS 폼: 접수(시안) ----
    document.querySelectorAll('.qform').forEach(function (form) {
      form.addEventListener('submit', function (e) {
        e.preventDefault();
        var agree = form.querySelector('.agree input[type=checkbox]');
        if (agree && !agree.checked) { toast('개인정보 수집 및 이용에 동의해 주세요.'); return; }
        toast('문의가 정상 접수되었습니다. (리디자인 시안)');
        form.querySelectorAll('input, textarea').forEach(function (f) {
          if (f.type === 'checkbox') f.checked = false; else f.value = '';
        });
      });
    });

  });
})();
