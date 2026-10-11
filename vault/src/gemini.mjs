// A tiny Gemini client for the bot's AI, using the current stable model alias
// so it never breaks when Google renames versions. Retries transient 503/429.

export class Gemini {
  constructor(key, { model = "gemini-flash-latest" } = {}) {
    this.key = key;
    this.model = model;
    this.base = "https://generativelanguage.googleapis.com/v1beta";
  }

  async generate({ system, prompt, temperature = 0.8 }) {
    const body = {
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { temperature },
      safetySettings: ["HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH",
        "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT"]
        .map((category) => ({ category, threshold: "BLOCK_ONLY_HIGH" })),
    };
    for (let attempt = 0; attempt < 4; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 90_000);
      try {
        const res = await fetch(`${this.base}/models/${this.model}:generateContent`, {
          method: "POST",
          headers: { "content-type": "application/json", "x-goog-api-key": this.key },
          body: JSON.stringify(body),
          signal: controller.signal,
        });
        const json = await res.json().catch(() => ({}));
        if (res.status === 503 || res.status === 429) { await sleep((attempt + 1) * 2000); continue; }
        if (!res.ok) throw new Error(json?.error?.message || `Gemini ${res.status}`);
        const parts = json?.candidates?.[0]?.content?.parts ?? [];
        const text = parts.map((p) => p.text).filter(Boolean).join("").trim();
        if (!text) throw new Error("empty response");
        return text;
      } catch (error) {
        if (attempt === 3) throw error;
        await sleep((attempt + 1) * 2000);
      } finally {
        clearTimeout(timer);
      }
    }
    throw new Error("Gemini unavailable");
  }

  /// A single turn of a function-calling conversation. `contents` is the full
  /// Gemini content array; `tools` is a functionDeclarations list. Returns the
  /// model's content part (text or a functionCall).
  async turn({ system, contents, tools }) {
    const body = {
      systemInstruction: { parts: [{ text: system }] },
      contents,
      tools: tools ? [{ functionDeclarations: tools }] : undefined,
      generationConfig: { temperature: 0.7 },
      safetySettings: ["HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH",
        "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT"]
        .map((category) => ({ category, threshold: "BLOCK_ONLY_HIGH" })),
    };
    for (let attempt = 0; attempt < 4; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 90_000);
      try {
        const res = await fetch(`${this.base}/models/${this.model}:generateContent`, {
          method: "POST",
          headers: { "content-type": "application/json", "x-goog-api-key": this.key },
          body: JSON.stringify(body),
          signal: controller.signal,
        });
        const json = await res.json().catch(() => ({}));
        if (res.status === 503 || res.status === 429) { await sleep((attempt + 1) * 2000); continue; }
        if (!res.ok) throw new Error(json?.error?.message || `Gemini ${res.status}`);
        return json?.candidates?.[0]?.content ?? { parts: [{ text: "" }] };
      } catch (error) {
        if (attempt === 3) throw error;
        await sleep((attempt + 1) * 2000);
      } finally {
        clearTimeout(timer);
      }
    }
    throw new Error("Gemini unavailable");
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));