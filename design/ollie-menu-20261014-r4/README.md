# Ollie menu icon refinement

Refinement of the Whiskers SVG shipped in build 31. The Happy Pocket app icon remains the reference.

- **A — Cheeks:** calm eyes, broad nose, two cheek lobes forming the lower contour. Selected for build 33.
- **B — Happy:** the same contour with smiling eyes, matching the app mascot's expression. Shipped in build 32.

Open `index.html` to select a version, compare the previous mark, and switch between 16, 18 and 20 pixels. Both menu appearances are visible together. A is selected by default.

The candidates use an 18 × 18 point canvas, a 1.25 point outline, solid black paint and transparent space. They have no masks, filters, embedded images, whisker crossings or separate mouth strokes. `a-cheeks.svg` is copied to `Ollie/Assets.xcassets/MenuBarIcon.imageset/otter.svg`; the asset catalog retains vector preservation and template rendering.

The comparison was checked at 728 and 360 pixels, with selection and sizing controls exercised. Both SVGs parsed successfully and rendered through AppKit at 18 and 36 pixels without opening app windows.

`opus-consult.md` records the advisory review. `sketches/` preserves the rejected intermediate face, silhouette and tail directions. The primary agent drew and refined the final candidates; the review's grid alignment claim was not used as a correctness requirement.
