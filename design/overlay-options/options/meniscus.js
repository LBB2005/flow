(function () {
  'use strict';
  var F = window.FlowStage;
  // 85% scale (was BW 3, GAP 3, H 22, MIN 3, MAX 20, side padding 17).
  var N = 11, BW = 2.5, GAP = 2.5, H = 19, MIN = 2.5, MAX = 17;
  var root, glass, row, canvas, icon, label, time, ctx;
  var ink = '#000';
  var shown = new Float32Array(N);

  function readInk() { ink = getComputedStyle(root).getPropertyValue('--mn-ink').trim() || '#000'; }
  function layout() { F.fitWidth(glass, row, 29); }

  F.define({
    id: 'meniscus',
    build: function (host) {
      host.innerHTML =
        '<div class="mn" data-s="listening"><div class="mn-glass">' +
          '<div class="mn-sheen"></div>' +
          '<div class="mn-row">' +
            '<span class="mn-lead"><canvas class="mn-bars" aria-hidden="true"></canvas><span class="mn-icon" aria-hidden="true"></span></span>' +
            '<span class="mn-label"></span>' +
            '<span class="mn-time">0:00</span>' +
          '</div>' +
        '</div></div>';
      root = host.querySelector('.mn');
      glass = host.querySelector('.mn-glass');
      row = host.querySelector('.mn-row');
      canvas = host.querySelector('.mn-bars');
      icon = host.querySelector('.mn-icon');
      label = host.querySelector('.mn-label');
      time = host.querySelector('.mn-time');
      ctx = F.fitCanvas(canvas, N * BW + (N - 1) * GAP, H);
      readInk();
      layout();
    },
    setState: function (s, info) {
      root.dataset.s = s;
      icon.innerHTML = F.icons[s] || '';
      label.textContent = s === 'listening' ? '' : info.message;
      if (s === 'listening') { shown.fill(0); time.textContent = '0:00'; }
      F.replay(row, 'in');
      layout();
    },
    relayout: layout,
    themeChanged: function () { setTimeout(readInk, 0); },
    tick: function (f) {
      if (f.state !== 'listening' || !f.visible) return;
      time.textContent = F.formatElapsed(f.elapsed);
      var k = f.reduced ? 1 : 1 - Math.exp(-f.dt / 0.06);
      var off = f.bars.length - N;
      ctx.clearRect(0, 0, N * BW + (N - 1) * GAP, H);
      ctx.fillStyle = ink;
      for (var i = 0; i < N; i++) {
        var lv = f.bars[off + i];
        var shaped = Math.min(1, lv * (0.85 + 0.15 * Math.abs(Math.sin(i * 1.9))));
        shown[i] += (shaped - shown[i]) * k;
        var h = MIN + shown[i] * (MAX - MIN);
        var x = i * (BW + GAP), y = (H - h) / 2;
        ctx.beginPath();
        if (ctx.roundRect) ctx.roundRect(x, y, BW, h, BW / 2); else ctx.rect(x, y, BW, h);
        ctx.fill();
      }
    }
  });
})();
