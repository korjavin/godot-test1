class_name HudTheme
extends RefCounted
## ============================================================================
## THE HUD'S ONE STYLE SOURCE — "CrimeKickers style", off the films
## ============================================================================
## Owner ruling 2026-09-05 (epic `godot-test1-y1o`): the HUD's reference is the
## intro and ending FILMS. The look, in one sentence: a graphic-novel
## corporate-dystopia card — ink-black grounds, tall condensed BONE-WHITE
## capitals with a hard drop shadow, cold steel-blue night light, and exactly one
## warm accent (the GD-RTV visor amber). **Nothing is rounded, nothing glows
## softly, nothing is translucent-glassy.**
##
## Every number below was measured off the GAME OVER title card and the film's
## night-yard shots, and it is typed ONCE — here. A second copy of `#13171b` in
## another script is the bug this file exists to prevent, and
## `hero_hud_selfcheck` check 8 greps for exactly that.
##
## ---------------------------------------------------------------------------
## TWO KINDS OF CONSUMER, AND THEY TAKE DIFFERENT THINGS
## ---------------------------------------------------------------------------
##   * **Control-based panels** (the MP panel, the help card, the skill tree, the
##     start card) adopt `theme = HudTheme.theme()` **on their own ROOT Control**.
##     Never `ProjectSettings`, never a `Theme` on the scene root: a project-wide
##     flip restyles every `Control` in the game at once and moves every German
##     width budget in one PR, which is precisely the thing the per-panel beads
##     exist to do one at a time.
##   * **`draw_*`-based HUDs** (`hero_hud`, `ability_hud`, `minimap_hud`) read the
##     consts directly. A `Theme` has nothing to say to `draw_rect`, so they take
##     the colours, the fonts and `OUTLINE_PX` / `SHADOW_OFFSET` and paint.
##
## `extends RefCounted` and everything `static`: this is a namespace, not a node.
## It is a SCRIPT dependency (`class_name`), which is what a table of constants
## is allowed to be — the group-discovery convention is about live nodes.

# ============================================================================
# PALETTE — six named colours, and the six are the whole vocabulary
# ============================================================================
## Card ground: the GAME OVER card's black, 54% of that frame. Panels take it at
## `PANEL_ALPHA` over the world; a title card takes it opaque.
const INK: Color = Color("#13171b")
## A raised strip, a secondary panel, a button face — the blurred cell block
## behind the film's title.
const INK_RAISED: Color = Color("#262c31")
## The film's night-yard blue-grey: dividers, inactive text, frames, borders.
const STEEL: Color = Color("#526671")
## Lettering and icons. Measured 230,228,216 on "GAME OVER" — never pure white.
const BONE: Color = Color("#e6e4d8")
## GD-RTV armour: "a teammate has him", neutral, disabled — and the corporate
## cutlery stamp.
const UNIT_KHAKI: Color = Color("#b3ab98")
## THE ONE ACCENT (visor glow #f0a030, the comic SFX lettering #e88127): the
## active hero ring, focus, the coin counter, "NEW BEST!", the ability dial.
## **Use it sparingly — one amber thing per screen region.**
const VISOR_AMBER: Color = Color("#f2a33a")

## What is deliberately NOT here, because it is SEMANTIC rather than stylistic
## and a palette pass may not quietly recolour it: the per-hero identity tints
## (`hero_hud.HERO_COLORS`), the captive cell bars' red, the speaking green
## (`remote_avatar.LABEL_SPEAKING_COLOR`), and the minimap's biome RGB, which is
## copied from `ground.gdshader` and is not ours to change.

## A panel sits at this alpha over the world; a modal card is opaque.
const PANEL_ALPHA: float = 0.88

## THE VEIL over something you cannot have — a held hero's tile, a disabled row.
## INK to dim it, pulled a little way toward the corporation's own khaki so
## "GD-RTV has this" reads as their grey-brown rather than as a plain shadow.
##
## A VEIL COMPOSITES TOWARD ITS OWN LUMINANCE, so everything DARKER than it comes
## out BRIGHTER — and the lerp is 0.08 rather than anything prettier for exactly
## that reason. At a quarter khaki the veil's luminance is 0.23, which lifted a
## fifth of Primm's portrait instead of dimming it and halved the FREE-vs-HELD
## read; at 0.08 it is 0.13, which still lifts the darkest 5-15% of a portrait
## (any veil above pure black lifts something — the honest claim is a BOUND, not
## "every pixel") and dims the rest to 79-90% of what the retired plain black
## veil managed, with the alpha raised 0.62 -> 0.72 to buy most of that back. `hero_hud_selfcheck` check 8 measures both ends —
## the ceiling on the veil's own luminance and the floor on how much it dims —
## because "unavailable" reading as "slightly greyer" is invisible in a diff.
##
## A `static func` and not a `const` because a `const` may not call a method, and
## the alternative was a seventh hex nobody could trace back to the two it came
## from — which is the one thing this file exists to prevent. A func rather than
## a `static var` so nothing can assign it, like `heading_font()` below.
const VEIL_KHAKI_MIX: float = 0.08
const VEIL_ALPHA: float = 0.72


static func veil() -> Color:
	return Color(INK.lerp(UNIT_KHAKI, VEIL_KHAKI_MIX), VEIL_ALPHA)

# ============================================================================
# TYPOGRAPHY
# ============================================================================
## Oswald (SIL OFL 1.1, `assets/fonts/OFL.txt` ships beside it). A tall condensed
## grotesque — Godot's default is a wide humanist sans and cannot fake the title
## card. Chosen over Bebas Neue because Oswald has lowercase AND full Latin-1
## (ß, ä/ö/ü), which the German table needs; `locale_selfcheck` measures the
## budgets on THIS face for exactly that reason.
##
## RULES, and they live at the DRAW SITE rather than in the table: headings and
## HUD numerals are ALL CAPS via `.to_upper()` — never in `ui.csv`, where the
## translation key IS the English source string; body text is sentence case.
const FONT_BOLD: FontFile = preload("res://assets/fonts/Oswald-Bold.ttf")
const FONT_REGULAR: FontFile = preload("res://assets/fonts/Oswald-Regular.ttf")

const HEADING_FONT_SIZE: int = 20
const BODY_FONT_SIZE: int = 14

## THE WORLD-SIDE LETTERING CONTRACT. Every string drawn ON the world rather than
## on a card gets a hard 2 px INK outline and a 1 px down-right shadow — which is
## the `draw_string_outline` idiom `hero_hud` and `ability_hud` already use, now
## fed the palette instead of black.
##
## READ THE UNIT BEFORE YOU PASS IT: this is 2 px OF INK, but Godot's
## `draw_string_outline(..., size, ...)` grows the glyph in BOTH directions, so a
## 2 px stroke is `OUTLINE_PX * 2` at the call site — which is what `hero_hud`
## passes, and what every panel bead after it must pass. Doubling at the call
## rather than storing 4 here keeps the constant meaning the thing the spec says.
const OUTLINE_PX: int = 2
const SHADOW_OFFSET: Vector2 = Vector2(1.0, 1.0)

## The panel language: hard edges, and a HARD shadow. `StyleBoxFlat.shadow_size`
## is a solid EXPANSION of the shadow rect and never a blur, so the offset shadow
## below is hard by construction; `anti_aliasing` only feathers the box's own edge
## by `anti_aliasing_size` and is documented as visible on rounded corners and
## skew, neither of which this file permits. It is turned off anyway, because a
## feathered edge is the one thing that could creep back in the day somebody adds
## a radius — belt and braces, not the mechanism.
const BORDER_PX: int = 1
const BORDER_MODAL_PX: int = 2
const SHADOW_PX: int = 2
const SHADOW_PANEL_OFFSET: Vector2i = Vector2i(2, 2)
const SHADOW_ALPHA: float = 0.6
## An 8 px grid, 12 px inside a card.
const GRID: int = 8
const CARD_PADDING: int = 12


static func heading_font() -> FontFile:
	return FONT_BOLD


static func body_font() -> FontFile:
	return FONT_REGULAR


# ============================================================================
# STYLEBOX BUILDERS — the three shapes a panel is made of
# ============================================================================
## They RETURN a fresh box rather than handing out a shared one: a `StyleBox` is
## a Resource and a caller that tweaked a shared instance would restyle every
## other panel in the game. `theme()` below builds its own set once.

static func card(modal: bool = false) -> StyleBoxFlat:
	"""
	A panel's ground: INK, hard-edged, a STEEL frame and a hard offset shadow.
	`modal` is the title-card case — opaque, and a 2 px frame.
	"""
	var box := _flat(INK if modal else Color(INK, PANEL_ALPHA))
	box.set_border_width_all(BORDER_MODAL_PX if modal else BORDER_PX)
	box.border_color = STEEL
	box.set_content_margin_all(CARD_PADDING)
	box.shadow_color = Color(INK, SHADOW_ALPHA)
	box.shadow_size = SHADOW_PX
	box.shadow_offset = Vector2(SHADOW_PANEL_OFFSET)
	return box


static func strip() -> StyleBoxFlat:
	"""A raised secondary strip inside a card — a member row, a lift stop, a
	key cap. No shadow: it is already on a card."""
	var box := _flat(INK_RAISED)
	box.set_border_width_all(BORDER_PX)
	box.border_color = STEEL
	box.content_margin_left = GRID
	box.content_margin_right = GRID
	box.content_margin_top = GRID / 2
	box.content_margin_bottom = GRID / 2
	return box


static func button(state: String = "normal") -> StyleBoxFlat:
	"""
	One button face. `state` is "normal" / "hover" / "pressed" / "disabled" /
	"focus", spelled the way Godot's own `Button` theme slots are so `theme()`
	below can loop over them.

	Only the FRAME moves on hover (STEEL -> VISOR_AMBER) and only the FACE on
	press (INK_RAISED -> INK): the film has no lit-up buttons, and the accent is
	rationed to one amber thing per region.
	"""
	# The spec gives DISABLED the same ink ground as a pressed button: a control
	# you cannot use must not share the raised face of one you can.
	var box := _flat(INK if state == "pressed" or state == "disabled" else INK_RAISED)
	box.set_border_width_all(BORDER_PX)
	box.border_color = VISOR_AMBER if state == "hover" or state == "focus" else STEEL
	if state == "focus":
		# A focus ring draws OVER the face, so it must not paint one.
		box.draw_center = false
	box.content_margin_left = CARD_PADDING
	box.content_margin_right = CARD_PADDING
	box.content_margin_top = GRID / 2
	box.content_margin_bottom = GRID / 2
	return box


static func _flat(ground: Color) -> StyleBoxFlat:
	"""Every box in this file starts here: square corners, no anti-aliasing —
	which is what keeps `shadow_size` a HARD offset rather than a blur."""
	var box := StyleBoxFlat.new()
	box.bg_color = ground
	box.set_corner_radius_all(0)
	box.anti_aliasing = false
	return box


# ============================================================================
# THE THEME — built once, adopted per ROOT Control
# ============================================================================
## Lazy because it is a Resource nobody needs until a Control-based panel opens,
## and because a `const` cannot hold one. It is SHARED, which is the point: ten
## panels adopting it cost one Theme, and a panel that wants something else
## overrides that one slot on itself rather than rebuilding this.
static var _theme: Theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = FONT_REGULAR
	t.default_font_size = BODY_FONT_SIZE

	t.set_stylebox("panel", "Panel", card())
	t.set_stylebox("panel", "PanelContainer", card())

	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", button(state))
	t.set_color("font_color", "Button", BONE)
	t.set_color("font_hover_color", "Button", BONE)
	t.set_color("font_pressed_color", "Button", BONE)
	t.set_color("font_disabled_color", "Button", UNIT_KHAKI)
	t.set_font("font", "Button", FONT_BOLD)   # button labels are caps at the draw site

	t.set_color("font_color", "Label", BONE)
	t.set_font("font", "Label", FONT_REGULAR)

	# ponytail: the bead names CheckBox and this project instantiates none — its one
	# checkbox-shaped control is `mobile_settings_panel`'s CheckButton, which
	# inherits Button's slots through the class chain and so is already styled.
	# Left as the bead specified rather than silently retargeted; `.29`/`.30` own
	# the call, and either way the locale ruler covers both weights.
	t.set_color("font_color", "CheckBox", BONE)
	t.set_color("font_disabled_color", "CheckBox", UNIT_KHAKI)
	t.set_font("font", "CheckBox", FONT_REGULAR)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "CheckBox", button(state))

	_theme = t
	return _theme

# ponytail: no title font size and no BONE-hairline builder yet — the modal card
# beads (y1o.28/.31/.32) are their only consumers and can add both when they land.
# `HEADING_FONT_SIZE` and `SHADOW_OFFSET` have no reader yet either, and unlike
# those two they STAY: the bead names both as part of the seam it is measured on,
# and a per-panel bead that had to invent its own heading size is the drift this
# file exists to stop.
