// A page reached through one of the site's links (site.js floods the old one with dithered ink): dark from its first paint, until
// site.js drains it from where the link was pressed. Run in the head, before anything is drawn.
try { if (Date.now() - JSON.parse(sessionStorage.getItem('sensorlove.go')).t < 4000) { document.documentElement.classList.add('dt'); } } catch (e) { /* none kept */ }
