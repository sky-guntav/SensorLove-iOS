// The visitor is the reading: their pointer (where it is, and a click), or their phone's tilt, shakes and spins once they press
// TRY in the experience (ASK_TILT; iOS asks on that tap). All of it goes in window.TILT, which the hero's experience (xp.js) and the app's motion toys
// (monitor.js) read; nothing is kept or sent. The app's phone (iframe.monitor) is zoomed to fit a narrow screen.
(function () {
  var T = window.TILT = { x:0, y:0, px:0, py:0, at:0, tap:0, dev:null, acc:null, rot:null };
  var f = document.querySelector('iframe.monitor'), granted = false, pending = false;
  function point(x, y) { T.px = x; T.py = y; T.x = x / innerWidth * 2 - 1; T.y = y / innerHeight * 2 - 1; T.at = performance.now(); }
  addEventListener('pointermove', function (e) { point(e.clientX, e.clientY); });
  addEventListener('pointerdown', function (e) { point(e.clientX, e.clientY); T.tap = performance.now(); T.tapOn = e.target; T.down = true; });
  addEventListener('pointerup', function () { T.down = false; });
  addEventListener('pointercancel', function () { T.down = false; });
  if (document.body.classList.contains('home')) { document.addEventListener('gesturestart', function (e) { e.preventDefault(); }); }   // iOS Safari pinches past user-scalable=no; this stops it on the home page

  var BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5], REDUCED = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var splash = function () {}, repaint = function () {}, hint = function () {}, heroEl = document.querySelector('.hero');   // the water's, the hero's (below)

  // The home page's ground, the app's unlit dots (style.css, on the root), is water: a ripple tank on their own grid, a dot a cell
  // (4 px), lit from the top left and drawn in the app's ordered dither (4 x 4 Bayer), lit dots in ink, and a slow river of noise
  // drifting under it all, as faint as the sketch's. The mouse leaves a wake; a press drops a wide stone whose rings run
  // far (two steps a frame while touched, damped less than the sketch) and keeps dropping while held; 18 frames a second, 36
  // while touched. After the user's TOUCH / RIVER FLOW sketch (its 500 px canvas had 4 px cells too). The canvas lies on the page
  // a window high and moves down it as it scrolls, so the water scrolls with the page. Only with a mouse, and not for reduced motion
  if (document.body.classList.contains('home') && matchMedia('(pointer: fine)').matches && !REDUCED) {
    var cv = document.createElement('canvas'), g = cv.getContext('2d'), css = getComputedStyle(document.documentElement);
    var DIM = css.getPropertyValue('--dim').trim(), MID = css.getPropertyValue('--mid').trim(), P = new Uint8Array(512);
    var W, H, top = 0, a, b, wet = false, at = null, down = false, fps = 18, touched = 0, then = 0, moved = false, t0 = performance.now();
    (function () { var p = [], i, j, k; for (i = 0; i < 256; i++) { p[i] = i; } for (i = 255; i > 0; i--) { j = Math.floor(Math.random() * (i + 1)); k = p[i]; p[i] = p[j]; p[j] = k; } for (i = 0; i < 512; i++) { P[i] = p[i & 255]; } })();
    var perlin = function (x, y) {                      // 2D gradient noise, 0 to 1 (p5's noise in the sketch)
      var X = Math.floor(x), Y = Math.floor(y), fx = x - X, fy = y - Y, u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy), A, B, C, D;
      var gr = function (h, dx, dy) { return (h & 1 ? dx : -dx) + (h & 2 ? dy : -dy); };
      X &= 255; Y &= 255;
      A = gr(P[P[X] + Y], fx, fy); B = gr(P[P[X + 1] + Y], fx - 1, fy); C = gr(P[P[X] + Y + 1], fx, fy - 1); D = gr(P[P[X + 1] + Y + 1], fx - 1, fy - 1);
      return .5 + .5 * (A + (B - A) * u + (C + (D - C) * u - A - (B - A) * u) * v);
    };
    var size = function () {                            // a cell a dot; the canvas's px its own (style.css: innerWidth counts the scrollbar)
      var d = devicePixelRatio || 1, w = document.documentElement.clientWidth;
      W = Math.ceil(w / 4); H = Math.floor(innerHeight / 4);   // never past the window's foot: the page would grow under it
      cv.width = w * d; cv.height = H * 4 * d; cv.style.height = H * 4 + 'px'; g.setTransform(d, 0, 0, d, 0, 0);
      a = new Float32Array(W * H); b = new Float32Array(W * H); wet = false;
      top = Math.floor(scrollY / 4) * 4; cv.style.top = top + 'px';
    };
    var anchor = function () {                          // the page scrolled: the canvas moves down it, the water's rows with the page
      var nt = Math.floor(scrollY / 4) * 4, dr = (nt - top) / 4, n = Math.abs(dr) * W;
      if (!dr) { return; }
      [a, b].forEach(function (u) {
        if (Math.abs(dr) >= H) { u.fill(0); } else if (dr > 0) { u.copyWithin(0, n); u.fill(0, u.length - n); } else { u.copyWithin(n, 0, u.length - n); u.fill(0, 0, n); }
      });
      top = nt; cv.style.top = top + 'px';
    };
    var step = function () {                            // each cell: its neighbours' mean, less where it was, damped (hard by the window's edges: nothing comes back off them)
      var x, y, i, m = 0, v, t;
      for (y = 1; y < H - 1; y++) {
        for (x = 1; x < W - 1; x++) {
          i = y * W + x;
          v = ((a[i - 1] + a[i + 1] + a[i - W] + a[i + W]) / 2 - b[i]) * (x < 6 || x > W - 7 || y < 6 || y > H - 7 ? .19 : .955);
          b[i] = v; if (v > m) { m = v; } else if (-v > m) { m = -v; }
        }
      }
      t = a; a = b; b = t;
      if (m < .2) { a.fill(0); b.fill(0); }             // still: no tank to run until the next stone
      return m >= .2;
    };
    var drop = function (px, py, e, r) {                // a stone at the window's (px, py), weighing e at its middle, r cells across (less to its rim)
      var x0 = Math.floor(px / 4), y0 = Math.floor((py + scrollY - top) / 4), x, y, d;
      for (y = Math.max(1, y0 - r); y <= Math.min(H - 2, y0 + r); y++) {
        for (x = Math.max(1, x0 - r); x <= Math.min(W - 2, x0 + r); x++) {
          d = Math.hypot(x - x0, y - y0);
          if (d <= r) { a[y * W + x] += e * (1 - d / (r + 1)); }
        }
      }
      wet = true; touched = 30;
    };
    var HDIM, HMID, hcss = heroEl ? getComputedStyle(heroEl) : css;   // the hero's own inks (its night or day)
    var draw = function (now) {                         // a dot's place: (4x + 2, 4y + 2) on the canvas, on the page's grid (its top a multiple of 4)
      var P4 = [new Path2D(), new Path2D(), new Path2D(), new Path2D()], r0 = top / 4, f = (now - t0) * .00063, x, y, i, k, s, v, p;
      var hb = heroEl ? (heroEl.getBoundingClientRect().bottom + scrollY) / 4 : 0;   // the hero's last row, on the page
      g.clearRect(0, 0, W * 4, H * 4);
      for (y = 1; y < H - 1; y++) {
        for (x = 1; x < W - 1; x++) {
          k = (BAYER[((y + r0) & 3) * 4 + (x & 3)] + .5) / 16;
          i = y * W + x;
          s = wet ? Math.max(0, -.6 * (a[i + 1] - a[i - 1]) - .6 * (a[i + W] - a[i - W])) * .16 : 0;   // the light off the water's slope
          if (s + .05 <= k) { continue; }               // too dark here even with the river at its brightest
          v = s + (perlin(x * .04 - f, (y + r0) * .04 - f) * .7 + perlin(x * .08 - f * 1.5, (y + r0) * .08 - f * 1.5) * .3) * .05;
          if (v > k) { p = P4[(s > .02 ? 1 : 0) + (y + r0 < hb ? 2 : 0)]; p.moveTo(x * 4 + 3.1, y * 4 + 2); p.arc(x * 4 + 2, y * 4 + 2, 1.1, 0, 7); }
        }
      }
      [DIM, MID, HDIM, HMID].forEach(function (ink, n) { g.fillStyle = ink; g.fill(P4[n]); });   // the river faint, the water's light in ink; the hero's in its own
    };
    var loop = function (now) {
      requestAnimationFrame(loop);
      if (!moved && now - then < 1000 / fps) { return; }
      then = now; moved = false;
      if (touched > 0) { fps += (36 - fps) * .2; touched--; } else { fps += (18 - fps) * .05; }
      anchor();
      if (down && at) { drop(at.x, at.y, 120, 1); }
      if (wet) { wet = step(); }
      if (wet && touched > 0) { wet = step(); }          // touched: the rings run twice as fast, out to the room around
      draw(now);
    };
    cv.className = 'ground';
    cv.setAttribute('aria-hidden', 'true');
    document.body.prepend(cv);
    size();
    requestAnimationFrame(loop);
    addEventListener('resize', size);
    addEventListener('pointermove', function (e) {     // a wake, heavier the faster it goes
      if (e.pointerType !== 'mouse') { return; }
      if (at) { drop(e.clientX, e.clientY, Math.min(10, Math.hypot(e.clientX - at.x, e.clientY - at.y) * .25), 1); }
      at = { x:e.clientX, y:e.clientY };
    });
    addEventListener('pointerdown', function (e) { if (e.pointerType === 'mouse' && !e.button) { at = { x:e.clientX, y:e.clientY }; down = true; drop(at.x, at.y, 320, 3); } });   // the left button: a right click opens the menu
    addEventListener('pointerup', function () { down = false; });
    addEventListener('pointercancel', function () { down = false; });
    addEventListener('pointerover', function (e) { if (e.target === f) { at = null; down = false; } });   // into the app's phone: its own page
    document.documentElement.addEventListener('pointerleave', function () { at = null; down = false; });
    addEventListener('scroll', function () { moved = true; }, { passive:true });
    splash = function (x, y, k) { drop(x, y, 320 * (k || 1), 3); };   // k: lighter stones (ALIVE's heartbeat)
    repaint = function () { HDIM = hcss.getPropertyValue('--dim').trim(); HMID = hcss.getPropertyValue('--mid').trim(); };   // the hero's night and day
    repaint();
  }

  // ALIVE beats like a heart while the mouse is on it: lub, dub, each a swell and a stone in the water under it (the second
  // lighter); the faster the mouse has lately gone over the page, the faster it beats, 66 to 150 a minute, calming over a few
  // beats. A finger's tap beats it once (a phone has no hover). Not for reduced motion
  var heart = document.querySelector('.alive');
  if (heart && !REDUCED) {
    var bpm = 66, pace = 0, prev = null, hover = false, due = null;
    var LUBDUB = [{ transform:'scale(1)' }, { transform:'scale(1.07)', offset:.14 }, { transform:'scale(.99)', offset:.3 }, { transform:'scale(1.04)', offset:.44 }, { transform:'scale(1)', offset:.7 }, { transform:'scale(1)' }];
    var beat = function () {                            // one lub-dub; the time to the next
      var r = heart.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height * .6, T = 60000 / bpm, d = Math.min(560, T * .85);
      heart.animate(LUBDUB, { duration:d });
      splash(x, y, .6);
      setTimeout(function () { splash(x, y, .35); }, d * .44);
      bpm += (66 + Math.min(84, pace * 60) - bpm) * .5;   // the pulse follows the mouse's pace (px a ms), and calms as it slows
      pace *= .6;
      return T;
    };
    var pulse = function () { due = hover ? setTimeout(pulse, beat()) : null; };
    heart.addEventListener('pointerenter', function (e) { if (e.pointerType === 'mouse') { hover = true; if (!due) { pulse(); } } });
    heart.addEventListener('pointerleave', function () { hover = false; });
    heart.addEventListener('pointerdown', function (e) { if (e.pointerType !== 'mouse') { beat(); } });
    addEventListener('pointermove', function (e) {
      var now = performance.now();
      if (e.pointerType !== 'mouse') { return; }
      if (prev && now > prev.t) { pace += (Math.min(3, Math.hypot(e.clientX - prev.x, e.clientY - prev.y) / (now - prev.t)) - pace) * .1; }
      prev = { x:e.clientX, y:e.clientY, t:now };
    });
  }

  // The hero is night (style.css) until a double click in it, anywhere but a link, a button or the phone, turns it to day, and
  // back: only the hero, and the app in the phone with it (its own switchTheme). The ink floods out of the click over the hero
  // alone, or drains back into it. A small note at the mouse there says what a right and a double click do, each line until used
  if (heroEl) {
    var note = document.createElement('div'), lines = ['RIGHT CLICK: MENU', 'DOUBLE CLICK: DAY'], showing = false;
    var tell = function () { note.textContent = lines.filter(Boolean).join('\n'); note.hidden = !showing || !note.textContent; };
    var away = function (t) { return t.closest && t.closest('a, button, iframe'); };
    note.className = 'note';
    note.setAttribute('aria-hidden', 'true');
    note.hidden = true;
    heroEl.appendChild(note);
    heroEl.addEventListener('pointermove', function (e) {
      showing = e.pointerType === 'mouse' && !away(e.target);
      note.style.left = e.clientX + 16 + 'px'; note.style.top = e.clientY + 20 + 'px';
      tell();
    });
    heroEl.addEventListener('pointerover', function (e) { if (away(e.target)) { showing = false; tell(); } });
    heroEl.addEventListener('pointerleave', function () { showing = false; tell(); });
    heroEl.addEventListener('dblclick', function (e) {
      var r = heroEl.getBoundingClientRect(), top = Math.max(0, r.top), box = { left:0, top:top, width:document.documentElement.clientWidth, height:Math.min(innerHeight, r.bottom) - top, rgb:[10, 9, 8] };
      var turn = function () {
        var day = heroEl.classList.toggle('day'), app = f && f.contentWindow;
        if (app && app.switchTheme) { app.switchTheme(day ? 'light' : 'dark'); }
        lines[1] = ''; tell(); repaint();
      };
      if (away(e.target)) { return; }
      if (REDUCED || box.height <= 0) { turn(); }
      else if (heroEl.classList.contains('day')) { wipe(e.clientX, e.clientY, true, function (c) { turn(); c.remove(); }, box); }
      else { turn(); wipe(e.clientX, e.clientY, false, function (c) { c.remove(); }, box); }   // day under the night's ink, drained from the click
    });
    hint = function () { lines[0] = ''; tell(); };     // the menu was opened: its line goes
  }

  // A link to another of the site's pages floods the window with ink from where it was pressed, in the same dither, ripples
  // running ahead of it; the page it opens drains from that point out, ripples left behind (and on the home page a stone in its
  // water). The point is kept for the tab (sessionStorage, sensorlove.go): dt.js darkens the new page from its first paint until
  // this opens it. Not for reduced motion
  function wipe(x, y, out, done, box) {                 // out: the ink floods in from (x, y); else it drains away from there. box: only that part of the window, in its ink. done(canvas) at the end
    var b = box || { left:0, top:0, width:innerWidth, height:innerHeight, rgb:[20, 18, 15] };   // --lit
    var c = document.createElement('canvas'), W = Math.ceil(b.width / 4), H = Math.ceil(b.height / 4), ctx, img, p, n;
    var T = out ? 420 : 640, R = Math.hypot(Math.max(x - b.left, b.left + b.width - x), Math.max(y - b.top, b.top + b.height - y)) + 120, t0 = performance.now();
    c.width = W; c.height = H; c.className = 'wipe'; c.style.width = W * 4 + 'px'; c.style.height = H * 4 + 'px'; c.style.left = b.left + 'px'; c.style.top = b.top + 'px';
    x -= b.left; y -= b.top;
    ctx = c.getContext('2d'); img = ctx.createImageData(W, H); p = img.data;
    for (n = 0; n < p.length; n += 4) { p[n] = b.rgb[0]; p[n + 1] = b.rgb[1]; p[n + 2] = b.rgb[2]; }
    document.body.appendChild(c);
    (function frame(now) {
      var k = Math.min(1, (now - t0) / T), r = R * (out ? k * k : 1 - Math.pow(1 - k, 3)), i, j, q, v;
      for (j = 0; j < H; j++) {
        for (i = 0; i < W; i++) {
          q = Math.hypot(i * 4 + 2 - x, j * 4 + 2 - y); q = out ? r - q : q - r;   // > 0: ink
          v = Math.min(1, Math.max(0, q / 60 + .5)) + (q < 0 ? (out ? .5 : .5 * (1 - k)) * Math.exp(q / 80) * (.5 + .5 * Math.cos(q * Math.PI / 18)) : 0);   // its edge, and ripples on the water past it
          p[(j * W + i) * 4 + 3] = v > (BAYER[(j & 3) * 4 + (i & 3)] + .5) / 16 ? 255 : 0;
        }
      }
      ctx.putImageData(img, 0, 0);
      if (k < 1) { requestAnimationFrame(frame); } else { done(c); }
    })(t0);
  }
  var came = null;
  try { came = JSON.parse(sessionStorage.getItem('sensorlove.go')); sessionStorage.removeItem('sensorlove.go'); } catch (e) { /* none kept */ }
  if (document.documentElement.classList.contains('dt')) {
    wipe(came ? came.x : innerWidth / 2, came ? came.y : innerHeight / 2, false, function (c) { c.remove(); });
    document.documentElement.classList.remove('dt');   // the canvas's ink covers it now
    if (came) { splash(came.x, came.y); }
  }
  addEventListener('pageshow', function (e) { if (e.persisted) { document.querySelectorAll('.wipe').forEach(function (c) { c.remove(); }); } });   // back to a page left flooded
  document.addEventListener('click', function (e) {
    var l = e.target.closest ? e.target.closest('a[href]') : null, u, r, x, y;
    if (!l || e.defaultPrevented || e.button || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || l.target || l.hasAttribute('download') || REDUCED) { return; }
    u = new URL(l.href, location.href);
    if (u.origin !== location.origin || u.pathname === location.pathname) { return; }   // another site, mail, or a place on this page
    e.preventDefault();
    r = l.getBoundingClientRect(); x = e.detail ? e.clientX : r.left + r.width / 2; y = e.detail ? e.clientY : r.top + r.height / 2;   // a key's click: the link's middle
    try { sessionStorage.setItem('sensorlove.go', JSON.stringify({ x:x, y:y, t:Date.now() })); } catch (err) { /* it opens from the middle */ }
    wipe(x, y, true, function () { location.href = u.href; });
  });

  // A right click on the page itself, the experience's window too, opens its pages as a small menu where it was pressed (the
  // footer's list, and the home page from a doc); on a link, a control, the phone or selected text, or with Shift, the browser's own menu stays.
  // Escape, a press elsewhere or a scroll closes it; its links flood out like any other
  var menu = null;
  function shut() { if (menu) { menu.remove(); menu = null; } }
  document.addEventListener('contextmenu', function (e) {
    var src = document.querySelector('footer nav'), t = e.target, home, r;
    shut();
    if (e.shiftKey || !src || String(getSelection()) || (t.closest && t.closest('a, button, input, textarea, select, iframe, video, pre, code, [contenteditable]'))) { return; }
    e.preventDefault();
    menu = document.createElement('nav');
    menu.className = 'ctx';
    menu.setAttribute('aria-label', 'Pages');
    if (!document.body.classList.contains('home')) { home = menu.appendChild(document.createElement('a')); home.href = '/'; home.textContent = 'SENSORLOVE'; }
    [].forEach.call(src.querySelectorAll('a'), function (a) { menu.appendChild(a.cloneNode(true)); });
    document.body.appendChild(menu);
    r = menu.getBoundingClientRect();
    menu.style.left = Math.max(8, Math.min(e.clientX, innerWidth - r.width - 8)) + 'px';
    menu.style.top = Math.max(8, Math.min(e.clientY, innerHeight - r.height - 8)) + 'px';
    menu.tabIndex = -1;
    menu.focus({ preventScroll:true });                 // the menu, not its first page: Tab goes on into it, nothing lit before the mouse is there
    hint();
  });
  addEventListener('pointerdown', function (e) { if (menu && !menu.contains(e.target)) { shut(); } }, true);
  addEventListener('keydown', function (e) { if (e.key === 'Escape') { shut(); } });
  addEventListener('scroll', shut, { passive:true });
  addEventListener('blur', shut);

  // SUPPORT ME's garden (build.py): bare until it comes into view, then it grows from the wizard out, each plant through HELLO's
  // stages (a shoot, two leaves, a bud, its flower; a fir tier by tier), the last with a small bounce, on GSAP's clock (gsap.min.js,
  // loaded on the home page after this; all deferred scripts have run by DOMContentLoaded). Without it, or for reduced motion, grown
  document.addEventListener('DOMContentLoaded', function () {
    var garden = document.querySelector('.garden');
    if (!garden || !window.gsap || matchMedia('(prefers-reduced-motion: reduce)').matches) { return; }
    gsap.set(garden.querySelectorAll('.plant > g'), { autoAlpha:0 });
    var io = new IntersectionObserver(function (es) {
      if (!es[0].isIntersecting) { return; }
      io.disconnect();
      var tl = gsap.timeline();
      garden.querySelectorAll('.plant').forEach(function (p) {
        var st = p.children, at = p.dataset.d / 60, dt = p.classList.contains('fir') ? .3 : .15, k;   // 60 dots a second out from him
        for (k = 0; k < st.length; k++) {
          tl.set(st[k], { autoAlpha:1 }, at + k * dt);
          if (k) { tl.set(st[k - 1], { autoAlpha:0 }, at + k * dt); }
        }
        tl.from(st[k - 1], { scale:1.3, transformOrigin:'50% 100%', duration:.4, ease:'back.out(3)' }, at + (k - 1) * dt);
      });
    }, { rootMargin:'0px 0px -15% 0px' });               // its top a little way up the window
    io.observe(garden);
  });

  if (f) {
    var fit = function () { f.style.zoom = Math.min(1, (innerWidth - 2 * Math.max(22, innerWidth * .04) - 26) / 390, innerWidth >= 1000 ? (innerHeight - 110) / 866 : 1); };   // a phone's width; on a computer, the window's height
    fit();
    addEventListener('resize', fit);
    f.addEventListener('load', function () {           // over the phone the pointer is the frame's: back into the window's terms
      f.contentWindow.addEventListener('pointermove', function (e) {
        var r = f.getBoundingClientRect(), k = r.width / f.contentWindow.innerWidth;
        point(r.left + e.clientX * k, r.top + e.clientY * k);
      });
    });
  }

  // SOUND(name, {n, pan, f, g}): the hero's few quiet sounds, made here and now (no files): a ring chimes a note of a pentatonic scale,
  // a line about the app comes with a soft fifth, a boost breathes, the frog blinks with a pip, the search beeps, the start swells; the drums
// (KNOCK BEAT) and the orchestra (CONDUCTOR) play on the sound's own clock (SOUND.time);
  // 'tone' is the theremin's one held voice (f, g). Browsers allow sound only after a tap or a key, so the first one starts it;
  // the speaker in the experience's corner stops it for the visit (nothing is kept).
  var A = null, on = true, noise = null, tone = null, sb = document.querySelector('.sound');
  function wake() {
    if (!on) { return; }
    try { A = A || new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return; }
    if (A.state === 'suspended') { A.resume(); }
    if (!noise) { noise = A.createBuffer(1, A.sampleRate * .3, A.sampleRate); var d = noise.getChannelData(0); for (var i = 0; i < d.length; i++) { d[i] = Math.random() * 2 - 1; } }
  }
  addEventListener('pointerdown', wake, true);
  addEventListener('keydown', wake, true);
  if (sb) { sb.addEventListener('click', function () { on = !on; sb.setAttribute('aria-pressed', on); if (!on && tone) { tone.g.gain.setTargetAtTime(0, A.currentTime, .03); } wake(); }); }
  function voice(type, f0, f1, len, gain, pan, at) {   // one tone, falling from f0 to f1, gone in len seconds
    var o = A.createOscillator(), g = A.createGain(), p = A.createStereoPanner ? A.createStereoPanner() : null;
    o.type = type; o.frequency.setValueAtTime(f0, at); o.frequency.exponentialRampToValueAtTime(f1, at + len);
    g.gain.setValueAtTime(0, at); g.gain.linearRampToValueAtTime(gain, at + .005); g.gain.exponentialRampToValueAtTime(.0001, at + len);
    o.connect(g); if (p) { p.pan.value = pan || 0; g.connect(p); p.connect(A.destination); } else { g.connect(A.destination); }
    o.start(at); o.stop(at + len + .02);
  }
  function hiss(freq, q, len, gain, at, to) {          // a short burst of noise through a band (sliding to 'to'): clicks, puffs, whooshes
    var s = A.createBufferSource(), b = A.createBiquadFilter(), g = A.createGain();
    s.buffer = noise; b.type = 'bandpass'; b.frequency.setValueAtTime(freq, at); b.Q.value = q;
    if (to) { b.frequency.exponentialRampToValueAtTime(to, at + len); }
    g.gain.setValueAtTime(0, at); g.gain.linearRampToValueAtTime(gain, at + len * .3); g.gain.exponentialRampToValueAtTime(.0001, at + len);
    s.connect(b); b.connect(g); g.connect(A.destination); s.start(at); s.stop(at + len + .02);
  }
  window.SOUND = function (name, o) {
    if (!on || !A || A.state !== 'running') { return; }
    var at = o.at ? Math.max(o.at, A.currentTime) : A.currentTime + .01, n = o.n || 0, steps = [0, 2, 4, 7, 9], gg = o.g === undefined ? 1 : o.g;   // at: a time on the sound's own clock (SOUND.time), for a beat that keeps time
    if (name === 'tone') {                            // the theremin: one sine, a slow vibrato, gliding where it is told
      if (!tone) {
        tone = { o:A.createOscillator(), v:A.createOscillator(), d:A.createGain(), g:A.createGain() };
        tone.o.type = 'sine'; tone.v.frequency.value = 5.5; tone.d.gain.value = 0; tone.g.gain.value = 0;
        tone.v.connect(tone.d); tone.d.connect(tone.o.frequency); tone.o.connect(tone.g); tone.g.connect(A.destination); tone.o.start(); tone.v.start();
      }
      tone.o.frequency.setTargetAtTime(o.f, at, .03); tone.d.gain.setTargetAtTime(o.f * .007, at, .1); tone.g.gain.setTargetAtTime(o.g || 0, at, .05);
      return;
    }
    if (name === 'ring') { var f = 440 * Math.pow(2, (steps[n % 5] + 12 * Math.min(2, Math.floor(n / 5))) / 12); voice('triangle', f, f * .995, .5, .06, o.pan, at); voice('sine', f * 2, f * 2, .18, .015, o.pan, at); }
    else if (name === 'sign') { var r = 220 * Math.pow(2, steps[n % 5] / 12); voice('triangle', r, r, 1.2, .04, 0, at); voice('triangle', r * 1.5, r * 1.5, 1.2, .028, 0, at + .08); }
    else if (name === 'boost') { hiss(500, 1.2, .45, .06, at, 2400); }
    else if (name === 'pip') { voice('sine', 1200, 1600, .08, .04, o.pan, at); }
    else if (name === 'beep') { voice('square', n > 1 ? 1320 : 880, n > 1 ? 1320 : 880, .07, .02, 0, at); }
    else if (name === 'start') { hiss(200, .8, .9, .08, at, 2400); }
    else if (name === 'kick') { voice('sine', 150, 42, .32, .3 * gg, o.pan, at); hiss(2500, .8, .015, .05 * gg, at); }   // the drums: KNOCK BEAT
    else if (name === 'snare') { hiss(1800, .8, .17, .16 * gg, at); voice('triangle', 200, 165, .09, .07 * gg, o.pan, at); }
    else if (name === 'hat') { hiss(8000, 1.6, .04, .06 * gg, at); }
    else if (name === 'pluck') { voice('triangle', o.f, o.f * .998, .6, .12 * gg, o.pan, at); voice('sawtooth', o.f, o.f, .12, .02 * gg, o.pan, at); }   // the orchestra: CONDUCTOR
    else if (name === 'mallet') { voice('sine', o.f, o.f, .7, .08 * gg, o.pan, at); voice('sine', o.f * 4.01, o.f * 4.01, .1, .02 * gg, o.pan, at); }
    else if (name === 'bell') { voice('sine', o.f, o.f, 1.8, .045 * gg, o.pan, at); voice('sine', o.f * 2.76, o.f * 2.76, .9, .018 * gg, o.pan, at); }
  };
  window.SOUND.time = function () { return A && A.state === 'running' ? A.currentTime : null; };   // the sound's own clock
  window.SOUND.ctx = function () { return on && A && A.state === 'running' ? A : null; };   // for an instrument with a voice of its own (the turntable)
  window.SOUND.isOn = function () { return on; };

  window.ASK_TILT = function () {                     // xp.js's TRY: a phone's motion, asked in that tap (iOS asks only then); refused, a finger plays
    if (granted || pending || !window.DeviceOrientationEvent || !matchMedia('(pointer: coarse)').matches) { return; }
    pending = true;
    var ios = typeof DeviceOrientationEvent.requestPermission === 'function', d = Math.PI / 180;
    (ios ? DeviceOrientationEvent.requestPermission() : Promise.resolve('granted')).then(function (s) {
      pending = false;
      if (s !== 'granted' || granted) { return; }
      granted = true;
      addEventListener('deviceorientation', function (e) { if (e.beta != null) { T.dev = [e.beta, e.gamma, e.alpha]; T.at = performance.now(); T.tilt = true; } });   // tilt: it really comes
      addEventListener('devicemotion', function (e) {   // in G and rad/s, as the app sends them; iOS gives gravity the other way round
        var a = e.accelerationIncludingGravity, r = e.rotationRate, k = (ios ? 1 : -1) / 9.81;
        if (a && a.x != null) { T.acc = [a.x * k, a.y * k, a.z * k]; }
        if (r && r.alpha != null) { T.rot = [r.beta * d, r.gamma * d, r.alpha * d]; }
      });
    }, function () { pending = false; });
  };
})();
