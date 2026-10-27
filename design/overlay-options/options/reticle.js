(function () {
  'use strict';
  var F = window.FlowStage;
  var SW = 128, SH = 24;
  var CODES = { listening: 'rec', thinking: 'proc', success: 'ok', cancelled: 'esc', noSpeech: 'nil', copied: 'clip', error: 'err' };
  var root, panel, row, code, scope, read, msg, full, typed, ctx;
  var ink = '#d3f1ff', inkClear = 'rgba(211,241,255,0)', dim = 'rgba(211,241,255,.48)';
  var ghosts = [new Float32Array(256), new Float32Array(256)];
  var typeTimer = null;

  function readColors() {
    var cs = getComputedStyle(root);
    ink = cs.getPropertyValue('--rt-ink').trim() || ink;
    var m = /^#([0-9a-f]{6})$/i.exec(ink);
    if (m) { var n = parseInt(m[1], 16); inkClear = 'rgba(' + (n >> 16) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',0)'; }
    dim = cs.getPropertyValue('--rt-line').trim() || dim;
  }
  function layout() { F.fitWidth(panel, row, 30); }

  function messageFor(s, info) {
    if (s === 'success') return 'pasted, ' + info.words + ' words';
    return info.message.toLowerCase().replace('⌘v', '⌘V').replace('…', '');
  }

  function typeOn(text, reduced) {
    clearInterval(typeTimer);
    full.textContent = text;
    if (reduced) { typed.textContent = text; msg.classList.remove('typing'); return; }
    var i = 0;
    typed.textContent = '';
    msg.classList.add('typing');
    typeTimer = setInterval(function () {
      i += 1;
      typed.textContent = text.slice(0, i);
      if (i >= text.length) {
        clearInterval(typeTimer);
        setTimeout(function () { msg.classList.remove('typing'); }, 500);
      }
    }, 16);
  }

  function drawTrace(arr, alpha, width) {
    ctx.globalAlpha = alpha;
    ctx.lineWidth = width;
    ctx.beginPath();
    for (var i = 0; i < 256; i += 2) {
      var x = (i / 255) * SW;
      var y = SH / 2 - arr[i] * (SH / 2 - 2);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }

  F.define({
    id: 'reticle',
    build: function (host) {
      host.innerHTML =
        '<div class="rt" data-s="listening"><div class="rt-panel">' +
          '<i class="rt-c tl"></i><i class="rt-c tr"></i><i class="rt-c bl"></i><i class="rt-c br"></i>' +
          '<div class="rt-row">' +
            '<span class="rt-tag"><i class="rt-dot"></i><span class="rt-code">rec</span></span>' +
            '<canvas class="rt-scope" aria-hidden="true"></canvas>' +
            '<span class="rt-msg"><span class="rt-full"></span><span class="rt-typed"></span></span>' +
            '<span class="rt-read">00:00.0</span>' +
          '</div>' +
          '<div class="rt-ruler" aria-hidden="true"></div>' +
        '</div></div>';
      root = host.querySelector('.rt');
      panel = host.querySelector('.rt-panel');
      row = host.querySelector('.rt-row');
      code = host.querySelector('.rt-code');
      scope = host.querySelector('.rt-scope');
      read = host.querySelector('.rt-read');
      msg = host.querySelector('.rt-msg');
      full = host.querySelector('.rt-full');
      typed = host.querySelector('.rt-typed');
      ctx = F.fitCanvas(scope, SW, SH);
      readColors();
      layout();
    },
    setState: function (s, info) {
      root.dataset.s = s;
      code.textContent = CODES[s];
      if (s === 'listening') { read.textContent = '00:00.0'; ghosts[0].fill(0); ghosts[1].fill(0); root.style.setProperty('--rt-p', 0); }
      if (s === 'thinking') read.textContent = 'thinking';
      if (s !== 'listening' && s !== 'thinking') typeOn(messageFor(s, info), info.reduced);
      else { clearInterval(typeTimer); full.textContent = ''; typed.textContent = ''; }
      layout();
    },
    relayout: layout,
    themeChanged: function () { setTimeout(readColors, 0); },
    tick: function (f) {
      if (!f.visible) return;
      var s = f.state;
      if (s !== 'listening' && s !== 'thinking') return;
      ctx.clearRect(0, 0, SW, SH);
      // centre line
      ctx.globalAlpha = 1;
      ctx.fillStyle = dim;
      for (var x = 0; x < SW; x += 4) ctx.fillRect(x, SH / 2, 1, 1);
      ctx.strokeStyle = ink;
      ctx.lineJoin = 'round';
      if (s === 'listening') {
        var e = f.elapsed;
        var mm = Math.floor(e / 60), ss = Math.floor(e % 60), ds = Math.floor((e * 10) % 10);
        read.textContent = String(mm).padStart(2, '0') + ':' + String(ss).padStart(2, '0') + '.' + ds;
        root.style.setProperty('--rt-p', Math.min(1, e / 300).toFixed(4));
        if (!f.reduced) {
          drawTrace(ghosts[1], 0.1, 1);
          drawTrace(ghosts[0], 0.22, 1);
        }
        drawTrace(f.wave, 0.18, 3);
        drawTrace(f.wave, 1, 1);
        ghosts[1].set(ghosts[0]);
        ghosts[0].set(f.wave);
      } else {
        // Thinking: flat trace with a scan line sweeping across it.
        ctx.globalAlpha = 0.5;
        ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(0, SH / 2 + 0.5); ctx.lineTo(SW, SH / 2 + 0.5); ctx.stroke();
        var p = f.reduced ? 0.5 : (f.t * 0.85) % 1;
        var sx = p * SW;
        var g = ctx.createLinearGradient(sx - 40, 0, sx, 0);
        g.addColorStop(0, inkClear);
        g.addColorStop(1, ink);
        ctx.globalAlpha = 0.28;
        ctx.fillStyle = g;
        ctx.fillRect(Math.max(0, sx - 40), 3, Math.min(40, sx), SH - 6);
        ctx.globalAlpha = 1;
        ctx.fillStyle = ink;
        ctx.fillRect(sx, 2, 1, SH - 4);
      }
      ctx.globalAlpha = 1;
    }
  });
})();
