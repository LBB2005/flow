(function () {
  'use strict';
  var F = window.FlowStage;
  var N = 25, BW = 2, GAP = 2.5, H = 24, W = N * BW + (N - 1) * GAP;
  var C = (N - 1) / 2;

  // Four aurora colours per state, as RGB.
  var PALETTES = {
    listening: [[123, 97, 255], [255, 95, 162], [63, 224, 197], [90, 169, 255]],
    thinking:  [[123, 97, 255], [255, 95, 162], [63, 224, 197], [90, 169, 255]],
    success:   [[51, 225, 161], [63, 224, 197], [140, 245, 200], [43, 195, 168]],
    cancelled: [[142, 142, 156], [110, 110, 124], [170, 170, 182], [124, 124, 138]],
    noSpeech:  [[255, 181, 71], [255, 138, 61], [255, 208, 138], [255, 159, 10]],
    copied:    [[90, 200, 250], [90, 169, 255], [143, 220, 255], [63, 224, 197]],
    error:     [[255, 90, 78], [255, 59, 107], [255, 122, 89], [255, 159, 10]]
  };
  // Aurora rotation speed (deg/s) and resting intensity per state.
  var SPIN = { listening: 24, thinking: 260, success: 60, cancelled: 8, noSpeech: 12, copied: 30, error: 10 };
  var REST = { listening: 0.3, thinking: 0.72, success: 0.95, cancelled: 0.18, noSpeech: 0.55, copied: 0.6, error: 0.65 };

  var root, shell, row, canvas, icon, label, time, ctx;
  var cur = PALETTES.listening.map(function (c) { return c.slice(); });
  var angle = 0, spin = 24, intensity = 0.3, pulse = 0;
  var shown = new Float32Array(N);

  function layout() { F.fitWidth(shell, row, 38); }
  function rgb(c, a) { return 'rgba(' + (c[0] | 0) + ',' + (c[1] | 0) + ',' + (c[2] | 0) + ',' + (a == null ? 1 : a) + ')'; }

  F.define({
    id: 'afterglow',
    build: function (host) {
      host.innerHTML =
        '<div class="ag" data-s="listening"><div class="ag-shell">' +
          '<div class="ag-aura" aria-hidden="true"></div>' +
          '<div class="ag-body"><div class="ag-row">' +
            '<canvas class="ag-wave" aria-hidden="true"></canvas>' +
            '<span class="ag-icon" aria-hidden="true"></span>' +
            '<span class="ag-label"></span>' +
            '<span class="ag-time">0:00</span>' +
          '</div></div>' +
        '</div></div>';
      root = host.querySelector('.ag');
      shell = host.querySelector('.ag-shell');
      row = host.querySelector('.ag-row');
      canvas = host.querySelector('.ag-wave');
      icon = host.querySelector('.ag-icon');
      label = host.querySelector('.ag-label');
      time = host.querySelector('.ag-time');
      ctx = F.fitCanvas(canvas, W, H);
      layout();
    },
    setState: function (s, info) {
      var prev = root.dataset.s;
      root.dataset.s = s;
      icon.innerHTML = F.icons[s] || '';
      label.textContent = s === 'listening' ? '' : info.message;
      if (s === 'listening') { shown.fill(0); time.textContent = '0:00'; }
      if (s === 'success' || s === 'error') pulse = 1;
      if (prev !== s && !((prev === 'listening' && s === 'thinking') || (prev === 'thinking' && s === 'listening'))) F.replay(row, 'in');
      layout();
    },
    relayout: layout,
    tick: function (f) {
      var s = f.state || 'listening';
      var dt = f.dt;
      // colours ease toward the state's palette
      var target = PALETTES[s];
      var kc = f.reduced ? 1 : 1 - Math.exp(-dt * 5);
      for (var i = 0; i < 4; i++) for (var j = 0; j < 3; j++) cur[i][j] += (target[i][j] - cur[i][j]) * kc;
      spin += ((f.reduced ? 0 : SPIN[s]) - spin) * (1 - Math.exp(-dt * 3));
      angle = (angle + spin * dt) % 360;
      var want = REST[s];
      if (s === 'listening') want = 0.22 + f.level * 0.85;
      if (s === 'thinking' && !f.reduced) want = 0.62 + 0.12 * Math.sin(f.t * 4);
      pulse = Math.max(0, pulse - dt * 1.6);
      want = Math.min(1, want + pulse * 0.25);
      intensity += (want - intensity) * (1 - Math.exp(-dt * 10));
      var st = root.style;
      st.setProperty('--ag-c1', rgb(cur[0]));
      st.setProperty('--ag-c2', rgb(cur[1]));
      st.setProperty('--ag-c3', rgb(cur[2]));
      st.setProperty('--ag-c4', rgb(cur[3]));
      st.setProperty('--ag-angle', angle.toFixed(1) + 'deg');
      st.setProperty('--ag-i', intensity.toFixed(3));

      if (!f.visible || (s !== 'listening' && s !== 'thinking')) return;
      if (s === 'listening') time.textContent = F.formatElapsed(f.elapsed);

      ctx.clearRect(0, 0, W, H);
      var g = ctx.createLinearGradient(0, 0, W, 0);
      var core = [cur[0][0] * 0.4 + 153, cur[0][1] * 0.4 + 153, cur[0][2] * 0.4 + 153];
      g.addColorStop(0, rgb(cur[2], 0.9));
      g.addColorStop(0.5, rgb(core));
      g.addColorStop(1, rgb(cur[1], 0.9));
      ctx.fillStyle = g;
      ctx.shadowColor = rgb(cur[0], 0.9);
      ctx.shadowBlur = 6;
      var k = f.reduced ? 1 : 1 - Math.exp(-dt / 0.07);
      var len = f.bars.length;
      for (var b = 0; b < N; b++) {
        var d = Math.abs(b - C);
        var h;
        if (s === 'listening') {
          // Newest sample in the centre, history spreading out to both sides.
          var lv = f.bars[len - 1 - Math.round(d)];
          var shaped = Math.min(1, lv * (1 - Math.pow(d / C, 2) * 0.4) * 1.1);
          shown[b] += (shaped - shown[b]) * k;
          h = 2 + shown[b] * (H - 2);
          ctx.globalAlpha = 1;
        } else {
          shown[b] += (0 - shown[b]) * k;
          var ripple = f.reduced ? 0.5 : Math.max(0, Math.sin(f.t * 6 - d * 0.55));
          h = 2 + shown[b] * (H - 2) + ripple * 3;
          ctx.globalAlpha = 0.3 + 0.7 * ripple;
        }
        var x = b * (BW + GAP);
        ctx.beginPath();
        if (ctx.roundRect) ctx.roundRect(x, (H - h) / 2, BW, h, 1); else ctx.rect(x, (H - h) / 2, BW, h);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      ctx.shadowBlur = 0;
    }
  });
})();
