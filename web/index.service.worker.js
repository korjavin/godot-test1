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
		// OUR caches only, matched by exact prefix. `caches` is scoped to the
		// ORIGIN, not to this worker's path, and the GitHub Pages mirror lives
		// on a korjavin.github.io shared with every other project of the
		// owner's — a blanket `caches.delete()` there wipes their offline
		// storage too, and `-sw-cache-` alone would still catch any other Godot
		// PWA on the domain. This prefix is measured, not guessed: exporting
		// with `progressive_web_app/enabled=true` emits a worker whose
		// `CACHE_PREFIX` is `<project name>-sw-cache-`.
		//
		// A rename would leave the old cache behind, and that is fine — it is
		// `unregister()` below that actually ends the staleness. An orphaned
		// cache with no worker to read it is unreachable garbage the browser
		// evicts on its own; deleting it here is hygiene, not the fix.
		const stale = (await caches.keys()).filter((name) => name.startsWith('CrimeKickers-sw-cache-'));
		await Promise.all(stale.map((name) => caches.delete(name)));
		await self.registration.unregister();
		// Controlled clients only — no `includeUncontrolled`. skipWaiting()
		// above handed us every tab the old worker held, which is exactly the
		// set that needs reloading; `includeUncontrolled: true` would widen this
		// to every same-origin window, scope or not, and blow away an unrelated
		// project's tab state on the shared Pages origin. A window that was not
		// controlled was never served from the stale cache, so it needs nothing.
		const clients = await self.clients.matchAll({ type: 'window' });
		for (const client of clients) {
			client.navigate(client.url);
		}
	})());
});
