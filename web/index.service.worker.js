// TOMBSTONE SERVICE WORKER — it exists only to destroy its predecessor.
//
// `export_presets.cfg` had `progressive_web_app/enabled=true`, so every export
// shipped Godot's own `index.service.worker.js`: a cache-first worker whose
// fetch handler returns a cache hit without ever touching the network, with
// `index.html` and `index.js` in its CACHED_FILES. The page never got an update
// path either — the shell only calls `installServiceWorker()` when
// `ensureCrossOriginIsolationHeaders` is true, and it is false here — so a
// worker registered by an old deploy stayed in control across every ordinary
// reload. That is the whole of the reported "updates only arrive after a hard
// reset with cache clear".
//
// Turning the export setting off stops NEW builds shipping that worker, but a
// registration already sitting in a player's browser is permanent: nothing in a
// newly served page can reach it, and it would go on serving its old cache
// forever. A registration is only replaced by a byte-different script at the
// SAME url. So this file has to keep being served at `/index.service.worker.js`
// — that is the only door back into those browsers.
//
// **Keep this deployed.** Browsers only collect it on their next navigation to
// the site; deleting it (so the url 404s) does not unregister anything, it just
// leaves the old worker in place on every install that has not called yet.
// Retire it when the stragglers no longer matter, not when the fix "looks done".

// Install: take over immediately. Without skipWaiting the new worker sits in
// "waiting" until every tab of the origin is closed — which is exactly the trap
// the old worker was in, and a plain reload never closes a tab.
self.addEventListener('install', (event) => {
	event.waitUntil(self.skipWaiting());
});

// Activate, in this order on purpose: the caches must be gone BEFORE the
// clients reload, or they reload straight back into the stale shell. Unregister
// then removes the registration, so the reloaded pages come up uncontrolled and
// every request goes to the network from then on.
//
// This worker deliberately registers NO fetch handler. A worker with no fetch
// listener is transparent — the browser skips it entirely — so even in the
// window between activation and the reload nothing is served from a cache.
self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		const names = await caches.keys();
		await Promise.all(names.map((name) => caches.delete(name)));
		await self.registration.unregister();
		// includeUncontrolled: after skipWaiting the old worker's clients are
		// already ours, but the flag costs nothing and covers the ordering
		// either way.
		const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
		for (const client of clients) {
			client.navigate(client.url);
		}
	})());
});
