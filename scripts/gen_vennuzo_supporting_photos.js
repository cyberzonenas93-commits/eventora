// scripts/gen_vennuzo_supporting_photos.js
//
// Renders 10 cinematic supporting photos for Vennuzo (event discovery + ticketing
// platform) via Gemini "Nano Banana" on Vertex AI. Uses the active gcloud OAuth
// account through the gplus-admin project (no API key — the CLAUDE.md key is expired).
//
// Output: public-pages/photos/*.png
//
// Brand palette baked into every prompt:
//   near-black #060611 · periwinkle #7B8CFF · purple #B06CFF · pink #FF6B9D
//   warm accent #FFB86C · mint accent #06D6A0
//
// Run:  GOOGLE_CLOUD_PROJECT=gplus-admin node scripts/gen_vennuzo_supporting_photos.js

const https = require("https");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "gplus-admin";
const LOCATION = process.env.GOOGLE_CLOUD_LOCATION || "us-central1";
const MODEL = process.env.GEMINI_IMAGE_MODEL || "gemini-2.5-flash-image";
const OUT_DIR = path.join(__dirname, "..", "public-pages", "photos");
const CONCURRENCY = 3;

// Shared style block appended to every scene so the set reads as one campaign.
const STYLE = `
Style: photorealistic premium editorial campaign photography, NOT generic stock.
Cinematic wide 16:9 landscape frame. Shallow depth of field, crisp expressive faces,
gentle film grain, rich contrast. Color grade to the Vennuzo palette: deep near-black
#060611 shadows lifted by periwinkle #7B8CFF, electric purple #B06CFF and pink #FF6B9D
light, with restrained warm #FFB86C and mint #06D6A0 accents. Stylish, diverse, modern
young adults (include Black and mixed-race subjects prominently). Atmospheric haze and
tasteful lens flare where it fits the scene.
Absolutely no words, captions, logos, watermarks, app UI overlays, or any legible
text/screen content — typography is added later in code.`;

const TARGETS = [
  {
    file: "01_hero_concert_crowd.png",
    aspectRatio: "16:9",
    prompt: `Hero image: a euphoric live-music crowd shot from behind, hundreds of hands
raised toward a bright stage drenched in periwinkle, purple and pink beams of light,
haze and god-rays cutting across the venue. The energy is electric and joyful. Keep the
left third of the frame darker and uncluttered so headline text can be overlaid later.`,
  },
  {
    file: "02_dj_booth_night.png",
    aspectRatio: "16:9",
    prompt: `A charismatic DJ behind the decks at the peak of a club night, one hand on the
mixer and one in the air, lit from behind by purple and pink wash lights, a sea of
blurred dancing silhouettes and bokeh in front of the booth, thick atmospheric haze.`,
  },
  {
    file: "03_festival_dusk.png",
    aspectRatio: "16:9",
    prompt: `An outdoor music festival at blue-hour dusk: a wide crowd of silhouettes
facing a glowing main stage, festoon string lights overhead, a purple-to-pink gradient
sky, faint confetti and sparks drifting in the air. Expansive, cinematic, romantic.`,
  },
  {
    file: "04_friends_arriving.png",
    aspectRatio: "16:9",
    prompt: `Three stylish young friends arriving at a venue entrance at night, mid-laugh
and clearly excited, washed in periwinkle and pink neon signage glow. One holds a phone
loosely (no legible screen). Capture the anticipation of a great night out. Editorial.`,
  },
  {
    file: "05_qr_entry.png",
    aspectRatio: "16:9",
    prompt: `Close, shallow-focus shot of hands holding a smartphone up to a glowing
ticket scanner at a venue door, the phone screen a soft abstract glow with NO legible
interface, a friendly usher softly blurred behind, warm and pink neon bokeh. Premium,
the seamless moment of contactless entry.`,
  },
  {
    file: "06_rooftop_party.png",
    aspectRatio: "16:9",
    prompt: `A chic rooftop party at night: a small group of well-dressed friends with
drinks, laughing together, a glittering city skyline bokeh and warm fairy lights behind
them, the scene blending warm golden glow with cool periwinkle and pink rim light.`,
  },
  {
    file: "07_dancefloor_silhouettes.png",
    aspectRatio: "16:9",
    prompt: `Tight on a packed dancefloor: silhouettes of people dancing with motion blur,
edged by vivid pink and purple rim light, laser beams and haze slicing through the dark.
High energy, kinetic, cinematic nightlife.`,
  },
  {
    file: "08_live_band_intimate.png",
    aspectRatio: "16:9",
    prompt: `An intimate small-venue live performance: a singer at a vintage microphone
under a warm pink spotlight, a close engaged crowd softly lit in the foreground, moody
and atmospheric — the smaller, personal end of the events spectrum. Editorial.`,
  },
  {
    file: "09_confetti_celebration.png",
    aspectRatio: "16:9",
    prompt: `A pure celebration moment: two friends in the middle of a crowd, faces lit
with joy, arms up as confetti and streamers rain down, lit by purple and pink stage
light with shallow depth of field isolating them from the glowing crowd behind.`,
  },
  {
    file: "10_gallery_culture_event.png",
    aspectRatio: "16:9",
    prompt: `An upscale cultural event — a modern art gallery opening or fashion preview:
elegantly dressed, diverse guests mingling with drinks among sculptural lighting and
clean architecture, subtle periwinkle and pink accent light. Sophisticated and premium,
showing events beyond nightlife. Editorial.`,
  },
];

function getToken() {
  return execSync("/opt/homebrew/bin/gcloud auth print-access-token", {
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
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const raw = Buffer.concat(chunks);
          try {
            resolve({ status: res.statusCode, json: JSON.parse(raw.toString()), raw });
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
  const imagePart = parts.find((p) => p.inlineData?.mimeType?.startsWith("image/"));
  return imagePart ? Buffer.from(imagePart.inlineData.data, "base64") : null;
}

async function generate(target, token) {
  const url =
    `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}` +
    `/locations/${LOCATION}/publishers/google/models/${MODEL}:generateContent`;
  const fullPrompt = `${target.prompt}\n${STYLE}`;
  const base = {
    contents: [{ role: "user", parts: [{ text: fullPrompt }] }],
  };

  // First try with imageConfig (forces the 16:9 framing); fall back without it on 400.
  let res = await postJson(url, token, {
    ...base,
    generationConfig: {
      responseModalities: ["TEXT", "IMAGE"],
      imageConfig: { aspectRatio: target.aspectRatio || "16:9" },
    },
  });
  if (res.status === 400) {
    res = await postJson(url, token, {
      ...base,
      generationConfig: { responseModalities: ["TEXT", "IMAGE"] },
    });
  }
  if (res.status !== 200) {
    throw new Error(`HTTP ${res.status}: ${res.raw.toString().slice(0, 300)}`);
  }
  const buffer = imageFromResponse(res);
  if (!buffer) {
    throw new Error(`no image in response: ${JSON.stringify(res.json).slice(0, 300)}`);
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
        const out = path.join(OUT_DIR, target.file);
        fs.writeFileSync(out, buffer);
        console.log(`  ok    ${target.file.padEnd(30)} ${(buffer.length / 1024).toFixed(0)}KB`);
        results.push({ file: target.file, ok: true });
      } catch (error) {
        console.error(`  FAIL  ${target.file.padEnd(30)} ${error.message}`);
        results.push({ file: target.file, ok: false, error: error.message });
      }
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  return results;
}

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const token = getToken();
  console.log(`Rendering ${TARGETS.length} Vennuzo supporting photos -> ${OUT_DIR}\n`);
  const results = await runPool(TARGETS, token);
  const ok = results.filter((r) => r.ok).length;
  console.log(`\nDone: ${ok}/${TARGETS.length} rendered.`);
  if (ok < TARGETS.length) process.exitCode = 1;
})();
