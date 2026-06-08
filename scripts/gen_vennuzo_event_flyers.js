// scripts/gen_vennuzo_event_flyers.js
//
// Generates premium seeded-event flyer artwork with Gemini on Vertex AI.
// Uses the active gcloud OAuth account and writes app/public/studio assets.
//
// Run:
//   GOOGLE_CLOUD_PROJECT=gplus-admin node scripts/gen_vennuzo_event_flyers.js

const https = require("https");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "gplus-admin";
const LOCATION = process.env.GOOGLE_CLOUD_LOCATION || "us-central1";
const MODEL = process.env.GEMINI_IMAGE_MODEL || "gemini-2.5-flash-image";
const GCLOUD_BIN = process.env.GCLOUD_BIN || "/opt/homebrew/bin/gcloud";
const ROOT = path.join(__dirname, "..");
const OUT_DIRS = [
  path.join(ROOT, "assets", "event_flyers"),
  path.join(ROOT, "studio", "public", "event_flyers"),
  path.join(ROOT, "public-pages", "event_flyers"),
];
const CONCURRENCY = Number(process.env.GEMINI_IMAGE_CONCURRENCY || 2);

const STYLE = `
Use case: ads-marketing.
Asset type: 9:16 premium event-poster background art for Vennuzo seeded events.
This is NOT the finished typographic flyer. It is the full-bleed visual layer
behind app-rendered text.
Art direction: 10/10 cinematic Ghana event poster background. Premium, modern,
high-fashion editorial energy with real human presence, dramatic lighting,
layered depth, subtle Vennuzo iridescent accents, refined composition, and
generous darker copy-safe space where Flutter will render typography later.
Palette language: deep near-black #060611, cyan #6EEBFF, periwinkle #7B8CFF,
violet #8A5CFF, magenta #FF5CCB, warm peach #FFB86C, and mint #06D6A0.
Critical text rule: the image must contain ZERO typography. No readable words,
letters, numbers, placeholder headlines, title text, logos, watermarks, venue
signage, fake brand marks, QR codes, or app UI. Do not write Vennuzo. Do not
write headline. Do not render any poster text at all.
Composition: full-bleed vertical poster background, no letterboxing, no framed
landscape image inside the vertical canvas, no black bars. Strong focal subject,
premium negative space, works when cropped into app cards and detail heroes with
a dark bottom scrim.
Avoid: generic stock-photo look, flat gradients, clip art, messy crowds, warped
typography, unrelated brands, low-resolution texture, cartoon styling.`;

const TARGETS = [
  {
    file: "qa_featured_map_night.png",
    aspectRatio: "9:16",
    prompt: `QA Map Night at Front/Back Accra. Create a full-height premium
nightlife event-poster background for a location-aware map discovery test night:
stylish Accra crowd arriving at an iconic members-club entrance, subtle glowing
map-route lines, phone check-in glow, warm courtyard shadows, cyan and magenta
rim light, high-end social energy, intimate but electric.`,
  },
  {
    file: "qa_recurring_workshop.png",
    aspectRatio: "9:16",
    prompt: `QA Weekly Creator Mixer at Impact Hub Accra. Create a full-height
premium creator-workshop event-poster background: modern coworking atrium,
creative founders, laptops and cameras, soft presentation glow, collaborative
circle, mint and periwinkle light accents, optimistic weekly community energy,
polished and editorial.`,
  },
  {
    file: "event_test_drive.png",
    aspectRatio: "9:16",
    prompt: `Tech startup demo event at a premium demo hall in Accra.
Create a full-height sleek product-demo night: elegant check-in desk, phone ticket glow,
abstract dashboard light, founders and guests moving through a polished event
space. Futuristic but warm, confident, premium SaaS launch atmosphere.`,
  },
  {
    file: "event_after_dark.png",
    aspectRatio: "9:16",
    prompt: `Ticketed late-night founder and creator music event at a premium hall in
Airport City Accra. Create a dramatic full-height nightlife background:
VIP lounge energy, headline stage beams, stylish crowd silhouettes, jewel-toned
smoke, premium bottle-service glow, music intensity without chaos.`,
  },
  {
    file: "event_rooftop.png",
    aspectRatio: "9:16",
    prompt: `Golden-hour rooftop culture gathering at an Accra skydeck. Create a
full-height rooftop culture background: open mic setup, painterly art textures, creator booths,
city skyline, warm sunset washing into electric night accents. Community-led,
creative, airy, sophisticated, optimistic.`,
  },
  {
    file: "event_market.png",
    aspectRatio: "9:16",
    prompt: `Sunday Loop Market at Cantonments Yard, Accra. Create a refined
neighborhood market poster: vendor tables, handmade goods, fresh food, acoustic
music corner, families and stylish shoppers, leafy daylight with iridescent
Vennuzo light ribbons. Friendly, premium, recurring Sunday ritual.`,
  },
  {
    file: "event_private.png",
    aspectRatio: "9:16",
    prompt: `Investor Listening Session at Embassy House, private invite-only Accra
event. Create an intimate executive listening-room poster: plush seating,
beautiful low light, acoustic performance setup, discreet panel conversation,
champagne-glass highlights, invitation-only restraint, luxurious and quiet.`,
  },
];

const requestedTargets = new Set(
  (process.env.VENNUZO_EVENT_FLYER_TARGETS || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean),
);
const activeTargets = requestedTargets.size
  ? TARGETS.filter((target) => requestedTargets.has(target.file))
  : TARGETS;

function getToken() {
  return execSync(`${GCLOUD_BIN} auth print-access-token`, {
    encoding: "utf8",
  }).trim();
}

function postJson(url, token, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = JSON.stringify(body);
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(data),
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const raw = Buffer.concat(chunks);
          try {
            resolve({
              status: res.statusCode,
              json: JSON.parse(raw.toString()),
              raw,
            });
          } catch (_) {
            resolve({ status: res.statusCode, json: null, raw });
          }
        });
      },
    );
    req.on("error", reject);
    req.write(data);
    req.end();
  });
}

function imageFromResponse(res) {
  const parts = res.json?.candidates?.[0]?.content?.parts ?? [];
  const imagePart = parts.find((part) =>
    part.inlineData?.mimeType?.startsWith("image/"),
  );
  return imagePart ? Buffer.from(imagePart.inlineData.data, "base64") : null;
}

async function generate(target, token) {
  const url =
    `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}` +
    `/locations/${LOCATION}/publishers/google/models/${MODEL}:generateContent`;
  const body = {
    contents: [
      { role: "user", parts: [{ text: `${target.prompt}\n${STYLE}` }] },
    ],
    generationConfig: {
      responseModalities: ["TEXT", "IMAGE"],
      imageConfig: { aspectRatio: target.aspectRatio },
      temperature: 1.0,
    },
  };
  let res = await postJson(url, token, body);
  if (res.status === 400) {
    res = await postJson(url, token, {
      contents: body.contents,
      generationConfig: {
        responseModalities: ["TEXT", "IMAGE"],
        temperature: 1.0,
      },
    });
  }
  if (res.status !== 200) {
    throw new Error(`HTTP ${res.status}: ${res.raw.toString().slice(0, 300)}`);
  }
  const buffer = imageFromResponse(res);
  if (!buffer) {
    throw new Error(
      `no image in response: ${JSON.stringify(res.json).slice(0, 300)}`,
    );
  }
  return buffer;
}

async function runPool(targets, token) {
  const queue = [...targets];
  const results = [];
  async function worker() {
    while (queue.length) {
      const target = queue.shift();
      try {
        const buffer = await generate(target, token);
        for (const dir of OUT_DIRS) {
          fs.mkdirSync(dir, { recursive: true });
          fs.writeFileSync(path.join(dir, target.file), buffer);
        }
        console.log(
          `  ok    ${target.file.padEnd(28)} ${(buffer.length / 1024).toFixed(
            0,
          )}KB`,
        );
        results.push({ file: target.file, ok: true });
      } catch (error) {
        console.error(
          `  FAIL  ${target.file.padEnd(28)} ${error.message}`,
        );
        results.push({ file: target.file, ok: false, error: error.message });
      }
    }
  }
  await Promise.all(
    Array.from({ length: Math.max(CONCURRENCY, 1) }, worker),
  );
  return results;
}

(async () => {
  OUT_DIRS.forEach((dir) => fs.mkdirSync(dir, { recursive: true }));
  const token = getToken();
  console.log(`Rendering ${activeTargets.length} seeded event flyers with ${MODEL}`);
  OUT_DIRS.forEach((dir) => console.log(`  -> ${dir}`));
  console.log("");
  const results = await runPool(activeTargets, token);
  const ok = results.filter((result) => result.ok).length;
  console.log(`\nDone: ${ok}/${activeTargets.length} rendered.`);
  if (ok < activeTargets.length) process.exitCode = 1;
})();
