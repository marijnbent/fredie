I didn't change anything in the project. I drew quick sketches of all three directions and rendered them with AppKit at 1x and 2x to check the geometry. They're scratch files in `/tmp/ollie-consult/`, and `sheet3.png` puts all three side by side.

## Why the current icon looks busy and catlike
- **Ears:** they are loops at the 45° corners of the head, which is how cat and bear ears sit.
- **Whiskers:** they cross the head outline at about x 2.6, so the edge looks knotted.
- **Mouth:** the ω-shaped mouth runs out to the cheeks. Together with whiskers, that is the cat emoji's ":3" face.
- **Nose:** it is only about 2.4pt wide, so nothing in the face reads as an otter.
- **Grid:** the 24-unit viewBox shown at 18pt makes one unit 1.5px at 2x, so no edge lands on a whole pixel. Draw in a `0 0 18 18` viewBox instead, so 1 unit = 1pt = 2px.

## 1. "Jowl Line": a restrained outline (recommended)
- **One line:** the whole head is a single continuous stroke, about 1.35pt, with round joins.
- **Crown:** flat at y≈4.1 between x 4 and 14.
- **Ears:** small bumps on the side walls, not loops at the corners. Each one leaves the side at (15.6, 5.9), reaches out to x≈17, and comes back at (16.1, 7.9); mirror it on the left. Every part of the ear must stay below the crown line.
- **No chin line:** the outline finishes as two cheek lobes centred at x 5.9 and 12.1, with their bottoms at y 14.3. They meet in a point at (9, 11.7), right under the nose. The head is widest here (x 1.5–16.5), echoing the cream cheeks on the app icon.
- **Nose:** this is the main feature. Make it about 4.4 wide and 2.9 tall, filled, sitting on that meeting point. Make it a wide, flat, rounded diamond with an almost straight top edge. In my render, a V-shaped nose pushed the face towards a pug.
- **Eyes:** dots of r 0.95 at (5.6, 7.9) and (12.4, 7.9), level with the tops of the ears.
- **Leave out** whiskers and any mouth strokes, so there are only three elements.

## 2. "Cream Cut": a solid silhouette with a cut-out muzzle
- **Head:** filled, using the same outline as direction 1.
- **Muzzle:** one cut-out shaped like a two-lobed cloud, spanning x 3.1–14.9 with its top at y≈9.3. That is at least 65% of the head's width and wider than the gap between the eyes, which is what stops it reading as a bear.
- **Open the bottom:** the cut-out must break through the chin, so the white lobes form the bottom edge and the black becomes a hood, like the chestnut fur. In my test, two enclosed cheek holes read as a monkey or raccoon mask.
- **Nose:** black, about 4.4 wide, hanging from the hood and joined to it, so it isn't a floating island.
- **Eyes:** white dots on a black face are the panda trap that sank the first version. Use cut-out happy arcs (∩) instead, at least 1.1pt thick and about 2.2 wide.
- **Weight:** keep black to about 45% of the bounding box or less. Next to line icons like Wi-Fi, a solid head looks like a hole in the menu bar.
- **Build:** make every cut-out part of one even-odd compound path, not a `<mask>`. AppKit's SVG renderer smeared my mask test into grey.

## 3. "Raft": the otter floating on its back
- **Size:** use a wider icon, `0 0 24 18`. A menu bar icon about 22pt wide is fine.
- **Pose:** belly up, head on the left, tail on the right. The tail flicks up to a sharp tip at about (23, 6.6) and must taper clearly over at least 5pt.
- **Head:** lift it above the belly with a neck notch at least 1.2pt deep. Make it at least 40% of the icon's height, with the snout pointing up and left, and an eye cut-out of at least 1.6pt.
- **Pebble:** an oval about 3.6 × 2.8, 0.6–0.8pt above the belly, held between two 1.2pt paw strokes. The pebble is the one detail tying this to the app icon, and it's the most ownable idea of the three.
- **Foot:** add one hind foot sticking up near the tail.
- **What went wrong in my sketches:** the first read as a teapot or gravy boat, with the pebble as the lid knob and the tail as the spout. The second read as a snail, or as a "Q" plus a ball. A flat underside makes it look like a boat, so avoid a water line, or keep it short and separate.

## Optical traps at 16–18px
- **Minimum sizes:** strokes at least 1.2pt, cut-outs at least 1.1pt, gaps at least 0.6pt. Anything smaller merges on a 1x external display.
- **Lines crossing the outline** (whiskers) turn into knots.
- **What each feature suggests:**

| Feature | Reads as |
|---|---|
| Ears on the corners or on top | Cat or bear |
| Ears low on the side walls | Otter or seal |
| Narrow, enclosed muzzle | Bear |
| Whiskers plus ω mouth | Cat |
| Triangle nose plus cheeks | Dog or pug |
| Two cheek holes | Monkey |
| Fat cheeks plus ears on top | Hamster |

- **Where to check:** at 1x and 2x, in light and dark menu bars, right next to the Wi-Fi and battery icons. It's a template image, so only the alpha channel counts.

## Recommendation: direction 1
- **Continuity:** the user already picked an outlined face, and this stays close to the line weight of the other menu bar icons.
- **Simplicity:** it has the fewest parts.
- **Evidence:** it was the only sketch that still read clearly at 1x.
- **Character:** it comes from the cheek lobes and the big flat nose, the same features that carry the app icon. Nothing is added on top.

Show direction 3 next to it as the wildcard if the user wants more personality. I'd only try direction 2 if direction 1 fails, because a solid face has already been rejected once.

Optional sketch, exactly as I rendered it (flatten the nose's top edge further):
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
<path fill="none" stroke="#000" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" d="M9 11.7C9.4 13.4 10.6 14.3 12.1 14.3C13.9 14.3 15.9 13.4 16.3 11.4C16.6 10.2 16.5 9 16.1 7.9C17.2 7.6 17 5.5 15.6 5.9C15.3 5.3 14.7 4.9 13.9 4.6C11.6 3.9 6.4 3.9 4.1 4.6C3.3 4.9 2.7 5.3 2.4 5.9C1 5.5 .8 7.6 1.9 7.9C1.5 9 1.4 10.2 1.7 11.4C2.1 13.4 4.1 14.3 5.9 14.3C7.4 14.3 8.6 13.4 9 11.7"/>
<path d="M6.8 9.8C6.8 9 11.2 9 11.2 9.8C11.2 10.8 9.9 11.9 9 11.9C8.1 11.9 6.8 10.8 6.8 9.8Z"/>
<circle cx="5.6" cy="7.9" r=".95"/><circle cx="12.4" cy="7.9" r=".95"/>
</svg>
```
