class_name LandmarkBuilders
extends RefCounted
## THE GEO-LANDMARK REGISTRY AND ITS SHAPE BUILDERS — the "which famous places
## exist and what does each one look like" half of the feature, lifted whole out
## of endless_terrain.gd so that adding a place is an edit to ONE file that
## nothing else in the project has to know about.
##
## THE SPLIT, and why it falls exactly here. endless_terrain.gd keeps the
## POLICY — WHERE each place stands (the MUSEUM MILE: one site per kind, chosen
## from run_seed alone and read back by `_landmark_at`), how far off the coin road
## it must sit, how its reward ring and its crocodile-exclusion footprint are
## sized (spawn_landmark_in_chunk).
## This file keeps the CONTENT — the palette, the registry, and the builder that
## turns a spot into stone. Policy is about the WORLD and reads a dozen sibling
## constants; content is about a PLACE and reads none of them. That is the whole
## seam, and it is why LANDMARK_RADIUS (a bound the placement test hands to
## _biome_spot_ok before any builder has run) stays over there while each entry's
## own `radius` lives in the registry here.
##
## THE REGISTRY IS THE EXTENSION POINT, and it is in this file precisely so the
## builder it names is a screen away rather than a file away: a new famous place
## is ONE builder function, ONE registry entry and TWO ui.csv rows, all of them
## here except the CSV. Nothing in endless_terrain.gd, in landmark_toast.gd or in
## landmark_selfcheck.gd has to learn about it.
##
## WHY STATIC FUNCTIONS THAT TAKE `terrain`. A builder's whole job is to append
## boxes to the chunk's ONE MultiMesh batch and ONE BlockCollision body, which it
## does through the terrain's own create_box / _spawn_artifact_accent /
## _get_camp_ember_material. Handing it the terrain as a plain first argument
## keeps that call unchanged and costs no object: there is no builder state to
## hold, so there is nothing to instantiate, and the dispatch stays the same one
## line it was — LandmarkBuilders.call(entry.builder, self, ...) — because
## Object.call() dispatches a GDScript static method exactly as it dispatched the
## method when it lived on the terrain node.
##
## ponytail: `terrain` is typed Node3D rather than a terrain class, because
## endless_terrain.gd declares no class_name and giving it one to satisfy a
## parameter hint would be a bigger change than the move it enables. The cost is
## that create_box is resolved dynamically; the self-check calls every builder in
## the registry, so a rename still fails loudly rather than in one chunk in fifty.

## --- Palette. Deliberately distinct from the warm RAMP_* block ramps, the
## artifacts' grey-green weathered stone and the camps' bone white, because the
## whole point of a landmark is that it does not read as scenery. Each place gets
## the colour a person would actually name it by.
const LM_STONE_GREY := Color(0.62, 0.61, 0.57)   # Stonehenge sarsen
const LM_BASALT := Color(0.34, 0.32, 0.30)       # Moai volcanic tuff
const LM_SANDSTONE := Color(0.80, 0.68, 0.44)    # Giza limestone
const LM_GRANITE := Color(0.48, 0.46, 0.47)      # plinths, pedestals, ahu
const LM_ORANGE := Color(0.75, 0.24, 0.10)       # Golden Gate International Orange
const LM_COPPER := Color(0.42, 0.71, 0.60)       # Liberty's oxidised copper
const LM_OCHRE := Color(0.72, 0.44, 0.24)        # Plaza Mayor walls
const LM_ROOF := Color(0.36, 0.20, 0.15)         # Plaza Mayor slate/tile trim
const LM_IRON := Color(0.45, 0.36, 0.28)         # Eiffel "brun tour Eiffel"
const LM_MARBLE := Color(0.93, 0.91, 0.87)       # Taj Mahal marble, Neuschwanstein limestone
## Wave 2. Only TWO new entries for ten new places, on purpose: a landmark is
## recognised by its silhouette, and every colour added is one more thing for a
## MultiMesh of grey boxes to fail to be distinct from. Where an existing entry is
## honestly the right colour it is reused — the Sphinx is Giza's own limestone,
## the Colosseum and the Great Wall are weathered sarsen grey, Cologne's soot-black
## Gothic stone is the Moai's basalt, and Neuschwanstein's white walls are the
## Taj's marble (its BLUE ROOFS are what tell the two apart at 30 m, which is
## exactly why the slate blue is one of the two that earned its place).
const LM_VERMILION := Color(0.78, 0.20, 0.14)    # Itsukushima torii lacquer
const LM_SLATE_BLUE := Color(0.30, 0.34, 0.45)   # Neuschwanstein's blue-grey spire roofs

## THE REGISTRY. Pure data, so it can be a `const` — and it is const precisely to
## make "add a place" a data edit rather than a code edit.
##
## `builder` is a METHOD-NAME STRING, invoked as call(entry.builder, ...). It is a
## String and not a Callable because a `const` Array cannot hold a Callable (a
## Callable binds an object at runtime, so it is not a constant expression); a
## String keeps the whole registry pure data and const-able, at the cost of the
## method name being checked at call time rather than parse time — which
## landmark_selfcheck.gd covers by calling every builder in the table.
##
## `name` and `fact` are the ENGLISH SOURCE STRINGS, not identifiers, because in
## this project THE TRANSLATION KEY IS THE ENGLISH SOURCE STRING (CLAUDE.md
## Localization RULE 1). The toast assigns them straight to a Label.text and gets
## translation AND live locale-switching for free, with no tr() call anywhere. Do
## not "fix" that by inventing HUD_LANDMARK_* keys — it would break the fallback
## that makes a place with no CSV row render as readable English.
##
## `radius` is that shape's OWN footprint radius (metres), which is what the
## reward ring and the obstacle footprint are measured from. It must be
## <= LANDMARK_RADIUS, and it must be a true bound on the stone the builder
## actually emits; landmark_selfcheck.gd measures both.
##
## `region` is one of exactly five words — europe / asia / africa / americas /
## oceania — and it exists for ONE consumer: quiz_options() below, which prefers
## distractors from the same region. It is deliberately a coarse continent word
## and not a country, because the only question it has to answer is "would these
## three names make a real quiz", and coarse is what makes that true. A new row
## MUST carry one from that set; landmark_selfcheck.gd's check 6 fails a row that
## invents a sixth word or forgets the field, because a missing region silently
## degrades that place's quiz to whole-table distractors rather than erroring.
##
## ORDER IS LOAD-BEARING ONLY IN THAT AN INDEX IS AN IDENTITY — since bead
## godot-test1-bcf a kind is unique in the world and its ROW INDEX is what
## `landmark_sites()` places, what the marker's `kind` meta carries and what
## `quiz_options` keys on. So APPENDING is free (a new row simply gets its own
## site) and REORDERING moves every landmark in every existing world, which is
## harmless because worlds are per-run anyway.
const LANDMARKS: Array = [
	{
		"builder": "_landmark_stonehenge",
		"name": "Stonehenge",
		"fact": "A Neolithic stone circle on Salisbury Plain, England, raised around 2500 BC.",
		"radius": 7.6,
		"region": "europe",
	},
	{
		"builder": "_landmark_moai",
		"name": "Moai of Easter Island",
		"fact": "Nearly 900 stone figures carved by the Rapa Nui on Easter Island, Chile, between 1250 and 1500.",
		"radius": 6.6,
		"region": "oceania",
	},
	{
		"builder": "_landmark_giza",
		"name": "Pyramids of Giza",
		"fact": "Three royal tombs near Cairo, Egypt, built around 2560 BC — the last surviving Wonder of the Ancient World.",
		"radius": 9.4,
		"region": "africa",
	},
	{
		"builder": "_landmark_golden_gate",
		"name": "Golden Gate Bridge",
		"fact": "A 2.7 km suspension bridge over San Francisco Bay, USA, opened in 1937 and painted International Orange.",
		"radius": 9.4,
		"region": "americas",
	},
	{
		"builder": "_landmark_liberty",
		"name": "Statue of Liberty",
		"fact": "A 93 m copper statue in New York Harbor, USA — a gift from France, dedicated in 1886.",
		"radius": 5.4,
		"region": "americas",
	},
	{
		"builder": "_landmark_plaza_mayor",
		"name": "Plaza Mayor",
		"fact": "The arcaded central square of Madrid, Spain, completed in 1619 and ringed by 237 balconies.",
		"radius": 8.6,
		"region": "europe",
	},
	{
		"builder": "_landmark_eiffel",
		"name": "Eiffel Tower",
		"fact": "A 330 m iron tower in Paris, France, built for the 1889 World's Fair and meant to stand only 20 years.",
		"radius": 6.2,
		"region": "europe",
	},
	{
		"builder": "_landmark_taj",
		"name": "Taj Mahal",
		"fact": "A white marble mausoleum in Agra, India, built by Shah Jahan for his wife Mumtaz Mahal in 1653.",
		"radius": 8.6,
		"region": "asia",
	},
	# --- WAVE 2 (appended, never inserted — see the ORDER note above). Ten more
	# places chosen for one property only: whether a person names them from the
	# SILHOUETTE alone. A ring of arches, a clock tower, a stack that leans, a lion
	# with a human head, a figure with its arms out, a two-beam gate, a wall with a
	# watchtower, a colonnade under a chariot, a castle of blue spires, twin
	# openwork spires. Three are German because the game's players are, and three
	# is the cap: the rest of that pool is a wave of its own.
	{
		"builder": "_landmark_colosseum",
		"name": "Colosseum",
		"fact": "A Roman amphitheatre completed in AD 80 that seated over 50,000 spectators in the heart of Rome, Italy.",
		"radius": 8.6,
		"region": "europe",
	},
	{
		"builder": "_landmark_big_ben",
		"name": "Big Ben",
		"fact": "The 96 m clock tower of the Palace of Westminster in London, England — Big Ben is properly the bell inside it.",
		"radius": 4.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_pisa",
		"name": "Leaning Tower of Pisa",
		"fact": "A 12th-century bell tower in Pisa, Italy that began tilting during construction because of the soft ground beneath it.",
		"radius": 4.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_sphinx",
		"name": "Great Sphinx of Giza",
		"fact": "A 73 m limestone lion with a human head, carved from the bedrock at Giza, Egypt around 2500 BC.",
		"radius": 7.6,
		"region": "africa",
	},
	{
		"builder": "_landmark_redeemer",
		"name": "Christ the Redeemer",
		"fact": "A 30 m soapstone statue that has stood on Corcovado mountain above Rio de Janeiro, Brazil since 1931.",
		"radius": 4.8,
		"region": "americas",
	},
	{
		"builder": "_landmark_torii",
		"name": "Itsukushima Torii",
		"fact": "The vermilion gate of Itsukushima Shrine in Japan, which stands in the sea and appears to float at high tide.",
		"radius": 5.6,
		"region": "asia",
	},
	{
		"builder": "_landmark_great_wall",
		"name": "Great Wall of China",
		"fact": "A chain of walls and watchtowers across northern China, over 20,000 km long and built over some 2,000 years.",
		"radius": 9.4,
		"region": "asia",
	},
	{
		"builder": "_landmark_brandenburg",
		"name": "Brandenburg Gate",
		"fact": "A sandstone gate in Berlin, Germany, finished in 1791 and crowned by the Quadriga — a chariot drawn by four horses.",
		"radius": 8.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_neuschwanstein",
		"name": "Neuschwanstein Castle",
		"fact": "A hillside castle in Bavaria, Germany, begun in 1869 for King Ludwig II and never finished in his lifetime.",
		"radius": 8.0,
		"region": "europe",
	},
	{
		"builder": "_landmark_cologne",
		"name": "Cologne Cathedral",
		"fact": "A Gothic cathedral in Cologne, Germany — begun in 1248, halted for 300 years and completed only in 1880.",
		"radius": 8.6,
		"region": "europe",
	},
	# --- WAVE 3 (appended, never inserted — see the ORDER note above). Ten more,
	# picked on the same single property: whether a person names the place from the
	# SILHOUETTE alone. A crown of onion domes, a row of white sails, a stepped
	# pyramid with one grand stair, a facade cut into a cliff, four heads in a rock
	# face, five lotus towers in a quincunx, terraces under a sharp peak, three
	# tiers of arches, a row of windmills, a three-stage tower with a fire on top.
	#
	# NO GERMAN ENTRIES ON PURPOSE — the German pack is its own wave, and spending
	# the pool here would leave it the leftovers (the same reasoning that capped
	# wave 2 at three). The ten are ten different countries instead, none of which
	# the registry already had except Egypt and France, and in both of those cases
	# the new shape shares nothing with the old one (a tapering lighthouse against
	# pyramids and a lion; an arcade of arches against a lattice tower).
	#
	# ZERO NEW PALETTE ENTRIES, which is a decision and not luck. Wave 2 added two
	# for ten places and said why: a landmark is recognised by its silhouette, and
	# every colour added is one more thing for a MultiMesh of grey boxes to fail to
	# be distinct from. St Basil's is the only place here that is ABOUT its colours,
	# and the four it needs are already in the table — LM_VERMILION brick, LM_COPPER
	# oxidised green, LM_MARBLE white and LM_SANDSTONE standing in for gold leaf,
	# which at the 30 m these are judged from is exactly what a warm tan reads as.
	{
		"builder": "_landmark_st_basil",
		"name": "St Basil's Cathedral",
		"fact": "A cathedral of nine coloured onion domes on Red Square in Moscow, Russia, completed in 1561 for Ivan the Terrible.",
		"radius": 6.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_sydney_opera",
		"name": "Sydney Opera House",
		"fact": "A performing-arts centre on Sydney Harbour, Australia, opened in 1973 and roofed with over a million tiles.",
		"radius": 8.2,
		"region": "oceania",
	},
	{
		"builder": "_landmark_chichen_itza",
		"name": "Chichén Itzá",
		"fact": "El Castillo, a Maya step pyramid in Chichén Itzá, Mexico, whose four stairways total 365 steps — one for every day.",
		"radius": 8.4,
		"region": "americas",
	},
	{
		"builder": "_landmark_petra",
		"name": "Petra",
		"fact": "Al-Khazneh, a temple facade carved into a rose-red sandstone cliff at Petra, Jordan, around the 1st century AD.",
		"radius": 8.0,
		"region": "asia",
	},
	{
		"builder": "_landmark_rushmore",
		"name": "Mount Rushmore",
		"fact": "Four 18 m presidential heads carved into a granite cliff in South Dakota, USA, between 1927 and 1941.",
		"radius": 8.6,
		"region": "americas",
	},
	{
		"builder": "_landmark_angkor_wat",
		"name": "Angkor Wat",
		"fact": "The largest religious monument on Earth, raised in Cambodia around 1150 and still flown on the national flag.",
		"radius": 9.0,
		"region": "asia",
	},
	{
		"builder": "_landmark_machu_picchu",
		"name": "Machu Picchu",
		"fact": "An Inca city on a 2,430 m ridge in Peru, built around 1450 and unknown to the outside world until 1911.",
		"radius": 9.0,
		"region": "americas",
	},
	{
		"builder": "_landmark_pont_du_gard",
		"name": "Pont du Gard",
		"fact": "A three-tier Roman aqueduct bridge over the Gardon in France, built around AD 50 to carry water 50 km to Nîmes.",
		"radius": 8.8,
		"region": "europe",
	},
	{
		"builder": "_landmark_kinderdijk",
		"name": "Kinderdijk Windmills",
		"fact": "Nineteen windmills built around 1740 to drain the polders of Kinderdijk, the Netherlands — a UNESCO World Heritage site.",
		"radius": 8.2,
		"region": "europe",
	},
	{
		"builder": "_landmark_pharos",
		"name": "Lighthouse of Alexandria",
		"fact": "A 100 m lighthouse on the island of Pharos at Alexandria, Egypt — a Wonder of the Ancient World, toppled by earthquakes.",
		"radius": 6.6,
		"region": "africa",
	},
	# --- WAVE 4, THE GERMAN PACK (appended, never inserted — see the ORDER note
	# above). Ten places from one country, which no earlier wave did and which is
	# the whole point: the game's players are German-speaking, waves 2 and 3
	# deliberately rationed and then withheld this pool so it would not be spent on
	# leftovers, and this is the wave it was being saved for. With the three wave-2
	# entries (Brandenburger Tor, Neuschwanstein, Kölner Dom) that takes German
	# coverage to 13 of 38.
	#
	# THE SELECTION RULE IS THE SAME ONE, unchanged: does a person name the place
	# from the SILHOUETTE alone. A domed parliament, a sphere on a needle, a black
	# Roman gate, two fat brick towers, a stone bell, a glass wave on a warehouse,
	# a cross on a summit, a keep over a timbered hall, ONE colossal steeple, and
	# four animals standing on each other. Ten shapes, and no two of them are the
	# same shape — which matters more here than in any earlier wave, because ten
	# entries from one country is also ten chances to build the same church twice.
	#
	# The two that come closest to an existing entry are called out in their own
	# docstrings rather than hidden: Ulm is deliberately the ONE-spire answer to
	# Cologne's two (which is the real recognition cue between them, and Cologne's
	# docstring already said so), and the Wartburg is deliberately stone-and-timber
	# ochre against Neuschwanstein's white-and-blue-cones, because "a castle" is a
	# silhouette two entries could share and a colour scheme is not.
	#
	# ZERO NEW PALETTE ENTRIES, for the third wave running and for wave 2's stated
	# reason. Northern brick Gothic and Hamburg's harbour warehouse both want a
	# brick red, which is LM_VERMILION darkened — the torii's lacquer is bright and
	# a wall of it is not, and their silhouettes could not be confused at any
	# distance. Glass is LM_SLATE_BLUE lightened, patinated bronze is LM_COPPER
	# darkened, and the Porta Nigra's soot-blackened sandstone is LM_STONE_GREY
	# darkened rather than the Moai's LM_BASALT — a third near-black entry in the
	# registry would have been one too many.
	{
		"builder": "_landmark_reichstag",
		"name": "Reichstag Building",
		"fact": "The seat of the German parliament in Berlin, opened in 1894 and crowned in 1999 with a glass dome the public may climb.",
		"radius": 8.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_fernsehturm",
		"name": "Berlin TV Tower",
		"fact": "At 368 m the tallest structure in Germany, raised in East Berlin in 1969 — sunlight on its sphere draws a cross the state could never remove.",
		"radius": 6.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_porta_nigra",
		"name": "Porta Nigra",
		"fact": "A Roman city gate in Trier from around AD 170, built of sandstone blocks set without mortar — the largest still standing north of the Alps.",
		"radius": 8.2,
		"region": "europe",
	},
	{
		"builder": "_landmark_holstentor",
		"name": "Holsten Gate",
		"fact": "The western gate of Lübeck, finished in 1478 in northern brick Gothic — its two round towers lean because the marshy ground gave way.",
		"radius": 7.8,
		"region": "europe",
	},
	{
		"builder": "_landmark_frauenkirche",
		"name": "Dresden Frauenkirche",
		"fact": "A Baroque church of 1743 whose great stone dome fell in the firestorm of 1945 — rebuilt from its own rubble and reconsecrated in 2005.",
		"radius": 7.2,
		"region": "europe",
	},
	{
		"builder": "_landmark_elbphilharmonie",
		"name": "Elbphilharmonie",
		"fact": "A concert hall opened in Hamburg in 2017 — a wave of glass set on top of a brick harbour warehouse from 1963.",
		"radius": 7.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_zugspitze",
		"name": "Zugspitze Summit Cross",
		"fact": "A gilded cross on Germany's highest peak, 2,962 m up in the Alps — first raised in 1851 after being carried up in pieces.",
		"radius": 6.0,
		"region": "europe",
	},
	{
		"builder": "_landmark_wartburg",
		"name": "Wartburg Castle",
		"fact": "A castle above Eisenach founded in 1067, where Martin Luther hid as 'Junker Jörg' and translated the New Testament in eleven weeks.",
		"radius": 7.2,
		"region": "europe",
	},
	{
		"builder": "_landmark_ulm_minster",
		"name": "Ulm Minster",
		"fact": "The tallest church steeple in the world at 161.5 m, begun in Ulm in 1377 and finished only in 1890 — 768 steps to the viewing gallery.",
		"radius": 8.0,
		"region": "europe",
	},
	{
		"builder": "_landmark_bremen_musicians",
		"name": "Bremen Town Musicians",
		"fact": "A donkey, dog, cat and rooster from the Grimm tale of 1819, cast in bronze at Bremen in 1953 — grasp the donkey's forelegs for luck.",
		"radius": 4.2,
		"region": "europe",
	},
	# --- WAVE 5 (appended, never inserted — see the ORDER note above). This is bead
	# asd.4, the wave the epic's ~48 target was counted for; the code's wave numbers
	# ran one ahead of the bead numbers from the German pack on, and renaming a
	# shipped comment block would only move the confusion rather than remove it.
	#
	# THE SELECTION RULE IS THE SAME ONE, for the fifth time: does a person name the
	# place from the SILHOUETTE alone. A rectangle of columns under a low gable, a
	# thicket of unequal spires, a bridge with two Gothic towers, ONE huge arch,
	# nine spheres on struts, nine letters on a hillside, a saucer on a tripod, five
	# upswept roofs on a battered stone base, black timber roofs stacked under
	# dragon heads, and a palace facade standing in its own pool.
	#
	# WHAT WAS LEFT ON THE BENCH AND WHY. The pool still held the CN Tower and a
	# Burj-style spire, and both were dropped for one reason: the registry already
	# answers "a tall thing with something near the top" three times (Eiffel, the
	# Fernsehturm, Pharos), the Space Needle makes four, and a fifth and sixth would
	# be the first time this epic shipped two entries a player cannot tell apart. A
	# plain obelisk went the same way at the small end. Trevi took the last slot
	# instead because nothing else in the registry is about WATER, and its pool is
	# the only silhouette in the whole table that lies flat.
	#
	# ZERO NEW PALETTE ENTRIES, for the fourth wave running and for wave 2's stated
	# reason. Pentelic marble, Paris limestone and Osaka's plaster are all LM_MARBLE;
	# Gaudí's sandstone and the Space Needle's Galaxy Gold are LM_SANDSTONE; the
	# Atomium's polished steel is LM_GRANITE lightened; Osaka's tiles and Trevi's
	# water are both LM_COPPER (green-grey darkened and blue-green lightened — the
	# one entry in the table that already reads as both); Borgund's tarred pine is
	# LM_BASALT.
	{
		"builder": "_landmark_parthenon",
		"name": "Parthenon",
		"fact": "A marble temple to Athena on the Acropolis of Athens, Greece, finished in 438 BC — its columns swell slightly so that they look straight.",
		"radius": 8.8,
		"region": "europe",
	},
	{
		"builder": "_landmark_sagrada",
		"name": "Sagrada Família",
		"fact": "A basilica in Barcelona, Spain, begun by Antoni Gaudí in 1882 and still unfinished — its eighteen planned towers rise only as fast as the donations come in.",
		"radius": 7.6,
		"region": "europe",
	},
	{
		"builder": "_landmark_tower_bridge",
		"name": "Tower Bridge",
		"fact": "A bascule bridge over the Thames in London, England, opened in 1894 — its two road halves still lift about 800 times a year.",
		"radius": 8.8,
		"region": "europe",
	},
	{
		"builder": "_landmark_arc_de_triomphe",
		"name": "Arc de Triomphe",
		"fact": "A 50 m triumphal arch in Paris, France, ordered by Napoleon in 1806 — twelve avenues radiate from the circle around it.",
		"radius": 7.2,
		"region": "europe",
	},
	{
		"builder": "_landmark_atomium",
		"name": "Atomium",
		"fact": "Nine steel spheres in Brussels, Belgium — one cell of an iron crystal magnified 165 billion times, built for the 1958 World's Fair.",
		"radius": 6.6,
		"region": "europe",
	},
	{
		"builder": "_landmark_hollywood",
		"name": "Hollywood Sign",
		"fact": "Nine 14 m letters above Los Angeles, USA, put up in 1923 to advertise a housing estate — they read HOLLYWOODLAND until 1949.",
		"radius": 8.8,
		"region": "americas",
	},
	{
		"builder": "_landmark_space_needle",
		"name": "Space Needle",
		"fact": "A 184 m observation tower raised for the 1962 World's Fair in Seattle, USA — its saucer was first sketched on a coffee-house napkin.",
		"radius": 6.2,
		"region": "americas",
	},
	{
		"builder": "_landmark_osaka_castle",
		"name": "Osaka Castle",
		"fact": "A Japanese castle first raised in 1583 on a base of a hundred thousand stone blocks — the golden fish on its roofs are there to ward off fire.",
		"radius": 8.8,
		"region": "asia",
	},
	{
		"builder": "_landmark_stave_church",
		"name": "Borgund Stave Church",
		"fact": "A church of tarred pine raised in Norway around 1180 — the dragon heads on its gables guard a Christian roof in Viking style.",
		"radius": 6.4,
		"region": "europe",
	},
	{
		"builder": "_landmark_trevi",
		"name": "Trevi Fountain",
		"fact": "A Baroque fountain finished in Rome, Italy in 1762 and fed by an aqueduct of 19 BC — some 3,000 euros in coins are thrown into it every day.",
		"radius": 8.6,
		"region": "europe",
	},
]

## THE CITY REGISTRY IS `scripts/city_builders.gd`'S SINCE bd `godot-test1-ftn.17`
## — Budapest's 22 authored slots, its two palette entries and its 26 builders
## went with it, and the reasoning for why it is a SECOND TABLE at all went with
## the table. It is aliased back HERE because `landmark_toast.gd`,
## `landmark_progress_selfcheck`, `budapest_selfcheck` and both registry
## assertions in `landmark_selfcheck` / `landmark_sites_selfcheck` spell it
## `LandmarkBuilders.CITY_LANDMARKS`, and a rename is not what that bead was.
##
## **THIS IS THE ONE PARSE-TIME EDGE BETWEEN THE TWO FILES, AND IT MUST STAY THE
## ONLY ONE.** `city_builders.gd` reaches back for the shared `LM_*` palette and
## `_lm_shade` / `_lm_onion` **inside function bodies**, which is a runtime
## lookup; a `const` or a `preload` back there would close the loop into a
## parse-time cycle. Same rule, same reason as `TowerInterior` / `TowerPlanBoxes`.
const CITY_LANDMARKS: Array = CityBuilders.CITY_LANDMARKS

# ----------------------------------------------------------------------------
# THE QUIZ PICKER — "which landmark is this?", decided without asking anyone
# ----------------------------------------------------------------------------

## Fixed salt for the quiz's hash stream, in the TREASURE_SALT / ARTIFACT_SALT /
## CAMP_SALT family: an arbitrary fixed constant that gives the option roll ITS
## OWN hash stream so it can never correlate with or perturb another site. In
## particular it draws NOTHING from the chunk RNG that placed the landmark — one
## extra draw there slides every landmark in the world (CLAUDE.md, determinism).
const QUIZ_SALT: int = 0x9012


static func quiz_options(kind: int, landmark_id: int, run_seed: int) -> Array[int]:
	"""
	The three registry indices a "which landmark is this?" card offers, with
	`kind` (the right answer) among them, in the order they are shown.

	PURE, so every peer in a room sees the same three options for the same
	landmark with no packet: run_seed is already shared, landmark_id is already a
	pure function of where the marker stands (coin.gd's id_at), and the whole roll
	is one private RandomNumberGenerator seeded from the two. That is a free
	multiplayer feature and the reason this is a static function and not toast
	state — it lives here because this is where the registry lives, the same way
	the toast preloads coin.gd purely for its static id_at.

	DISTRACTORS PREFER THE SAME REGION. "Brandenburg Gate / Plaza Mayor /
	Colosseum" is a quiz; "Brandenburg Gate / Moai / Sydney Opera House" is a
	giveaway — a player who cannot name the gate can still name the only European
	thing in the list. A region with fewer than two other rows (oceania, today)
	falls back to the whole table, because three DISTINCT options matter more than
	the flavour of the two wrong ones.
	"""
	var options: Array[int] = []
	if LANDMARKS.size() < 3:
		return options
	# The kind arrives from a marker meta, i.e. from outside this file; a garbage
	# index would otherwise index the registry out of bounds below.
	kind = clampi(kind, 0, LANDMARKS.size() - 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(landmark_id, QUIZ_SALT, run_seed))

	var answer: Dictionary = LANDMARKS[kind]
	var region: String = String(answer.get("region", ""))
	var pool: Array[int] = []
	for i: int in LANDMARKS.size():
		var row: Dictionary = LANDMARKS[i]
		if i != kind and String(row.get("region", "")) == region:
			pool.append(i)
	if pool.size() < 2:
		pool.clear()
		for i: int in LANDMARKS.size():
			if i != kind:
				pool.append(i)

	# Drawn WITHOUT replacement (pop_at, not a re-roll loop) so two distractors can
	# never collide and the number of draws is fixed — a reject-and-retry loop
	# would consume a seed-dependent number of draws, which is the kind of thing
	# that makes a "deterministic" stream stop being reproducible after a retune.
	for _n: int in 2:
		options.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	# The correct answer's SLOT, from the same stream AFTER the distractors, so
	# adding a region row cannot change where the answer sits for an unrelated
	# place. Without this the answer would always be shown third.
	options.insert(rng.randi_range(0, 2), kind)
	return options


# ----------------------------------------------------------------------------
# THE BUILDERS (one per registry entry, in registry order)
# ----------------------------------------------------------------------------
##
## Every builder has the identical signature
##   _landmark_x(center, rng, parent_chunk, block_batch, block_body) -> Dictionary
## and returns { "radius": float, "top": float } — no `gem_offset`, because a
## landmark deliberately pays NO GEM (see the REWARD DECISION in the constant
## banner). `center` is CHUNK-LOCAL, exactly as the artifact builders take it.
##
## Shared rules, all four of them load-bearing:
##  1. EVERY solid box goes through create_box with a color_override, so it lands
##     in the chunk's ONE MultiMesh and ONE BlockCollision body. A landmark is
##     therefore free at the draw-call level however many boxes it is made of.
##  2. `collide = false` for pure trim that sits INSIDE another box's collision
##     volume (dark recesses, thin cornices, brows, cable strands overhead). The
##     chest's brass band and the camp's fire stones are the precedent.
##  3. The returned `radius` must BOUND every box actually emitted, measured as
##     horizontal centre offset + the rotated box's horizontal half-diagonal —
##     which is exactly what landmark_selfcheck.gd measures over 25 seeds per
##     builder. Each builder's comment carries its own worst-case arithmetic, so
##     a retune can be checked by reading rather than by running.
##  4. AT MOST ONE emissive accent, and only where a real light belongs (a
##     capstone, a torch, a beacon). An accent is a genuine extra draw call, and
##     it reuses terrain._get_camp_ember_material() — the warm one. DO NOT add a third
##     glow material; two temperatures is the whole vocabulary.
##
## The RNG is the landmark's PRIVATE stream (seeded from _landmark_at's `seed`),
## so a builder may draw as freely as its shape needs — nothing else reads it.
##
## ---------------------------------------------------------------------------
## THE KIND SLOT — a FIELD builder's fifth rule (bead godot-test1-y1o.6)
## ---------------------------------------------------------------------------
## Every box here used to be a cube, so a dome, a column, an onion and a boulder
## were the same silhouette in different proportions. create_box's last argument
## picks a shared unit MESH instead (ChunkBatch.BoxKind), and choosing one is
## free: it costs no RNG draw, no collision shape and no draw call beyond the one
## MultiMeshInstance3D per kind PRESENT in a chunk. Four rules, and every one of
## them is what makes this a colour-only-stream edit rather than a rebuild:
##
##  5a. NOTHING BUT THE KIND MOVED. No box was added, removed, resized, recoloured
##      or reordered by this pass, because a builder's RNG stream is shared with
##      nothing and its DRAW ORDER is the world's determinism: an extra
##      _lm_shade would slide every later box in that landmark. If a shape wants
##      one more piece, that is a separate bead with its own A/B.
##  5b. THE UNIT MESH FITS THE UNIT CUBE, so `dimensions` still means the
##      bounding box, the declared radius still bounds the stone, and each
##      builder's own radius arithmetic is untouched. It also REACHES the cube's
##      top face at its axis, which is what keeps a returned `top` (and
##      rotated_box_top) the DRAWN apex rather than merely an upper bound —
##      landmark_selfcheck's check 9 asserts exactly that, per kind.
##  5c. THE TAPER RULE. A spire in this file is a stack of shrinking boxes, and
##      a stack of CONES is a stack of POINTS with an overhanging disc above each
##      one. So a taper is CYLINDER all the way up and CONE only on the piece
##      that ends it. The same reasoning is why a shrinking stack that carries
##      something above it (a finial, a lantern) keeps CYLINDER to the top.
##  5d. COLLISION FOLLOWS THE KIND, AND THE CONE IS THE ONE THAT STILL DOES NOT.
##      Bead godot-test1-y1o.10 closed the mismatch this rule used to record: a
##      near-round colliding SPHERE now hangs a `SphereShape3D` and a near-round
##      colliding CYLINDER a `CylinderShape3D`, both inscribed in the box, so the
##      Zugspitze's scree, the Trevi's reef, the Space Needle's foot pads, the
##      Colosseum's piers, the Kinderdijk drums and the Atomium's base are the
##      shape you see — you stop at the ball, and you stand on the drum's real
##      round top. `ChunkBatch.collision_shape_for` is the whole mapping and the
##      whole argument; nothing about it is this file's to restate.
##      TWO THINGS ARE STILL ON THIS FILE:
##        * A CONE COLLIDES AS A BOX — Godot has no cone primitive — so its stone
##          is a POINT at the top of a box-shaped ledge, a floor made of nothing.
##          Nothing a player can reach may be a colliding cone; check 9c asserts
##          it, and rule 5c's "CONE only on the piece that ends a taper" is what
##          keeps them out of reach in the first place.
##        * A ROUND BOX SQUASHED PAST `ChunkBatch.ROUND_COLLIDER_MAX_ASPECT` (1.6)
##          FALLS BACK TO ITS BOX, because no SphereShape3D is an ellipsoid. The
##          worst colliding SPHERE is still the Taj's chattri dome at **1.57**
##          (1.1 x 0.7 x 1.1), 0.03 off the gate: **squash a dome any further and
##          it silently goes back to being a box.** If you want a flattened dome a
##          player stands on, draw it as a CYLINDER — a cylinder's aspect is
##          measured in PLAN only, so a pancake drum is still round however thin
##          it is.
##          BEAD y1o.17 GAVE THE FALLBACK ITS FIRST TWO CONSUMERS, and both are
##          deliberate: the Sydney Opera House's shell slabs (4.0 in plan) and the
##          Pont du Gard's tier-2 piers (1.83). Both keep exactly the BoxShape3D
##          they had as cubes, so nothing about walking into either changed, and a
##          CYLINDER fills its box floor to ceiling — the mismatch is four plan
##          corners per slab and never a foot-height hole. Every other round
##          colliding box in the field is still round in collision. (`chunk_batch.
##          gd`'s `collision_shape_for` banner records the pre-y1o.17 census and
##          its "the fallback has no consumer today" line is that measurement's,
##          not a rule.) A NEW past-the-gate colliding round box needs the same
##          two sentences at ITS line: why the shape wants it, and why the box it
##          keeps is harmless where a player can reach.
##
## The 22 Budapest builders below take NO kind at all and must not: a city box is
## sliced on the chunk grid, and a rotated or non-cube one keeps the centre rule
## (see _spawn_city_landmarks_in_chunk). budapest_selfcheck fails one that does.

static func _lm_shade(base: Color, rng: RandomNumberGenerator, amount: float = 0.06) -> Color:
	"""
	One stone's colour: the landmark's base palette entry nudged by up to `amount`
	in each channel. Mortared ruins and quarried blocks are never one flat colour,
	and a per-box jitter is what stops a MultiMesh of identical greys reading as a
	single extruded blob. Deliberately SMALL — a landmark has to stay recognizable,
	which means its silhouette does the work and the colour stays quiet.
	"""
	var d := rng.randf_range(-amount, amount)
	return Color(clampf(base.r + d, 0.0, 1.0), clampf(base.g + d, 0.0, 1.0), clampf(base.b + d, 0.0, 1.0))


static func rotated_box_top(center_y: float, size: Vector3, tilt: float) -> float:
	"""
	The highest vertex of a box of dimensions `size` centered vertically at
	`center_y` and tilted by `tilt` radians about a horizontal axis
	(Basis(RIGHT, tilt)): center_y + hy·|cos(tilt)| + hz·|sin(tilt)|.
	"""
	return center_y + (size.y * 0.5) * absf(cos(tilt)) + (size.z * 0.5) * absf(sin(tilt))

static func _landmark_stonehenge(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 0 — STONEHENGE: an outer ring of 5 trilithons (two uprights carrying a
	lintel laid across their tops) around an inner horseshoe of 4 shorter, drunkenly
	leaning standing stones. Salisbury Plain in cubes.

	RADIUS ARITHMETIC (declared 7.6). The widest thing is a lintel: its centre sits
	on the RING_R (5.6) ring and its horizontal half-diagonal is
	0.5*sqrt(3.4^2 + 1.0^2) = 1.77, so 5.6 + 1.77 = 7.37 <= 7.6. The uprights sit
	further out along the tangent (sqrt(5.6^2 + 1.2^2) = 5.73) but are much thinner
	(half-diagonal 0.71), so 6.44. RING_R is 5.6 rather than the 6.0 a real plan
	would suggest precisely because of that lintel term.
	NO ACCENT: Stonehenge is a sundial, not a lamp.

	THE STANDING STONES ARE CYLINDERS, THE LINTELS STAY CUBES (bead
	godot-test1-y1o.17). A menhir is a weathered pillar and a sarsen upright reads
	as one; a lintel is a DRESSED beam laid flat across two of them, and a round
	lintel is a log. Both collide as the CylinderShape3D they draw — which matters
	here more than anywhere else in the registry, because these are the one
	landmark whose stones you walk between at head height. The upright is 1.00 in
	plan; the BLUESTONE is 1.0 x 0.7, i.e. **1.43 against the 1.6 gate**, the
	second-tightest colliding round box in this file after the Taj's dome — thin
	it and it silently goes back to being a box, so widen the 0.7 rather than
	narrowing it if this stone is ever retuned.
	"""
	const RING_R := 5.6
	const TRILITHONS := 5
	const UPRIGHT := Vector3(1.0, 4.2, 1.0)
	const LINTEL := Vector3(3.4, 0.8, 1.0)
	# One shared orientation for the whole monument, so the ring reads as built
	# rather than scattered.
	var base_a := rng.randf_range(0.0, TAU)

	for i in TRILITHONS:
		var a := base_a + TAU * float(i) / float(TRILITHONS)
		# yaw = PI/2 - a points the stone's local Z (its thin depth axis) along the
		# radius, i.e. the trilithon FACES the centre and its long X axis runs along
		# the tangent — the same face-the-centre trick the artifact stone circle uses.
		var yaw := PI / 2.0 - a
		var radial := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var ring_pos := center + radial * RING_R
		# The two uprights, offset along the tangent so the lintel bridges them.
		for side in [-1.0, 1.0]:
			terrain.create_box(ring_pos + tangent * (side * 1.2) + Vector3(0.0, UPRIGHT.y / 2.0, 0.0),
					UPRIGHT, yaw + rng.randf_range(-0.05, 0.05), rng, block_batch, block_body,
					0.0, _lm_shade(LM_STONE_GREY, rng), true, ChunkBatch.BoxKind.CYLINDER)
		# The lintel laid flat across both tops — the detail that makes a trilithon
		# read as Stonehenge and not as a stone circle.
		terrain.create_box(ring_pos + Vector3(0.0, UPRIGHT.y + LINTEL.y / 2.0, 0.0),
				LINTEL, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_STONE_GREY, rng))

	# Inner horseshoe: 4 shorter bluestones over a 3/4 arc (a horseshoe, not a
	# second ring), each leaning a little — a thousand years of frost heave.
	const INNER_R := 2.8
	for i in 4:
		var a := base_a + 0.35 + (TAU * 0.75) * float(i) / 3.0
		var dims := Vector3(1.0, rng.randf_range(2.2, 2.9), 0.7)
		var lean := rng.randf_range(-0.15, 0.15)
		terrain.create_box(center + Vector3(cos(a) * INNER_R, dims.y / 2.0 - 0.15, sin(a) * INNER_R),
				dims, PI / 2.0 - a, rng, block_batch, block_body, lean, _lm_shade(LM_STONE_GREY, rng),
				true, ChunkBatch.BoxKind.CYLINDER)

	return { "radius": 7.6, "top": UPRIGHT.y + LINTEL.y }

static func _landmark_moai(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 1 — MOAI OF EASTER ISLAND: five heavy figures standing shoulder to
	shoulder on a low ahu platform, ALL FACING THE SAME WAY (inland, as the real
	ones do). The row plus the shared gaze is the whole recognition cue.

	RADIUS ARITHMETIC (declared 6.6). The ahu slab is the widest box:
	0.5*sqrt(11.0^2 + 3.0^2) = 5.70. The outermost statue body sits at x = 4.4 with
	half-diagonal 0.79 => 5.19. So 5.70 <= 6.6.
	NO ACCENT.
	"""
	const AHU := Vector3(11.0, 0.7, 3.0)
	const STATUES := 5
	const SPACING := 2.2
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_BASALT, rng, 0.03)  # one quarry, one colour family
	terrain.create_box(center + Vector3(0.0, AHU.y / 2.0, 0.0), AHU, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))

	var tallest := AHU.y
	for i in STATUES:
		var offset := (float(i) - float(STATUES - 1) / 2.0) * SPACING
		var base := center + rot * Vector3(offset, 0.0, 0.0)
		# Each figure is carved separately, so each leans a hair differently — but
		# the wobble stays tiny, because "all facing one way" is the recognition cue.
		var wobble := rng.randf_range(-0.09, 0.09)
		var body := Vector3(1.3, rng.randf_range(2.7, 3.2), 0.9)
		terrain.create_box(base + Vector3(0.0, AHU.y + body.y / 2.0, 0.0), body, yaw + wobble, rng, block_batch, block_body, 0.0, stone)
		var head := Vector3(1.15, 1.5, 1.0)
		var head_y := AHU.y + body.y + head.y / 2.0
		terrain.create_box(base + Vector3(0.0, head_y, 0.0), head, yaw + wobble, rng, block_batch, block_body, 0.0, stone,
				true, ChunkBatch.BoxKind.SPHERE)
		# The heavy brow ridge, proud of the face — visual trim only (it sits on the
		# head's own collision volume), so collide = false.
		terrain.create_box(base + Vector3(0.0, head_y + 0.25, 0.0) + Basis(Vector3.UP, yaw + wobble) * Vector3(0.0, 0.0, head.z / 2.0 + 0.06),
				Vector3(1.2, 0.35, 0.18), yaw + wobble, rng, block_batch, block_body, 0.0,
				_lm_shade(LM_BASALT, rng, 0.02).darkened(0.25), false)
		tallest = maxf(tallest, AHU.y + body.y + head.y)

	return { "radius": 6.6, "top": tallest }

static func _landmark_giza(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 2 — PYRAMIDS OF GIZA: three stepped pyramids of descending size on the
	shallow diagonal the real ones stand on, plus ONE emissive capstone on the
	Great Pyramid (the pyramidion that is missing in Cairo and present here).

	RADIUS ARITHMETIC (declared 9.4). Worst case is the SMALLEST pyramid, because
	it is the one pushed furthest out: centre offset sqrt(5.0^2 + 3.0^2) = 5.83 plus
	its base half-diagonal 0.5*sqrt(2*4.0^2) = 2.83 => 8.66. The Great Pyramid is
	2.5 out with a 4.95 half-diagonal => 7.45. So 8.66 <= 9.4.
	Sizes and offsets are FIXED rather than rolled: three pyramids in descending
	size on a diagonal IS the recognition cue, and a roll that shuffled them would
	sometimes produce three equal lumps.
	"""
	# base width, layer count, offset from the group centre — largest first.
	var plan := [
		{ "base": 7.0, "layers": 9, "off": Vector2(-2.0, -1.5) },
		{ "base": 5.5, "layers": 7, "off": Vector2(2.2, 1.0) },
		{ "base": 4.0, "layers": 5, "off": Vector2(5.0, 3.0) },
	]
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var great_top := 0.0
	for p in plan:
		var base_w: float = p.base
		var layers: int = p.layers
		var spot: Vector3 = center + rot * Vector3(p.off.x, 0.0, p.off.y)
		# Same tapering-stack recipe as spawn_pyramid, so a stepped pyramid is
		# climbable the same way theirs is.
		var layer_h: float = base_w / float(layers) * 0.62
		var shrink: float = base_w / float(layers + 1)
		var y := 0.0
		for i in layers:
			var w: float = base_w - float(i) * shrink
			terrain.create_box(spot + Vector3(0.0, y + layer_h / 2.0, 0.0), Vector3(w, layer_h, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng))
			y += layer_h
		if great_top == 0.0:
			great_top = y
			# THE one accent: a gilded capstone on the Great Pyramid.
			terrain._spawn_artifact_accent(parent_chunk, spot + Vector3(0.0, y + 0.35, 0.0),
					Vector3(0.9, 0.7, 0.9), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 9.4, "top": great_top + 0.7 }

static func _landmark_golden_gate(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 3 — GOLDEN GATE BRIDGE: two International Orange towers, a deck slab
	spanning and overhanging them, and the main cable as a chain of small boxes
	sagging from tower top to tower top in a shallow catenary.

	THE DECK IS SOLID ON PURPOSE. It goes through create_box like every other solid,
	so downstream it IS ordinary block stone: it has a real CollisionShape3D in the
	chunk's one BlockCollision body and the player stands on it rather than falling
	through, which is what stops the span reading as a painted backdrop.

	ponytail: it is solid but NOT REACHABLE from flat ground — the deck top sits at
	DECK_Y + DECK.y/2 = 5.3 m against the player's 3.6125 m jump apex, and the
	towers are smooth 11 m boxes with no ledge. So you walk under this bridge, not
	over it. Upgrade path if crossing it is ever wanted: drop DECK_Y to ~2.9 (top
	3.2), or add a step block at each abutment; both change the silhouette's
	proportions, which is why neither was done for a shape whose whole job is to be
	recognisable at 30 m. Note also that a road coin whose column crosses this
	landmark is SKIPPED, not perched — spawn_landmark_in_chunk appends the footprint
	`climbable: false` for every landmark (they are 5-18 m tall), so _settle_coin_y
	drops it rather than stranding it on the circle's top.

	RADIUS ARITHMETIC (declared 9.4). The deck is the widest box:
	0.5*sqrt(17.0^2 + 3.0^2) = 8.63. A tower leg sits at sqrt(5.5^2 + 1.2^2) = 5.63
	with half-diagonal 0.64 => 6.27. So 8.63 <= 9.4.
	NO ACCENT: the towers already carry the loudest colour in the whole palette.

	THE TOWER SHAFTS ARE CYLINDERS AND THE CABLE IS NOT (bead godot-test1-y1o.17).
	A leg is a 0.9 x 0.9 plan column, so it collides as the CylinderShape3D it
	draws and is a round steel shaft you walk under. THE CABLE STAYS CUBES, and
	the reason is the enum rather than the shape: `CylinderMesh`'s axis is the
	entry's local +Y (collision_shape_for's banner), and a cable segment is a
	1.25 m box lying on its side with 0.3 m of height — asking for a CYLINDER
	there draws a 1.25 m PANCAKE, not a strand. A horizontal tube in this file is
	`_lm_strut`, which would mean re-laying the catenary as struts: a box COUNT
	change, a different RNG draw count in this builder, and therefore its own
	bead. Same reason the two crossbeams stay boxes.
	"""
	const TOWER_X := 5.5          # half the tower spacing (towers 11 m apart)
	const LEG := Vector3(0.9, 11.0, 0.9)
	const LEG_Z := 1.2            # half the spacing between a tower's two legs
	const DECK := Vector3(17.0, 0.6, 3.0)
	const DECK_Y := 5.0
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var orange := _lm_shade(LM_ORANGE, rng, 0.04)

	for side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(side * TOWER_X, LEG.y / 2.0, z_side * LEG_Z),
					LEG, yaw, rng, block_batch, block_body, 0.0, orange, true, ChunkBatch.BoxKind.CYLINDER)
		# Two crossbeams tying each tower's legs together — the ladder look that
		# says "suspension tower" rather than "two posts".
		for beam_y in [DECK_Y + 1.4, LEG.y - 1.0]:
			terrain.create_box(center + rot * Vector3(side * TOWER_X, beam_y, 0.0),
					Vector3(0.7, 0.6, LEG_Z * 2.0 + LEG.z), yaw, rng, block_batch, block_body, 0.0, orange)

	# The deck, overhanging both towers so the span reads as part of a longer road.
	terrain.create_box(center + rot * Vector3(0.0, DECK_Y, 0.0), DECK, yaw, rng, block_batch, block_body, 0.0,
			_lm_shade(LM_ORANGE, rng, 0.04).darkened(0.2))

	# The main cable: a chain of short boxes on a parabola from tower top, dipping
	# to just above the deck at mid-span, back up to the other tower top. Two of
	# them, one per side, hung off the same LEG_Z the legs use.
	# collide = false — a 30 cm strand of cable overhead is decoration, and giving
	# it a collision shape would let the player stand on thin air at mid-span.
	const CABLE_SEGMENTS := 11
	var top_y := LEG.y
	var sag_y := DECK_Y + 0.9
	var cable_dims := Vector3(TOWER_X * 2.0 / float(CABLE_SEGMENTS - 1) + 0.15, 0.3, 0.3)
	for z_side in [-1.0, 1.0]:
		for i in CABLE_SEGMENTS:
			var t := float(i) / float(CABLE_SEGMENTS - 1)   # 0..1 across the span
			var u := t * 2.0 - 1.0                          # -1..1, 0 at mid-span
			var x := u * TOWER_X
			var y: float = sag_y + (top_y - sag_y) * u * u   # parabola == shallow catenary
			terrain.create_box(center + rot * Vector3(x, y, z_side * LEG_Z), cable_dims,
					yaw, rng, block_batch, block_body, 0.0, orange, false)

	return { "radius": 9.4, "top": rotated_box_top(LEG.y, cable_dims, 0.0) }

static func _landmark_liberty(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 4 — STATUE OF LIBERTY: a stepped pedestal, a robe tapering upward, a head
	wearing a seven-point crown, and a raised right arm carrying ONE emissive torch.
	The crown and the raised torch are the whole silhouette; everything else is
	scaffolding for them.

	RADIUS ARITHMETIC (declared 5.4). The widest box is the bottom pedestal slab,
	0.5*sqrt(2*4.6^2) = 3.25, at the centre. The arm reaches out ~1.9 with a small
	half-diagonal => under 3.0. So 3.25 <= 5.4, with room to spare for the crown
	spikes' tilt.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var granite := _lm_shade(LM_GRANITE, rng)
	var copper := _lm_shade(LM_COPPER, rng, 0.03)

	# Pedestal: three shrinking slabs (Fort Wood's star fort, flattened to steps).
	var y := 0.0
	for i in 3:
		var w := 4.6 - float(i) * 0.7
		var h := 1.2
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, granite)
		y += h

	# Robe: four boxes narrowing as they rise — a cone, in the house's box vocabulary.
	for i in 4:
		var w: float = 2.6 - float(i) * 0.33
		var h := 1.6
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w * 0.85), yaw, rng, block_batch, block_body, 0.0, copper,
				true, ChunkBatch.BoxKind.CYLINDER)
		y += h

	# Head.
	var head_h := 1.1
	terrain.create_box(center + Vector3(0.0, y + head_h / 2.0, 0.0), Vector3(1.0, head_h, 1.0), yaw, rng, block_batch, block_body, 0.0, copper,
			true, ChunkBatch.BoxKind.SPHERE)
	var crown_y := y + head_h

	# The seven-point crown: spikes radiating outward and up. Trim only (they hang
	# off the head's own volume), so collide = false.
	#
	# SIGN GOTCHA, the same one the Eiffel legs record and the treasure chest's lid
	# records before that: create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt),
	# Basis(RIGHT, t) tips local +Y toward local +Z, and the yaw PI/2 - a maps local
	# +Z onto (cos a, sin a) — radially OUTWARD. So "radiating outward" is a POSITIVE
	# tilt. Measured with it negative, the spikes ran from r = 1.07 at their bases to
	# r = 0.63 at their tips: a cage closing over the head rather than a crown.
	for i in 7:
		var a := yaw + PI * (float(i) / 6.0 - 0.5)   # a half-circle fan, facing forward
		terrain.create_box(center + Vector3(cos(a) * 0.85, crown_y + 0.15, sin(a) * 0.85), Vector3(0.22, 1.0, 0.22),
				PI / 2.0 - a, rng, block_batch, block_body, 0.45, copper, false, ChunkBatch.BoxKind.CONE)

	# The raised arm: two vertical boxes stepping outward and up (upper arm, then
	# forearm), with the torch on top. Deliberately NOT tilted — a tilted arm box
	# would need its own sign reasoning for a limb that reads fine as a step at the
	# 30 m the silhouette is judged from.
	var shoulder := center + rot * Vector3(1.0, y - 0.6, 0.0)
	terrain.create_box(shoulder + rot * Vector3(0.35, 0.8, 0.0), Vector3(0.5, 2.0, 0.5), yaw, rng, block_batch, block_body, 0.0, copper,
			true, ChunkBatch.BoxKind.CYLINDER)
	var hand := shoulder + rot * Vector3(0.7, 2.6, 0.0)
	terrain.create_box(hand, Vector3(0.6, 1.6, 0.6), yaw, rng, block_batch, block_body, 0.0, copper, true, ChunkBatch.BoxKind.CYLINDER)
	# THE one accent: the torch flame, warm — the only thing on this statue that
	# should be visible from the coin road at night.
	terrain._spawn_artifact_accent(parent_chunk, hand + Vector3(0.0, 1.2, 0.0), Vector3(0.55, 0.8, 0.55), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 5.4, "top": maxf(crown_y + 0.9, hand.y + 1.6) }

static func _landmark_plaza_mayor(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 5 — PLAZA MAYOR: a square of three-storey ochre buildings enclosing an
	open courtyard, with an arcade of pillars along the inner faces, an arched
	entrance gap in one side, and a statue plinth in the middle. The one landmark
	you go INSIDE.

	WHY EACH SIDE IS THREE SEGMENTS AND NOT ONE LONG WALL. Purely the radius bound:
	a single 11.4 m wall has a horizontal half-diagonal of 5.79, which added to its
	4.7 offset is 10.5 — over the declared 8.6, even though its actual far corner is
	only at 8.4. The bound the self-check measures is offset + half-diagonal, so
	splitting each side into three bays (half-diagonal 2.14) brings the worst case
	to sqrt(3.75^2 + 4.7^2) + 2.14 = 6.01 + 2.14 = 8.15 <= 8.6. It also happens to
	read better: three bays per side is what an arcaded square looks like.
	NO ACCENT.
	"""
	const SIDE := 11.4        # outer side of the square
	const WALL_T := 2.0       # building depth
	const BAY := 3.8          # one segment's length
	const STOREY := 2.2
	const STOREYS := 3
	var yaw := rng.randf_range(0.0, TAU)
	var wall_line := SIDE / 2.0 - WALL_T / 2.0
	var ochre := _lm_shade(LM_OCHRE, rng, 0.05)

	# Four sides; side 0 is the entrance side and skips its middle bay.
	for side_i in 4:
		var side_yaw := yaw + PI / 2.0 * float(side_i)
		var side_rot := Basis(Vector3.UP, side_yaw)
		for bay in 3:
			if side_i == 0 and bay == 1:
				continue  # the archway: left open, spanned by a lintel below
			var along := (float(bay) - 1.0) * BAY
			var foot := center + side_rot * Vector3(along, 0.0, wall_line)
			for s in STOREYS:
				terrain.create_box(foot + Vector3(0.0, STOREY * float(s) + STOREY / 2.0, 0.0),
						Vector3(BAY, STOREY, WALL_T), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(ochre, rng, 0.03))
			# Slate cornice capping the bay — trim sitting on the wall's own volume.
			terrain.create_box(foot + Vector3(0.0, STOREY * float(STOREYS) + 0.18, 0.0),
					Vector3(BAY + 0.2, 0.36, WALL_T + 0.3), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)
		# The arcade: three squat pillars along this side's inner face, standing
		# proud of the wall — the colonnade you walk behind.
		for p in 3:
			var px := (float(p) - 1.0) * BAY
			terrain.create_box(center + side_rot * Vector3(px, STOREY / 2.0, wall_line - WALL_T / 2.0 - 0.35),
					Vector3(0.5, STOREY, 0.5), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.05),
					true, ChunkBatch.BoxKind.CYLINDER)

	# The entrance arch: two piers either side of the missing bay plus a lintel over
	# it, so the gap reads as a doorway rather than as a demolition.
	var arch_rot := Basis(Vector3.UP, yaw)
	for s in [-1.0, 1.0]:
		terrain.create_box(center + arch_rot * Vector3(s * (BAY / 2.0 - 0.35), STOREY, wall_line),
				Vector3(0.7, STOREY * 2.0, WALL_T), yaw, rng, block_batch, block_body, 0.0, ochre)
	terrain.create_box(center + arch_rot * Vector3(0.0, STOREY * 2.0 + STOREY / 2.0, wall_line),
			Vector3(BAY, STOREY, WALL_T), yaw, rng, block_batch, block_body, 0.0, ochre)

	# The courtyard's centrepiece: Felipe III on his plinth, abstracted to two boxes.
	terrain.create_box(center + Vector3(0.0, 0.4, 0.0), Vector3(1.4, 0.8, 1.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
	terrain.create_box(center + Vector3(0.0, 0.8 + 0.85, 0.0), Vector3(0.55, 1.7, 0.55), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.03),
			true, ChunkBatch.BoxKind.CYLINDER)

	# ponytail: the roof is a cornice band, not a pitched roof — a real one needs
	# tilted slabs whose collision would then be a ramp the player slides off. Add
	# tilted eaves if the square ever reads too flat from a distance.
	return { "radius": 8.6, "top": STOREY * float(STOREYS) + 0.36 }

static func _landmark_eiffel(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 6 — EIFFEL TOWER: four legs leaning inward in two segments each (the
	curve, in two straight pieces), a broad first platform, a smaller second one, a
	tapering shaft and an antenna, with ONE emissive beacon at the top.

	WHY THE LEGS ARE TWO SEGMENTS. Partly the curve — a single straight leg reads
	as a pylon — and partly the radius bound: a tilted box contributes
	sin(tilt) * height/2 of horizontal reach, so one 7 m leg tilted 0.3 rad reaches
	further than two 3.5 m ones that each restart closer to the axis.

	RADIUS ARITHMETIC (declared 6.2). Worst case is the FIRST PLATFORM,
	0.5*sqrt(2*6.0^2) = 4.24 at the centre. A lower leg segment sits at
	sqrt(2*2.2^2) = 3.11 with a tilted horizontal half-reach under 1.5 => 4.6.
	So 4.6 <= 6.2.

	THE IRONWORK IS CYLINDERS, THE PLATFORMS ARE NOT (bead godot-test1-y1o.17).
	Every leg segment, every shaft box and the antenna is square in plan and
	stands on its own local +Y, so each becomes the round member it always
	wanted to be and collides as the CylinderShape3D it draws (rule 5d) — the
	legs are the one part of this shape a player walks into. The two PLATFORMS
	stay CUBE because they really are square decks, and rule 5c keeps the taper
	CYLINDER to the top rather than ending it in a cone: the antenna collides,
	and a colliding cone is a point under a box-shaped ledge (check 9c).
	"""
	const LEG_TILT := 0.30
	const SEG := Vector3(0.85, 3.6, 0.85)
	var yaw := rng.randf_range(0.0, TAU)
	var iron := _lm_shade(LM_IRON, rng, 0.04)

	# Four legs at the corners of a square, each leaning toward the axis. The tilt
	# is applied about the leg's own local X after a yaw that points that X along
	# the tangent, so every leg leans INWARD rather than all four leaning north.
	#
	# THE TILT IS NEGATED, AND THAT SIGN IS THE WHOLE SHAPE. create_box composes
	# Basis(UP, yaw) * Basis(RIGHT, tilt), and Basis(RIGHT, t) tips the box's local
	# +Y toward its local +Z (the same gotcha the treasure chest's lid records, one
	# axis over). The yaw here is PI/2 - a, which maps local +Z onto (cos a, sin a)
	# — i.e. RADIALLY OUTWARD from the tower axis. So a POSITIVE tilt splays the
	# legs out. Measured with the sign wrong: the lower segment ran from r = 1.67 at
	# the ground to r = 2.73 at its top, the upper segment restarted at r = 0.90 and
	# rose to 1.50, so all four legs flared outward AND had a 1.83 m horizontal
	# discontinuity where the two segments are supposed to meet. Negated, the lower
	# runs 2.73 -> 1.67 and the upper 1.50 -> 0.90: converging, and the joint closes
	# to a 0.17 m step. The radius bound is unaffected either way (the magnitude of
	# the widest leg point is the same, it just moves from the top to the bottom).
	for corner in 4:
		var a := yaw + PI / 4.0 + PI / 2.0 * float(corner)
		var lower := center + Vector3(cos(a) * 2.2, SEG.y / 2.0, sin(a) * 2.2)
		terrain.create_box(lower, SEG, PI / 2.0 - a, rng, block_batch, block_body, -LEG_TILT, iron,
				true, ChunkBatch.BoxKind.CYLINDER)
		var upper := center + Vector3(cos(a) * 1.2, SEG.y * 1.5 - 0.1, sin(a) * 1.2)
		terrain.create_box(upper, Vector3(SEG.x * 0.85, SEG.y, SEG.z * 0.85), PI / 2.0 - a, rng, block_batch, block_body, -LEG_TILT * 0.55, iron,
				true, ChunkBatch.BoxKind.CYLINDER)

	# First platform — the wide one you can see people standing on from the Champ
	# de Mars, and here a genuinely reachable roof if you climb the legs.
	var p1_y := SEG.y * 2.0 - 0.2
	terrain.create_box(center + Vector3(0.0, p1_y + 0.25, 0.0), Vector3(6.0, 0.5, 6.0), yaw, rng, block_batch, block_body, 0.0, iron)
	# Second platform.
	var p2_y := p1_y + 4.0
	terrain.create_box(center + Vector3(0.0, p2_y + 0.2, 0.0), Vector3(3.6, 0.4, 3.6), yaw, rng, block_batch, block_body, 0.0, iron)

	# The shaft between and above the platforms: three boxes narrowing upward.
	var y := p1_y + 0.5
	for i in 3:
		var w: float = 2.4 - float(i) * 0.55
		var h := 3.5
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, iron,
				true, ChunkBatch.BoxKind.CYLINDER)
		y += h

	# Antenna, and THE one accent: the aircraft beacon at the very top.
	terrain.create_box(center + Vector3(0.0, y + 1.25, 0.0), Vector3(0.3, 2.5, 0.3), yaw, rng, block_batch, block_body, 0.0, iron,
			true, ChunkBatch.BoxKind.CYLINDER)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 2.7, 0.0), Vector3(0.4, 0.4, 0.4), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 6.2, "top": y + 2.5 }

static func _landmark_taj(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 7 — TAJ MAHAL: a white marble plinth carrying a cubic mausoleum under a
	stacked onion dome, four corner minarets, and a dark iwan arch recessed into
	the front face. Symmetry is the recognition cue, so nothing here is jittered
	except the colour.

	RADIUS ARITHMETIC (declared 8.6). The plinth is the widest box,
	0.5*sqrt(2*11.6^2) = 8.20. A minaret stands at sqrt(2*4.6^2) = 6.51 with a
	half-diagonal of 0.57 => 7.08. So 8.20 <= 8.6.
	NO ACCENT: the marble is the brightest albedo in the palette already.
	"""
	const PLINTH := Vector3(11.6, 0.9, 11.6)
	const HALL := Vector3(6.0, 5.0, 6.0)
	const MINARET_OFF := 4.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var marble := _lm_shade(LM_MARBLE, rng, 0.02)

	terrain.create_box(center + Vector3(0.0, PLINTH.y / 2.0, 0.0), PLINTH, yaw, rng, block_batch, block_body, 0.0, marble)
	var hall_y := PLINTH.y
	terrain.create_box(center + Vector3(0.0, hall_y + HALL.y / 2.0, 0.0), HALL, yaw, rng, block_batch, block_body, 0.0, marble)

	# The iwan: a tall dark recess in the front (+Z) face. Trim only — it sits on
	# the hall's own collision volume, so collide = false keeps the wall solid.
	terrain.create_box(center + rot * Vector3(0.0, hall_y + 1.9, HALL.z / 2.0 - 0.05), Vector3(2.4, 3.4, 0.5),
			yaw, rng, block_batch, block_body, 0.0, LM_MARBLE.darkened(0.72), false)

	# The dome: drum, bulbous dome, and collar plus a finial. Replacing the
	# stepped flattened-lens tiers with one cubic SPHERE restores the Mughal
	# silhouette while preserving box count, draw order, and collisions.
	var y := hall_y + HALL.y
	# A CYLINDER for the drum, a cubic SPHERE for the bulbous dome, and a
	# CYLINDER for the shoulder necking into the finial.
	var dome_kinds: Array = [ChunkBatch.BoxKind.CYLINDER, ChunkBatch.BoxKind.SPHERE, ChunkBatch.BoxKind.CYLINDER]
	var dome_i := 0
	for dims in [Vector3(2.8, 1.0, 2.8), Vector3(3.6, 3.0, 3.6), Vector3(1.2, 0.5, 1.2)]:
		terrain.create_box(center + Vector3(0.0, y + dims.y / 2.0, 0.0), dims, yaw, rng, block_batch, block_body, 0.0, marble,
				true, dome_kinds[dome_i])
		dome_i += 1
		y += dims.y
	# CYLINDER and not the cone the taper wants: this finial COLLIDES, and rule 5d
	# refuses a colliding cone (a point at the top of a box-shaped ledge). The
	# collide flag is not this bead's to move — that changes collision shapes.
	terrain.create_box(center + Vector3(0.0, y + 0.6, 0.0), Vector3(0.35, 1.2, 0.35), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng),
			true, ChunkBatch.BoxKind.CYLINDER)

	# Four minarets, one per plinth corner, each with a small cap.
	for corner in 4:
		var a := yaw + PI / 4.0 + PI / 2.0 * float(corner)
		var spot := center + Vector3(cos(a) * MINARET_OFF * sqrt(2.0), 0.0, sin(a) * MINARET_OFF * sqrt(2.0))
		terrain.create_box(spot + Vector3(0.0, PLINTH.y + 4.0, 0.0), Vector3(0.8, 8.0, 0.8), yaw, rng, block_batch, block_body, 0.0, marble,
				true, ChunkBatch.BoxKind.CYLINDER)
		terrain.create_box(spot + Vector3(0.0, PLINTH.y + 8.35, 0.0), Vector3(1.1, 0.7, 1.1), yaw, rng, block_batch, block_body, 0.0, marble,
				true, ChunkBatch.BoxKind.SPHERE)

	return { "radius": 8.6, "top": y + 1.2 }

# ----------------------------------------------------------------------------
# WAVE 2 — TEN MORE PLACES
# ----------------------------------------------------------------------------
##
## Same four rules as the eight above (batched stone through create_box, collide =
## false for trim inside another box's volume, a declared radius that BOUNDS every
## emitted corner, at most ONE emissive accent and only where a real lamp belongs).
## Two of the ten spend their accent — Big Ben's Ayrton Light, which is a real lamp
## lit while Parliament sits, and the Great Wall's beacon tower, whose entire
## purpose was to be set on fire. The other eight spend none.
##
## RADIUS ARITHMETIC, once, because all ten comments use it: the self-check
## transforms the unit cube's corners by each box's real basis, which is
## Basis(UP, yaw) * Basis(RIGHT, tilt) scaled by the dimensions. Yaw only rotates
## within the XZ plane, so the horizontal half-extent of one box is
##     sqrt( (w/2)^2 + (h/2 * |sin tilt| + d/2 * |cos tilt|)^2 )
## which at tilt = 0 is the familiar half-diagonal 0.5 * sqrt(w^2 + d^2). Each
## comment gives the worst box as "centre offset + that", which is an upper bound
## on what the check measures (it assumes the offset and the corner point the same
## way). Over-declaring is SAFE — see the note at the end of the self-check's
## check 1 — and two entries here deliberately do it, for a reason that is about
## the TOAST rather than the stone: the card's trigger distance is the declared
## radius + APPROACH_PAD, so a tall thin tower declaring its true 3.1 m footprint
## would only announce itself once the player was already standing in it.

static func _landmark_colosseum(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 8 — COLOSSEUM: an elliptical ring of arcade piers carrying a lintel band,
	a second tier standing on part of it, and a stub of a third — the collapsed
	half is the recognition cue every bit as much as the arches are, because a
	complete ring reads as a fort.

	RADIUS ARITHMETIC (declared 8.6). The widest box is a first-tier LINTEL, which
	is the one that bridges two piers and is therefore much longer than a pier:
	half-extent 0.5*sqrt(2.7^2 + 1.3^2) = 1.50 at the ellipse's semi-major 6.9, so
	6.9 + 1.50 = 8.40 <= 8.6. A pier is 6.9 + 0.99 = 7.89, and the arena floor is
	one 9.0 x 7.2 slab at the centre, i.e. 0.5*sqrt(9.0^2 + 7.2^2) = 5.76.
	RING_A is 6.9 rather than the 7.6 the footprint would allow precisely because
	of that lintel term — the Stonehenge lesson, one landmark on.
	NO ACCENT.
	"""
	const PIERS := 16
	const RING_A := 6.9          # ellipse semi-major
	const RING_B := 5.5          # semi-minor
	const PIER := Vector3(1.5, 3.0, 1.3)
	const LINTEL := Vector3(2.7, 0.7, 1.3)
	const PIER2 := Vector3(1.3, 2.6, 1.1)
	const LINTEL2 := Vector3(2.5, 0.6, 1.1)
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	# The arena floor, a shade darker so the ring reads as enclosing something.
	terrain.create_box(center + Vector3(0.0, 0.17, 0.0), Vector3(9.0, 0.35, 7.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng).darkened(0.25))

	# How much of the upper ring survives — 9 to 12 of 16 bays, which is what makes
	# one side a broken cliff and the other a wall.
	var standing := rng.randi_range(9, 12)
	var tier1_top := PIER.y + LINTEL.y
	var tier2_top := tier1_top + PIER2.y + LINTEL2.y

	for i in PIERS:
		var a := TAU * float(i) / float(PIERS)
		# Positions ride the ellipse; orientation uses the circle's tangent rule
		# (yaw + PI/2 - a, the same face-the-centre trick Stonehenge uses). A true
		# elliptical normal would differ by a few degrees, which is invisible in
		# boxes and would cost a second trig pair per pier.
		var spot: Vector3 = center + rot * Vector3(cos(a) * RING_A, 0.0, sin(a) * RING_B)
		var face := yaw + PI / 2.0 - a
		terrain.create_box(spot + Vector3(0.0, PIER.y / 2.0, 0.0), PIER, face, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03),
				true, ChunkBatch.BoxKind.CYLINDER)
		# The lintel bridging this bay to the next — trim, sitting on the piers'
		# own collision volumes, so collide = false keeps the arcade walkable.
		terrain.create_box(spot + Vector3(0.0, PIER.y + LINTEL.y / 2.0, 0.0), LINTEL, face,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), false)
		if i >= standing:
			continue
		terrain.create_box(spot + Vector3(0.0, tier1_top + PIER2.y / 2.0, 0.0), PIER2, face, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03),
				true, ChunkBatch.BoxKind.CYLINDER)
		terrain.create_box(spot + Vector3(0.0, tier1_top + PIER2.y + LINTEL2.y / 2.0, 0.0), LINTEL2, face,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), false)
		# The attic wall, on a shorter arc still, so the ruin steps down twice.
		if i < standing - 4:
			terrain.create_box(spot + Vector3(0.0, tier2_top + 1.0, 0.0), Vector3(1.2, 2.0, 0.9), face,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	return { "radius": 8.6, "top": tier2_top + 2.0 }

static func _landmark_big_ben(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 9 — BIG BEN (properly the Elizabeth Tower; Big Ben is the bell, which the
	fact says so the card teaches something): a square shaft, four pale clock faces
	under a parapet, a steep spire, and ONE emissive lamp at the very top.

	RADIUS ARITHMETIC (declared 4.4, honestly 3.11). The widest box is the base
	plinth, 0.5*sqrt(2 * 4.4^2) = 3.11 at the centre; the parapet is 2.76 and a
	clock face reaches 1.78 + 1.00 = 2.78. The declared 4.4 is DELIBERATELY LOOSE
	and the reason is the toast, not the stone: the card fires at radius +
	APPROACH_PAD (6), so a true 3.1 would only announce an 18 m tower from 9 m
	away, i.e. from inside its own shadow. Over-declaring costs a little reserved
	ground and nothing else (see the self-check's note).
	THE one accent: the Ayrton Light, lit above the clock while Parliament sits.
	"""
	const PLINTH := Vector3(4.4, 1.0, 4.4)
	const SHAFT := Vector3(3.0, 4.2, 3.0)
	const CLOCK_STAGE := Vector3(3.4, 3.0, 3.4)
	const PARAPET := Vector3(3.9, 0.55, 3.9)
	var yaw := rng.randf_range(0.0, TAU)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.03)

	terrain.create_box(center + Vector3(0.0, PLINTH.y / 2.0, 0.0), PLINTH, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
	var y := PLINTH.y
	for i in 2:
		terrain.create_box(center + Vector3(0.0, y + SHAFT.y / 2.0, 0.0), SHAFT, yaw, rng, block_batch, block_body, 0.0, stone)
		y += SHAFT.y

	# The clock stage, and the four faces on it. The faces are trim on the stage's
	# own collision volume, so collide = false — and they are the brightest albedo
	# on the tower, because at 30 m the pale discs are what say "clock".
	terrain.create_box(center + Vector3(0.0, y + CLOCK_STAGE.y / 2.0, 0.0), CLOCK_STAGE, yaw, rng, block_batch, block_body, 0.0, stone)
	var dial := _lm_shade(LM_MARBLE, rng, 0.02)
	for side in 4:
		var face_yaw := yaw + PI / 2.0 * float(side)
		var out: Vector3 = Basis(Vector3.UP, face_yaw) * Vector3(0.0, 0.0, CLOCK_STAGE.z / 2.0 + 0.08)
		terrain.create_box(center + Vector3(0.0, y + CLOCK_STAGE.y / 2.0, 0.0) + out, Vector3(2.0, 2.0, 0.16),
				face_yaw, rng, block_batch, block_body, 0.0, dial, false)
	y += CLOCK_STAGE.y

	terrain.create_box(center + Vector3(0.0, y + PARAPET.y / 2.0, 0.0), PARAPET, yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	y += PARAPET.y

	# The spire: four boxes narrowing to a point — and the ONE taper in this file
	# that stops at CYLINDER all the way up. Every box of this tower COLLIDES and
	# rule 5d refuses a colliding cone; the collide flag is not this bead's to
	# move, because that changes the chunk's collision shapes. The round tiers
	# still lose the four square corners a stepped stone spire had.
	for i in 4:
		var w: float = 3.0 - float(i) * 0.68
		var h := 1.3
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04),
				true, ChunkBatch.BoxKind.CYLINDER)
		y += h
	terrain.create_box(center + Vector3(0.0, y + 0.35, 0.0), Vector3(0.25, 0.7, 0.25), yaw, rng, block_batch, block_body, 0.0, stone,
			true, ChunkBatch.BoxKind.CYLINDER)
	y += 0.7
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 0.3, 0.0), Vector3(0.4, 0.5, 0.4), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 4.4, "top": y + 0.6 }

static func _landmark_pisa(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 10 — LEANING TOWER OF PISA: eight stacked drums with overhanging gallery
	lips, the whole stack tilted off vertical along one bearing.

	THE LEAN IS THE WHOLE LANDMARK, so it is built as a real tilted AXIS rather
	than as a stack of boxes each given a tilt: every drum's centre is placed at
	arc length `s` along a line leaning LEAN (0.10 rad, about 5.7 deg — the real
	tower is 4, exaggerated so it reads at 30 m) toward a rolled bearing, i.e.
	centre + lean_dir * (s * sin LEAN) + UP * (s * cos LEAN). A stack of tilted
	boxes at vertical offsets would shear apart at the joints.

	SIGN GOTCHA, the third instance of the one the Eiffel legs and Liberty's crown
	both record: create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt), and
	Basis(RIGHT, t) tips local +Y toward local +Z, while yaw = PI/2 - a maps local
	+Z onto (cos a, sin a). So a POSITIVE tilt leans the drum's top toward bearing
	a — which is the direction the centres are being offset in, so the two agree
	and the drums stay stacked. Negate it and the stack scissors open.

	RADIUS ARITHMETIC (declared 4.4). The widest thing is a gallery LIP near the
	top of the stack, where the lean offset has grown: at s = 9.0 the offset is
	9.0 * sin(0.10) = 0.90 and a 4.5 x 0.25 lip tilted 0.10 has half-extent
	0.5*sqrt(4.5^2 + (0.25*0.0998 + 4.5*0.995)^2) = 3.18, so 4.08 <= 4.4. The base
	drum is 0.17 + 3.16 = 3.33; the belfry lip is 1.05 + 2.62 = 3.67.
	NO ACCENT.
	"""
	const LEAN := 0.10
	const BASE_DRUM := Vector3(4.4, 1.7, 4.4)
	const GALLERY := Vector3(4.0, 1.45, 4.0)
	const BELFRY := Vector3(3.2, 1.6, 3.2)
	const GALLERIES := 5
	var lean_a := rng.randf_range(0.0, TAU)
	var drum_yaw := PI / 2.0 - lean_a
	var lean_dir := Vector3(cos(lean_a), 0.0, sin(lean_a))
	var marble := _lm_shade(LM_MARBLE, rng, 0.03)

	# One helper closure would be tidier, but GDScript lambdas cannot be static-
	# friendly here; the two lines are cheaper than the indirection.
	var s := 0.0
	var tiers: Array = [BASE_DRUM]
	for i in GALLERIES:
		tiers.append(GALLERY)
	tiers.append(BELFRY)

	for tier_variant: Variant in tiers:
		var dims: Vector3 = tier_variant
		var mid := s + dims.y / 2.0
		var drum_pos := center + lean_dir * (mid * sin(LEAN)) + Vector3(0.0, mid * cos(LEAN), 0.0)
		terrain.create_box(drum_pos, dims, drum_yaw, rng, block_batch, block_body, LEAN, _lm_shade(marble, rng, 0.02),
				true, ChunkBatch.BoxKind.CYLINDER)
		# The gallery lip capping this drum — pure overhang, sitting on the drum's
		# own collision volume, so collide = false. It is what makes the stack read
		# as a colonnaded tower rather than as a pile of blocks.
		var lip_s := s + dims.y
		var lip_pos := center + lean_dir * (lip_s * sin(LEAN)) + Vector3(0.0, lip_s * cos(LEAN), 0.0)
		var lip_dims := Vector3(dims.x + 0.5, 0.25, dims.z + 0.5)
		terrain.create_box(lip_pos, lip_dims, drum_yaw,
				rng, block_batch, block_body, LEAN, _lm_shade(marble, rng, 0.02).darkened(0.12), false, ChunkBatch.BoxKind.CYLINDER)
		s += dims.y

	return { "radius": 4.4, "top": rotated_box_top(s * cos(LEAN), Vector3(BELFRY.x + 0.5, 0.25, BELFRY.z + 0.5), LEAN) }

static func _landmark_sphinx(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 11 — GREAT SPHINX OF GIZA: a long low recumbent body with two forepaws
	stretched out in front, a raised chest, and a small head under the striped
	nemes headdress. The proportion — a body five times the height of the head,
	with paws out front — is the whole recognition cue.

	It reuses LM_SANDSTONE deliberately: this IS Giza's limestone, and the two
	never appear in the same chunk.

	RADIUS ARITHMETIC (declared 7.6). The widest reach is a FOREPAW: centre at
	sqrt(4.9^2 + 1.05^2) = 5.01 with half-diagonal 0.5*sqrt(4.2^2 + 1.0^2) = 2.16,
	so 7.17 <= 7.6. The body slab is 0.8 + 0.5*sqrt(9.4^2 + 3.4^2) = 0.8 + 5.00 =
	5.80, and the headdress is 1.6 + 1.91 = 3.51.
	NO ACCENT: the Sphinx has no light and never had one.

	CARVED PARTS ARE ROUND, THE CARCASS IS NOT (bead godot-test1-y1o.17). The
	head is a SPHERE and the chest a SPHERE (both near-cubic, 1.11 and 1.15 in
	aspect, so both collide as the SphereShape3D they draw), and the rear haunch
	is a CYLINDER — a flat drum whose aspect is measured in PLAN only (rule 5d),
	so a 1.1 m thick rump is still round in collision. The BODY SLAB STAYS A
	CUBE on purpose: at 9.4 x 2.4 x 3.4 it is 3.9 aspect, past
	ChunkBatch.ROUND_COLLIDER_MAX_ASPECT in every orientation, so a round mesh
	there would keep its BoxShape3D and put a metre of invisible stone at the
	flanks of the one landmark in this registry you can walk the whole length
	of. Rounding it honestly means splitting it into segments, which is boxes,
	which is another bead. The paws stay cubes because a paw IS a squared block.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.04)

	# The body, lying along local +X with its front end toward +X.
	const BODY := Vector3(9.4, 2.4, 3.4)
	terrain.create_box(center + rot * Vector3(-0.8, BODY.y / 2.0, 0.0), BODY, yaw, rng, block_batch, block_body, 0.0, stone)
	# The rear haunch, a little higher than the back.
	terrain.create_box(center + rot * Vector3(-3.6, BODY.y + 0.55, 0.0), Vector3(3.0, 1.1, 3.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03),
			true, ChunkBatch.BoxKind.CYLINDER)

	# The two forepaws. They collide — walking into a paw is the scale cue.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(4.9, 0.45, side * 1.05), Vector3(4.2, 0.9, 1.0), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# Chest and head.
	const CHEST := Vector3(2.6, 3.0, 3.0)
	var chest_y := BODY.y + CHEST.y / 2.0
	terrain.create_box(center + rot * Vector3(1.5, chest_y, 0.0), CHEST, yaw, rng, block_batch, block_body, 0.0, stone,
			true, ChunkBatch.BoxKind.SPHERE)
	var head_base := BODY.y + CHEST.y
	terrain.create_box(center + rot * Vector3(1.5, head_base + 0.9, 0.0), Vector3(2.0, 1.8, 2.0), yaw, rng, block_batch, block_body, 0.0, stone,
			true, ChunkBatch.BoxKind.SPHERE)
	# The nemes headdress — the flared cloth that makes the head read as a pharaoh
	# rather than as a lion's. Trim on the head's own volume.
	terrain.create_box(center + rot * Vector3(1.5, head_base + 1.5, 0.0), Vector3(2.8, 1.4, 2.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03).darkened(0.12), false)
	# The famous missing nose, as a shadowed recess.
	terrain.create_box(center + rot * Vector3(1.5 + 1.0, head_base + 0.85, 0.0), Vector3(0.35, 0.6, 0.5), yaw,
			rng, block_batch, block_body, 0.0, LM_SANDSTONE.darkened(0.6), false)

	return { "radius": 7.6, "top": head_base + 2.2 }

static func _landmark_redeemer(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 12 — CHRIST THE REDEEMER: a two-step pedestal, a robe tapering upward, a
	small head, and ONE horizontal box for the whole arm span. That single box is
	the landmark: a figure whose arms are wider than it is tall is unmistakable in
	silhouette and unrecoverable if the arms are built as two stepped limbs.

	RADIUS ARITHMETIC (declared 4.8). The arm span box is 8.4 x 0.85 at the centre,
	half-extent 0.5*sqrt(8.4^2 + 0.85^2) = 4.22; the drape blocks hanging at its
	ends reach 3.95 + 0.55 = 4.50; the pedestal is 0.5*sqrt(2 * 4.2^2) = 2.97.
	NO ACCENT: the floodlights are on the mountain, not on the statue.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var soapstone := _lm_shade(LM_STONE_GREY, rng, 0.03)

	var y := 0.0
	for dims in [Vector3(4.2, 1.2, 4.2), Vector3(3.0, 1.6, 3.0)]:
		terrain.create_box(center + Vector3(0.0, y + dims.y / 2.0, 0.0), dims, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
		y += dims.y

	# The robe: three boxes narrowing as they rise, the house's cone.
	for i in 3:
		var w: float = 2.0 - float(i) * 0.2
		var h := 2.2
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w * 0.8), yaw, rng, block_batch, block_body, 0.0, soapstone,
				true, ChunkBatch.BoxKind.CYLINDER)
		y += h

	# THE ARMS — one box, and the reason this shape works at all.
	var shoulder_y := y - 1.1
	terrain.create_box(center + Vector3(0.0, shoulder_y, 0.0), Vector3(8.4, 0.75, 0.85), yaw, rng, block_batch, block_body, 0.0, soapstone)
	# The robe hanging off each hand, which is what stops the span reading as a
	# plank. Trim beside the arm rather than inside it, but small and high, so
	# collide = false keeps the arms a clean single collision box.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 3.95, shoulder_y - 0.75, 0.0), Vector3(0.75, 1.1, 0.8), yaw,
				rng, block_batch, block_body, 0.0, soapstone, false)

	# Head and shoulders above the arms.
	terrain.create_box(center + Vector3(0.0, y + 0.5, 0.0), Vector3(0.9, 1.0, 0.9), yaw, rng, block_batch, block_body, 0.0, soapstone,
			true, ChunkBatch.BoxKind.SPHERE)

	return { "radius": 4.8, "top": y + 1.0 }

static func _landmark_torii(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 13 — ITSUKUSHIMA TORII: two vermilion pillars on four splayed feet under
	TWO crossbeams — the upper one (kasagi) sweeping upward at its ends, the lower
	one (nuki) running straight through the pillars and out the far side. Two beams
	rather than one is what separates a torii from a goalpost.

	THE UPWARD SWEEP IS BUILT AS STEPS, not as a rotation. create_box offers yaw
	and a tilt about the box's local X; the kasagi's long axis IS local X, so no
	tilt available here can lift its ends. Five segments at rising heights give the
	curve in the house's own vocabulary, which is what every other curve in this
	file does too (the Golden Gate's cable, the Taj's dome).

	RADIUS ARITHMETIC (declared 5.6). The widest are the kasagi's end caps, at
	x = 4.5 with half-diagonal 0.5*sqrt(1.2^2 + 1.0^2) = 0.78, so 5.28 <= 5.6. The
	outer kasagi segments are 3.6 + 1.14 = 4.74 and the nuki is 0.5*sqrt(7.6^2 +
	0.9^2) = 3.83.
	NO ACCENT.
	"""
	const PILLAR := Vector3(0.95, 6.0, 0.95)
	const PILLAR_X := 2.8
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var lacquer := _lm_shade(LM_VERMILION, rng, 0.04)

	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * PILLAR_X, PILLAR.y / 2.0, 0.0), PILLAR, yaw, rng, block_batch, block_body, 0.0, lacquer,
				true, ChunkBatch.BoxKind.CYLINDER)
		# The four splayed support legs that make this the ITSUKUSHIMA torii rather
		# than a plain one — the shrine's gate stands in the sea on exactly these.
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(side * (PILLAR_X + 0.15), 1.9, z_side * 1.5), Vector3(0.5, 3.8, 0.5),
					yaw, rng, block_batch, block_body, 0.0, _lm_shade(lacquer, rng, 0.03), true, ChunkBatch.BoxKind.CYLINDER)

	# The nuki: straight, and deliberately longer than the pillar spacing so it
	# protrudes on both sides. Trim (it threads the pillars' own volumes).
	terrain.create_box(center + Vector3(0.0, 4.3, 0.0), Vector3(7.6, 0.6, 0.9), yaw, rng, block_batch, block_body, 0.0, lacquer, false)
	# The gakuzuka, the short strut standing on the nuki.
	terrain.create_box(center + Vector3(0.0, 5.35, 0.0), Vector3(0.5, 1.5, 0.5), yaw, rng, block_batch, block_body, 0.0, lacquer, false, ChunkBatch.BoxKind.CYLINDER)

	# The shimaki (the flat second beam) and the kasagi above it, both stepped
	# upward toward the ends. All trim: a beam 6 m up is not something to stand on.
	var dark := _lm_shade(LM_VERMILION, rng, 0.03).darkened(0.2)
	terrain.create_box(center + Vector3(0.0, 6.1, 0.0), Vector3(7.4, 0.5, 1.0), yaw, rng, block_batch, block_body, 0.0, dark, false)
	const KASAGI_X: Array = [-3.6, -1.8, 0.0, 1.8, 3.6]
	const KASAGI_Y: Array = [6.78, 6.64, 6.58, 6.64, 6.78]
	for i in KASAGI_X.size():
		terrain.create_box(center + rot * Vector3(KASAGI_X[i], KASAGI_Y[i], 0.0), Vector3(2.0, 0.55, 1.1), yaw,
				rng, block_batch, block_body, 0.0, lacquer, false)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 4.5, 6.95, 0.0), Vector3(1.2, 0.5, 1.0), yaw,
				rng, block_batch, block_body, 0.0, lacquer, false)

	return { "radius": 5.6, "top": 7.2 }

static func _landmark_great_wall(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 14 — GREAT WALL OF CHINA: a battlemented wall running clean across the
	chunk with a square watchtower astride it, the wall's height stepping up and
	down so it reads as following a ridge rather than as a fence.

	FIVE SEGMENTS, NOT ONE WALL, and it is the Plaza Mayor's reason exactly: a
	single 17 m box has a half-diagonal of 8.6 which, added to nothing at all,
	already crowds the bound, and there is then no room for the watchtower. Five
	3.5 m bays put the outermost centre at 6.8 with a half-diagonal of 2.12.

	RADIUS ARITHMETIC (declared 9.4, honestly 8.92). The end bay is 6.8 + 2.12 =
	8.92; a merlon on the parapet reaches 8.0 + 0.47 = 8.47; the tower roof is
	0.5*sqrt(4.9^2 + 4.1^2) = 3.19. Declared loose for the toast's sake, like Big
	Ben — this landmark is 17 m long and a card that fired at 15 m would go off
	while the player was already walking along the parapet.
	THE one accent: the beacon fire on the watchtower. Signal fires are what these
	towers were FOR — the wall was a communication line before it was a barrier.
	"""
	const BAYS := 5
	const BAY_STEP := 3.4
	const BAY := Vector3(3.5, 0.0, 2.4)   # y filled in per bay
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	var tallest := 0.0
	for i in BAYS:
		var along := (float(i) - float(BAYS - 1) / 2.0) * BAY_STEP
		var h := rng.randf_range(2.6, 3.6)
		tallest = maxf(tallest, h)
		terrain.create_box(center + rot * Vector3(along, h / 2.0, 0.0), Vector3(BAY.x, h, BAY.z), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		# The battlements: alternating merlons along the outer edge of this bay.
		# Trim on the wall's own volume — a 0.65 m block on a parapet is not a step.
		for m in 2:
			var mx := along + (float(m) - 0.5) * 1.7
			terrain.create_box(center + rot * Vector3(mx, h + 0.32, -BAY.z / 2.0 + 0.28), Vector3(0.75, 0.65, 0.55), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), false)

	# The watchtower, astride the middle bay.
	var tower_h: float = tallest + 2.4
	terrain.create_box(center + Vector3(0.0, tower_h / 2.0, 0.0), Vector3(4.2, tower_h, 3.4), yaw, rng, block_batch, block_body, 0.0, stone)
	terrain.create_box(center + Vector3(0.0, tower_h + 0.25, 0.0), Vector3(4.9, 0.5, 4.1), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)
	# Two dark window slots, so the tower reads as occupied.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 1.1, tower_h - 1.0, 1.68), Vector3(0.6, 1.0, 0.3), yaw,
				rng, block_batch, block_body, 0.0, LM_STONE_GREY.darkened(0.7), false)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, tower_h + 0.9, 0.0), Vector3(0.7, 0.7, 0.7), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 9.4, "top": tower_h + 0.5 }

static func _landmark_brandenburg(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 15 — BRANDENBURG GATE (Brandenburger Tor): twelve Doric columns in two
	rows under a three-bay entablature, flanked by the two pavilion wings, with the
	copper Quadriga — a chariot and four horses — standing on the attic.

	The gate you can WALK THROUGH is the point: the columns collide and the bays
	between them do not, so the five passages are real.

	RADIUS ARITHMETIC (declared 8.4). The widest reach is a flanking WING: centre
	at 6.0 with half-diagonal 0.5*sqrt(1.8^2 + 3.8^2) = 2.10, so 8.10 <= 8.4. The
	plinth slab is 0.5*sqrt(12.6^2 + 4.8^2) = 6.74 at the centre, an architrave bay
	is 4.4 + 3.04 = 7.44, and a corner column is 5.23 + 0.64 = 5.87.
	NO ACCENT.
	"""
	const COL := Vector3(0.95, 6.0, 0.95)
	const COL_X: Array = [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]
	const COL_Z := 1.55
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.03)

	terrain.create_box(center + Vector3(0.0, 0.3, 0.0), Vector3(12.6, 0.6, 4.8), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
	var col_base := 0.6

	for cx_variant: Variant in COL_X:
		var cx: float = cx_variant
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(cx, col_base + COL.y / 2.0, z_side * COL_Z), COL, yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02),
					true, ChunkBatch.BoxKind.CYLINDER)

	# The entablature, in three bays for the Plaza Mayor's radius reason.
	var arch_y := col_base + COL.y
	for bx in [-4.4, 0.0, 4.4]:
		terrain.create_box(center + rot * Vector3(bx, arch_y + 0.5, 0.0), Vector3(4.4, 1.0, 4.2), yaw, rng, block_batch, block_body, 0.0, stone)
	# The attic block the Quadriga stands on.
	var attic_y := arch_y + 1.0
	terrain.create_box(center + Vector3(0.0, attic_y + 0.8, 0.0), Vector3(7.2, 1.6, 3.2), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))

	# The flanking pavilion wings.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 6.0, 2.2, 0.0), Vector3(1.8, 4.4, 3.8), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))

	# THE QUADRIGA — chariot plus four horses, in oxidised copper so it reads
	# against the sandstone. All trim: it is 11 m up and nothing may stand on it.
	var q_y := attic_y + 1.6
	var copper := _lm_shade(LM_COPPER, rng, 0.03)
	terrain.create_box(center + rot * Vector3(-1.2, q_y + 0.55, 0.0), Vector3(1.4, 1.1, 1.3), yaw, rng, block_batch, block_body, 0.0, copper, false)
	for h in 4:
		var hx: float = 0.2 + float(h) * 0.85
		terrain.create_box(center + rot * Vector3(hx, q_y + 0.6, (float(h) - 1.5) * 0.55), Vector3(1.6, 1.2, 0.55), yaw,
				rng, block_batch, block_body, 0.0, copper, false)
		terrain.create_box(center + rot * Vector3(hx + 0.85, q_y + 1.15, (float(h) - 1.5) * 0.55), Vector3(0.5, 0.5, 0.4), yaw,
				rng, block_batch, block_body, 0.0, copper, false)

	return { "radius": 8.4, "top": q_y + 1.4 }

static func _landmark_neuschwanstein(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 16 — NEUSCHWANSTEIN CASTLE: a white castle on a grey crag — a tall slender
	keep, a long palas beside it, a lower gatehouse, three corner turrets, and a
	blue-grey conical roof on every one of them. The BLUE ROOFS are the recognition
	cue and the reason LM_SLATE_BLUE is one of the two colours wave 2 added: the
	walls reuse the Taj's marble, so without them a distant white castle is a
	distant white mausoleum.

	RADIUS ARITHMETIC (declared 8.0). The widest reach is the GATEHOUSE, centre at
	sqrt(4.8^2 + 0.8^2) = 4.87 with half-diagonal 0.5*sqrt(3.2^2 + 3.4^2) = 2.33,
	so 7.20 <= 8.0. The crag slab is 0.5*sqrt(7.6^2 + 6.4^2) = 4.97, a turret's
	roof base reaches 5.2 + 1.27 = 6.47, and the keep is 4.05 + 1.56 = 5.61.
	NO ACCENT.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var wall := _lm_shade(LM_MARBLE, rng, 0.02)
	var roof := _lm_shade(LM_SLATE_BLUE, rng, 0.04)

	# The crag. Two grey slabs, so the castle stands on rock rather than on grass.
	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(7.6, 1.0, 6.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.05))
	terrain.create_box(center + rot * Vector3(-0.4, 1.7, 0.0), Vector3(5.4, 1.4, 5.0), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.05))
	const CRAG := 2.4

	# The palas, in two bays.
	for bx in [-2.2, 2.2]:
		terrain.create_box(center + rot * Vector3(bx, CRAG + 3.2, 0.0), Vector3(4.2, 6.4, 4.2), yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02))
	# A gabled roof band over the palas — trim on the bays' own volumes.
	terrain.create_box(center + Vector3(0.0, CRAG + 6.8, 0.0), Vector3(8.8, 0.8, 4.6), yaw, rng, block_batch, block_body, 0.0, roof, false)

	# The gatehouse, lower and off to one side.
	terrain.create_box(center + rot * Vector3(4.8, CRAG + 2.3, 0.8), Vector3(3.2, 4.6, 3.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02))
	terrain.create_box(center + rot * Vector3(4.8, CRAG + 4.9, 0.8), Vector3(3.6, 0.7, 3.8), yaw, rng, block_batch, block_body, 0.0, roof, false)
	# Its dark arched doorway.
	terrain.create_box(center + rot * Vector3(4.8, CRAG + 1.2, 2.55), Vector3(1.2, 2.2, 0.4), yaw,
			rng, block_batch, block_body, 0.0, LM_MARBLE.darkened(0.72), false)

	# The keep — the tall slender one, and the tallest thing here.
	const KEEP := Vector3(2.2, 10.5, 2.2)
	var keep_spot := center + rot * Vector3(-3.8, 0.0, -1.4)
	terrain.create_box(keep_spot + Vector3(0.0, CRAG + KEEP.y / 2.0, 0.0), KEEP, yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02),
			true, ChunkBatch.BoxKind.CYLINDER)
	var top := CRAG + KEEP.y
	# Its spire: three shrinking slabs to a point — the taper rule, CONE last.
	for i in 3:
		var w: float = 2.7 - float(i) * 0.75
		terrain.create_box(keep_spot + Vector3(0.0, top + 0.6, 0.0), Vector3(w, 1.2, w), yaw, rng, block_batch, block_body, 0.0, roof, false,
				ChunkBatch.BoxKind.CONE if i == 2 else ChunkBatch.BoxKind.CYLINDER)
		top += 1.2

	# Three corner turrets, each with its own cone.
	const TURRET_SPOTS: Array = [Vector2(-4.4, 2.6), Vector2(1.4, -3.4), Vector2(4.4, -2.4)]
	for spot_variant: Variant in TURRET_SPOTS:
		var spot: Vector2 = spot_variant
		var base := center + rot * Vector3(spot.x, 0.0, spot.y)
		var t_h := rng.randf_range(6.0, 7.4)
		terrain.create_box(base + Vector3(0.0, CRAG + t_h / 2.0, 0.0), Vector3(1.3, t_h, 1.3), yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02),
				true, ChunkBatch.BoxKind.CYLINDER)
		var ty := CRAG + t_h
		for i in 2:
			var w: float = 1.8 - float(i) * 0.7
			terrain.create_box(base + Vector3(0.0, ty + 0.45, 0.0), Vector3(w, 0.9, w), yaw, rng, block_batch, block_body, 0.0, roof, false,
					ChunkBatch.BoxKind.CONE if i == 1 else ChunkBatch.BoxKind.CYLINDER)
			ty += 0.9

	return { "radius": 8.0, "top": top }

static func _landmark_cologne(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 17 — COLOGNE CATHEDRAL (Kölner Dom): TWIN openwork spires over a west
	front, a nave running back behind them under a steep ridge roof, and a small
	apse at the far end. Twin spires of equal height is the cue — one spire is a
	church, two is the Dom.

	It reuses LM_BASALT: Cologne's stone is near-black with centuries of soot, and
	nothing else in the registry is that dark except the Moai, whose silhouette
	could not be confused with this one at any distance.

	RADIUS ARITHMETIC (declared 8.6). The furthest box is the APSE at the far end
	of the nave: centre at 6.2 with half-diagonal 0.5*sqrt(3.6^2 + 2.2^2) = 2.11,
	so 8.31 <= 8.6. A nave bay is 4.0 + 3.28 = 7.28, the roof ridge is 2.3 + 4.47 =
	6.77, and a tower is sqrt(2.2^2 + 3.0^2) = 3.72 + 2.12 = 5.84.
	NO ACCENT: a Gothic cathedral lit from within would need windows, and windows
	are exactly the detail that vanishes at 30 m.
	"""
	const TOWER := Vector3(3.0, 13.0, 3.0)
	const TOWER_X := 2.2
	const TOWER_Z := -3.0
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_BASALT, rng, 0.03)

	# The nave, two bays, plus the ridge roof over them.
	for bz in [0.6, 4.0]:
		terrain.create_box(center + rot * Vector3(0.0, 3.6, bz), Vector3(5.6, 7.2, 3.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	terrain.create_box(center + rot * Vector3(0.0, 7.85, 2.3), Vector3(5.0, 1.3, 7.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02).darkened(0.2), false)
	# The apse closing the far end.
	terrain.create_box(center + rot * Vector3(0.0, 3.3, 6.2), Vector3(3.6, 6.6, 2.2), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	# Buttress stubs down the flanks — the ribs that say Gothic in four boxes.
	for bx in [-3.6, 3.6]:
		for bz in [1.0, 4.2]:
			terrain.create_box(center + rot * Vector3(bx, 2.6, bz), Vector3(0.9, 5.2, 0.9), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# The west front between the towers.
	terrain.create_box(center + rot * Vector3(0.0, 5.25, TOWER_Z), Vector3(1.8, 10.5, 3.0), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	# The great west portal, dark and deep.
	terrain.create_box(center + rot * Vector3(0.0, 1.7, TOWER_Z - 1.6), Vector3(1.4, 3.4, 0.5), yaw,
			rng, block_batch, block_body, 0.0, LM_BASALT.darkened(0.6), false)

	# THE TWIN TOWERS and their spires — equal height, deliberately, because that
	# is the whole recognition cue.
	var tip := 0.0
	for side in [-1.0, 1.0]:
		var base := center + rot * Vector3(side * TOWER_X, 0.0, TOWER_Z)
		terrain.create_box(base + Vector3(0.0, TOWER.y / 2.0, 0.0), TOWER, yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
		var y := TOWER.y
		# Four shrinking slabs to a needle point. Trim: it is 13 m up. The taper
		# rule: CYLINDER all the way up, CONE on the piece that ends it.
		for i in 4:
			var w: float = 2.7 - float(i) * 0.6
			var h := 1.5
			terrain.create_box(base + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.CYLINDER)
			y += h
		terrain.create_box(base + Vector3(0.0, y + 0.5, 0.0), Vector3(0.3, 1.0, 0.3), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.CONE)
		tip = y + 1.0

	return { "radius": 8.6, "top": tip }

# ----------------------------------------------------------------------------
# WAVE 3
# ----------------------------------------------------------------------------

static func _lm_onion(terrain: Node3D, base: Vector3, width: float, color: Color, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> float:
	"""
	ONE ONION DOME, and the middle box is the WIDEST — that is the entire trick. A
	stack that only ever narrows is a cone, and this file already has cones
	(Neuschwanstein's spires, Angkor's lotus towers taper the same way); the BULGE
	is what makes a dome an onion, so this goes drum -> bulge wider than the drum ->
	shoulder narrowing back in -> finial spike.

	Shared by St Basil's six ring towers and its centre spire's crown, which is why
	the six read as one building rather than as six separate experiments. Returns
	the height it added above `base` (which is the top of whatever it stands on).

	ALL OF IT IS collide = false: these sit 6-14 m up, on their own tower's
	collision volume, and a 2 m bulb is not a thing to stand on.
	"""
	var h := 0.0
	terrain.create_box(base + Vector3(0.0, 0.25, 0.0), Vector3(width * 0.78, 0.5, width * 0.78), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(color, rng, 0.03), false, ChunkBatch.BoxKind.CYLINDER)
	h += 0.5
	terrain.create_box(base + Vector3(0.0, h + width * 0.42, 0.0), Vector3(width, width * 0.84, width), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(color, rng, 0.03), false, ChunkBatch.BoxKind.SPHERE)
	h += width * 0.84
	terrain.create_box(base + Vector3(0.0, h + 0.28, 0.0), Vector3(width * 0.52, 0.56, width * 0.52), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(color, rng, 0.03), false, ChunkBatch.BoxKind.CYLINDER)
	h += 0.56
	terrain.create_box(base + Vector3(0.0, h + 0.55, 0.0), Vector3(0.18, 1.1, 0.18), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng, 0.02), false, ChunkBatch.BoxKind.CONE)
	return h + 1.1

static func _landmark_st_basil(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 18 — ST BASIL'S CATHEDRAL: a low white podium carrying a tall central tent
	spire ringed by six shorter towers, each capped with an ONION DOME in a
	different colour.

	THE ONLY LANDMARK IN THE REGISTRY WHOSE COLOURS DO THE RECOGNISING, which is
	precisely why the four it needs had to already exist — LM_VERMILION brick,
	LM_COPPER oxidised green, LM_MARBLE white and LM_SANDSTONE standing in for gold
	leaf. At the 30 m these shapes are judged from a warm tan reads as gold, and
	adding a fifth entry to the palette to be literal about it would have made every
	OTHER landmark one shade harder to tell apart (the wave-2 palette rule).

	The centre tower is a TENT ROOF rather than an onion, and that contrast is
	deliberate: the real cathedral's middle spire is the one thing on it that does
	not bulge, so making it bulge too would flatten nine domes into one texture.

	RADIUS ARITHMETIC (declared 6.4). The podium is the widest box, 8.0 square, so
	0.5*sqrt(2*8.0^2) = 5.66. A ring tower's dome bulge is 1.9 square (half-diagonal
	1.34) on the RING_R 3.6 ring => 4.94. So 5.66 <= 6.4.
	NO ACCENT: the domes are gilded, not lit.
	"""
	const RING_R := 3.6
	const TOWERS := 6
	const PODIUM := Vector3(8.0, 1.0, 8.0)
	# Cycled round the ring, and 4 into 6 does not divide — which is the point: no
	# two neighbours match and the pattern does not repeat on the far side either.
	var dome_colors: Array = [LM_VERMILION, LM_COPPER, LM_SANDSTONE, LM_MARBLE]
	var yaw := rng.randf_range(0.0, TAU)
	var brick := _lm_shade(LM_VERMILION, rng, 0.04).darkened(0.1)

	terrain.create_box(center + Vector3(0.0, PODIUM.y / 2.0, 0.0), PODIUM, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_MARBLE, rng, 0.03))

	# The six chapel towers. Heights step in threes so the ring reads as a crown
	# rather than as a fence of equal posts — no two of the real ones match either.
	var top := PODIUM.y
	for i in TOWERS:
		var a := yaw + TAU * float(i) / float(TOWERS)
		var spot := center + Vector3(cos(a) * RING_R, 0.0, sin(a) * RING_R)
		var shaft_h: float = 4.2 + float(i % 3) * 1.1
		terrain.create_box(spot + Vector3(0.0, PODIUM.y + shaft_h / 2.0, 0.0), Vector3(1.7, shaft_h, 1.7), yaw,
				rng, block_batch, block_body, 0.0, brick, true, ChunkBatch.BoxKind.CYLINDER)
		var dome_h := _lm_onion(terrain, spot + Vector3(0.0, PODIUM.y + shaft_h, 0.0), 1.9,
				dome_colors[i % dome_colors.size()], yaw, rng, block_batch, block_body)
		top = maxf(top, PODIUM.y + shaft_h + dome_h)

	# The centre: an octagonal shaft (two boxes crossed at 45 degrees, which is as
	# octagonal as a box vocabulary gets) under a stepped tent roof.
	const SHAFT_H := 9.0
	for k in 2:
		terrain.create_box(center + Vector3(0.0, PODIUM.y + SHAFT_H / 2.0, 0.0), Vector3(2.9, SHAFT_H, 2.9),
				yaw + float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, _lm_shade(LM_MARBLE, rng, 0.03),
				true, ChunkBatch.BoxKind.CYLINDER)
	var ty := PODIUM.y + SHAFT_H
	for i in 5:
		var w: float = 2.7 - float(i) * 0.46
		terrain.create_box(center + Vector3(0.0, ty + 0.55, 0.0), Vector3(w, 1.1, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(LM_VERMILION, rng, 0.03), false,
				ChunkBatch.BoxKind.CONE if i == 4 else ChunkBatch.BoxKind.CYLINDER)
		ty += 1.1
	var crown := _lm_onion(terrain, center + Vector3(0.0, ty, 0.0), 1.2, LM_SANDSTONE, yaw, rng, block_batch, block_body)

	return { "radius": 6.4, "top": maxf(top, ty + crown) }

static func _landmark_sydney_opera(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 19 — SYDNEY OPERA HOUSE: a low podium carrying three groups of white
	SHELLS, each shell a run of slabs that get shorter and narrower as they step
	away from its mouth — a sail seen edge on. Two big groups facing one way and a
	small third facing the other is the plan of the real building, and that
	asymmetric roofline is most of what a person actually recognises; three
	identical shells would read as a row of tents.

	SHELLS ARE STEPS, NOT ARCS, for the torii's reason exactly: create_box offers a
	yaw and a tilt about the box's own local X, and neither can sweep a box's TOP
	into a curve. Six stepped slabs give the sail in the house's own vocabulary.
	The shells COLLIDE — they are the building — and only the dark glass mouth,
	which sits inside a shell's own volume, does not.

	A SLAB IS A CYLINDER AND NOT A SPHERE, and the difference is where the player
	stands (bead godot-test1-y1o.17). Rounding the slabs is the point — six
	rectangles stepping back is the most box-like silhouette in the registry —
	but a SPHERE tapers to nothing at the box's FLOOR, and the shells stand on a
	1.1 m podium a player can walk onto, so a lens-shaped sail would put a 3.4 m
	wide invisible wall around a needle at foot height. A CYLINDER fills its box
	top to bottom, so there is no foot-height hole at all — every height of the
	box is filled to the inscribed ellipse — and the sail is round where you see
	it edge on. It is past ChunkBatch.ROUND_COLLIDER_MAX_ASPECT in plan (4.0), so
	the collider is the same BoxShape3D these slabs have always had and nothing
	about walking into the Opera House changed. **What it costs is named
	honestly**: the ellipse leaves the box everywhere but its four tangent
	points, worst along the long face — on the widest slab (3.4 x 0.85) the
	drawn surface at x = +/-1.5 is 0.20 m off the axis while the collider's face
	is still at 0.425, and the gap at a box corner is about 0.51 m. That is
	invisible stone along the outer third of each long face, on a podium a player
	can walk onto, and it is the price of a round sail until a shell is drawn as
	more than one piece — which is boxes and its own bead.

	RADIUS ARITHMETIC (declared 8.2). The podium is the widest box, 14.0 x 6.0, so
	0.5*sqrt(14.0^2 + 6.0^2) = 7.62. The furthest shell slab is the small group's
	last, at sqrt(4.8^2 + 2.99^2) = 5.66 with a half-diagonal of 0.96 => 6.62; the
	big group's is 4.31 + 1.75 = 6.06. So 7.62 <= 8.2.
	NO ACCENT.
	"""
	const PODIUM := Vector3(14.0, 1.1, 6.0)
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var sail := _lm_shade(LM_MARBLE, rng, 0.02)

	terrain.create_box(center + Vector3(0.0, PODIUM.y / 2.0, 0.0), PODIUM, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.03))

	# x offset, z offset, which way the shell steps back, and how big it is.
	var groups: Array = [
		{ "x": -3.4, "z": -0.6, "dir": 1.0, "s": 1.0 },
		{ "x": 1.4, "z": 0.4, "dir": 1.0, "s": 0.82 },
		{ "x": 4.8, "z": -1.2, "dir": -1.0, "s": 0.55 },
	]
	var tallest := PODIUM.y
	for g in groups:
		var s: float = g.s
		var dir: float = g.dir
		for i in 6:
			var t := float(i) / 5.0
			var h: float = (7.6 - 5.6 * t) * s      # the tall slab is at the shell's MOUTH
			var w: float = (3.4 - 1.9 * t) * s
			var d: float = (0.85 - 0.28 * t) * s
			var z: float = float(g.z) + dir * (0.35 + t * 2.9) * s
			terrain.create_box(center + rot * Vector3(g.x, PODIUM.y + h / 2.0, z), Vector3(w, h, d), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(sail, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
			tallest = maxf(tallest, PODIUM.y + h)

	# The glass wall closing each shell's mouth — the dark vertical face that stops
	# a shell reading as a solid white wedge. Trim on the shell's own volume.
	for g in groups:
		var s: float = g.s
		terrain.create_box(center + rot * Vector3(g.x, PODIUM.y + 2.4 * s, float(g.z) - float(g.dir) * 0.52 * s),
				Vector3(3.2 * s, 4.4 * s, 0.25), yaw, rng, block_batch, block_body, 0.0,
				LM_SLATE_BLUE.darkened(0.35), false)

	return { "radius": 8.2, "top": tallest }

static func _landmark_chichen_itza(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 20 — CHICHÉN ITZÁ: El Castillo — a nine-tier square step pyramid with ONE
	broad stairway climbing the front face and a small temple on the summit.

	THE STAIR AND THE TEMPLE ARE THE WHOLE REASON THIS IS NOT GIZA. Both landmarks
	are stepped pyramids of sandstone-coloured boxes, and the registry can put
	either in front of the player, so the two things that separate them get real
	geometry and the tiers get nothing else at all: Giza is a TRIO of smooth
	shrinking stacks, this is ONE stack with a stripe of treads up its face and a
	block on top.

	The treads COLLIDE and are untilted, so the stair is a real climb rather than a
	painted stripe — 0.92 m a step, comfortably inside the 3.6125 m jump apex.

	RADIUS ARITHMETIC (declared 8.4). The bottom tier is 11.0 square, so
	0.5*sqrt(2*11.0^2) = 7.78. Its tread sits at z = 5.95 with a half-diagonal of
	0.5*sqrt(3.6^2 + 1.0^2) = 1.87 => 7.82. So 7.82 <= 8.4.
	NO ACCENT: the serpent's shadow needs an equinox, not a lamp.
	"""
	const TIERS := 9
	const BASE_W := 11.0
	const TIER_H := 0.92
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var limestone := _lm_shade(LM_SANDSTONE, rng, 0.04)

	# Divided by TIERS + 3 rather than TIERS + 1 so the summit stays broad enough to
	# carry the temple — a pyramid that tapers to a point has nowhere to put one.
	var shrink := BASE_W / float(TIERS + 3)
	var y := 0.0
	for i in TIERS:
		var w: float = BASE_W - float(i) * shrink
		terrain.create_box(center + Vector3(0.0, y + TIER_H / 2.0, 0.0), Vector3(w, TIER_H, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(limestone, rng, 0.02))
		terrain.create_box(center + rot * Vector3(0.0, y + TIER_H / 2.0, w / 2.0 + 0.45), Vector3(3.6, TIER_H, 1.0), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(limestone, rng, 0.02))
		y += TIER_H

	# The temple: a squat block with a cornice and one dark doorway.
	const TEMPLE := Vector3(3.4, 2.6, 3.4)
	terrain.create_box(center + Vector3(0.0, y + TEMPLE.y / 2.0, 0.0), TEMPLE, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(limestone, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, y + TEMPLE.y + 0.2, 0.0), Vector3(3.9, 0.4, 3.9), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(limestone, rng, 0.03), false)
	terrain.create_box(center + rot * Vector3(0.0, y + 1.05, TEMPLE.z / 2.0 - 0.08), Vector3(1.3, 1.9, 0.35), yaw,
			rng, block_batch, block_body, 0.0, LM_SANDSTONE.darkened(0.75), false)

	return { "radius": 8.4, "top": y + TEMPLE.y + 0.4 }

static func _landmark_petra(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 21 — PETRA: Al-Khazneh, and the recognition cue is that the building is NOT
	a building — it is a facade cut INTO a cliff. So the cliff goes up first, at full
	width and with two ragged shoulders so it does not read as a wall somebody built,
	and everything else is carved out of its front face.

	THE SECOND STOREY IS WHAT MAKES IT PETRA. A row of columns under a triangular
	pediment is a temple, and this registry already has that silhouette twice (the
	Brandenburg Gate's colonnade, the Plaza's arcade). What nothing else has is the
	upper storey: a round drum with a conical cap standing BETWEEN two half-pediments,
	which is why the tholos gets its own crossed-box octagon rather than being
	simplified into another block.

	RADIUS ARITHMETIC (declared 8.0). The cliff slab is the widest box, 12.0 x 3.2,
	set back to z = -1.3: 1.3 + 0.5*sqrt(12.0^2 + 3.2^2) = 1.3 + 6.22 = 7.52. The
	entablature is 10.0 x 1.4 at z = 0.55 => 0.55 + 5.05 = 5.60; a shoulder is at
	sqrt(5.2^2 + 0.6^2) = 5.23 with half-diagonal 1.56 => 6.79. So 7.52 <= 8.0.
	NO ACCENT.
	"""
	const CLIFF := Vector3(12.0, 14.0, 3.2)
	const FACADE_Z := 0.35
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var rock := _lm_shade(LM_OCHRE, rng, 0.05)

	terrain.create_box(center + rot * Vector3(0.0, CLIFF.y / 2.0, -1.3), CLIFF, yaw, rng, block_batch, block_body, 0.0, rock)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 5.2, 4.5, 0.6), Vector3(2.4, 9.0, 2.0),
				yaw + side * 0.12, rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.04))

	# LOWER STOREY: a plinth, six columns, an entablature, a stepped pediment.
	terrain.create_box(center + rot * Vector3(0.0, 0.35, FACADE_Z), Vector3(9.6, 0.7, 2.0), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
	for i in 6:
		terrain.create_box(center + rot * Vector3((float(i) - 2.5) * 1.7, 3.3, FACADE_Z + 0.35), Vector3(0.7, 5.2, 0.7), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03), true, ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(center + rot * Vector3(0.0, 6.3, FACADE_Z + 0.2), Vector3(10.0, 1.0, 1.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
	for i in 3:
		terrain.create_box(center + rot * Vector3(0.0, 7.1 + float(i) * 0.6, FACADE_Z + 0.1),
				Vector3(8.6 - float(i) * 2.6, 0.6, 1.1), yaw, rng, block_batch, block_body, 0.0,
				_lm_shade(rock, rng, 0.03), false)
	# The doorway — the one thing on the facade that is a hole rather than stone.
	terrain.create_box(center + rot * Vector3(0.0, 2.5, FACADE_Z - 0.5), Vector3(2.0, 4.0, 0.4), yaw,
			rng, block_batch, block_body, 0.0, LM_OCHRE.darkened(0.8), false)

	# UPPER STOREY: two flanking blocks with their broken cornices, and the tholos.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 3.5, 10.2, FACADE_Z), Vector3(2.6, 5.0, 1.2), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
		terrain.create_box(center + rot * Vector3(side * 3.5, 12.9, FACADE_Z), Vector3(3.0, 0.5, 1.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03), false)
	# THE THOLOS. The crossed pair that was the octagon is now two CYLINDERS —
	# the same drum, actually round — and its cap takes the taper rule.
	for k in 2:
		terrain.create_box(center + rot * Vector3(0.0, 10.4, FACADE_Z + 0.1), Vector3(3.2, 4.6, 3.2),
				yaw + float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03),
				true, ChunkBatch.BoxKind.CYLINDER)
	for i in 3:
		var w: float = 2.6 - float(i) * 0.75
		terrain.create_box(center + rot * Vector3(0.0, 12.9 + float(i) * 0.55, FACADE_Z + 0.1), Vector3(w, 0.55, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03), false,
				ChunkBatch.BoxKind.CONE if i == 2 else ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(center + rot * Vector3(0.0, 14.9, FACADE_Z + 0.1), Vector3(0.9, 1.0, 0.9), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03), false, ChunkBatch.BoxKind.CONE)

	return { "radius": 8.0, "top": 15.4 }

static func _landmark_rushmore(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 22 — MOUNT RUSHMORE: a granite bluff built from four jagged segments, with
	four heads in a row protruding from its front face and a talus of tumbled
	boulders at its foot.

	THE ROCK IS DELIBERATELY IRREGULAR and the heads are deliberately not. Four busts
	in a row on a tidy wall is a monument; four faces emerging from a mountain that
	clearly was not built is Rushmore, so the cliff segments jitter in height and yaw
	while the heads stay level, evenly spaced and identical in size.

	RADIUS ARITHMETIC (declared 8.6). The outermost cliff segment is at
	sqrt(5.4^2 + 1.0^2) = 5.49 with a half-diagonal of 0.5*sqrt(4.6^2 + 3.6^2) = 2.92
	=> 8.41 — and its yaw jitter is already inside that, because a half-diagonal
	bounds a box at ANY yaw. The furthest boulder is at sqrt(6.4^2 + 1.9^2) = 6.68
	with a tilted half-diagonal under 1.30 => 7.98; the outermost head's hair block is
	at 5.55 + 1.17 = 6.72. So 8.41 <= 8.6.
	NO ACCENT.
	"""
	const SEGMENTS := 4
	const SEG_STEP := 3.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var granite := _lm_shade(LM_GRANITE, rng, 0.05)

	var tallest := 0.0
	for i in SEGMENTS:
		var sx := (float(i) - float(SEGMENTS - 1) / 2.0) * SEG_STEP
		var h := rng.randf_range(8.0, 11.5)
		tallest = maxf(tallest, h)
		terrain.create_box(center + rot * Vector3(sx, h / 2.0, -1.0), Vector3(4.6, h, 3.6),
				yaw + rng.randf_range(-0.12, 0.12), rng, block_batch, block_body, 0.0, _lm_shade(granite, rng, 0.04))
		# One boulder off the talus slope every carved cliff has. Tilted, so it must
		# stay small: a tilt widens a box's horizontal reach as well as leaning it.
		terrain.create_box(center + rot * Vector3(sx + rng.randf_range(-1.0, 1.0), 0.7, 1.9), Vector3(1.8, 1.4, 1.5),
				yaw + rng.randf_range(0.0, TAU), rng, block_batch, block_body, rng.randf_range(-0.2, 0.2),
				_lm_shade(granite, rng, 0.05), true, ChunkBatch.BoxKind.SPHERE)

	# The four heads. Trim (brow, nose, hair) sits on the head's own volume, so
	# collide = false; the head itself collides like the rock it was cut from.
	const HEAD_Y := 6.6
	for i in 4:
		var hx := (float(i) - 1.5) * 3.4
		var face := _lm_shade(granite, rng, 0.03).lightened(0.06)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y, 2.2), Vector3(1.7, 2.2, 1.5), yaw,
				rng, block_batch, block_body, 0.0, face)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y + 0.45, 3.0), Vector3(1.5, 0.35, 0.35), yaw,
				rng, block_batch, block_body, 0.0, face, false)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y - 0.05, 3.05), Vector3(0.35, 0.7, 0.45), yaw,
				rng, block_batch, block_body, 0.0, face, false)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y + 1.35, 2.1), Vector3(1.8, 0.7, 1.5), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(granite, rng, 0.04), false)

	return { "radius": 8.6, "top": tallest }

static func _landmark_angkor_wat(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 23 — ANGKOR WAT: five lotus towers in a quincunx — four on the corners of a
	square, one taller in the middle — on two stepped terraces, with a causeway
	running out from one face.

	THE CAUSEWAY EXISTS TO MAKE THE QUINCUNX READ AS A PLAN. Five spires with nothing
	pointing at them is five spires; one walk approaching them from a single side is
	what tells the eye which way the temple faces, and a plan you can read from
	outside is the whole recognition cue.

	A LOTUS TOWER IS A CONE WITH A WAIST: four narrowing tiers, then one that goes
	WIDER again, then the finial. That small bulge two thirds up is what separates it
	from Neuschwanstein's plain cones and from El Castillo's even steps.

	RADIUS ARITHMETIC (declared 9.0). The lower terrace is 12.0 square, so
	0.5*sqrt(2*12.0^2) = 8.49. The causeway slab is 3.0 x 4.4 centred 5.4 out:
	5.4 + 0.5*sqrt(3.0^2 + 4.4^2) = 5.4 + 2.66 = 8.06. A corner tower's shaft is 2.4
	square (half-diagonal 1.70) on the (3.4, 3.4) corner (offset 4.81) => 6.51.
	So 8.49 <= 9.0.
	NO ACCENT.
	"""
	const TOWER_R := 3.4
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	var y := 0.0
	for dims in [Vector3(12.0, 0.9, 12.0), Vector3(9.4, 1.0, 9.4)]:
		terrain.create_box(center + Vector3(0.0, y + dims.y / 2.0, 0.0), dims, yaw, rng, block_batch, block_body,
				0.0, _lm_shade(stone, rng, 0.03))
		y += dims.y

	terrain.create_box(center + rot * Vector3(0.0, 0.45, 5.4), Vector3(3.0, 0.9, 4.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 1.35, 1.25, 5.4), Vector3(0.4, 0.7, 4.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)

	var spots: Array = [
		Vector2(-TOWER_R, -TOWER_R), Vector2(TOWER_R, -TOWER_R),
		Vector2(-TOWER_R, TOWER_R), Vector2(TOWER_R, TOWER_R), Vector2(0.0, 0.0),
	]
	var tallest := y
	for i in spots.size():
		var p: Vector2 = spots[i]
		var f := 1.0 if i < 4 else 1.34   # the middle one is the tall one
		var spot := center + rot * Vector3(p.x, 0.0, p.y)
		var ty := y
		terrain.create_box(spot + Vector3(0.0, ty + 1.5 * f, 0.0), Vector3(2.4 * f, 3.0 * f, 2.4 * f), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		ty += 3.0 * f
		for k in 4:
			var w: float = (2.2 - float(k) * 0.34) * f
			var h: float = 0.85 * f
			terrain.create_box(spot + Vector3(0.0, ty + h / 2.0, 0.0), Vector3(w, h, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.CYLINDER)
			ty += h
		# The waist that makes it a lotus rather than a cone — and now that the
		# tiers are round it is a SPHERE, which is what a lotus bud actually is.
		terrain.create_box(spot + Vector3(0.0, ty + 0.45 * f, 0.0), Vector3(1.5 * f, 0.9 * f, 1.5 * f), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.SPHERE)
		ty += 0.9 * f
		terrain.create_box(spot + Vector3(0.0, ty + 0.6 * f, 0.0), Vector3(0.5 * f, 1.2 * f, 0.5 * f), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.CONE)
		tallest = maxf(tallest, ty + 1.2 * f)

	return { "radius": 9.0, "top": tallest }

static func _landmark_machu_picchu(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 24 — MACHU PICCHU: four broad agricultural terraces stepping up a slope, a
	scatter of small roofless stone houses on the flat above them, and one sharp
	peak leaning over the lot.

	THE PEAK IS THE RISK, NOT THE FEATURE. Huayna Picchu is what a photograph of
	Machu Picchu is framed by, but a lone rock spike is EXACTLY what a mountain
	massif already looks like in this world — so the terraces have to carry the
	recognition on their own: four wide, shallow, evenly stepped slabs (a rough
	slope would read as scenery) with a town standing on top of them. The peak is
	built last and leans, so it is clearly a backdrop rather than the subject.

	The terrace risers are 1.1 m, so the stack is climbable — which is the right
	reading for a hillside somebody farmed.

	RADIUS ARITHMETIC (declared 9.0). A terrace is 10.0 x 2.0 and the front one is at
	z = 3.6: 3.6 + 0.5*sqrt(10.0^2 + 2.0^2) = 3.6 + 5.10 = 8.70. The peak's base box
	is 3.4 square at z = -5.0 with up to 1.2 of x jitter (offset 5.14) and a tilt of
	up to 0.14, which widens its half-diagonal to 2.57 => 7.71. So 8.70 <= 9.0.
	NO ACCENT.
	"""
	const TERRACES := 4
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	var top_y := 0.0
	for i in TERRACES:
		var h: float = 1.1 * float(i + 1)
		terrain.create_box(center + rot * Vector3(0.0, h / 2.0, 3.6 - float(i) * 1.8), Vector3(10.0, h, 2.0), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		top_y = h

	# The town: shells rather than four-walled rooms (four thin walls would be four
	# times the boxes for the same 30 m silhouette), each with a dark doorway.
	# Jittered in place and yaw — an Inca town on a ridge is not a grid.
	for i in 6:
		var hx := rng.randf_range(-3.8, 3.8)
		var hz := rng.randf_range(-3.4, -0.6)
		var hh := rng.randf_range(1.5, 2.1)
		var hyaw := yaw + rng.randf_range(-0.4, 0.4)
		terrain.create_box(center + rot * Vector3(hx, top_y + hh / 2.0, hz), Vector3(1.9, hh, 1.6), hyaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04))
		terrain.create_box(center + rot * Vector3(hx, top_y + 0.7, hz) + Basis(Vector3.UP, hyaw) * Vector3(0.0, 0.0, 0.85),
				Vector3(0.6, 1.2, 0.3), hyaw, rng, block_batch, block_body, 0.0, LM_STONE_GREY.darkened(0.75), false)

	# Huayna Picchu: three boxes each smaller than the last and each nudged the same
	# way, so the peak overhangs the town exactly as the real one does.
	var px := rng.randf_range(-1.2, 1.2)
	var py := top_y
	var top := top_y
	var lean := rng.randf_range(0.06, 0.14)
	var pw := 3.4
	for i in 3:
		var h: float = 3.4 - float(i) * 0.5
		var peak_dims := Vector3(pw, h, pw)
		terrain.create_box(center + rot * Vector3(px + float(i) * 0.5, py + h / 2.0, -5.0 + float(i) * 0.45),
				peak_dims, yaw + float(i) * 0.3, rng, block_batch, block_body, lean,
				_lm_shade(stone, rng, 0.05))
		top = maxf(top, rotated_box_top(py + h / 2.0, peak_dims, lean))
		py += h
		pw -= 0.9

	return { "radius": 9.0, "top": top }

static func _landmark_pont_du_gard(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 25 — PONT DU GARD: three tiers of arches — three big ones at the bottom,
	five above them, and a run of small ones carrying the water channel across the
	top. Arches getting smaller and more numerous as they rise IS the recognition
	cue, and it is why every tier is built as PIERS AND LINTELS rather than as a wall
	with holes: an arch you can see daylight through is the difference between an
	aqueduct and a viaduct-shaped block.

	THE SECOND TIER'S PIERS DELIBERATELY DO NOT SIT OVER THE FIRST'S. A shifted
	rhythm is what an aqueduct looks like; a stacked one is what a modern bridge
	looks like, and the Golden Gate already owns "bridge" in this registry.

	BUILT AS BAYS, NOT AS SPANS — the Great Wall's lesson. A single 14 m lintel has a
	half-diagonal of 7.0 before anything else is added to it.

	RADIUS ARITHMETIC (declared 8.8). The outermost second-tier pier is at x = 7.0
	with a half-diagonal of 0.5*sqrt(1.2^2 + 2.2^2) = 1.25 => 8.25. A bottom pier is
	at 6.3 with 0.5*sqrt(1.8^2 + 2.6^2) = 1.58 => 7.88; the top deck's outermost
	segment is at 5.6 + 1.71 = 7.31. So 8.25 <= 8.8.
	NO ACCENT.

	THE PIERS ARE CYLINDERS AND THE LINTELS ARE NOT (bead godot-test1-y1o.17).
	Every tier's uprights become round weathered stone — a tier-1 pier is 1.44 in
	plan, inside ChunkBatch.ROUND_COLLIDER_MAX_ASPECT, so the piers a player
	actually walks between collide as the CylinderShape3D they draw; the tier-2
	piers are 1.83 and keep their box. **That box is a real 0.37 m of invisible
	stone at their corners, and it is REACHABLE by an ability, not unreachable**:
	they stand at t2_y = 6.0, which is exactly where the tier-1 lintels top out,
	so there is a colliding ledge at their feet — it is over the 3.6125 m jump
	apex, so a walking hero cannot get there, but Windman's Air Rush can. It is
	accepted at that size rather than claimed to be free. The lintels and the
	channel deck stay CUBE: they are the flat courses
	laid ACROSS the piers, and a round one is a log. What is still missing is the
	ARCH itself — a semicircle of voussoirs is a ring of new boxes, i.e. a
	different draw count in this builder, so it is its own bead and not a kind.
	"""
	const T1_H := 5.0
	const T2_H := 4.2
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.05)

	# TIER 1 — four heavy piers carrying three big arches.
	for i in 4:
		terrain.create_box(center + rot * Vector3((float(i) - 1.5) * 4.2, T1_H / 2.0, 0.0), Vector3(1.8, T1_H, 2.6), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), true, ChunkBatch.BoxKind.CYLINDER)
	for i in 3:
		terrain.create_box(center + rot * Vector3((float(i) - 1.0) * 4.2, T1_H + 0.5, 0.0), Vector3(4.2, 1.0, 2.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# TIER 2 — six lighter piers over the same span, carrying five arches.
	var t2_y: float = T1_H + 1.0
	for i in 6:
		terrain.create_box(center + rot * Vector3((float(i) - 2.5) * 2.8, t2_y + T2_H / 2.0, 0.0), Vector3(1.2, T2_H, 2.2), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), true, ChunkBatch.BoxKind.CYLINDER)
	for i in 5:
		terrain.create_box(center + rot * Vector3((float(i) - 2.0) * 2.8, t2_y + T2_H + 0.45, 0.0), Vector3(2.8, 0.9, 2.0), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# TIER 3 — the channel, on a run of small arches. The deck collides (it is the
	# top of an aqueduct, and the one part of this shape a player could reach from a
	# hillside); the channel walls and the little piers are trim on its own volume.
	var t3_y: float = t2_y + T2_H + 0.9
	for i in 6:
		terrain.create_box(center + rot * Vector3((float(i) - 2.5) * 2.24, t3_y + 0.85, 0.0), Vector3(0.75, 1.7, 1.6), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.CYLINDER)
	for i in 5:
		var dx := (float(i) - 2.0) * 2.8
		terrain.create_box(center + rot * Vector3(dx, t3_y + 2.0, 0.0), Vector3(2.9, 0.6, 1.8), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		for side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(dx, t3_y + 2.65, side * 0.75), Vector3(2.9, 0.7, 0.35), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)

	return { "radius": 8.8, "top": t3_y + 3.0 }

static func _landmark_kinderdijk(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 26 — KINDERDIJK WINDMILLS: three brick mills standing on a dyke, each a
	tapering body under a dark thatched cap carrying a cross of sails. THREE of them
	rather than one is the point — a lone windmill is a farm, a ROW of them on a
	dyke is Kinderdijk — and the dyke is what stops the row reading as three
	separate buildings that happen to be near each other.

	THE SAIL CROSS IS A PLUS, NOT AN X, and that is a vocabulary limit stated
	honestly rather than a shape preference. create_box offers a yaw (about world Y)
	and a tilt about the box's own local X; neither can roll a box about the axis a
	mill's sails turn on, so a diagonal arm is not expressible at all. A vertical bar
	crossed by a horizontal one is an ordinary resting position for a real mill,
	costs two boxes instead of a dozen stepped ones, and reads as sails at 30 m —
	the torii's stepped kasagi, one building over. Upgrade path if it ever grates:
	four arms of 3-4 stepped boxes each, i.e. 12 boxes per mill and 36 per landmark.

	RADIUS ARITHMETIC (declared 8.2). The outer mill's horizontal sail is 4.6 long,
	centred at (5.2, 1.75): offset 5.49 plus a half-diagonal of
	0.5*sqrt(4.6^2 + 0.22^2) = 2.30 => 7.79. The dyke slab is 13.0 x 3.4 =>
	0.5*sqrt(13.0^2 + 3.4^2) = 6.72; a mill body is 3.0 square at x = 5.2 => 7.32.
	So 7.79 <= 8.2. MILL_STEP (5.2) also has to exceed the 4.6 sail span, or two
	neighbouring mills' sails interpenetrate — 0.6 m of daylight, deliberately.
	NO ACCENT.
	"""
	const MILLS := 3
	const MILL_STEP := 5.2
	const SAIL_SPAN := 4.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)

	terrain.create_box(center + rot * Vector3(0.0, 0.3, 0.0), Vector3(13.0, 0.6, 3.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.04))

	var tallest := 0.6
	for i in MILLS:
		var mx := (float(i) - float(MILLS - 1) / 2.0) * MILL_STEP
		var brick := _lm_shade(LM_OCHRE, rng, 0.05)
		var y := 0.6
		# The tapering body: three shrinking boxes, the octagonal brick tower in the
		# house's vocabulary.
		for k in 3:
			var w: float = 3.0 - float(k) * 0.42
			terrain.create_box(center + rot * Vector3(mx, y + 0.95, 0.0), Vector3(w, 1.9, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(brick, rng, 0.03), true, ChunkBatch.BoxKind.CYLINDER)
			y += 1.9
		# The cap: dark thatch, tapering to a cone point. Non-colliding so rule 5d
		# is respected (no colliding cone); the body cylinders below provide the
		# collision shape.
		terrain.create_box(center + rot * Vector3(mx, y + 0.8, 0.0), Vector3(2.4, 1.6, 2.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false, ChunkBatch.BoxKind.CONE)
		y += 1.6
		var hub_y: float = y - 0.9
		terrain.create_box(center + rot * Vector3(mx, hub_y, 1.35), Vector3(0.4, 0.4, 0.9), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(LM_BASALT, rng, 0.03), false)
		# The sails. Trim: a sail 7 m up is not a floor.
		var canvas := _lm_shade(LM_MARBLE, rng, 0.03)
		terrain.create_box(center + rot * Vector3(mx, hub_y, 1.75), Vector3(0.3, SAIL_SPAN, 0.22), yaw,
				rng, block_batch, block_body, 0.0, canvas, false)
		terrain.create_box(center + rot * Vector3(mx, hub_y, 1.75), Vector3(SAIL_SPAN, 0.3, 0.22), yaw,
				rng, block_batch, block_body, 0.0, canvas, false)
		tallest = maxf(tallest, hub_y + SAIL_SPAN / 2.0)

	return { "radius": 8.2, "top": tallest }

static func _landmark_pharos(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 27 — LIGHTHOUSE OF ALEXANDRIA: the Pharos, in the three stages every
	surviving description gives it — a wide square base, a narrower octagonal
	middle, a slim cylindrical top — standing on its island quay with a FIRE burning
	on the platform.

	THE STEPPING-DOWN-IN-THREES PROFILE IS THE RECOGNITION CUE, and the fire is what
	makes it a lighthouse rather than a chimney, which is why this is one of the very
	few builders that spends the one permitted accent. The Great Wall's beacon and
	Liberty's torch are the precedent: an accent goes where a real light belongs, and
	nowhere else.

	The octagon is two boxes crossed at 45 degrees — the same trick St Basil's centre
	shaft uses, and the closest a box vocabulary gets to eight sides.

	RADIUS ARITHMETIC (declared 6.6). The quay is the widest box, 8.4 square, so
	0.5*sqrt(2*8.4^2) = 5.94. The base stage is 5.4 square => 3.82, and the octagon
	is 3.4 square => 2.40. So 5.94 <= 6.6.
	THE one accent: the signal fire.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var stone := _lm_shade(LM_MARBLE, rng, 0.03)
	var trim := _lm_shade(LM_SANDSTONE, rng, 0.04)

	terrain.create_box(center + Vector3(0.0, 0.35, 0.0), Vector3(8.4, 0.7, 8.4), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04))
	var y := 0.7

	# STAGE 1 — the square base, battered (two boxes, the upper one narrower).
	for k in 2:
		var w: float = 5.4 - float(k) * 0.6
		terrain.create_box(center + Vector3(0.0, y + 1.8, 0.0), Vector3(w, 3.6, w), yaw, rng, block_batch, block_body,
				0.0, _lm_shade(stone, rng, 0.02))
		y += 3.6
	terrain.create_box(center + Vector3(0.0, y + 0.2, 0.0), Vector3(5.2, 0.4, 5.2), yaw, rng, block_batch, block_body,
			0.0, trim, false)
	y += 0.4

	# STAGE 2 — the octagon, which is now honestly a CYLINDER: the crossed pair
	# was the closest a box vocabulary got to a round stage, and it no longer has
	# to approximate.
	for k in 2:
		terrain.create_box(center + Vector3(0.0, y + 2.6, 0.0), Vector3(3.4, 5.2, 3.4), yaw + float(k) * PI / 4.0,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	y += 5.2
	terrain.create_box(center + Vector3(0.0, y + 0.2, 0.0), Vector3(3.6, 0.4, 3.6), yaw, rng, block_batch, block_body,
			0.0, trim, false)
	y += 0.4

	# STAGE 3 — the slim top and the lantern platform over it.
	terrain.create_box(center + Vector3(0.0, y + 1.7, 0.0), Vector3(2.2, 3.4, 2.2), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	y += 3.4
	terrain.create_box(center + Vector3(0.0, y + 0.25, 0.0), Vector3(3.0, 0.5, 3.0), yaw, rng, block_batch, block_body,
			0.0, trim)
	y += 0.5
	# Four corner posts round the fire, so the flame reads as held rather than as
	# floating over a slab.
	for i in 4:
		var a := yaw + PI / 4.0 + TAU * float(i) / 4.0
		terrain.create_box(center + Vector3(cos(a) * 1.15, y + 0.7, sin(a) * 1.15), Vector3(0.3, 1.4, 0.3), yaw,
				rng, block_batch, block_body, 0.0, trim, false, ChunkBatch.BoxKind.CYLINDER)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 0.8, 0.0), Vector3(1.1, 1.2, 1.1),
			yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 6.6, "top": y + 1.6 }

# ----------------------------------------------------------------------------
# WAVE 4 — THE GERMAN PACK
# ----------------------------------------------------------------------------
##
## Ten places from one country, and the one risk that carries which no earlier
## wave had: ten entries from one national pool is also ten chances to build the
## same church twice. So every builder below is checked against the other nine on
## SILHOUETTE FIRST — a domed parliament, a sphere on a needle, a black Roman
## gate, two fat leaning brick towers, a stone bell, a glass wave on a warehouse,
## a cross on a summit, a keep beside a timbered hall, ONE colossal steeple, and
## four animals standing on each other. Where two came close it is said out loud
## in the builder's own docstring (Ulm vs Cologne, Wartburg vs Neuschwanstein)
## rather than left for the next reader to discover at 30 m.
##
## FOUR SHARED SHAPE IDIOMS get reused here rather than reinvented, which is the
## other half of keeping ten German boxes distinguishable — the differences that
## remain are then real differences and not accidents of how each was built:
##   - THE OCTAGON: two boxes crossed at PI/4, from St Basil's centre shaft and
##     the Pharos' middle stage. Every round tower here is one (Fernsehturm base,
##     Porta Nigra's east tower, the Holstentor's drums, Ulm's octagon stage).
##   - THE BULGE STACK: a stack whose MIDDLE box is the widest, from _lm_onion.
##     The Frauenkirche's stone bell and the Fernsehturm's sphere are both this,
##     at very different proportions.
##   - THE LEANING AXIS: centres placed along a tilted line rather than boxes
##     each given a tilt, from Pisa — used by the Holstentor's sinking towers,
##     including Pisa's sign gotcha, which is recorded there and holds here.
##   - THE SHRINKING SPIRE: from Cologne and Neuschwanstein, used by Ulm.

static func _landmark_reichstag(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 28 — REICHSTAG BUILDING: a broad classical block with a corner tower at
	each of its four corners, a six-column portico under a pediment on the front,
	and Foster's GLASS DOME sitting in the middle of the roof.

	THE DOME IS THE WHOLE ENTRY, and it is why this is not simply "a parliament".
	A wide stone block with corner towers is every 19th-century government building
	in Europe; a wide stone block with corner towers and a transparent blue-white
	drum on top is the Reichstag and nothing else. So the dome gets the pale glass
	(LM_SLATE_BLUE lightened — the wave-4 palette note) and everything under it
	stays quiet sandstone, which is also the real contrast: the 1894 stone was
	deliberately left scarred and the 1999 dome deliberately made to read as new.

	RADIUS ARITHMETIC (declared 8.4). The widest reach is a CORNER TOWER CAP:
	centre at sqrt(5.4^2 + 3.4^2) = 6.38 with half-diagonal 0.5*sqrt(2 * 2.6^2) =
	1.84, so 8.22 <= 8.4. The cornice slab is 0.5*sqrt(13.8^2 + 9.0^2) = 8.24, the
	pediment is 4.6 + 0.5*sqrt(7.0^2 + 1.2^2) = 4.6 + 3.55 = 8.15, and the plinth
	is 0.5*sqrt(13.6^2 + 9.2^2) = 8.21. Four boxes within 0.2 m of the declared
	radius is deliberate: this shape is a rectangle, and a rectangle spends its
	budget on the corners it actually has.
	NO ACCENT: the dome is daylit by a mirrored cone, which is exactly the detail
	an emissive box cannot say.
	"""
	const BLOCK := Vector3(13.0, 5.6, 8.6)
	const TOWER_X := 5.4
	const TOWER_Z := 3.4
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.03)
	var glass := _lm_shade(LM_SLATE_BLUE, rng, 0.03).lightened(0.32)

	terrain.create_box(center + Vector3(0.0, 0.35, 0.0), Vector3(13.6, 0.7, 9.2), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04))
	var y := 0.7
	terrain.create_box(center + Vector3(0.0, y + BLOCK.y / 2.0, 0.0), BLOCK, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02))
	# Pilaster strips down the long flanks — the rhythm that says "classical" in
	# eight boxes. Trim: they sit on the block's own collision volume.
	for px in [-4.8, -2.4, 0.0, 2.4, 4.8]:
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(px, y + BLOCK.y / 2.0, z_side * (BLOCK.z / 2.0 + 0.12)),
					Vector3(0.7, BLOCK.y - 0.8, 0.24), yaw, rng, block_batch, block_body,
					0.0, _lm_shade(stone, rng, 0.03).darkened(0.1), false)
	y += BLOCK.y
	terrain.create_box(center + Vector3(0.0, y + 0.25, 0.0), Vector3(13.8, 0.5, 9.0), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02), false)

	# THE PORTICO — six columns standing proud of the front face, under a pediment.
	# The columns collide, so walking into the front of the building is walking into
	# a colonnade rather than into a flat wall.
	for cx in [-3.0, -1.8, -0.6, 0.6, 1.8, 3.0]:
		terrain.create_box(center + rot * Vector3(cx, 0.7 + 2.6, -(BLOCK.z / 2.0 + 0.3)), Vector3(0.9, 5.2, 0.9),
				yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(center + rot * Vector3(0.0, y + 0.9, -(BLOCK.z / 2.0 + 0.3)), Vector3(7.0, 1.4, 1.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)
	# The dark recess behind the columns, so the portico reads as a porch.
	terrain.create_box(center + rot * Vector3(0.0, 0.7 + 2.2, -(BLOCK.z / 2.0 - 0.1)), Vector3(6.4, 4.4, 0.4), yaw,
			rng, block_batch, block_body, 0.0, LM_SANDSTONE.darkened(0.62), false)

	# The four corner towers.
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var spot := center + rot * Vector3(x_side * TOWER_X, 0.0, z_side * TOWER_Z)
			terrain.create_box(spot + Vector3(0.0, y + 1.7, 0.0), Vector3(2.2, 3.4, 2.2), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
			terrain.create_box(spot + Vector3(0.0, y + 3.65, 0.0), Vector3(2.6, 0.5, 2.6), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03).darkened(0.14), false)

	# THE GLASS DOME on its stone drum. Four shrinking glass boxes and a lantern —
	# the same shrinking stack as every cone in this file, but the colour is what
	# stops it reading as one, and the SLIGHT re-yaw per tier is what stops it
	# reading as a pyramid.
	terrain.create_box(center + Vector3(0.0, y + 0.6, 0.0), Vector3(5.6, 1.2, 5.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	var dy := y + 1.2
	# Foster's dome really IS a stepped glass drum, so the four tiers are
	# CYLINDERS rather than a sphere — and the lantern on top is the sphere.
	for i in 4:
		var w: float = 5.0 - float(i) * 0.95
		terrain.create_box(center + Vector3(0.0, dy + 0.55, 0.0), Vector3(w, 1.1, w), yaw + float(i) * PI / 8.0,
				rng, block_batch, block_body, 0.0, _lm_shade(glass, rng, 0.02), false, ChunkBatch.BoxKind.CYLINDER)
		dy += 1.1
	terrain.create_box(center + Vector3(0.0, dy + 0.4, 0.0), Vector3(0.8, 0.8, 0.8), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(glass, rng, 0.02), false, ChunkBatch.BoxKind.SPHERE)

	return { "radius": 8.4, "top": dy + 0.8 }

static func _landmark_fernsehturm(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 29 — BERLIN TV TOWER (Fernsehturm): a low octagonal pavilion, a needle
	shaft rising out of it, a SPHERE threaded onto the shaft two-thirds of the way
	up, and an antenna above that. The sphere-on-a-needle is unmistakable and is
	shared with no other entry in the registry.

	THE SPHERE IS A BULGE STACK — five boxes whose MIDDLE one is widest, the
	_lm_onion trick at different proportions (an onion is a teardrop, this is
	symmetric top-to-bottom, which is the whole difference between a dome and a
	ball). Building it as a shrinking stack would give a diamond, and a diamond on
	a stick is a spire.

	THE ANTENNA IS THE TALL PART, deliberately: this is the tallest structure in
	Germany and the fact says so, so the silhouette has to earn that claim rather
	than stop at the sphere the postcards crop to.

	RADIUS ARITHMETIC (declared 6.4, honestly 5.37). The widest box is the pavilion
	octagon, 7.6 square, so 0.5*sqrt(2 * 7.6^2) = 5.37. The sphere's widest boxes
	are 4.8 square => 3.39, and the shaft is 2.6 square => 1.84. The declared 6.4 is
	loose for Big Ben's reason — a 26 m needle whose stone is 5 m wide would
	otherwise announce itself from 11 m away, i.e. from directly underneath.
	THE one accent: the aviation warning light at the antenna tip, which is a real
	light in the only place a real light is on this structure.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var pale := _lm_shade(LM_MARBLE, rng, 0.02)
	var steel := _lm_shade(LM_STONE_GREY, rng, 0.03)

	# The pavilion at the foot — an octagon, so the tower stands on something with
	# a plan rather than sprouting out of the grass.
	for k in 2:
		terrain.create_box(center + Vector3(0.0, 0.8, 0.0), Vector3(7.6, 1.6, 7.6), yaw + float(k) * PI / 4.0,
				rng, block_batch, block_body, 0.0, _lm_shade(pale, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	var y := 1.6

	# THE SHAFT, in two tapering stages so it reads as a needle rather than a post.
	const SHAFT_TOP := 17.4
	terrain.create_box(center + Vector3(0.0, y + 4.0, 0.0), Vector3(2.6, 8.0, 2.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(pale, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(center + Vector3(0.0, 9.6 + (SHAFT_TOP - 9.6) / 2.0, 0.0), Vector3(2.1, SHAFT_TOP - 9.6, 2.1),
			yaw, rng, block_batch, block_body, 0.0, _lm_shade(pale, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)

	# THE SPHERE, threaded onto the shaft at 11 m. All trim — it hangs in the air on
	# the shaft's own collision volume and there is nothing there to stand on.
	const SPHERE_W: Array = [3.0, 4.2, 4.8, 4.2, 3.0]
	const SPHERE_H := 0.94
	var sy := 11.0 - SPHERE_H * float(SPHERE_W.size()) / 2.0
	for i in SPHERE_W.size():
		var w: float = SPHERE_W[i]
		# The band at the sphere's equator is the observation deck, and the two
		# above it are the revolving restaurant's glazing — darker, so the ball has
		# a horizon line instead of reading as one smooth lump.
		var tint: Color = steel if i == 2 else pale
		terrain.create_box(center + Vector3(0.0, sy + SPHERE_H / 2.0, 0.0), Vector3(w, SPHERE_H, w),
				yaw + float(i) * PI / 10.0, rng, block_batch, block_body, 0.0, _lm_shade(tint, rng, 0.02), false,
				ChunkBatch.BoxKind.SPHERE)
		sy += SPHERE_H

	# THE ANTENNA — four thinning segments, red and white banded the way every tall
	# mast in Europe is, then the light.
	y = SHAFT_TOP
	for i in 4:
		var w: float = 1.3 - float(i) * 0.22
		var h := 2.2
		var band: Color = _lm_shade(LM_VERMILION, rng, 0.03) if i % 2 == 1 else _lm_shade(pale, rng, 0.02)
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw,
				rng, block_batch, block_body, 0.0, band, false, ChunkBatch.BoxKind.CONE if i == 3 else ChunkBatch.BoxKind.CYLINDER)
		y += h
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 0.4, 0.0), Vector3(0.5, 0.6, 0.5),
			yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 6.4, "top": y + 0.8 }

static func _landmark_porta_nigra(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 30 — PORTA NIGRA: a long soot-black Roman gate — two ground-level
	passages between three piers, two storeys of blind arcading above them, and one
	end tower carried a storey higher than the other. It is the LOPSIDEDNESS that
	makes it this gate and not a generic wall: the real Porta Nigra's east tower
	was finished and its west tower never was.

	THE TWO PASSAGES ARE REAL — the piers collide and the gaps between them do not,
	so a player walks through the gate exactly as the Brandenburg Gate's colonnade
	lets them walk through it. That is the same decision, made for the same reason:
	a gate you cannot pass is a wall.

	Its stone is LM_STONE_GREY darkened rather than the Moai's LM_BASALT — the
	registry banner's reason: a third near-black entry would start costing the two
	that already earned it. Trier's blocks went black from 1,800 years of weather,
	not from being volcanic, and a very dark grey is honestly what that looks like.

	RADIUS ARITHMETIC (declared 8.2). The widest reach is an OUTER PIER: centre at
	5.0 with half-diagonal 0.5*sqrt(2.0^2 + 5.0^2) = 2.69, so 7.69 <= 8.2. The east
	tower is 5.4 + 0.5*sqrt(2 * 3.2^2) = 5.4 + 2.26 = 7.66, the plinth is
	0.5*sqrt(12.6^2 + 5.6^2) = 6.89, and a storey band is 0.5*sqrt(12.0^2 + 5.0^2)
	= 6.50.
	NO ACCENT.
	"""
	const PIER := Vector3(2.0, 4.6, 5.0)
	const PIER_X: Array = [-5.0, 0.0, 5.0]
	const STOREY := 3.2
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var soot := _lm_shade(LM_STONE_GREY, rng, 0.03).darkened(0.46)

	terrain.create_box(center + Vector3(0.0, 0.3, 0.0), Vector3(12.6, 0.6, 5.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04).darkened(0.3))
	var y := 0.6

	# GROUND STOREY — three piers, two passages.
	for px_variant: Variant in PIER_X:
		var px: float = px_variant
		terrain.create_box(center + rot * Vector3(px, y + PIER.y / 2.0, 0.0), PIER, yaw, rng, block_batch, block_body,
				0.0, _lm_shade(soot, rng, 0.02))
	y += PIER.y
	terrain.create_box(center + Vector3(0.0, y + 0.4, 0.0), Vector3(12.0, 0.8, 5.0), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(soot, rng, 0.02))
	y += 0.8

	# THE TWO ARCADED STOREYS. Each is a solid band with a row of colonnettes stood
	# against the front and back faces — trim on the band's own volume, and the only
	# thing on this shape that says "Roman arcade" rather than "long wall".
	for storey in 2:
		terrain.create_box(center + Vector3(0.0, y + STOREY / 2.0, 0.0), Vector3(11.6, STOREY, 4.6), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(soot, rng, 0.02))
		for cx in [-4.8, -3.2, -1.6, 0.0, 1.6, 3.2, 4.8]:
			for z_side in [-1.0, 1.0]:
				terrain.create_box(center + rot * Vector3(cx, y + STOREY / 2.0, z_side * 2.36), Vector3(0.55, STOREY - 0.7, 0.4),
						yaw, rng, block_batch, block_body, 0.0, _lm_shade(soot, rng, 0.03).darkened(0.12), false, ChunkBatch.BoxKind.CYLINDER)
		y += STOREY
		terrain.create_box(center + Vector3(0.0, y + 0.35, 0.0), Vector3(12.0, 0.7, 5.0), yaw, rng, block_batch, block_body,
				0.0, _lm_shade(soot, rng, 0.02))
		y += 0.7

	# THE EAST TOWER, one storey higher and rounded — an octagon, the house idiom.
	# The west end gets a low unfinished stub instead, which is the lopsidedness.
	var east := center + rot * Vector3(5.4, 0.0, 0.0)
	for k in 2:
		terrain.create_box(east + Vector3(0.0, 0.6 + (y - 0.6) / 2.0 + 1.7, 0.0), Vector3(3.2, y - 0.6 + 3.4, 3.2),
				yaw + float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, _lm_shade(soot, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(east + Vector3(0.0, y + 3.6, 0.0), Vector3(3.6, 0.5, 3.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(soot, rng, 0.03).darkened(0.14), false)
	terrain.create_box(center + rot * Vector3(-5.4, 0.6 + (y - 0.6) / 2.0, 0.0), Vector3(3.0, y - 0.6, 3.0), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(soot, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)

	return { "radius": 8.2, "top": y + 3.9 }

static func _landmark_holstentor(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 31 — HOLSTEN GATE (Holstentor): two FAT round brick towers under conical
	roofs with a lower gabled block wedged between them, the whole thing LEANING
	inward and forward the way the real gate has sunk into Lübeck's marsh since
	1478.

	FAT IS THE RECOGNITION CUE and the reason the drums are 4.2 m across on an 8 m
	tower. Every other tower in this registry is slender (Big Ben, the Fernsehturm,
	Ulm, Cologne); the Holstentor's are almost as wide as they are tall, which is
	what makes a two-tower gate read as THIS two-tower gate.

	THE LEAN USES PISA'S LEANING AXIS, not a per-box tilt: each tower is four
	octagonal drums whose CENTRES walk outward along a line leaning LEAN (0.045 rad)
	away from the gate, and Pisa's sign gotcha holds unchanged — create_box composes
	Basis(UP, yaw) * Basis(RIGHT, tilt), so the tilt handed to each drum has to
	agree with the direction its centre was offset in or the drums scissor apart.
	Here the lean bearing is fixed (straight out along local X, away from the
	centre), so the yaw that maps local +Z onto that bearing is yaw + side*PI/2 —
	worked out in full at the line itself, because on an OCTAGONAL drum the wrong
	sign is invisible in plan and shows up only as a scissored tower.

	RADIUS ARITHMETIC (declared 7.8). The widest reach is a tower's ROOF CONE at the
	top of the lean: the tower centre is 3.8 out, the lean has added
	8.0 * sin(0.045) = 0.36, and the widest cone box is 4.6 square with half-diagonal
	0.5*sqrt(2 * 4.6^2) = 3.25 — so 3.8 + 0.36 + 3.25 = 7.41 <= 7.8. The topmost
	drum is 4.16 + 2.97 = 7.13 and the plinth is 0.5*sqrt(11.6^2 + 5.6^2) = 6.44.
	NO ACCENT.
	"""
	const LEAN := 0.045
	const TOWER_X := 3.8
	const DRUMS := 4
	const DRUM_H := 2.0
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var brick := _lm_shade(LM_VERMILION, rng, 0.03).darkened(0.44)
	var roof := _lm_shade(LM_ROOF, rng, 0.04)

	terrain.create_box(center + Vector3(0.0, 0.3, 0.0), Vector3(11.6, 0.6, 5.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04))

	var tower_top := 0.0
	for side in [-1.0, 1.0]:
		var lean_dir := rot * Vector3(side, 0.0, 0.0)
		var foot := center + rot * Vector3(side * TOWER_X, 0.0, 0.0) + Vector3(0.0, 0.6, 0.0)
		# THE SIGN, derived rather than guessed, because Pisa's gotcha bites here in a
		# form Pisa's own wording does not cover: the drums are OCTAGONS (two boxes
		# crossed at PI/4) and the roof cones are squares, so a drum_yaw that is 180
		# degrees wrong looks IDENTICAL in plan — only the tilt direction flips, and
		# the tower then scissors inward against a centreline walking outward. There
		# is nothing to see in a footprint measurement and nothing for the self-check
		# to catch; it is visible only as a seam on the model.
		#
		# create_box composes Basis(UP, drum_yaw) * Basis(RIGHT, tilt), and
		# Basis(RIGHT, +t) tips local +Y toward local +Z — so a POSITIVE tilt leans
		# the drum's top toward wherever local +Z points, and the requirement is
		# exactly Basis(UP, drum_yaw) * +Z == lean_dir. With
		# lean_dir = Basis(UP, yaw) * (side, 0, 0) = side * (cos yaw, 0, -sin yaw),
		# and Basis(UP, d) * +Z = (sin d, 0, cos d), that needs
		# sin d = side * cos yaw and cos d = -side * sin yaw, i.e. d = yaw + side*PI/2.
		# The MINUS form is the trap: it satisfies both equations up to sign, points
		# local +Z at -lean_dir, and leans every drum the wrong way. MEASURED both
		# ways with a throwaway harness that compares each drum's top face centre
		# against the next drum's bottom face centre: 0.0000 m at every one of the
		# six joints as written, and 0.1799 m — an open wedge you can see through —
		# with the sign flipped back.
		var drum_yaw: float = yaw + side * PI / 2.0
		var s := 0.0
		for i in DRUMS:
			var mid := s + DRUM_H / 2.0
			var pos := foot + lean_dir * (mid * sin(LEAN)) + Vector3(0.0, mid * cos(LEAN), 0.0)
			for k in 2:
				terrain.create_box(pos, Vector3(4.2, DRUM_H, 4.2), drum_yaw + float(k) * PI / 4.0,
						rng, block_batch, block_body, LEAN, _lm_shade(brick, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
			s += DRUM_H
		# The dark arrow-slit band round each drum stack, and the conical roof over
		# it. Both trim: they sit on the drums' own collision volume.
		var slit := foot + lean_dir * (4.6 * sin(LEAN)) + Vector3(0.0, 4.6 * cos(LEAN), 0.0)
		terrain.create_box(slit, Vector3(4.4, 0.5, 4.4), drum_yaw, rng, block_batch, block_body, LEAN,
				_lm_shade(brick, rng, 0.03).darkened(0.3), false, ChunkBatch.BoxKind.CYLINDER)
		var cy := s
		for i in 3:
			var w: float = 4.6 - float(i) * 1.4
			var mid := cy + 0.85
			var pos := foot + lean_dir * (mid * sin(LEAN)) + Vector3(0.0, mid * cos(LEAN), 0.0)
			var roof_dims := Vector3(w, 1.7, w)
			terrain.create_box(pos, roof_dims, drum_yaw, rng, block_batch, block_body, LEAN,
					_lm_shade(roof, rng, 0.03), false, ChunkBatch.BoxKind.CONE if i == 2 else ChunkBatch.BoxKind.CYLINDER)
			tower_top = maxf(tower_top, rotated_box_top(0.6 + mid * cos(LEAN), roof_dims, LEAN))
			cy += 1.7

	# THE CENTRE BLOCK between the towers, lower, with the stepped gable that fills
	# the gap above the archway.
	terrain.create_box(center + Vector3(0.0, 0.6 + 3.2, 0.0), Vector3(4.4, 6.4, 4.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(brick, rng, 0.02))
	# The archway — a deep dark recess rather than a hole, because a real opening
	# would need the block split in two and this one is only 4.4 m wide.
	for z_side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(0.0, 0.6 + 1.9, z_side * 2.15), Vector3(2.4, 3.8, 0.5), yaw,
				rng, block_batch, block_body, 0.0, LM_VERMILION.darkened(0.8), false)
	var gy := 0.6 + 6.4
	for i in 3:
		var w: float = 4.0 - float(i) * 1.1
		terrain.create_box(center + Vector3(0.0, gy + 0.55, 0.0), Vector3(w, 1.1, 4.2), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(brick, rng, 0.03), false)
		gy += 1.1

	return { "radius": 7.8, "top": maxf(tower_top, gy) }

static func _landmark_frauenkirche(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 32 — DRESDEN FRAUENKIRCHE: a near-square sandstone body with a corner
	turret at each of its four corners, carrying the STEINERNE GLOCKE — the stone
	bell — with a lantern and a cross on top.

	THE BELL IS A BULGE STACK, and getting the bulge right is the entire entry.
	The Frauenkirche's dome is famous for being STONE where every other Baroque
	dome of its size is timber and lead, and the way that reads is that it swells
	OUTWARD above its base before it turns in — a bell, not a cone. So the widest
	box in the stack is the SECOND one, exactly as _lm_onion does it, and the six
	tiers then close in. Build it as a shrinking stack and it becomes Chichén Itzá
	with a spike on top.

	The stone is LM_SANDSTONE darkened: Dresden's Elbe sandstone blackens with age,
	and the rebuilt church is famously PIEBALD — the 43% of blocks salvaged from
	the 1945 rubble went back black while the new stone went back pale. That is
	what the per-box _lm_shade jitter is doing here at a deliberately wide 0.06
	rather than the usual 0.02-0.03: on this one building the patchwork is the point.

	RADIUS ARITHMETIC (declared 7.2). The widest box is the PLINTH, 9.2 square, so
	0.5*sqrt(2 * 9.2^2) = 6.51 <= 7.2. The body is 8.0 square => 5.66, the bell's
	widest tier is 6.9 square => 4.88, and a corner turret is sqrt(2 * 3.4^2) = 4.81
	+ 0.5*sqrt(2 * 1.3^2) = 0.92 => 5.73.
	NO ACCENT.
	"""
	const BODY := 8.0
	const TURRET_XZ := 3.4
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.03).darkened(0.16)

	terrain.create_box(center + Vector3(0.0, 0.4, 0.0), Vector3(9.2, 0.8, 9.2), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04))
	var y := 0.8

	# The body, plus a 45-degree crossed box so the corners read as chamfered — the
	# real plan is a square with its corners cut, which is what the four turrets
	# stand on.
	terrain.create_box(center + Vector3(0.0, y + 3.2, 0.0), Vector3(BODY, 6.4, BODY), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.06))
	terrain.create_box(center + Vector3(0.0, y + 3.2, 0.0), Vector3(7.4, 6.4, 7.4), yaw + PI / 4.0,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.06))
	y += 6.4
	terrain.create_box(center + Vector3(0.0, y + 0.3, 0.0), Vector3(8.6, 0.6, 8.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.04), false)
	y += 0.6

	# The four corner turrets — the stair towers, and the only vertical accents on
	# a building that is otherwise all curve.
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var spot := center + rot * Vector3(x_side * TURRET_XZ, 0.0, z_side * TURRET_XZ)
			terrain.create_box(spot + Vector3(0.0, 0.8 + 4.1, 0.0), Vector3(1.3, 8.2, 1.3), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.05), true, ChunkBatch.BoxKind.CYLINDER)
			terrain.create_box(spot + Vector3(0.0, 0.8 + 8.6, 0.0), Vector3(1.0, 0.8, 1.0), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04), false, ChunkBatch.BoxKind.SPHERE)

	# THE STONE BELL. Widest tier SECOND — see the docstring.
	const BELL_W: Array = [6.6, 6.9, 6.4, 5.4, 4.0, 2.6]
	const BELL_H: Array = [1.0, 1.1, 1.1, 1.1, 1.0, 0.9]
	# EVERY TIER A CYLINDER, including the bulging one: the bell is a surface of
	# revolution and the widths already carry the swell, so a stack of drums cut
	# to those widths IS the curve. Spheres here would bead it.
	for i in BELL_W.size():
		var w: float = BELL_W[i]
		var h: float = BELL_H[i]
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw + float(i) * PI / 12.0,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.06), false, ChunkBatch.BoxKind.CYLINDER)
		y += h

	# The lantern, its little cupola, and the golden cross that went back up in 2004
	# — made in London by the son of one of the bomber crews, which is the kind of
	# thing a one-line fact has no room for and a shape can at least gesture at.
	terrain.create_box(center + Vector3(0.0, y + 0.9, 0.0), Vector3(2.0, 1.8, 2.0), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.04), false, ChunkBatch.BoxKind.CYLINDER)
	y += 1.8
	for i in 2:
		var w: float = 1.7 - float(i) * 0.6
		terrain.create_box(center + Vector3(0.0, y + 0.4, 0.0), Vector3(w, 0.8, w), yaw, rng, block_batch, block_body,
				0.0, _lm_shade(stone, rng, 0.04), false, ChunkBatch.BoxKind.CONE if i == 1 else ChunkBatch.BoxKind.CYLINDER)
		y += 0.8
	var gold := _lm_shade(LM_SANDSTONE, rng, 0.02)
	terrain.create_box(center + Vector3(0.0, y + 0.9, 0.0), Vector3(0.22, 1.8, 0.22), yaw, rng, block_batch, block_body,
			0.0, gold, false)
	terrain.create_box(center + Vector3(0.0, y + 1.2, 0.0), Vector3(0.9, 0.22, 0.2), yaw, rng, block_batch, block_body,
			0.0, gold, false)

	return { "radius": 7.2, "top": y + 1.8 }

static func _landmark_elbphilharmonie(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 33 — ELBPHILHARMONIE: a plain brick harbour warehouse with a GLASS BODY
	set on top of it, roofed by a run of peaks and troughs — the wave.

	THE JOINT IS THE LANDMARK. Neither half is remarkable alone: a brick box is
	every warehouse on the Elbe, and a glass box is every office built since 1990.
	What people photograph is the SEAM — the moment where the 1963 Kaispeicher A
	stops dead and something transparent starts. So the two halves are built as two
	deliberately unblended volumes, the brick pilaster strips stop exactly at the
	seam, and the wave sits inset from the glass below it so the profile steps.

	THE WAVE IS AN EXPLICIT HEIGHT TABLE, not a sine. Eight segments at heights
	that rise and fall unevenly, because the real roof is not periodic — it peaks
	high at one end, dips, peaks higher in the middle and tapers off. A sine would
	read as corrugation, which is the one thing this roof must not look like.

	RADIUS ARITHMETIC (declared 7.4). The widest box is the QUAY, 11.6 x 7.4, so
	0.5*sqrt(11.6^2 + 7.4^2) = 6.88 <= 7.4. The warehouse is 0.5*sqrt(10.8^2 +
	6.6^2) = 6.33, the glass body is 0.5*sqrt(10.4^2 + 6.2^2) = 6.05, and the
	outermost wave segment is 4.2 + 0.5*sqrt(1.4^2 + 5.6^2) = 4.2 + 2.89 = 7.09.
	NO ACCENT: the building is lit from inside by 2,100 windows, and one emissive
	box would say "bonfire on a roof".
	"""
	const WAREHOUSE := Vector3(10.8, 6.2, 6.6)
	const GLASS_BODY := Vector3(10.4, 4.4, 6.2)
	## The wave. Eight segment tops, deliberately not periodic — see the docstring.
	const WAVE_H: Array = [1.7, 0.8, 2.3, 1.1, 2.7, 1.4, 2.0, 0.9]
	const WAVE_W := 1.4
	const WAVE_D := 5.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var brick := _lm_shade(LM_VERMILION, rng, 0.03).darkened(0.52)
	var glass := _lm_shade(LM_SLATE_BLUE, rng, 0.03).lightened(0.3)

	terrain.create_box(center + Vector3(0.0, 0.25, 0.0), Vector3(11.6, 0.5, 7.4), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04).darkened(0.2))
	var y := 0.5

	# THE WAREHOUSE, and the pilaster strips that stop at the seam.
	terrain.create_box(center + Vector3(0.0, y + WAREHOUSE.y / 2.0, 0.0), WAREHOUSE, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(brick, rng, 0.02))
	for px in [-4.2, -2.8, -1.4, 0.0, 1.4, 2.8, 4.2]:
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(px, y + WAREHOUSE.y / 2.0, z_side * (WAREHOUSE.z / 2.0 + 0.1)),
					Vector3(0.6, WAREHOUSE.y - 0.6, 0.2), yaw, rng, block_batch, block_body,
					0.0, _lm_shade(brick, rng, 0.03).darkened(0.16), false)
	y += WAREHOUSE.y

	# THE SEAM — a thin dark band, which is the plaza deck between the two halves.
	terrain.create_box(center + Vector3(0.0, y + 0.2, 0.0), Vector3(11.2, 0.4, 7.0), yaw, rng, block_batch, block_body,
			0.0, LM_SLATE_BLUE.darkened(0.55), false)
	y += 0.4

	# THE GLASS BODY.
	terrain.create_box(center + Vector3(0.0, y + GLASS_BODY.y / 2.0, 0.0), GLASS_BODY, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(glass, rng, 0.02))
	y += GLASS_BODY.y

	# THE WAVE. Each segment is a slab plus a narrower cap, so a peak comes to a
	# ridge rather than to a flat top. All trim, 11 m up on the glass body's volume.
	var top := y
	for i in WAVE_H.size():
		var h: float = WAVE_H[i]
		var x: float = (float(i) - 3.5) * 1.2
		terrain.create_box(center + rot * Vector3(x, y + h / 2.0, 0.0), Vector3(WAVE_W, h, WAVE_D), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(glass, rng, 0.03), false)
		terrain.create_box(center + rot * Vector3(x, y + h + 0.25, 0.0), Vector3(WAVE_W * 0.6, 0.5, WAVE_D * 0.8), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(glass, rng, 0.03).darkened(0.1), false)
		top = maxf(top, y + h + 0.5)

	return { "radius": 7.4, "top": top }

static func _landmark_zugspitze(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 34 — ZUGSPITZE SUMMIT CROSS: a rock summit of five tapering tiers with
	snow on the top two and the GILDED CROSS standing on the highest stone.

	THE ONLY ENTRY IN THE REGISTRY THAT IS A PIECE OF LANDSCAPE, and the scale is
	honest about that: at 12 m it is a crag, not a 2,962 m mountain. What makes it
	read is the CROSS, which is why the cross is exaggerated — 3.4 m of it on a
	9 m crag, where the real one is 4.9 m on a mountain. Shrink it to scale and
	this becomes an anonymous rock, which the mountain biome already builds by the
	dozen.

	IT DELIBERATELY BORROWS THE MOUNTAIN BIOME'S OWN RULES — tapering layers, a
	per-layer yaw, a small lateral jitter so it does not read as a wedding cake, and
	snow forced onto the top layers — because a player who has walked past a hundred
	massifs should recognise the family and then notice the one thing that is
	different. That is the joke, and it only works if the family resemblance is real.

	RADIUS ARITHMETIC (declared 6.0). The widest box is the BASE TIER, 7.4 square,
	with the lateral jitter at its worst: 0.5*sqrt(2 * 7.4^2) + JITTER (0.25) =
	5.23 + 0.25 = 5.48 <= 6.0. A foot boulder is at most 4.3 out with half-diagonal
	0.5*sqrt(2 * 1.4^2) = 0.99 => 5.29, and the cross arms are 0.5*sqrt(2.0^2 +
	0.26^2) = 1.01 at the axis.
	NO ACCENT: the cross is gilded, not lit — the same call St Basil's domes make.
	"""
	const TIER_W: Array = [7.4, 6.0, 4.7, 3.4, 2.0]
	const TIER_H: Array = [2.2, 2.0, 1.8, 1.6, 1.4]
	const JITTER := 0.25
	const SNOW_FROM := 3  # the top two tiers, the same "above the snow line" rule
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var rock := _lm_shade(LM_GRANITE, rng, 0.05)
	var snow := _lm_shade(LM_MARBLE, rng, 0.02)

	var y := 0.0
	for i in TIER_W.size():
		var w: float = TIER_W[i]
		var h: float = TIER_H[i]
		var jx := rng.randf_range(-JITTER, JITTER)
		var jz := rng.randf_range(-JITTER, JITTER)
		var tint: Color = snow if i >= SNOW_FROM else rock
		terrain.create_box(center + rot * Vector3(jx, y + h / 2.0, jz), Vector3(w, h, w),
				yaw + rng.randf_range(-0.5, 0.5), rng, block_batch, block_body, 0.0, _lm_shade(tint, rng, 0.04))
		y += h

	# Scree at the foot — the loose boulders that say "this broke off the thing
	# above it" rather than "this was placed here".
	var boulders := rng.randi_range(4, 6)
	for i in boulders:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(3.1, 4.3)
		var w := rng.randf_range(0.7, 1.4)
		terrain.create_box(center + Vector3(cos(a) * r, w / 2.0, sin(a) * r), Vector3(w, w, w),
				rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.05), true, ChunkBatch.BoxKind.SPHERE)

	# THE CROSS. Trim: it stands on the summit's own collision volume 9 m up, and a
	# 22 cm post is not something to walk into.
	var gold := _lm_shade(LM_SANDSTONE, rng, 0.02)
	terrain.create_box(center + Vector3(0.0, y + 1.7, 0.0), Vector3(0.26, 3.4, 0.26), yaw, rng, block_batch, block_body,
			0.0, gold, false)
	terrain.create_box(center + Vector3(0.0, y + 2.55, 0.0), Vector3(2.0, 0.26, 0.24), yaw, rng, block_batch, block_body,
			0.0, gold, false)
	# The little sunburst at the crossing, which every Alpine Gipfelkreuz has.
	terrain.create_box(center + Vector3(0.0, y + 2.55, 0.0), Vector3(0.6, 0.6, 0.3), yaw + PI / 4.0,
			rng, block_batch, block_body, 0.0, gold, false)

	return { "radius": 6.0, "top": y + 3.4 }

static func _landmark_wartburg(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 35 — WARTBURG CASTLE: a square stone keep (the Bergfried, with its cross)
	standing over a long HALF-TIMBERED hall, a gate tower at one end and a low
	curtain wall closing the courtyard, all of it on a rock outcrop.

	DELIBERATELY NOT NEUSCHWANSTEIN, and the registry banner says why: "a castle" is
	a silhouette two entries could share, so the separation has to be COLOUR and
	MASS. Neuschwanstein is white walls, blue cones and a tall slender keep — a
	fairy tale seen from below. The Wartburg is ochre and dark timber, wide and low,
	with a square battlemented keep — a fortress that was a fortress. Put them side
	by side and nothing about them matches.

	SO THE BERGFRIED STAYS SQUARE AND THE GATE TOWER GOES ROUND (bead
	godot-test1-y1o.17). The keep is the half of that contrast that does the work,
	and it keeps every cube it has: square shaft, square battlement band, four
	square merlons. The GATE tower is the other tower a fortress like this has, and
	it is a CYLINDER with a CONE cap — round in plan (1.08 aspect), so it collides
	as the drum it draws, and its cap is already collide = false, which is what
	rule 5d requires of a cone. One 1.2 m hipped cone on a gate house is not
	Neuschwanstein's three blue spires, and the sentence above still holds.

	THE TIMBER FRAMING IS THE HALF THAT DOES THE WORK. Fachwerk — dark beams laid
	over pale infill in horizontals and diagonals — is a pattern nothing else in the
	registry has, and it is eight thin trim boxes on the hall's front face. Without
	it the hall is a beige shed.

	RADIUS ARITHMETIC (declared 7.2). The widest reach is the GATE TOWER'S ROOF (not
	the tower under it — the roof oversails it by 0.2 m on each side, which is
	exactly the kind of trim that quietly becomes the binding box): centre at
	sqrt(4.6^2 + 2.2^2) = 5.10 with half-diagonal 0.5*sqrt(2.8^2 + 3.0^2) = 2.05, so
	7.15 <= 7.2. The tower itself is 5.10 + 1.77 = 6.87, the hall is 1.79 +
	0.5*sqrt(7.0^2 + 4.4^2) = 1.79 + 4.13 = 5.92, its roof 1.79 + 4.41 = 6.20, the
	outcrop 0.5*sqrt(9.0^2 + 7.0^2) = 5.70, and the keep sqrt(3.0^2 + 1.2^2) = 3.23
	+ 2.26 = 5.49. This is the tightest entry in the registry (0.15 m of headroom,
	measured), and it is safe because every one of those terms is yaw-INVARIANT —
	a box's offset and its own half-diagonal both rotate with the shape — so the
	self-check's 25-seed sweep is not what is holding it up.
	NO ACCENT.
	"""
	const HALL := Vector3(7.0, 5.6, 4.4)
	const KEEP := Vector3(3.2, 11.0, 3.2)
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)
	var plaster := _lm_shade(LM_OCHRE, rng, 0.04)
	var timber := _lm_shade(LM_ROOF, rng, 0.03).darkened(0.25)

	# The outcrop. Two slabs, so the castle stands on rock — Neuschwanstein's crag,
	# reused because a castle on grass reads as a model of a castle.
	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(9.0, 1.0, 7.0), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.05))
	terrain.create_box(center + rot * Vector3(0.2, 1.55, 0.0), Vector3(7.6, 1.1, 5.8), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.05))
	const ROCK := 2.1

	# THE HALL (the Palas), in stone up to first-floor level and half-timbered above
	# — which is how the real one is built and why the two-tone matters.
	var hall_spot := center + rot * Vector3(1.6, 0.0, 0.8)
	terrain.create_box(hall_spot + Vector3(0.0, ROCK + 1.4, 0.0), Vector3(HALL.x, 2.8, HALL.z), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	terrain.create_box(hall_spot + Vector3(0.0, ROCK + 2.8 + 1.4, 0.0), Vector3(HALL.x, 2.8, HALL.z), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(plaster, rng, 0.03))
	# THE FACHWERK — three horizontal rails and four diagonal braces on the front
	# face, plus a post at each end. Trim on the hall's own volume.
	var timber_y := ROCK + 2.8
	var face_z := -(HALL.z / 2.0 + 0.1)
	for rail in 3:
		terrain.create_box(hall_spot + rot * Vector3(0.0, timber_y + 0.25 + float(rail) * 1.25, face_z),
				Vector3(HALL.x, 0.22, 0.2), yaw, rng, block_batch, block_body, 0.0, timber, false)
	for i in 4:
		var bx: float = (float(i) - 1.5) * 1.7
		terrain.create_box(hall_spot + rot * Vector3(bx, timber_y + 1.4, face_z), Vector3(0.24, 2.4, 0.2),
				yaw, rng, block_batch, block_body, 0.0, timber, false)
	# The steep roof over the hall.
	terrain.create_box(hall_spot + Vector3(0.0, ROCK + 5.6 + 0.8, 0.0), Vector3(HALL.x + 0.4, 1.6, HALL.z + 0.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)
	terrain.create_box(hall_spot + Vector3(0.0, ROCK + 7.2 + 0.5, 0.0), Vector3(HALL.x - 1.6, 1.0, HALL.z - 1.8), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)

	# THE BERGFRIED — square, battlemented, no cone. The tallest thing here.
	var keep_spot := center + rot * Vector3(-3.0, 0.0, -1.2)
	terrain.create_box(keep_spot + Vector3(0.0, ROCK + KEEP.y / 2.0, 0.0), KEEP, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.03))
	var keep_top := ROCK + KEEP.y
	# Its battlements: four merlons per side is too many boxes for what it says, so
	# it is one ring band with the four corner merlons standing on it.
	terrain.create_box(keep_spot + Vector3(0.0, keep_top + 0.3, 0.0), Vector3(3.8, 0.6, 3.8), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04), false)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			terrain.create_box(keep_spot + rot * Vector3(x_side * 1.5, keep_top + 1.0, z_side * 1.5),
					Vector3(0.8, 1.4, 0.8), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04), false)
	# The cross on the keep, which is the one thing the fact's Luther hook can point
	# at without a signpost.
	terrain.create_box(keep_spot + Vector3(0.0, keep_top + 2.6, 0.0), Vector3(0.2, 2.0, 0.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng, 0.02), false)
	terrain.create_box(keep_spot + Vector3(0.0, keep_top + 2.9, 0.0), Vector3(0.9, 0.2, 0.18), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng, 0.02), false)

	# The gate tower and the curtain wall closing the courtyard.
	var gate_spot := center + rot * Vector3(4.6, 0.0, -2.2)
	terrain.create_box(gate_spot + Vector3(0.0, ROCK + 3.0, 0.0), Vector3(2.4, 6.0, 2.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), true, ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(gate_spot + Vector3(0.0, ROCK + 6.6, 0.0), Vector3(2.8, 1.2, 3.0), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false, ChunkBatch.BoxKind.CONE)
	terrain.create_box(gate_spot + rot * Vector3(0.0, ROCK + 1.3, -1.4), Vector3(1.2, 2.6, 0.4), yaw,
			rng, block_batch, block_body, 0.0, LM_OCHRE.darkened(0.78), false)
	for wx in [-1.4, 0.6, 2.6]:
		terrain.create_box(center + rot * Vector3(wx, ROCK + 1.1, -3.0), Vector3(2.0, 2.2, 0.9), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04))

	return { "radius": 7.2, "top": keep_top + 3.6 }

static func _landmark_ulm_minster(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 36 — ULM MINSTER: ONE colossal steeple over a modest nave, and the tower
	is the tallest thing in the whole registry because that is the fact — 161.5 m,
	the tallest church steeple on Earth, on a parish church in a town of 130,000.

	DELIBERATELY THE ONE-SPIRE ANSWER TO COLOGNE, which Cologne's own docstring
	already set up: "one spire is a church, two is the Dom". So this builder is not
	allowed to hedge. The tower is single, it is CENTRED on the west front rather
	than flanking it, it is far taller relative to its nave than Cologne's, and the
	nave behind it is deliberately low and plain so nothing competes. Read the two
	silhouettes side by side and the difference is not a detail, it is the subject.

	The stone is LM_MARBLE darkened — Ulm's is pale limestone, near-white and a
	world away from Cologne's soot-black basalt, which is the second separator.

	RADIUS ARITHMETIC (declared 8.0). The widest reach is the CHOIR at the far end
	of the nave: centre at 5.8 with half-diagonal 0.5*sqrt(3.4^2 + 2.2^2) = 2.03, so
	7.83 <= 8.0. The far nave bay is 4.0 + 0.5*sqrt(6.0^2 + 3.2^2) = 4.0 + 3.40 =
	7.40, the roof ridge is 2.5 + 0.5*sqrt(5.4^2 + 7.4^2) = 2.5 + 4.58 = 7.08, and
	the tower's base stage is 3.6 + 0.5*sqrt(2 * 5.2^2) = 3.6 + 3.68 = 7.28.
	NO ACCENT, for Cologne's reason: a Gothic church lit from within needs windows,
	and windows are what vanishes at 30 m.
	"""
	const NAVE := Vector3(6.0, 7.6, 3.2)
	const TOWER_Z := -3.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_MARBLE, rng, 0.03).darkened(0.14)

	# The nave — two low bays, plain, and it stays plain on purpose.
	for bz in [1.0, 4.0]:
		terrain.create_box(center + rot * Vector3(0.0, NAVE.y / 2.0, bz), NAVE, yaw, rng, block_batch, block_body,
				0.0, _lm_shade(stone, rng, 0.02))
	terrain.create_box(center + rot * Vector3(0.0, NAVE.y + 0.7, 2.5), Vector3(5.4, 1.4, 7.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)
	terrain.create_box(center + rot * Vector3(0.0, 3.3, 5.8), Vector3(3.4, 6.6, 2.2), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02))
	# Flying-buttress stubs down the flanks.
	for bx in [-3.8, 3.8]:
		for bz in [1.0, 4.2]:
			terrain.create_box(center + rot * Vector3(bx, 2.5, bz), Vector3(0.9, 5.0, 0.9), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# THE TOWER. Square base stage, a narrower shaft, then an OCTAGON stage (the
	# house idiom) and the openwork spire — which is the real tower's own sequence
	# and the reason it does not read as a chimney.
	var base := center + rot * Vector3(0.0, 0.0, TOWER_Z)
	terrain.create_box(base + Vector3(0.0, 4.0, 0.0), Vector3(5.2, 8.0, 5.2), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02))
	# The great west portal, dark and deep.
	terrain.create_box(base + rot * Vector3(0.0, 2.0, -2.5), Vector3(1.8, 4.0, 0.5), yaw, rng, block_batch, block_body,
			0.0, LM_MARBLE.darkened(0.66), false)
	terrain.create_box(base + Vector3(0.0, 12.0, 0.0), Vector3(4.4, 8.0, 4.4), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02))
	var y := 16.0
	for k in 2:
		terrain.create_box(base + Vector3(0.0, y + 2.6, 0.0), Vector3(3.4, 5.2, 3.4), yaw + float(k) * PI / 4.0,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)
	y += 5.2

	# THE OPENWORK SPIRE — six shrinking boxes, each re-yawed a little so the taper
	# reads as a pierced stone filigree rather than as a smooth cone. Trim: 21 m up.
	for i in 6:
		var w: float = 3.0 - float(i) * 0.44
		var h := 1.6
		terrain.create_box(base + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw + float(i) * PI / 16.0,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.CONE if i == 5 else ChunkBatch.BoxKind.CYLINDER)
		y += h
	terrain.create_box(base + Vector3(0.0, y + 0.7, 0.0), Vector3(0.28, 1.4, 0.28), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02), false, ChunkBatch.BoxKind.CONE)

	return { "radius": 8.0, "top": y + 1.4 }

static func _landmark_bremen_musicians(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 37 — BREMEN TOWN MUSICIANS: a donkey with a dog on its back, a cat on the
	dog and a rooster on the cat, in patinated bronze on a two-step plinth.

	THE STACK IS THE LANDMARK, so everything is subordinate to reading it as FOUR
	ANIMALS and not as one totem pole. Each one therefore gets a head that sticks
	out FORWARD (so the profile is a staircase of muzzles, not a column) and each is
	visibly smaller than the one below by more than its share — donkey, dog, cat,
	rooster in a 1 : 0.62 : 0.42 : 0.28 body length ratio, wider than life so the
	four steps survive the 30 m the whole registry is judged at.

	THE ONLY FIGURATIVE GROUP IN THE REGISTRY and by far the smallest entry, which
	is exactly right: it is a 4 m bronze on a street corner, not a monument. Its
	radius is DELIBERATELY LOOSE for Big Ben's reason — the honest stone reaches
	2.55 m, and a 2.55 m radius would fire the toast from 8.5 m, i.e. from close
	enough that the card and the statue fight for the same screen.

	The forelegs are given their own boxes and made deliberately prominent because
	the fact ends on them: grasping the donkey's forelegs is what the queue on
	Bremen's Marktplatz is actually there to do, and a fact that points at a detail
	the shape does not have is a fact about somewhere else.

	RADIUS ARITHMETIC (declared 4.2, honestly 2.55). The widest box is the lower
	plinth step, 3.6 square, so 0.5*sqrt(2 * 3.6^2) = 2.55. The donkey's muzzle is
	the furthest-out small box at 1.75 + 0.5*sqrt(1.1^2 + 0.6^2) = 1.75 + 0.63 =
	2.38, and its tail reaches 1.5 + 0.28 = 1.78.
	NO ACCENT.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var bronze := _lm_shade(LM_COPPER, rng, 0.03).darkened(0.38)
	var patina := _lm_shade(LM_COPPER, rng, 0.04)

	terrain.create_box(center + Vector3(0.0, 0.35, 0.0), Vector3(3.6, 0.7, 3.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04))
	terrain.create_box(center + Vector3(0.0, 0.95, 0.0), Vector3(2.6, 0.5, 2.6), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.03))
	const PLINTH := 1.2

	# THE DONKEY. Four legs, and the FORELEGS (at +x, the front) are thicker and
	# stand clear of the body — see the docstring.
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var thick: float = 0.34 if x_side > 0.0 else 0.28
			terrain.create_box(center + rot * Vector3(x_side * 0.95, PLINTH + 0.6, z_side * 0.38),
					Vector3(thick, 1.2, thick), yaw, rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02),
					true, ChunkBatch.BoxKind.CYLINDER)
	var body_y := PLINTH + 1.2 + 0.62
	terrain.create_box(center + Vector3(0.0, body_y, 0.0), Vector3(2.6, 1.24, 1.1), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(bronze, rng, 0.02))
	# Neck, muzzle and the two long ears — the ears are what make it a donkey and
	# not a horse, and they are 20 cm boxes, so they are worth the two lines.
	terrain.create_box(center + rot * Vector3(1.15, body_y + 0.75, 0.0), Vector3(0.65, 1.2, 0.7), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02), false)
	terrain.create_box(center + rot * Vector3(1.75, body_y + 1.15, 0.0), Vector3(1.1, 0.6, 0.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02), false)
	for z_side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(1.25, body_y + 1.75, z_side * 0.2), Vector3(0.22, 0.8, 0.3), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02), false)
	terrain.create_box(center + rot * Vector3(-1.5, body_y - 0.1, 0.0), Vector3(0.5, 0.7, 0.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02), false)

	# THE DOG, standing on the donkey's back. From here up everything is trim: it is
	# stacked on the donkey's own collision volume, and a bronze cat is not a ledge.
	var dog_y := body_y + 0.62 + 0.42
	terrain.create_box(center + rot * Vector3(-0.05, dog_y, 0.0), Vector3(1.62, 0.84, 0.75), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(patina, rng, 0.02), false)
	terrain.create_box(center + rot * Vector3(0.9, dog_y + 0.5, 0.0), Vector3(0.72, 0.62, 0.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(patina, rng, 0.02), false)
	for z_side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(0.78, dog_y + 0.9, z_side * 0.2), Vector3(0.24, 0.4, 0.26), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(patina, rng, 0.02), false)

	# THE CAT.
	var cat_y := dog_y + 0.42 + 0.3
	terrain.create_box(center + rot * Vector3(-0.05, cat_y, 0.0), Vector3(1.1, 0.6, 0.55), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02), false)
	terrain.create_box(center + rot * Vector3(0.6, cat_y + 0.42, 0.0), Vector3(0.5, 0.46, 0.46), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02), false)
	terrain.create_box(center + rot * Vector3(-0.72, cat_y + 0.35, 0.0), Vector3(0.18, 0.8, 0.18), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(bronze, rng, 0.02), false)

	# THE ROOSTER, and its comb — the top of the stack, and the one that has to be
	# unmistakable in profile because there is nothing above it to give it context.
	var bird_y := cat_y + 0.3 + 0.32
	terrain.create_box(center + rot * Vector3(0.0, bird_y, 0.0), Vector3(0.72, 0.64, 0.5), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(patina, rng, 0.02), false)
	terrain.create_box(center + rot * Vector3(0.22, bird_y + 0.52, 0.0), Vector3(0.34, 0.42, 0.32), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(patina, rng, 0.02), false)
	terrain.create_box(center + rot * Vector3(0.22, bird_y + 0.82, 0.0), Vector3(0.4, 0.26, 0.14), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_VERMILION, rng, 0.03), false)
	# The tail, swept up and back.
	terrain.create_box(center + rot * Vector3(-0.46, bird_y + 0.42, 0.0), Vector3(0.5, 0.7, 0.16), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(patina, rng, 0.02), false)

	return { "radius": 4.2, "top": bird_y + 0.95 }

# ----------------------------------------------------------------------------
# WAVE 5
# ----------------------------------------------------------------------------

static func _lm_strut(terrain: Node3D, center: Vector3, from: Vector3, to: Vector3, thick: float, color: Color, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, collide: bool = false, kind: int = ChunkBatch.BoxKind.CUBE) -> void:
	"""
	ONE BOX SPANNING TWO POINTS IN ANY DIRECTION — the piece this file has been
	working around since wave 1, and the reason three of wave 5's shapes are
	buildable at all (the Atomium's twelve tubes, the Space Needle's tripod, the
	Hollywood sign's Y and W).

	create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt), which every earlier
	docstring in this file treats as "yaw, plus a lean toward +Z". It is more than
	that: those two angles are a full spherical parametrisation of the box's local
	+Y axis. Basis(RIGHT, t) sends +Y to (0, cos t, sin t), and Basis(UP, a) then
	sends that to (sin t * sin a, cos t, sin t * cos a). So for any unit direction d,

	    tilt  = acos(d.y)            (how far off vertical)
	    theta = atan2(d.x, d.z)      (which bearing to lean along)

	and passing `yaw + theta` as the yaw points a Y-long box exactly along d IN THE
	LANDMARK'S OWN FRAME — the landmark's own yaw composes on top for free, which is
	why `from` and `to` are LOCAL offsets and the caller never touches a basis.

	COLLIDE DEFAULTS FALSE because most struts are overhead trim (tubes 12 m up, a
	letter's diagonal stroke). Pass true for anything the player can walk into — the
	Space Needle's legs are the only wave-5 caller that does.

	KIND DEFAULTS CUBE for the one caller that must stay flat: the Hollywood sign's
	Y and W are sheet metal, and a round stroke is a pipe. Everything else that
	spans two points here is a TUBE — the Atomium's twelve, Tower Bridge's chains,
	the Space Needle's legs, a dragon's neck — and passes CYLINDER. The kind rides
	the same box, so it costs no draw and no RNG draw (rule 5a above).

	@param from / to: chunk-local offsets from `center`, BEFORE the landmark yaw.
	@param thick: the strut's square cross-section.

	RADIUS NOTE for callers: a strut's end faces sit exactly on `from` and `to`, so
	its horizontal reach is bounded by max(|from.xz|, |to.xz|) + thick * 0.71. No
	caller here is anywhere near its landmark's declared radius on a strut.
	"""
	var d := to - from
	var length := d.length()
	if length < 0.001:
		return
	var dir := d / length
	var tilt := acos(clampf(dir.y, -1.0, 1.0))
	var theta := atan2(dir.x, dir.z)
	terrain.create_box(center + Basis(Vector3.UP, yaw) * ((from + to) * 0.5), Vector3(thick, length, thick),
			yaw + theta, rng, block_batch, block_body, tilt, color, collide, kind)


static func _landmark_parthenon(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 38 — PARTHENON: a three-step marble platform, a peristyle of Doric columns
	running ALL THE WAY ROUND it, a three-bay architrave on their capitals and a low
	gabled roof of three shrinking slabs.

	THE RECTANGLE OF COLUMNS IS THE LANDMARK. A row of columns under a gable is a
	bank, a courthouse or a museum; a closed rectangle of them is the Parthenon, so
	the peristyle goes round rather than across the front — eight per long flank and
	two more per end, which is the real 8 x 17 plan thinned to what survives at 30 m.
	The colonnade is also why the architrave is THREE BAYS and not one 13 m box: the
	Plaza Mayor's reason exactly (one long box's rotated half-diagonal is what blows
	a radius), and it costs two extra boxes.

	It reuses LM_MARBLE — Pentelic marble is what the Taj's white already is — and
	shades the columns a touch off the platform, because a colonnade in one flat
	colour reads as a grooved wall.

	RADIUS ARITHMETIC (declared 8.8). The widest box is the bottom STEP, centred, so
	0.5*sqrt(15.2^2 + 8.0^2) = 8.59. A corner column sits at (5.8, 2.4) with 0.45
	half-extents => sqrt(6.25^2 + 2.85^2) = 6.87, an architrave bay at x = 4.4 is
	sqrt(6.6^2 + 3.2^2) = 7.33, and the widest roof slab is 0.5*sqrt(13.4^2 + 6.6^2)
	= 7.47.
	NO ACCENT: a temple lit from inside would need the cella's doorway, and a
	doorway is exactly the detail that vanishes at 30 m.
	"""
	const COL := Vector3(0.9, 5.4, 0.9)
	const FLANK_Z := 2.4
	const END_X := 5.8
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var marble := _lm_shade(LM_MARBLE, rng, 0.02)

	# The krepis: three shrinking steps, the platform you climb to reach the temple.
	var step_y := 0.0
	for i in 3:
		var w: float = 15.2 - float(i) * 0.8
		var d: float = 8.0 - float(i) * 0.8
		terrain.create_box(center + Vector3(0.0, step_y + 0.175, 0.0), Vector3(w, 0.35, d), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(marble, rng, 0.03))
		step_y += 0.35

	# THE PERISTYLE. Eight columns down each long flank, plus two per end to close
	# the rectangle (the flank rows already own the four corners).
	var col_y := step_y + COL.y / 2.0
	for i in 8:
		var cx: float = -END_X + float(i) * (END_X * 2.0 / 7.0)
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(cx, col_y, z_side * FLANK_Z), COL, yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(marble, rng, 0.025), true, ChunkBatch.BoxKind.CYLINDER)
	for x_side in [-1.0, 1.0]:
		for cz in [-0.8, 0.8]:
			terrain.create_box(center + rot * Vector3(x_side * END_X, col_y, cz), COL, yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(marble, rng, 0.025), true, ChunkBatch.BoxKind.CYLINDER)

	# The cella — the walled inner room the columns stand around. Kept low enough
	# that the colonnade still reads as a colonnade from every bearing.
	terrain.create_box(center + Vector3(0.0, step_y + 2.4, 0.0), Vector3(9.0, 4.8, 3.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(marble, rng, 0.03).darkened(0.08))

	# The entablature, in three bays for the Plaza Mayor's radius reason.
	var arch_y := step_y + COL.y
	for bx in [-4.4, 0.0, 4.4]:
		terrain.create_box(center + rot * Vector3(bx, arch_y + 0.5, 0.0), Vector3(4.4, 1.0, 6.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(marble, rng, 0.02))
	arch_y += 1.0

	# The roof: three slabs shrinking in depth, which is the gable seen from the
	# flank AND the pediment seen from the end, in three boxes instead of six.
	var roof_y := arch_y
	for i in 3:
		var d: float = 6.6 - float(i) * 1.9
		terrain.create_box(center + Vector3(0.0, roof_y + 0.25, 0.0), Vector3(13.4, 0.5, d), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(marble, rng, 0.02).darkened(0.12), false)
		roof_y += 0.5

	return { "radius": 8.8, "top": roof_y }


static func _landmark_sagrada(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 39 — SAGRADA FAMÍLIA: a nave under a THICKET of tapering spires of unequal
	height, each one twisted a little against the one beside it, each capped with a
	coloured pinnacle, and one central tower standing head and shoulders above all
	of them.

	UNEQUAL AND CROWDED IS THE WHOLE CUE, and it is what separates this from the two
	cathedrals the registry already has. Cologne is TWO spires of deliberately equal
	height; Ulm is ONE. Here there are nine, no two the same height, packed close
	enough to overlap in silhouette from most bearings — which is also honest to the
	building, whose towers have gone up one at a time for 140 years.

	The heights are drawn per spire rather than fixed, so no two worlds show the
	same skyline; the tallest is always the CENTRAL one, because a Jesus tower that
	is merely joint-tallest reads as a tenth bell tower.

	RADIUS ARITHMETIC (declared 7.6). The widest box is the PLINTH, centred, so
	0.5*sqrt(8.8^2 + 11.6^2) = 7.28. A corner spire's base sits at (2.7, 4.2), i.e.
	4.99 out, and its tiers carry their own twist, so the bound is |offset| plus the
	full half-diagonal 0.5*sqrt(2 * 1.5^2) = 1.06 => 6.05. A transept block reaches
	sqrt(2.5^2 + 5.7^2) = 6.22.
	NO ACCENT: nine spires already carry nine coloured pinnacles, and a glow on one
	of them would say "this one matters", which is the opposite of the point.
	"""
	const SPIRE_X: Array = [-2.7, -0.9, 0.9, 2.7]
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.03)
	var pinnacles: Array = [LM_VERMILION, LM_COPPER, LM_MARBLE, LM_SLATE_BLUE]

	terrain.create_box(center + Vector3(0.0, 0.35, 0.0), Vector3(8.8, 0.7, 11.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.04))

	# The nave, two bays, and the two facade blocks the spires rise out of.
	for bz in [-2.6, 2.6]:
		terrain.create_box(center + rot * Vector3(0.0, 5.05, bz), Vector3(5.4, 9.0, 4.6), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.025))
	for fz in [-4.6, 4.6]:
		terrain.create_box(center + rot * Vector3(0.0, 3.7, fz), Vector3(5.0, 6.0, 2.2), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# THE EIGHT BELL TOWERS. Each is a stack of shrinking boxes with a small extra
	# yaw per tier, which is what turns a cone into the pierced, faceted stonework
	# Gaudí's towers actually have — the same trick Ulm's spire uses, and the reason
	# their radius bound has to use the full half-diagonal.
	for sx_variant: Variant in SPIRE_X:
		var sx: float = sx_variant
		for sz in [-4.2, 4.2]:
			var base := center + rot * Vector3(sx, 0.0, sz)
			var y := 0.7
			var tiers := rng.randi_range(6, 8)
			for i in tiers:
				var w: float = 1.5 - float(i) * 0.16
				var h := rng.randf_range(1.5, 2.1)
				terrain.create_box(base + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w),
						yaw + float(i) * PI / 14.0, rng, block_batch, block_body, 0.0,
						_lm_shade(stone, rng, 0.025), i < 2,
						ChunkBatch.BoxKind.CONE if i == tiers - 1 else ChunkBatch.BoxKind.CYLINDER)
				y += h
			# The pinnacle is a SPHERE: Gaudi's are knobbly coloured bulbs, and
			# that is the one thing on this thicket that is not a taper.
			terrain.create_box(base + Vector3(0.0, y + 0.45, 0.0), Vector3(0.75, 0.9, 0.75), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(pinnacles[rng.randi_range(0, 3)], rng, 0.04), false,
					ChunkBatch.BoxKind.SPHERE)

	# THE CENTRAL TOWER, and it is drawn to be the tallest by construction.
	var y := 0.7
	for i in 10:
		var w: float = 2.8 - float(i) * 0.22
		var h := rng.randf_range(1.9, 2.3)
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w),
				yaw + float(i) * PI / 20.0, rng, block_batch, block_body, 0.0,
				_lm_shade(stone, rng, 0.02), i < 2, ChunkBatch.BoxKind.CONE if i == 9 else ChunkBatch.BoxKind.CYLINDER)
		y += h
	terrain.create_box(center + Vector3(0.0, y + 0.7, 0.0), Vector3(1.1, 1.4, 1.1), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_MARBLE, rng, 0.03), false, ChunkBatch.BoxKind.CONE)

	return { "radius": 7.6, "top": y + 1.4 }


static func _landmark_tower_bridge(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 40 — TOWER BRIDGE: two Gothic towers on river piers, a road deck between
	them at their feet, a pair of blue HIGH-LEVEL WALKWAYS between them at their
	heads, approach spans running out to abutments either side, and the suspension
	chains slung from tower to abutment.

	THE TWO LEVELS ARE THE RECOGNITION CUE and the only thing separating this from
	the Golden Gate: a road at the bottom, an empty gap, and a second span in the
	air. Every other suspension bridge in the world has one deck. So the walkways
	are BLUE where the towers are grey — Tower Bridge's paintwork is the same cue
	repeated in colour — and they are trim rather than solid, because a 9 m walkway
	the player could stand on would need a way up, and there isn't one.

	The chains use _lm_strut instead of the Golden Gate's chain-of-boxes: these are
	straight, not catenary (they hang from tower head to abutment over a short
	span), so one box each is both cheaper and truer than eleven.

	RADIUS ARITHMETIC (declared 8.8). The furthest box is an ABUTMENT PIER at
	x = 7.6 with half-extents (0.8, 1.7) => sqrt(8.4^2 + 1.7^2) = 8.57. An approach
	deck reaches sqrt(8.2^2 + 1.6^2) = 8.35, a river pier sqrt(5.3^2 + 2.2^2) =
	5.74, and a chain's far end sqrt(7.4^2 + 1.5^2) + 0.25 = 7.80.
	NO ACCENT.
	"""
	const TOWER_X := 3.4
	const TOWER := Vector3(3.0, 9.0, 3.6)
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.03)
	var blue := _lm_shade(LM_SLATE_BLUE, rng, 0.03).lightened(0.12)

	var tower_top := 0.0
	for side in [-1.0, 1.0]:
		# The river pier each tower stands on.
		terrain.create_box(center + rot * Vector3(side * TOWER_X, 0.6, 0.0), Vector3(3.8, 1.2, 4.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04).darkened(0.1))
		terrain.create_box(center + rot * Vector3(side * TOWER_X, 1.2 + TOWER.y / 2.0, 0.0), TOWER, yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.025))
		# The road arch through its foot, dark and deep. Trim inside the tower's own
		# collision volume, so the tower stays one solid mass to walk round.
		terrain.create_box(center + rot * Vector3(side * TOWER_X, 2.4, 0.0), Vector3(1.9, 2.4, 3.9), yaw,
				rng, block_batch, block_body, 0.0, LM_STONE_GREY.darkened(0.65), false)
		var y := 1.2 + TOWER.y
		# Four corner turrets and the steep central roof — the Gothic half.
		for tx in [-1.1, 1.1]:
			for tz in [-1.4, 1.4]:
				terrain.create_box(center + rot * Vector3(side * TOWER_X + tx, y + 0.9, tz), Vector3(0.8, 1.8, 0.8), yaw,
						rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), false, ChunkBatch.BoxKind.CYLINDER)
				terrain.create_box(center + rot * Vector3(side * TOWER_X + tx, y + 2.2, tz), Vector3(0.5, 0.9, 0.5), yaw,
						rng, block_batch, block_body, 0.0, blue, false, ChunkBatch.BoxKind.CONE)
		for i in 3:
			var w: float = 2.6 - float(i) * 0.75
			terrain.create_box(center + rot * Vector3(side * TOWER_X, y + 0.55, 0.0), Vector3(w, 1.1, w), yaw,
					rng, block_batch, block_body, 0.0, blue, false, ChunkBatch.BoxKind.CONE if i == 2 else ChunkBatch.BoxKind.CYLINDER)
			y += 1.1
		tower_top = y

		# The approach span and its abutment, out beyond each tower.
		terrain.create_box(center + rot * Vector3(side * 6.2, 2.4, 0.0), Vector3(4.0, 0.5, 3.2), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03).darkened(0.15))
		terrain.create_box(center + rot * Vector3(side * 7.6, 1.2, 0.0), Vector3(1.6, 2.4, 3.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04))

		# The suspension chain, one straight strut per side of the roadway.
		for z_side in [-1.0, 1.0]:
			_lm_strut(terrain, center, Vector3(side * 4.9, 6.4, z_side * 1.5), Vector3(side * 7.4, 2.9, z_side * 1.5),
					0.35, blue, yaw, rng, block_batch, block_body, false, ChunkBatch.BoxKind.CYLINDER)

	# The bascule roadway between the towers, closed to traffic and solid underfoot.
	terrain.create_box(center + Vector3(0.0, 2.4, 0.0), Vector3(6.8, 0.5, 3.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03).darkened(0.2))
	# THE HIGH-LEVEL WALKWAYS — the second span, 8 m up, and the whole point.
	for z_side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(0.0, 8.4, z_side * 1.2), Vector3(7.4, 0.45, 0.7), yaw,
				rng, block_batch, block_body, 0.0, blue, false)
	terrain.create_box(center + Vector3(0.0, 9.1, 0.0), Vector3(7.0, 0.9, 2.8), yaw,
			rng, block_batch, block_body, 0.0, blue.darkened(0.12), false)

	return { "radius": 8.8, "top": tower_top }


static func _landmark_arc_de_triomphe(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 41 — ARC DE TRIOMPHE: ONE colossal vault through a single block of pale
	limestone, a smaller vault crossing it, deep relief panels on the four piers and
	a plain attic on top.

	ONE ARCH IS THE WHOLE IDENTITY, which is what keeps it apart from the two gates
	the registry already has. The Brandenburg Gate is a COLONNADE with five
	passages; the Porta Nigra is two storeys of arcading. This is a solid mass with
	a single hole in it, and it is built as four corner piers precisely so that the
	hole is real from both bearings — you walk through it either way.

	The reliefs are a real feature and not decoration: the Arc is remembered as the
	one covered in sculpture, so each pier face gets a deeply recessed panel. They
	are trim inside the piers' own volumes.

	RADIUS ARITHMETIC (declared 7.2). The widest box is the bottom STEP, centred, so
	0.5*sqrt(11.4^2 + 7.6^2) = 6.85. The attic is 0.5*sqrt(10.8^2 + 7.2^2) = 6.49, a
	pier sits at (3.6, 2.1) with half-extents (1.4, 1.1) => sqrt(5.0^2 + 3.2^2) =
	5.94, and a relief panel reaches sqrt(4.7^2 + 3.43^2) = 5.82.
	NO ACCENT.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_MARBLE, rng, 0.02).darkened(0.14)

	terrain.create_box(center + Vector3(0.0, 0.2, 0.0), Vector3(11.4, 0.4, 7.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.04))

	# FOUR PIERS, which is what makes both vaults real rather than painted on.
	const PIER := Vector3(2.8, 8.6, 2.2)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(x_side * 3.6, 0.4 + PIER.y / 2.0, z_side * 2.1), PIER, yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
			# The relief panel on the outward face of each pier.
			terrain.create_box(center + rot * Vector3(x_side * 3.6, 5.0, z_side * 3.28), Vector3(2.2, 3.4, 0.3), yaw,
					rng, block_batch, block_body, 0.0, stone.darkened(0.45), false)

	# The mass over the vault, then the attic that finishes it flat.
	var y := 0.4 + PIER.y
	terrain.create_box(center + Vector3(0.0, y + 2.0, 0.0), Vector3(10.0, 4.0, 6.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	y += 4.0
	terrain.create_box(center + Vector3(0.0, y + 0.6, 0.0), Vector3(10.8, 1.2, 7.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03).darkened(0.06))
	y += 1.2

	return { "radius": 7.2, "top": y }


static func _landmark_atomium(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 42 — ATOMIUM: nine steel spheres at the corners and centre of a cube
	STANDING ON ONE VERTEX, joined by tubes along all twelve edges and by six more
	running in to the middle.

	THE VERTEX STANCE IS THE LANDMARK. A cube of balls sitting flat is a molecule
	model; tipped onto a corner it becomes the Atomium, and the tipped cube has a
	shape that falls out of boxes for free: one sphere on the ground, THREE in a ring
	a third of the way up, one dead centre, THREE more in a ring two thirds up
	rotated 60 degrees against the first, and one on top. That is exactly a cube's
	eight vertices in that orientation, so it is built from that description rather
	than from a rotation this file has no way to express.

	A SPHERE OUT OF BOXES is three boxes: a cube, the same cube yawed 45 degrees
	(which rounds the horizontal profile) and a vertical bar (which rounds the top
	and bottom). At the 30 m the registry is judged from that is a ball; closer, it
	is a faceted ball, which is what a riveted 1958 steel sphere looked like anyway.

	The tubes are the first real customer for _lm_strut — twelve of them point in
	twelve different directions, and before that helper existed this shape could not
	be built at all.

	RADIUS ARITHMETIC (declared 6.6). A ring sphere sits at radius 4.2. Its yawed
	cube carries its own rotation, so the bound is 4.2 + 0.5*sqrt(2 * 1.9^2) = 5.54;
	its horizontal bar is placed on the landmark yaw, worst case at the 210-degree
	node => sqrt(4.89^2 + 2.75^2) = 5.61. Every tube's ends sit on sphere centres, so
	no tube reaches past 4.2 + 0.36 = 4.56.
	ONE ACCENT is deliberately NOT taken: nine steel balls with one glowing would
	read as a reactor, not a monument.
	"""
	const NODE := 1.9
	const RING_R := 4.2
	const RING_A_Y := 5.6
	const RING_B_Y := 11.6
	const CORE_Y := 8.6
	const TOP_Y := 16.6
	const BOTTOM_Y := 1.4
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var steel := _lm_shade(LM_GRANITE, rng, 0.03).lightened(0.25)

	# The nine sphere centres, in the tipped-cube layout the docstring describes.
	var spheres: Array[Vector3] = [Vector3(0.0, BOTTOM_Y, 0.0)]
	for i in 3:
		var a := deg_to_rad(90.0 + float(i) * 120.0)
		spheres.append(Vector3(cos(a) * RING_R, RING_A_Y, sin(a) * RING_R))
	spheres.append(Vector3(0.0, CORE_Y, 0.0))
	for i in 3:
		var a := deg_to_rad(30.0 + float(i) * 120.0)
		spheres.append(Vector3(cos(a) * RING_R, RING_B_Y, sin(a) * RING_R))
	spheres.append(Vector3(0.0, TOP_Y, 0.0))

	# The pedestal the bottom sphere rests on.
	terrain.create_box(center + Vector3(0.0, 0.2, 0.0), Vector3(2.8, 0.4, 2.8), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.04))

	# THE TUBES FIRST, so the spheres' boxes land on top of them in the batch and a
	# tube never appears to pass in front of the ball it ends in. Twelve cube edges:
	# bottom to ring A, ring A to its two ring-B neighbours, ring B to the top. Then
	# six more from every ring sphere in to the core, which the real Atomium has as
	# its escalator shafts.
	for i in 3:
		_lm_strut(terrain, center, spheres[0], spheres[1 + i], 0.5, steel, yaw, rng, block_batch, block_body, false, ChunkBatch.BoxKind.CYLINDER)
		_lm_strut(terrain, center, spheres[5 + i], spheres[8], 0.5, steel, yaw, rng, block_batch, block_body, false, ChunkBatch.BoxKind.CYLINDER)
		_lm_strut(terrain, center, spheres[1 + i], spheres[5 + i], 0.5, steel, yaw, rng, block_batch, block_body, false, ChunkBatch.BoxKind.CYLINDER)
		_lm_strut(terrain, center, spheres[1 + i], spheres[5 + (i + 2) % 3], 0.5, steel, yaw, rng, block_batch, block_body, false, ChunkBatch.BoxKind.CYLINDER)
		_lm_strut(terrain, center, spheres[1 + i], spheres[4], 0.42, steel, yaw, rng, block_batch, block_body, false, ChunkBatch.BoxKind.CYLINDER)
		_lm_strut(terrain, center, spheres[5 + i], spheres[4], 0.42, steel, yaw, rng, block_batch, block_body, false, ChunkBatch.BoxKind.CYLINDER)

	# THE SPHERES. Solid only where the player could walk into one — the bottom
	# sphere and the three of ring A sit low enough to matter; the rest is 8 m up.
	for i in spheres.size():
		var s: Vector3 = spheres[i]
		var solid: bool = s.y < 6.5
		var tint := _lm_shade(steel, rng, 0.02)
		terrain.create_box(center + rot * s, Vector3(NODE, NODE, NODE), yaw,
				rng, block_batch, block_body, 0.0, tint, solid, ChunkBatch.BoxKind.SPHERE)
		terrain.create_box(center + rot * s, Vector3(NODE, NODE, NODE), yaw + PI / 4.0,
				rng, block_batch, block_body, 0.0, tint, false, ChunkBatch.BoxKind.SPHERE)
		terrain.create_box(center + rot * s, Vector3(NODE * 0.66, NODE * 1.32, NODE * 0.66), yaw,
				rng, block_batch, block_body, 0.0, tint.darkened(0.06), false, ChunkBatch.BoxKind.CYLINDER)

	return { "radius": 6.6, "top": TOP_Y + NODE * 0.66 }


## The nine letters of HOLLYWOOD, and nothing else — this is a sign, not a font.
## Strokes live in a 1 x 1 glyph box with the origin at its bottom-left corner, so
## the builder scales one pair of numbers and the table never has to know how big
## the sign is. A BAR is [cx, cy, w, h]; HW_DIAGS holds [x0, y0, x1, y1] segments
## for the only two letters here that need them.
const HW_BARS: Dictionary = {
	"H": [[0.13, 0.5, 0.26, 1.0], [0.87, 0.5, 0.26, 1.0], [0.5, 0.5, 0.74, 0.2]],
	"O": [[0.13, 0.5, 0.26, 1.0], [0.87, 0.5, 0.26, 1.0], [0.5, 0.9, 0.74, 0.2], [0.5, 0.1, 0.74, 0.2]],
	"L": [[0.13, 0.5, 0.26, 1.0], [0.56, 0.1, 0.6, 0.2]],
	"Y": [[0.5, 0.25, 0.26, 0.5]],
	"W": [],
	"D": [[0.13, 0.5, 0.26, 1.0], [0.87, 0.46, 0.26, 0.82], [0.5, 0.9, 0.74, 0.2], [0.5, 0.1, 0.74, 0.2]],
}
const HW_DIAGS: Dictionary = {
	"H": [], "O": [], "L": [], "D": [],
	"Y": [[0.06, 1.0, 0.5, 0.48], [0.94, 1.0, 0.5, 0.48]],
	"W": [[0.03, 1.0, 0.24, 0.05], [0.24, 0.05, 0.5, 0.72], [0.5, 0.72, 0.76, 0.05], [0.76, 0.05, 0.97, 1.0]],
}


static func _landmark_hollywood(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 43 — HOLLYWOOD SIGN: nine white letters standing in a row along the crest
	of a low scrub hill.

	THE ONLY LANDMARK IN THE REGISTRY THAT IS WRITING, which is why it earns a slot
	at all — every other entry here is a building, a statue or a bridge, and a word
	is a silhouette nothing else can be confused with. It is also the widest thing
	in the table relative to its height: 14.8 m of letters only 2.4 m tall, which is
	the sign's real proportion and the reason it needs its own hill to stand on
	(flat ground would make it a fence).

	THE LETTERS ARE UNEVEN ON PURPOSE. Each one gets its own small height and lean
	off the RNG, because the real sign's letters have never been in line — they were
	nailed to telegraph poles in 1923 as a property advertisement, and every photo
	of them shows the row sagging.

	Y and W are the reason _lm_strut exists on the Hollywood side: a staircase of
	little vertical boxes would read as a smear at 30 m, and one leaning box per
	diagonal reads as a stroke.

	RADIUS ARITHMETIC (declared 8.8). The widest box is the lower HILL slab, centred,
	so 0.5*sqrt(16.8^2 + 3.6^2) = 8.59. The outermost letter stroke centres at
	x = 7.4 + 0.37 * 1.4 = 7.92 with half-width 0.18 and half-depth 0.17 =>
	sqrt(8.10^2 + 0.17^2) = 8.10.
	NO ACCENT.
	"""
	const WORD := "HOLLYWOOD"
	const LW := 1.4          # letter width
	const LH := 2.4          # letter height
	const PITCH := 1.85      # letter-to-letter spacing
	const STROKE := 0.34     # how thick the sheet metal is, front to back
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var white := _lm_shade(LM_MARBLE, rng, 0.03)
	var scrub := _lm_shade(LM_OCHRE, rng, 0.05).darkened(0.32)

	# The hill: two slabs, the upper one set back so the letters stand on a crest
	# with ground falling away in front of them.
	terrain.create_box(center + Vector3(0.0, 0.45, 0.0), Vector3(16.8, 0.9, 3.6), yaw,
			rng, block_batch, block_body, 0.0, scrub)
	terrain.create_box(center + rot * Vector3(0.0, 1.3, -0.35), Vector3(13.6, 0.8, 2.5), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(scrub, rng, 0.04))
	# A few bushes, so the hill is chaparral rather than a plinth.
	for i in 5:
		var bx := rng.randf_range(-7.4, 7.4)
		var bs := rng.randf_range(0.5, 0.9)
		terrain.create_box(center + rot * Vector3(bx, 0.9 + bs / 2.0, rng.randf_range(1.0, 1.6)),
				Vector3(bs * 1.4, bs, bs * 1.2), rng.randf_range(0.0, TAU),
				rng, block_batch, block_body, 0.0, scrub.darkened(0.2), false, ChunkBatch.BoxKind.SPHERE)

	var top := 0.0
	for i in WORD.length():
		var glyph := WORD[i]
		var lx := (float(i) - 4.0) * PITCH
		# The sagging row: each letter is its own height off the same base.
		var base_y := 1.7 + rng.randf_range(-0.1, 0.1)
		var scale := rng.randf_range(0.94, 1.06)
		for bar_variant: Variant in HW_BARS[glyph]:
			var bar: Array = bar_variant
			terrain.create_box(center + rot * Vector3(lx + (float(bar[0]) - 0.5) * LW, base_y + float(bar[1]) * LH * scale, 0.0),
					Vector3(float(bar[2]) * LW, float(bar[3]) * LH * scale, STROKE), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(white, rng, 0.02), true)
		for seg_variant: Variant in HW_DIAGS[glyph]:
			var seg: Array = seg_variant
			_lm_strut(terrain, center,
					Vector3(lx + (float(seg[0]) - 0.5) * LW, base_y + float(seg[1]) * LH * scale, 0.0),
					Vector3(lx + (float(seg[2]) - 0.5) * LW, base_y + float(seg[3]) * LH * scale, 0.0),
					0.32, _lm_shade(white, rng, 0.02), yaw, rng, block_batch, block_body, true)
		# The 0.25 m buffer covers the diagonal strut corners from _lm_strut
		# (thick * 0.5 * sin(tilt) reaches up to ~0.08 m beyond the bar endpoints).
		top = maxf(top, base_y + LH * scale + 0.25)

	return { "radius": 8.8, "top": top }


static func _landmark_space_needle(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 44 — SPACE NEEDLE: three splayed legs meeting a slim core, and a gold
	flying-saucer clamped near the top with a spike above it.

	THE TRIPOD IS WHAT MAKES IT NOT THE FERNSEHTURM. Both are "a tower with a shape
	near the top", which is the crowded corner of this registry, so the two cues
	that separate them are both taken as far as they go: Berlin's is ONE shaft with a
	SPHERE, Seattle's is THREE legs splaying to a wide stance with a FLAT DISC. The
	legs are real struts rather than a tapering stack of boxes because the splay has
	to be visible in profile from every bearing.

	THE LEGS COLLIDE and everything from the saucer up does not: at 4 m out and 11 m
	long they are exactly the sort of thing a player walks into, while the disc is
	15 m up and nothing may stand on it.

	RADIUS ARITHMETIC (declared 6.2). The widest box is the WINDOW BAND round the
	saucer, centred and duplicated at 45 degrees, so 0.5*sqrt(2 * 7.4^2) = 5.23. A
	leg pad sits at 4.0 with half-extents 0.8 => sqrt(4.8^2 + 0.8^2) = 4.87, and a
	leg's own foot reaches 4.0 + 0.64 = 4.64.
	ONE ACCENT, and it is the one place in this shape a real light belongs: the
	aircraft beacon on the spike.
	"""
	const LEG_R := 4.0
	const CORE := Vector3(1.6, 15.6, 1.6)
	const SAUCER_Y := 15.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var steel := _lm_shade(LM_MARBLE, rng, 0.03).darkened(0.12)
	var gold := _lm_shade(LM_SANDSTONE, rng, 0.04)

	for i in 3:
		var a := deg_to_rad(90.0 + float(i) * 120.0)
		var foot := Vector3(cos(a) * LEG_R, 0.4, sin(a) * LEG_R)
		terrain.create_box(center + rot * Vector3(foot.x, 0.25, foot.z), Vector3(1.6, 0.5, 1.6), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.04), true, ChunkBatch.BoxKind.CYLINDER)
		_lm_strut(terrain, center, foot, Vector3(cos(a) * 0.75, 11.4, sin(a) * 0.75), 0.9, steel,
				yaw, rng, block_batch, block_body, true, ChunkBatch.BoxKind.CYLINDER)

	terrain.create_box(center + Vector3(0.0, CORE.y / 2.0, 0.0), CORE, yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(steel, rng, 0.02), true, ChunkBatch.BoxKind.CYLINDER)

	# THE SAUCER, four stacked discs each doubled at 45 degrees so the profile is a
	# round dish rather than a square tray. All trim — it is 15 m up.
	var discs: Array = [
		[5.4, 0.6, steel.darkened(0.1)],
		[7.4, 0.5, steel.darkened(0.5)],   # the window band, dark
		[7.2, 1.1, _lm_shade(steel, rng, 0.02)],
		[6.0, 0.55, gold],                 # "Galaxy Gold", the roof's real colour
	]
	var y := SAUCER_Y
	for disc_variant: Variant in discs:
		var disc: Array = disc_variant
		var w: float = disc[0]
		var h: float = disc[1]
		for extra_yaw in [0.0, PI / 4.0]:
			terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w),
					yaw + float(extra_yaw), rng, block_batch, block_body, 0.0, disc[2], false, ChunkBatch.BoxKind.CYLINDER)
		y += h

	# The spike, and the beacon that has to be on top of it.
	for i in 5:
		var w: float = 1.0 - float(i) * 0.17
		terrain.create_box(center + Vector3(0.0, y + 0.5, 0.0), Vector3(w, 1.0, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(steel, rng, 0.02), false, ChunkBatch.BoxKind.CONE if i == 4 else ChunkBatch.BoxKind.CYLINDER)
		y += 1.0
	terrain._spawn_artifact_accent(_parent_chunk, center + Vector3(0.0, y + 0.3, 0.0), Vector3(0.35, 0.45, 0.35),
			yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 6.2, "top": y + 0.5 }


static func _landmark_osaka_castle(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 45 — OSAKA CASTLE: a battered stone base of two sloping courses, and on it a
	five-tier tenshu of white plaster walls, each tier wearing a green tiled roof
	whose corners kick upward, with the golden shachihoko on the ridge.

	FIVE ROOFS, EACH WIDER THAN THE FLOOR IT COVERS — that is the whole East Asian
	castle silhouette, and it is why this cannot be confused with the two European
	castles already in the registry (Neuschwanstein's blue cones, the Wartburg's
	keep-over-hall). The upswept corners are four small boxes per roof and they are
	what stop the stack reading as a wedding cake.

	The stone base is not scenery either: a tenshu sits on a colossal battered plinth
	that is often taller than the tower, and cutting it would leave a pagoda.

	RADIUS ARITHMETIC (declared 8.8). The widest box is the outer PLINTH, centred, so
	0.5*sqrt(12.8^2 + 11.0^2) = 8.44. The first roof is 0.5*sqrt(8.5^2 + 7.5^2) =
	5.67 and its corner kicks reach sqrt(4.75^2 + 4.25^2) = 6.37.
	NO ACCENT: the shachihoko are already the bright thing up there, and gold that
	glows is a lamp.

	NOTHING ON A TENSHU IS ROUND EXCEPT ITS ORNAMENT (bead godot-test1-y1o.17).
	The plinth courses, the five tiers and the five roofs are rectangular and stay
	CUBE — an oval Osaka Castle is not Osaka Castle, and a CONE roof would pull its
	edge inside the four corner kicks that are standing on it and leave them
	floating. What is round is the trim: each roof's UPSWEPT CORNER is a CONE (a
	kicked eave tip is a point, and all twenty are collide = false, which is what
	rule 5d asks of a cone), and each shachihoko is a SPHERE body with a CONE
	tail — a fish, rather than two boxes. Curving the roof PLANES needs a curve
	create_box cannot draw and more pieces than this builder emits, so it is not a
	kind and not this bead.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_GRANITE, rng, 0.04)
	var wall := _lm_shade(LM_MARBLE, rng, 0.02)
	var tile := _lm_shade(LM_COPPER, rng, 0.03).darkened(0.3)
	var gold := _lm_shade(LM_SANDSTONE, rng, 0.03)

	terrain.create_box(center + Vector3(0.0, 0.45, 0.0), Vector3(12.8, 0.9, 11.0), yaw,
			rng, block_batch, block_body, 0.0, stone)
	terrain.create_box(center + Vector3(0.0, 1.7, 0.0), Vector3(11.0, 1.6, 9.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	terrain.create_box(center + Vector3(0.0, 3.25, 0.0), Vector3(9.4, 1.5, 8.0), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# THE TENSHU. Five tiers, each narrower than the last, each roofed wider than
	# the floor it covers.
	var y := 4.0
	var ridge_w := 0.0
	for i in 5:
		var w: float = 7.0 - float(i) * 1.05
		var d: float = 6.0 - float(i) * 0.9
		terrain.create_box(center + Vector3(0.0, y + 0.95, 0.0), Vector3(w, 1.9, d), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02))
		# A dark window band, so five white boxes are five storeys and not one wall.
		terrain.create_box(center + Vector3(0.0, y + 1.25, 0.0), Vector3(w * 0.72, 0.5, d + 0.06), yaw,
				rng, block_batch, block_body, 0.0, LM_BASALT.darkened(0.15), false)
		y += 1.9
		var rw := w + 1.5
		var rd := d + 1.5
		terrain.create_box(center + Vector3(0.0, y + 0.22, 0.0), Vector3(rw, 0.45, rd), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(tile, rng, 0.03), false)
		# THE UPSWEPT CORNERS — four per roof, and the reason this is a tenshu.
		for x_side in [-1.0, 1.0]:
			for z_side in [-1.0, 1.0]:
				terrain.create_box(center + rot * Vector3(x_side * rw / 2.0, y + 0.55, z_side * rd / 2.0),
						Vector3(1.0, 0.4, 1.0), yaw, rng, block_batch, block_body, 0.0,
						_lm_shade(tile, rng, 0.04).lightened(0.1), false, ChunkBatch.BoxKind.CONE)
		y += 0.45
		ridge_w = w

	# THE SHACHIHOKO: two golden fish facing each other along the top ridge, tails up.
	for x_side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(x_side * ridge_w * 0.32, y + 0.4, 0.0), Vector3(0.85, 0.8, 0.4), yaw,
				rng, block_batch, block_body, 0.0, gold, false, ChunkBatch.BoxKind.SPHERE)
		terrain.create_box(center + rot * Vector3(x_side * (ridge_w * 0.32 + 0.35), y + 0.95, 0.0), Vector3(0.3, 0.6, 0.3), yaw,
				rng, block_batch, block_body, 0.0, gold, false, ChunkBatch.BoxKind.CONE)

	return { "radius": 8.8, "top": y + 1.25 }


static func _landmark_stave_church(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 46 — BORGUND STAVE CHURCH: three tiers of steep black timber roofs stacked
	one inside the next, a covered walkway skirting the whole thing at ground level,
	a small tower on top and dragon heads reaching off the gable ends.

	ROOFS INSIDE ROOFS is the recognition cue and there is nothing else like it in
	the registry: every other roofed entry has ONE roof over ONE volume, and this is
	a pagoda's stacking done in Norwegian pine. Each tier is three shrinking slabs
	(the same trick the Parthenon's gable uses), which gives the very steep pitch
	stave churches are known for without a single tilted box.

	THE DRAGON HEADS ARE NOT DECORATION. They are the fact — Viking prow-carvings
	nailed to a Christian church — so they get real boxes reaching out past the
	gables where they can be seen in profile, using _lm_strut for the neck.

	Everything is LM_BASALT lightened a little: stave churches are painted with pine
	tar, which is black-brown and glossy, and the Moai's basalt is the only near-
	black in the palette. The silhouettes could not be confused at any distance.

	RADIUS ARITHMETIC (declared 6.4). The widest box is the first SKIRT ROOF slab,
	centred, so 0.5*sqrt(8.4^2 + 7.4^2) = 5.59. The apse sits at z = 3.9 with
	half-depth 1.1 => 5.0, and its own roof at 5.35; a lower dragon head reaches
	3.9 + 0.9 = 4.8.
	NO ACCENT.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var timber := _lm_shade(LM_BASALT, rng, 0.03).lightened(0.1)
	var shingle := _lm_shade(LM_BASALT, rng, 0.02)

	terrain.create_box(center + Vector3(0.0, 0.2, 0.0), Vector3(7.8, 0.4, 6.8), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_STONE_GREY, rng, 0.04).darkened(0.2))

	# The ambulatory — the covered walkway that runs right round the church, and the
	# reason a stave church looks wider at the bottom than it has any right to be.
	terrain.create_box(center + Vector3(0.0, 1.55, 0.0), Vector3(6.6, 2.3, 5.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(timber, rng, 0.03))
	# The apse and the porch, front and back.
	terrain.create_box(center + rot * Vector3(0.0, 1.9, 3.9), Vector3(2.6, 3.0, 2.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(timber, rng, 0.03))
	terrain.create_box(center + rot * Vector3(0.0, 1.6, -3.6), Vector3(2.2, 2.4, 1.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(timber, rng, 0.03))
	terrain.create_box(center + rot * Vector3(0.0, 1.2, -4.2), Vector3(1.1, 2.0, 0.4), yaw,
			rng, block_batch, block_body, 0.0, LM_BASALT.darkened(0.5), false)

	# THREE TIERS OF ROOF, each a shrinking three-slab wedge over the volume below.
	var y := 2.7
	var tiers: Array = [[8.4, 7.4, 0.42, 0.0], [5.4, 4.6, 0.4, 4.4], [3.6, 3.2, 0.35, 2.8]]
	var gable_y: Array = []
	for t_variant: Variant in tiers:
		var t: Array = t_variant
		var body_w: float = t[3]
		if body_w > 0.0:
			# The wall the next roof sits on, set inside the roof below it.
			terrain.create_box(center + Vector3(0.0, y + 1.2, 0.0), Vector3(body_w, 2.4, body_w * 0.84), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(timber, rng, 0.03), false)
			y += 2.4
		gable_y.append(y + float(t[2]) * 1.5)
		for i in 3:
			var w: float = float(t[0]) - float(i) * float(t[0]) * 0.17
			var d: float = float(t[1]) - float(i) * float(t[1]) * 0.19
			terrain.create_box(center + Vector3(0.0, y + float(t[2]) / 2.0, 0.0), Vector3(w, float(t[2]), d), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(shingle, rng, 0.03), false)
			y += float(t[2])

	# The ridge turret and its spire.
	terrain.create_box(center + Vector3(0.0, y + 1.3, 0.0), Vector3(1.5, 2.6, 1.5), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(timber, rng, 0.02), false, ChunkBatch.BoxKind.CYLINDER)
	y += 2.6
	for i in 4:
		var w: float = 1.9 - float(i) * 0.42
		terrain.create_box(center + Vector3(0.0, y + 0.45, 0.0), Vector3(w, 0.9, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(shingle, rng, 0.02), false, ChunkBatch.BoxKind.CONE if i == 3 else ChunkBatch.BoxKind.CYLINDER)
		y += 0.9

	# THE DRAGON HEADS — four of them, off the gable ends of the two lower roofs,
	# reaching out and up the way a longship's prow does.
	for level in 2:
		var gy: float = gable_y[level]
		var reach: float = 3.9 - float(level) * 1.5
		for z_side in [-1.0, 1.0]:
			var root := Vector3(0.0, gy, z_side * (reach - 0.9))
			var head := Vector3(0.0, gy + 1.1, z_side * reach)
			_lm_strut(terrain, center, root, head, 0.28, _lm_shade(timber, rng, 0.02), yaw, rng, block_batch, block_body,
					false, ChunkBatch.BoxKind.CYLINDER)
			terrain.create_box(center + rot * (head + Vector3(0.0, 0.15, z_side * 0.2)), Vector3(0.34, 0.4, 0.7), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(timber, rng, 0.02), false)

	return { "radius": 6.4, "top": y }


static func _landmark_trevi(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 47 — TREVI FOUNTAIN: a palace facade with a columned centre bay, a deep
	niche with Oceanus standing in it, a reef of tumbled rock spilling out of the
	facade's foot, and a wide basin of pale water in front of the whole thing.

	THE POOL IS WHY THIS IS IN THE REGISTRY AT ALL. Every one of the other 47 places
	is a thing that stands up; this one is the only silhouette in the table that LIES
	FLAT, and a landmark you recognise by looking down at it is worth a slot on that
	basis alone. It is also the only water in the game outside the biome rivers, and
	it is honest about that: the pool is a flat tinted slab, exactly the way a river
	is a flat tinted band, with no mesh, no depth and no transparency (CLAUDE.md's
	flat-world invariant is a world rule, not a terrain rule, and a landmark that
	dug a hole would be the first thing to break it).

	THE FACADE IS A PALACE and not a temple front, which is the detail that separates
	it from the Parthenon two entries up: it is a WALL with columns applied to it,
	standing behind its own water, rather than a rectangle of free-standing columns.

	RADIUS ARITHMETIC (declared 8.6, the tightest fit of the wave because this is
	also the widest shape in it and the only one near LANDMARK_RADIUS's 9.5 ceiling).
	The furthest box is the ATTIC over the facade:
	centre at z = -3.2 with half-extents (6.9, 1.3) => sqrt(6.9^2 + 4.5^2) = 8.24.
	The facade itself is sqrt(6.6^2 + 4.3^2) = 7.88, a basin side wall sits at
	(6.0, 2.6) with half-extents (0.3, 2.7) => sqrt(6.3^2 + 5.3^2) = 8.23, and the
	front step reaches sqrt(4.5^2 + 6.5^2) = 7.90.
	NO ACCENT: the water is the bright thing here, and a glowing fountain is a
	swimming pool.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var travertine := _lm_shade(LM_SANDSTONE, rng, 0.03).lightened(0.22)
	var water := _lm_shade(LM_COPPER, rng, 0.03).lightened(0.3)

	# THE FACADE, its projecting centre bay and the attic that caps it.
	terrain.create_box(center + rot * Vector3(0.0, 4.3, -3.2), Vector3(13.2, 8.6, 2.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(travertine, rng, 0.02))
	terrain.create_box(center + rot * Vector3(0.0, 9.3, -3.2), Vector3(13.8, 1.4, 2.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(travertine, rng, 0.03).darkened(0.08))
	terrain.create_box(center + rot * Vector3(0.0, 5.0, -2.6), Vector3(6.0, 10.0, 3.0), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(travertine, rng, 0.02))
	# Four applied columns, then THE NICHE and the figure standing in it.
	for cx in [-4.6, -1.9, 1.9, 4.6]:
		terrain.create_box(center + rot * Vector3(cx, 4.3, -1.2), Vector3(0.9, 7.2, 0.9), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(travertine, rng, 0.025), true, ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(center + rot * Vector3(0.0, 4.2, -1.15), Vector3(3.6, 6.4, 0.6), yaw,
			rng, block_batch, block_body, 0.0, travertine.darkened(0.55), false)
	terrain.create_box(center + rot * Vector3(0.0, 2.6, -0.9), Vector3(1.3, 3.4, 0.85), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_MARBLE, rng, 0.02), false, ChunkBatch.BoxKind.CYLINDER)
	terrain.create_box(center + rot * Vector3(0.0, 4.6, -0.9), Vector3(0.55, 0.6, 0.55), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_MARBLE, rng, 0.02), false, ChunkBatch.BoxKind.SPHERE)

	# THE REEF: tumbled rock spilling from the facade's foot into the water. Own
	# yaws, so the bound is |offset| + half-diagonal rather than the aligned corner.
	for i in 8:
		var rx := rng.randf_range(-3.6, 3.6)
		var rz := rng.randf_range(-0.8, 1.4)
		var rs := rng.randf_range(0.9, 1.8)
		terrain.create_box(center + rot * Vector3(rx, rs * 0.42, rz), Vector3(rs * 1.2, rs * 0.9, rs),
				rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0,
				_lm_shade(LM_STONE_GREY, rng, 0.05), true, ChunkBatch.BoxKind.SPHERE)

	# THE BASIN: three rim walls (the facade is the fourth), the water, and one step
	# down to it — the step people sit on to throw the coin over their shoulder.
	terrain.create_box(center + rot * Vector3(0.0, 0.45, 5.0), Vector3(12.6, 0.9, 0.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(travertine, rng, 0.03))
	for x_side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(x_side * 6.0, 0.45, 2.6), Vector3(0.6, 0.9, 5.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(travertine, rng, 0.03))
	terrain.create_box(center + rot * Vector3(0.0, 0.55, 2.6), Vector3(11.4, 0.15, 4.8), yaw,
			rng, block_batch, block_body, 0.0, water, false)
	terrain.create_box(center + rot * Vector3(0.0, 0.175, 5.9), Vector3(9.0, 0.35, 1.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(travertine, rng, 0.04))

	return { "radius": 8.6, "top": 10.0 }
