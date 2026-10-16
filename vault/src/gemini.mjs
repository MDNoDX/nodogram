// Gemini client for the bot's AI.
//
// Free-tier reality (2026): a new API key can only call the newest flash model
// (e.g. gemini-flash-latest → gemini-3.8-flash), capped at ~20 requests/day.
// So we (a) accept several keys and rotate to the next the instant one is
// quota-exhausted, (b) try a short list of models, (c) never burn long retries
// on a 429 — that's a daily cap, not a blip — and (d) surface a clear quota
// error the bot can explain, instead of a vague "unavailable".

const MODELS = ["gemini-flash-lite-latest", "gemini-flash-latest"];
const IMAGE_MODELS = ["gemini-2.5-flash-image", "gemini-3.1-flash-image"];

export class QuotaExceeded extends Error {
  constructor(retryAfter) { super("quota"); this.name = "QuotaExceeded"; this.retryAfter = retryAfter; }
}

export class Gemini {
  constructor(keys, { models = MODELS } = {}) {
    this.keys = (Array.isArray(keys) ? keys : [keys]).map((k) => String(k).trim()).filter(Boolean);
    this.models = models;
    this.base = "https://generativelanguage.googleapis.com/v1beta";
    this.keyIndex = 0;   // rotate start point so load spreads across keys
  }

  get hasKey() { return this.keys.length > 0; }

  async generate({ system, prompt, temperature = 0.8 }) {
    const content = await this.request({
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { temperature },
    });
    const text = (content.parts || []).map((p) => p.text).filter(Boolean).join("").trim();
    if (!text) throw new Error("empty response");
    return text;
  }

  async turn({ system, contents, tools }) {
    return this.request({
      systemInstruction: { parts: [{ text: system }] },
      contents,
      tools: tools ? [{ functionDeclarations: tools }] : undefined,
      generationConfig: { temperature: 0.7 },
    });
  }

  /// Generates an image from a text prompt. Returns { mime, data (base64) }.
  /// Rotates keys/models on 429 like request(); throws QuotaExceeded if all
  /// keys are out of image quota.
  async image(prompt) {
    if (!this.hasKey) throw new Error("no API key");
    const body = {
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ["IMAGE"] },
    };
    let quotaRetry = null, lastError = null;
    const n = this.keys.length;
    for (let ki = 0; ki < n; ki++) {
      const key = this.keys[(this.keyIndex + ki) % n];
      for (const model of IMAGE_MODELS) {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 90_000);
        try {
          const res = await fetch(`${this.base}/models/${model}:generateContent`, {
            method: "POST",
            headers: { "content-type": "application/json", "x-goog-api-key": key },
            body: JSON.stringify(body), signal: controller.signal,
          });
          const json = await res.json().catch(() => ({}));
          if (res.status === 429) { quotaRetry = quotaRetry ?? retryFrom(json); break; }
          if (res.status === 404) { lastError = new Error("image model unavailable"); continue; }
          if (!res.ok) { lastError = new Error(json?.error?.message || `Gemini ${res.status}`); continue; }
          const parts = json?.candidates?.[0]?.content?.parts ?? [];
          const img = parts.find((p) => p.inlineData);
          if (img) { this.keyIndex = (this.keyIndex + ki) % n; return { mime: img.inlineData.mimeType || "image/png", data: img.inlineData.data }; }
          lastError = new Error(parts.find((p) => p.text)?.text?.slice(0, 120) || "no image returned");
        } catch (error) {
          lastError = error;
        } finally { clearTimeout(timer); }
      }
      if (quotaRetry) continue;   // this key capped → next key
    }
    if (quotaRetry !== null) throw new QuotaExceeded(quotaRetry);
    throw lastError || new Error("image generation failed");
  }

  /// Tries each (key × model) combination. 503 is a brief blip → one short
  /// retry. 429 means that key is out of daily quota → move on immediately.
  /// Returns the model content part; throws QuotaExceeded if every key is
  /// capped, or a plain Error for anything else.
  async request(body) {
    if (!this.hasKey) throw new Error("no API key");
    body.safetySettings = ["HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH",
      "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT"]
      .map((category) => ({ category, threshold: "BLOCK_ONLY_HIGH" }));

    let quotaRetry = null;
    let lastError = null;
    const n = this.keys.length;
    for (let ki = 0; ki < n; ki++) {
      const key = this.keys[(this.keyIndex + ki) % n];
      for (const model of this.models) {
        for (let attempt = 0; attempt < 2; attempt++) {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 60_000);
          try {
            const res = await fetch(`${this.base}/models/${model}:generateContent`, {
              method: "POST",
              headers: { "content-type": "application/json", "x-goog-api-key": key },
              body: JSON.stringify(body),
              signal: controller.signal,
            });
            const json = await res.json().catch(() => ({}));
            if (res.status === 429) {        // daily quota for this key — skip it
              quotaRetry = quotaRetry ?? retryFrom(json);
              break;
            }
            if (res.status === 503) { await sleep(1500); continue; }   // transient blip
            if (res.status === 404) { lastError = new Error(json?.error?.message || "model 404"); break; } // try next model
            if (!res.ok) { lastError = new Error(json?.error?.message || `Gemini ${res.status}`); break; }
            // Success → make this key the preferred start next time.
            this.keyIndex = (this.keyIndex + ki) % n;
            return json?.candidates?.[0]?.content ?? { parts: [{ text: "" }] };
          } catch (error) {
            lastError = error;
            if (attempt === 0) { await sleep(1200); continue; }
          } finally {
            clearTimeout(timer);
          }
        }
        if (quotaRetry) break;   // this key is capped on the primary model → next key
      }
    }
    if (quotaRetry !== null) throw new QuotaExceeded(quotaRetry);
    throw lastError || new Error("Gemini unavailable");
  }
}

function retryFrom(json) {
  const detail = (json?.error?.details || []).find((d) => d["@type"]?.includes("RetryInfo"));
  const secs = detail?.retryDelay ? parseInt(detail.retryDelay, 10) : null;
  if (!secs || Number.isNaN(secs)) return "about a day";
  const h = Math.floor(secs / 3600), m = Math.round((secs % 3600) / 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
