// Self-destroying service worker.
//
// This path used to be served by the app's former Flutter Web build, whose
// service worker aggressively cached and served the old app shell — meaning
// returning users kept getting the Flutter version even after this SvelteKit
// app went live. Browsers periodically re-fetch the registered service worker
// script to check for updates; when they fetch this (byte-different) version,
// it installs, unregisters itself, and reloads open tabs so they load the
// current app fresh from the network. One-shot: after it runs, no service
// worker remains registered.

self.addEventListener('install', () => {
	self.skipWaiting();
});

self.addEventListener('activate', (event) => {
	event.waitUntil(
		// clients.claim() takes control of tabs that are already open (opened
		// under the old worker) immediately, rather than only affecting future
		// navigations — otherwise an already-open tab may not be handed to
		// this worker until it happens to reload some other way.
		self.clients
			.claim()
			.then(() => self.registration.unregister())
			.then(() => self.clients.matchAll({ type: 'window' }))
			.then((clients) => {
				clients.forEach((client) => {
					if ('navigate' in client) client.navigate(client.url);
				});
			})
	);
});

// Belt-and-suspenders: a worker with no fetch listener already behaves as a
// pure passthrough to the network per spec, but make that explicit in case a
// browser implementation quirk (this whole file exists because of one)
// serves something stale from an old cache instead.
self.addEventListener('fetch', (event) => {
	event.respondWith(fetch(event.request));
});
