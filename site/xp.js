// SENSORLOVE EXPERIENCE: the window under sensor.love's hero, and SensorLove's first mini games (the app gets them later, as its
// Experience window). It opens on its name and TRY alone, and TRY asks for the phone's motion (iOS asks only inside a tap). Then
// the cards come to the middle, under the card reader: one dragged in, the screen finds SensorLove the way a destination does, and
// it plays. The cards go down to a row along the bottom (a finger across scrolls it, a card pulled up comes out), and another one
// dragged in loads. A card going in asks again for its own sensor if it was not given: motion through site.js ASK_TILT, the
// microphone through AURORA. Each card is a sensor and what
// people make with it; nothing to lose in any of them (for now the page plays only PAPER PLANE; the others wait here for their fixes):
//   PAPER PLANE  ATTITUDE steers the app's paper plane through rings (a click: ACCELEROMETER, a boost).
//   TURNTABLE    GYROSCOPE: turn the phone (or the record) and its own sound follows, faster, slower, backwards: a scratch.
//   KNOCK BEAT   USER ACCELERATION: knock the phone and the hit goes into a looping beat; which way it moved picks the drum.
//   THEREMIN     TOUCH as an XY pad: across is the pitch, up is louder.
//   AURORA       MICROPHONE (asked on a tap): your voice draws the northern lights; a clap, a shooting star; a long note, a crown.
//   HUNGRY FROG  FACE TRACKING doing something else: the head aims the app's frog, the open mouth shoots its tongue at flies.
//   CONDUCTOR    HAND TRACKING: conduct the frogs' orchestra; each stroke down a beat, higher is louder, sideways picks who leads.
// Instruments more than games, as Electroplankton, Bloom and Blob Opera are: something to play, nothing to win.
// While it plays, what the app does and what it is good for comes by, line after line; the console shows the sensor's OSC live.
// The tilt, a finger or the mouse stands in for what a page cannot read (a face, a hand). Nothing is kept or sent.
(function () {
  var cv = document.querySelector('canvas.xp');
  if (!cv) { return; }
  var APP = '{{app}}';                                  // the app's frog and its blink (WebUI/home.html), how many sensors and addresses it has: written in by site/build.py
  var ctx = cv.getContext('2d'), hero = cv.parentNode, box = cv.closest('section'), pre = box.querySelector('.osc pre'), REDUCED = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var carts = [].slice.call(box.querySelectorAll('.cart')), coarse = matchMedia('(pointer: coarse)').matches, loading = null, door = box.querySelector('.start');
  var W, H, CX, CY, F, D, SC = 1, narrow, INK, LIT, MID, DIM, RED, t = 0, last = 0, said = 0, tapSeen = 0, keysAt = -1e9, held = {}, seen = true, heard = 0, mode = null;
  var cam = { x:0, y:0, roll:0 }, stars = [], streaks = [], lines = null, line = -1, lineAt = 0, SAY = [['LOOKING FOR A DESTINATION', 0], ['FOUND: THIS SCREEN', 1.3], ['CONNECTED · UDP 9000', 2.1]], ON = 3.2;
  var FREE = ['FREE.', 'NO ADS. NO ACCOUNTS. NOTHING LOCKED. FOR IPHONE, ON THE APP STORE'];
  for (var i = 0; i < 300; i++) { stars.push({ x:(Math.random() * 2 - 1) * 9, y:(Math.random() * 2 - 1) * 6, z:.5 + Math.random() * 40 }); }

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function sound(name, o) { if (window.SOUND) { window.SOUND(name, o || {}); } }
  function size() {
    var dpr = devicePixelRatio || 1, cs = getComputedStyle(hero), tok = function (k) { return cs.getPropertyValue(k).trim(); };
    INK = tok('--fg'); LIT = tok('--lit'); MID = tok('--mid'); DIM = tok('--dim'); RED = tok('--accent');
    W = cv.clientWidth; H = cv.clientHeight; narrow = W < 760; D = narrow ? 3 : 4; SC = narrow ? 1 : clamp(H / 640, 1, 1.5);   // SC: the side views grow with a tall screen
    CX = W / 2; CY = H * (narrow ? .5 : .46); F = Math.min(W, H) * (narrow ? .95 : .8);
    cv.width = W * dpr; cv.height = H * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  function proj(x, y, z) {                              // world → screen: the camera follows the plane a little and leans with it
    var X = (x - cam.x) / z * F, Y = -(y - cam.y) / z * F, c = Math.cos(cam.roll), s = Math.sin(cam.roll);
    return [CX + X * c - Y * s, CY + X * s + Y * c];
  }
  function paint(list, color, k) {                      // x, y, size triplets as the app's round dots
    ctx.fillStyle = color; ctx.beginPath();
    for (var i = 0; i < list.length; i += 3) { var r = list[i + 2] * k; ctx.moveTo(list[i] + r, list[i + 1]); ctx.arc(list[i], list[i + 1], r, 0, 6.2832); }
    ctx.fill();
  }
  function ring(out, x, y, r, gap, size, phase) {       // a dotted circle, a dot every gap px
    var n = Math.max(8, Math.round(r * 6.2832 / gap));
    for (var i = 0; i < n; i++) { var a = phase + i / n * 6.2832; out.push(x + Math.cos(a) * r, y + Math.sin(a) * r, size); }
  }
  function text(s, x, y, size, color, align) {
    ctx.font = size + 'px "Departure Mono", monospace'; ctx.fillStyle = color; ctx.textAlign = align || 'left'; ctx.textBaseline = 'top'; ctx.fillText(s, x, y);
  }
  function glyphs(s) {                                  // a line in Departure Mono's own pixels (at 11 px one is one), as [x, y] from its middle
    var c = document.createElement('canvas'), q = c.getContext('2d'), w, out = [];
    q.font = '11px "Departure Mono", monospace'; w = Math.ceil(q.measureText(s).width); c.width = w; c.height = 11;
    q.font = '11px "Departure Mono", monospace'; q.textBaseline = 'top'; q.fillStyle = '#fff'; q.fillText(s, 0, 0);
    var a = q.getImageData(0, 0, w, 11).data;
    for (var y = 0; y < 11; y++) { for (var x = 0; x < w; x++) { if (a[(y * w + x) * 4 + 3] > 127) { out.push([x - w / 2, y - 5.5]); } } }
    return out;
  }
  function input(now, point) {                          // what steers now: a phone that said yes, keys, a pointer over the hero, or no one (point: a game a finger plays even with the tilt on)
    var T = window.TILT, r = cv.getBoundingClientRect();
    if (!point && T && T.dev && now - T.at < 1000) { return { kind:'tilt', beta:T.dev[0], gamma:T.dev[1], acc:T.acc, rot:T.rot }; }
    if (now - keysAt < 3000) { return { kind:'keys', x:(held.ArrowRight ? 1 : 0) - (held.ArrowLeft ? 1 : 0), y:(held.ArrowUp ? 1 : 0) - (held.ArrowDown ? 1 : 0) }; }
    if (T && T.px && now - T.at < 5000 && T.py >= r.top && T.py <= r.bottom) { return { kind:'point', x:T.px - r.left, y:T.py - r.top, down:T.down && (T.tapOn === cv || T.tapOn === zone) }; }
    return null;
  }
  function tapped() {                                   // a click or tap on the play area since the last frame (site.js keeps it): where
    var T = window.TILT, r = cv.getBoundingClientRect();
    if (T && T.tap && T.tap !== tapSeen) { tapSeen = T.tap; if (T.tapOn === cv || T.tapOn === zone) { return [T.px - r.left, T.py - r.top]; } }
    return null;
  }
  function tell(rows) {                                 // the site's console: address, value
    if (!pre) { return; }
    var pad = Math.max.apply(null, rows.map(function (r) { return r[0].length; })) + 2;
    var s = rows.map(function (r) { var v = r[1], n = typeof v === 'number' ? (v < 0 ? '-' : '+') + Math.abs(v).toFixed(3) : v; return (r[0] + '                              ').slice(0, pad) + ('          ' + n).slice(-8); }).join('\n');
    if (pre.textContent !== s) { pre.textContent = s; }
  }
  function inTri(x, y, A, B, C) {
    var s = function (a, b) { return (x - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (y - b[1]); }, d1 = s(A, B), d2 = s(B, C), d3 = s(C, A);
    return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
  }

  // ---------- the frog (paintMark's rules in home.html): outline, mouth, eye rings, a pupil each looking at a point ----------
  function frogCells(look, shut) {                      // lit cells [x, y] on the mark's 27 x 16 (rows 6-14), look in cells
    var L = APP.logo, out = [], pupil = {}, x, y;
    var body = function (x, y) { return y >= 7 && y < 15 && x >= 2 && x < 25 && L[y - 7][x - 2] !== '.'; };
    var eye = function (x, y) { return body(x, y) && /[og]/.test(L[y - 7][x - 2]); };
    var inner = function (x, y) { return eye(x, y) && eye(x - 1, y) && eye(x + 1, y) && eye(x, y - 1) && eye(x, y + 1); };
    [[2, 13], [13, 25]].forEach(function (e) {
      var best = '', bd = 1e9;
      for (y = 7; y < 15; y++) { for (x = e[0]; x < e[1]; x++) { if (inner(x, y)) { var dd = Math.hypot(x + .5 - look[0], y + .5 - look[1]); if (dd < bd) { bd = dd; best = x + ',' + y; } } } }
      pupil[best] = 1;
    });
    for (y = 6; y < 15; y++) {
      for (x = 0; x < 27; x++) {
        if (!body(x, y) ? body(x - 1, y) || body(x + 1, y) || body(x, y - 1) || body(x, y + 1) : L[y - 7][x - 2] === 'm' || (!shut && eye(x, y) && (!inner(x, y) || pupil[x + ',' + y]))) { out.push([x, y]); }
      }
    }
    if (shut) { APP.arc.forEach(function (p) { out.push([2 + p[0], 7 + p[1]]); }); }   // asleep, or a blink: two arcs
    return out;
  }
  function logo(look, shut) {                           // on top, small, at the door, while the screen finds SensorLove and a card loads: an astronaut, helmet glass, its glint, the aerial sending
    if (narrow) { return; }
    var c = 3, ox = Math.round(CX - 13.5 * c), oy = 70, out = [], dim = [], hx = CX, hy = oy + 10 * c, R = 15 * c, a;
    frogCells([(look[0] - ox) / c, (look[1] - oy) / c], shut).forEach(function (p) { out.push(ox + (p[0] + .5) * c, oy + (p[1] + .5) * c, c); });
    for (a = -3.4; a < .25; a += .11) { dim.push(hx + Math.cos(a) * R, hy + Math.sin(a) * R, c); }
    for (a = 3.55; a < 4.35; a += .08) { out.push(hx + Math.cos(a) * (R - 2 * c), hy + Math.sin(a) * (R - 2 * c), c * .9); }
    for (a = .55; a < 2.6; a += .1) { dim.push(hx + Math.cos(a) * R * .95, hy + R * .25 + Math.sin(a) * R * .55, c); }
    for (var k = 1; k < 5; k++) { dim.push(hx + R * .55 + k * c * 1.2, hy - R * .82 - k * c * 1.4, c * .8); }
    paint(dim, MID, .31); paint(out, LIT, .31);
    if (Math.floor(t * 2) % 2) { paint([hx + R * .55 + 5.4 * c, hy - R * .82 - 6.6 * c, c * 1.4], RED, .4); }
  }
  function sky(v, dt) {                                 // the stars, streaming past; now and then a meteor far off
    var near = [], far = [], st = [];
    stars.forEach(function (s) {
      s.z -= v * dt;
      if (s.z < .4) { s.z += 40; s.x = (Math.random() * 2 - 1) * 9; s.y = (Math.random() * 2 - 1) * 6; }
      var p = proj(s.x, s.y, s.z), k = Math.min(3.2, 7.2 / s.z);
      if (p[0] < -20 || p[1] < -20 || p[0] > W + 20 || p[1] > H + 20) { return; }
      (s.z < 12 ? near : far).push(p[0], p[1], Math.max(1, k));
      if (v > 4 && s.z < 6) { var q = proj(s.x, s.y, s.z + .5); near.push(q[0], q[1], Math.max(1, k * .7)); }
    });
    if (!REDUCED && Math.random() < dt * .5) { streaks.push({ x:Math.random() * W, y:-10, vx:-120 - Math.random() * 200, vy:240 + Math.random() * 160, life:1.6 }); }
    streaks.forEach(function (q) { q.x += q.vx * dt; q.y += q.vy * dt; q.life -= dt; for (var j = 0; j < 8; j++) { st.push(q.x - q.vx * j * .014, q.y - q.vy * j * .014, 2.6 - j * .28); } });
    streaks = streaks.filter(function (q) { return q.life > 0; });
    paint(far, DIM, .31); paint(near, MID, .31); paint(st, MID, .31);
  }

  // ---------- the scenes on the ground: the frog small, dotted lines and ovals ----------
  function frog(x, y, c, at, shut, color) {             // the app's frog, its middle at x, y (it sits on y + 4.5c), c px a cell, looking at the point at
    var out = [];
    frogCells([13.5 + (at[0] - x) / c * .35, 10.5 + (at[1] - y) / c * .35], shut).forEach(function (p) { out.push(x - 13.5 * c + (p[0] + .5) * c, y - 10.5 * c + (p[1] + .5) * c, c); });
    paint(out, color || LIT, .31);
  }
  function dotted(out, x0, y0, x1, y1, gap, size) {     // a dotted line, a dot every gap px
    var n = Math.max(1, Math.round(Math.hypot(x1 - x0, y1 - y0) / gap));
    for (var i = 0; i <= n; i++) { out.push(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n, size); }
  }
  function oval(out, x, y, rx, ry, gap, size) {         // a dotted ellipse
    var n = Math.max(8, Math.round(3.1416 * (rx + ry) / gap));
    for (var i = 0; i < n; i++) { var a = i / n * 6.2832; out.push(x + Math.cos(a) * rx, y + Math.sin(a) * ry, size); }
  }
  function ground() { return H * (narrow ? .6 : .62); }  // the line the side views stand on

  // ---------- what comes by: the next line about the app, and its sound ----------
  function nextLine() { line = (line + 1) % lines.length; lineAt = t; sound('sign', { n:line }); return words(lines[line]); }
  function words(l) { if (typeof l === 'function') { l = l(); } return l.mouse ? l[window.TILT && window.TILT.tilt ? 'tilt' : coarse ? 'touch' : 'mouse'] : l; }   // a how-to line, in the words of what plays it now
  function caption() {                                  // the one line at the top: how to play, then what the app does; typed, until the next
    if (line < 0) { return; }
    var l = words(lines[line]), y = narrow ? 26 : 44, k = Math.floor((t - lineAt) * 40), n = k - l[0].length;
    ctx.font = '16.5px "Departure Mono", monospace'; var fs = narrow && ctx.measureText(l[0]).width > W - 110 ? 13 : 16.5;   // on a phone a long one shrinks, clear of the speaker
    text(l[0].slice(0, k), CX, y + (16.5 - fs) / 2, fs, l === FREE ? RED : LIT, 'center');
    wrap(l[1], W - 48).forEach(function (s, i) { text(s.slice(0, Math.max(0, n)), CX, y + 28 + i * 16.5, 11, MID, 'center'); n -= s.length + 1; });
  }
  function wrap(s, w) {                                 // words in 11 px, to lines no wider than w
    ctx.font = '11px "Departure Mono", monospace';
    return s.split(' ').reduce(function (out, word) { var l = out[out.length - 1], next = l ? l + ' ' + word : word; if (l && ctx.measureText(next).width > w) { out.push(word); } else { out[out.length - 1] = next; } return out; }, ['']);
  }

  // ---------- 1 PAPER PLANE: ATTITUDE steers, a click (ACCELEROMETER) boosts ----------
  var PLANE = (function () {
    var V = [[0, 13, 0], [0, -11, 0], [-8, -11, 2.9], [8, -11, 2.9], [0, -6, -2.8]], FACES = [[0, 1, 2], [0, 3, 1], [0, 4, 1]], S = .03;   // home.html's PLANE: x span, y nose, z its top
    var Z = 2.4, AX = 1.6, AY = .8, GAP = 6.5, P, rings, bits, signs, speed, idle, count = 0, boost = 0;
    var LINES = [{ tilt:['TILT TO STEER', 'THROUGH THE RINGS. TAP OR KNOCK TO BOOST'], touch:['TOUCH TO STEER', 'THROUGH THE RINGS. TAP TO BOOST'], mouse:['MOVE TO STEER', 'THROUGH THE RINGS. CLICK TO BOOST'] }, ['FLY A CAMERA', 'ATTITUDE: TILT THE PHONE AND THE CAMERA TURNS WITH IT'], [APP.sensors + ' SENSORS', 'MOTION, FACE, HANDS, TOUCH, SOUND, LOCATION, WEATHER, TIME, VIDEO, DEPTH'],
      ['FIRE A CUE', 'ACCELEROMETER: KNOCK THE PHONE TO START A SOUND OR A LIGHT'], [APP.addresses + ' ADDRESSES', 'EVERY VALUE ON ITS OWN OSC ADDRESS: /SENSORLOVE/ACCEL/X'],
      ['LEAN A LIGHT', 'GRAVITY: TILT TO MOVE A LIGHT ON STAGE'], ['120 A SECOND', 'SEND RATE 15, 30, 60 OR 120 TIMES A SECOND'],
      ['MANY PHONES', 'ONE COMPUTER, A PREFIX FOR EACH PHONE'], ['REC TO CSV', 'EVERY RUNNING SENSOR, ONE ROW PER SEND, IN THE FILES APP'], FREE];
    function begin() { lines = LINES; line = -1; P = { x:0, y:-1.6, vx:0, vy:2.2, tx:0, ty:0, roll:0 }; rings = []; bits = []; signs = []; speed = 6.5; idle = 9; count = 0; boost = 0; for (var z = 14; z < 40; z += GAP) { spawn(z); } }
    function spawn(z) { rings.push({ x:(Math.random() * 2 - 1) * AX * .7, y:(Math.random() * 2 - 1) * AY * .65, z:z, r:.66, state:0, spin:Math.random() * 6 }); }
    function ahead() { return rings.filter(function (r) { return !r.state; }).sort(function (a, b) { return a.z - b.z; })[0]; }
    function step(dt, inp, tap) {
      if (inp && inp.kind === 'point') { P.tx = clamp((inp.x - CX) / (W * .36), -1, 1) * AX; P.ty = clamp(-(inp.y - CY) / (H * .3), -1, 1) * AY; }
      else if (inp && inp.kind === 'tilt') {           // the tilt is where it flies, from how the hand held the phone at take-off (slowly following it, as one sits back)
        if (!P.n) { P.n = [inp.beta, inp.gamma]; }
        P.n[0] += (inp.beta - P.n[0]) * dt / 20; P.n[1] += (inp.gamma - P.n[1]) * dt / 20;
        P.tx = clamp((inp.gamma - P.n[1]) / 18, -1, 1) * AX; P.ty = clamp((P.n[0] - inp.beta) / 12, -1, 1) * AY;
        if (inp.acc && Math.abs(Math.hypot(inp.acc[0], inp.acc[1], inp.acc[2]) - 1) > .6) { tap = true; }
      }
      else if (inp && inp.kind === 'keys') { P.tx = clamp(P.tx + inp.x * 2.4 * dt, -AX, AX); P.ty = clamp(P.ty + inp.y * 2 * dt, -AY, AY); }
      if (inp) { idle = 0; } else { idle += dt; }
      if (idle > 4) { var n = ahead(); if (n) { P.tx = n.x * .96; P.ty = n.y * .96; } }   // nobody at the controls: it flies itself
      if (tap) { if (boost <= 0) { sound('boost'); } boost = .7; }   // a knock: the accelerometer
      boost = Math.max(0, boost - dt);
      var ax = (P.tx - P.x) * 30 - P.vx * 10, ay = (P.ty - P.y) * 30 - P.vy * 10;
      P.vx += ax * dt; P.vy += ay * dt; P.x = clamp(P.x + P.vx * dt, -AX, AX); P.y = clamp(P.y + P.vy * dt, -AY - 1, AY);
      P.roll += (-P.vx * .25 - P.roll) * Math.min(1, dt * 10);
      cam.x = P.x * .45; cam.y = P.y * .45; cam.roll = -P.vx * .06;
      speed = REDUCED && idle > 4 ? 0 : 6.5 * (boost > 0 ? 1.8 : 1);
      rings.forEach(function (r) {
        r.z -= speed * dt; r.spin += dt * .5;
        if (!r.state && r.z <= Z) {
          var hit = Math.hypot(P.x - r.x, P.y - r.y) < r.r, p = proj(r.x, r.y, Z);
          r.state = hit ? 1 : 2;
          if (hit) { sound('ring', { n:count % 5, pan:p[0] / W * 2 - 1 }); for (var j = 0; j < 24; j++) { var a = j / 24 * 6.2832; bits.push({ x:p[0] + Math.cos(a) * r.r / Z * F, y:p[1] + Math.sin(a) * r.r / Z * F, vx:Math.cos(a) * 120, vy:Math.sin(a) * 120, life:.5 }); } }
          if (++count % 3 === 0) { var l = nextLine(); signs.push({ dots:glyphs(l[0]), z:24, red:l === FREE }); }   // every third ring, through or not: the next thing the app does
        }
      });
      rings = rings.filter(function (r) { return r.z > .35; });
      var far = rings.reduce(function (m, r) { return Math.max(m, r.z); }, 0);
      if (far < 40 - GAP) { spawn(far + GAP); }
      signs.forEach(function (s) { s.z -= speed * dt; });
      signs = signs.filter(function (s) { return s.z > .6; });
      bits.forEach(function (b) { b.x += b.vx * dt; b.y += b.vy * dt; b.life -= dt; });
      bits = bits.filter(function (b) { return b.life > 0; });
    }
    function draw() {
      signs.forEach(function (s) {                      // the line's words, up ahead in dots, coming; close by they dissolve
        var u = narrow ? .026 : .032, out = [], r = clamp(u / s.z * F * .36, .7, 7);
        s.dots.forEach(function (d) { var p = proj(d[0] * u, AY * .75 - d[1] * u, s.z); out.push(p[0], p[1], r); });
        ctx.globalAlpha = clamp((s.z - 1.4) / 3, 0, 1); paint(out, s.red ? RED : LIT, 1); ctx.globalAlpha = 1;
      });
      var next = ahead(), lit = [], ink = [], mid = [], dim = [];
      rings.slice().sort(function (a, b) { return b.z - a.z; }).forEach(function (r) {
        var p = proj(r.x, r.y, r.z), size = clamp(10 / r.z, 1, 4);
        ring(r === next ? lit : r.state === 2 ? dim : r.z > 20 ? mid : ink, p[0], p[1], r.r / r.z * F, Math.max(5, size * 3.4), size, r.spin);
      });
      paint(dim, DIM, .31); paint(mid, MID, .31); paint(ink, INK, .31); paint(lit, LIT, .31);
      var b = []; bits.forEach(function (q) { b.push(q.x, q.y, 1.5 + q.life * 4); }); paint(b, LIT, .31);
      plane();
    }
    function plane() {                                  // its three folds on the dot grid: the brightest face lit, the next shaded, the last dark; ink round the outside
      var cr = Math.cos(P.roll), sr = Math.sin(P.roll), pi = P.vy * .22 + .1, cp = Math.cos(pi), sp = Math.sin(pi), ya = P.vx * .12, cy = Math.cos(ya), sy = Math.sin(ya);
      var W3 = V.map(function (v) {
        var x = v[0], y = v[1], z = v[2], q;
        q = x * cr - z * sr; z = x * sr + z * cr; x = q;
        q = y * cp - z * sp; z = y * sp + z * cp; y = q;
        q = x * cy - y * sy; y = x * sy + y * cy; x = q;
        return [P.x + x * S, P.y + z * S, Z + y * S];    // its span across, its top up, its nose away
      });
      var S2 = W3.map(function (w) { return proj(w[0], w[1], w[2]); }), L = [-.45, .75, -.5], cells = {}, k;
      var faces = FACES.map(function (f) {
        var a = W3[f[0]], b = W3[f[1]], c = W3[f[2]], u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
        var n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]], l = Math.hypot(n[0], n[1], n[2]) || 1;
        return { f:f, lit:Math.abs(n[0] * L[0] + n[1] * L[1] + n[2] * L[2]) / l, z:(a[2] + b[2] + c[2]) / 3 };
      });
      faces.slice().sort(function (a, b) { return b.lit - a.lit; }).forEach(function (q, r) { q.tone = [1, .5, .25][r]; });
      faces.sort(function (a, b) { return b.z - a.z; }).forEach(function (q) {
        var A = S2[q.f[0]], B = S2[q.f[1]], C = S2[q.f[2]], x0 = Math.floor(Math.min(A[0], B[0], C[0]) / D), x1 = Math.ceil(Math.max(A[0], B[0], C[0]) / D), y0 = Math.floor(Math.min(A[1], B[1], C[1]) / D), y1 = Math.ceil(Math.max(A[1], B[1], C[1]) / D);
        for (var gy = y0; gy <= y1; gy++) { for (var gx = x0; gx <= x1; gx++) { if (inTri((gx + .5) * D, (gy + .5) * D, A, B, C)) { cells[gx + ',' + gy] = q.tone; } } }
      });
      var ink = [];
      for (k in cells) {
        var p = k.split(','), gx = +p[0], gy = +p[1], tone = cells[k], edge = !cells[(gx - 1) + ',' + gy] || !cells[(gx + 1) + ',' + gy] || !cells[gx + ',' + (gy - 1)] || !cells[gx + ',' + (gy + 1)];
        if (edge || tone === 1 || (tone === .5 && (gx + gy) % 2 === 0) || (tone === .25 && gx % 2 === 0 && gy % 2 === 0)) { ink.push((gx + .5) * D, (gy + .5) * D, D); }
      }
      paint(ink, LIT, .36);
    }
    function osc() {
      var p = P.vy * .22 + .1, r = P.roll;
      return [['/sensorlove/attitude/pitch', p], ['/sensorlove/attitude/roll', r], ['/sensorlove/attitude/yaw', P.vx * .12], ['/sensorlove/accel/z', -Math.cos(r) * Math.cos(p) - (boost > .45 ? 1.6 : 0)]];
    }
    function icon(out) { [[[4, 14], [44, 4]], [[4, 14], [44, 24]], [[44, 4], [30, 14]], [[44, 24], [30, 14]], [[4, 14], [30, 14]]].forEach(function (s) { for (var j = 0; j <= 10; j++) { out.push(s[0][0] + (s[1][0] - s[0][0]) * j / 10, s[0][1] + (s[1][1] - s[0][1]) * j / 10); } }); }
    return { needs:'motion', begin:begin, step:step, draw:draw, osc:osc, speed:function () { return speed; }, end:function () {}, icon:icon };
  })();

  // ---------- 2 HUNGRY FROG: FACE TRACKING doing something else than a face: the head aims, the open mouth catches ----------
  var FACE = (function () {
    var look = [0, 0], blink = -9, jaw = 0, smile = 0, idle = 9, every = 0, flies = [], tongue = 0, out = false, held = null, caught = 0, c = 10, FX = 0, FY = 0;
    var LINES = [{ tilt:['TILT TO AIM', 'TAP: IT OPENS ITS MOUTH. CATCH THE FLIES'], touch:['TOUCH TO AIM', 'IT OPENS ITS MOUTH. CATCH THE FLIES'], mouse:['MOVE TO AIM', 'CLICK: IT OPENS ITS MOUTH. CATCH THE FLIES'] }, ['AIM WITH YOUR HEAD', 'FACE TRACKING: HOW YOUR HEAD TURNS, AS NUMBERS'], ['TRIGGER WITH YOUR MOUTH', 'JAW OPEN, FROM 0 TO 1: OPEN WIDE TO FIRE A CUE'],
      ['52 EXPRESSIONS', 'EACH FROM 0 TO 1, EACH ON ITS OWN OSC ADDRESS'], ['PUPPET A CHARACTER', 'YOUR HEAD, YOUR EYES, YOUR MOUTH, ON SOMETHING ELSE'],
      ['IN THE APP', 'YOUR FACE DOES THIS, WITH THE FRONT CAMERA'], FREE];
    function fly() { return { x:W * (.15 + Math.random() * .7), y:H * (.22 + Math.random() * .3), vx:0, vy:0, ph:Math.random() * 6 }; }
    function begin() { lines = LINES; line = -1; every = 6; blink = -9; jaw = 0; idle = 9; tongue = 0; out = false; held = null; caught = 0; flies = [fly(), fly(), fly(), fly(), fly()]; look = [CX, H * .3]; }
    function mouth() { return [FX, FY + 3.5 * c]; }    // where the tongue starts: the mouth, under the eyes
    function step(dt, inp, tap) {
      c = narrow ? 6 : Math.min(11, W / 110); FX = CX; FY = H * (narrow ? .58 : .6);
      var P = inp && inp.kind === 'point' ? [inp.x, inp.y] : inp && inp.kind === 'tilt' ? [CX + inp.gamma / 30 * W / 2, CY + (inp.beta - 40) / 30 * H / 2] : inp && inp.kind === 'keys' ? [look[0] + inp.x * 60, look[1] - inp.y * 60] : null, want;
      if (P) { idle = 0; } else {                       // alone, it watches the nearest fly and goes for it
        idle += dt; var n = flies.slice().sort(function (a, b) { return Math.hypot(a.x - FX, a.y - FY) - Math.hypot(b.x - FX, b.y - FY); })[0]; P = [n.x, n.y];
      }
      look[0] += (P[0] - look[0]) * Math.min(1, dt * 7); look[1] += (P[1] - look[1]) * Math.min(1, dt * 7);
      want = (inp && inp.down) || tap ? 1 : idle > 2 && !out && tongue === 0 && Math.hypot(look[0] - P[0], look[1] - P[1]) < 30 && Math.random() < dt * .6 ? 1 : 0;   // held: the mouth opens
      if (want && !out && tongue === 0) { out = true; sound('boost', {}); }
      jaw += ((out ? 1 : want) - jaw) * Math.min(1, dt * 12);
      var m = mouth(), reach = Math.min(Math.hypot(look[0] - m[0], look[1] - m[1]), H * .8);
      if (out) { tongue += dt * 1600; if (tongue >= reach || held) { out = false; } }   // out to where it looks, or until it has one
      else { tongue = Math.max(0, tongue - dt * 1200); if (tongue === 0 && held) { flies.splice(flies.indexOf(held), 1); held = null; caught++; smile = 1; sound('ring', { n:caught % 5, pan:0 }); } }   // in: swallowed
      var d = Math.hypot(look[0] - m[0], look[1] - m[1]) || 1, tip = [m[0] + (look[0] - m[0]) / d * tongue, m[1] + (look[1] - m[1]) / d * tongue];
      flies.forEach(function (f, i) {
        if (f === held) { f.x = tip[0]; f.y = tip[1]; return; }
        f.ph += dt * 9; f.vx += (Math.random() - .5) * 900 * dt; f.vy += (Math.random() - .5) * 900 * dt; f.vx *= .92; f.vy *= .92;
        f.x = clamp(f.x + f.vx * dt, W * .15, W * .85); f.y = clamp(f.y + f.vy * dt, H * .18, H * .5);   // where the tongue reaches
        if (!held && tongue > 0 && Math.hypot(f.x - tip[0], f.y - tip[1]) < 26) { held = f; out = false; flies[i] = fly(); flies.push(f); }
      });
      if (t - blink > 3 + Math.random() * 5) { blink = t; }
      smile = Math.max(.2, smile - dt * .5);
      if ((every -= dt) <= 0) { every = 6; nextLine(); }
    }
    function draw() {
      var bugs = [], wings = [], m = mouth(), d = Math.hypot(look[0] - m[0], look[1] - m[1]) || 1, tg = [], k;
      flies.forEach(function (f) { var w = Math.sin(f.ph * 3) > 0 ? 6 : 3; bugs.push(f.x, f.y, 6); wings.push(f.x - w, f.y - 4, 4, f.x + w, f.y - 4, 4); });
      for (k = 0; k < tongue; k += 7) { tg.push(m[0] + (look[0] - m[0]) / d * k, m[1] + (look[1] - m[1]) / d * k, 2.4); }
      if (tongue > 0) { tg.push(m[0] + (look[0] - m[0]) / d * tongue, m[1] + (look[1] - m[1]) / d * tongue, 5); }
      paint(wings, MID, .5); paint(bugs, LIT, .5); paint(tg, RED, .5);
      var ox = FX - 13.5 * c, oy = FY - 10.5 * c, lit = [], mouthDots = [], x, shut = t - blink < .15;
      frogCells([13.5 + (look[0] - FX) / c * .35, 10.5 + (look[1] - FY) / c * .35], shut).forEach(function (p) { lit.push(ox + (p[0] + .5) * c, oy + (p[1] + .5) * c, c); });
      var my = oy + 12.5 * c, mw = 2.2 + jaw * 1.2;      // the mouth: open with the jaw, corners up after a catch
      for (x = -mw; x <= mw + .01; x += .55) {
        var cu = (x * x) / (mw * mw);
        mouthDots.push(FX + x * c, my + (1 - cu) * jaw * c * 2 - cu * smile * c * 1.2, c * .9);
        if (jaw > .15) { mouthDots.push(FX + x * c, my - (1 - cu) * jaw * c * .5, c * .9); }
      }
      paint(lit, LIT, .31); paint(mouthDots, LIT, .31);
      if (caught) { text(caught + (caught === 1 ? ' FLY' : ' FLIES'), FX, FY + 6 * c, 11, MID, 'center'); }
    }
    function osc() { var m = mouth(); return [['/sensorlove/face/rotation/y', clamp((look[0] - m[0]) / W, -.5, .5)], ['/sensorlove/face/jawOpen', jaw], ['/sensorlove/face/eyeBlinkLeft', t - blink < .15 ? 1 : 0], ['/sensorlove/face/mouthSmileLeft', smile]]; }
    function icon(out) { frogCells([13.5, 10.5], false).forEach(function (p) { out.push(2 + p[0] * 2.2, (p[1] - 6) * 2.6 + 2); }); }
    return { begin:begin, step:step, draw:draw, osc:osc, end:function () {}, icon:icon };
  })();

  // ---------- 3 THEREMIN: TOUCH as an XY pad ----------
  var THEREMIN = (function () {
    var u = .5, v = 0, g = 0, hand = null, waves = [], phase = 0, beat = 0, every = 0;
    var NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    var LINES = [{ tilt:['TILT TO PLAY', 'SIDEWAYS IS THE PITCH, UPRIGHT IS LOUDER'], touch:['TOUCH TO PLAY', 'ACROSS IS THE PITCH, UP IS LOUDER'], mouse:['MOVE TO PLAY', 'ACROSS IS THE PITCH, UP IS LOUDER'] }, ['PLAY A SYNTH', 'TOUCH: WHERE YOUR FINGER IS, AS AN XY PAD'], ['FIVE FINGERS', 'EACH WITH ITS OWN X, Y AND DOWN'],
      ['BEND A NOTE', 'ATTITUDE: TILT THE PHONE TO GLIDE THE PITCH'], ['SING TO IT', 'MICROPHONE: HOW LOUD IT IS AROUND THE PHONE'], FREE];
    function hz() { return 110 * Math.pow(2, u * 3); } // three octaves, A2 to A5, gliding as a theremin does
    function begin() { lines = LINES; line = -1; every = 6; waves = []; g = 0; }
    function step(dt, inp, tap) {
      var on = false;
      if (inp && inp.kind === 'point') { u = clamp(inp.x / W, 0, 1); v = clamp(1 - inp.y / (H * .82), 0, 1); hand = [inp.x, inp.y]; on = true; }
      else if (inp && inp.kind === 'tilt') { u = clamp(.5 + inp.gamma / 60, 0, 1); v = clamp((inp.beta - 10) / 70, 0, 1); hand = [u * W, (1 - v) * H * .82]; on = true; }
      else if (inp && inp.kind === 'keys') { u = clamp(u + inp.x * .4 * dt, 0, 1); v = clamp(v + inp.y * .6 * dt, 0, 1); hand = [u * W, (1 - v) * H * .82]; on = true; }
      else { hand = null; }
      g += ((on ? v : 0) - g) * Math.min(1, dt * 8);
      sound('tone', { f:hz(), g:seen ? g * .14 : 0 });
      phase += dt * hz() / 40;
      beat += dt * (1 + u * 8);                          // higher, more rings
      if (hand && g > .03 && beat > 1) { beat = 0; waves.push({ x:hand[0], y:hand[1], r:6, a:g }); }
      if (tap) { waves.push({ x:tap[0], y:tap[1], r:6, a:1, big:true }); sound('ring', { n:Math.round(u * 9), pan:tap[0] / W * 2 - 1 }); }
      waves.forEach(function (w) { w.r += dt * (w.big ? 260 : 140); w.a -= dt * (w.big ? .9 : .6); });
      waves = waves.filter(function (w) { return w.a > 0; });
      if ((every -= dt) <= 0) { every = 6; nextLine(); }
    }
    function draw() {
      var dots = [], dim = [], lit = [], x, y = CY + H * .04, amp = g * H * .16, lam = W / (2 + u * 14);   // the sound itself, across the screen
      for (x = 0; x <= W; x += 6) { dots.push(x, y + Math.sin((x / lam) * 6.2832 - phase) * amp, g > .02 ? 2.2 : 1.4); }
      waves.forEach(function (w) { ring(w.a > .5 ? lit : dim, w.x, w.y, w.r, 9, 1.4 + w.a * 2.4, 0); });
      paint(dim, DIM, .31); paint(dots, g > .02 ? LIT : MID, .31); paint(lit, LIT, .31);
      if (hand) {
        var f = hz(), n = Math.round(12 * Math.log2(f / 440)) + 57, hl = [];
        ring(hl, hand[0], hand[1], 10, 6, 2, phase); paint(hl, LIT, .31);
        text(NOTES[(n % 12 + 12) % 12] + Math.floor(n / 12) + '  ' + Math.round(f) + ' HZ', hand[0] + 18, hand[1] - 22, 11, LIT);
        text('VOLUME ' + Math.round(g * 100), hand[0] + 18, hand[1] - 8, 11, MID);
      }
    }
    function osc() { return [['/sensorlove/touch/count', hand ? 1 : 0], ['/sensorlove/touch/1/x', u], ['/sensorlove/touch/1/y', 1 - v], ['/sensorlove/touch/1/down', hand ? 1 : 0]]; }
    function icon(out, w, h) { for (var x = 0; x <= w; x += 4) { out.push(x, h / 2 + Math.sin(x / w * 6.2832 * 2) * h * .35); } }
    return { needs:'motion', begin:begin, step:step, draw:draw, osc:osc, end:function () { sound('tone', { f:hz(), g:0 }); }, zone:function () { return [0, H * .14, W, H * .86 - 130]; }, icon:icon };
  })();

  // ---------- 4 TURNTABLE: GYROSCOPE, how fast the phone turns: turn it like a record and the record's own sound follows, backwards too ----------
  var TURN = (function () {
    var ang = 0, rate = 1, want = 1, spin = 0, lastA = null, idle = 9, every = 0, auto = 0, loop = null, peaks = null, pos = 0, node = null, out = null, making = false;
    var LINES = [{ tilt:['TURN THE PHONE LIKE A RECORD', 'BACK AND FORTH TO SCRATCH. HELD STILL, IT PLAYS ON'], touch:['HOLD THE RECORD AND TURN IT', 'BACK AND FORTH TO SCRATCH. LET GO, IT PLAYS ON'], mouse:['GRAB THE RECORD AND TURN IT', 'BACK AND FORTH TO SCRATCH. LET GO, IT PLAYS ON'] },
      ['SCRATCH WITH A PHONE', 'GYROSCOPE: HOW FAST IT TURNS, AND THE SOUND FOLLOWS'], ['SPIN A KNOB', 'THE SPEED OF A TURN, AS A VALUE IN YOUR HAND'],
      ['SCRUB A CLIP', 'TURN BACK AND FORTH THROUGH A VIDEO'], ['STEER A WHEEL', 'HOLD THE PHONE LIKE A STEERING WHEEL'], FREE];
    function make(A) {                                  // the record itself, made here once: two bars at 96 BPM (kick, snare, hats, a bass, an "ah"), rendered offline
      var OAC = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      if (!OAC) { return; }
      making = true;
      var sr = A.sampleRate, st = 60 / 96 / 4, O = new OAC(1, Math.round(sr * st * 32), sr), nb = O.createBuffer(1, sr, sr), nd = nb.getChannelData(0), i;
      for (i = 0; i < nd.length; i++) { nd[i] = Math.random() * 2 - 1; }
      function env(g, t0, d) { var e = O.createGain(); e.gain.setValueAtTime(0, t0); e.gain.linearRampToValueAtTime(g, t0 + .004); e.gain.exponentialRampToValueAtTime(.0001, t0 + d); e.connect(O.destination); return e; }
      function tone(type, f0, f1, t0, d, g, lp) { var o = O.createOscillator(), e = env(g, t0, d); o.type = type; o.frequency.setValueAtTime(f0, t0); o.frequency.exponentialRampToValueAtTime(f1, t0 + d); if (lp) { var b = O.createBiquadFilter(); b.type = 'lowpass'; b.frequency.value = lp; o.connect(b); b.connect(e); } else { o.connect(e); } o.start(t0); o.stop(t0 + d + .02); }
      function noise(f, q, t0, d, g) { var s = O.createBufferSource(), b = O.createBiquadFilter(); s.buffer = nb; b.type = 'bandpass'; b.frequency.value = f; b.Q.value = q; s.connect(b); b.connect(env(g, t0, d)); s.start(t0); s.stop(t0 + d + .02); }
      function ah(f, t0, d, g) { [[800, 1], [1150, .55], [2900, .2]].forEach(function (fm) { var o = O.createOscillator(), b = O.createBiquadFilter(); o.type = 'sawtooth'; o.frequency.setValueAtTime(f, t0); o.frequency.linearRampToValueAtTime(f * .96, t0 + d); b.type = 'bandpass'; b.frequency.value = fm[0]; b.Q.value = 9; o.connect(b); b.connect(env(g * fm[1], t0, d)); o.start(t0); o.stop(t0 + d + .02); }); }
      var bass = [55, 55, 65.41, 49];
      for (i = 0; i < 32; i++) {
        var t0 = i * st, bt = bass[(i >> 3) % 4];
        if ([0, 6, 10, 16, 22, 26, 29].indexOf(i) >= 0) { tone('sine', 150, 42, t0, .32, .9); }
        if (i % 8 === 4) { noise(1800, .7, t0, .2, .9); tone('triangle', 210, 175, t0, .1, .3); }
        if (i % 2 === 0) { noise(8500, 1.5, t0, i % 4 === 2 ? .1 : .04, .35); }
        if (i % 4 === 0) { tone('sawtooth', bt, bt * .99, t0, st * 3.6, .28, 380); }
      }
      ah(220, 0, .55, .6); ah(262, 10 * st, .4, .55); ah(196, 16 * st, .55, .6); ah(247, 26 * st, .4, .55);
      var done = false, fin = function (b) {
        if (done || !b) { return; }
        done = true; var d = b.getChannelData(0), mx = 0, k, j;
        for (k = 0; k < d.length; k++) { mx = Math.max(mx, Math.abs(d[k])); }
        for (k = 0; k < d.length; k++) { d[k] *= .9 / (mx || 1); }
        peaks = []; var n = 120, m = Math.floor(d.length / n);
        for (k = 0; k < n; k++) { var p = 0; for (j = k * m; j < (k + 1) * m; j += 24) { p = Math.max(p, Math.abs(d[j])); } peaks.push(p / .9); }
        loop = b;
      };
      O.oncomplete = function (e) { fin(e.renderedBuffer); };
      var pr = O.startRendering(); if (pr && pr.then) { pr.then(fin, function () {}); }
    }
    function plug() {                                   // the record on the deck: played at the platter's own speed, backwards too
      var A = window.SOUND && window.SOUND.ctx && window.SOUND.ctx();
      if (!A || node) { return; }
      if (!loop) { if (!making) { make(A); } return; }
      out = A.createGain(); out.gain.value = 0; out.connect(A.destination);
      node = A.createScriptProcessor(1024, 1, 1);
      var d = loop.getChannelData(0), n = d.length, r = 1, z = A.createGain(), o = A.createOscillator();
      z.gain.value = 0; o.connect(z); z.connect(node); o.start(); node.silent = o;   // Safari runs a processor only with something going in
      node.onaudioprocess = function (e) {
        var b = e.outputBuffer.getChannelData(0);
        for (var i = 0; i < b.length; i++) {
          r += (rate - r) * .002;                        // the platter has weight
          pos += r; if (pos >= n) { pos -= n; } else if (pos < 0) { pos += n; }
          var i0 = pos | 0, f = pos - i0; b[i] = d[i0] * (1 - f) + d[i0 + 1 < n ? i0 + 1 : 0] * f;
        }
      };
      node.connect(out);
    }
    function mute() { if (out) { out.gain.setTargetAtTime(0, out.context.currentTime, .03); } }
    function geo() { var R = narrow ? W * .3 : Math.min(W, H) * .25; return { R:R, cx:CX - (narrow ? 0 : R * .12), cy:H * (narrow ? .5 : .53) }; }
    function begin() { lines = LINES; line = -1; every = 6; rate = want = 1; lastA = null; idle = 9; auto = 0; }
    function step(dt, inp) {
      var g = geo(), T = window.TILT, z = T && T.tilt && T.rot ? T.rot[2] : 0, target = 1;
      if (!node) { plug(); }
      if (inp && inp.kind === 'point' && inp.down && (lastA !== null || Math.hypot(inp.x - g.cx, inp.y - g.cy) < g.R * 1.1)) {   // a hand on the record: it turns as the hand does; held still, it stops
        var a = Math.atan2(inp.y - g.cy, inp.x - g.cx);
        target = lastA === null ? 0 : Math.atan2(Math.sin(a - lastA), Math.cos(a - lastA)) / Math.max(dt, .001) / 3.5;
        lastA = a; idle = 0; auto = 0; spin = target * 3.5;
      } else {
        lastA = null;
        if (Math.abs(z) > .15) { target = 1 + z / 3.5; idle = 0; auto = 0; spin = z; }   // the phone itself turning: faster, slower, backwards
        else { spin = 0; if (inp) { idle = 0; } else { idle += dt; } }
        if (inp && inp.kind === 'keys' && inp.x) { target = 1 + inp.x * 1.6; }
      }
      if (idle > 4) { auto += dt; var ph = auto % 5; if (ph < 1.6) { target = Math.sin(ph / 1.6 * 6.2832 * 2) * 2.4; spin = target * 3.5; } }   // alone: a scratch now and then
      want += (clamp(target, -3, 3) - want) * Math.min(1, dt * 18);
      rate = want; ang += rate * 3.5 * dt;
      if (out) { out.gain.setTargetAtTime(window.SOUND.isOn() && seen ? .35 : 0, out.context.currentTime, .04); }
      if ((every -= dt) <= 0) { every = 6; nextLine(); }
    }
    function draw() {
      var g = geo(), R = g.R, cx = g.cx, cy = g.cy, dim = [], mid = [], lit = [], k, j, a, x;
      plinth(dim, cx - R * 1.22, cy - R * 1.18, cx + R * (narrow ? 1.22 : 1.62), cy + R * 1.18, R * .16);
      for (k = 0; k < 12; k++) {                        // the grooves: each its own start, so the turn shows; the light on the vinyl stays where it is
        var rr = R * (.4 + k * .05), n = Math.max(12, Math.round(rr * 6.2832 / 8));
        for (j = 0; j < n; j++) {
          a = ang + j / n * 6.2832 + k * .37;
          var s = ((a % 6.2832) + 6.2832) % 6.2832, sheen = Math.cos(s - 5.5) > .94 || Math.cos(s - 2.36) > .97;
          (sheen ? lit : k % 3 ? dim : mid).push(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr, sheen ? 3.2 : 2.4);
        }
      }
      ring(lit, cx, cy, R, 6, 3.4, ang);                // its rim
      ring(mid, cx, cy, R * .34, 5, 2.6, -ang);         // the label, and the app's frog on it, turning with it
      var c = R * .5 / 27, cs = Math.cos(ang), sn = Math.sin(ang);
      frogCells([13.5, 10.5], false).forEach(function (p) { var u = (p[0] + .5 - 13.5) * c, v = (p[1] + .5 - 10.5) * c; lit.push(cx + u * cs - v * sn, cy + u * sn + v * cs, c * 1.5); });
      var px = cx + R * 1.18, py = cy - R * .95, ex = cx + R * 1.14, ey = cy + R * .2, a2 = -.35 + Math.sin(t * .3) * .02, nx = cx + Math.cos(a2) * R * .78, ny = cy + Math.sin(a2) * R * .78;   // the tonearm, its needle in a groove
      if (!narrow) { ring(mid, px, py, R * .1, 5, 3, 0); lit.push(px, py, 6); dotted(lit, px, py, ex, ey, 6, 3.4); dotted(lit, ex, ey, nx, ny, 6, 3.4); dotted(lit, nx - 6, ny - 9, nx + 6, ny + 9, 4, 3.6); }
      if (peaks) {                                       // the record's sound, and where the needle is in it
        var sw = Math.min(W - 48, 720), sx = CX - sw / 2, sy = narrow ? 112 : 126, ph = loop ? pos / loop.length : 0;
        for (k = 0; k < peaks.length; k++) { x = sx + k / (peaks.length - 1) * sw; var hh = 2 + peaks[k] * (narrow ? 12 : 20); for (j = -hh; j <= hh; j += 4) { (k / peaks.length < ph ? mid : dim).push(x, sy + j, 2.4); } }
        dotted(lit, sx + ph * sw, sy - 26, sx + ph * sw, sy + 26, 4, 3);
      }
      paint(dim, DIM, .5); paint(mid, MID, .5); paint(lit, LIT, .5);
      paint([cx, cy, 5], RED, .5);
      text(Math.round(rate * 33) + ' RPM', narrow ? cx : cx + R * 1.14, narrow ? cy + R * 1.18 + 14 : cy + R * .2 + 22, 11, rate < 0 ? LIT : MID, 'center');   // by the arm
    }
    function osc() { return [['/sensorlove/gyro/x', 0], ['/sensorlove/gyro/y', 0], ['/sensorlove/gyro/z', spin]]; }
    function end() { if (node) { node.onaudioprocess = null; node.disconnect(); node.silent.stop(); } if (out) { out.disconnect(); } node = out = null; }
    function zone() { var g = geo(), r = g.R * 1.12; return [g.cx - r, g.cy - r, r * 2, r * 2]; }   // a finger on the record turns it; beside it the page still scrolls
    function icon(out) { var a, r; for (r = 4; r <= 12; r += 4) { for (a = 0; a < 6.28; a += 2.4 / r) { out.push(16 + Math.cos(a) * r, 14 + Math.sin(a) * r); } } out.push(16, 14); for (a = 0; a <= 1; a += .2) { out.push(38 - a * 8, 2 + a * 12); } }   // a record and its arm
    return { needs:'motion', point:true, begin:begin, step:step, draw:draw, osc:osc, end:end, away:mute, zone:zone, icon:icon };
  })();
  function plinth(out, x0, y0, x1, y1, r) {             // a dotted box, its corners round
    var gap = 7, size = 2.4, a;
    dotted(out, x0 + r, y0, x1 - r, y0, gap, size); dotted(out, x0 + r, y1, x1 - r, y1, gap, size);
    dotted(out, x0, y0 + r, x0, y1 - r, gap, size); dotted(out, x1, y0 + r, x1, y1 - r, gap, size);
    [[x0 + r, y0 + r, 3.1416], [x1 - r, y0 + r, 4.7124], [x1 - r, y1 - r, 0], [x0 + r, y1 - r, 1.5708]].forEach(function (q) { for (a = .3; a < 1.45; a += .4) { out.push(q[0] + Math.cos(q[2] + a) * r, q[1] + Math.sin(q[2] + a) * r, size); } });
  }

  // ---------- 5 KNOCK BEAT: USER ACCELERATION, the phone's own jolts with gravity taken out: knock it, and the hit goes into a looping beat ----------
  var BEAT = (function () {
    var VO = ['hat', 'snare', 'kick'], NAMES = ['HAT', 'SNARE', 'KICK'], SD = 60 / 100 / 4, grid = [[], [], []], t0 = null, src = '', next = 0, shown = -1, queue = [], grav = null, jolt = [0, 0, 0];
    var cool = 0, idle = 9, every = 0, hits = [], squash = 0, preset = 0, bars = 0, autoT = 0, blink = -9, wiped = -9;
    var PRESETS = [[[0, 2, 4, 6, 8, 10, 12, 14], [4, 12], [0, 8, 11]], [[2, 6, 10, 14], [4, 12, 15], [0, 3, 8, 10]], [[0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14], [4, 12], [0, 7, 8]]];
    var LINES = [{ tilt:['KNOCK THE PHONE', 'ON ITS BACK A KICK, ON ITS SIDE A SNARE, ON ITS TOP A HAT'], touch:['TAP A STEP, OR TAP HIGH OR LOW', 'HIGH A HAT, LOW A KICK: IT GOES INTO THE LOOP'], mouse:['CLICK A STEP, OR CLICK HIGH OR LOW', 'HIGH A HAT, LOW A KICK: IT GOES INTO THE LOOP'] },
      ['A DRUM IN YOUR HAND', 'USER ACCELERATION: A KNOCK IS A SPIKE, GRAVITY TAKEN OUT'], ['WHICH WAY IT MOVED', 'X, Y AND Z: A TAP ON THE SIDE IS NOT A KNOCK ON THE BACK'],
      ['FIRE A CUE', 'KNOCK THE PHONE: A LIGHT, A CLIP, A SCENE'], ['SHAKE TO CLEAR', 'A BIG SHAKE IS A BIG NUMBER'], FREE];
    function now() { var c = window.SOUND && window.SOUND.time && window.SOUND.time(); return typeof c === 'number' ? [c, 'a'] : [performance.now() / 1000, 'p']; }
    function empty() { return [0, 1, 2].map(function () { var r = []; for (var i = 0; i < 16; i++) { r.push(0); } return r; }); }
    function begin() { lines = LINES; line = -1; every = 6; grid = empty(); t0 = null; next = 0; shown = -1; queue = []; grav = null; jolt = [0, 0, 0]; idle = 9; hits = []; squash = 0; bars = 0; autoT = 0; }
    function geo() { var cw = narrow ? Math.min(21, (W - 36) / 16) : 36 * Math.min(SC, 1.25), ch = narrow ? 36 : 46 * Math.min(SC, 1.25); return { cw:cw, ch:ch, x0:CX - 8 * cw, y0:H * (narrow ? .44 : .47) }; }
    function knock(r, m) {                              // a hit: heard now, and into the step it fell on
      var n = now()[0], s = t0 === null ? 0 : ((Math.round((n - t0) / SD) % 16) + 16) % 16;
      grid[r][s] = 1; sound(VO[r], {}); cool = .1; idle = 0; if (r === 2) { squash = 1; } hits.push({ r:r, s:s, t0:t });
      jolt = r === 2 ? [0, 0, -m] : r === 1 ? [m, 0, 0] : [0, m, 0];
    }
    function clear() { grid = empty(); wiped = t; sound('boost', {}); }
    function step(dt, inp, tap) {
      var g = geo(), c = now(), n = c[0], k, r;
      if (c[1] !== src) { src = c[1]; t0 = null; queue = []; }   // the sound came on (or went): its own clock from here
      if (t0 === null) { t0 = n + .08; next = 0; }
      while (t0 + next * SD < n + (src === 'a' ? .12 : 0)) {   // the next steps, on the sound's own clock so the beat keeps time
        var s16 = next % 16, at = t0 + next * SD;
        if (src === 'a') { for (r = 0; r < 3; r++) { if (grid[r][s16]) { sound(VO[r], { at:at, g:r === 0 && s16 % 4 ? .7 : 1 }); } } }
        queue.push({ s:s16, at:at }); next++;
        if (s16 === 15) { bars++; }
      }
      while (queue.length && queue[0].at <= n) { var q = queue.shift(); shown = q.s; for (k = 0; k < 3; k++) { if (grid[k][q.s]) { hits.push({ r:k, s:q.s, t0:t }); if (k === 2) { squash = 1; } if (k === 0) { blink = t; } } } }
      if (inp && inp.kind === 'tilt' && inp.acc) {      // the phone knocked: what is left once gravity is taken out, and which way
        if (!grav) { grav = inp.acc.slice(); }
        for (k = 0; k < 3; k++) { grav[k] += (inp.acc[k] - grav[k]) * Math.min(1, dt * 3); jolt[k] = inp.acc[k] - grav[k]; }
        var m = Math.hypot(jolt[0], jolt[1], jolt[2]), ax = jolt.map(Math.abs);
        if (m > 2.2 && t - wiped > 1.5) { clear(); }
        else if (m > .55 && cool <= 0) { knock(ax[2] >= ax[0] && ax[2] >= ax[1] ? 2 : ax[0] >= ax[1] ? 1 : 0, m); }
      }
      if (tap) {
        var cc = Math.floor((tap[0] - g.x0) / g.cw), rr = Math.floor((tap[1] - g.y0) / g.ch);
        if (cc >= 0 && cc < 16 && rr >= 0 && rr < 3) { grid[rr][cc] = grid[rr][cc] ? 0 : 1; if (grid[rr][cc]) { sound(VO[rr], {}); hits.push({ r:rr, s:cc, t0:t }); } idle = 0; }   // a step, on or off
        else { knock(tap[1] < g.y0 + g.ch ? 0 : tap[1] < g.y0 + g.ch * 2 ? 1 : 2, 1); }   // anywhere else: a knock; high a hat, low a kick
      }
      if (inp) { idle = 0; } else { idle += dt; }
      if (idle > 5) {                                   // alone: the frog knocks a beat in, a row a bar; after a while, another one
        autoT += dt;
        if (autoT > SD * 16) {
          autoT = 0;
          var P = PRESETS[preset], row = [0, 1, 2].filter(function (q) { return P[q].some(function (s) { return !grid[q][s]; }); })[0];
          if (row !== undefined) { P[row].forEach(function (s) { grid[row][s] = 1; }); bars = 0; }
          else if (bars > 6) { clear(); preset = (preset + 1) % PRESETS.length; bars = 0; }
        }
      } else { autoT = 0; }
      cool -= dt; squash = Math.max(0, squash - dt * 6); jolt = jolt.map(function (v) { return v * Math.pow(.01, dt); });
      hits = hits.filter(function (h) { return t - h.t0 < .6; });
      if ((every -= dt) <= 0) { every = 6; nextLine(); }
    }
    function draw() {
      var g = geo(), dim = [], mid = [], lit = [], r, s, x, y, i, j, wipe = clamp((t - wiped) / .5, 0, 1);
      for (r = 0; r < 3; r++) {
        for (s = 0; s < 16; s++) {
          x = g.x0 + (s + .5) * g.cw; y = g.y0 + (r + .5) * g.ch;
          var on = grid[r][s], here = s === shown, d = g.cw * .2;
          if (on) { for (i = -1; i <= 1; i++) { for (j = -1; j <= 1; j++) { (here ? lit : mid).push(x + i * d, y + j * d * 1.2, here ? 4.6 : 3.6); } } }   // a hit: a block of dots
          else { var e = d * 1.1, q = s % 4 === 0 ? mid : dim; q.push(x - e, y - e, 2, x + e, y - e, 2, x - e, y + e, 2, x + e, y + e, 2); if (here) { mid.push(x, y, 3.6); } }
        }
      }
      if (shown >= 0) { x = g.x0 + (shown + .5) * g.cw; dotted(mid, x, g.y0 - 16, x, g.y0 + 3 * g.ch + 10, 6, 2.4); }   // the step playing
      if (wipe < 1) { dotted(lit, g.x0 + wipe * 16 * g.cw, g.y0 - 10, g.x0 + wipe * 16 * g.cw, g.y0 + 3 * g.ch + 6, 4, 4); }   // shaken clear
      hits.forEach(function (h) { var a = t - h.t0; ring(a < .2 ? lit : dim, g.x0 + (h.s + .5) * g.cw, g.y0 + (h.r + .5) * g.ch, 6 + a * 90, 6, 3.4 * (1 - a), 0); });
      paint(dim, DIM, .5); paint(mid, MID, .5); paint(lit, LIT, .5);
      if (!narrow) { for (r = 0; r < 3; r++) { text(NAMES[r], g.x0 - 16, g.y0 + (r + .5) * g.ch - 6, 11, MID, 'right'); } }
      var fc = (narrow ? 2.6 : 3.6) * SC, fy = g.y0 - 46 * SC - 4.5 * fc + squash * 7;   // the frog dances on the beat: down on the kick, a blink on the hats
      frog(CX, fy, fc * (1 + squash * .05), [g.x0 + (Math.max(shown, 0) + .5) * g.cw, g.y0], t - blink < .08);
      text('100 BPM · 16 STEPS', CX, g.y0 + 3 * g.ch + 22, 11, MID, 'center');
    }
    function osc() { return [['/sensorlove/useraccel/x', jolt[0]], ['/sensorlove/useraccel/y', jolt[1]], ['/sensorlove/useraccel/z', jolt[2]]]; }
    function icon(out) { var on = [[0, 2, 4, 6], [2, 6], [0, 3, 4]], r, s; for (r = 0; r < 3; r++) { for (s = 0; s < 8; s++) { out.push(4 + s * 5, 5 + r * 9); if (on[r].indexOf(s) >= 0) { out.push(4 + s * 5 + 2, 5 + r * 9, 4 + s * 5, 5 + r * 9 + 2, 4 + s * 5 + 2, 5 + r * 9 + 2); } } } }   // a beat, three rows
    return { needs:'motion', begin:begin, step:step, draw:draw, osc:osc, end:function () {}, icon:icon };
  })();

  // ---------- 6 AURORA: MICROPHONE, how loud it is: the voice draws the northern lights over the pond; a clap, a shooting star; a long note, a crown ----------
  var AURORA = (function () {
    var N = 120, hist = [], level = 0, idle = 9, every = 0, hum = 0, meteors = [], corona = 0, sung = 0, acc = 0, state = 'off', A = null, an = null, buf = null, stream = null, blink = -9;
    var HOW = { off:{ tilt:['TAP, THEN SING', 'IT ASKS FOR THE MICROPHONE: ONLY HOW LOUD, NOTHING IS KEPT'], touch:['TAP, THEN SING', 'IT ASKS FOR THE MICROPHONE: ONLY HOW LOUD, NOTHING IS KEPT'], mouse:['CLICK, THEN SING', 'IT ASKS FOR THE MICROPHONE: ONLY HOW LOUD, NOTHING IS KEPT'] },
      on:['SING, HUM OR CLAP', 'YOUR VOICE DRAWS THE SKY. A CLAP, A SHOOTING STAR. HOLD A NOTE'],
      no:{ tilt:['HOLD TO HUM', 'NO MICROPHONE: YOUR FINGER HUMS INSTEAD. TAP: A CLAP'], touch:['HOLD TO HUM', 'NO MICROPHONE: YOUR FINGER HUMS INSTEAD. TAP: A CLAP'], mouse:['HOLD TO HUM', 'NO MICROPHONE: THE BUTTON HUMS INSTEAD. CLICK: A CLAP'] } };
    var LINES = [function () { return HOW[state === 'asking' ? 'off' : state]; }, ['DRIVE LIGHTS WITH SOUND', 'MICROPHONE: HOW LOUD IT IS AROUND THE PHONE, FROM 0 TO 1'], ['CLAP TO CUE', 'A CLAP IS A SPIKE: FIRE A LIGHT, A CLIP, A SCENE'],
      ['A ROOM THAT LISTENS', 'THE CROWD GETS LOUDER, THE VISUALS GROW'], ['NOTHING RECORDED', 'ONLY HOW LOUD, NEVER WHAT IS SAID'], FREE];
    function begin() { lines = LINES; line = -1; every = 6; hist = []; for (var i = 0; i < N; i++) { hist.push(0); } level = 0; meteors = []; corona = 0; sung = 0; hum = 0; idle = 9; acc = 0; cv.addEventListener('pointerup', ask); }
    function again() { if (mode === AURORA) { line = 0; lineAt = t; } }   // its first line again, in the words of now
    function ask() {                                    // in the tap (iOS starts sound only then): the microphone, read here for how loud and nothing else
      if (state !== 'off') { return; }
      var md = navigator.mediaDevices, AC = window.AudioContext || window.webkitAudioContext;
      if (!md || !md.getUserMedia || !AC) { state = 'no'; again(); return; }
      state = 'asking'; A = new AC(); if (A.resume) { A.resume(); }
      md.getUserMedia({ audio:{ echoCancellation:false, noiseSuppression:false, autoGainControl:false } }).then(function (s) {
        if (state !== 'asking') { s.getTracks().forEach(function (k) { k.stop(); }); return; }   // another card went in (or the window went away) before it said yes
        stream = s; an = A.createAnalyser(); an.fftSize = 1024; buf = new Float32Array(an.fftSize); A.createMediaStreamSource(s).connect(an); state = 'on'; again();
      }, function () { state = 'no'; again(); });
    }
    function stop() {                                   // the microphone off: another card, or the window scrolled away
      if (stream) { stream.getTracks().forEach(function (k) { k.stop(); }); }
      if (A && A.close) { A.close(); }
      stream = null; A = null; an = null;
      if (state !== 'no') { state = 'off'; }
    }
    function shoot() { meteors.push({ x:W * (.35 + Math.random() * .6), y:H * (.06 + Math.random() * .18), vx:-(320 + Math.random() * 280), vy:110 + Math.random() * 120, life:1.1 }); blink = t; }
    function step(dt, inp, tap) {
      var L = 0;
      if (state === 'on' && an) {
        an.getFloatTimeDomainData(buf); var s = 0; for (var i = 0; i < buf.length; i++) { s += buf[i] * buf[i]; }
        L = clamp((20 * Math.log10(Math.sqrt(s / buf.length) + 1e-9) + 58) / 46, 0, 1);   // -58 dB is 0, -12 dB is 1
      } else {
        if (inp) { idle = 0; } else { idle += dt; }
        var want = (inp && inp.down) || (idle > 4 && state !== 'asking' && Math.sin(t * .7) > .1);   // held: a hum; alone, it hums now and then
        hum = clamp(hum + (want ? dt * 1.6 : -dt * 1.2), 0, 1);
        L = hum * (.66 + .16 * Math.sin(t * 5) + .1 * Math.sin(t * 13));
        if (tap && state !== 'off' && state !== 'asking') { shoot(); }   // a tap, a clap
        if (idle > 4 && Math.random() < dt * .25) { shoot(); }
      }
      var before = level; level += (L - level) * Math.min(1, dt * (L > level ? 16 : 3));
      if (state === 'on' && L - before > .3 && L > .5) { shoot(); }   // a clap: a jump in how loud
      acc += dt; if (acc > .05) { acc = 0; hist.push(level); hist.shift(); }   // the last 6 s of how loud, the newest on the right
      sung = level > .45 ? sung + dt : Math.max(0, sung - dt);
      if (sung > 2.2 && corona <= 0) { corona = 4; sound('sign', { n:3 }); }   // a long loud note: the sky opens into a crown
      corona = Math.max(0, corona - dt);
      meteors.forEach(function (q) { q.x += q.vx * dt; q.y += q.vy * dt; q.life -= dt; });
      meteors = meteors.filter(function (q) { return q.life > 0; });
      if ((every -= dt) <= 0) { every = 6; nextLine(); }
    }
    function draw() {
      var GY = ground(), dim = [], mid = [], lit = [], refl = [], k, x, j, gap = narrow ? 8 : 10, ds = narrow ? 7 : 8, cr = corona > 0 ? Math.min(1, corona, (4 - corona) * 2) : 0;
      for (k = 0; k < 2; k++) {                         // two curtains, the far one dimmer: each ray as tall and bright as your voice was, a moment ago
        var base = H * (.22 + k * .1), amp = 1 - k * .3;
        for (x = gap / 2 + k * gap / 2; x <= W; x += gap) {
          var u = x / W, v = hist[Math.min(N - 1, Math.floor(u * N))] * amp, wave = Math.sin(u * 7 + t * .6 + k * 1.7) * 22 + Math.sin(u * 17 - t * 1.1 + k) * 8;
          var top = Math.max(110, base + wave - v * H * .08), len = (40 + v * H * .38) * (.75 + .25 * Math.sin(u * 31 + t * 2 + k * 2)), shim = Math.sin(t * 7 + x * .21 + k * 3) > -.2;
          var dx = 0, dy = 1;
          if (cr) { var vx = x - CX, vy = top - H * .04, vl = Math.hypot(vx, vy) || 1; dx = vx / vl * cr; dy = (1 - cr) + vy / vl * cr; var dl = Math.hypot(dx, dy) || 1; dx /= dl; dy /= dl; }   // the crown: every ray from one point
          for (j = 0; j < len; j += ds) {
            var f = j / len, px = x + dx * j + Math.sin(t + j * .02 + u * 9) * 2, py = top + dy * j;
            if (py > GY - 4) { break; }
            (f < .3 && v > .3 && shim ? lit : f < .65 ? mid : dim).push(px, py, (1 - f) * (2.4 + v * 3) + .8);
            if (j % (ds * 2) === 0) { refl.push(px, GY + (GY - py) * .22 + 6, 1.6); }   // in the pond, faint
          }
        }
      }
      dotted(dim, 0, GY, W, GY, 9, 2.6);                // the far shore
      meteors.forEach(function (q) { for (var i = 0; i < 9; i++) { (i ? mid : lit).push(q.x - q.vx * i * .016, q.y - q.vy * i * .016, (i ? 3.2 - i * .3 : 5)); } });
      paint(refl, DIM, .5); paint(dim, DIM, .5); paint(mid, MID, .5); paint(lit, LIT, .5);
      var fc = (narrow ? 2.6 : 3.4) * SC, peak = 0, pk = 0; hist.forEach(function (v, i) { if (v > peak) { peak = v; pk = i; } });
      frog(CX, GY - 4.5 * fc, fc, meteors.length ? [meteors[0].x, meteors[0].y] : [pk / N * W, H * .2], t - blink < .15);   // it looks up at the brightest
    }
    function osc() { return [['/sensorlove/mic', level]]; }
    function icon(out) { for (var x = 2; x <= 42; x += 4) { var top = 6 + Math.sin(x * .25) * 3, len = 6 + (x * 7 % 13); for (var y = 0; y <= len; y += 3) { out.push(x, top + y); } } }   // rays of light
    return { needs:'mic', point:true, begin:begin, step:step, draw:draw, osc:osc, key:ask, away:function () { if (state === 'on' || state === 'asking') { stop(); again(); } }, end:function () { cv.removeEventListener('pointerup', ask); stop(); }, icon:icon };
  })();

  // ---------- 7 CONDUCTOR: HAND TRACKING, where the hand is and how it moves: conduct the frogs' orchestra; each stroke down is a beat ----------
  var BATON = (function () {
    var trail = [], last = null, vy = 0, down = false, beats = 0, lastBeat = -9, bpm = 0, vol = .6, side = .5, idle = 9, every = 0, notes = [], bob = [0, 0, 0], ghost = 0, gk = -1, hand = null;
    var MEL = [4, 7, 9, 7, 4, 2, 0, 2, 4, 7, 9, 12, 11, 7, 9, -1, 9, 7, 5, 4, 2, 4, 5, 7, 4, 2, 0, 2, 0, -1, 0, -1];   // a tune of eight bars, a beat each
    var ROOT = [0, -3, 5, 7, 5, 0, 7, 0], CH = { 0:[0, 4, 7], '-3':[-3, 0, 4], 5:[5, 9, 12], 7:[7, 11, 14] };
    var LINES = [{ tilt:['CONDUCT WITH YOUR FINGER', 'EACH STROKE DOWN IS A BEAT. HIGHER IS LOUDER, SIDEWAYS PICKS WHO LEADS'], touch:['CONDUCT WITH YOUR FINGER', 'EACH STROKE DOWN IS A BEAT. HIGHER IS LOUDER, SIDEWAYS PICKS WHO LEADS'], mouse:['CONDUCT WITH THE MOUSE', 'EACH STROKE DOWN IS A BEAT. HIGHER IS LOUDER, SIDEWAYS PICKS WHO LEADS'] },
      ['CONDUCT WITH YOUR HAND', 'HAND TRACKING: WHERE YOUR HAND IS, AND HOW FAST IT MOVES'], ['A FADER IN THE AIR', 'HOW HIGH YOUR HAND IS, AS A VALUE'],
      ['TWO HANDS', 'EACH ITS OWN ADDRESSES: /HAND/1 AND /HAND/2'], ['7 GESTURES', 'FIST, OPEN PALM, VICTORY: EACH ONE A NUMBER'], FREE];
    function hz(s, base) { return base * Math.pow(2, s / 12); }
    function groups() { var y = H * (narrow ? .6 : .62), dx = W * (narrow ? .3 : .24); return [[CX - dx, y + 6], [CX, y - 18], [CX + dx, y + 6]]; }   // basses, melody, bells
    function begin() { lines = LINES; line = -1; every = 6; trail = []; last = null; vy = 0; down = false; beats = 0; lastBeat = -9; bpm = 0; idle = 9; notes = []; ghost = 0; gk = -1; }
    function play() {                                   // a beat of the tune: the basses on 1 and 3, the melody on each, the bells at each bar's start; where the hand is, that section leads
      var b = beats % 32, root = ROOT[b >> 2], g = .3 + vol * .9, w = [clamp(1.5 - side * 2.2, .2, 1), clamp(1.1 - Math.abs(side - .5) * 1.6, .3, 1), clamp(side * 2.2 - .7, .2, 1)], G = groups(), T = window.SOUND && window.SOUND.time && window.SOUND.time();
      if (b % 2 === 0) { sound('pluck', { f:hz(root, 65.41), g:g * w[0], pan:-.5 }); bob[0] = 1; notes.push({ x:G[0][0], y:G[0][1] - 30, t0:t, k:0 }); }
      if (MEL[b] >= 0) { sound('mallet', { f:hz(MEL[b], 523.25), g:g * w[1] }); bob[1] = 1; notes.push({ x:G[1][0], y:G[1][1] - 30, t0:t, k:1 }); }
      if (b % 4 === 0) { CH[root].forEach(function (s, i) { sound('bell', { f:hz(s, 1046.5), g:g * w[2] * .8, pan:.5, at:typeof T === 'number' ? T + .02 + i * .07 : 0 }); }); bob[2] = 1; notes.push({ x:G[2][0], y:G[2][1] - 30, t0:t, k:2 }); }
      beats++;
    }
    function pattern(ph) {                              // the ghost's four in a bar: down, in, out, up, a little bounce off each
      var K = [[0, 1], [-1, .75], [1, .75], [.1, .15]], R = [[-.15, .45], [-.55, .3], [.55, .3], [0, -.3]], k = Math.floor(ph) % 4, f = ph - Math.floor(ph), a, b, e;
      if (f < .45) { a = K[k]; b = R[k]; e = Math.sin(f / .45 * 1.5708); } else { a = R[k]; b = K[(k + 1) % 4]; e = 1 - Math.cos((f - .45) / .55 * 1.5708); }
      return [a[0] + (b[0] - a[0]) * e, a[1] + (b[1] - a[1]) * e];
    }
    function step(dt, inp) {
      var P = inp && inp.kind === 'point' ? [inp.x, inp.y] : null;
      if (P) { idle = 0; } else { idle += dt; }
      if (!P && idle > 3) {                             // alone: a ghost baton beats four at 84
        ghost += dt * 84 / 60; var p = pattern(ghost); P = [CX + p[0] * W * .15, H * .3 + p[1] * H * .16];
        if (Math.floor(ghost) !== gk) { gk = Math.floor(ghost); bpm = 84; lastBeat = t; play(); }
      }
      if (P && !(idle > 3)) {                           // a stroke down, then its bottom: a beat
        if (last) { var v = (P[1] - last[1]) / Math.max(dt, .001); vy += (v - vy) * Math.min(1, dt * 14);
          if (vy > H * .28) { down = true; }
          else if (down && vy < H * .04) { down = false; if (t - lastBeat > .2) { bpm = lastBeat > 0 && t - lastBeat < 2.5 ? clamp(60 / (t - lastBeat), 30, 220) : 0; lastBeat = t; play(); } }
        }
      }
      if (P) { last = P; trail.push(P[0], P[1]); if (trail.length > 80) { trail.splice(0, 2); } vol = clamp(1 - P[1] / (H * .75), 0, 1); side = clamp(P[0] / W, 0, 1); }
      else { last = null; if (trail.length) { trail.splice(0, 2); } }
      hand = P;
      if (t - lastBeat > 2.5) { bpm = 0; }               // no beat for a while: the orchestra waits
      bob = bob.map(function (b) { return Math.max(0, b - dt * 4); });
      notes.forEach(function (q) { q.y -= dt * 40; }); notes = notes.filter(function (q) { return t - q.t0 < 1.4; });
      if ((every -= dt) <= 0) { every = 6; nextLine(); }
    }
    function draw() {
      var G = groups(), dim = [], mid = [], lit = [], c = (narrow ? 1.25 : 1.8) * SC, sp = (narrow ? 38 : 64) * SC, k, i, waits = bpm === 0;
      oval(dim, CX, G[0][1] + 34 * SC, W * (narrow ? .46 : .4), 26 * SC, 9, 2.4);   // the stage
      G.forEach(function (g, k) {
        var w = [clamp(1.5 - side * 2.2, .2, 1), clamp(1.1 - Math.abs(side - .5) * 1.6, .3, 1), clamp(side * 2.2 - .7, .2, 1)][k], lead = w > .7 ? lit : mid;
        for (i = -1; i <= 1; i++) {
          var fx = g[0] + i * sp, fy = g[1] + Math.abs(i) * 6 - bob[k] * 6 - 4.5 * c;
          if (k === 0) { oval(lead, fx + 13.5 * c * .6, fy + 4 * c, 4 * c, 7 * c, 4, 2.2); dotted(lead, fx + 13.5 * c * .6, fy - 3 * c, fx + 13.5 * c * .6, fy - 9 * c, 4, 2.2); }   // a cello
          else if (k === 1) { dotted(lead, fx + 2 * c, fy + 2.6 * c, fx + 14 * c, fy + 1.4 * c, 4, 2.2); }   // a flute
          else { ring(lead, fx + 12 * c, fy - 6 * c, 3 * c, 3.5, 2.4, 0); dotted(lead, fx + 12 * c, fy - 9 * c, fx + 12 * c, fy - 12 * c, 3, 2.2); }   // a bell
          frog(fx, fy, c, hand || [CX, H * .3], waits && Math.sin(t * 2 + i + k) > .6, w > .7 ? LIT : MID);
        }
      });
      notes.forEach(function (q) { var a = 1 - (t - q.t0) / 1.4, x = q.x + Math.sin((t - q.t0) * 4 + q.k) * 6; (a > .5 ? lit : mid).push(x, q.y, 5 * a + 1); dotted(a > .5 ? lit : mid, x + 3, q.y, x + 3, q.y - 12, 4, 2 * a + .6); });   // the notes they play, rising
      for (i = 0; i < trail.length; i += 2) { (i > trail.length - 10 ? lit : i > trail.length / 2 ? mid : dim).push(trail[i], trail[i + 1], 1.6 + i / trail.length * 3); }   // the baton's path
      if (hand) { lit.push(hand[0], hand[1], 6); }
      paint(dim, DIM, .5); paint(mid, MID, .5); paint(lit, LIT, .5);
      text((vol < .33 ? 'P' : vol < .66 ? 'MF' : 'FF') + ' · ' + (waits ? 'WAITING FOR A BEAT' : Math.round(bpm) + ' BPM'), CX, G[0][1] + 34 * SC + 34 * SC, 11, MID, 'center');
    }
    function osc() { return [['/sensorlove/hand/1/active', hand ? 1 : 0], ['/sensorlove/hand/1/pinch_x', side], ['/sensorlove/hand/1/pinch_y', 1 - vol], ['/sensorlove/hand/1/velocity', Math.abs(vy) / H]]; }
    function zone() { return [0, H * .14, W, H * .86 - 130]; }   // a finger in the hall conducts; the very top still scrolls the page
    function icon(out) { var a; for (a = 0; a <= 1; a += .1) { out.push(6 + a * 26, 24 - a * 20); } for (a = 0; a < 6.28; a += .5) { out.push(30 + Math.cos(a) * 8, 12 + Math.sin(a * 2) * 5); } }   // a baton and its figure
    return { point:true, begin:begin, step:step, draw:draw, osc:osc, end:function () {}, zone:zone, icon:icon };
  })();

  // ---------- which one: the door, the cards, the reader, the connecting; the visitor, the loop ----------
  // door (its name, TRY) → pick (the cards in the middle, under the reader) → connect (one in: the screen finds SensorLove) → play
  var MODES = [PLANE], pick = -1, stage = 'door', connectAt = 0;   // the cards' order on the page; TURN, BEAT, THEREMIN, AURORA, FACE and BATON wait for their fixes (their cards come back in index.html with them)
  var reader = box.querySelector('.reader'), peek = 0;
  function setStage(s) { stage = s; hero.setAttribute('data-stage', s); reader.classList.toggle('show', s === 'pick'); if (zone) { place(); } }
  function go(m) {
    if (mode) { mode.end(); }
    mode = m; cam = { x:0, y:0, roll:0 }; mode.begin(); line = 0; lineAt = t;   // its first line: how to play it
    slot();
  }
  function slot() { carts.forEach(function (c, i) { c.setAttribute('aria-pressed', String(i === pick)); icon(c, i); }); }
  function askFor(i) {                                  // the card going in asks for its own sensor, inside the tap that put it in (iOS asks only then)
    var m = MODES[i];
    if (m.needs === 'motion' && window.ASK_TILT) { window.ASK_TILT(); }
    if (m.needs === 'mic' && m.key) { m.key(); }
  }
  function insert(i) {                                  // a card goes in: the first one connects the screen, the next ones load
    if (loading !== null || stage === 'connect') { return; }
    pick = i; if (mode) { mode.end(); mode = null; }
    if (MODES[i] !== AURORA) { AURORA.away(); }        // a microphone asked for by a card that did not stay in goes off
    if (stage === 'play') { loading = t; } else { door.hidden = true; connectAt = performance.now(); heard = 0; setStage('connect'); }
    slot(); sound('beep', { n:1 });
  }
  door.querySelector('.try').addEventListener('click', function () {   // TRY asks for the phone's motion, inside its tap (all the cards the page plays now want motion)
    if (window.ASK_TILT) { window.ASK_TILT(); }
    door.hidden = true; setStage('pick'); sound('beep', { n:1 });
  });
  function readerOff() { if (stage !== 'pick') { reader.classList.remove('show'); } }
  function over(g) {                                    // the card's middle over the reader (a little round it counts)
    var r = g.getBoundingClientRect(), q = reader.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
    return x > q.left - 30 && x < q.right + 30 && y > q.top - 30 && y < q.bottom + 30;
  }
  function lift(c, i) {                                 // picked up: a copy follows the hand (the row may scroll, and would cut the card off); the card leaves its gap
    var r = c.getBoundingClientRect(), g = c.cloneNode(true);
    g.className = 'cart ghost'; g.removeAttribute('aria-pressed'); g.setAttribute('aria-hidden', 'true'); g.tabIndex = -1;
    g.style.left = r.left + 'px'; g.style.top = r.top + 'px';
    hero.appendChild(g); icon(g, i); c.classList.add('lifted');
    g.r0 = r; return g;
  }
  function land(c, g) { g.remove(); c.classList.remove('lifted'); }
  carts.forEach(function (c, i) {                       // a card goes in only by hand: picked up, the reader comes up; dropped in its slot, it goes in
    var drag = null;
    c.addEventListener('pointerdown', function (e) { if (e.button > 0) { return; } drag = { x:e.clientX, y:e.clientY, dx:0, dy:0, g:null, touch:e.pointerType !== 'mouse' }; if (!drag.touch) { c.setPointerCapture(e.pointerId); } });   // a finger is held by its card anyway; a capture would stop the row from scrolling
    c.addEventListener('pointermove', function (e) {
      if (!drag) { return; }
      drag.dx = e.clientX - drag.x; drag.dy = e.clientY - drag.y;
      if (!drag.g && Math.hypot(drag.dx, drag.dy) < 6) { return; }
      if (!drag.g && drag.touch && stage !== 'pick' && (Math.abs(drag.dx) > Math.abs(drag.dy) || drag.dy > 0)) { drag = null; return; }   // in the row a finger across scrolls it; only pulled up does a card come out
      if (!drag.g) { clearTimeout(peek); drag.g = lift(c, i); reader.classList.add('show'); sound('pip', {}); }
      drag.g.style.transform = 'translate(' + drag.dx + 'px,' + drag.dy + 'px) rotate(' + clamp(drag.dx / 40, -8, 8) + 'deg)';
      reader.classList.toggle('hot', over(drag.g));
    });
    function drop() {
      if (!drag) { return; }
      var g = drag.g; drag = null;
      if (!g) { if (stage !== 'pick') { reader.classList.add('show'); clearTimeout(peek); peek = setTimeout(readerOff, 1500); } return; }   // only pressed: the reader shows where it goes
      var hot = over(g); reader.classList.remove('hot');
      if (!hot) { g.classList.add('back'); g.style.transform = ''; setTimeout(function () { land(c, g); readerOff(); }, 260); return; }   // not in the reader: back to its place
      askFor(i);                                        // in this tap: its sensor's permission
      var q = reader.querySelector('.rslot').getBoundingClientRect(), r = g.r0;
      var tx = (q.left + q.width / 2) - (r.left + r.width / 2), ty = q.top - r.top;
      g.style.transform = 'translate(' + tx + 'px,' + (ty - 10) + 'px)';   // over the slot, upright
      requestAnimationFrame(function () { requestAnimationFrame(function () {
        g.classList.add('into'); g.style.transform = 'translate(' + tx + 'px,' + (ty + 40) + 'px) scale(.7)';   // and down into it
        setTimeout(function () { land(c, g); insert(i); readerOff(); }, 380);
      }); });
    }
    c.addEventListener('pointerup', drop);
    c.addEventListener('pointercancel', function () { if (drag) { if (drag.g) { land(c, drag.g); } reader.classList.remove('hot'); readerOff(); drag = null; } });   // the row scrolled instead
    c.addEventListener('click', function (e) {            // the keyboard's Enter or Space (a pointer's click has a detail, and does nothing): straight in
      if (e.detail || (i === pick && mode)) { return; }
      askFor(i);
      c.classList.remove('going'); void c.offsetWidth; c.classList.add('going');
      insert(i);
    });
  });
  function icon(c, i) {                                 // each card's small drawing, in dots
    var k = c.querySelector('canvas'), dpr = devicePixelRatio || 1, w = k.clientWidth, h = k.clientHeight, q = k.getContext('2d'), out = [], cs = getComputedStyle(c);
    if (!w) { return; }
    k.width = w * dpr; k.height = h * dpr; q.setTransform(dpr, 0, 0, dpr, 0, 0); q.clearRect(0, 0, w, h);
    MODES[i].icon(out, w, h);
    q.fillStyle = cs.getPropertyValue(i === pick ? '--fg' : '--mid').trim(); q.beginPath();
    pairs(out).forEach(function (p) { q.moveTo(p[0] + 1.1, p[1]); q.arc(p[0], p[1], 1.1, 0, 6.2832); });
    q.fill();
  }
  function pairs(a) { var r = []; for (var j = 0; j < a.length; j += 2) { r.push([a[j], a[j + 1]]); } return r; }
  function load() {                                     // a card goes in while playing: its name, a bar of dots filling, then it plays
    var k = clamp((t - loading) / .9, 0, 1), n = 24, bar = [], name = carts[pick] ? carts[pick].querySelector('.cn').textContent : '';
    text('LOADING ' + name, CX, CY - 24, narrow ? 11 : 16.5, MID, 'center');
    for (var j = 0; j < n; j++) { bar.push(CX + (j - (n - 1) / 2) * 9, CY + 8, j < k * n ? 2.4 : 1.2); }
    paint(bar, k >= 1 ? LIT : MID, 1);
    if (t - loading > 1.05) { loading = null; go(MODES[pick]); }
  }
  cv.addEventListener('keydown', function (e) {
    if (/^Arrow/.test(e.key)) { held[e.key] = true; keysAt = performance.now(); e.preventDefault(); }
    else if (e.key === ' ') { var T = window.TILT, r = cv.getBoundingClientRect(); if (T) { T.tap = performance.now(); T.tapOn = cv; T.px = T.px || r.left + W / 2; T.py = T.py || r.top + H / 2; } if (mode && mode.key) { mode.key(); } e.preventDefault(); }
  });
  cv.addEventListener('keyup', function (e) { held[e.key] = false; });
  var zone = box.querySelector('.zone'), zoneAt = '';   // where a finger plays a game (a record, the hall) instead of scrolling the page: the browser decides that where a touch starts
  function place() { var z = stage === 'play' && mode && mode.zone ? mode.zone() : null, k = z ? z.map(Math.round).join(',') : ''; if (k === zoneAt) { return; } zoneAt = k; zone.style.display = z ? 'block' : 'none'; if (z) { zone.style.left = z[0] + 'px'; zone.style.top = z[1] + 'px'; zone.style.width = z[2] + 'px'; zone.style.height = z[3] + 'px'; } }
  if (window.IntersectionObserver) { new IntersectionObserver(function (e) { seen = e[0].isIntersecting; if (!seen && mode && mode.away) { mode.away(); } }).observe(cv); }   // scrolled away: a microphone goes off
  function intro(it) {                                  // the screen finds SensorLove: a search going out in rings, then the three lines
    var R = Math.min(W, H) * .42, out = [], k;
    for (k = 0; k < 3; k++) { var f = ((it + k * .5) % 1.5) / 1.5; if (!(it > SAY[1][1] && f > .2)) { ring(out, CX, CY, f * R, 10, 4 * (1 - f) + 1, 0); } }
    paint(out, DIM, .31);
    SAY.forEach(function (s, i) {
      if (it < s[1]) { return; }
      var shown = s[0].slice(0, Math.floor((it - s[1]) * 30)), y = CY + (i - 1) * (narrow ? 22 : 34) - 8;
      text(shown, CX, y, narrow ? 11 : 16.5, i === 2 ? LIT : MID, 'center');
      if (i === 2 && shown.length === s[0].length && Math.floor(it * 4) % 2) { ctx.fillStyle = RED; ctx.fillRect(CX - ctx.measureText(s[0]).width / 2 - (narrow ? 12 : 18), y + (narrow ? 3 : 5), narrow ? 6 : 8, narrow ? 6 : 8); }
      if (i && heard < i) { heard = i; sound('beep', { n:i }); }
    });
    if (pre) { var s = SAY.filter(function (q) { return it >= q[1]; }).map(function (q) { return q[0]; }).join('\n'); if (pre.textContent !== s) { pre.textContent = s; } }
  }
  function looking() { var T = window.TILT, r = cv.getBoundingClientRect(); return T && T.px ? [T.px - r.left, T.py - r.top] : [CX, CY]; }
  function frame(now) {
    requestAnimationFrame(frame);
    var dt = Math.min(.05, (now - last) / 1000); last = now;
    if (!seen) { sound('tone', { f:110, g:0 }); return; }   // off screen: nothing to draw, nothing to hear
    t += dt;
    ctx.clearRect(0, 0, W, H);
    if (stage === 'door' || stage === 'pick') {         // the door: the frog asleep; the cards: awake, it watches the hand (unless the reader comes too close)
      sky(.3, dt); if (stage === 'door' || H * .3 > 235) { logo(stage === 'pick' ? looking() : [CX, CY], stage === 'door'); } return;
    }
    if (stage === 'connect') {                          // the screen finds SensorLove, until it ends or a tap skips it
      var it = REDUCED ? ON + 1 : (now - connectAt) / 1000;
      if (it < ON && !tapped()) { sky(.3, dt); intro(it); logo([CX, CY], it < SAY[2][1]); return; }
      setStage('play'); go(MODES[pick]); sound('start');
    }
    if (loading !== null) { sky(.3, dt); load(); logo([CX, CY], false); return; }
    var inp = input(now, mode.point);
    place();
    mode.step(dt, inp, tapped());
    sky(mode.speed ? mode.speed() : REDUCED ? 0 : .3, dt);
    mode.draw();
    caption();
    if (now - said > 83) { said = now; tell(mode.osc()); }
  }
  size(); setStage('door'); slot();
  addEventListener('resize', function () { size(); slot(); });
  (document.fonts ? document.fonts.load('22px "Departure Mono"') : Promise.resolve()).then(begin, begin);
  function begin() { last = performance.now(); requestAnimationFrame(frame); }
})();
