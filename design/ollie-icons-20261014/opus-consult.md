# Ollie icon: four directions

## Is the bolt strong enough?

Yes. A bolt is a common symbol, but it fits a "do it fast" multi-tool utility. Small feature glyphs like a clipboard, mic or window would fail at 16 px. The bolt becomes Ollie's own through:
1. **Exact geometry:** use the same chunky, rounded silhouette every time, large and uncropped.
2. **Fixed pairs:** each direction gets one tile colour and one bolt colour, and they never change.
3. **No add-ons:** no letter O, rings, orbit dots or second symbol.

## Rules for all four directions

- **Bolt path:** use the exact path. Scale it evenly, with no rotation, mirroring or outer stroke. Draw rims and highlights inside the bolt's clip only, because an outer stroke fills the notches at 16 px.
- **Notches:** the two inner corners at (15.19, 8) and (9.81, 14) are what makes the shape a bolt. Check that both stay open at every size. If they close, it reads as a blob or an arrow.
- **Size and position:** make the bolt 56–62% of the tile height at 1024. The bolt is heavier at the top, so after centring its bounding box, move it down about 14–18 px. Judge the result at 64 px.
- **Framing for older macOS (.icns):** a 1024 canvas with an 824×824 tile at (100, 100) and rounded corners of about 185 px. Use the curved squircle corner shape from Apple's template, not a plain `rx`, and the template's soft shadow.
- **macOS 26 and later:** also export the background and the bolt as separate full-bleed layers so the system's Dark, Clear and Tinted modes work. A one-colour bolt layer works best for Tinted.
- **Small sizes:** make dedicated 16/32/64 renders, with @2x versions. Use a flat tile and a flat bolt with no texture, rim, sheen or noise, and make the bolt about 10% larger at 16 and 32. The bolt must contrast with the tile's average colour by at least 4.5:1.

## A — Smoke (smoky glass, matches the approved UI)

- **Tile:** linear gradient from `#2E3B3E` at the top to `#141B1D` at the bottom.
  - Smoke: radial gradient centred at 30%/22% with a 70% radius, `#4A6064` at 45% opacity fading to 0.
  - Shadow: second radial gradient at 80%/90%, `#0A0F10` at 60% opacity fading to 0.
- **Rim:** a 10 px stroke inside the tile, from white at 28% at the top to 4% at the bottom. Add a 1.5 px outer hairline in black at 45%.
- **Sheen:** soft white at 9% across the top 40% of the tile. Its lower edge must fade out with no visible horizon line.
- **Bolt:** gradient from `#F5F0E6` to `#E4DACA`. Add a 3 px white highlight at 50% along the top edges, inside the clip. Drop shadow: y +12, blur 24, black at 45%. No glow. Height 56%.
- **Small sizes:** flat tile `#1F2A2C`, flat bolt `#F5F0E6`, 1 px white rim at 18% at 32 px and none at 16 px.
- **Pitfalls:**
  - It can disappear against a dark Dock without the rim.
  - At 64 px the smoke can look dirty; halve the radial opacity there.
  - The sheen edge shows up as a line at 32 px.

## B — Ceramic (warm, tactile)

- **Change from the draft:** if the ember bolt is orange (hue around 15–25°) and the tile leans peach, this reads as the old Fredie icon with a bolt on it. Change the bolt to an oxblood glaze and the tile to a low-saturation, slightly yellow bone colour.
- **Tile:** gradient from `#F4EFE7` to `#E3DACD`.
  - Glaze highlight: radial gradient at the top left, white at 55% fading to 0.
  - Thickness: a 14 px inner rim of `#CDBFAE` at 60%, along the bottom only.
  - Speckle: small `#8A7A68` dots at 12% opacity, only at 256 px and above.
- **Bolt:** base `#A3301F`, a top-left gradient to `#C9503A`, and glaze pooling to `#5F1A10` along the inner bottom-right (10 px inner shadow, blur 14). One soft highlight on the top block, white at 35%. Height 58%.
- **Shadow:** warm `#5A3A28` at 28%, y +10, blur 18.
- **Pitfalls:** at 32 px the highlight becomes a white speck and the speckle turns to mud. Remove both at 64 px and below.

## C — Signal (flat, bold)

- **Change from the draft:** stay chartreuse, not fluorescent. Something like `#CCFF00` buzzes on screen and breaks the no-neon rule.
- **Tile:** flat `#D3EC4B`, or a nearly invisible gradient from `#DAF05A` to `#CBE341`. Add a 1 px inner stroke in black at 10% so the edge holds on light backgrounds.
- **Bolt:** flat ink `#15171B` at 62%, the largest of the four. No echo or offset shadow, because both thicken the bolt at small sizes.
- **Pitfalls:**
  - The tile edge goes weak on light wallpapers.
  - It looks less premium and less native than A.
  - In return, it's the most recognisable of the four in a Dock.

## D — Alloy → Keycap (the unexpected option)

- **Change from the draft:** plain brushed silver feels like an older macOS icon, and the inset graphite bolt loses contrast. Treat the whole tile as one key instead. That suits a keyboard-first app with a launcher, snippets, a window switcher and typing sounds, without adding a second symbol.
- **Skirt (the key's sides):** gradient from `#C7CCD1` to `#9AA1A8`, darker at the bottom.
- **Dished top face:** inset 7% on the sides, 5% at the top and 10% at the bottom so it has a lip. The face runs from `#CDD2D7` at the top to `#E4E7EA` at the bottom, which makes it look concave.
- **Brushing:** horizontal streaks at 4% opacity, only at 256 px and above.
- **Bolt:** a printed legend in solid `#23262A`, not debossed. Height 50% of the tile.
- **Small sizes:** drop the skirt and the dish; use a flat `#CDD2D6` tile with the `#23262A` bolt.
- **Pitfalls:**
  - At 32 px the dish's inner rounded square becomes a double outline.
  - Silver blends into a grey Dock.

## Comparison board

Show each direction at 1024, 128, 64, 32 and 16 px, on both a light (`#F5F5F7`) and a dark (`#1E1E1E`) background. Add a Dock row with Finder, Safari and Mail as neighbours, and put the unchanged menu bar glyph next to each.

## My pick: A, Smoke

It carries the approved Tabbie-like smoky glass into the Dock and fits the current macOS glass look. The ivory bolt has the highest contrast of the four, and it scales down cleanly to the flat 16/32 renders. If the user wants the most distinctive option over the most native one, C is the runner-up.
