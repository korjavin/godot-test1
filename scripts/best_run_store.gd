extends Node
class_name BestRunStore
## Where the personal best-run records live, and how they reach the lobby.
##
## Two layers, and the split is the whole point:
##
##   * LOCAL — a `ConfigFile` at `user://best_run.cfg` on desktop, and
##     `window.localStorage` **on web**.
##
##     MEASURED, because the obvious story turned out to be wrong: `user://` on
##     the web export IS a working IndexedDB mount. Driven headless against the
##     deployed build, a record written at game over reached IndexedDB, came back
##     across a reload, and correctly suppressed the "NEW BEST!" flash — in
##     Chromium AND in WebKit. So the reported "every run flashes NEW BEST" is
##     **not** this code path failing; it is site storage not surviving in the
##     reporter's browser (Safari/iOS purges IndexedDB for sites without recent
##     interaction, a private window keeps none of it, and GitHub Pages vs the
##     deployment host are two different origins with two different stores) —
##     which is exactly the class of failure only a server-side store can fix.
##
##     localStorage is still the better local half, for two reasons that survive
##     that finding: the player id has to live there anyway (nothing else on web
##     is both synchronous and readable before the engine's first frame), and
##     `setItem` has committed when it returns, whereas an IndexedDB write is
##     flushed a frame or more later — a tab closed inside that window loses it.
##     A pre-existing `user://` record is still READ on web, so nobody's stored
##     best is thrown away by the switch; see `_read_local`.
##
##   * SERVER — `GET`/`POST <lobby>/best?id=<player id>` on the same Go lobby the
##     multiplayer code already talks to (`server/best.go`). It is the
##     owner-chosen fix, and what it actually buys is that a record survives the
##     browser throwing site storage away. Every failure is silent and non-fatal:
##     the local layer has already answered, so a lobby that is down, old, or
##     blocked by CORS costs nothing but the server half.
##
##     **CEILING — "follows you between devices" means devices that SHARE THE ID,
##     and nothing here transfers one.** The id is minted per browser profile and
##     per install, so a second device starts a fresh record; wiping localStorage
##     *and* `user://` on the one device orphans the old record too (it stays on
##     the server, unreachable, until the cap evicts it). That is the bead's own
##     design — this game has no accounts and the owner scoped the acceptance to
##     "devices sharing the player id". `ponytail:` the upgrade path was showing
##     the id somewhere the player can copy it and accepting a pasted one —
##     SHIPPED as `adopt_player_id()` below plus the MP panel's Sync section
##     (bead godot-test1-i8yu.6); a real login is still the one after that.
##
## RECORDS ONLY EVER GO UP, on both layers and on the server. That is what makes
## the ordering irrelevant: `loaded` fires once with the local values (inside
## `fetch()`, synchronously) and possibly again when the server answers with
## better ones, and the player folds each in with `maxi`. A late reply cannot
## lower anything, a lost reply costs nothing, and a retried POST is idempotent.
##
## Deliberately NOT here: a leaderboard (owner: personal bests only), any
## authentication (see `server/best.go`'s trust-model note), and any retry timer —
## the next game over posts again.
##
## THE SAVE SLOT RIDES `/save` BESIDE `/best` (epic godot-test1-i8yu, bead .5) —
## and a save is NOT a record, so the monotone rule above does NOT cover it. The
## two copies reconcile by `saved_at`, LAST-WRITE-WINS:
##
##   * BOOT: `fetch()` also GETs `/save?id=`; a server blob decoding valid whose
##     `saved_at` is NEWER than the local slot's (or the slot is empty) replaces
##     it and emits `save_loaded` once, so the start card can flip PLAY to
##     CONTINUE while it still shows. A server copy OLDER than (or equal to)
##     local is ignored — and the next write pushes ours, so there is no
##     catch-up POST at boot.
##   * WRITE: `push_save_slot()` (asked by `player_controller.write_save()` after
##     its change gate) POSTs the slot's own blob under the slot's own stamp —
##     never `now`, or every POST would outbid a newer server copy instead of
##     learning it. The server answers LWW, and a reply NEWER than what was sent
##     (another device wrote meanwhile) is adopted locally, silently — do not
##     fight. `clear_save_slot()` sends the DELETE verb the same way.
##   * Every failure silent and non-fatal, exactly like `/best`: the local layer
##     has already answered. No retry timer either — the next checkpoint posts
##     again, which bounds a moving player at 4 POSTs/min through .2's
##     change-gated 15 s tick (a standing player posts nothing).
##   * In a room writes still happen (the slot carries the room's seed — epic
##     rule); reads never apply mid-run — only `continue_save()` reads the slot,
##     and it refuses in a room.
##
## The wire shape is the server's (`server/save.go`): GET answers
## `{"blob":s,"saved_at":N}` (zeroes when unknown), POST takes
## `{"blob":s,"saved_at":N}` and answers the record to trust (the stored one on
## a stale write), an empty POST blob clears, DELETE clears. The BLOB is opaque
## here — `SaveState.decode` is the ONLY gate (malformed, v=2 and oversize all
## read as no-save); the envelope stamp is never trusted. A POST racing the boot
## GET cannot corrupt it: adoption needs a STRICTLY newer stamp, so our own echo
## (equal stamp) is ignored.
## SIGNED-IN IDENTITY (epic godot-test1-i8yu, bead .7): the session is the
## lobby's proof that this browser verified an email — 64 hex minted
## server-side, kept beside the player id in BOTH local layers (`ck_session` /
## `[player]` session, the typed address in `ck_session_email` /
## `[player]` email), and carried as `X-Session` on every /best and /save
## request. `player_id()` stays the anon id and is STILL SENT as `?id=`: the
## SERVER resolves the two (the first authed request links anon -> sub), so
## the client never merges, never computes, never shows anything but the typed
## address. The redirect/reload of the tab is acceptable ONLY because .2's
## close-write saved the slot first and .5's boot GET brings the server copy
## back. Ceiling: 30-day fixed expiry, web only — a 401 signs out and says
## why, and the next link starts over. Against a lobby without /auth/* the
## flow degrades to anonymous: the header is absent, the take is "", a send
## refuses honestly with "Cannot reach the lobby".
##
##
## IT ALSO CARRIES THE META-PROGRESSION COUNTERS (`lifetime_coins` /
## `spent_points`), and that is reuse rather than scope creep: they are keyed by
## the same player id, want the same monotone merge, the same local layers and the
## same silent-failure rule, so a store of their own would have been this file
## twice plus a second `/best`-shaped route (and a second entry in the Traefik
## path rule in `server/docker-compose.yml`). They ride the SAME record on the
## server — see `server/best.go`. `scripts/progression.gd` owns what they MEAN;
## this file only knows they are two numbers that never go down.
##
## THE PER-HERO SKILL RANKS (`skill_ranks`) ride the LOCAL layer AND NOTHING
## ELSE, and that asymmetry with the two counters beside them is deliberate:
##
##   * `spent_points` — a scalar that only ever rises — stays the whole of the
##     progression surface the server sees, so `server/best.go` needed no change,
##     no new route appeared, and the Traefik path rule in
##     `server/docker-compose.yml` stayed as it was. A dict of dicts on the wire
##     would need a schema plus a per-entry merge rule on the Go side to keep the
##     monotone guarantee that makes every POST idempotent.
##   * The ranks merge **per entry with `maxi`** (`merge_ranks()`), which is the
##     same monotone rule one dimension down, and is exactly right because v1 has
##     no respec: a rank never falls, so a stale local copy can only ever be
##     behind and merging can only ever be correct.
##   * The ceiling, stated plainly: a device that somehow learns a HIGHER
##     `spent_points` from the server than its own rank map accounts for has
##     fewer points to spend and no extra ranks. `unspent_points()`'s `maxi(0, …)`
##     absorbs it. Never a free rank, never a negative count — the safe
##     direction, and unreachable in practice for the same reason the record
##     "follows you between devices" ceiling above is: the player id is minted per
##     browser profile and per install, so two devices are two profiles.

# =============================================================================
# CONFIGURATION
# =============================================================================

## Desktop persistence. Kept at the path (and section) `player_controller.gd`
## already used, so an existing desktop record survives this change.
##
## STATIC AND WRITABLE PURELY AS A TEST SEAM, and nothing in the game ever
## assigns it — the running game always uses the default. A self-check cannot
## assert against this file: every write here is a monotone read-modify-write
## merge (see `_write_local`), so a check that stores 1234 into a developer's
## real profile reads back whatever larger number that profile already held.
## Backing the file up and putting it back does not fix that — the merge happens
## while the check is running — and it puts a real record one crashed assertion
## away from being lost. So a check points this at a throwaway path for its
## duration instead; `progression_selfcheck.gd` and `best_run_e2e.gd` both do.
## Static rather than per-instance so ONE assignment covers every store the run
## builds, including the one `player_controller._ready()` makes for itself.
static var config_path: String = "user://best_run.cfg"

## Lobby origin override. Empty (the game) means `LobbyClient.http_url()` with
## the whole `--lobby=` / `?lobby=` / export / default precedence; a self-check
## points it at a stub URL that refuses connections, so the whole sync half
## runs hermetically — fake replies are fed through the `_on_save_*_completed`
## handlers directly. Static and writable purely as a test seam, like
## `config_path` above; nothing in the game ever assigns it.
static var lobby_url_override: String = ""
const CONFIG_SECTION: String = "best"
const CONFIG_PLAYER_SECTION: String = "player"

## Web persistence: `localStorage` keys. Prefixed because the origin is shared
## with whatever else is served from it.
const LS_PLAYER_ID: String = "ck_player_id"
const LS_DISTANCE: String = "ck_best_distance"
const LS_COINS: String = "ck_best_coins"
const LS_HAS_WON: String = "ck_has_won"
const LS_LANDMARKS_BEST: String = "ck_landmarks_best"
const LS_LIFETIME: String = "ck_lifetime_coins"
const LS_SPENT: String = "ck_spent_points"
## The per-hero skill ranks, as a JSON object. JSON on BOTH layers (rather than a
## ConfigFile-native Dictionary on desktop) so there is one parse path to get
## wrong instead of two, and so a hand-edited or truncated value fails the same
## way everywhere: it is ignored and the ranks stay as they were.
const LS_RANKS: String = "ck_skill_ranks"

const CONFIG_RECORD_HAS_WON: String = "has_won"
const CONFIG_RECORD_LANDMARKS_BEST: String = "landmarks_best"

## Desktop section for the progression counters. A section of its own so a
## player's meta-progression is legible in `best_run.cfg` and so deleting it by
## hand (the bead's "clean profile" case) does not touch their best run.
const CONFIG_PROGRESSION_SECTION: String = "progression"

## Desktop section and localStorage key for voice chat mode (bead godot-test1-xtr.2).
const CONFIG_VOICE_SECTION: String = "voice"
const LS_VOICE_MODE: String = "ck_voice_mode"
## Incoming voice volume, an integer percent 0-100 (bead godot-test1-xtr.9). It
## shares the section above rather than opening a third `user://` path, which
## `progression_selfcheck`'s hermetic_stores audit would fail.
const LS_VOICE_VOLUME: String = "ck_voice_volume"


## Desktop section for THE TOWER'S EARNED STATE — one monotone set of ids (see
## the tower block further down). A section of its own for the same two reasons
## the progression one has one: it is legible in the file, and deleting it by
## hand resets the tower without touching a best run or a level.
##
## `ponytail:` THE PER-WORLD SAVE MODEL IS A SEPARATE, LARGER EPIC — session-03
## of the tower epic (godot-test1-3iy) identified it, and NEW GAME BEHAVIOUR IS
## EXPLICITLY OUT OF SCOPE HERE. So today there is exactly one record and
## `endless_terrain.new_run()` does not clear it: a new run moves the tower's
## SITE and rebuilds the shell, and the rebuilt shell hydrates the same earned
## set — deliberately, and on the same footing as the meta-progression counters
## above, which are run-independent for the same reason.
##
## WITH ONE CARVE-OUT: the lift's visited landings (bead godot-test1-4ban, owner
## ruling 2026-09-16). Those ids ride the shell's opened set like a gate does, but
## they are PER-RUN — a new run offers only the ground floor — so they are the one
## thing this section declines to store. `_sanitize_tower_ids` drops them at both
## ends and `TowerGraph.is_lift_stop_id()` is the whole of the rule. Gates, scars,
## the checkpoint and the rescue are untouched and still persist.
##
## The epic slots in AROUND this record without touching the set semantics: a
## save id becomes a second key in this section, or a section suffix, and each
## save gets its own union-merged set. Nothing below needs to know that happened
## — which is the point of putting the whole thing in one section behind two
## functions.
const CONFIG_TOWER_SECTION: String = "tower"
const CONFIG_TOWER_KEY: String = "opened_ids"

## Desktop section and localStorage key for THE DISCOVERY PASSPORT's found set
## (bead godot-test1-0bnw.1) — one monotone union of field-landmark ids, on the
## tower set's footing: run-independent, never cleared by new_game(), and read
## with the same silent-failure rule. BOTH local layers, unlike the tower set:
## cfg `[passport] found` on desktop, and on web `ck_found_landmarks` in
## localStorage — the banner's measured reason for localStorage (setItem has
## committed when it returns) applies to a stamp earned a second before the tab
## closes. On web BOTH are read (the one-way migration idiom) and LS is written.
const CONFIG_PASSPORT_SECTION: String = "passport"
const CONFIG_PASSPORT_KEY: String = "found"
const LS_FOUND: String = "ck_found_landmarks"

## Hard bound on the stored passport set, at BOTH ends. Same discipline as
## MAX_TOWER_IDS: the 48 field kinds need less than half of this, so 128 is
## headroom against a hand-edited dump, not a limit on discovery.
const MAX_FOUND_IDS: int = 128

## Monotone generation counter for the passport found set (bead godot-test1-nufd
## round 2): bumped ONLY when the stored set actually grows, so an in-memory
## mirror can tell "changed since I last looked" off one integer compare and
## re-read the file only then — never per tick. Not persisted and not merged:
## a relaunch re-hydrates from the file anyway, which is newer than any count.
static var found_version: int = 0

## A passport id is the registry builder minus `_landmark_` — lowercase ASCII,
## digits and underscores — and the store holds the line at 32 characters.
const FOUND_ID_PATTERN: String = "^[a-z0-9_]{1,32}$"
static var _found_id_rx: RegEx = null

## THE WORLD ARCHIVE — the full-custody protocol's failure record (phase 11).
##
## `[world] archived = true` and nothing else. Its own section, and the choice of
## home is the whole design decision, so it is written down rather than implied:
##
##   * NOT the tower's opened set above, even though it sits one section away. That
##     set is a monotone UNION with no removal verb, by design — and this latch has
##     to be CLEARED, because New Game is what un-ends a campaign. A latch that can
##     go backwards does not belong in a union, which is the same rule that keeps
##     the captive set out of it (`player_controller.captive_heroes`).
##   * NOT nowhere, which is where the tower guards live: a campaign that ended
##     must still be over after a relaunch. That is the entire feature — Continue
##     reopens the ending screen.
##
## `ponytail:` THE PER-WORLD SAVE ID IS STILL THE SEPARATE, LARGER EPIC the tower
## section above declined to entangle with, and it has not landed. So today there
## is one world, `new_game()` clears the latch, and that IS "New Game mints a fresh
## save id" with one slot. The epic slots in around this exactly as it does around
## the tower set: the id becomes a second key here or a section suffix, `new_game()`
## mints it instead of clearing, and no caller below or above changes.
const CONFIG_WORLD_SECTION: String = "world"
const CONFIG_WORLD_ARCHIVED: String = "archived"

## THE BROWSER/DESKTOP SAVE SLOT (epic godot-test1-i8yu, bead .2) - ONE string:
## cfg `[save] slot` on desktop, `ck_save` in localStorage on web. Deliberately
## inside the existing file: the tower section's banner reserved exactly this (a
## second key or a section suffix), so no third `user://` path and the hermetic
## audits (`Sentinel.REAL_PATHS`, `progression_selfcheck`) stay untouched. Same
## read-modify-write every other write uses; on web LS is written (setItem has
## committed when it returns) and BOTH layers are read, so a pre-switch cfg
## record is kept (the passport's one-way migration idiom).
##
## PLAIN OVERWRITE, no merge - the file's FIRST non-monotone field after the
## archive latch, and that is right because a save goes backwards by design: a
## checkpoint after coins were spent, or after a captive was freed, holds LESS
## than the checkpoint before it. Last-write-wins by `saved_at`; an ended
## campaign (`archive_world()`) and a fresh one (`new_game()`) clear it, so a
## run never resurrects captives across runs.
const CONFIG_SAVE_SECTION: String = "save"
const CONFIG_SAVE_KEY: String = "slot"
const LS_SAVE: String = "ck_save"

## Hard bound on the stored tower set, at BOTH ends — what is written and what is
## accepted back. The same discipline (and the same reason) as
## `MpCodec.MAX_STATE_IDS`: this exists to keep a corrupt or hand-edited file
## from being walked without limit, not to police how much of the tower a player
## may open. The whole authored building is a dozen ids (`tower_graph.gd`), so
## 256 is two orders of headroom and still a bound.
const MAX_TOWER_IDS: int = 256

## The player id is 128 random bits as 32 hex characters — inside the lobby's
## `^[A-Za-z0-9_-]{8,64}$` guard, and wide enough that guessing somebody else's
## is the only attack and it does not work.
const PLAYER_ID_HEX_LEN: int = 32

## The id's EXACT shape: 32 hex digits, upper- or lower-case, nothing else — in
## particular no sign. `String.is_valid_hex_number()` accepts a leading `+`/`-`,
## so a signed 32-char string used to validate AND persist as an id the lobby's
## `playerIDRe` then rejected on every request, killing sync until a valid code
## was adopted (send-back round 1). The mint path shares the validator below, so
## both tightened together; minted ids are `%08x` lowercase and always match.
const PLAYER_ID_PATTERN: String = "^[0-9a-fA-F]{32}$"

## The session's two local keys (bead `godot-test1-i8yu.7.2`): `localStorage`
## on web, `[player]` in the cfg everywhere — the same section as the id, no
## new section and no new user:// path, so the hermetic audit in
## `progression_selfcheck` and `Sentinel.REAL_PATHS` need no change.
const LS_SESSION: String = "ck_session"
const LS_SESSION_EMAIL: String = "ck_session_email"

## The session token's EXACT shape: 32 random bytes as 64 lowercase hex, minted
## server-side (`server/auth.go`'s `tokenRe`). Anything else reads as signed
## out — and is cleared from both layers, the re-mint idiom.
const SESSION_PATTERN: String = "^[0-9a-f]{64}$"

## The header every /best and /save request carries while signed in.
const SESSION_HEADER: String = "X-Session"

## The longest address the client sends: the server's `maxEmailLen`, so a
## longer typed address is refused HERE instead of 400ing a request for it.
const MAX_EMAIL_LEN: int = 254

## The URL-hash take, as one JS string (bead `godot-test1-i8yu.7.2`): read
## `session=<64 hex>` off `location.hash`, strip the hash in the SAME call
## with `history.replaceState` so a later `location.reload()`
## (`build_version.gd`) cannot replay it, and answer the session or "". A
## STRING either way, never a boolean — the bridge corrupts booleans into dead
## Variants, and `intro_selfcheck`'s all-scripts scan covers this const.
const URL_SESSION_SNIPPET: String = "(function(){try{var m=(location.hash||'').match(/session=([0-9a-f]{64})/);if(!m){return '';}history.replaceState(null,'',location.pathname+location.search);return m[1];}catch(e){return '';}})()"

## `HTTPRequest`'s default timeout is *wait forever*, and a stuck request makes
## every later one on that node answer ERR_BUSY — the trap `lobby_client.gd`
## documents at length. Short, because nothing waits on these.
const REQUEST_TIMEOUT_SEC: float = 5.0

# =============================================================================
# SIGNALS
# =============================================================================

## Best-known records. May fire more than once (local first, then the server if
## it knows better); the values only ever rise.
signal loaded(distance: int, coins: int)

## Best-known progression counters. Same contract as `loaded`: fires once with
## the local values inside `fetch()`, and again only if the server knew better.
## The values only ever rise, so a listener folds each in with `maxi`.
signal progression_loaded(lifetime_coins: int, spent_points: int)

## The cloud slot adopted a server-newer copy at boot. Fires at most once per
## adopted reply — never for an older/equal/malformed reply, never on the write
## path (an adoption there stays silent, so the card cannot flip mid-run). The
## start card listens while it still shows and flips PLAY to CONTINUE; a late
## listener re-reads through `save_slot()` / `has_save()`.
signal save_loaded

## The sign-in state moved: (true, "") on adoption, (false, why) on sign-out —
## the why names the cause (the 401 text, or "" for a deliberate sign-out) so
## the panel can say it where the player reads send outcomes too.
signal session_changed(signed_in: bool, why: String)

## The /auth/magic reply: (true, "") when the link is on its way, (false, why)
## otherwise — why is the server's error text, or the transport text when the
## lobby never answered. Emitted synchronously off the request call for a
## refused address (nothing is sent), async off the reply otherwise.
signal magic_link_sent(ok: bool, why: String)


# =============================================================================
# STATE
# =============================================================================

## Best known to this store. Public so a caller can read them without waiting.
var distance: int = 0
var coins: int = 0

## The coins record THE SERVER REPORTED, kept PRE-MERGE and deliberately
## beside `coins` rather than folded into it. `coins` is the merged best
## and includes this session's own `submit()`s, so it cannot answer the one
## question the "NEW BEST!" flash needs — "was there already a record this run
## had to beat" — because by then an echo of our own bank and a record another
## device holds are the same number. This one is only ever written from a GET
## reply, so it is that other device's number and nothing else.
##
## Stays 0 while the lobby is unreachable, which reads as "no external record"
## and leaves the caller's local comparison standing.
var server_best_coins: int = 0
var server_best_distance: int = 0

## Meta-progression, same monotone rule. `lifetime_coins` is cumulative coins
## picked up across every run ever and is NEVER deducted (owner, 2026-08-25);
## spending a skill point raises `spent_points` instead. The LEVEL is not stored
## anywhere — `progression.gd` derives it from `lifetime_coins`, so a stored level
## cannot drift from the count that produced it.
var lifetime_coins: int = 0
var spent_points: int = 0

## Win state (OR-merged) and best landmark count (max-merged) for Budapest escape.
var has_won: bool = false
var landmarks_best: int = 0

## Per-hero skill ranks (`hero → { skill id: rank }`), LOCAL LAYER ONLY — see the
## header for why they never reach the server. Merged, never assigned.
var skill_ranks: Dictionary = {}

var _player_id: String = ""

## An adoption whose fetch found the GET node busy (the boot fetch still in
## flight, or two adopts back to back): the adopted id's GET never started, so
## this remembers it across the in-flight request. `_request_get()` clears it
## the moment a GET actually starts; `_on_get_completed()` spends it on exactly
## one retry. Never armed by anything but `adopt_player_id()`, so an ordinary
## overlap retries nothing.
var _adopt_refetch_pending: bool = false

## Live instances for static-origin verbs. `write_save_slot()` stays
## instance-free (its one production writer asks its owned store to push), but
## `clear_save_slot()` originates in static contexts with no owner in scope
## (`archive_world()`, `new_game()`, the start card's NEW GAME) — so the clear
## verb fans out to every live in-tree instance. Weakrefs, pruned on every use;
## the local layer is always cleared first, so a fan-out to nobody still
## cleared the slot.
static var _save_sync_live: Array = []


func _init() -> void:
	_save_sync_live.append(weakref(self))


## Drop dead instance refs. Cheap enough to run on every use.
static func _prune_save_sync_live() -> void:
	var kept: Array = []
	for ref: WeakRef in _save_sync_live:
		if ref.get_ref() != null:
			kept.append(ref)
	_save_sync_live = kept

## Two `HTTPRequest` nodes, deliberately — one node answers ERR_BUSY while a
## request is in flight, and the boot GET can still be running when a very short
## first run ends. Same reasoning (and the same fix) as `lobby_client.gd`'s
## `_http` / `_rooms_http` split.
var _get_http: HTTPRequest = null
var _post_http: HTTPRequest = null

## The save slot's own GET/POST pair, deliberately — the boot GET and a
## checkpoint POST overlap exactly the way `/best`'s do, so sharing `/best`'s
## nodes would ERR_BUSY-drop one of them. Same timeout, same silent rule.
var _save_get_http: HTTPRequest = null
var _save_post_http: HTTPRequest = null

## The clear's own node (round 1: the DELETE reused the POST node and died on
## ERR_BUSY behind every checkpoint push — node-per-verb, as `/best`'s split).
var _save_delete_http: HTTPRequest = null

## The last save verb this instance STARTED ("GET", "POST", "DELETE" for the
## clear effect, "" when none): observability for `save_selfcheck`, which pins
## that fetch GETs, a push POSTs and a clear DELETEs. Recorded only when
## `request()` accepted the request — a refused lobby still records it (the
## request starts, then fails async), while an ERR_BUSY overlap records nothing.
var _last_save_verb: String = ""

## The `saved_at` the in-flight save POST carried. A reply adopts only when
## NEWER than this — never than the live slot, which a checkpoint may have
## advanced meanwhile.
var _save_post_sent_at: int = 0

## The exact headers the last request STARTED with, per instance: observability
## for `save_selfcheck`, beside `_last_save_verb` and with its rule — recorded
## only when `request()` accepted the request, so the spy pins the bearer the
## lobby actually received instead of the intent.
var _last_request_headers: PackedStringArray = []

## The auth verbs' own node (bead `godot-test1-i8yu.7.2`): node-per-verb, as
## the save split — one node for BOTH auth verbs is fine, they never overlap in
## practice (a link is requested from a signed-out panel, a sign-out from a
## signed-in one), and sharing it with a record verb would ERR_BUSY-drop the
## link behind a checkpoint push. Same timeout, same silent rule.
var _auth_http: HTTPRequest = null

## The session token cache, read lazily like `_player_id`: "" is signed out —
## a fresh install, or a 401 since — and every verb sends `X-Session` while one
## is held, so anonymous traffic is byte-for-byte what it was before this ring
## existed. The token IS the session: the lobby minted it for the verified
## click, and the client never computes anything from it — it only carries it.
var _session_token: String = ""

## The address the player typed, CLIENT-SIDE ONLY: written to both layers by
## `request_magic_link()` on a valid address — never by a reply — so it
## survives the redirect/reload the verified click arrives on, and "" for a
## session with no request behind it. Shown, never sent (except in the one
## /auth/magic POST that asked for the link).
var _session_email: String = ""

## Whether the boot GET's reply may be trusted as a PRE-SUBMIT baseline — which is
## the only thing `server_best_distance` is for, and the one property the two
## `HTTPRequest` nodes above take away. They overlap on purpose (that is the whole
## reason for the split), the lobby serves them concurrently, and nothing orders
## them: a bite in the first seconds of a run POSTs this run's distance, and if
## that merge lands before the still-in-flight GET is read, the reply hands our
## OWN number back as if another device held it. The reconciliation then takes
## back a flash the player earned — exactly the echo the pre-merge field exists
## to be immune to.
##
## So a POST that actually started while the GET was outstanding retires the
## baseline. `server_best_distance` then stays 0, which is already the documented
## "no external record" degrade, and the local comparison stands — the safe
## direction, because the alternative claims a record on evidence we produced.
## The next boot's GET has no POST racing it and reports the truth.
var _get_in_flight: bool = false
var _get_baseline_ok: bool = false


# =============================================================================
# PUBLIC API
# =============================================================================

func fetch() -> void:
	"""
	Load the records. The local layer answers immediately (so a boot with no
	network behaves exactly as it always did), then the server is asked and may
	raise them.
	"""
	_read_local()
	loaded.emit(distance, coins)
	progression_loaded.emit(lifetime_coins, spent_points)
	# The verified click lands in the URL hash: take it BEFORE the boot GETs,
	# so the very first pair already runs under the session and the server
	# links anon -> sub on it. Quiet (no nested fetch) — the pair below is the
	# adoption's one GET pair.
	var fresh := take_session_from_url()
	if not fresh.is_empty():
		_adopt_session_quiet(fresh)
	_request_get()
	_request_save_get()


func submit(_new_distance: int, new_coins: int) -> void:
	"""
	Record a run's results. Called from `_trigger_game_over()` only when a record
	actually moved, so this is not a per-frame path.

	It re-reads the local store first so that a `submit()` without a preceding
	`fetch()` cannot LOWER a stored record — `coins` starts at 0, and a plain
	`_write_local()` off that would overwrite a real best with this run's number.
	One file open per game over, and it makes call order stop mattering.
	"""
	_read_local()
	coins = maxi(coins, new_coins)
	distance = 0
	_write_local()
	_request_post()


func submit_progression(
	new_lifetime: int, new_spent: int, new_ranks: Dictionary = {}
) -> void:
	"""
	Record the meta-progression counters. Called by `progression.gd` on a level-up,
	at game over, and on every skill point spent — not a per-pickup path.

	`new_ranks` is a TRAILING parameter defaulting to {}, so the pre-skill-tree
	call shape stays inert (an empty merge changes nothing); the ranks are merged
	per entry, never assigned, for the monotone reason in the header.

	Same shape and same reasoning as `submit()`, including the `_read_local()`
	first: without it a store whose `fetch()` never ran would write its zeroes over
	a real lifetime total, which on this record is a player's LEVEL.

	A save landing while the previous POST is still in flight is answered ERR_BUSY
	and dropped — a level-up followed closely by a game over is the realistic case.
	That costs only the SERVER half (the local layer is written above, before the
	request), and it is self-repairing rather than lost: the next boot's GET sees a
	server behind the local record and fires the catch-up POST for exactly this.
	"""
	_read_local()
	lifetime_coins = maxi(lifetime_coins, new_lifetime)
	spent_points = maxi(spent_points, new_spent)
	merge_ranks(skill_ranks, new_ranks)
	_write_local()
	_request_post()


func player_id() -> String:
	"""
	This player's persistent id, generated once and kept in the same local store
	as the records. Empty only when the store is unwritable (a private window
	with `localStorage` disabled), in which case the server half is simply
	skipped — see `_request_get`.
	"""
	if _player_id.is_empty():
		_player_id = _load_or_make_player_id()
	return _player_id


static func is_valid_player_id(code: String) -> bool:
	"""
	Whether `code` is shaped like a player id: 32 hex characters.

	The re-mint rule `_load_or_make_player_id()` already enforces, factored out
	so the mint path and the claim path (`adopt_player_id()`) cannot drift
	apart — the lobby refuses anything else, so a second spelling of "valid"
	is a second outage. Strictly `PLAYER_ID_PATTERN`, never the engine's
	`is_valid_hex_number()` (see that const for why the engine spelling lies).
	"""
	var shape := RegEx.create_from_string(PLAYER_ID_PATTERN)
	return shape != null and shape.search(code) != null


func adopt_player_id(code: String) -> bool:
	"""
	Adopt a pasted claim code as this profile's player id (bead godot-test1-i8yu.6).

	The code may carry the display separators (`mp_ui.gd` shows groups of four)
	and any casing; both are normalized away, and anything that is not then a
	valid id is refused WITHOUT changing anything — no layer written,
	`_player_id` untouched, no request made.

	On acceptance BOTH local layers are written — the `localStorage` key AND the
	ConfigFile `[player]` id, on every platform (the migration idiom in
	`_load_or_make_player_id()` reads both, so both must agree) — `_player_id`
	is set, and `fetch()` runs once so the adopted id's records merge in through
	the ordinary monotone path. The saved game follows the same rule once its
	own boot load lands (epic godot-test1-i8yu).
	"""
	var cleaned: String = code.strip_edges().to_lower()
	for separator: String in [" ", "\t", "\n", "\r", "-"]:
		cleaned = cleaned.replace(separator, "")
	if not is_valid_player_id(cleaned):
		return false
	_ls_set(LS_PLAYER_ID, cleaned)
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep every other section intact
	cfg.set_value(CONFIG_PLAYER_SECTION, "id", cleaned)
	cfg.save(config_path)
	_player_id = cleaned
	# Armed until the adoption's GET actually starts (see `_request_get`): if the
	# boot fetch is still in flight, this fetch's GET is dropped on ERR_BUSY and
	# the flag buys it one retry when that GET completes (see `_on_get_completed`).
	_adopt_refetch_pending = true
	fetch()
	return true


# =============================================================================
# LOCAL LAYER
# =============================================================================

func _read_local() -> void:
	"""
	Raise the in-memory records from the local store.

	The ConfigFile is read on EVERY platform, web included, and that is the
	one-way migration: a web player who already has a record in the old
	`user://best_run.cfg` keeps it, and the next `_write_local()` mirrors it into
	localStorage. Reading both costs one file open at boot and means the switch
	throws nobody's best away.
	"""
	if OS.has_feature("web"):
		coins = maxi(coins, maxi(0, _ls_get(LS_COINS).to_int()))
		lifetime_coins = maxi(lifetime_coins, maxi(0, _ls_get(LS_LIFETIME).to_int()))
		spent_points = maxi(spent_points, maxi(0, _ls_get(LS_SPENT).to_int()))
		has_won = has_won or (_ls_get(LS_HAS_WON) == "1" or _ls_get(LS_HAS_WON) == "true")
		landmarks_best = maxi(landmarks_best, maxi(0, _ls_get(LS_LANDMARKS_BEST).to_int()))
		merge_ranks(skill_ranks, _parse_ranks(_ls_get(LS_RANKS)))
	var cfg := ConfigFile.new()
	# A missing file (first ever run) is NOT an error — the zero defaults stand.
	# That is also the bead's "delete the file, get a clean level-0 profile" case.
	if cfg.load(config_path) != OK:
		return
	coins = maxi(coins, maxi(0, int(cfg.get_value(CONFIG_SECTION, "coins", 0))))
	has_won = has_won or bool(cfg.get_value(CONFIG_SECTION, CONFIG_RECORD_HAS_WON, false))
	landmarks_best = maxi(
		landmarks_best,
		maxi(0, int(cfg.get_value(CONFIG_SECTION, CONFIG_RECORD_LANDMARKS_BEST, 0)))
	)
	lifetime_coins = maxi(
		lifetime_coins,
		maxi(0, int(cfg.get_value(CONFIG_PROGRESSION_SECTION, "lifetime_coins", 0)))
	)
	spent_points = maxi(
		spent_points,
		maxi(0, int(cfg.get_value(CONFIG_PROGRESSION_SECTION, "spent_points", 0)))
	)
	merge_ranks(
		skill_ranks,
		_parse_ranks(String(cfg.get_value(CONFIG_PROGRESSION_SECTION, "skill_ranks", "")))
	)


func _write_local() -> void:
	"""
	Persist the records (and the player id, which shares the store). Failures are
	ignored: an unpersisted record is non-fatal and must never interrupt the
	game-over flow.

	EVERY WRITE IS A READ-MODIFY-WRITE MERGE, and that is what makes two stores on
	one file safe. A store serializes ALL its fields, but it only ever *changes*
	the two it was told about — the other pair is whatever it happened to read at
	boot. So without the `_read_local()` below, the player's store mirroring a
	late GET reply would write its boot-time `lifetime_coins` over a level the
	player earned in between (and the progression store would do the same to a
	fresh best run). Reading first makes the write a merge instead of an
	overwrite: `_read_local()` only ever raises, so this cannot lower anything,
	and the cost is one file open on a path that runs at a level-up and a game
	over, never per frame.
	"""
	_read_local()
	if OS.has_feature("web"):
		_ls_set(LS_DISTANCE, "0")
		_ls_set(LS_COINS, str(coins))
		_ls_set(LS_HAS_WON, "1" if has_won else "0")
		_ls_set(LS_LANDMARKS_BEST, str(landmarks_best))
		_ls_set(LS_LIFETIME, str(lifetime_coins))
		_ls_set(LS_SPENT, str(spent_points))
		_ls_set(LS_RANKS, JSON.stringify(skill_ranks))
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep any other section (the player id) intact
	cfg.set_value(CONFIG_SECTION, "distance", 0)
	cfg.set_value(CONFIG_SECTION, "coins", coins)
	cfg.set_value(CONFIG_SECTION, CONFIG_RECORD_HAS_WON, has_won)
	cfg.set_value(CONFIG_SECTION, CONFIG_RECORD_LANDMARKS_BEST, landmarks_best)
	cfg.set_value(CONFIG_PROGRESSION_SECTION, "lifetime_coins", lifetime_coins)
	cfg.set_value(CONFIG_PROGRESSION_SECTION, "spent_points", spent_points)
	cfg.set_value(CONFIG_PROGRESSION_SECTION, "skill_ranks", JSON.stringify(skill_ranks))
	cfg.save(config_path)


func record_win() -> void:
	"""Record that the player has won the game: OR-merged so a win is never lost."""
	has_won = true
	_write_local()


func submit_landmarks(count: int) -> void:
	"""Record explored landmark count: max-merged."""
	landmarks_best = maxi(landmarks_best, count)
	_write_local()


# =============================================================================
# SKILL RANKS — the local-only third field (see the header)
# =============================================================================

static func merge_ranks(into: Dictionary, from: Dictionary) -> void:
	"""
	Fold `from` into `into` with a per-entry `maxi`, in place.

	The same monotone rule the scalars use, one dimension down: because there is
	no respec, a rank never falls, so the higher of two copies is always the newer
	one and ordering stops mattering — a late load, a re-read before a write and a
	retried save are all idempotent.

	Every level is type-checked because one source of `from` is parsed JSON out of
	`localStorage`, i.e. a string a player (or a broken write) can put anything in.
	A malformed hero or rank is skipped rather than rejecting the whole map: the
	rest of a player's tree is worth keeping.
	"""
	for hero: Variant in from:
		if typeof(hero) != TYPE_STRING or typeof(from[hero]) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = from[hero]
		var dst: Dictionary = into.get(hero, {})
		for skill_id: Variant in src:
			if typeof(skill_id) != TYPE_STRING:
				continue
			var rank: Variant = src[skill_id]
			if typeof(rank) != TYPE_INT and typeof(rank) != TYPE_FLOAT:
				continue
			dst[skill_id] = maxi(int(dst.get(skill_id, 0)), maxi(0, int(rank)))
		into[hero] = dst


static func _parse_ranks(raw: String) -> Dictionary:
	"""
	Decode a stored rank map. Anything that is not a JSON object reads as "no
	ranks stored", which is the correct answer for a missing key, an empty string
	and a corrupt value alike — and, thanks to the merge above, costs nothing when
	the other local layer still has them.
	"""
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


# =============================================================================
# THE TOWER'S EARNED STATE — a monotone set, merged by union
# =============================================================================
#
# WHY IT IS HERE AND NOT IN A STORE OF ITS OWN: exactly the reuse argument the
# header makes for the progression counters. It wants the same local file, the
# same read-modify-write merge and the same silent-failure rule, so a second
# store would have been this file again for one array.
#
# WHY IT IS STATIC AND INSTANCE-FREE: `tower_shell.gd` is a building, not a node
# that owns a player's records. It needs two calls — "what did I open before" and
# "remember I just opened this" — and neither wants an `HTTPRequest` pair, a
# player id or a `fetch()`. Both functions are complete round trips to the file.
#
# WHY THE UNION IS THE WHOLE MERGE RULE: a gate only ever OPENS, a stop only ever
# UNLOCKS, a stage only ever COMPLETES. The set can only grow, so the newer of
# two copies is the superset and `stored | ours` is always the right answer —
# which makes a stale copy harmless, a re-save idempotent and an interleaved
# write from a second instance a no-op rather than a rollback. It is the scalars'
# `maxi` one dimension up, and `merge_ranks`'s per-entry `maxi` one across.
#
# **A MET DEMAND GATE NEVER RE-LOCKS.** Earned progression must not become
# upkeep, so a demand gate's opened state is in this same set as an identity
# gate's, and nothing here can ever take an id back out.
#
# WHAT IS NEVER WRITTEN: anything that resets. Guards, alarms, loose objects and
# unfinished in-room puzzle configuration go nowhere near this — if it can go
# backwards it does not belong in a monotone set, and the tower rebuilds it from
# scratch every time it is streamed in.
#
# AND THE LIFT'S VISITED LANDINGS, which are the same rule seen from the other
# side (bead godot-test1-4ban): they only ever grow WITHIN a run, so they merge
# by union like everything else here, but a new run starts them empty again — so
# they reset, so they do not belong. They live in the shell, which the seed write
# frees, and `_sanitize_tower_ids` is what keeps them off this disk.
#
# V1 IS THE LOCAL LAYER ONLY. No `/best` POST: the lobby record is a scalar
# schema whose monotone merge lives in Go (`server/best.go`), and putting a set
# on that wire needs a merge rule on the server side, which is its own bead.
# `user://` is a working store on web too (the header measured it), so the one
# ceiling is the IndexedDB flush lag — a tab closed within a frame of opening a
# gate loses that gate, and re-opening it costs one walk.

static func tower_opened_ids() -> Array[String]:
	"""
	The tower ids this profile has already earned.

	@return: A fresh sorted Array of String — the caller may keep or mutate it.

	A missing file, a missing key, a truncated value or a hand-edited mess all
	read as "nothing opened yet", which is the correct answer for every one of
	them: the tower simply comes up shut and can be opened again. Every entry is
	type-checked and the count is bounded, because this is a file a player can
	edit.
	"""
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return []
	var raw := String(cfg.get_value(CONFIG_TOWER_SECTION, CONFIG_TOWER_KEY, ""))
	if raw.is_empty():
		return []
	# `JSON.new().parse()` rather than the `JSON.parse_string()` helper the ranks
	# use, for one reason: the helper PRINTS an engine error on malformed input,
	# and a truncated or hand-edited record is an expected state on this path, not
	# an incident. The check that exercises it should not have to print an ERROR
	# line in order to pass.
	var json := JSON.new()
	if json.parse(raw) != OK:
		return []
	return _sanitize_tower_ids(json.data)


static func merge_tower_opened_ids(ids: Array) -> void:
	"""
	Fold `ids` into the stored set and save it. The only writer.

	@param ids: The ids to add. Already-stored ones cost nothing.

	READ-MODIFY-WRITE, like every other write in this file — and here it is not
	only about the other sections: it is what makes the merge a UNION rather than
	an overwrite. Without the re-read, a shell hydrated from a stale copy (or one
	built before a second instance saved) would write its own smaller set over the
	larger one on disk, and a gate the player had earned would re-lock. That is
	the bug this whole shape exists to make impossible.

	Called on a gate OPENING and nowhere else — rare and precious, so it writes
	immediately rather than batching to some later flush that a crash eats.
	Failures are ignored, for the reason `_write_local` gives.
	"""
	var stored := tower_opened_ids()
	var merged := stored.duplicate()
	for id: Variant in ids:
		if merged.size() >= MAX_TOWER_IDS:
			break
		if typeof(id) == TYPE_STRING and not String(id).is_empty() and not merged.has(id):
			merged.append(String(id))
	# THE SAME FILTER ON THE WAY OUT (bead godot-test1-4ban). `_sanitize_tower_ids`
	# already dropped the lift's landings on the way IN, so routing the merged set
	# back through it does two things: a landing offered to `mark_opened` never
	# reaches the file, and any landing an OLDER build left on disk is physically
	# gone the next time a gate is earned — old profiles self-heal with no
	# migration step. It also sorts, which the write used to do itself.
	merged = _sanitize_tower_ids(merged)
	# NOTHING NEW, NOTHING WRITTEN. A lift-only merge sanitizes back to the set we
	# just loaded, and re-earning an id must not recreate a profile the player
	# deleted (the `tower_gate_sync_selfcheck` 13c idiom) — nor cost a ConfigFile
	# round trip on every landing walked.
	if merged == stored:
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep the records, the counters and the player id intact
	cfg.set_value(CONFIG_TOWER_SECTION, CONFIG_TOWER_KEY, JSON.stringify(merged))
	cfg.save(config_path)


static func _sanitize_tower_ids(parsed: Variant) -> Array[String]:
	"""
	Turn whatever came out of the store into a sorted, bounded Array of String.

	Anything that is not a JSON array is nothing; a non-string or empty entry is
	skipped rather than rejecting the whole set, for the same reason a malformed
	rank is skipped in `merge_ranks` — the rest of what a player earned is worth
	keeping. Duplicates collapse, because this is a SET.

	AND THE LIFT'S LANDINGS ARE DROPPED — the one id this file deliberately
	refuses to keep (bead godot-test1-4ban, owner ruling 2026-09-16). Every other
	merge in this store is max/union and nothing is ever taken away; this is the
	one carve-out, on the `captive_heroes` precedent: a set that is NOT monotone
	across runs has no business in a monotone store. The lift's memory of visited
	landings dies with the run, so it lives in the shell (which `_tower_reset()`
	frees on every seed write) and is room-shared while the run lasts. Run through
	both `tower_opened_ids()` and `merge_tower_opened_ids()`, so the filter holds
	at both ends and a profile written by an older build self-heals.
	"""
	var out: Array[String] = []
	if typeof(parsed) != TYPE_ARRAY:
		return out
	for id: Variant in parsed as Array:
		if out.size() >= MAX_TOWER_IDS:
			break
		if typeof(id) == TYPE_STRING and not String(id).is_empty() and not out.has(id) \
				and not TowerGraph.is_lift_stop_id(String(id)):
			out.append(String(id))
	out.sort()
	return out


# =============================================================================
# THE DISCOVERY PASSPORT — a monotone union of found field-landmark ids
# =============================================================================
#
# WHY IT IS HERE AND NOT IN A STORE OF ITS OWN: the tower set's reason, one
# dimension over — the same local file, the same read-modify-write merge, the
# same silent-failure rule, and (unlike the tower set) the same localStorage
# half the scalars use, because a stamp earned a second before the tab closes
# must already have committed.
#
# WHY IT IS STATIC AND INSTANCE-FREE: the tower set's reason again —
# `landmark_toast.gd` is a widget, not a node that owns records. It needs two
# calls, "what did I find before" and "remember I was just here", and neither
# wants an HTTPRequest pair, a player id or a fetch(). Both are complete round
# trips to the local layers.
#
# UNION ONLY, on every layer (child 2 adds the lobby `/best` one). A landmark
# only ever gets FOUND — there is no un-finding — so the newer of two copies is
# the superset and `stored | ours` is always the right answer. `new_game()`
# clears the world latch and nothing else, so the passport outlives the run the
# way the meta-progression counters do. No payout, no percentage: the panel
# counts, it never pays.

static func found_landmark_ids() -> Array[String]:
	"""
	The field-landmark ids this profile has ever found.

	@return: A fresh sorted Array of String — the caller may keep or mutate it.

	A missing file, a missing key, a truncated value or a hand-edited mess all
	read as "nothing found yet", for the tower set's reason: the passport
	simply opens empty and can be filled again. On web the localStorage layer
	is read FIRST and the cfg layer second, so a pre-switch record is kept
	(the one-way migration idiom) and the union of the two answers.
	"""
	var merged: Array[String] = []
	if OS.has_feature("web"):
		merged = _sanitize_found_ids(_parse_found_json(_ls_get(LS_FOUND)))
	var cfg := ConfigFile.new()
	if cfg.load(config_path) == OK:
		var raw := String(cfg.get_value(CONFIG_PASSPORT_SECTION, CONFIG_PASSPORT_KEY, ""))
		for id: String in _sanitize_found_ids(_parse_found_json(raw)):
			if not merged.has(id):
				merged.append(id)
	merged.sort()
	return merged


static func merge_found_landmark_ids(ids: Array) -> void:
	"""
	Fold `ids` into the stored found set and save it. The only writer.

	@param ids: The ids to add. Already-stored ones cost nothing.

	READ-MODIFY-WRITE, for the tower set's reason: without the re-read a toast
	hydrated from a stale copy would write its own smaller set over the larger
	one on disk, and a found landmark would un-find itself. Merged back through
	the sanitizer, so a profile written by an older build self-heals the same
	way the tower set does.

	Called on a run's first arrival at a field landmark and by the lobby fold —
	rare and precious either way, so it writes immediately rather than batching
	to a later flush that a crash eats. Failures are ignored, for `_write_local`'s
	reason.
	"""
	var stored := found_landmark_ids()
	var merged := stored.duplicate()
	for id: Variant in ids:
		if merged.size() >= MAX_FOUND_IDS:
			break
		# The `not merged.has(id)` guard is redundant defense: `_sanitize_found_ids`
		# below dedupes anyway, so dropping it changes nothing observable (a review
		# mutation proved it stays green). It stays because the tower set's merge
		# carries the same guard, and the raw stored layer should hold the union,
		# not the union plus the evidence of how many times it was merged.
		if typeof(id) == TYPE_STRING and _found_id_ok(String(id)) and not merged.has(id):
			merged.append(String(id))
	merged = _sanitize_found_ids(merged)
	# NOTHING NEW, NOTHING WRITTEN. Re-finding an id must not recreate a profile
	# the player deleted (the tower set's 13c idiom), nor cost a ConfigFile round
	# trip on every revisit.
	if merged == stored:
		return
	# The set grew: bump the generation so in-memory mirrors (the toast's
	# passport cache, bead godot-test1-nufd round 2) can see the change without
	# re-reading the file. Both writers — the arrival above and the lobby fold
	# below — pass through here, so one bump covers both.
	found_version += 1
	if OS.has_feature("web"):
		_ls_set(LS_FOUND, JSON.stringify(merged))
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep the records, the counters and the player id intact
	cfg.set_value(CONFIG_PASSPORT_SECTION, CONFIG_PASSPORT_KEY, JSON.stringify(merged))
	cfg.save(config_path)


static func _parse_found_json(raw: String) -> Variant:
	"""
	Decode one stored found layer. Anything that is not a JSON array reads as
	"nothing stored" — a missing key, an empty string and a corrupt value alike.
	"""
	if raw.is_empty():
		return []
	# `JSON.new().parse()` rather than `JSON.parse_string()`, for the tower
	# set's reason: a truncated or hand-edited record is an expected state on
	# this path, not an incident, and must not print an engine error.
	var json := JSON.new()
	if json.parse(raw) != OK:
		return []
	return json.data


static func _found_id_ok(id: String) -> bool:
	"""Whether `id` is shaped like a passport id (see FOUND_ID_PATTERN)."""
	if _found_id_rx == null:
		_found_id_rx = RegEx.new()
		_found_id_rx.compile(FOUND_ID_PATTERN)
	return _found_id_rx.search(id) != null


static func _sanitize_found_ids(parsed: Variant) -> Array[String]:
	"""
	Turn whatever came out of the store into a sorted, bounded Array of String.

	Anything that is not a JSON array is nothing; a non-string or misshapen
	entry is skipped rather than rejecting the whole set, for the tower set's
	reason — the rest of what a player found is worth keeping. Duplicates
	collapse, because this is a SET, and the 129th id is dropped, because a
	hand-edited dump is walked with a bound or not at all.
	"""
	var out: Array[String] = []
	if typeof(parsed) != TYPE_ARRAY:
		return out
	for id: Variant in parsed as Array:
		if out.size() >= MAX_FOUND_IDS:
			break
		if typeof(id) == TYPE_STRING and _found_id_ok(String(id)) and not out.has(String(id)):
			out.append(String(id))
	out.sort()
	return out


# =============================================================================
# THE WORLD ARCHIVE — read-only-save semantics for a campaign that ended
# =============================================================================
#
# Three lines of state and one rule: while the latch is set the world is finished,
# and the only thing that clears it is starting a new one. Read at boot by
# `player_controller`, which raises the ending screen instead of handing out a run.

const OUTCOME_CAPTURED: String = "captured"
const OUTCOME_WON: String = "won"

static func world_archived() -> bool:
	"""
	Has this world's campaign ended? False for a missing, unreadable, or active file.
	"""
	return not archived_outcome().is_empty()


static func archived_outcome() -> String:
	"""
	Return the archived outcome ("captured" or "won"), or "" if no world is archived.
	Handles legacy boolean `true` as "captured".
	"""
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return ""
	var val: Variant = cfg.get_value(CONFIG_WORLD_SECTION, CONFIG_WORLD_ARCHIVED, false)
	if typeof(val) == TYPE_STRING:
		return String(val)
	elif typeof(val) == TYPE_BOOL and bool(val):
		return OUTCOME_CAPTURED
	return ""


static func has_ever_won() -> bool:
	"""
	Has the player ever won? Reads local store.
	"""
	if OS.has_feature("web"):
		return _ls_get(LS_HAS_WON) == "1" or _ls_get(LS_HAS_WON) == "true"
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return false
	return bool(cfg.get_value(CONFIG_SECTION, CONFIG_RECORD_HAS_WON, false))


static func archive_world(outcome: String = OUTCOME_CAPTURED) -> void:
	"""
	End this world with the specified outcome ("captured" or "won").

	READ-MODIFY-WRITE like every other write in this file, so the records, the
	counters, the player id and the tower's opened set survive it — an archived
	world is still the profile that earned them.
	"""
	clear_save_slot()
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value(CONFIG_WORLD_SECTION, CONFIG_WORLD_ARCHIVED, outcome)
	cfg.save(config_path)


static func new_game() -> void:
	"""
	Start a fresh world: clear the archive latch.

	`ponytail:` one save slot, so "mint a fresh save id" is "clear the flag" — see
	the section constant for the epic this leaves room for. The ceiling is that a
	new game inherits the old world's earned tower set (gates AND scars), exactly as
	it already inherits the meta-progression counters; the save-id epic is what
	separates them, and it separates all three together or none.
	"""
	clear_save_slot()
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	cfg.set_value(CONFIG_WORLD_SECTION, CONFIG_WORLD_ARCHIVED, false)
	cfg.save(config_path)


# =============================================================================
# THE SAVE SLOT - one overwrite string (see the const banner above)
# =============================================================================

static func save_slot() -> String:
	"""
	The saved run, as the `SaveState` blob `write_save_slot()` stored - or ""
	when there is none (no save yet, cleared by `clear_save_slot()`, or a
	truncated/hand-edited value, which reads as no save for the tower set's
	reason: the run simply starts over and can save again).

	On web localStorage answers first (it is the write layer) and the cfg
	second, so a record stored before the localStorage switch is kept.
	"""
	if OS.has_feature("web"):
		var from_ls := _ls_get(LS_SAVE)
		if not from_ls.is_empty():
			return from_ls
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return ""
	return String(cfg.get_value(CONFIG_SAVE_SECTION, CONFIG_SAVE_KEY, ""))


static func write_save_slot(raw: String) -> void:
	"""
	Store `raw` as the saved run. PLAIN OVERWRITE - the one field in this file
	that is not merged, for the banner's reason: a save goes backwards.

	LOCAL ONLY: the POST rides separately through `push_save_slot()`, asked by
	the slot's one production writer (`player_controller.write_save()`, after its
	change gate) on the store node it owns. Kept apart so a lobby that is down
	cannot touch this path — the local answer is unconditional.

	@param raw: the canonical `SaveState.encode()` blob (about 200-400 bytes).
	"""
	_write_save_local(raw)


static func _write_save_local(raw: String) -> void:
	"""
	The local half of `write_save_slot()`, shared with the boot adoption in
	`_on_save_get_completed()` — which must NOT push back what it just learned,
	or every boot GET would echo into a write (and the next checkpoint carries
	ours anyway).
	"""
	if OS.has_feature("web"):
		_ls_set(LS_SAVE, raw)
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep the records, the counters and the player id intact
	cfg.set_value(CONFIG_SAVE_SECTION, CONFIG_SAVE_KEY, raw)
	cfg.save(config_path)


static func clear_save_slot() -> void:
	"""Forget the saved run. An ended campaign and a new game both come through
	here, so neither can resurrect the captives the save was stored with.

	The DELETE verb fans out to every live in-tree store (see
	`_save_sync_live`): an ended campaign that never writes again must still
	clear the server copy, or the next boot's GET would resurrect it onto
	another device. Local first, silent always — a fan-out to nobody still
	cleared the slot."""
	if OS.has_feature("web"):
		_ls_set(LS_SAVE, "")
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value(CONFIG_SAVE_SECTION, CONFIG_SAVE_KEY, "")
	cfg.save(config_path)
	_notify_save_cleared()


static func _notify_save_cleared() -> void:
	"""Send the clear verb on every live instance. Prunes dead refs as it goes."""
	_prune_save_sync_live()
	var kept: Array = []
	for ref: WeakRef in _save_sync_live:
		var inst := ref.get_ref() as BestRunStore
		if inst == null or not is_instance_valid(inst):
			continue
		kept.append(ref)
		if inst.is_inside_tree():
			# The GET first: a boot fetch still in flight must not resurrect
			# the slot just cleared (NEW GAME while the lobby is slow).
			inst._cancel_save_get()
			inst._request_save_delete()
	_save_sync_live = kept


func _cancel_save_get() -> void:
	"""Drop an in-flight cloud-slot GET, with its one-shot, so a late reply
	cannot land on a slot cleared after the request started."""
	if _save_get_http == null:
		return
	_save_get_http.cancel_request()
	if _save_get_http.request_completed.is_connected(_on_save_get_completed):
		_save_get_http.request_completed.disconnect(_on_save_get_completed)


func _load_or_make_player_id() -> String:
	"""Read the stored id, or mint and store a fresh one."""
	var stored := ""
	if OS.has_feature("web"):
		stored = _ls_get(LS_PLAYER_ID)
	if stored.is_empty():
		# Also the web migration path: an id already in the ConfigFile is reused
		# rather than replaced, so a player who has one keeps their server record.
		var cfg := ConfigFile.new()
		if cfg.load(config_path) == OK:
			stored = str(cfg.get_value(CONFIG_PLAYER_SECTION, "id", ""))
	# Re-mint anything the lobby would refuse, so a corrupted store self-heals
	# instead of 400ing every request for the rest of this install's life.
	# The shape itself is `is_valid_player_id()`, shared with `adopt_player_id()`.
	if is_valid_player_id(stored):
		return stored

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fresh := ""
	for _i in 4:
		fresh += "%08x" % rng.randi()

	if OS.has_feature("web"):
		_ls_set(LS_PLAYER_ID, fresh)
	else:
		var cfg := ConfigFile.new()
		cfg.load(config_path)
		cfg.set_value(CONFIG_PLAYER_SECTION, "id", fresh)
		cfg.save(config_path)
	return fresh


static func ls_get(key: String) -> String:
	return _ls_get(key)


static func ls_set(key: String, value: String) -> void:
	_ls_set(key, value)


static func _ls_get(key: String) -> String:

	"""
	Read one `localStorage` key, or "" for anything that is not a stored string.

	The whole expression is wrapped in a JS `try` because `localStorage` *throws*
	rather than returning null when a browser has site data blocked (a private
	window, or a strict privacy setting) — an unguarded read would surface as a
	JavaScriptBridge error every boot. The key goes through `JSON.stringify` so it
	is a JS string literal and cannot break out of the call.
	"""
	if not OS.has_feature("web"):
		return ""
	var js := "(function(){try{return window.localStorage.getItem(%s)||'';}catch(e){return '';}})()"
	var value: Variant = JavaScriptBridge.eval(js % JSON.stringify(key), true)
	return value as String if typeof(value) == TYPE_STRING else ""


static func _ls_set(key: String, value: String) -> void:
	"""Write one `localStorage` key. Same throw guard and same quoting as _ls_get."""
	if not OS.has_feature("web"):
		return
	var js := "try{window.localStorage.setItem(%s,%s);}catch(e){}"
	JavaScriptBridge.eval(js % [JSON.stringify(key), JSON.stringify(value)], true)


# =============================================================================
# SERVER LAYER
# =============================================================================

static func _origin() -> String:
	"""The lobby origin: the override when a self-check set one, else the usual
	`--lobby=` / `?lobby=` / export / default precedence."""
	if not lobby_url_override.is_empty():
		return lobby_url_override.strip_edges().rstrip("/")
	return LobbyClient.http_url()


func _endpoint() -> String:
	"""`<lobby origin>/best?id=<player id>`, honouring the usual lobby overrides."""
	return "%s/best?id=%s" % [_origin(), player_id().uri_encode()]


func _save_endpoint() -> String:
	"""`<lobby origin>/save?id=<player id>` — the slot beside the records."""
	return "%s/save?id=%s" % [_origin(), player_id().uri_encode()]


func _request_get() -> void:
	"""Ask the lobby for this player's stored records. Failure is silent."""
	if player_id().is_empty():
		return
	if _get_http == null:
		_get_http = HTTPRequest.new()
		_get_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_get_http)
	var headers := PackedStringArray(_auth_headers())
	var err: int = _get_http.request(_endpoint(), headers)
	if err != OK:
		# ERR_BUSY is an ordinary overlap and says nothing — with ONE exception:
		# an adoption's fetch dropped here is the adopted id never syncing while
		# the UI says "adopted", so `_adopt_refetch_pending` survives exactly this
		# error and dies on every other (nothing is in flight to complete after
		# those) and on the line below (the GET carrying this id started, so the
		# retry has nothing left to buy).
		if err != ERR_BUSY:
			push_warning("BestRunStore: /best GET could not start (%d)" % err)
			_adopt_refetch_pending = false
		return
	_adopt_refetch_pending = false
	_last_request_headers = headers
	# The window opens here and closes in the reply handler; a POST inside it is
	# what closes the baseline. See `_get_baseline_ok`.
	_get_in_flight = true
	_get_baseline_ok = true
	_get_http.request_completed.connect(_on_get_completed, CONNECT_ONE_SHOT)


func _on_get_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""
	Fold the server's records in. Anything unexpected — transport failure, a lobby
	too old to have the route, an unparseable body — is simply "no server record",
	which is the state a solo desktop player is permanently in.
	"""
	# Closed FIRST, above every early return: a GET that failed is still no longer
	# outstanding, and a POST after it races nothing.
	_get_in_flight = false
	if _reject_if_signed_out(response_code, body):
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data := json.data as Dictionary
	var server_coins := maxi(0, int(data.get("coins", 0)))
	# A lobby too old to know about progression simply omits these, which reads as
	# zero and raises nothing — the same forward/backward compatibility the server
	# side has for an old client's POST.
	var server_lifetime := maxi(0, int(data.get("lifetime", 0)))
	var server_spent := maxi(0, int(data.get("spent", 0)))
	# The server can be BEHIND us: a record set before this feature shipped, one
	# migrated out of the old `user://` file, or simply a run banked while the
	# lobby was unreachable. Without this the whole local history sits here until
	# the player happens to beat it, and never reaches their other devices — the
	# reply is the only moment we know what the server has, so it is where the
	# catch-up POST belongs. It converges: the next boot finds them equal.
	var server_is_behind := (
		server_coins < coins
		or server_lifetime < lifetime_coins
		or server_spent < spent_points
	)
	# THE PASSPORT (bead godot-test1-0bnw.2): the lobby carries the union of
	# every device's found set, so fold it the way the toast's arrival does —
	# through the SHIPPED sanitizer and merge, never assignment. A lobby too
	# old to know the field omits it (reads as []); a malformed one sanitizes
	# to [] and merges nothing — and a smaller reply can never shrink the local
	# set, because the merge is a union. If the server lacks an id we hold, it
	# is behind and earns the catch-up POST below.
	var server_found: Array[String] = _sanitize_found_ids(data.get("found", []))
	merge_found_landmark_ids(server_found)
	for id in found_landmark_ids():
		if not server_found.has(id):
			server_is_behind = true
			break
	# Kept BEFORE the merge below, and `maxi` because a monotone field never
	# unlearns. This is the only writer — and it only writes when this reply is a
	# causally pre-submit baseline, which `_get_baseline_ok` is the whole record of.
	if _get_baseline_ok:
		server_best_coins = maxi(server_best_coins, server_coins)
	var raised := server_coins > coins
	var progression_raised := server_lifetime > lifetime_coins or server_spent > spent_points

	coins = maxi(coins, server_coins)
	distance = 0
	lifetime_coins = maxi(lifetime_coins, server_lifetime)
	spent_points = maxi(spent_points, server_spent)
	if raised or progression_raised:
		# Mirror down, so the next boot has them even with the lobby unreachable.
		_write_local()
	if raised:
		loaded.emit(0, coins)
	if progression_raised:
		progression_loaded.emit(lifetime_coins, spent_points)
	if server_is_behind:
		_request_post()
	if _adopt_refetch_pending:
		# The adoption fetch above (or an earlier one) found the GET node busy,
		# so everything just processed belongs to the PRE-adoption id and the
		# adopted id's GET never happened. One retry, spent here: `_endpoint()`
		# reads `player_id()` at call time, so it carries the adopted id, and the
		# flag is already down, so the retry cannot chain into a second one.
		_adopt_refetch_pending = false
		fetch()


func _request_post() -> void:
	"""
	Publish the records. The lobby merges rather than overwrites, so this is
	idempotent and a dropped POST costs nothing but a round of cross-device sync —
	the next game over sends the same numbers again.
	"""
	if player_id().is_empty():
		return
	if _post_http == null:
		_post_http = HTTPRequest.new()
		_post_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_post_http)
	var body := JSON.stringify({
		"distance": 0,
		"coins": coins,
		"lifetime": lifetime_coins,
		"spent": spent_points,
		# The passport rides the same POST: the lobby unions it across devices.
		# An old lobby ignores the unknown field; the merge is idempotent, so a
		# dropped POST costs nothing but a round of cross-device sync.
		"found": found_landmark_ids(),
	})
	var headers := _auth_headers(PackedStringArray(["Content-Type: application/json"]))
	var err: int = _post_http.request(
		_endpoint(), headers, HTTPClient.METHOD_POST, body
	)
	if err == OK:
		_last_request_headers = headers
	if err == OK and _get_in_flight:
		# This run's numbers are now on their way to a lobby whose reply to the boot
		# GET has not been read yet, so that reply may echo them back. Retire the
		# baseline — only a POST that really started can contaminate it, which is why
		# this sits under `err == OK` and not above the request.
		_get_baseline_ok = false
	# Same reasoning as the GET: the local record is already written, so a failure
	# here costs only the cross-device half — but it must not be invisible.
	if err != OK and err != ERR_BUSY:
		push_warning("BestRunStore: /best POST could not start (%d)" % err)
	if err == OK:
		_post_http.request_completed.connect(_on_post_completed, CONNECT_ONE_SHOT)


func _on_post_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""The /best POST's reply is read for ONE reason: the 401 gate. Anything
	else is the existing silence — the POST path never adopted a reply and
	starts now only to learn the session died.
	"""
	if _reject_if_signed_out(response_code, body):
		return

# ---------------------------------------------------------------------------
# SAVE SYNC — GET at boot, POST on push, DELETE on clear (see the banner)
# ---------------------------------------------------------------------------

func _request_save_get() -> void:
	"""Ask the lobby for this player's cloud slot. Every failure silent: the
	local slot has already answered, and a failed reply simply leaves it."""
	if player_id().is_empty():
		return
	if _save_get_http == null:
		_save_get_http = HTTPRequest.new()
		_save_get_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_save_get_http)
	var headers := PackedStringArray(_auth_headers())
	if _save_get_http.request(_save_endpoint(), headers) != OK:
		return
	# Recorded only on a started request: the check pins the verb the lobby
	# actually received, not the intent.
	_last_save_verb = "GET"
	_last_request_headers = headers
	_save_get_http.request_completed.connect(_on_save_get_completed, CONNECT_ONE_SHOT)


func _on_save_get_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""
	Reconcile the cloud slot with the local one, LAST-WRITE-WINS on `saved_at`.

	Anything unexpected — transport failure, non-200, an unparseable envelope,
	an empty blob (no cloud save yet), a blob `SaveState.decode` rejects
	(malformed, v=2, oversize) — leaves the local slot untouched and emits
	nothing. A server copy older than or equal to local is ignored too: the next
	write pushes ours. Only a STRICTLY newer server copy replaces the local
	slot, and only that emits `save_loaded` — once per adopted reply.
	"""
	if _reject_if_signed_out(response_code, body):
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data := json.data as Dictionary
	if typeof(data.get("blob")) != TYPE_STRING:
		return
	var blob := String(data.get("blob"))
	if blob.is_empty():
		return
	# `SaveState.decode` is the ONLY gate: the envelope stamp is never trusted.
	var remote := SaveState.decode(blob)
	if remote.is_empty():
		return
	var remote_at := int(remote.get("saved_at", -1))
	var local_at := -1
	var local := SaveState.decode(save_slot())
	if not local.is_empty():
		local_at = int(local.get("saved_at", -1))
	if remote_at <= local_at:
		return
	# Local-only, never a push: answering a GET with a POST would echo every
	# boot into a write, and the next checkpoint carries ours anyway.
	_write_save_local(blob)
	save_loaded.emit()


func push_save_slot() -> void:
	"""
	POST the current slot to the lobby. Asked by `player_controller.write_save()`
	after its change gate — so this only ever runs when the rest changed.

	Carries the slot's OWN stamp (never `now`): the server answers LWW, and a
	reply newer than what was sent is adopted rather than fought. An empty slot
	sends the clear verb as DELETE instead — a clear that never writes again must
	still reach the server. A corrupt slot posts nothing: it reads as no-save
	locally, and garbage must not ride the wire. Every failure silent.
	"""
	if player_id().is_empty():
		return
	var raw := save_slot()
	if raw.is_empty():
		_request_save_delete()
		return
	var snap := SaveState.decode(raw)
	if snap.is_empty():
		return
	var sent_at := int(snap.get("saved_at", 0))
	var out := JSON.stringify({"blob": raw, "saved_at": sent_at})
	if _save_post_http == null:
		_save_post_http = HTTPRequest.new()
		_save_post_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_save_post_http)
	var headers := _auth_headers(PackedStringArray(["Content-Type: application/json"]))
	if _save_post_http.request(
		_save_endpoint(), headers, HTTPClient.METHOD_POST, out
	) != OK:
		return
	# Both set only on a started request: on ERR_BUSY the baseline must keep
	# the in-flight POST's stamp, or a genuinely newer server record is skipped
	# (round 1 minor 6) — and the verb must name what the lobby received
	# (round 1 MAJOR 2).
	_save_post_sent_at = sent_at
	_last_save_verb = "POST"
	_last_request_headers = headers
	_save_post_http.request_completed.connect(_on_save_post_completed, CONNECT_ONE_SHOT)


func _on_save_post_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""
	Adopt the reply when it is NEWER than what was sent — another device wrote
	meanwhile, and the server (LWW) kept theirs. Anything else — failure,
	non-200, an unparseable envelope, a malformed blob, an older-or-equal stamp
	(including our own echo) — is ignored, silently and without a signal: the
	write path never flips the card.
	"""
	if _reject_if_signed_out(response_code, body):
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data := json.data as Dictionary
	if typeof(data.get("blob")) != TYPE_STRING:
		return
	var blob := String(data.get("blob"))
	var remote := SaveState.decode(blob)
	if remote.is_empty():
		return
	# Against the SENT stamp, not the live slot: a checkpoint may have advanced
	# it meanwhile, and only the server's word on what we sent can outbid it.
	if int(remote.get("saved_at", -1)) <= _save_post_sent_at:
		return
	_write_save_local(blob)


func _request_save_delete() -> void:
	"""DELETE the cloud slot. Fire-and-forget: no reply is read, every failure
	silent — the local clear already happened. Own node (round 1 MAJOR 1: sharing
	the POST node died on ERR_BUSY behind every checkpoint push, so the clear
	never left and the next boot resurrected the ended campaign cross-device).
	On a start failure the clearing POST below is tried instead — the server
	clears on an empty blob too — so a dropped verb only costs a stale server
	copy that LWW settles on the next write. The verb recorded is the EFFECT
	(clear), whichever method carried it, and only when one actually started."""
	if player_id().is_empty():
		return
	if _save_delete_http == null:
		_save_delete_http = HTTPRequest.new()
		_save_delete_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_save_delete_http)
	var headers := PackedStringArray(_auth_headers())
	if _save_delete_http.request(_save_endpoint(), headers, HTTPClient.METHOD_DELETE) == OK:
		_last_save_verb = "DELETE"
		_last_request_headers = headers
		_save_delete_http.request_completed.connect(_on_save_delete_completed, CONNECT_ONE_SHOT)
		return
	if _save_post_http == null:
		_save_post_http = HTTPRequest.new()
		_save_post_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_save_post_http)
	# The fallback POST's reply is read through the save-post handler: its
	# adoption half finds an empty blob and ignores it, while the 401 half
	# signs out a dead session instead of leaving it standing.
	var post_headers := _auth_headers(PackedStringArray(["Content-Type: application/json"]))
	if _save_post_http.request(_save_endpoint(), post_headers,
			HTTPClient.METHOD_POST, JSON.stringify({"blob": "", "saved_at": 0})) == OK:
		_last_save_verb = "DELETE"
		_save_post_http.request_completed.connect(_on_save_post_completed, CONNECT_ONE_SHOT)
		_last_request_headers = post_headers


# ==============================================================================
# ==============================================================================


func _on_save_delete_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""The clear's reply is read for ONE reason: the 401 gate — a clear that
	lands on a dead session must still sign out. Anything else is the existing
	fire-and-forget silence.
	"""
	if _reject_if_signed_out(response_code, body):
		return
# AUTH RING — magic-link sign-in (bead godot-test1-i8yu.7.2)
# ==============================================================================
## Passwordless sign-in for the web export, where there is no keyboard to type
## a claim code with: the player enters an email, the lobby mails a link, and
## opening it on the game machine 302s the tab back with `#session=<64 hex>` —
## which `fetch()` takes and strips at boot. The token IS the session: the
## lobby minted it for that verified click, so holding it is signed in. The
## address remembered is the one the current link went to (written by the
## request, never by a reply); a session with no request behind it signs in
## with no address to show.
##
## The store never touches UI — every outcome reads off state or a signal:
## `session_token()` for the header, `session_email()` for the row,
## `session_changed` for the transitions, `magic_link_sent` for the send. The
## panel speaks; the store only ever forgets (401, sign-out).


## Web-only gate with a test seam: -1 asks the platform, 0/1 force it. The
## panel and the store both read `auth_available()` — never `OS.has_feature`
## directly for this flow — so a headless check forces 1 to reach the web rows
## and 0 for the control.
static var auth_available_override: int = -1


static func auth_available() -> bool:
	"""Whether the magic-link flow may start: the web export, or a forced row."""
	if auth_available_override >= 0:
		return auth_available_override == 1
	return OS.has_feature("web")


func session_token() -> String:
	"""This session's token, "" when signed out. Cached like `_player_id`:
	localStorage then the cfg `[player]` session (the id's migration idiom);
	anything not matching `SESSION_PATTERN` reads as "" AND is cleared from
	both layers, the re-mint idiom — garbage must not screen a later session.
	"""
	if not _session_token.is_empty():
		return _session_token
	var stored := ""
	if OS.has_feature("web"):
		stored = _ls_get(LS_SESSION)
	if stored.is_empty():
		var cfg := ConfigFile.new()
		if cfg.load(config_path) == OK:
			stored = str(cfg.get_value(CONFIG_PLAYER_SECTION, "session", ""))
	if is_valid_session_token(stored):
		_session_token = stored
		return _session_token
	if not stored.is_empty():
		_clear_session_layers()
	return ""


func session_email() -> String:
	"""The address the player typed, CLIENT-SIDE ONLY — for "Signed in as …".
	"" when signed out. Shown, never sent (except in the one /auth/magic POST
	that asked for the link). Lazily re-read from both layers, so the address
	a pre-redirect request stored is still here on the fresh boot.
	"""
	if session_token().is_empty():
		return ""
	if not _session_email.is_empty():
		return _session_email
	if OS.has_feature("web"):
		_session_email = _ls_get(LS_SESSION_EMAIL)
	if _session_email.is_empty():
		var cfg := ConfigFile.new()
		if cfg.load(config_path) == OK:
			_session_email = str(cfg.get_value(CONFIG_PLAYER_SECTION, "email", ""))
	return _session_email


static func is_valid_session_token(token: String) -> bool:
	"""Whether `token` is shaped like a lobby-minted session: 64 lowercase
	hex, strictly `SESSION_PATTERN` — the server's `tokenRe`, so anything else
	is refused HERE instead of 401ing a request for it.
	"""
	var shape := RegEx.create_from_string(SESSION_PATTERN)
	return shape != null and shape.search(token) != null


static func is_valid_magic_email(address: String) -> bool:
	"""Whether `address` may be sent: the same minimal rule as the server
	(`server/auth.go`'s `validEmail` minus the `mail.ParseAddress` half the
	client cannot run) — one `@` with non-empty sides, no whitespace, at most
	`MAX_EMAIL_LEN`. Factored out so the request path and the panel cannot
	drift apart: a second spelling of "valid" is a second outage.
	"""
	if address.is_empty() or address.length() > MAX_EMAIL_LEN:
		return false
	if address.contains(" ") or address.contains("\t") or address.contains("\n") or address.contains("\r"):
		return false
	var at := address.find("@")
	if at <= 0 or at != address.rfind("@") or at >= address.length() - 1:
		return false
	return true


func adopt_session(token: String) -> bool:
	"""Adopt a lobby-minted session token: the shape refused (`false`, nothing
	touched), otherwise BOTH local layers written (the `adopt_player_id`
	idiom), the cache set, `session_changed(true, "")` emitted, then `fetch()`
	— the first authed GET /best?id=<anon> is what makes the server link anon
	→ sub, and the reply (sub's record) folds in through the ordinary monotone
	path; /save's reply lands LWW through `_on_save_get_completed` as today.
	Reuses `_adopt_refetch_pending` exactly as `adopt_player_id` does (the boot
	GET may still be in flight).
	"""
	if not is_valid_session_token(token):
		return false
	_adopt_session_quiet(token)
	# Armed until the adoption's GET actually starts (see `_request_get`): the
	# same ERR_BUSY overlap the claim adoption documents there.
	_adopt_refetch_pending = true
	fetch()
	return true


func _adopt_session_quiet(token: String) -> void:
	"""Adopt without fetching: the take inside `fetch()` uses this, and the
	outer fetch's own GET pair is the adoption's one pair. Shape-guarded —
	the snippet already matched it, but a second spelling of the take must not
	become a way around the validator.
	"""
	if not is_valid_session_token(token):
		return
	_ls_set(LS_SESSION, token)
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep every other section intact
	cfg.set_value(CONFIG_PLAYER_SECTION, "session", token)
	cfg.save(config_path)
	_session_token = token
	session_changed.emit(true, "")


func request_magic_link(email: String) -> void:
	"""Ask the lobby to mail a sign-in link to `email`. Trims and lowercases
	(the server normalizes the same way); a refused address emits
	`magic_link_sent(false, …)` synchronously and sends NOTHING. Otherwise the
	address is stored in both layers NOW — it must survive the redirect/reload
	the session arrives on — and POST `<origin>/auth/magic` with
	`{"email": …}` goes out on `_auth_http`. Reply: 200 → (true, ""); 400/429/
	503 with a JSON error → (false, that text); anything else → (false,
	"Cannot reach the lobby"). No retry timer.
	"""
	var address := email.strip_edges().to_lower()
	if not is_valid_magic_email(address):
		magic_link_sent.emit(false, tr("That does not look like an email address"))
		return
	_store_session_email(address)
	_request_magic_link()


func _store_session_email(address: String) -> void:
	"""Write the typed address to the cache and both layers."""
	_session_email = address
	_ls_set(LS_SESSION_EMAIL, address)
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep every other section intact
	cfg.set_value(CONFIG_PLAYER_SECTION, "email", address)
	cfg.save(config_path)


func _clear_session_layers() -> void:
	"""Forget the token AND the email in both layers and both caches. Records
	and the save slot are NOT touched: what is local stays local, exactly as
	when the id changes.
	"""
	_session_token = ""
	_session_email = ""
	_ls_set(LS_SESSION, "")
	_ls_set(LS_SESSION_EMAIL, "")
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep every other section intact
	cfg.set_value(CONFIG_PLAYER_SECTION, "session", "")
	cfg.set_value(CONFIG_PLAYER_SECTION, "email", "")
	cfg.save(config_path)


func _magic_link_envelope() -> Dictionary:
	"""The magic-link POST as data (`url`/`headers`/`body`): factored pure so
	`save_selfcheck` pins the shape without sending anything. The header rides
	exactly like the save verbs'.
	"""
	var headers := _auth_headers(PackedStringArray(["Content-Type: application/json"]))
	var body := JSON.stringify({"email": _session_email})
	return {"url": "%s/auth/magic" % _origin(), "headers": headers, "body": body}


func _request_magic_link() -> void:
	"""POST the sign-in link request. Own node, same silent rule as every verb:
	the reply is read only to speak it through `magic_link_sent` — a sent link
	needs nothing more, and the panel already said SENDING off the dispatch.
	"""
	if player_id().is_empty():
		return
	if _auth_http == null:
		_auth_http = HTTPRequest.new()
		_auth_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_auth_http)
	var ask := _magic_link_envelope()
	if _auth_http.request(ask["url"], ask["headers"], HTTPClient.METHOD_POST, ask["body"]) != OK:
		return
	_last_request_headers = ask["headers"]
	_auth_http.request_completed.connect(_on_magic_link_completed, CONNECT_ONE_SHOT)


func _on_magic_link_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""Speak the link request's reply through `magic_link_sent`: 200 is on its
	way; a refusal carries the server's own error text; anything else (a lobby
	too old for /auth/* included) is "Cannot reach the lobby" — an honest
	refusal, not a crash. A 401 signs out first: the token died mid-run.
	"""
	if _reject_if_signed_out(response_code, body):
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		magic_link_sent.emit(false, tr("Cannot reach the lobby"))
		return
	if response_code == 200:
		magic_link_sent.emit(true, "")
		return
	if response_code == 400 or response_code == 429 or response_code == 503:
		magic_link_sent.emit(false, _auth_error_text(body, tr("Cannot reach the lobby")))
		return
	magic_link_sent.emit(false, tr("Cannot reach the lobby"))


static func _auth_error_text(body: PackedByteArray, fallback: String) -> String:
	"""The server's `{"error": …}` reason, or `fallback` when the body is not
	one — a refusal must still say something honest on screen.
	"""
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return fallback
	var reason := str((json.data as Dictionary).get("error", "")).strip_edges()
	if reason.is_empty():
		return fallback
	return reason


func sign_out(why: String = "") -> void:
	"""Sign out: fire-and-forget DELETE `<origin>/auth/session` with the dying
	header, then forget the token AND the email locally and emit
	`session_changed(false, why)`. The header is built BEFORE the local state
	goes; the send's outcome changes nothing (the server copy dies at expiry),
	so its return — ERR_BUSY included — is swallowed. Records and the save
	slot are NOT touched.
	"""
	var headers := _auth_headers()
	_clear_session_layers()
	if _auth_http == null:
		_auth_http = HTTPRequest.new()
		_auth_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_auth_http)
	_auth_http.request("%s/auth/session" % _origin(), headers, HTTPClient.METHOD_DELETE)
	session_changed.emit(false, why)


func take_session_from_url() -> String:
	"""Take `#session=` off the page URL at boot and strip it in the same call
	(`URL_SESSION_SNIPPET`). Web only — returns "" off-web WITHOUT touching
	the bridge, so desktop and headless never eval. The answer is already
	shape-checked by the snippet's own match; `fetch()` adopts it quietly.
	"""
	if not OS.has_feature("web"):
		return ""
	var answer: Variant = JavaScriptBridge.eval(URL_SESSION_SNIPPET, true)
	return answer as String if typeof(answer) == TYPE_STRING else ""


func _auth_headers(extra: PackedStringArray = []) -> PackedStringArray:
	"""`extra` plus `X-Session: <token>` while signed in — the ONE header the
	server's session middleware reads. Signed out this is `extra` alone, so
	the anonymous boot GET and every other signed-out request send exactly
	what they sent before this ring.
	"""
	var headers := PackedStringArray(extra)
	var token := session_token()
	if not token.is_empty():
		headers.append("%s: %s" % [SESSION_HEADER, token])
	return headers


func _reject_if_signed_out(response_code: int, body: PackedByteArray) -> bool:
	"""The 401 rule, in one place so the five sites cannot drift: a 401 means
	the session died server-side, so `sign_out()` with the server's error text
	when the body parses — else "Your sign-in has expired — send a new link" —
	and the caller returns. True when it signed out, so handlers lead with
	`if _reject_if_signed_out(...): return`. Silent otherwise, like every
	failure in this file: the panel's status row repaints off the
	`session_changed` signal, which is where the player reads it.
	"""
	if response_code != HTTPClient.RESPONSE_UNAUTHORIZED:
		return false
	sign_out(_auth_error_text(body, tr("Your sign-in has expired — send a new link")))
	return true
