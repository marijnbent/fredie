# Otter menu mark and app-icon variants

## 1. Making it read as an otter, not a bear, at 18pt

The current mark reads as a bear because the head is taller than it is wide, the ears sit on top and the muzzle is a separate oval.

- **Head:** make it wider than tall, about 1.35:1, with a flat crown. A bear head is round or tall.
- **Ears:** put small nubs low on the sides, roughly 10 and 2 o'clock, and sink half of each into the head outline. Ears on top read as bear or cat.
- **Muzzle:** make it the widest feature, as two lobes filling the lower 40–45% of the face. Use a wide, flat nose, not a pointed triangle.
- **Eyes:** place them high and wide apart, close to the line where the ears sit.
- **Whiskers:** if you have only one extra detail, use two short whiskers per side that cross the head outline. They do more than anything else.
- **Body:** when you show it, the long tapering tail and the floating-on-back pose identify an otter right away.

At 18pt, keep only three or four features. Check every candidate at 16px in both light and dark menu bars.

## 2. Four menu mark constructions

All four use an 18×18 viewBox (author at 36×36 for @2x) with one color as a template image. Stroked versions use a 1.5pt stroke with round caps and joins.

**A. Wide outlined face, "Whisker Face"**
- Head: a stroked flat ellipse, 16×11, centered at y≈10.
- Ears: 3pt semicircle nubs on the outline at y≈6.5, about 2pt in from each side.
- Eyes: filled dots, 2pt across, at y≈8.5, about 6pt apart.
- Muzzle: two stroked circles, r≈2.4, touching at the center line, y≈12.
- Nose: a filled rounded capsule, 3×2, where the two muzzle circles meet.
- Whiskers: two 3pt strokes per side, crossing the outline at a slight downward angle.
- Risks: the whiskers can alias into grey smudges, so snap them to the pixel grid. Too much interior stroke can fill in at 1x.

**B. Smiling solid face, "Happy Mask"**
- Head: a filled flat ellipse, 17×11.5, with notched side ears as in A.
- Muzzle: one cutout shaped like a soft "W", 9pt wide.
- Nose: a solid island inside the muzzle cutout, at least 2.5pt wide.
- Eyes: cutout upward arcs (^ ^) with a 1.5pt stroke weight. These give the happy look.
- Whiskers: optional notches in the cheek edge.
- Risks: a nose island smaller than 2.5pt disappears. The upward-arc eyes can look like closed-eye smugness, so test a variant with dot eyes and a smiling cutout.

**C. Side profile, "Peek"**
- Water: one wave stroke across the bottom at y≈15.
- Neck: a 5pt-wide column rising from the wave.
- Head: a horizontal capsule, about 11×6, at the top, with a blunt snout pointing right.
- Nose: a filled dot at the snout tip.
- Eye: a cutout or dot one-third of the way back along the head.
- Ear: a 2pt nub at the back of the crown.
- Whiskers: two short lines from the snout.
- Risks: it can read as a seal or a dog, and the ear nub and whiskers fix that. The wave line can make the mark look busy, so keep it to a single arc.

**D. Floating body, "Raft"**
- Body: the otter on its back as one horizontal capsule, about 15×5.5, lying slightly diagonal.
- Head: a 6pt circle on the left end, with one ear nub.
- Tail: tapers to a point on the right, flicked up.
- Paws: a small bump on the chest with a cutout pebble dot, about 2pt.
- Water: optionally, one ripple arc underneath.
- Risks: at 18pt it can turn into a "bean with a ball". Keep the head bigger than you think it needs to be, and make the tail taper clearly. It also has the least to tie it to the app icon's face.

**Optional E. "Curl-O"**
- The otter curls into a ring, with its head at the top and its tail tapering around to meet its chin. The shape doubles as an O for Ollie.

## 3. ImageGen character variants

Shared base for all prompts:
> *macOS app icon, single character centered on a deep ink-teal rounded square, soft studio lighting, subtle rim light, no text, no border, 1024×1024*

Shared otter anchors:
> *broad flat head wider than tall, small ears low on the sides, large cream whisker pads, fine whiskers, webbed paws, long tapered tail*

Shared negatives:
> *not a bear, not a teddy, no round ears on top of the head*

**1. Happy Pocket Otter (same family)**
> *chestnut glossy vinyl sea otter toy, eyes closed in upturned crescents, wide open smile showing a small pink tongue, cheeks pushed up into the whisker pads, head tilted 10°, both paws hugging a grey pebble to the chest, whiskers fanned out*

Keep the material, colors and framing of the installed icon so this can work as a direct swap.

**2. Sleek Otter (distinctly otter)**
> *slender river-otter character in matte soft-touch ceramic, warm dark brown with a cream throat and muzzle, long body in a curious upright three-quarter stance, tail curving around the front of the frame, flat head, glossy dark eyes, alert friendly half-smile, minimal designer-toy styling*

This one leans on proportions rather than chubbiness, which pushes it furthest from the bear reading.

**3. Floating Otter, alternate pose and style**
> *top-down view of a sea otter floating on its back, paws on its belly holding a pebble, tail extended, eyes softly closed with a content smile, concentric ripple rings in the water around it, rendered as layered smoky translucent glass with gentle refraction, warm chestnut tones glowing through cool teal glass*

This ties the icon to Ollie's smoky glass UI, and the pose matches menu candidate D.

**Optional 4. Mischief**
> *same vinyl family as variant 1, one-eye wink, crooked grin, pebble balanced on the nose*

## Recommendation

Pair menu mark A or B with app variant 1, so the face carries through from icon to menu bar. If you want the strongest otter silhouette, pair menu mark D with app variant 3.
