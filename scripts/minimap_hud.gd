extends Control
## Minimap HUD — where you are, which way you face, and where the coin road goes.
##
## Drawn entirely in _draw() with no texture assets, exactly like ability_hud.gd
## and lives_hud.gd: this project ships a web build where every KB and every draw
## call is budgeted, so the HUD is code-built circles, lines and text.
##
## Discovery is GROUP-BASED like the rest of the HUD — the player comes from the
## "player" group and the world from the "terrain" group, both re-fetched if they
## ever go away, both guarded with has_method() so this control still runs (blank)
## in a scene that has neither.
##
## WHAT IT SHOWS
##   * A north-up map: world +X is screen RIGHT, world +Z is screen DOWN. North-up
##     (rather than rotating the map under a fixed arrow) is deliberate: the coin
##     road always trends +X by construction, so a fixed frame makes "the road goes
##     that way" readable at a glance, and it costs no per-point rotation.
##   * The BIOME FIELD across the whole disc, as coloured bands — so the desert or
##     the snow you are walking toward is visible before you reach it, not just the
##     one you are standing in. The colours are copied from
##     assets/shaders/ground.gdshader and checked against it by minimap_selfcheck:
##     a map that disagrees with the ground about where a band sits is worse than a
##     map with no colour (see BIOME_TINTS and _gather_terrain).
##   * The player as a triangle at the centre, rotated to the character's facing.
##   * The coin road centerline as a polyline, read straight out of the terrain's
##     existing station cache (see _gather_road below).
##   * Crocodiles within range as small red dots.
##   * Geo landmarks (Stonehenge, Giza, the Eiffel Tower — see endless_terrain's
##     GEO LANDMARKS banner) as small violet X marks, clamped to the rim and
##     dimmed when they are off the map. They are destinations, so a rim hint is
##     the point: at the default zoom most loaded landmarks are past the disc.
##   * THE TOWER (GastroDefense HQ) as a mint UPRIGHT CROSS at `tower_site()`, also
##     rim-clamped and dimmed off-disc. Unlike every other layer it is not read off
##     a group — the terrain is asked where the tower is, not where its geometry
##     currently stands — so the bearing to it is on the map from the first frame
##     of a run, 400 m before there is anything out there to see.
##   * Multiplayer teammates as dots in their own stable per-peer colour, clamped
##     to the rim (as a radial tick, not a blob) when they are off the map. Solo,
##     there is no teammate layer at all and nothing is drawn or scanned.
##   * World X / Z coordinates and the biome underfoot as text, with a "~ river ~"
##     marker while the player is standing in a wading band.
##   * INSIDE THE HQ ONLY: the storey beside the coordinates and the cell block's
##     storey beside the biome ("Floor 6" / "JAIL F10  ^4"), plus — after 90 s
##     without progress and never before — one amber arrow at the rim. See the
##     INDOORS banner below for what is deliberately NOT drawn there.
##
## ZOOM. +/- step through ZOOM_RADII (raw keycodes outside the input map, like the
## M toggle). The WIDGET NEVER CHANGES SIZE — what changes is how many metres the
## disc covers, and EVERY layer derives from the one shared factor `_map_scale()`
## (or the `_view_radius()` behind it): the road window, the crocodile dot radius,
## the teammate dots and their rim clamp. There is deliberately no second constant
## anywhere that means "how far the map reaches" — see `_view_radius()`.
##
## PERFORMANCE SHAPE (this is a web-build feature, so it is the design)
##   * Everything is recomputed on a throttled TICK_INTERVAL tick (~5 Hz), never
##     per frame — the same discipline as crocodile_lod_manager.gd's 9 Hz scan and
##     perf_overlay.gd's 4 Hz refresh.
##   * _draw() reads only the snapshot the tick left behind; it fetches nothing,
##     allocates nothing, and runs at the TICK rate, not the frame rate (~5 redraws
##     a second of one small control). The point buffers are PackedVector2Array
##     members written in place; only the road buffer ever resizes, and only when
##     the number of stations in a fixed-width window changes.
##   * Every drawing primitive was picked for its DRAW CALL count, measured against
##     a frozen world with the same counters perf_overlay.gd (F3) reads: one
##     polyline for the road rather than ~20 lines, one multiline for the whole
##     crocodile pack rather than one circle each, ONE multiline for every landmark
##     X on screen rather than a polygon each, one two-line string rather than
##     two, ONE multiline of run-length bars for the entire terrain field rather
##     than a rect per cell. Total cost of the map: +10 draw calls, +1 more while
##     any landmark is loaded (0 when none is), +1 for the tower cross (which is
##     one marker and therefore always exactly one call), no measurable CPU change.
##   * The terrain field is the one layer with a real CPU cost: TERRAIN_GRID^2
##     `biome_at()` samples per TICK, measured at ~0.24 ms on desktop and ~1 ms in
##     the browser — once every 200 ms, against a 33 ms spike threshold. It is
##     sampled in `_gather_terrain()` into the same kind of reusable buffer every
##     other layer uses; `_draw()` never calls `biome_at()`, and minimap_selfcheck
##     measures that it doesn't.
##
## Toggle with M (a raw keycode like perf_overlay's F3 and motion_debug's F4, so it
## stays outside the project input map and can't collide with a gameplay action).

# ============================================================================
# CONFIGURATION
# ============================================================================

## Key that shows/hides the map. Raw keycode on purpose — this is a HUD toggle,
## not a gameplay control, so it deliberately lives outside project.godot's map.
const TOGGLE_KEYCODE: Key = KEY_M

## How often (seconds) the map re-reads the world and redraws. ~5 Hz: fast enough
## that the player dot never looks frozen, slow enough that the crocodile group
## scan and the road walk are invisible in a frame budget.
const TICK_INTERVAL: float = 0.2

## Zoom steps, in world metres from the centre of the map to its edge. The widget
## keeps its pixel size at every step; only the metres-per-pixel change.
## `ZOOM_DEFAULT_INDEX` is the 60 m the map shipped with — it comfortably covers
## the crocodile LOD sleep radius (45 m), so at the default zoom anything that
## could plausibly reach the player is on the map. Five steps: two in for reading
## a crowded camp, two out for finding where the road went.
const ZOOM_RADII: Array[float] = [30.0, 45.0, 60.0, 90.0, 130.0]
const ZOOM_DEFAULT_INDEX: int = 2

## Keys that step the zoom. Raw keycodes for the same reason TOGGLE_KEYCODE is one
## — a HUD control has no business in project.godot's gameplay input map. Both the
## main row and the numpad are accepted, and KEY_EQUAL is included because "+" is
## shift-equals on most layouts and nobody holds shift to zoom a map.
const ZOOM_IN_KEYCODES: Array[Key] = [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]
const ZOOM_OUT_KEYCODES: Array[Key] = [KEY_MINUS, KEY_KP_SUBTRACT]

## Radius of the drawn map disc, in pixels — 1.5x the 62 px the map shipped with.
## PIXELS ONLY. How many METRES the disc reaches is `_view_radius()` and is
## deliberately unchanged at every zoom step: growing the widget makes the same
## world bigger on screen, it does not show more of it. The terrain layer below is
## why it grew — a 15-cell grid across 62 px is 8 px cells, which reads as noise.
const MAP_RADIUS: float = 93.0

## Centre of the map disc within this control. `scenes/main.tscn` sizes the
## MinimapHUD control from these two numbers — its WIDTH must stay MAP_CENTER.x * 2,
## because the caption below the disc is centred across `size.x` and would otherwise
## drift off the disc's axis. `minimap_selfcheck` asserts the rect still holds both.
const MAP_CENTER := Vector2(101.0, 101.0)

## Fraction of the map's reach within which crocodiles get a dot — a FRACTION, not
## a metre count, so it follows the zoom instead of needing its own step table.
## Deliberately HALF the map's reach: the outer ring of the map is for the road,
## the inner disc is for threats. At the default zoom that is the 30 m the map
## shipped with, which covers everything that can currently see the player (the
## ordinary DETECTION_RADIUS is 15 m, a boss's is 25 m), while dotting the full
## radius would be ~80 red specks far from the origin, where croc density scales
## up — noise, not information.
const CROC_VIEW_FRACTION: float = 0.5

## Hard cap on crocodile dots, and the size of the dot buffer. CROC_VIEW_RADIUS
## covers ~1.1 chunks of ground, which holds 10 crocodiles near the origin and ~20
## at the far end of the density gradient, so this is a genuine safety bound rather
## than a limit the game reaches: it matters because the group is in spawn order,
## not distance order, so a cap that actually bit could drop the croc standing next
## to the player in favour of one 30 m away.
const MAX_CROC_DOTS: int = 40

## Hard cap on road centerline points. The window is 2 * `_view_radius()` metres
## wide and stations sit road_coin_spacing (6 m) apart, so ~21 points at the
## default zoom and ~44 fully zoomed out — but road_coin_spacing is an @export a
## designer can shrink, and an unbounded walk over a 0.1 m spacing would be
## thousands of points, so the walk is capped.
const MAX_ROAD_POINTS: int = 96

## Player arrow size in pixels (half-length along the facing direction).
const ARROW_LENGTH: float = 9.0
const ARROW_HALF_WIDTH: float = 6.0

## Crocodile dot radius in pixels.
const CROC_DOT_RADIUS: float = 2.6

## Teammate dot radius in pixels — bigger than a crocodile's, because there are at
## most three of them and they are the thing you are looking for.
const PEER_DOT_RADIUS: float = 3.6

## Hard cap on teammate dots, and the size of the dot buffers. The lobby caps a
## room at 4 members (`server/room.go`), so 3 is the real number; this is a bound
## on peer-supplied data, in the same spirit as every other bound on the relay.
const MAX_PEER_DOTS: int = 8

## Geo-landmark marker: half-length of each arm of the X, and the width the two
## crossing segments are stroked at. An X rather than a dot or a diamond outline
## because SHAPE is what survives at this size: a 4 px diamond outline is
## indistinguishable from the square blobs the crocodile and teammate layers draw,
## while a cross reads as "a marked site" at a glance and costs two segments.
const LANDMARK_MARK_RADIUS: float = 3.4
const LANDMARK_MARK_WIDTH: float = 1.6

## How far an X reaches from its own centre: the arm's half-DIAGONAL (its corners
## sit at (±arm, ±arm), so the reach is arm * sqrt(2), not arm) plus half the
## stroke width. THIS, never LANDMARK_MARK_RADIUS, is what the rim inset below
## subtracts — inset by the arm length alone and a clamped X pokes its corners
## ~1.4 px past the ring, which is precisely the "does not poke past the ring"
## rule the crocodile and teammate dots get for free by being horizontal segments
## as long as they are wide. Written as a literal multiplier because GDScript
## cannot call sqrt() in a const expression.
const LANDMARK_MARK_REACH: float = LANDMARK_MARK_RADIUS * 1.4142136 + LANDMARK_MARK_WIDTH * 0.5

## Hard cap on landmark markers, and the size of the landmark buffers. Landmarks
## are ~1 per 46 chunks and only 49 (web) to 121 (desktop) chunks are ever active,
## so the group holds typically 0-3 nodes: this is a genuine bound on a group
## another script fills, never a limit play reaches.
const MAX_LANDMARK_DOTS: int = 12

## Alpha a rim-clamped (off-map) landmark X is drawn at, relative to one on the
## map — the teammate tick's rule, for the teammate tick's reason: off the map is
## less certain information and must not out-shout a landmark you can walk to.
## Shared by the tower mark below, which is the same rule about the same thing (a
## fixed destination you can be far from) and does not want a second number.
const LANDMARK_EDGE_ALPHA: float = 0.7

## THE TOWER MARK — GastroDefense HQ (epic godot-test1-3iy, phase 2): half-length
## of each arm and the stroke width, in the landmark X's units.
##
## AN UPRIGHT CROSS, NOT AN X, and that is the whole design. There is exactly ONE
## tower in a world and the map has to say "that one, over there" at a glance while
## a handful of violet X marks may be on the disc at the same time — so it is
## distinguished by SHAPE first (a + reads differently from an × even at four
## pixels, where two colours a hue apart do not) and by colour second. Bigger than
## the landmark X for the same reason: the tower is the destination, the landmarks
## are scenery you pass.
const TOWER_MARK_RADIUS: float = 4.4
const TOWER_MARK_WIDTH: float = 1.8

## How far the tower mark reaches from its own centre, i.e. the rim inset — the
## LANDMARK_MARK_REACH rule ("inset by the mark's reach or a clamped mark pokes
## past the ring"), with the arithmetic the cross's axis-aligned arms make easier:
## the true worst point is a corner at (width/2, arm), so arm + width/2 is a
## deliberate slight OVER-estimate, which insets by ~0.8 px more than strictly
## needed and can only ever keep the mark further inside the ring.
const TOWER_MARK_REACH: float = TOWER_MARK_RADIUS + TOWER_MARK_WIDTH * 0.5

## Length in pixels of the radial tick an OFF-MAP teammate is drawn as. A dot
## clamped to the rim would read as a teammate standing exactly at the map's edge;
## a tick pointing outward along their bearing reads as "further, that way".
const PEER_EDGE_TICK: float = 7.0

## Alpha a rim-clamped teammate tick is drawn at, relative to an on-map dot. Off
## the map is less certain information, and it should not out-shout a teammate you
## can actually walk to.
const PEER_EDGE_ALPHA: float = 0.75

## On-widget touch zoom buttons: size in pixels, and the gap between them. Built
## only in a touch session (see `_build_zoom_buttons`).
const ZOOM_BUTTON_SIZE: float = 30.0
const ZOOM_BUTTON_GAP: float = 4.0

# --- INDOORS: the storey line, the jail's floor, and the anti-stall arrow -----
#
# All of it is gated on `TowerShell.sheltered()` and NOTHING is added outside it —
# out in the field this feature costs one cached null check per tick (bd
# godot-test1-kox).
#
# WHAT IS DELIBERATELY NOT HERE, because the design note on that bead rejected each
# by name: no radar sweep, no facing pulse, and NO CONTINUOUS BEARING to the cell
# block. A live arrow to the jail would rank the corridors for you at every junction
# — the player walks two steps down each one and keeps whichever improved the
# bearing — which solves the labyrinth without ever entering it. The horizontal help
# is authored into the building instead (`TowerInterior.SIGN_PIECES`).
#
# What survives here is the VERTICAL intent, which is honest and unsolvable: the
# block is on the top storey and saying so costs the maze nothing.

## How long (seconds) a player may go without MEANINGFUL PROGRESS before the
## anti-stall arrow appears — and progress is a FIRST-TIME room or maze cell this
## visit, or a storey gained, never any room-entry event (`TowerInterior.zone_at`).
## Oscillating in a doorway must not reset this, and a player re-walking rooms they
## have already searched is genuinely stuck and must still get help.
const STALL_SECONDS: float = 90.0

## Seconds the arrow takes to fade in once the threshold passes. It is a rescue, not
## an alert: it must not pop.
const STALL_FADE: float = 3.0

## THE LABYRINTH'S UNSTABLE LOCK. On the maze storeys the jail line already reads
## "NO LOCK", so an arrow that simply appeared there would make the degraded system
## quietly reliable — the one thing the fiction may not do. It flickers instead: a
## brief hold every period, on a bearing snapped to the compass points.
const MAZE_FLICKER_PERIOD: float = 4.0
const MAZE_FLICKER_ON: float = 0.9
const MAZE_BEARING_STEP: float = PI / 4.0

## The anti-stall arrow's size in pixels (half-length along the bearing, half-width
## across it) — the player triangle's shape at the rim, a little smaller.
const JAIL_ARROW_LENGTH: float = 8.0
const JAIL_ARROW_HALF_WIDTH: float = 5.0

## Amber: the one warm hue on the disc that is not the road's gold, and it is the
## colour of the plaques in the building the arrow points into.
const COLOR_JAIL := Color(1.0, 0.62, 0.15, 1.0)

## Where unused crocodile dot slots are parked. Well outside the control on both
## axes, so the segments drawn there land off-screen no matter where the HUD puts
## this control (offsets only ever move it right and down from the viewport corner).
const PARKED_SEGMENT := Vector2(-4000.0, -4000.0)

## Road line width in pixels.
const ROAD_WIDTH: float = 2.5

## Text block: font size, and the gap from the bottom of the disc to its baseline.
const TEXT_SIZE: int = 15
const TEXT_TOP_GAP: float = 18.0

## Terrain layer: biome samples per axis across the disc's bounding square.
##
## COARSE ON PURPOSE. The biome field has a 400 m wavelength (BIOME_CELL_SIZE, ~8
## chunks) while the disc reaches 30-130 m, so the whole map is a fraction of one
## noise cell: a fine grid resolves nothing a coarse one misses, it just costs
## samples. 15 is picked from the other end instead — it is the coarsest grid whose
## cells (2 * MAP_RADIUS / 15 = 12.4 px) still read as a band rather than as
## chequerboard — and being ODD puts a row and a column exactly on the centre, so
## the cell under the player arrow is a real sample and not an interpolation of two.
##
## MEASURED COST (desktop, Godot 4.5): 177 of the 225 cells fall inside the disc and
## `biome_at()` costs ~1.35 us, so a tick spends ~0.24 ms sampling — 1.2 ms per
## second at the 5 Hz tick rate. Web GDScript runs this maybe 2-4x slower, so
## ~0.5-1.0 ms once every 200 ms; the spike log's threshold is 33 ms.
const TERRAIN_GRID: int = 15

## Side of one terrain cell in pixels — DERIVED, never a second number: it is the
## disc's own diameter cut into TERRAIN_GRID. It is also the draw width of the
## horizontal bars the layer is painted with, which is what makes the rows tile.
const TERRAIN_CELL: float = MAP_RADIUS * 2.0 / TERRAIN_GRID

## Alpha every terrain cell is painted at. The RGB comes from the ground shader
## (see BIOME_TINTS); this is the map's own dimming, and the only part of the
## colour that is ours: the terrain is a BACKDROP for the road, the dots and the
## arrow, and it must never out-shout them. 0.55 is what the single whole-disc
## tint this layer replaced was already drawn at.
const TERRAIN_ALPHA: float = 0.55

# --- Colours ----------------------------------------------------------------
const COLOR_BACKDROP := Color(0.0, 0.0, 0.0, 0.5)   # dark disc under everything
const COLOR_RIM := Color(1, 1, 1, 0.35)              # thin ring round the disc

## Width of that ring in pixels. The rim is a slightly LARGER filled circle drawn
## underneath the disc rather than a draw_arc(): an antialiased arc cost 3 draw
## calls on its own where a plain filled circle costs 1, and at 1.5 px the two are
## indistinguishable.
const RIM_WIDTH: float = 1.5
const COLOR_ROAD := Color(1.0, 0.85, 0.15, 0.9)      # coin gold, matches the coins
const COLOR_CROC := Color(0.95, 0.25, 0.2, 0.95)     # threat red, matches the vignette
const COLOR_PLAYER := Color(0.4, 0.95, 1.0, 1.0)     # cyan, nothing else on the map is
## Violet, deliberately away from every other hue on the disc — the road's gold,
## the crocodiles' red, the player's cyan — and legible on all four biome tints.
const COLOR_LANDMARK := Color(0.85, 0.55, 1.0, 0.95)
## The tower's mint green. Every other hue on the disc is taken — the road's gold,
## the crocodiles' red, the landmarks' violet, the player's cyan — and the biome
## tints are all dark and desaturated, so a saturated mint sits on top of any of
## them. It is closest to the player's cyan and that is fine: the player is a large
## triangle permanently at the exact centre of the disc, so nothing at the rim is
## ever mistaken for it.
const COLOR_TOWER := Color(0.35, 1.0, 0.6, 0.98)
const COLOR_TEXT := Color(1, 1, 1, 0.95)
const COLOR_RIVER_TEXT := Color(0.45, 0.75, 1.0, 0.95)

## The terrain palette, indexed by endless_terrain's Biome enum (PLAINS, DESERT,
## FOREST, MOUNTAIN, CITY, SNOW — the declaration order, which is what the int we
## get across the group boundary means).
##
## EVERY RGB HERE IS COPIED FROM assets/shaders/ground.gdshader AND IS NOT OURS TO
## RETUNE. The shader is where the ground's colour is decided; a map that invents
## its own greens tells the player the desert is somewhere it isn't, which is worse
## than a map with no colour at all. So this is a THIRD copy of the same parity
## discipline `_biome_noise` already carries (see the CPU/GPU parity contract in
## endless_terrain.gd): mirrored by hand, and checked by machine —
## `minimap_selfcheck.gd` parses the shader's uniform defaults and fails if any row
## here has drifted from them. PLAINS has no uniform of its own: the shader mottles
## between `green_a` and `green_b` per vertex, so the map uses their midpoint, which
## is what that mottle averages to.
##
## The ALPHA is ours (TERRAIN_ALPHA) — the shader paints the world, we paint a
## backdrop that the road, the dots and the arrow have to stay legible on top of.
const BIOME_TINTS: Array[Color] = [
	Color(0.31, 0.495, 0.25, TERRAIN_ALPHA),  # PLAINS   — midpoint of green_a/green_b
	Color(0.78, 0.68, 0.44, TERRAIN_ALPHA),   # DESERT   — desert_color
	Color(0.13, 0.30, 0.17, TERRAIN_ALPHA),   # FOREST   — forest_color
	Color(0.45, 0.43, 0.40, TERRAIN_ALPHA),   # MOUNTAIN — mountain_color
	Color(0.50, 0.48, 0.45, TERRAIN_ALPHA),   # CITY     — city_color
	Color(0.85, 0.89, 0.93, TERRAIN_ALPHA),   # SNOW     — snow_color
]
## Indexed by endless_terrain.Biome, so the ORDER here is the enum's integer
## order and NOT the order the bands sit in the noise field — CITY is appended
## because the enum appends it (its band lies between plains and forest), and SNOW
## is appended after it (its band is the topmost, above mountain).
const BIOME_NAMES: Array[String] = ["PLAINS", "DESERT", "FOREST", "MOUNTAIN", "CITY", "SNOW"]

# ============================================================================
# STATE (written by the tick, read by _draw — they never disagree)
# ============================================================================

## Cached node references, re-fetched when they go away (respawn, restart, a scene
## run without one of them).
var _player: Node3D = null
var _terrain: Node = null
## The multiplayer manager, found in the "mp" group with a has_method() guard like
## every other reach across a system boundary here. Null in a scene without one,
## and `peer_markers()` answers null while offline — both mean "no teammate layer".
var _mp: Node = null

## Index into ZOOM_RADII. Session-only by design: a map zoom is a glance-scale
## preference, not a setting, and the project already has two ConfigFiles whose
## web persistence is documented as flaky. Nothing writes it to disk.
var _zoom_index: int = ZOOM_DEFAULT_INDEX

## Seconds until the next tick.
var _time_until_tick: float = 0.0

## False until the first successful read of the player — _draw() then renders
## nothing rather than leaving a stale map painted.
var _have_data: bool = false

## Snapshot of the player.
var _player_pos: Vector3 = Vector3.ZERO
## Player facing as a screen-space unit vector (+X right, +Z down), already mapped
## out of the 3D basis so _draw() does no trigonometry.
var _facing: Vector2 = Vector2(1.0, 0.0)

## Snapshot of the world under the player.
var _biome: int = 0
var _in_river: bool = false

## The terrain layer, in the same "segment pairs for ONE draw call" form the
## teammate and landmark buffers use: each entry is a HORIZONTAL BAR — a run of
## same-biome grid cells along one row, drawn through `draw_multiline_colors()` at
## a width of TERRAIN_CELL so consecutive rows tile into a solid field. One colour
## per SEGMENT, so `_terrain_colors` is half the length of `_terrain_points`.
##
## RUN-LENGTH IS WHAT KEEPS THIS ONE DRAW CALL AND CHEAP TO FILL: the biome field
## is smooth at this scale, so a row is normally one or two runs, not fifteen —
## but the buffers are sized for the worst case (every cell its own run) so the
## tick never allocates and there is no cap that could ever bite and silently drop
## part of the map. The unused tail is parked off-control and transparent, exactly
## like the crocodile, teammate and landmark tails.
var _terrain_points: PackedVector2Array = PackedVector2Array()
var _terrain_colors: PackedColorArray = PackedColorArray()
var _terrain_count: int = 0

## Road centerline in ABSOLUTE control-space pixels, already clamped inside the map
## disc, ready to hand straight to ONE draw_polyline(). It is resized only when the
## number of stations in the window changes (the window is a fixed width, so that
## settles within a tick or two and then never allocates again). The exact-length
## array is what buys the single draw call: draw_polyline() takes the whole array,
## so a spare-capacity buffer plus a count would need a slice — an allocation per
## draw — or N separate draw_line() calls, which is what this replaced.
var _road_points: PackedVector2Array = PackedVector2Array()
var _road_count: int = 0

## Crocodile dots as absolute-pixel LINE SEGMENT PAIRS (two entries per dot), for
## one draw_multiline(). Unlike the road buffer this one is permanently sized to
## MAX_CROC_DOTS and never resized — the dot count changes on most ticks, so a
## resize-to-fit would mean a reallocation on most ticks; the unused tail is parked
## off-control instead (see PARKED_SEGMENT).
var _croc_points: PackedVector2Array = PackedVector2Array()
var _croc_count: int = 0

## The player arrow's three corners, rewritten each _draw() rather than rebuilt —
## draw_colored_polygon() takes a PackedVector2Array, and constructing one per
## draw would be the feature's only steady-state allocation.
var _arrow_points: PackedVector2Array = PackedVector2Array()

## Teammate dots, in the same "segment pairs for ONE draw call" form the crocodile
## buffer uses — but through `draw_multiline_colors()`, because each teammate has
## its own stable colour and `draw_multiline()` takes exactly one. That variant
## wants ONE COLOUR PER SEGMENT (`colors.size() * 2 == points.size()`), which is
## why `_peer_colors` is half the length of `_peer_points`. Both are sized once to
## MAX_PEER_DOTS and never resized; the unused tail is parked off-control (and
## transparent) exactly like the crocodile tail.
var _peer_points: PackedVector2Array = PackedVector2Array()
var _peer_colors: PackedColorArray = PackedColorArray()
var _peer_count: int = 0

## Landmark X marks, in the teammate buffers' form with one difference: each marker
## is TWO segments (the crossing arms), so it is FOUR points and TWO colours, and
## `_landmark_colors` is again half the length of `_landmark_points` because
## `draw_multiline_colors()` wants one colour per SEGMENT. Both are sized once to
## MAX_LANDMARK_DOTS and never resized; the unused tail is parked off-control and
## transparent exactly like the crocodile and teammate tails. The per-segment
## colour is what carries the dimmed rim clamp through the SAME single draw call.
var _landmark_points: PackedVector2Array = PackedVector2Array()
var _landmark_colors: PackedColorArray = PackedColorArray()
var _landmark_count: int = 0

## The tower's cross, in the landmark buffers' exact form — TWO segments, so FOUR
## points and TWO colours, drawn by one `draw_multiline_colors()`.
##
## THE FIXED BUFFER IS ONE MARKER WIDE because there is exactly one tower in a
## world (`endless_terrain.tower_site()` is a function, not a list). `_tower_count`
## is therefore 0 or 1 and does the same job MAX_LANDMARK_DOTS does for the group
## scan: it is what parks the unused tail off-control when there is nothing to draw,
## which is the whole reason the layer never allocates on the tick.
var _tower_points: PackedVector2Array = PackedVector2Array()
var _tower_colors: PackedColorArray = PackedColorArray()
var _tower_count: int = 0

## The tower SHELL, from the "tower" group — cached with the stale re-fetch every
## other node reference here uses. It owns `sheltered()`, and the interior is
## parented at its origin, so its local frame is the interior's own.
var _tower_node: Node3D = null

## The two indoor caption fragments, composed on the tick and painted by `_draw()`.
## Both are "" whenever the player is not sheltered, which is the whole of how this
## feature disappears outdoors.
var _floor_text: String = ""
var _jail_text: String = ""

## Anti-stall bookkeeping, all of it reset on leaving the building. `_visited` is the
## set of `zone_at()` keys seen THIS VISIT (a few hundred short strings at worst),
## `_seen_floor` the highest storey reached, `_stall` the seconds since either last
## moved. `_jail_alpha` is 0 whenever no arrow is drawn.
var _visited: Dictionary = {}
var _seen_floor: int = -1
var _stall: float = 0.0
var _jail_alpha: float = 0.0
var _jail_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	# Never let the map eat clicks meant for the game or the touch UI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Group registration so anything could find/toggle us later without a hard
	# reference (same convention as perf_overlay.gd).
	add_to_group("minimap")
	# The arrow is always exactly three corners, so size it once and never again.
	_arrow_points.resize(3)
	# ...and so is the anti-stall arrow at the rim.
	_jail_points.resize(3)
	# The crocodile buffer is sized ONCE to its hard cap and never resized: see
	# PARKED_SEGMENT for how the unused tail is kept out of the picture.
	_croc_points.resize(MAX_CROC_DOTS * 2)
	# Same discipline for the teammate buffers — two points and ONE colour per dot.
	_peer_points.resize(MAX_PEER_DOTS * 2)
	_peer_colors.resize(MAX_PEER_DOTS)
	# And for the landmarks — FOUR points and TWO colours per X (two segments).
	_landmark_points.resize(MAX_LANDMARK_DOTS * 4)
	_landmark_colors.resize(MAX_LANDMARK_DOTS * 2)
	# And for the ONE tower — same shape, one marker's worth (see _tower_points).
	_tower_points.resize(4)
	_tower_colors.resize(2)
	# The terrain field: worst case is every cell its own run, i.e. one bar per
	# cell — two points and one colour each. Sized once here for that worst case so
	# the tick never allocates and no run is ever dropped (see _gather_terrain).
	_terrain_points.resize(TERRAIN_GRID * TERRAIN_GRID * 2)
	_terrain_colors.resize(TERRAIN_GRID * TERRAIN_GRID)
	_build_zoom_buttons()


func _input(event: InputEvent) -> void:
	# Raw keycode read (not a named action) — see TOGGLE_KEYCODE.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEYCODE:
			visible = not visible
			if visible:
				# Refresh immediately so it reappears with live data, not the
				# snapshot from whenever it was hidden.
				_time_until_tick = 0.0
			return
		# Zoom only while the map is up: with it hidden there is nothing to zoom,
		# and silently eating +/- from a hidden HUD is how a key ends up "not
		# working" somewhere else later.
		if not visible:
			return
		if ZOOM_IN_KEYCODES.has(event.keycode):
			_zoom_by(-1)
		elif ZOOM_OUT_KEYCODES.has(event.keycode):
			_zoom_by(1)


func _zoom_by(step: int) -> void:
	"""Step the zoom, clamped at both ends. `step` is a move through ZOOM_RADII, so
	-1 zooms IN (a smaller world radius) and +1 zooms out."""
	var next := clampi(_zoom_index + step, 0, ZOOM_RADII.size() - 1)
	if next == _zoom_index:
		return
	_zoom_index = next
	# Re-read on the next frame rather than at the tick's leisure: a zoom is a
	# deliberate press and a fifth of a second of the old scale reads as lag.
	_time_until_tick = 0.0


func _view_radius() -> float:
	"""World metres from the centre of the disc to its rim, at the current zoom.

	THIS AND `_map_scale()` ARE THE ONLY PLACES THE MAP'S REACH IS DEFINED. Every
	layer — the road window, the crocodile radius (a fraction of this), the
	teammate dots and their rim clamp — derives from one of the two. A layer that
	hardcodes a metre count instead is a layer that silently stops agreeing with
	the picture at every zoom but the default, which is exactly what
	`minimap_selfcheck.gd`'s zoom checks are written to catch."""
	return ZOOM_RADII[_zoom_index]


func _map_scale() -> float:
	"""Pixels per world metre at the current zoom."""
	return MAP_RADIUS / _view_radius()


func _croc_view_radius() -> float:
	"""World metres within which a crocodile gets a dot — a fraction of the map's
	reach, so it follows the zoom (see CROC_VIEW_FRACTION)."""
	return _view_radius() * CROC_VIEW_FRACTION


func _build_zoom_buttons() -> void:
	"""A small +/- pair on the widget, for a phone with no keyboard.

	Gated on `MobileSensors.is_touch_session()` exactly like the rest of the touch
	UI, so on desktop these are never created and the map is byte-for-byte the
	control it was. FOCUS_NONE is not cosmetic: `ui_accept` is Space, Space is
	jump, and a focused button would fire on every jump for the rest of the run —
	the same rule `mp_ui._make_button()` documents. The labels are "+" and "-",
	which are symbols in every locale, so there is no CSV row to add."""
	if not MobileSensors.is_touch_session():
		return
	# Bottom-right of the disc, stacked so a thumb can reach both without covering
	# the player arrow at the centre.
	var right := MAP_CENTER.x + MAP_RADIUS - ZOOM_BUTTON_SIZE * 0.5
	var top := MAP_CENTER.y + MAP_RADIUS - ZOOM_BUTTON_SIZE * 2.0 - ZOOM_BUTTON_GAP
	_add_zoom_button("+", Vector2(right, top), -1)
	_add_zoom_button("-", Vector2(right, top + ZOOM_BUTTON_SIZE + ZOOM_BUTTON_GAP), 1)


func _add_zoom_button(label: String, at: Vector2, step: int) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE  # see _build_zoom_buttons
	button.position = at
	button.size = Vector2(ZOOM_BUTTON_SIZE, ZOOM_BUTTON_SIZE)
	button.pressed.connect(_zoom_by.bind(step))
	add_child(button)


func _process(delta: float) -> void:
	# Hidden costs nothing at all.
	if not visible:
		return
	_time_until_tick -= delta
	if _time_until_tick > 0.0:
		return
	_time_until_tick = TICK_INTERVAL
	_tick()


func _tick() -> void:
	"""Re-read the world into the snapshot _draw() paints from. This is the only
	place that touches the scene tree; it runs ~5 times a second."""
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		# No player — clear the map once instead of leaving a stale one painted.
		if _have_data:
			_have_data = false
			queue_redraw()
		return

	_player_pos = _player.global_position
	# Godot's convention: -Z is a body's forward. Reading it off the basis rather
	# than rebuilding it from rotation.y keeps us correct whatever the controller
	# does with its transform, and costs no sin/cos.
	var forward := -_player.global_transform.basis.z
	# World (x, z) maps to screen (x, y): north-up, +X right, +Z down.
	var facing := Vector2(forward.x, forward.z)
	_facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector2(1.0, 0.0)

	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")

	_gather_world()
	_gather_terrain()
	_gather_road()
	_gather_crocodiles()
	_gather_landmarks()
	_gather_tower()
	_gather_peers()
	_gather_shelter()

	_have_data = true
	queue_redraw()


func _gather_world() -> void:
	"""Biome + river underfoot: exactly TWO noise evaluations per tick.

	Both are pure functions of world position (endless_terrain documents them as
	safe to call every physics tick), so this is genuinely cheap. `_biome` is still
	read here, and separately from the terrain grid `_gather_terrain()` samples,
	because the CAPTION must name the biome the player is actually standing in — a
	grid cell is 12 px of map and its centre is not the player.

	RIVER BANDS ARE STILL NOT DRAWN, and now for a sharper reason than cost. A river
	is a ~8 m contour of the same field, which is 12 px at the default zoom — one
	TERRAIN_CELL. Sampling it on the terrain grid would catch roughly every other
	cell a river crosses, i.e. paint blue confetti along a line that is not the
	line, and a map that puts the water in the wrong place is exactly the failure
	the CPU/GPU parity contract exists to prevent. So the river stays what it was:
	the honest "~ river ~" caption for the band you are standing in. ponytail: if
	river bands are ever wanted on the disc they need contour tracing off the raw
	field value, not a denser grid — a denser grid only makes the confetti finer."""
	_biome = 0
	_in_river = false
	if _terrain == null:
		return
	if _terrain.has_method("biome_at"):
		var b: int = _terrain.biome_at(_player_pos.x, _player_pos.z)
		# Defensive clamp: the enum arrives as a plain int across the group
		# boundary, and it indexes our colour/name tables.
		_biome = clampi(b, 0, BIOME_NAMES.size() - 1)
	if _terrain.has_method("is_river_at"):
		_in_river = _terrain.is_river_at(_player_pos)


func _gather_terrain() -> void:
	"""Paint the biome FIELD across the disc — the map's bottom layer.

	WHY A GRID AT ALL. The map used to tint the whole disc with the ONE biome under
	the player, which answers "what am I in" and nothing about "what am I walking
	toward". The field is what the player steers by, so the field is what gets drawn.

	SHAPE OF THE WORK, and why it fits the tick budget:
	  * TERRAIN_GRID x TERRAIN_GRID cells over the disc's bounding square, and only
	    the ~78% whose centre falls inside the disc are sampled at all — 177 of 225
	    `biome_at()` calls, ~0.24 ms (see TERRAIN_GRID for the measurement).
	  * Each ROW is emitted as RUN-LENGTH bars: consecutive cells of the same biome
	    become ONE horizontal segment. The field is smooth at this scale so a row is
	    normally one or two bars, and the whole layer is ONE
	    `draw_multiline_colors()` at TERRAIN_CELL width — the same draw-call
	    discipline as the crocodile pack and the landmark X marks, and exactly the
	    same cost as the single tinted circle it replaces.
	  * Each row is clipped to the disc by its own CHORD, so the layer keeps the
	    circular silhouette instead of painting a square. The steps that leaves at
	    the rim are one cell tall and sit inside the smooth dark backdrop circle
	    that is still drawn underneath.

	EVERYTHING GEOMETRIC HERE COMES FROM MAP_RADIUS AND `_map_scale()`. TERRAIN_CELL
	is the disc's own diameter cut into TERRAIN_GRID and the world extent of a cell
	is that over the shared scale, so the grid covers exactly the disc at every zoom
	and there is no second number meaning "how far the map reaches"."""
	_terrain_count = 0
	# A scene with no terrain (or an older one without the API) simply has no
	# terrain layer — the dark backdrop disc underneath is what shows through.
	if _terrain != null and _terrain.has_method("biome_at"):
		# World metres per pixel — the inverse of the ONE shared scale factor.
		var metres_per_px := 1.0 / _map_scale()
		var origin := MAP_CENTER - Vector2(MAP_RADIUS, MAP_RADIUS)
		var half_cell := TERRAIN_CELL * 0.5
		for j in range(TERRAIN_GRID):
			var py := origin.y + (float(j) + 0.5) * TERRAIN_CELL
			var dy := py - MAP_CENTER.y
			# The chord at the bar's OUTER EDGE, never at its centre line. A bar is
			# TERRAIN_CELL tall, so clipping it to the centre-line chord hangs its
			# outer corners several pixels past the ring — the same "the mark's ink,
			# not its anchor" rule LANDMARK_MARK_REACH states for the landmark X.
			# The price is that the outermost row of the grid always comes out empty
			# (its outer edge sits exactly on the rim), so the field has a one-cell
			# flat cap top and bottom, over the dark backdrop disc that is still a
			# true circle. A cap inside the ring beats ink outside it.
			var edge := absf(dy) + half_cell
			var chord_sq := MAP_RADIUS * MAP_RADIUS - edge * edge
			if chord_sq <= 0.0:
				continue  # row's bar would not fit inside the disc
			var chord := sqrt(chord_sq)
			var left_limit := MAP_CENTER.x - chord
			var right_limit := MAP_CENTER.x + chord
			# The cells whose CENTRE falls inside the chord, solved directly rather
			# than tested per cell: centre i sits at origin.x + (i + 0.5) * CELL.
			var i0 := maxi(int(ceil((left_limit - origin.x) / TERRAIN_CELL - 0.5)), 0)
			var i1 := mini(int(floor((right_limit - origin.x) / TERRAIN_CELL - 0.5)), TERRAIN_GRID - 1)
			if i0 > i1:
				continue
			var world_z := _player_pos.z + dy * metres_per_px
			var run_biome := -1
			var run_left := 0.0
			for i in range(i0, i1 + 1):
				var px := origin.x + (float(i) + 0.5) * TERRAIN_CELL
				# The enum arrives as a plain int across the group boundary and
				# indexes our palette, so it is clamped like `_gather_world` does.
				var b: int = clampi(_terrain.biome_at(_player_pos.x + (px - MAP_CENTER.x) * metres_per_px,
					world_z), 0, BIOME_TINTS.size() - 1)
				if b == run_biome:
					continue  # extend the open run; nothing to emit yet
				if run_biome >= 0:
					_push_terrain_bar(run_left, px - half_cell, py, run_biome)
				run_biome = b
				# The first run of the row starts at the chord, not at its cell edge.
				run_left = maxf(px - half_cell, left_limit)
			# Flush the open run, ended at the chord for the same reason.
			_push_terrain_bar(run_left,
				minf(origin.x + (float(i1) + 1.0) * TERRAIN_CELL, right_limit), py, run_biome)
	# Park the unused tail off-control and transparent, for the reason every other
	# layer here parks its tail: the buffers are permanently sized so the tick never
	# allocates, and `draw_multiline_colors()` consumes the whole array. Parking the
	# WHOLE tail rather than only the slots that just went out of use was measured
	# and kept: it is ~5% of this layer's tick, and it is one fewer piece of state
	# than a high-water mark that four sibling layers here manage to live without.
	for i in range(_terrain_count * 2, _terrain_points.size()):
		_terrain_points[i] = PARKED_SEGMENT
	for i in range(_terrain_count, _terrain_colors.size()):
		_terrain_colors[i] = Color(0, 0, 0, 0)


func _push_terrain_bar(x0: float, x1: float, y: float, biome: int) -> void:
	"""Emit one run of same-biome cells as a horizontal bar. Zero-width runs (a run
	whose whole cell was clipped away by the chord) are dropped rather than emitted
	as a degenerate segment. The buffers are sized for one bar per cell, so there is
	no bound to check here and no run that can ever be silently lost."""
	if x1 <= x0 or biome < 0:
		return
	var p := _terrain_count * 2
	_terrain_points[p] = Vector2(x0, y)
	_terrain_points[p + 1] = Vector2(x1, y)
	_terrain_colors[_terrain_count] = BIOME_TINTS[biome]
	_terrain_count += 1


func _gather_road() -> void:
	"""Walk the terrain's EXISTING coin-road station cache across the map window.

	No road maths is duplicated and no cache is extended: the stations covering the
	player's own chunk are already cached (spawn_coins_in_chunk built them when the
	chunk loaded, and the cache is contiguous and never reset within a run), and the
	binary search is the terrain's own O(log n) helper. Anything outside the cached
	range is simply not drawn — a soft, silent degradation rather than a hitch.

	Stations step _road_spacing() (6 m) apart, so a 120 m window is ~20 points."""
	_road_count = 0
	# _road_points IS the draw buffer, so an empty window has to empty it too —
	# leaving the last window's points in place would paint a stale road.
	if _terrain == null or not _terrain.has_method("_road_first_k_at_or_after_x"):
		_road_points.resize(0)
		return
	var stations: Dictionary = _terrain.road_stations
	if stations.is_empty():
		_road_points.resize(0)
		return
	var k_min: int = _terrain.road_k_min
	var k_max: int = _terrain.road_k_max
	# The window is the map's reach at the CURRENT zoom, in both directions —
	# never a hardcoded metre count. See `_view_radius()`.
	var view := _view_radius()
	var k: int = _terrain._road_first_k_at_or_after_x(_player_pos.x - view)
	# The helper returns k_max + 1 when the whole cache lies left of us; clamping
	# to k_min also covers the case where our window starts before the cache.
	k = maxi(k, k_min)
	var x_limit := _player_pos.x + view
	var scale := _map_scale()
	# The road runs far enough in X to fill the window, but its Z can wander well
	# outside the disc, so each point is clamped to the rim rather than clipped: a
	# clamped point still shows the direction the road leaves in, and keeping the
	# polyline unbroken is what keeps it ONE draw call.
	var rim := MAP_RADIUS - ROAD_WIDTH * 0.5
	# Count first, resize once (only when the count actually changed), then fill.
	var k_start := k
	while k <= k_max and _road_count < MAX_ROAD_POINTS:
		var center: Vector2 = stations[k].center
		if center.x > x_limit:
			break
		_road_count += 1
		k += 1
	if _road_points.size() != _road_count:
		_road_points.resize(_road_count)
	for i in range(_road_count):
		# Station centres are (x, z) in world space; the same north-up mapping the
		# player arrow uses.
		var c: Vector2 = stations[k_start + i].center
		var p := Vector2(c.x - _player_pos.x, c.y - _player_pos.z) * scale
		_road_points[i] = MAP_CENTER + p.limit_length(rim)


func _gather_crocodiles() -> void:
	"""Crocodile dots, on THIS control's ~5 Hz tick — never a per-frame scan.

	The "crocodile" group holds every spawned croc in the active chunk field (the
	LOD manager sleeps the distant ones but never removes them), so this is one
	group fetch plus a squared-distance compare each; no square roots, and the
	positions land in a reused buffer. Reading the LOD manager's own 9 Hz scan
	instead would save this pass, but it would also mean a new cross-file contract
	for something this cheap.

	Each dot is stored as a short LINE SEGMENT (two points), not a centre: _draw()
	hands the whole array to one draw_multiline(), which is the difference between
	one draw call and one per crocodile. Measured with the F3 counters, draw_circle()
	per dot cost exactly 1 draw call each — fine at the 6 near the spawn point,
	40 out where the density gradient has ramped up."""
	_croc_count = 0
	var scale := _map_scale()
	var croc_view := _croc_view_radius()
	var radius_sq := croc_view * croc_view
	# Segment length is set EQUAL to the draw width below, so each dot rasterises as
	# a square blob. Halving it (the obvious "short stub") drew tall thin bars.
	var half := CROC_DOT_RADIUS
	for node in get_tree().get_nodes_in_group("crocodile"):
		if _croc_count >= MAX_CROC_DOTS:
			break
		var croc := node as Node3D
		if croc == null:
			continue
		var pos := croc.global_position
		var dx := pos.x - _player_pos.x
		var dz := pos.z - _player_pos.z
		if dx * dx + dz * dz > radius_sq:
			continue
		# A segment as long as it is wide: a dot, for one draw call across the pack.
		var c := MAP_CENTER + Vector2(dx, dz) * scale
		_croc_points[_croc_count * 2] = c - Vector2(half, 0.0)
		_croc_points[_croc_count * 2 + 1] = c + Vector2(half, 0.0)
		_croc_count += 1
	# draw_multiline() consumes the WHOLE array, and this one is permanently sized to
	# MAX_CROC_DOTS so the tick never allocates — so the unused tail is parked far
	# outside the control instead of being truncated away. A resize-to-fit here would
	# realloc on every tick where the dot count changed, which is most of them.
	for i in range(_croc_count * 2, _croc_points.size()):
		_croc_points[i] = PARKED_SEGMENT


func _gather_landmarks() -> void:
	"""Geo landmarks, on the same ~5 Hz tick — the map's "where is there something
	worth walking to" layer.

	The draw set needs no bookkeeping at all: `spawn_landmark_in_chunk` parents a
	mesh-free, script-free marker Node3D to the chunk and puts it in the "landmark"
	group, so the group holds exactly the landmarks whose chunks are loaded and a
	landmark that streams back in re-registers itself. Reading position off the node
	is the whole contract used here — the `name_key` / `fact_key` / `radius` metas
	belong to landmark_toast.gd, and a marker is deliberately mute on the map (the
	toast already names it on approach), so nothing here reads a meta and nothing
	here adds a string.

	Each marker is an X: two crossing SEGMENTS, so the whole set is ONE
	`draw_multiline_colors()` — the crocodile pack's draw-call discipline, through
	the `_colors` variant for the same reason the teammate layer uses it, since the
	rim clamp needs a per-marker alpha and `draw_multiline()` takes exactly one
	colour.

	OFF-MAP LANDMARKS ARE CLAMPED TO THE RIM AND DIMMED, not dropped, and unlike a
	teammate they stay an X rather than becoming a radial tick. A landmark does not
	move, so "further, that way" is answered by walking toward the mark and watching
	it slide inward; what a tick WOULD cost is the shape that says "monument"
	instead of "peer". Dropping them was the other option and it is the wrong one:
	the group spans the whole loaded field (~150 m on web, ~250 m on desktop) while
	the disc reaches 30-130 m, so at the default zoom most loaded landmarks are off
	it and the layer would be blank almost all the time."""
	_landmark_count = 0
	var scale := _map_scale()
	var arm := LANDMARK_MARK_RADIUS
	for node in get_tree().get_nodes_in_group("landmark"):
		if _landmark_count >= MAX_LANDMARK_DOTS:
			break
		var marker := node as Node3D
		if marker == null:
			continue
		# Same north-up mapping as every other layer, off the SAME shared scale:
		# world (x, z) → screen (x, y). See `_view_radius()`.
		var offset := Vector2(marker.global_position.x - _player_pos.x,
			marker.global_position.z - _player_pos.z) * scale
		var color := COLOR_LANDMARK
		var center: Vector2
		var dist := offset.length()
		if dist > MAP_RADIUS:
			# OFF THE MAP — classified against the DISC EDGE itself, never against
			# the inset the mark is drawn at, for the reason `_gather_peers` spells
			# out: testing against the inset declares the outer band of the disc
			# off-map and dims a landmark you can actually see. The division is safe
			# — this branch needs dist > MAP_RADIUS > 0.
			center = MAP_CENTER + (offset / dist) * (MAP_RADIUS - LANDMARK_MARK_REACH)
			color.a *= LANDMARK_EDGE_ALPHA
		else:
			# ON the map, pulled in by the mark's own REACH (see LANDMARK_MARK_REACH
			# — the corner, not the arm) so an X at the very edge of the view does
			# not poke past the ring. That moves it by at most that reach and never
			# changes the classification above.
			center = MAP_CENTER + offset.limit_length(MAP_RADIUS - LANDMARK_MARK_REACH)
		var p := _landmark_count * 4
		_landmark_points[p] = center + Vector2(-arm, -arm)
		_landmark_points[p + 1] = center + Vector2(arm, arm)
		_landmark_points[p + 2] = center + Vector2(-arm, arm)
		_landmark_points[p + 3] = center + Vector2(arm, -arm)
		_landmark_colors[_landmark_count * 2] = color
		_landmark_colors[_landmark_count * 2 + 1] = color
		_landmark_count += 1
	# Park the unused tail off-control and transparent, for the reason the crocodile
	# and teammate tails are parked: the buffers are permanently sized so the tick
	# never allocates, and `draw_multiline_colors()` consumes the whole array.
	for i in range(_landmark_count * 4, _landmark_points.size()):
		_landmark_points[i] = PARKED_SEGMENT
	for i in range(_landmark_count * 2, _landmark_colors.size()):
		_landmark_colors[i] = Color(0, 0, 0, 0)


func _gather_tower() -> void:
	"""The tower — GastroDefense HQ — as a mint cross, on the same ~5 Hz tick.

	THE ONE MARKER THAT IS NOT READ OFF A GROUP, and deliberately so. Every other
	layer here draws things that exist as nodes: a landmark is on the map because
	its chunk is loaded, a crocodile because it is spawned. The tower is 400 m away
	and its shell does not exist until you are nearly there — a group scan would
	show it only once you no longer needed the map to find it. So this layer asks
	the terrain where the tower IS (`tower_site()`, a pure memoized function of the
	run seed) rather than where its geometry currently is, and the mark is on the
	disc from the first frame of the run.

	That is one method call per tick with no allocation and no node walk — the
	memo behind `tower_site()` makes it two scalar compares — and the usual
	has_method() guard means a scene with an older terrain (or no terrain at all)
	simply has no tower layer instead of erroring.

	RIM-CLAMPED AND DIMMED when off the disc, by the landmark X's rule and for a
	sharper version of the landmark X's reason: the site is 400 m out and the map
	reaches 30-130 m, so for almost the whole journey the clamped mark IS the
	feature — it is the compass bearing that says "keep walking that way"."""
	_tower_count = 0
	if _terrain == null or not _terrain.has_method("tower_site"):
		# Park the empty buffer and leave: `draw_multiline_colors()` consumes the
		# whole array, so an unparked tail from a previous tick would keep drawing.
		_park_tower()
		return
	var site: Vector3 = _terrain.tower_site()
	# Same north-up mapping as every other layer, off the SAME shared scale.
	var offset := Vector2(site.x - _player_pos.x, site.z - _player_pos.z) * _map_scale()
	var color := COLOR_TOWER
	var center: Vector2
	var dist := offset.length()
	if dist > MAP_RADIUS:
		# OFF THE MAP — classified against the DISC EDGE, never against the inset
		# the mark is drawn at (see `_gather_landmarks` for what testing against the
		# inset costs). The division is safe: this branch needs dist > MAP_RADIUS > 0.
		center = MAP_CENTER + (offset / dist) * (MAP_RADIUS - TOWER_MARK_REACH)
		color.a *= LANDMARK_EDGE_ALPHA
	else:
		center = MAP_CENTER + offset.limit_length(MAP_RADIUS - TOWER_MARK_REACH)
	var arm := TOWER_MARK_RADIUS
	# An upright cross: one horizontal segment, one vertical (see TOWER_MARK_RADIUS
	# for why the shape and not the colour is what tells it from a landmark X).
	_tower_points[0] = center + Vector2(-arm, 0.0)
	_tower_points[1] = center + Vector2(arm, 0.0)
	_tower_points[2] = center + Vector2(0.0, -arm)
	_tower_points[3] = center + Vector2(0.0, arm)
	_tower_colors[0] = color
	_tower_colors[1] = color
	_tower_count = 1


func _gather_shelter() -> void:
	"""The indoor half of the caption, and the anti-stall arrow behind it.

	ONE GROUP LOOKUP AND ONE `sheltered()` CALL per 5 Hz tick while the shell exists,
	and while it does not (which is most of a run — the tower is built only within
	`DRAW_RADIUS` of the site) a null check. `sheltered()` is three compares and a
	transform; `current_floor()` and `zone_at()` are pure walks of `const` tables.

	MULTIPLAYER: the "player" group is the LOCAL player by contract, so every peer
	sees their own storey and their own stall timer, and nothing here is relayed."""
	if _tower_node == null or not is_instance_valid(_tower_node):
		_tower_node = get_tree().get_first_node_in_group("tower") as Node3D
	if _tower_node == null or not _tower_node.has_method("sheltered") \
			or not _tower_node.sheltered(_player_pos):
		# OUTSIDE. Everything this feature knows is forgotten, so the next visit
		# starts a fresh set of rooms and a fresh timer.
		_floor_text = ""
		_jail_text = ""
		_jail_alpha = 0.0
		_stall = 0.0
		_seen_floor = -1
		if not _visited.is_empty():
			_visited.clear()
		return

	# The interior is parented at the shell's own origin (endless_terrain builds it
	# that way), so the shell's local frame IS the interior's — which is the frame
	# every `TowerInterior` static below is written in.
	var local: Vector3 = _tower_node.to_local(_player_pos)
	var here: int = TowerInterior.current_floor(local.y)
	var jail: int = TowerInterior.block_floor()
	# +1 because `current_floor()` answers a FLOOR_Y index and a lift says storeys:
	# the cell block is drawn on index 9 and the building calls it storey 10, which
	# is what the plans, the fiction and this caption all say.
	_floor_text = tr("Floor %d") % (here + 1)
	var degraded := TowerInterior.is_maze_floor(here)
	if jail < 0:
		# No storey draws the block — nothing honest to say about where it is.
		_jail_text = ""
	else:
		var delta := jail - here
		var chevron := ""
		if delta != 0:
			chevron = "  %s%d" % ["^" if delta > 0 else "v", absi(delta)]
		# THE LABYRINTH DEGRADES RATHER THAN GOING BLANK: the storey delta stays
		# (you can always count floors), the target lock is what the maze jams.
		_jail_text = (tr("NO LOCK") if degraded else tr("JAIL F%d") % (jail + 1)) + chevron

	# --- progress, and the stall timer behind it ---------------------------------
	if _seen_floor < 0:
		# First tick of this visit.
		_visited.clear()
		_seen_floor = here
		_stall = 0.0
	var zone := TowerInterior.zone_at(local)
	var progress := here > _seen_floor or (zone != "" and not _visited.has(zone))
	if zone != "":
		_visited[zone] = true
	_seen_floor = maxi(_seen_floor, here)
	_stall = 0.0 if progress else _stall + TICK_INTERVAL

	_gather_jail_arrow(jail, degraded)


func _gather_jail_arrow(jail: int, degraded: bool) -> void:
	"""The rim arrow — ANTI-STALL ONLY, and never a bearing you can navigate by.

	It exists for the player who has been going nowhere for `STALL_SECONDS`, and it
	is gone the instant they find a room they have not been in. In the labyrinth it
	flickers on a coarse bearing instead of holding a true one, because up there the
	line above it says NO LOCK and a degraded system that quietly starts working is
	a lie the fiction cannot afford."""
	_jail_alpha = 0.0
	if jail < 0 or _stall < STALL_SECONDS:
		return
	if degraded and fmod(_stall - STALL_SECONDS, MAZE_FLICKER_PERIOD) >= MAZE_FLICKER_ON:
		return
	# The gallery's own centre, off the confinement box the prison role already
	# derives from the plan — no second lookup of where the block is.
	var target: Vector3 = _tower_node.to_global(
			(TowerInterior.block_min() + TowerInterior.block_max()) * 0.5)
	var offset := Vector2(target.x - _player_pos.x, target.z - _player_pos.z)
	if offset.length_squared() < 0.0001:
		return
	var dir := offset.normalized()
	if degraded:
		dir = Vector2.from_angle(snappedf(dir.angle(), MAZE_BEARING_STEP))
	_jail_alpha = clampf((_stall - STALL_SECONDS) / STALL_FADE, 0.0, 1.0)
	# A triangle at the rim, pointing out along the bearing — the player arrow's
	# shape and construction, so there is no second piece of trigonometry here.
	var perp := Vector2(-dir.y, dir.x)
	var tip := MAP_CENTER + dir * (MAP_RADIUS - 1.0)
	var tail := tip - dir * JAIL_ARROW_LENGTH * 2.0
	_jail_points[0] = tip
	_jail_points[1] = tail + perp * JAIL_ARROW_HALF_WIDTH
	_jail_points[2] = tail - perp * JAIL_ARROW_HALF_WIDTH


func _park_tower() -> void:
	"""Push the tower buffer off-control and transparent, exactly as every other
	layer parks its unused tail."""
	for i in _tower_points.size():
		_tower_points[i] = PARKED_SEGMENT
	for i in _tower_colors.size():
		_tower_colors[i] = Color(0, 0, 0, 0)


func _gather_peers() -> void:
	"""Multiplayer teammates, on the same ~5 Hz tick.

	Solo this is one group lookup and one `== null` test: `MpManager.peer_markers()`
	answers null whenever there is no room, so the whole layer costs nothing and
	draws nothing — the map is byte-for-byte what it was before multiplayer. The
	reach across the boundary is the project's standard group lookup plus a
	has_method() guard, so a scene without the manager (or an older build of it)
	simply has no teammate layer rather than erroring.

	Each teammate becomes one segment pair plus one colour, for a SINGLE
	`draw_multiline_colors()` across the whole room — the crocodile pack's
	draw-call discipline, with the per-peer colour that `draw_multiline()` cannot
	carry. Off-map teammates are CLAMPED to the rim rather than dropped, and
	drawn as an outward radial tick instead of a blob, so the map still answers
	"which way is my team" when they are a chunk away."""
	_peer_count = 0
	if _mp == null or not is_instance_valid(_mp):
		_mp = get_tree().get_first_node_in_group("mp")
	if _mp != null and _mp.has_method("peer_markers"):
		var markers: Variant = _mp.peer_markers()
		if markers is Array:
			var scale := _map_scale()
			# OFF-MAP IS CLASSIFIED AGAINST THE DISC EDGE ITSELF, never against an
			# inset. The two are easy to conflate — the tick has to START inset so
			# it does not poke past the ring — but using the inset as the TEST too
			# declares the outer band of the map off-map: at MAP_RADIUS 62 and a
			# PEER_EDGE_TICK 7 inset, a teammate anywhere in the outer 11% of the
			# disc (54-60 m at the default zoom) would be drawn as an outward "keep
			# going that way" tick while actually standing inside the view.
			for entry: Variant in markers:
				if _peer_count >= MAX_PEER_DOTS:
					break
				if not (entry is Dictionary):
					continue
				var marker: Dictionary = entry
				var pos: Vector3 = marker.get("pos", Vector3.ZERO)
				var color: Color = marker.get("color", COLOR_PLAYER)
				var offset := Vector2(pos.x - _player_pos.x, pos.z - _player_pos.z) * scale
				var a: Vector2
				var b: Vector2
				var dist := offset.length()
				if dist > MAP_RADIUS:
					# OFF THE MAP: a tick ending ON the rim and pointing out along
					# the bearing. Only the tick's own length is inset (the division
					# is safe — this branch needs dist > MAP_RADIUS > 0).
					var dir := offset / dist
					a = MAP_CENTER + dir * (MAP_RADIUS - PEER_EDGE_TICK)
					b = MAP_CENTER + dir * MAP_RADIUS
					color.a *= PEER_EDGE_ALPHA
				else:
					# ON the map: a segment as long as it is wide, i.e. a dot — the
					# same trick the crocodile dots use. The centre is pulled in by
					# the dot's own radius so a teammate right at the view's edge
					# does not have their blob poke past the ring; that moves the
					# dot by at most PEER_DOT_RADIUS and never changes the
					# on-map/off-map classification above.
					var c := MAP_CENTER + offset.limit_length(MAP_RADIUS - PEER_DOT_RADIUS)
					a = c - Vector2(PEER_DOT_RADIUS, 0.0)
					b = c + Vector2(PEER_DOT_RADIUS, 0.0)
				_peer_points[_peer_count * 2] = a
				_peer_points[_peer_count * 2 + 1] = b
				_peer_colors[_peer_count] = color
				_peer_count += 1
	# Park the unused tail off-control and transparent, for the reason the
	# crocodile tail is parked: the buffers are permanently sized so the tick never
	# allocates, and `draw_multiline_colors()` consumes the whole array.
	for i in range(_peer_count * 2, _peer_points.size()):
		_peer_points[i] = PARKED_SEGMENT
	for i in range(_peer_count, _peer_colors.size()):
		_peer_colors[i] = Color(0, 0, 0, 0)


# ============================================================================
# DRAWING (snapshot only — no node lookups, no allocation)
# ============================================================================

func _draw() -> void:
	if not _have_data:
		return

	# 1. The backdrop, painted outside-in: rim ring, dark disc, then the biome FIELD.
	#    Two filled circles — see RIM_WIDTH for why the rim is not a draw_arc() —
	#    plus ONE multiline for the whole terrain layer, which is the same draw-call
	#    cost as the single whole-disc tint circle it replaced. The dark disc stays
	#    underneath: it is what gives the map its smooth circular edge (the terrain
	#    rows are chord-clipped, so their own silhouette is stepped by one cell) and
	#    what shows through in a scene with no terrain at all.
	draw_circle(MAP_CENTER, MAP_RADIUS + RIM_WIDTH, COLOR_RIM)
	draw_circle(MAP_CENTER, MAP_RADIUS, COLOR_BACKDROP)
	if _terrain_count > 0:
		draw_multiline_colors(_terrain_points, _terrain_colors, TERRAIN_CELL)

	# 2. The coin road: ONE polyline for the whole window. The per-segment
	#    draw_line() version this replaced cost ~20 draw calls on its own — the
	#    single biggest line item in the map's budget — because antialiased lines
	#    do not batch. The points are already absolute and rim-clamped.
	if _road_count >= 2:
		draw_polyline(_road_points, COLOR_ROAD, ROAD_WIDTH, true)

	# 2b. Landmarks — ONE draw call for every X on screen (see _gather_landmarks),
	#     and ZERO while no landmark chunk is loaded. Under the crocodiles on
	#     purpose: a destination must never hide a threat.
	if _landmark_count > 0:
		draw_multiline_colors(_landmark_points, _landmark_colors, LANDMARK_MARK_WIDTH)

	# 2c. The tower — ONE draw call, and OVER the landmarks: there is one of it in
	#     the world and it is where the player is going, so it is the one
	#     destination allowed to sit on top of another. Still under the crocodiles,
	#     for the landmark layer's reason: a destination must never hide a threat.
	if _tower_count > 0:
		draw_multiline_colors(_tower_points, _tower_colors, TOWER_MARK_WIDTH)

	# 3. Crocodiles — one draw call for the whole pack (see _gather_crocodiles).
	if _croc_count > 0:
		draw_multiline(_croc_points, COLOR_CROC, CROC_DOT_RADIUS * 2.0)

	# 3b. Teammates — ONE draw call for the whole room, in their own colours (see
	#     _gather_peers). Zero calls solo, where _peer_count is never above 0.
	if _peer_count > 0:
		draw_multiline_colors(_peer_points, _peer_colors, PEER_DOT_RADIUS * 2.0)

	# 4. The player: a triangle at the centre pointing the way the character faces.
	#    Built from the cached facing vector and its perpendicular — no trig here.
	var perp := Vector2(-_facing.y, _facing.x)
	var tail := MAP_CENTER - _facing * ARROW_LENGTH * 0.6
	_arrow_points[0] = MAP_CENTER + _facing * ARROW_LENGTH
	_arrow_points[1] = tail + perp * ARROW_HALF_WIDTH
	_arrow_points[2] = tail - perp * ARROW_HALF_WIDTH
	draw_colored_polygon(_arrow_points, COLOR_PLAYER)

	# 4b. The anti-stall arrow, ONE draw call and only while `_jail_alpha` is above
	#     zero — which is never outdoors, and indoors only after STALL_SECONDS
	#     without progress (see _gather_jail_arrow).
	if _jail_alpha > 0.0:
		draw_colored_polygon(_jail_points, Color(COLOR_JAIL, _jail_alpha))

	# 5. Coordinates + biome under the disc, as ONE two-line string. X is also the
	#    run's distance score (the coin road's X is strictly increasing by
	#    construction), so the number doubles as "how far have I got". The outline
	#    is not optional: this text sits outside the dark disc, over whatever the
	#    world happens to be, and the sky here is nearly white.
	#    The two words are `tr()`d individually: this caption is painted with
	#    `draw_multiline_string`, not assigned to a `Control.text`, so Godot's
	#    automatic Control translation never sees it. X and Z are axis letters and
	#    stay as they are. `_draw()` re-runs on the 0.2 s tick, so a language
	#    switched mid-run reaches this caption within one tick like everything else.
	var text := "X %d   Z %d" % [roundi(_player_pos.x), roundi(_player_pos.z)]
	# INDOORS, the storey goes BESIDE THE COORDINATES and the jail's floor beside the
	# biome — two fragments composed on the tick, appended to the two lines the
	# caption already has. A third line would need a taller control (see
	# minimap_selfcheck's widget-rect check) to say what fits on these two.
	if not _floor_text.is_empty():
		text += "   " + _floor_text
	text += "\n" + tr(BIOME_NAMES[_biome])
	var color := COLOR_TEXT
	if _in_river:
		text += tr("  ~ river ~")
		color = COLOR_RIVER_TEXT
	if not _jail_text.is_empty():
		text += "   " + _jail_text
	# draw_multiline_string* is what keeps this at 2 draw calls instead of 4: the
	# per-line draw_string()/draw_string_outline() pair it replaced cost one each.
	var font := get_theme_default_font()
	var pos := Vector2(0.0, MAP_CENTER.y + MAP_RADIUS + TEXT_TOP_GAP)
	font.draw_multiline_string_outline(get_canvas_item(), pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, TEXT_SIZE, -1, 4, Color(0, 0, 0, 0.85))
	font.draw_multiline_string(get_canvas_item(), pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, TEXT_SIZE, -1, color)
