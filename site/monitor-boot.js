// The hero is the app itself: WebUI/home.html, copied in by site/build.py as monitor.html and fed as the app feeds it (this runs
// before its script), but drawn as the browser study draws it, in a phone with its status bar, in its dark theme (the hero's
// night). It opens with one sensor on, its card first, another each time the page loads (the last one is kept for the tab,
// sessionStorage, so a reload never shows it again); monitor.js runs the show, SL.cycle in turn. What the page tells the app goes nowhere.
(function () {
  var first = ['face', 'quat', 'hand', 'weather', 'attitude', 'time', 'battery', 'gravity', 'pressure', 'accel'];   // the cards on top
  var CYCLE = first.concat(['gyro', 'useraccel', 'mag', 'mic']), SHOW = CYCLE, last = null, pick;   // what can be on: what monitor.js feeds, moving
  try { last = sessionStorage.getItem('sensorlove.hero'); } catch (e) { /* none kept */ }
  SHOW = SHOW.filter(function (id) { return id !== last; });
  pick = SHOW[Math.floor(Math.random() * SHOW.length)];
  try { sessionStorage.setItem('sensorlove.hero', pick); } catch (e) { /* then it may come again */ }
  var mac = { name: 'STUDIO MAC', host: '192.168.1.20', port: 9000, prefix: '', tcp: false, json: false, on: true };   // so its top bar shows data going out
  window.webkit = { messageHandlers: { sl: { postMessage: function () {} } } };
  window.SL = {
    version: '1.0',
    store: { 'sensorlove.last': JSON.stringify({ s: { on: [pick], order: [pick].concat(first.filter(function (id) { return id !== pick; })), hz: 60, dests: [mac.name], cam: 'FRONT', camhz: 30 }, dests: [mac], preset: 'MAIN', theme: 'dark', bg: true }) },
    osc: {}, cycle: CYCLE, live: '{{live}}', ip: '192.168.1.5',     // live: every sensor the app reads (Sender.live), written in by site/build.py
    perm: { motion: 'ok', camera: 'ok', location: 'ok', mic: 'ok', network: 'ok' }
  };
  document.documentElement.classList.add('demo');
})();
