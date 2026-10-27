(function () {
  'use strict';
  var F = window.FlowStage;
  var NP = 72;              // points on the filament
  var CW = 460, CH = 42;    // canvas (centred on the pill, larger than it)
  var PH = 34, R = 17;      // pill height and radius
  var SLOT = { listening: 104, thinking: 60, success: 16, cancelled: 13, noSpeech: 22, copied: 12, error: 6 };

  var root, pill, row, slot, label, time, canvas, ctx;
  var ink = 'rgba(0,0,0,.86)', dim = 'rgba(0,0,0,.45)';
  var pts = new Float32Array(NP * 2), tgt = new Float32Array(NP * 2);
  var q = 0, initialised = false, morphFast = false, dotAlpha = 0;

  function readColors() {
    var cs = getComputedStyle(root);
    ink = cs.getPropertyValue('--fl-ink').trim() || ink;
    dim = cs.getPropertyValue('--fl-dim').trim() || dim;
  }
  function layout() {
    slot.style.width = SLOT[root.dataset.s] + 'px';
    F.fitWidth(pill, row, 30);
  }
  function ease(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }

  // Resample a polyline (array of [x,y]) into NP points spaced evenly by arc length.
  function resample(poly, out) {
    var lens = [0], total = 0, i;
    for (i = 1; i < poly.length; i++) {
      total += Math.hypot(poly[i][0] - poly[i - 1][0], poly[i][1] - poly[i - 1][1]);
      lens.push(total);
    }
    var seg = 1;
    for (var n = 0; n < NP; n++) {
      var d = total * n / (NP - 1);
      while (seg < poly.length - 1 && lens[seg] < d) seg++;
      var a = poly[seg - 1], b = poly[seg];
      var span = lens[seg] - lens[seg - 1] || 1;
      var u = Math.min(1, Math.max(0, (d - lens[seg - 1]) / span));
      out[n * 2] = a[0] + (b[0] - a[0]) * u;
      out[n * 2 + 1] = a[1] + (b[1] - a[1]) * u;
    }
  }
  function glyph(shape, cx, cy, w, h) {
    return shape.map(function (p) { return [cx - w / 2 + p[0] * w, cy - h / 2 + p[1] * h]; });
  }

  function buildTarget(f, sx, sw, cy) {
    var s = f.state, i, u;
    if (s === 'listening') {
      var A = f.level * 7.5, t = f.reduced ? 0 : f.t;
      for (i = 0; i < NP; i++) {
        u = i / (NP - 1);
        var y = Math.sin(Math.PI * u) * Math.sin(t * 9.1) +
                0.6 * Math.sin(2 * Math.PI * u) * Math.sin(t * 14.3 + 1.1) +
                0.35 * Math.sin(3 * Math.PI * u) * Math.sin(t * 21.7 + 2.3) +
                0.2 * Math.sin(4 * Math.PI * u) * Math.sin(t * 29.9 + 0.4);
        if (f.reduced) y = Math.sin(Math.PI * u);
        tgt[i * 2] = sx + u * sw;
        tgt[i * 2 + 1] = cy + y * A;
      }
      return;
    }
    if (s === 'thinking') {
      var tt = f.reduced ? 0 : f.t;
      for (i = 0; i < NP; i++) {
        u = i / (NP - 1);
        tgt[i * 2] = sx + u * sw;
        tgt[i * 2 + 1] = cy + 2.4 * Math.sin(2 * Math.PI * (u * 1.5 - tt * 1.1)) * Math.sin(Math.PI * u);
      }
      return;
    }
    var mid = sx + sw / 2, poly;
    if (s === 'success') poly = glyph([[0, 0.55], [0.36, 0.92], [1, 0.08]], mid, cy, 15, 12);
    else if (s === 'cancelled') poly = glyph([[0, 0], [1, 1], [0.5, 0.5], [1, 0], [0, 1]], mid, cy, 11, 11);
    else if (s === 'copied') poly = glyph([[0.5, 0], [1, 0], [1, 1], [0, 1], [0, 0], [0.5, 0]], mid, cy, 10, 13);
    else if (s === 'error') poly = glyph([[0.5, 0], [0.5, 0.62]], mid, cy, 4, 14);
    else poly = [[sx, cy], [sx + sw, cy]]; // noSpeech: flat line
    resample(poly, tgt);
  }

  function capsulePath(c, x, y, w, h, r, side) {
    // Half outline, from bottom centre round one side to top centre (side = 1 right, -1 left).
    var cx = x + w / 2;
    c.moveTo(cx, y + h);
    if (side > 0) {
      c.lineTo(x + w - r, y + h);
      c.arc(x + w - r, y + r, r, Math.PI / 2, -Math.PI / 2, true);
      c.lineTo(cx, y);
    } else {
      c.lineTo(x + r, y + h);
      c.arc(x + r, y + r, r, Math.PI / 2, Math.PI * 1.5, false);
      c.lineTo(cx, y);
    }
  }

  F.define({
    id: 'filament',
    build: function (host) {
      host.innerHTML =
        '<div class="fl" data-s="listening"><div class="fl-pill">' +
          '<div class="fl-fill"></div>' +
          '<canvas class="fl-canvas" aria-hidden="true"></canvas>' +
          '<div class="fl-row"><span class="fl-slot"></span><span class="fl-label"></span><span class="fl-time">0:00</span></div>' +
        '</div></div>';
      root = host.querySelector('.fl');
      pill = host.querySelector('.fl-pill');
      row = host.querySelector('.fl-row');
      slot = host.querySelector('.fl-slot');
      label = host.querySelector('.fl-label');
      time = host.querySelector('.fl-time');
      canvas = host.querySelector('.fl-canvas');
      ctx = F.fitCanvas(canvas, CW, CH);
      readColors();
      layout();
    },
    setState: function (s, info) {
      root.dataset.s = s;
      label.textContent = s === 'listening' ? '' : info.message;
      if (s === 'listening') time.textContent = '0:00';
      morphFast = false;
      F.replay(row, 'in');
      layout();
    },
    relayout: layout,
    themeChanged: function () { setTimeout(readColors, 0); },
    tick: function (f) {
      var dt = f.dt;
      var target = f.visible ? 1 : 0;
      var dur = f.reduced ? 0.15 : (f.visible ? 0.6 : 0.32);
      q += Math.sign(target - q) * dt / dur;
      q = Math.min(1, Math.max(0, q));
      var p = ease(q);
      root.style.setProperty('--fl-p', p.toFixed(3));
      pill.style.visibility = q > 0 ? 'visible' : 'hidden';
      if (q === 0) { initialised = false; return; }
      if (f.state === 'listening' && f.visible) time.textContent = F.formatElapsed(f.elapsed);

      // Geometry in canvas space.
      var pw = pill.offsetWidth;
      var ox = (CW - pw) / 2, oy = (CH - PH) / 2;
      var rowLeft = pw / 2 - row.offsetWidth / 2;
      var sx = ox + rowLeft + slot.offsetLeft;
      var sw = slot.offsetWidth;
      var cy = oy + PH / 2;

      buildTarget(f, sx, sw, cy);
      if (!initialised) {
        // Start as a flat line collapsed at the centre of the slot.
        for (var i = 0; i < NP; i++) { pts[i * 2] = sx + sw / 2; pts[i * 2 + 1] = cy; }
        initialised = true;
      }
      var settle = f.state === 'listening' && morphFast ? 40 : 13;
      var k = f.reduced ? 1 : 1 - Math.exp(-dt * settle);
      var maxErr = 0;
      for (var n = 0; n < NP * 2; n++) {
        var d = tgt[n] - pts[n];
        pts[n] += d * k;
        if (Math.abs(d) > maxErr) maxErr = Math.abs(d);
      }
      if (maxErr < 1.5) morphFast = true;

      ctx.clearRect(0, 0, CW, CH);
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      // Outline, drawn in from the bottom centre.
      var x = ox + 0.5, y = oy + 0.5, w = pw - 1, h = PH - 1, r = R - 0.5;
      var half = (w / 2 - r) * 2 + Math.PI * r;
      ctx.strokeStyle = dim;
      ctx.lineWidth = 1;
      ctx.setLineDash([half * p, half + 2]);
      ctx.beginPath(); capsulePath(ctx, x, y, w, h, r, 1); ctx.stroke();
      ctx.beginPath(); capsulePath(ctx, x, y, w, h, r, -1); ctx.stroke();
      ctx.setLineDash([]);

      // Filament.
      var fa = Math.min(1, Math.max(0, (p - 0.35) / 0.5));
      ctx.globalAlpha = fa * (f.state === 'noSpeech' ? 0.45 : 1);
      ctx.strokeStyle = ink;
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.moveTo(pts[0], pts[1]);
      for (var m = 1; m < NP; m++) ctx.lineTo(pts[m * 2], pts[m * 2 + 1]);
      ctx.stroke();

      // The error glyph's dot.
      dotAlpha += ((f.state === 'error' ? 1 : 0) - dotAlpha) * (f.reduced ? 1 : 1 - Math.exp(-dt * 8));
      if (dotAlpha > 0.01) {
        ctx.globalAlpha = fa * dotAlpha;
        ctx.fillStyle = ink;
        ctx.beginPath();
        ctx.arc(sx + sw / 2, cy + 6.2, 0.95, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }
  });
})();
