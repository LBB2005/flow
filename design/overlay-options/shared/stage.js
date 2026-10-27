/*
 * Flow overlay mockups: shared stage.
 * Builds the fake desktop, runs the state machine (same states and timings as Flow/Overlay/PillState.swift),
 * produces voice levels (synthetic or real mic, RMS -> 0..1 over -50..0 dBFS like the app) and calls the
 * option's hooks. Each option file calls FlowStage.define({ build, setState, tick, ... }).
 */
(function () {
  'use strict';

  var STATES = ['listening', 'thinking', 'success', 'cancelled', 'noSpeech', 'copied', 'error'];
  var BUTTON_LABELS = {
    listening: 'Listening', thinking: 'Thinking', success: 'Pasted', cancelled: 'Cancelled',
    noSpeech: 'No speech', copied: 'Copied', error: 'Error'
  };
  // Same copy as PillState.message (success has none in the app; the pop-ups say "Pasted").
  var MESSAGES = {
    listening: 'Listening', thinking: 'Thinking…', success: 'Pasted', cancelled: 'Cancelled',
    noSpeech: "Didn't catch that", copied: 'Copied, press ⌘V', error: 'Microphone access needed'
  };
  // PillState.autoHideAfter
  var AUTO_HIDE = { success: 600, cancelled: 2000, noSpeech: 2000, copied: 2000, error: 2000 };
  var TEXT = "Sounds good. Let's move the review to Thursday at 3, and I'll send the deck over tonight.";
  var WORDS = TEXT.split(/\s+/).length;
  var BAR_N = 48;

  var params = new URLSearchParams(location.search);
  var embed = params.has('embed');
  var root = document.documentElement;
  if (embed) root.classList.add('embed');

  function storeGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function storeSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignore */ } }

  var mqDark = window.matchMedia('(prefers-color-scheme: dark)');
  var mqReduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  var theme = params.get('theme') || (embed ? null : storeGet('flow-overlay-theme')) || (mqDark.matches ? 'dark' : 'light');
  root.dataset.theme = theme;
  var reduced = mqReduce.matches;
  root.classList.toggle('reduce-motion', reduced);
  root.dataset.flowState = 'idle';

  var opt = null;
  var host, field, fieldText, ctl;
  var S = { state: null, visible: false, startedAt: performance.now(), elapsed: 0, autoHide: false, playing: false, loop: params.has('loop') };
  var hideTimer = null;
  var playToken = 0;

  // ---------- levels ----------
  var bars = new Float32Array(BAR_N);
  var wave = new Float32Array(256);
  var level = 0, raw = 0, barPeak = 0, barT = 0, last = performance.now();
  var mic = null;

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function hash(n) { var s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); }
  function noise1(x) { var i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f); return hash(i) * (1 - u) + hash(i + 1) * u; }
  function smooth01(x) { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); }

  function synthLevel(t) {
    var el = (performance.now() - S.startedAt) / 1000;
    var onset = smooth01((el - 0.25) / 0.3);
    var syl = Math.pow(Math.max(0, Math.sin(t * Math.PI * 2 * 3.7 + 2.2 * noise1(t * 0.9))), 1.3);
    var phrase = smooth01((noise1(t * 0.75 + 7.3) - 0.14) * 5);
    var env = 0.35 + 0.65 * noise1(t * 2.1 + 3.1);
    return clamp(onset * phrase * (0.2 + syl * env * 0.8) + 0.02 * noise1(t * 37), 0, 1);
  }
  function synthWave(t, lv) {
    var f0 = 3.2 + 1.6 * noise1(t * 0.6);
    var p1 = t * 15, p2 = t * 24.3, p3 = t * 43.7;
    for (var i = 0; i < 256; i++) {
      var x = i / 256;
      var v = Math.sin(2 * Math.PI * f0 * x + p1) * 0.55 +
              Math.sin(2 * Math.PI * 2.03 * f0 * x + p2) * 0.3 +
              Math.sin(2 * Math.PI * 5.1 * f0 * x + p3) * 0.14 +
              (hash(i + t * 61) - 0.5) * 0.16;
      wave[i] = clamp(v * Math.min(1, lv * 1.6), -1, 1);
    }
  }
  function readMic() {
    var buf = mic.buf;
    mic.an.getFloatTimeDomainData(buf);
    var s = 0;
    for (var i = 0; i < buf.length; i++) s += buf[i] * buf[i];
    var rms = Math.sqrt(s / buf.length);
    var db = 20 * Math.log10(Math.max(rms, 1e-7));
    var step = Math.floor(buf.length / 256);
    for (var j = 0; j < 256; j++) wave[j] = clamp(buf[j * step] * 3.5, -1, 1);
    return clamp((db + 50) / 50, 0, 1);
  }
  function resetBars() { bars.fill(0); barPeak = 0; barT = 0; }

  async function enableMic() {
    status('Asking for the microphone…');
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) throw { name: 'NotSupported' };
      var stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
      var AC = window.AudioContext || window.webkitAudioContext;
      var ac = new AC();
      var src = ac.createMediaStreamSource(stream);
      var an = ac.createAnalyser();
      an.fftSize = 2048;
      src.connect(an);
      mic = { stream: stream, ac: ac, an: an, buf: new Float32Array(an.fftSize) };
      status('Mic on. Speak while the pop-up is listening.');
    } catch (err) {
      mic = null;
      status('Mic unavailable (' + (err && err.name || 'error') + '). Using the synthetic voice.');
    }
    markControls();
  }
  function disableMic() {
    if (!mic) return;
    mic.stream.getTracks().forEach(function (t) { t.stop(); });
    try { mic.ac.close(); } catch (e) { /* ignore */ }
    mic = null;
    status('Mic off. Using the synthetic voice.');
    markControls();
  }

  // ---------- canvas helper ----------
  function fitCanvas(canvas, w, h) {
    var dpr = Math.min(3, window.devicePixelRatio || 1);
    var W = Math.max(1, Math.round(w * dpr)), H = Math.max(1, Math.round(h * dpr));
    if (canvas.width !== W || canvas.height !== H) {
      canvas.width = W; canvas.height = H;
      canvas.style.width = w + 'px'; canvas.style.height = h + 'px';
    }
    var ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  }
  // Size an element to its max-content child so CSS can animate the width between states.
  function fitWidth(el, inner, extra) {
    var w = Math.ceil(inner.scrollWidth + (extra || 0));
    el.style.width = w + 'px';
    return w;
  }
  // Restart a CSS animation class on an element.
  function replay(el, cls) {
    el.classList.remove(cls);
    void el.offsetWidth;
    el.classList.add(cls);
  }

  // ---------- state machine ----------
  function go(state, fromPlay) {
    if (!fromPlay) stopPlay();
    clearTimeout(hideTimer);
    var prev = S.visible ? S.state : null;
    S.state = state;
    if (state === 'listening' && prev !== 'listening') { S.startedAt = performance.now(); resetBars(); }
    if (state === 'success') insertText();
    host.dataset.state = state;
    root.dataset.flowState = state;
    opt.setState(state, { prev: prev, message: MESSAGES[state], words: WORDS, reduced: reduced });
    if (!S.visible) show();
    if (!fromPlay && S.autoHide && AUTO_HIDE[state]) hideTimer = setTimeout(hide, AUTO_HIDE[state]);
    markControls();
  }
  function show() {
    S.visible = true;
    host.dataset.booted = 'true';
    host.dataset.visible = 'true';
    if (opt.show) opt.show();
  }
  function hide() {
    clearTimeout(hideTimer);
    if (!S.visible) return;
    S.visible = false;
    host.dataset.visible = 'false';
    root.dataset.flowState = 'idle';
    if (opt.hide) opt.hide();
    markControls();
  }
  function sleep(ms, tok) {
    return new Promise(function (res, rej) {
      setTimeout(function () { if (tok === playToken) res(); else rej('stop'); }, ms);
    });
  }
  async function play() {
    var tok = ++playToken;
    clearTimeout(hideTimer);
    S.playing = true;
    markControls();
    try {
      do {
        if (S.visible) { hide(); await sleep(520, tok); }
        clearText();
        await sleep(450, tok);
        go('listening', true);
        await sleep(4000, tok);
        go('thinking', true);
        await sleep(1300, tok);
        go('success', true);
        await sleep(AUTO_HIDE.success, tok);
        hide();
        if (S.loop) await sleep(2800, tok);
      } while (S.loop);
    } catch (e) {
      if (e !== 'stop') throw e;
    }
    if (tok === playToken) { S.playing = false; markControls(); }
  }
  function stopPlay() { playToken++; S.playing = false; }

  // ---------- fake text field ----------
  function clearText() { fieldText.textContent = ''; field.classList.remove('has-text'); }
  function insertText() {
    fieldText.textContent = '';
    var span = document.createElement('span');
    span.className = 'ins';
    span.textContent = TEXT;
    fieldText.appendChild(span);
    field.classList.add('has-text');
    setTimeout(function () { span.classList.add('settled'); }, 60);
  }

  // ---------- theme / motion ----------
  function setTheme(t) {
    theme = t;
    root.dataset.theme = t;
    if (!embed) storeSet('flow-overlay-theme', t);
    if (opt && opt.themeChanged) opt.themeChanged(t);
    markControls();
  }
  function setReduced(on) {
    reduced = !!on;
    root.classList.toggle('reduce-motion', reduced);
    markControls();
  }
  mqReduce.addEventListener && mqReduce.addEventListener('change', function (e) { setReduced(e.matches); });

  // ---------- frame loop ----------
  function frame(now) {
    var dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    var t = now / 1000;
    var speaking = S.visible && S.state === 'listening';
    if (speaking) {
      if (mic) raw = readMic();
      else { raw = synthLevel(t); synthWave(t, raw); }
      S.elapsed = (now - S.startedAt) / 1000;
    } else {
      raw = 0;
      for (var i = 0; i < 256; i++) wave[i] *= 0.85;
    }
    var k = raw > level ? 1 - Math.pow(0.55, dt * 60) : 1 - Math.pow(0.88, dt * 60);
    level += (raw - level) * k;
    // Calm Scroll: one bar per 120 ms, loudest reading in the window, eased 0.55 toward the previous bar.
    barPeak = Math.max(barPeak, raw);
    barT += dt;
    if (barT >= 0.12) {
      barT = 0;
      var prevBar = bars[BAR_N - 1];
      bars.copyWithin(0, 1);
      bars[BAR_N - 1] = prevBar + 0.55 * (barPeak - prevBar);
      barPeak = 0;
    }
    if (opt && opt.tick) {
      opt.tick({ t: t, dt: dt, level: level, raw: raw, bars: bars, wave: wave, elapsed: S.elapsed, state: S.state, visible: S.visible, reduced: reduced, theme: theme });
    }
    requestAnimationFrame(frame);
  }

  function formatElapsed(s) {
    s = Math.max(0, Math.floor(s));
    return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
  }

  // ---------- DOM ----------
  var GLYPHS = {
    folder: '<path d="M3 7.5a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" fill="#fff" opacity=".92"/>',
    globe: '<circle cx="12" cy="12" r="8.2" fill="none" stroke="#fff" stroke-width="1.6"/><path d="M3.8 12h16.4M12 3.8c2.6 2.6 2.6 13.8 0 16.4M12 3.8c-2.6 2.6-2.6 13.8 0 16.4" fill="none" stroke="#fff" stroke-width="1.4"/>',
    chat: '<path d="M12 4.5c4.7 0 8.5 3 8.5 6.8s-3.8 6.8-8.5 6.8c-.9 0-1.8-.1-2.6-.3L5.2 19.6l1.1-3.5C4.6 14.9 3.5 13.2 3.5 11.3 3.5 7.5 7.3 4.5 12 4.5z" fill="#fff"/>',
    mail: '<rect x="3.5" y="6" width="17" height="12" rx="2" fill="#fff"/><path d="M4 7l8 6 8-6" fill="none" stroke="#4a8ee6" stroke-width="1.5"/>',
    cal: '<text x="12" y="17.5" text-anchor="middle" font-size="11" font-weight="600" fill="#1d1d1f" font-family="-apple-system,Helvetica,Arial">21</text>',
    notes: '<path d="M6 8h12M6 12h12M6 16h8" stroke="#6b5a12" stroke-width="1.7" stroke-linecap="round"/>',
    music: '<path d="M10 17.5V7l8-1.8v10" fill="none" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/><circle cx="8" cy="17.5" r="2.2" fill="#fff"/><circle cx="16" cy="15.2" r="2.2" fill="#fff"/>',
    photo: '<circle cx="12" cy="8" r="3" fill="#ffb24d"/><circle cx="16" cy="12" r="3" fill="#7bd36f" opacity=".9"/><circle cx="12" cy="16" r="3" fill="#5aa8ff" opacity=".9"/><circle cx="8" cy="12" r="3" fill="#ff6fa3" opacity=".9"/>',
    term: '<path d="M6.5 8.5l3.5 3.5-3.5 3.5M12 16h5.5" fill="none" stroke="#e8e8ea" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
    gear: '<circle cx="12" cy="12" r="5.2" fill="none" stroke="#fff" stroke-width="2.4" stroke-dasharray="2.6 1.4"/><circle cx="12" cy="12" r="2" fill="#fff"/>',
    trash: '<path d="M7 7.5h10l-1 11H8z" fill="none" stroke="#5d6270" stroke-width="1.4"/><path d="M6 7.5h12" stroke="#5d6270" stroke-width="1.4"/>'
  };
  function app(glyph, bg, cls) {
    return '<div class="app ' + (cls || '') + '" style="background:' + bg + '"><svg viewBox="0 0 24 24">' + GLYPHS[glyph] + '</svg></div>';
  }

  function buildDesktop() {
    var dock =
      app('folder', 'linear-gradient(160deg,#5aa9ff,#2f6fe0)', 'running') +
      app('globe', 'linear-gradient(160deg,#43d2c6,#1f8fa8)') +
      app('chat', 'linear-gradient(160deg,#8b7bff,#5a46e0)', 'running') +
      app('mail', 'linear-gradient(160deg,#7fc2ff,#3d86e6)') +
      app('cal', 'linear-gradient(180deg,#ff5a52 0 26%,#fbfbfd 26%)', 'extra') +
      app('notes', 'linear-gradient(180deg,#ffd84d 0 22%,#fff6c9 22%)') +
      app('music', 'linear-gradient(160deg,#ff6f86,#e0365a)', 'extra') +
      app('photo', '#fbfbfd', 'extra') +
      app('term', 'linear-gradient(160deg,#3a3d46,#1f2127)', 'running') +
      app('gear', 'linear-gradient(160deg,#a9adb8,#6f7480)', 'extra') +
      '<div class="sep"></div>' +
      app('trash', 'linear-gradient(160deg,#eef0f4,#c9ccd4)', 'extra');

    var desk = document.createElement('div');
    desk.className = 'desk';
    desk.innerHTML =
      '<header class="menubar" aria-hidden="true">' +
        '<span class="mb-logo"></span><span class="mb-app">Chat</span>' +
        '<span class="mb-menus" style="display:contents"><span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span></span>' +
        '<span class="mb-right"><span class="mb-flow" title="Flow"><i></i><i></i><i></i><i></i><i></i></span><span class="mb-clock"></span></span>' +
      '</header>' +
      '<section class="win" aria-label="Example chat window">' +
        '<div class="win-bar"><div class="win-lights"><i></i><i></i><i></i></div><div class="win-title">Priya Shah<small>Active now</small></div></div>' +
        '<div class="thread">' +
          '<div class="stamp">Today 10:31</div>' +
          '<div class="msg them">Are we still on for the design review this week?</div>' +
          '<div class="msg them">Wednesday is looking packed on my side.</div>' +
          '<div class="msg me">Let me check, one sec</div>' +
        '</div>' +
        '<div class="composer"><div class="field"><span class="ph">Message</span><span class="txt"></span><span class="caret"></span></div></div>' +
      '</section>' +
      '<nav class="dock" aria-hidden="true">' + dock + '</nav>' +
      '<div id="pill-host" data-visible="false" role="status" aria-live="polite"></div>';
    document.body.prepend(desk);
    host = desk.querySelector('#pill-host');
    field = desk.querySelector('.field');
    fieldText = desk.querySelector('.field .txt');

    var clock = desk.querySelector('.mb-clock');
    function tickClock() {
      var d = new Date();
      clock.textContent = d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }) + '  ' +
        d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
    }
    tickClock();
    setInterval(tickClock, 15000);
  }

  function buildControls() {
    var list = window.FLOW_OPTIONS || [];
    var idx = -1;
    for (var i = 0; i < list.length; i++) if (list[i].id === opt.id) idx = i;
    var meta = list[idx] || { name: opt.id, why: '', build: '' };
    var prevO = list[(idx - 1 + list.length) % list.length];
    var nextO = list[(idx + 1) % list.length];

    ctl = document.createElement('aside');
    ctl.className = 'ctl';
    ctl.setAttribute('aria-label', 'Review controls');
    var collapsed = window.innerWidth < 900 ? 'true' : 'false';
    ctl.dataset.collapsed = collapsed;
    var stateButtons = STATES.map(function (s, n) {
      return '<button type="button" data-go="' + s + '" aria-pressed="false">' + BUTTON_LABELS[s] + '<kbd>' + (n + 1) + '</kbd></button>';
    }).join('');
    ctl.innerHTML =
      '<div class="ctl-head">' +
        '<a href="../index.html" title="All options">‹ All</a>' +
        '<span class="ctl-name">' + meta.name + '</span>' +
        '<span class="ctl-nav">' +
          (prevO ? '<a href="' + prevO.id + '.html" title="Previous: ' + prevO.name + '">‹</a>' : '') +
          '<span>' + (idx + 1) + '/' + list.length + '</span>' +
          (nextO ? '<a href="' + nextO.id + '.html" title="Next: ' + nextO.name + '">›</a>' : '') +
        '</span>' +
        '<button type="button" class="ctl-toggle" data-act="collapse" aria-expanded="' + (collapsed === 'false') + '" title="Show or hide controls">' + (collapsed === 'true' ? 'Controls' : 'Hide') + '</button>' +
      '</div>' +
      '<div class="ctl-body">' +
        '<div class="ctl-row"><button type="button" data-act="play">Play flow<kbd>Space</kbd></button><button type="button" data-act="hide">Dismiss<kbd>H</kbd></button></div>' +
        '<div class="ctl-sec"><b>Jump to a state</b><div class="ctl-states">' + stateButtons + '</div></div>' +
        '<div class="ctl-sec">' +
          '<label><input type="checkbox" data-act="mic"> Use my mic<kbd>M</kbd></label>' +
          '<label><input type="checkbox" data-act="dark"> Dark backdrop<kbd>T</kbd></label>' +
          '<label><input type="checkbox" data-act="reduce"> Reduce motion</label>' +
          '<label><input type="checkbox" data-act="autohide"> Auto-hide like the app</label>' +
          '<div class="ctl-status" aria-live="polite"></div>' +
        '</div>' +
        '<div class="ctl-about"><p>' + meta.why + '</p><p><b>SwiftUI:</b> ' + meta.build + '</p><p>Esc while listening cancels, as in the app.</p></div>' +
      '</div>';
    document.body.appendChild(ctl);

    ctl.addEventListener('click', function (e) {
      var b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.go) { S.loop = false; go(b.dataset.go); }
      else if (b.dataset.act === 'play') { if (S.playing) { stopPlay(); markControls(); } else { S.loop = false; play(); } }
      else if (b.dataset.act === 'hide') { stopPlay(); hide(); }
      else if (b.dataset.act === 'collapse') {
        var c = ctl.dataset.collapsed === 'true' ? 'false' : 'true';
        ctl.dataset.collapsed = c;
        b.textContent = c === 'true' ? 'Controls' : 'Hide';
        b.setAttribute('aria-expanded', String(c === 'false'));
      }
    });
    ctl.addEventListener('change', function (e) {
      var a = e.target.dataset.act;
      if (a === 'mic') { if (e.target.checked) enableMic(); else disableMic(); }
      else if (a === 'dark') setTheme(e.target.checked ? 'dark' : 'light');
      else if (a === 'reduce') setReduced(e.target.checked);
      else if (a === 'autohide') S.autoHide = e.target.checked;
    });
  }

  function status(msg) {
    if (!ctl) return;
    ctl.querySelector('.ctl-status').textContent = msg;
  }

  function markControls() {
    if (!ctl) return;
    ctl.querySelectorAll('[data-go]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(S.visible && !S.playing && b.dataset.go === S.state));
    });
    var p = ctl.querySelector('[data-act="play"]');
    p.firstChild.textContent = S.playing ? 'Stop' : 'Play flow';
    p.setAttribute('aria-pressed', String(S.playing));
    ctl.querySelector('[data-act="mic"]').checked = !!mic;
    ctl.querySelector('[data-act="dark"]').checked = theme === 'dark';
    ctl.querySelector('[data-act="reduce"]').checked = reduced;
  }

  function onKey(e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.target.closest && e.target.closest('input, textarea, select')) return;
    var n = parseInt(e.key, 10);
    if (n >= 1 && n <= STATES.length) { S.loop = false; go(STATES[n - 1]); return; }
    switch (e.key) {
      case ' ':
        if (e.target.closest && e.target.closest('button')) return;
        e.preventDefault();
        if (S.playing) { stopPlay(); markControls(); } else { S.loop = false; play(); }
        break;
      case 'h': case 'H': stopPlay(); hide(); break;
      case 't': case 'T': setTheme(theme === 'dark' ? 'light' : 'dark'); break;
      case 'm': case 'M': if (mic) disableMic(); else enableMic(); break;
      case 'Escape': if (S.visible && S.state === 'listening') go('cancelled'); break;
    }
  }

  function onMessage(e) {
    if (e.origin !== location.origin) return;
    var d = e.data;
    if (!d || d.type !== 'flow') return;
    if (d.cmd === 'theme') setTheme(d.value);
    else if (d.cmd === 'state') { S.loop = false; go(d.value); }
    else if (d.cmd === 'play') { S.loop = !!d.loop; play(); }
    else if (d.cmd === 'hide') { stopPlay(); hide(); }
    else if (d.cmd === 'reduce') setReduced(d.value);
  }

  function boot() {
    if (!opt) { console.error('FlowStage: no option defined'); return; }
    buildDesktop();
    opt.build(host, { reduced: reduced, theme: theme });
    if (!embed) buildControls();
    markControls();
    window.addEventListener('keydown', onKey);
    window.addEventListener('message', onMessage);
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(function () { if (opt.relayout) opt.relayout(); });
    }
    requestAnimationFrame(function (now) { last = now; requestAnimationFrame(frame); });
    if (S.loop) setTimeout(play, 600);
  }

  window.FlowStage = {
    STATES: STATES,
    MESSAGES: MESSAGES,
    TEXT: TEXT,
    WORDS: WORDS,
    fitCanvas: fitCanvas,
    fitWidth: fitWidth,
    replay: replay,
    formatElapsed: formatElapsed,
    noise: noise1,
    clamp: clamp,
    isReduced: function () { return reduced; },
    getState: function () { return S.state; },
    // SF-Symbol-like line icons, 24 x 24, stroked with currentColor.
    icons: {
      success: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 12.5l4.2 4.2L18.5 7.5"/></svg>',
      cancelled: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M7.5 7.5l9 9M16.5 7.5l-9 9"/></svg>',
      noSpeech: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M9.2 9.3V7a2.8 2.8 0 0 1 5.6 0v4.6M14.4 14a2.8 2.8 0 0 1-5.2-1.4v-.6"/><path d="M6 11.5a6 6 0 0 0 9.6 4.8M18 11.5c0 .9-.2 1.7-.5 2.4M12 17.5V20"/><path d="M4.5 4.5l15 15"/></svg>',
      copied: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="5.5" width="12" height="14.5" rx="2.2"/><path d="M9.5 5.5V4.6c0-.6.4-1 1-1h3c.6 0 1 .4 1 1v.9M9.5 11h5M9.5 14.5h3.5"/></svg>',
      error: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M10.4 4.6a1.8 1.8 0 0 1 3.2 0l6.9 12.3a1.8 1.8 0 0 1-1.6 2.7H5.1a1.8 1.8 0 0 1-1.6-2.7z"/><path d="M12 9.5v4M12 16.6v.01"/></svg>'
    },
    define: function (o) { opt = o; }
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else setTimeout(boot, 0);
})();
