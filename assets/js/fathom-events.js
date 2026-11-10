// Sends Yonderbook's funnel events to Fathom (#1408). These feed Fathom's own
// weekly email; the app keeps no reporting of its own.
//
// Three ways an event fires:
//   - a page renders <meta name="fathom-event" content="name"> (layout.erb)
//   - a form carrying data-fathom-submit="name" is submitted
//   - any link to /connect is clicked (connect_started)
//
// Event names are permanent: Fathom cannot rename them, so change one only by
// adding a new name.
(function () {
  function track(name) {
    if (window.fathom && name) window.fathom.trackEvent(name);
  }

  window.addEventListener('load', function () {
    document.querySelectorAll('meta[name="fathom-event"]').forEach(function (meta) {
      track(meta.content);
    });
  });

  document.addEventListener('click', function (event) {
    var link = event.target.closest && event.target.closest('a[href]');
    if (link && link.pathname === '/connect') track('connect_started');
  });

  document.addEventListener('submit', function (event) {
    track(event.target.dataset && event.target.dataset.fathomSubmit);
  });
})();
