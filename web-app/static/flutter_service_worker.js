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
		self.registration
			.unregister()
			.then(() => self.clients.matchAll())
			.then((clients) => {
				clients.forEach((client) => client.navigate(client.url));
			})
	);
});
