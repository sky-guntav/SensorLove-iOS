// The hero's app, as it opens: one sensor on, another each load (monitor-boot.js), and every 3 s the next of SL.cycle in its place
// on the monitor. With all off, the paper wizard says hello, then the app's own lines (TAP A SENSOR BELOW ...); the visitor turns
// the sensors on and off, and from their first tap the phone is theirs (the turns stop).
// The motion sensors follow the visitor (window.TILT in site.js: their mouse, or their phone's tilt after TRY); left alone, the slow
// sway of a phone in a hand, and once they have touched it, a phone lying still. The rest is made up the same way, fed as the app
// feeds it (SL.recv, 30 a second).
(function () {
  var POSES = ['open', 'victory', 'ily', 'thumbup', 'point', 'pinch'];
  var COARSE = matchMedia('(pointer: coarse)').matches, mine = false, t0 = performance.now(), cur = [0, 0, 0], timers = [], APP_SAY = HELLO_SAY, APP_TIP = HELLO_TIP;
  HELLO_SAY = [['HELLO! THIS IS', 'SENSORLOVE']];
  HELLO_TIP = 48;                                       // 4 s a line (12 ticks a second)

  setInterval(function () {                             // sharp at any zoom: the page sized its canvases for the ratio it saw first
    if (DPR !== devicePixelRatio) { DPR = devicePixelRatio; Object.keys(pageCache).forEach(function (k) { sizePage(pageCache[k]); }); }
  }, 300);

  function quat(p, r, y) {                              // pitch, roll, yaw → x, y, z, w
    var c = [Math.cos(p / 2), Math.cos(r / 2), Math.cos(y / 2)], s = [Math.sin(p / 2), Math.sin(r / 2), Math.sin(y / 2)];
    return [s[0] * c[1] * c[2] - c[0] * s[1] * s[2], c[0] * s[1] * c[2] + s[0] * c[1] * s[2], c[0] * c[1] * s[2] - s[0] * s[1] * c[2], c[0] * c[1] * c[2] + s[0] * s[1] * s[2]];
  }
  function aim(t) {                                     // pitch, roll, yaw: the visitor's phone, their mouse, or the sway (a finger taps, it is no tilt: the cards would swing under it)
    var T = parent.TILT, now = performance.now(), d = Math.PI / 180, w = Math.sin;
    if (T && T.dev && now - T.at < 1000) { return [T.dev[0] * d, T.dev[1] * d, -T.dev[2] * d]; }
    if (T && !COARSE && now - T.at < 3000) { return [T.y * .9, T.x * 1.3, T.x * .6]; }
    if (mine) { return [0, 0, 0]; }                    // theirs now: it lies still, the cards upright
    return [.5 * w(t * .6), .7 * w(t * .45 + 1), t * .3];
  }
  setInterval(function () {
    var t = (performance.now() - t0) / 1000, w = Math.sin, k = Math.floor(t / 3) % FACE_MOVES.length, e = (t % 3) * 12, a = aim(t);
    var step = cur.map(function (c, i) { var d = a[i] - c; return Math.atan2(w(d), Math.cos(d)) * .15; });   // eased, the short way round
    cur = cur.map(function (c, i) { return c + step[i]; });
    var p = cur[0], r = cur[1], y = Math.atan2(w(cur[2]), Math.cos(cur[2]));
    var g = [-w(r) * Math.cos(p), w(p), -Math.cos(r) * Math.cos(p)], knock = Math.max(0, w(t * 2.1)) > .97 ? .6 : 0;
    var one = HAND_POSES[POSES[Math.floor(t / 2) % POSES.length]], two = HAND_POSES[POSES[(Math.floor(t / 2) + 3) % POSES.length]];
    SL.recv({
      mps: tiles.some(function (s) { return s.on; }) ? 900 + Math.round(60 * w(t * 2)) : 0,   // made up too: the console is not at 0 while its dots run
      v: {
        attitude: [p, r, y], quat: quat(p, r, y), gravity: g,
        accel: [g[0] + knock, g[1] + .05 * w(t * 9), g[2]], pressure: [101.3 + .02 * w(t * .2), .8 * w(t * .5)],
        gyro: step.map(function (s) { return s * 30; }), useraccel: [knock, .05 * w(t * 9), 0], mag: [22 * Math.cos(y), -22 * w(y), -38],
        mic: [.3 + .4 * Math.abs(w(t * 2.7) * w(t * 7.1))], prox: [w(t * .4) > .98 ? 0 : 1],
        weather: [13.4, 12.1, 82, 1.4, 96, 4.6, 230, 1012, 1, 61], time: clockVals(new Date()), battery: [.92, 0],
        face: faceMove(k, Math.min(1, (t % 3) * 2), e)
      },
      hands: [handLm(1, one, .3, .7, .13, .1 * w(t)), handLm(-1, two, .7, .7, .13, -.1 * w(t * 1.3))]
    });
  }, 33);

  // VIDEO and DEPTH: the camera's picture is made up too, a paper frog on a table sitting for the front camera, fed as NDI.swift
  // feeds the cards (SL.recv thumb, while a card is on): VIDEO the picture; DEPTH by 1 / distance with FAR as set (the wall is past
  // the sensor's reach: black); depthshade its slopes, lit as NDI.swift lights them. One receiver watches each source.
  var CW = 240, CH = 320, CF = 208, TOP = -.255, U = new Float32Array(CW * CH), ID = new Int8Array(CW * CH), GRAIN = [];   // 3:4, 60° across: a phone's front lens. TOP: the table, under its feet
  var shot = document.createElement('canvas'), sc = shot.getContext('2d'), vid = sc.createImageData(CW, CH), grey = sc.createImageData(CW, CH);
  var PAPER = [236, 229, 214], WHITE = [247, 244, 237], INK = [34, 31, 27], RED = [224, 83, 58], WOOD = [190, 174, 150], WALL = [255, 244, 224], MIX = [0, 0, 0], L = [-.5, .65, -.6].map(function (v) { return v / Math.hypot(.5, .65, .6); });   // L: toward the window, top left
  var HIT = null, Z = 0, RGB = [0, 0, 0], AT = [0, .45];   // what a ray met (a ball, 'T' the table, null the wall), how far, its colour; AT: the frog's middle (x, z)
  var LIT = new Float32Array(CW * CH).map(function (_, k) {   // the wall, a window's light on it from the top left
    var u = k % CW / CW - .5, v = Math.floor(k / CW) / CH - .5;
    return (.42 + .34 * Math.exp(-((u + .3) * (u + .3) + (v + .3) * (v + .3)) * 7)) * (1 - .6 * (u * u + v * v));
  });
  shot.width = CW; shot.height = CH;
  for (var n = 0; n < 4096; n++) { GRAIN.push((Math.random() - .5) * 10); }
  function frog(t) {                                    // its balls (m: x right, y up, z away; radii; colour): it breathes, sways, blinks and looks where the visitor points
    var T = parent.TILT, live = T && performance.now() - T.at < 3000, gx = live ? T.x * .011 : .006 * Math.sin(t * .7), gy = live ? -T.y * .009 : .004 * Math.sin(t * .9);
    var a = .12 * Math.sin(t * .5), br = 1 + .015 * Math.sin(t * 1.4), shut = t % 4.3 < .15;
    var B = [[0, -.07, .45, .15, .11 * br, .12, PAPER], [0, -.17, .44, .12, .07 * br, .1, WHITE], [-.1, -.235, .41, .05, .02, .05, PAPER], [.1, -.235, .41, .05, .02, .05, PAPER]];
    [-1, 1].forEach(function (s) {
      B.push([s * .075, .035, .42, .05, .05, .045, PAPER], [s * .075, .045, .393, .036, shut ? .004 : .036, .03, WHITE]);
      if (!shut) { B.push([s * .075 + gx, .045 + gy, .364, .016, .019, .006, INK]); }
    });
    AT = [0, camSide() === 'BACK' ? .95 : .45];         // BACK: the phone held out, the frog further off
    return B.map(function (q, n) {                      // turned about its middle; each ball's box on the picture, so a ray tries only the few it can meet
      var x = q[0] * Math.cos(a) + (q[2] - .45) * Math.sin(a), z = AT[1] - q[0] * Math.sin(a) + (q[2] - .45) * Math.cos(a), r = Math.max(q[3], q[4]) * CF / (z - q[5]) * 1.1;
      var u = CW / 2 + x / z * CF, v = CH / 2 - q[1] / z * CF;
      return { n:n, c:[x, q[1], z], ir:[1 / q[3], 1 / q[4], 1 / q[5]], col:q[6], box:[u - r, u + r, v - r, v + r] };
    });
  }
  function look(B, x, y) {                              // the ray through the picture's (x, y), (dx, dy, 1): its depth is where it meets something
    var dx = (x - CW / 2) / CF, dy = (CH / 2 - y) / CF, b, q, w, c;
    HIT = null; Z = Infinity;
    for (b = 0; b < B.length; b++) {
      q = B[b];
      if (x < q.box[0] || x > q.box[1] || y < q.box[2] || y > q.box[3]) { continue; }
      var ex = dx * q.ir[0], ey = dy * q.ir[1], ez = q.ir[2], ox = -q.c[0] * q.ir[0], oy = -q.c[1] * q.ir[1], oz = -q.c[2] * q.ir[2];
      var A = ex * ex + ey * ey + ez * ez, h = ox * ex + oy * ey + oz * ez, s = h * h - A * (ox * ox + oy * oy + oz * oz - 1);
      if (s > 0 && (-h - Math.sqrt(s)) / A < Z) { Z = (-h - Math.sqrt(s)) / A; HIT = q; }
    }
    if (dy < 0 && TOP / dy < Math.min(Z, AT[1] + .45)) { Z = TOP / dy; HIT = 'T'; }   // the table, 45 cm on behind the frog
    if (HIT === 'T') {                                  // in the light, the frog's soft shadow cast back and right
      var sx = dx * Z - AT[0] - .05, sz = Z - AT[1] - .04;
      w = (.4 + .68 * L[1]) * (sx * sx + sz * sz < .1 ? 1 - .5 * Math.exp(-sx * sx / .012 - sz * sz / .005) : 1); c = WOOD;
    } else if (HIT) {                                   // paper in the window's light; the mouth a wide smile, the cheeks red
      var px = dx * Z - HIT.c[0], py = dy * Z - HIT.c[1], nx = px * HIT.ir[0] * HIT.ir[0], ny = py * HIT.ir[1] * HIT.ir[1], nz = (Z - HIT.c[2]) * HIT.ir[2] * HIT.ir[2];
      w = .4 + .68 * Math.max(0, (nx * L[0] + ny * L[1] + nz * L[2]) / Math.sqrt(nx * nx + ny * ny + nz * nz)); c = HIT.col;
      if (HIT.n === 0) {
        var m = Math.abs(px) < .11 ? clamp((.0035 - Math.abs(py + .015 - 1.6 * px * px)) / .0015) : 0, r2 = (Math.abs(px) - .1) * (Math.abs(px) - .1) + (py + .045) * (py + .045), k = r2 < .0005 ? .5 * clamp(1 - Math.sqrt(r2) / .022) : 0;
        for (b = 0; b < 3; b++) { MIX[b] = (c[b] + (RED[b] - c[b]) * k) * (1 - m) + INK[b] * m; }
        c = MIX;
      }
    } else { w = LIT[(y | 0) * CW + (x | 0)]; c = WALL; }
    RGB[0] = c[0] * w; RGB[1] = c[1] * w; RGB[2] = c[2] * w;
  }
  function trace(B) {                                   // a ray a pixel: U its 1 / depth (0: none), vid the picture
    var d = vid.data, g = Math.floor(Math.random() * 4096), rows = [], k, i, j, o, s0, s1, s2;
    for (j = 0; j < CH; j++) { rows.push(B.filter(function (q) { return q.box[2] <= j + 1 && q.box[3] >= j; })); }   // a row tries only the balls it crosses
    for (k = 0; k < U.length; k++) {
      look(rows[Math.floor(k / CW)], k % CW + .5, Math.floor(k / CW) + .5);
      ID[k] = HIT === 'T' ? -2 : HIT ? HIT.n : -1; U[k] = HIT ? 1 / Z : 0;
      put(d, k, GRAIN[(k + g) & 4095]);
    }
    for (k = 0; k < U.length; k++) {                   // its edges smoothed as a lens has them: 4 rays a pixel where what it sees changes (DEPTH keeps them sharp, as measured)
      i = k % CW; j = (k - i) / CW;
      if ((i < 1 || ID[k - 1] === ID[k]) && (i > CW - 2 || ID[k + 1] === ID[k]) && (j < 1 || ID[k - CW] === ID[k]) && (j > CH - 2 || ID[k + CW] === ID[k])) { continue; }
      for (s0 = s1 = s2 = o = 0; o < 4; o++) { look(rows[j], i + .25 + (o & 1) * .5, j + .25 + (o >> 1) * .5); s0 += RGB[0]; s1 += RGB[1]; s2 += RGB[2]; }
      RGB[0] = s0 / 4; RGB[1] = s1 / 4; RGB[2] = s2 / 4; put(d, k, GRAIN[(k + g) & 4095]);
    }
  }
  function put(d, k, e) { d[k * 4] = RGB[0] + e; d[k * 4 + 1] = RGB[1] + e; d[k * 4 + 2] = RGB[2] + e; d[k * 4 + 3] = 255; }
  function jpeg(img) { sc.putImageData(img, 0, 0); return shot.toDataURL('image/jpeg', .7); }
  function greys(f) { for (var k = 0, d = grey.data; k < U.length; k++) { d[k * 4] = d[k * 4 + 1] = d[k * 4 + 2] = f(k); d[k * 4 + 3] = 255; } return jpeg(grey); }
  function depthPic() {                                 // NDI.swift's range: FAR's metres from 20 cm; AUTO (and EQ, here) the scene's; FACE 40 cm from the nearest
    var zn = Infinity, zf = 0, f = NDISET.far, k;
    for (k = 0; k < U.length; k++) { if (U[k]) { zn = Math.min(zn, 1 / U[k]); zf = Math.max(zf, 1 / U[k]); } }
    var near = typeof f === 'number' ? .2 : Math.max(zn * .97, .2), far = typeof f === 'number' ? f : f === 'FACE' ? near + .4 : Math.max((zf + .01) * 1.05, near + .3);
    return greys(function (k) { return U[k] && 1 / U[k] <= far ? 255 * Math.min(1, Math.max(32 / 56064, (U[k] - 1 / far) / (1 / near - 1 / far))) : 0; });
  }
  function shadePic() {                                 // NDI.swift's depthshade: lit from the top left by its slopes, 0 where it or a neighbour has no depth
    return greys(function (k) {
      if (k % CW < 1 || k % CW > CW - 2 || k < CW || k >= U.length - CW || !U[k] || !U[k - 1] || !U[k + 1] || !U[k - CW] || !U[k + CW]) { return 0; }
      var gx = CF * (U[k + 1] - U[k - 1]) / (2 * U[k]), gy = CF * (U[k + CW] - U[k - CW]) / (2 * U[k]);
      return 255 * (gx + gy + 1) / (1.7320508 * Math.sqrt(gx * gx + gy * gy + 1));
    });
  }
  setInterval(function () {                             // 10 a second (the app's come at 30): the frog moves slowly
    var v = tileOf('video').on, dp = tileOf('depth').on, s = NDISET.size, wh = s === 'MAX' ? [1440, 1920] : [s, s * 4 / 3], f = frameElement && frameElement.getBoundingClientRect();
    var src = function (on, nm) { return on ? [1, 1, 0, wh[0], wh[1], 30, 'IPHONE (' + NDISET.name + ' ' + nm + ')'] : [0, 0, 0, 0, 0, 0, '']; };   // on, one watching, no tally
    SL.recv({ ndi:{ video:src(v, 'VIDEO'), depth:src(dp, 'DEPTH') } });
    if ((!v && !dp) || (f && (f.bottom < 0 || f.top > parent.innerHeight))) { return; }   // nothing on, or the hero scrolled away: no frames
    trace(frog((performance.now() - t0) / 1000));
    if (v) { SL.recv({ thumb:['video', jpeg(vid)] }); }
    if (dp) { SL.recv({ thumb:NDIVIEW === 'DITHER' ? ['depthshade', shadePic()] : ['depth', depthPic()] }); }   // only the one IMAGE draws (the app sends both)
  }, 100);

  setInterval(function () {                             // every 3 s the next sensor takes the monitor, the one before off, until the visitor's first tap
    var ring = SL.cycle || [], on = tiles.filter(function (t) { return t.on; }), next;
    if (mine || !ring.length || document.hidden) { return; }
    next = tileOf(ring[(ring.indexOf(on.length ? on[0].c.id : '') + 1) % ring.length]);
    if (!next) { return; }
    on.forEach(function (t) { toggle(t); });
    toggle(next); showTile(next);
  }, 3000);

  function later(f, ms) { timers.push(setTimeout(f, ms)); }
  function own() { HELLO_SAY = APP_SAY; HELLO_TIP = APP_TIP; }   // the app's own lines: TAP A SENSOR BELOW ...
  later(function () {                                   // the page takes no tap in its first 400 ms
    if (pageCache.hello && pageCache.hello.hz) { helloTap(pageCache.hello, frame); }
    later(own, HELLO_SAY.length * HELLO_TIP / 12 * 1000 + 1500);
  }, 1100);
  if (COARSE) {                                         // a finger scrolls the app's list; past either end it moves the site (a page in a frame does not hand a scroll on)
    var fy = null;
    main.addEventListener('touchstart', function (e) { fy = e.touches.length === 1 ? e.touches[0].clientY : null; }, { passive:true });
    main.addEventListener('touchmove', function (e) {
      if (fy === null || LIFT) { return; }
      var y = e.touches[0].clientY, dy = y - fy, end = main.scrollHeight - main.clientHeight, k = frameElement ? frameElement.getBoundingClientRect().height / innerHeight : 1;
      fy = y;
      if ((dy < 0 && main.scrollTop >= end - 2) || (dy > 0 && main.scrollTop <= 1)) { parent.scrollBy(0, -dy * k); }   // 2 px: a zoomed frame stops a little short of the end
    }, { passive:true });
  }
  addEventListener('pointerdown', function () {         // the visitor's now: no more hello
    mine = true;
    timers.forEach(clearTimeout);
    own();
  }, { once:true, capture:true });
})();
