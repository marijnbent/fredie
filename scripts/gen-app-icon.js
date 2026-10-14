const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");
const master = path.join(root, "release/Icon.png");
const catalog = path.join(root, "Ollie/Assets.xcassets/AppIcon.appiconset");
const { images } = JSON.parse(fs.readFileSync(path.join(catalog, "Contents.json"), "utf8"));

for (const image of images) {
  const dimensions = /^(\d+)x\1$/.exec(image.size);
  const scale = /^([12])x$/.exec(image.scale);
  if (image.idiom !== "mac" || !dimensions || !scale || path.basename(image.filename) !== image.filename) {
    throw new Error("Invalid app icon catalog entry");
  }
  const pixels = Number(dimensions[1]) * Number(scale[1]);
  execFileSync("sips", ["-z", String(pixels), String(pixels), master, "--out", path.join(catalog, image.filename)], {
    stdio: "ignore",
  });
  console.log(`${image.filename}: ${pixels}x${pixels}`);
}
