// scripts/gen_vennuzo_visual_pack.js
//
// Generates a reusable Vennuzo visual system pack with Gemini on Vertex AI.
// Uses the active gcloud OAuth account and writes assets to Flutter, Studio,
// and static public-page folders so app and website share one art direction.
//
// Run: GOOGLE_CLOUD_PROJECT=gplus-admin node scripts/gen_vennuzo_visual_pack.js

const https = require("https");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "gplus-admin";
const LOCATION = process.env.GOOGLE_CLOUD_LOCATION || "us-central1";
const MODEL = process.env.GEMINI_IMAGE_MODEL || "gemini-2.5-flash-image";
const ROOT = path.join(__dirname, "..");
const OUT_DIRS = [
  path.join(ROOT, "assets", "visuals"),
  path.join(ROOT, "studio", "public", "visuals"),
  path.join(ROOT, "public-pages", "visuals"),
];
const CONCURRENCY = Number(process.env.GEMINI_IMAGE_CONCURRENCY || 2);

const STYLE = `
Art direction: Vennuzo premium event universe inspired by the supplied logo:
near-black space depth, glassy iridescent ribbons, cyan #6EEBFF, periwinkle
#7B8CFF, violet #8A5CFF, magenta #FF5CCB, warm peach #FFB86C, and mint
#06D6A0. Premium editorial, cinematic, sophisticated, energetic, inclusive.
Show real event contexts across nightlife, corporate, marketing, church,
community, culture, food, sports, workshops, and creator operations.
Absolutely no G+, GPlus, Eventora, third-party branding, visible words, labels,
watermarks, logos, fake UI text, or readable screens. Leave clean darker areas
where product text can be overlaid later.`;

const TARGETS = [
  {
    file: "visual_explore_spotlight.png",
    aspectRatio: "16:9",
    prompt: `Marketplace spotlight hero: a premium Ghana city night event moment,
diverse crowd arriving at a beautiful venue, iridescent glass light trails in the
air, energetic but not chaotic, clear dark lower-left copy space.`,
  },
  {
    file: "visual_onboarding_preferences.png",
    aspectRatio: "9:16",
    prompt: `Vertical onboarding collage without hard dividers: elegant glimpses of
nightlife, corporate conference, church gathering, art opening, food festival,
fitness event, and workshop, united by Vennuzo iridescent glass ribbons and dark
cosmic atmosphere. Human, warm, aspirational.`,
  },
  {
    file: "visual_creator_profile.png",
    aspectRatio: "16:9",
    prompt: `Creator profile cover: event organizer reviewing beautiful event photos on
a tablet beside printed photo proofs and camera gear, with a lively venue blurred
behind. Premium creator brand energy, no readable screens.`,
  },
  {
    file: "visual_organizer_ops.png",
    aspectRatio: "16:9",
    prompt: `Organizer operations command room: check-in desk, ticket scanner glow,
team coordinating admissions and guest flow, polished but realistic event
production, no readable screens, dark elegant copy space on the left.`,
  },
  {
    file: "visual_checkout_ticket.png",
    aspectRatio: "16:9",
    prompt: `Ticket checkout and delivery moment: close-up of a sleek phone, QR-like
abstract glow, mobile money/payment receipt vibe, hands exchanging confidence at
venue entry, premium and trustworthy, no readable UI or QR data.`,
  },
  {
    file: "visual_campaign_reach.png",
    aspectRatio: "16:9",
    prompt: `Paid promotion reach visual: abstract audience network made from real
eventgoers, opt-in signal paths, push and SMS represented as soft glowing pulses,
ethical targeted marketing feeling, no icons with text or readable UI.`,
  },
  {
    file: "visual_wallet_services.png",
    aspectRatio: "16:9",
    prompt: `Creator wallet and paid services visual: premium table setup with event
flyer proofs, card and mobile money glow, elegant payment confidence, subtle
iridescent ribbons, no currency text, no readable receipts.`,
  },
  {
    file: "visual_admin_console.png",
    aspectRatio: "16:9",
    prompt: `Platform admin console mood image: calm operations desk with blurred
analytics monitors, safety/support workflow, premium cyber-event lighting, human
operator presence, no readable dashboard content.`,
  },
  {
    file: "visual_support_chat.png",
    aspectRatio: "16:9",
    prompt: `Support chat visual: friendly support specialist helping an eventgoer,
soft message bubbles as abstract light only, reassuring premium service desk,
no readable chat text.`,
  },
  {
    file: "visual_cosmic_texture.png",
    aspectRatio: "16:9",
    prompt: `Pure reusable background texture: dark starfield depth with glossy
iridescent glass ribbons echoing the Vennuzo V-wave logo, elegant, high contrast,
no letters, no symbols, no logo, no text.`,
  },
];

const requestedTargets = new Set(
  (process.env.VENNUZO_VISUAL_TARGETS || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean),
);
const activeTargets = requestedTargets.size
  ? TARGETS.filter((target) => requestedTargets.has(target.file))
  : TARGETS;

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
  const body = {
    contents: [{ role: "user", parts: [{ text: `${target.prompt}\n${STYLE}` }] }],
    generationConfig: {
      responseModalities: ["TEXT", "IMAGE"],
      imageConfig: { aspectRatio: target.aspectRatio },
    },
  };
  let res = await postJson(url, token, body);
  if (res.status === 400) {
    res = await postJson(url, token, {
      contents: body.contents,
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
        for (const dir of OUT_DIRS) {
          fs.mkdirSync(dir, { recursive: true });
          fs.writeFileSync(path.join(dir, target.file), buffer);
        }
        console.log(`  ok    ${target.file.padEnd(34)} ${(buffer.length / 1024).toFixed(0)}KB`);
        results.push({ file: target.file, ok: true });
      } catch (error) {
        console.error(`  FAIL  ${target.file.padEnd(34)} ${error.message}`);
        results.push({ file: target.file, ok: false, error: error.message });
      }
    }
  }
  await Promise.all(Array.from({ length: Math.max(CONCURRENCY, 1) }, worker));
  return results;
}

(async () => {
  OUT_DIRS.forEach((dir) => fs.mkdirSync(dir, { recursive: true }));
  const token = getToken();
  console.log(`Rendering ${activeTargets.length} Vennuzo visuals with ${MODEL}`);
  OUT_DIRS.forEach((dir) => console.log(`  -> ${dir}`));
  console.log("");
  const results = await runPool(activeTargets, token);
  const ok = results.filter((result) => result.ok).length;
  console.log(`\nDone: ${ok}/${activeTargets.length} rendered.`);
  if (ok < activeTargets.length) process.exitCode = 1;
})();
