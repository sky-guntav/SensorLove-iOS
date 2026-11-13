// Counting visits: Google Analytics, on sensor.love itself (the previews here count no one), its ad features off
// (docs/privacy-policy.md, This website). A file of its own: page.html's CSP runs no inline script
(function () {
  var ID = 'G-R52SQ4FJGQ', s;
  if (location.hostname !== 'sensor.love') { return; }
  // Tag Assistant: gtag.js opens its debug panel for a gtm_debug link, a visit from tagassistant.google.com, its __TAG_ASSISTANT
  // cookie or its extension's mark. Under this CSP the panel can neither dress nor connect, and the cookie kept it on every page
  // of the browser that once tested: both go, and such a visit is not counted
  ['', '; domain=sensor.love', '; domain=.sensor.love'].forEach(function (d) { document.cookie = '__TAG_ASSISTANT=; max-age=0; path=/' + d; });
  document.documentElement.removeAttribute('data-tag-assistant-present');
  if (/[?&]gtm_debug=/.test(location.search) || /^https:\/\/tagassistant\.google\.com\//.test(document.referrer)) { return; }
  window.dataLayer = window.dataLayer || [];
  window.gtag = function () { window.dataLayer.push(arguments); };   // gtag.js wants the arguments object itself
  window.gtag('js', new Date());
  window.gtag('config', ID, { allow_google_signals:false, allow_ad_personalization_signals:false });
  s = document.createElement('script'); s.async = true; s.src = 'https://www.googletagmanager.com/gtag/js?id=' + ID;
  document.head.appendChild(s);
})();
