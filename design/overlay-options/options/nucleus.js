(function () {
  'use strict';
  var F = window.FlowStage;
  var CW = 124, CH = 124, CX = CW / 2, CY = CH / 2;
  var NPART = 34;

  function hex(h) { var n = parseInt(h.slice(1), 16); return [n >> 16, (n >> 8) & 255, n & 255]; }
  // [lobe1, lobe2, lobe3, base highlight, base edge]
  var TINTS = {
    listening: ['#b9a6ff', '#8fe3e0', '#ffc6a8', '#ece8ff', '#a395f0'],
    thinking:  ['#b9a6ff', '#8fe3e0', '#ffc6a8', '#ece8ff', '#a395f0'],
    success:   ['#7cf0b0', '#a6f5d8', '#5fd7a0', '#e4fcef', '#3fbf80'],
    cancelled: ['#c9cbd3', '#b4b6c0', '#dadbe1', '#eeeff2', '#9a9daa'],
    noSpeech:  ['#ffd08a', '#ffb86b', '#ffe2b0', '#fff3de', '#eb9b3a'],
    copied:    ['#8fdcff', '#a9c8ff', '#8fe3e0', '#e6f6ff', '#5aa8ea'],
    error:     ['#ff8a80', '#ff6b8a', '#ffb199', '#ffe6e2', '#e5483f']
  };
  Object.keys(TINTS).forEach(function (k) { TINTS[k] = TINTS[k].map(hex); });

  var root, shell, row, icon, label, canvas, ctx;
  var theme = 'light';
  var cur = TINTS.listening.map(function (c) { return c.slice(); });
  var a = 0, av = 0;          // appear scale (spring) and its velocity
  var radius = 15, ring = 0, swirl = 0;
  var parts = [];
  for (var i = 0; i < NPART; i++) {
    parts.push({ r: 0.2 + 0.7 * Math.sqrt(Math.random()), th: Math.random() * Math.PI * 2, w: 0.6 + Math.random() * 1.2, cur: 0.5, s: 0.6 + Math.random() * 0.8 });
  }

  function rgba(c, al) { return 'rgba(' + (c[0] | 0) + ',' + (c[1] | 0) + ',' + (c[2] | 0) + ',' + al + ')'; }
  function layout() {
    var hasLabel = root.classList.contains('has-label');
    F.fitWidth(shell, row, hasLabel ? 18 : 2);
  }

  function blobPath(R, wob, t) {
    var p = new Path2D();
    var n = 96;
    for (var k = 0; k <= n; k++) {
      var th = (k / n) * Math.PI * 2;
      var d = 0.55 * Math.sin(2 * th + t * 1.3) +
              0.35 * Math.sin(3 * th - t * 1.9 + 1.7) +
              0.22 * Math.sin(5 * th + t * 2.6 + 0.4) +
              0.12 * Math.sin(7 * th - t * 3.4);
      var r = R * (1 + wob * d);
      var x = CX + Math.cos(th) * r, y = CY + Math.sin(th) * r;
      if (k === 0) p.moveTo(x, y); else p.lineTo(x, y);
    }
    p.closePath();
    return p;
  }

  F.define({
    id: 'nucleus',
    build: function (host, env) {
      theme = env.theme;
      host.innerHTML =
        '<div class="nu" data-s="listening"><div class="nu-shell">' +
          '<div class="nu-bg"></div>' +
          '<canvas class="nu-orb" aria-hidden="true"></canvas>' +
          '<div class="nu-row"><span class="nu-slot"><span class="nu-icon" aria-hidden="true"></span></span><span class="nu-label"></span></div>' +
        '</div></div>';
      root = host.querySelector('.nu');
      shell = host.querySelector('.nu-shell');
      row = host.querySelector('.nu-row');
      icon = host.querySelector('.nu-icon');
      label = host.querySelector('.nu-label');
      canvas = host.querySelector('.nu-orb');
      ctx = F.fitCanvas(canvas, CW, CH);
      layout();
    },
    setState: function (s, info) {
      var prev = root.dataset.s;
      root.dataset.s = s;
      var hasLabel = s !== 'listening' && s !== 'thinking';
      root.classList.toggle('has-label', hasLabel);
      icon.innerHTML = F.icons[s] || '';
      label.textContent = hasLabel ? info.message : (s === 'thinking' ? '' : '');
      if (s === 'success' && prev !== 'success') ring = 1;
      if (hasLabel) F.replay(row, 'in');
      layout();
    },
    relayout: layout,
    themeChanged: function (t) { theme = t; },
    tick: function (f) {
      var dt = f.dt, s = f.state || 'listening';
      // Appear spring with a little overshoot.
      var target = f.visible ? 1 : 0;
      if (f.reduced) { a = target; av = 0; }
      else {
        var stiffness = f.visible ? 210 : 320, damping = f.visible ? 16 : 30;
        av += (stiffness * (target - a) - damping * av) * dt;
        a += av * dt;
        if (!f.visible && a < 0.02) { a = 0; av = 0; }
      }
      ctx.clearRect(0, 0, CW, CH);
      if (a <= 0.001) return;

      var T = TINTS[s];
      var kc = f.reduced ? 1 : 1 - Math.exp(-dt * 6);
      for (var i = 0; i < 5; i++) for (var j = 0; j < 3; j++) cur[i][j] += (T[i][j] - cur[i][j]) * kc;

      var t = f.reduced ? 0 : f.t;
      var wantR = s === 'listening' ? 15 + f.level * 5 : s === 'thinking' ? 13 + (f.reduced ? 0 : Math.sin(f.t * 3.2) * 0.8) : 11;
      radius += (wantR - radius) * (1 - Math.exp(-dt * 12));
      var R = Math.max(0.1, radius * a);
      var wob = s === 'listening' ? 0.03 + f.level * 0.15 : s === 'thinking' ? 0.05 : 0.018;
      if (f.reduced) wob *= 0.4;
      var swirlSpeed = s === 'thinking' ? 4.2 : s === 'listening' ? 0.5 + f.level * 3 : 0.35;
      if (!f.reduced) swirl += swirlSpeed * dt;
      var dark = theme === 'dark';

      // Halo.
      var haloA = dark ? 0.16 + (s === 'listening' ? f.level * 0.3 : 0.1) : 0.08 + (s === 'listening' ? f.level * 0.18 : 0.05);
      var halo = ctx.createRadialGradient(CX, CY, R * 0.6, CX, CY, R * 2.6);
      halo.addColorStop(0, rgba(cur[4], haloA * a));
      halo.addColorStop(1, rgba(cur[4], 0));
      ctx.fillStyle = halo;
      ctx.fillRect(0, 0, CW, CH);

      var path = blobPath(R, wob, t);

      // Base pearl.
      ctx.save();
      if (!dark) { ctx.shadowColor = 'rgba(60,40,120,0.28)'; ctx.shadowBlur = 14; ctx.shadowOffsetY = 5; }
      var base = ctx.createRadialGradient(CX - R * 0.32, CY - R * 0.38, 0, CX, CY, R * 1.25);
      base.addColorStop(0, '#ffffff');
      base.addColorStop(0.42, rgba(cur[3], 1));
      base.addColorStop(1, rgba(cur[4], 1));
      ctx.fillStyle = base;
      ctx.fill(path);
      ctx.restore();

      // Inner colour lobes and particles, clipped to the blob.
      ctx.save();
      ctx.clip(path);
      for (var l = 0; l < 3; l++) {
        var ang = swirl * (0.8 + l * 0.35) + l * 2.1;
        var lx = CX + Math.cos(ang) * R * 0.5, ly = CY + Math.sin(ang) * R * 0.5;
        var lg = ctx.createRadialGradient(lx, ly, 0, lx, ly, R * 0.85);
        lg.addColorStop(0, rgba(cur[l], 0.85));
        lg.addColorStop(1, rgba(cur[l], 0));
        ctx.fillStyle = lg;
        ctx.fillRect(CX - R * 2, CY - R * 2, R * 4, R * 4);
      }
      // Particles: drift with the voice, spiral in while thinking.
      var inward = s === 'thinking' ? 0.42 : 1;
      ctx.fillStyle = 'rgba(255,255,255,0.75)';
      for (var pI = 0; pI < NPART; pI++) {
        var q = parts[pI];
        if (!f.reduced) q.th += q.w * swirlSpeed * dt * 0.9;
        q.cur += (q.r * inward - q.cur) * (1 - Math.exp(-dt * 3));
        var pr = q.cur * R * 0.92;
        ctx.globalAlpha = 0.25 + 0.5 * q.s * (s === 'listening' ? 0.4 + f.level : 0.7);
        ctx.beginPath();
        ctx.arc(CX + Math.cos(q.th) * pr, CY + Math.sin(q.th) * pr, 0.55 + q.s * 0.45, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      // Specular highlight.
      var sx = CX - R * 0.38, sy = CY - R * 0.45;
      var sg = ctx.createRadialGradient(sx, sy, 0, sx, sy, R * 0.45);
      sg.addColorStop(0, 'rgba(255,255,255,0.9)');
      sg.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = sg;
      ctx.fillRect(CX - R * 2, CY - R * 2, R * 4, R * 4);
      ctx.restore();

      // Rim.
      ctx.lineWidth = 1;
      ctx.strokeStyle = dark ? 'rgba(255,255,255,0.45)' : 'rgba(255,255,255,0.85)';
      ctx.stroke(path);

      // Success ring.
      if (ring > 0) {
        if (!f.reduced) {
          ctx.globalAlpha = ring * 0.7;
          ctx.strokeStyle = rgba(cur[4], 1);
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.arc(CX, CY, R * (1.15 + (1 - ring) * 1.5), 0, Math.PI * 2);
          ctx.stroke();
          ctx.globalAlpha = 1;
        }
        ring = Math.max(0, ring - dt * 1.7);
      }
    }
  });
})();
