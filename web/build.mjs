// Builds the static web app into web/dist.
// Shares catalog.json and the picture questions with the iOS app, but never ships
// the third-party press photos (credit "©"): those questions link to the BAMF PDF instead.
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = dirname(fileURLToPath(import.meta.url));
const root = join(web, "..");
const resources = join(root, "Sources/EinbuergerungTrainer/Resources");
const dist = join(web, "dist");

rmSync(dist, { recursive: true, force: true });
mkdirSync(join(dist, "img"), { recursive: true });
cpSync(join(web, "src"), dist, { recursive: true });
cpSync(join(root, "Assets/logo.svg"), join(dist, "logo.svg"));

const catalog = JSON.parse(readFileSync(join(resources, "catalog.json"), "utf8"));
let photos = 0, pictures = 0;
for (const q of catalog.questions) {
  if (!q.image) continue;
  if ((q.credit || "").startsWith("©")) {
    q.image = null;
    q.photo = true;
    photos++;
  } else {
    cpSync(join(resources, q.image), join(dist, "img", q.image));
    pictures++;
  }
}
writeFileSync(join(dist, "catalog.json"), JSON.stringify(catalog));

// Version the JS/CSS URLs so browsers pick up new deploys immediately.
const hash = createHash("sha256")
  .update(readFileSync(join(dist, "app.js"))).update(readFileSync(join(dist, "styles.css")))
  .update(JSON.stringify(catalog)).digest("hex").slice(0, 10);
const html = readFileSync(join(dist, "index.html"), "utf8")
  .replace('href="styles.css"', `href="styles.css?v=${hash}"`)
  .replace('src="app.js"', `src="app.js?v=${hash}"`);
writeFileSync(join(dist, "index.html"), html);
const app = readFileSync(join(dist, "app.js"), "utf8").replace('fetch("catalog.json")', `fetch("catalog.json?v=${hash}")`);
writeFileSync(join(dist, "app.js"), app);
writeFileSync(join(dist, "_headers"), "/\n  Cache-Control: no-cache\n/index.html\n  Cache-Control: no-cache\n");

// Home-screen icon for iOS Safari.
const icon = join(root, "Assets/AppIcon.png");
if (existsSync(icon)) {
  try { execFileSync("sips", ["-Z", "180", icon, "--out", join(dist, "icon-180.png")], { stdio: "ignore" }); }
  catch { cpSync(icon, join(dist, "icon-180.png")); }
}

console.log(`Built web/dist: ${catalog.questions.length} questions, ${pictures} pictures, ${photos} press photos left out.`);
