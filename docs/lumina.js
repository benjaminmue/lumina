/* Lumina landing page script.
   The engine (scrollcraft.js) is untouched: it pins the acts and publishes
   progress. Everything bespoke here reads scroll itself and reproduces the
   transition math from Sources/Lumina/Views/SlideTransitions.swift:

     cut        identity, no animation at all
     crossfade  opacity only
     slide      incoming from the trailing edge, outgoing stays put and fades
     push       incoming from trailing, outgoing out to leading, together
     zoom       incoming 1.18 -> 1.0 with opacity, outgoing 1.0 -> 0.88 with opacity
     wipe       incoming revealed by a rectangular mask growing from the
                trailing edge, outgoing fades
     flip       two half phases: outgoing rotates away over duration/2 with
                ease-in, incoming rotates in over duration/2 with ease-out and
                a duration/2 delay
*/
(function () {
  'use strict';

  var d = document, root = d.documentElement;
  root.classList.add('sc-js');

  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var projector = d.getElementById('projector');

  if (reduce) {
    root.classList.add('sc-reduce');
    // Hand the projector back to the document: plain stacked figures with
    // captions. The engine must not pin it.
    if (projector) projector.removeAttribute('data-sc-act');
  } else {
    root.classList.add('sc-motion');
  }

  if (window.ScrollCraft) ScrollCraft.mount(d.body);

  var clamp01 = function (x) { return x < 0 ? 0 : x > 1 ? 1 : x; };
  var easeIn = function (t) { return t * t; };
  var easeOut = function (t) { return 1 - (1 - t) * (1 - t); };
  var easeInOut = function (t) { return t * t * (3 - 2 * t); };

  /* ---- shared transition math ------------------------------------------ */
  /* Fills A (outgoing) and B (incoming) with {o, tf, clip, z} for progress t. */
  function applyTransition(type, t, A, B) {
    var e = easeInOut(clamp01(t));
    switch (type) {
      case 'cut':
        if (t < 1) { A.o = 1; A.z = 1; } else { B.o = 1; B.z = 2; }
        break;
      case 'crossfade':                      /* opacity only */
        A.o = 1 - e; A.z = 1;
        B.o = e; B.z = 2;
        break;
      case 'slide':                          /* incoming moves, outgoing fades in place */
        A.o = 1 - e; A.z = 1;
        B.o = 1; B.z = 2;
        B.tf = 'translate3d(' + (100 * (1 - e)).toFixed(3) + '%,0,0)';
        break;
      case 'push':                           /* both travel together */
        A.o = 1; A.z = 1;
        A.tf = 'translate3d(' + (-100 * e).toFixed(3) + '%,0,0)';
        B.o = 1; B.z = 2;
        B.tf = 'translate3d(' + (100 * (1 - e)).toFixed(3) + '%,0,0)';
        break;
      case 'zoom':                           /* 1.18 -> 1 in, 1 -> 0.88 out, with opacity */
        A.o = 1 - e; A.z = 1;
        A.tf = 'scale(' + (1 - 0.12 * e).toFixed(4) + ')';
        B.o = e; B.z = 2;
        B.tf = 'scale(' + (1.18 - 0.18 * e).toFixed(4) + ')';
        break;
      case 'wipe':                           /* rectangular mask from the trailing edge */
        A.o = 1 - e; A.z = 1;
        B.o = 1; B.z = 2;
        B.clip = 'inset(0 0 0 ' + (100 * (1 - e)).toFixed(2) + '%)';
        break;
      case 'flip':                           /* two half phases with the delay */
        if (t < 0.5) {
          A.o = 1; A.z = 2;
          A.tf = 'rotateY(' + (-90 * easeIn(t * 2)).toFixed(2) + 'deg)';
        } else {
          B.o = 1; B.z = 2;
          B.tf = 'rotateY(' + (90 * (1 - easeOut(t * 2 - 1))).toFixed(2) + 'deg)';
        }
        break;
    }
  }

  function writeFrame(el, cache, st) {
    var o = st.o.toFixed(3), tf = st.tf || '', clip = st.clip || '', z = String(st.z || 0);
    if (cache.o !== o) { el.style.opacity = o; cache.o = o; }
    if (cache.tf !== tf) { el.style.transform = tf; cache.tf = tf; }
    if (cache.clip !== clip) { el.style.clipPath = clip; cache.clip = clip; }
    if (cache.z !== z) { el.style.zIndex = z; cache.z = z; }
  }

  /* ---- act one: the projector ------------------------------------------ */
  function initProjector() {
    var stage = projector.querySelector('[data-sc-stage]');
    var frames = Array.prototype.slice.call(projector.querySelectorAll('.frame'));
    var kbs = frames.map(function (f) { return f.querySelector('.kb'); });
    var files = ['cliffs.webp', 'saturn.webp', 'jupiter.webp', 'pillars.webp', 'bluemarble.webp'];
    var hud = d.getElementById('hud');
    var hudFile = d.getElementById('hud-file');
    var hudState = d.getElementById('hud-state');
    /* The engine fades the hero copy out with the first scroll but leaves it
       in the tab order, so a keyboard user could focus an invisible Download
       link. Mirror the cue's opacity into visibility so the link leaves the
       focus order while it cannot be seen. */
    var heroCopy = projector.querySelector('.copy-hero');
    var heroVis = '';

    /* the slideshow timeline, in fractions of the act's pinned travel */
    var SEGS = [
      { type: 'hold', slide: 0, from: 0.000, to: 0.145 },
      { type: 'crossfade', a: 0, b: 1, from: 0.145, to: 0.235, label: 'Crossfade' },
      { type: 'hold', slide: 1, from: 0.235, to: 0.325 },
      { type: 'push', a: 1, b: 2, from: 0.325, to: 0.415, label: 'Push' },
      { type: 'hold', slide: 2, from: 0.415, to: 0.505 },
      { type: 'wipe', a: 2, b: 3, from: 0.505, to: 0.595, label: 'Wipe' },
      { type: 'hold', slide: 3, from: 0.595, to: 0.685 },
      { type: 'flip', a: 3, b: 4, from: 0.685, to: 0.790, label: 'Flip' },
      { type: 'hold', slide: 4, from: 0.790, to: 1.001 }
    ];
    /* each slide's on-screen life, for Ken Burns across holds AND transitions */
    var LIFE = [[0, 0.235], [0.145, 0.415], [0.325, 0.595], [0.505, 0.790], [0.685, 1.0]];
    /* Ken Burns Medium: zoom 1.0 -> 1.14, pan 0.05 of the edge, seeded per image */
    var PAN = [[0.85, -0.53], [-0.92, 0.39], [0.55, 0.84], [-0.76, -0.65], [0.98, 0.20]];

    var caches = frames.map(function () { return {}; });
    var kbCache = frames.map(function () { return ''; });
    var st = frames.map(function () { return { o: 0, tf: '', clip: '', z: 0 }; });
    var top = 0, H = 1, vh = innerHeight, lastY = -1, dirty = true;
    var lastHudFile = '', lastHudState = '', lastVerify = '', hudOn = null;

    function measure() {
      var r = projector.getBoundingClientRect();
      top = r.top + scrollY;
      H = projector.offsetHeight;
      vh = innerHeight;
      dirty = true;
    }

    function render(p, y) {
      var i, seg = SEGS[SEGS.length - 1];
      for (i = 0; i < SEGS.length; i++) { if (p < SEGS[i].to) { seg = SEGS[i]; break; } }
      var segIdx = SEGS.indexOf(seg);
      var t = 0;

      for (i = 0; i < st.length; i++) { st[i].o = 0; st[i].tf = ''; st[i].clip = ''; st[i].z = 0; }
      if (seg.type === 'hold') {
        st[seg.slide].o = 1; st[seg.slide].z = 1;
      } else {
        t = clamp01((p - seg.from) / (seg.to - seg.from));
        applyTransition(seg.type, t, st[seg.a], st[seg.b]);
      }

      /* Ken Burns on every visible slide, across its whole on-screen life */
      for (i = 0; i < frames.length; i++) {
        if (st[i].o <= 0 && !(seg.type !== 'hold' && (i === seg.a || i === seg.b))) continue;
        var lp = clamp01((p - LIFE[i][0]) / (LIFE[i][1] - LIFE[i][0]));
        var s = (1 + 0.14 * lp).toFixed(4);
        var tx = (PAN[i][0] * 5 * lp).toFixed(3);
        var ty = (PAN[i][1] * 2.6 * lp).toFixed(3);
        var kb = 'translate3d(' + tx + '%,' + ty + '%,0) scale(' + s + ')';
        if (kbCache[i] !== kb) { kbs[i].style.transform = kb; kbCache[i] = kb; }
      }

      for (i = 0; i < frames.length; i++) writeFrame(frames[i], caches[i], st[i]);

      /* the player readout */
      var f, sTxt;
      if (seg.type === 'hold') {
        f = files[seg.slide];
        sTxt = 'slide ' + (seg.slide + 1) + ' of 5';
      } else {
        f = files[seg.b];
        /* Pad the percentage to three digits (trailing spaces, .hud__state is
           white-space: pre) so the pill's width holds still while the readout
           counts instead of jumping at 9 -> 10 and 99 -> 100. */
        var pct = String(Math.round(t * 100));
        sTxt = seg.label.toLowerCase() + ' ' + pct + '%' +
               (pct.length < 3 ? Array(4 - pct.length).join(' ') : '');
      }
      if (f !== lastHudFile) { hudFile.textContent = f; lastHudFile = f; }
      if (sTxt !== lastHudState) { hudState.textContent = sTxt; lastHudState = sTxt; }
      var on = y < top + H - vh * 0.6;
      if (on !== hudOn) { hud.classList.toggle('hud--on', on); hudOn = on; }

      /* let the verification harness see the composition change */
      var v = segIdx + ':' + (seg.type === 'hold' ? 'hold' + seg.slide : seg.type + ':' + (Math.round(t * 50) / 50));
      if (v !== lastVerify) { stage.setAttribute('data-sc-verify-state', v); lastVerify = v; }
    }

    function frame() {
      var y = scrollY;
      if (y !== lastY || dirty) {
        lastY = y; dirty = false;
        render(clamp01((y - top) / Math.max(H - vh, 1)), y);
      }
      /* focus-order sync for the cue-faded hero copy (no layout read: the
         engine writes the cue's opacity as an inline style) */
      if (heroCopy) {
        var hv = parseFloat(heroCopy.style.opacity || '1') <= 0.02 ? 'hidden' : '';
        if (hv !== heroVis) { heroCopy.style.visibility = hv; heroVis = hv; }
      }
      requestAnimationFrame(frame);
    }

    addEventListener('resize', measure);
    addEventListener('load', measure);
    measure();
    requestAnimationFrame(function () { requestAnimationFrame(function () { measure(); frame(); }); });
  }

  /* ---- the picker: every entry, on demand ------------------------------- */
  function initPicker() {
    var stageEl = d.getElementById('picker-stage');
    if (!stageEl) return;
    var desc = d.getElementById('picker-desc');
    var buttons = Array.prototype.slice.call(d.querySelectorAll('.pbtn'));
    var panes = Array.prototype.slice.call(stageEl.querySelectorAll('.pframe'));
    var caches = [{}, {}];
    var cur = 0, rafId = 0, active = null;

    var DESC = {
      cut: 'Identity. No animation at all.',
      crossfade: 'Opacity only. Nothing moves.',
      slide: 'The incoming moves in from the trailing edge; the outgoing stays put and fades.',
      push: 'Incoming from the trailing edge, outgoing out through the leading edge: both travel together, like a film strip.',
      zoom: 'The incoming scales from 1.18 with opacity; the outgoing scales down to 0.88 with opacity.',
      wipe: 'A rectangular mask grows from the trailing edge; the outgoing fades.',
      flip: 'Two half phases: the outgoing rotates away with ease-in, then the incoming rotates in with ease-out, half a duration later.',
      random: 'One of the seven, chosen for you.'
    };
    var LABEL = { cut: 'Hard cut', crossfade: 'Crossfade', slide: 'Slide', push: 'Push', zoom: 'Zoom', wipe: 'Wipe', flip: 'Flip' };
    var STYLES = ['cut', 'crossfade', 'slide', 'push', 'zoom', 'wipe', 'flip'];

    function settle(A, B) {
      A.style.opacity = '0'; A.style.transform = ''; A.style.clipPath = ''; A.style.zIndex = '0';
      B.style.opacity = '1'; B.style.transform = ''; B.style.clipPath = ''; B.style.zIndex = '1';
      caches[0] = {}; caches[1] = {};
      cur = 1 - cur;
      active = null;
    }

    function run(style, btn) {
      /* Interruptible: a click during a running transition lands the running
         one instantly and starts the new one, instead of being swallowed. */
      if (active) { cancelAnimationFrame(rafId); settle(active.A, active.B); }
      var chosen = style;
      var text = DESC[style];
      if (style === 'random') {
        chosen = STYLES[Math.floor(Math.random() * STYLES.length)];
        text = 'Random chose ' + LABEL[chosen] + '. ' + DESC[chosen];
      }
      desc.textContent = text;
      buttons.forEach(function (b) { b.setAttribute('aria-pressed', b === btn ? 'true' : 'false'); });

      var A = panes[cur], B = panes[1 - cur];
      if (reduce || chosen === 'cut') { settle(A, B); return; }

      active = { A: A, B: B };
      var t0 = performance.now();
      var DUR = 1000; /* the app's default transition duration: 1.0 s */
      var stA = {}, stB = {};
      (function tick(now) {
        var t = Math.min((now - t0) / DUR, 1);
        stA.o = 0; stA.tf = ''; stA.clip = ''; stA.z = 1;
        stB.o = 0; stB.tf = ''; stB.clip = ''; stB.z = 2;
        stA.o = chosen === 'flip' ? 0 : 1;
        applyTransition(chosen, t, stA, stB);
        writeFrame(A, caches[0], stA);
        writeFrame(B, caches[1], stB);
        if (t < 1) rafId = requestAnimationFrame(tick);
        else settle(A, B);
      })(t0);
    }

    buttons.forEach(function (b) {
      b.addEventListener('click', function () { run(b.getAttribute('data-t'), b); });
    });
  }

  initPicker();
  if (!reduce && projector) initProjector();
})();
