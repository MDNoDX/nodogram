// Talks to the Nodogram app's local control server (127.0.0.1:47824) for live
// data only a logged-in session can give: global search, a person's shared
// groups and activity, and the owner's own account picture. When the app is
// closed the calls fail fast and Nodik falls back to its own stored data.

const APP = "http://127.0.0.1:47824";

export class AppBridge {
  constructor(token) { this.token = token; }

  async get(path) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12_000);
    try {
      const res = await fetch(APP + path, {
        headers: { authorization: this.token },
        signal: controller.signal,
      });
      if (!res.ok) return { ok: false, error: `app returned ${res.status}` };
      return await res.json();
    } catch {
      return { ok: false, offline: true, error: "Nodogram app is closed — open it on the Mac for live group/search data." };
    } finally {
      clearTimeout(timer);
    }
  }

  async ping() { return this.get("/ping"); }
  async search(q) { return this.get("/search?q=" + encodeURIComponent(q)); }
  async info(q) { return this.get("/info?q=" + encodeURIComponent(q)); }
  async resolve(q) { return this.get("/resolve?q=" + encodeURIComponent(q)); }
  async myInfo() { return this.get("/myinfo"); }
}
