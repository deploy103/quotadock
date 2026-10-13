const { test } = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const source = fs.readFileSync(`${__dirname}/app.js`, "utf8");
class Element {
  constructor(tag = "div") {
    this.tag = tag;
    this.children = [];
    this.textContent = "";
    this.value = "";
    this.events = {};
    this.attrs = {};
  }
  append(...children) {
    this.children.push(...children);
  }
  replaceChildren(...children) {
    this.children = children;
  }
  setAttribute(key, value) {
    this.attrs[key] = value;
  }
  addEventListener(key, fn) {
    this.events[key] = fn;
  }
  fire(key) {
    return this.events[key]({ preventDefault() {} });
  }
}
function start(search = "") {
  const ids = Object.fromEntries(
    [
      "auto-refresh",
      "providers",
      "mode",
      "refresh",
      "disconnect",
      "updated",
      "status",
      "connection-message",
      "connect-form",
      "endpoint",
      "token",
    ].map((id) => [id, new Element()]),
  );
  const storage = new Map(),
    calls = [];
  let interval, response, deadline;
  const document = {
    hidden: false,
    events: {},
    addEventListener(key, fn) {
      this.events[key] = fn;
    },
    getElementById: (id) => ids[id],
    createElement: (tag) => new Element(tag),
    querySelector: () => new Element(),
  };
  vm.runInNewContext(source, {
    document,
    location: { search, protocol: "https:", origin: "https://dashboard.test" },
    URL,
    URLSearchParams,
    Intl,
    Date,
    AbortController,
    TextDecoder,
    sessionStorage: {
      getItem: (k) => storage.get(k),
      setItem: (k, v) => storage.set(k, v),
      removeItem: (k) => storage.delete(k),
    },
    setInterval: (fn, ms) => {
      assert.equal(ms, 60000);
      interval = fn;
      return 1;
    },
    clearInterval() {
      interval = undefined;
    },
    setTimeout: (fn, ms) => {
      assert.equal(ms, 15000);
      deadline = fn;
      return 1;
    },
    clearTimeout() { deadline = undefined; },
    fetch: async (url, options) => {
      calls.push({ url, options });
      if (response instanceof Error) throw response;
      if (typeof response === "function") return response();
      return new Response(JSON.stringify(response));
    },
  });
  return {
    ids,
    storage,
    calls,
    document,
    tick: () => interval?.(),
    expire: () => deadline?.(),
    reply: (value) => {
      response = value;
    },
  };
}
const descendants = (el) => [el, ...el.children.flatMap(descendants)];
const text = (el) =>
  descendants(el)
    .map((e) => e.textContent)
    .join(" ");
const settle = () => new Promise((resolve) => setImmediate(resolve));
test("unpaired and demo stay distinct; unknown Grok has no bar", () => {
  const plain = start();
  assert.equal(plain.calls.length, 0);
  assert.equal(plain.ids.refresh.disabled, true);
  assert.equal(plain.ids.providers.children.length, 4);
  const demo = start("?demo=1");
  assert.match(demo.ids.mode.textContent, /DEMO/);
  assert.equal(demo.calls.length, 0);
  assert.equal(
    descendants(demo.ids.providers).filter((e) => e.tag === "progress").length,
    6,
  );
  assert.equal(
    descendants(demo.ids.providers.children[3]).filter(
      (e) => e.tag === "progress",
    ).length,
    0,
  );
  demo.ids.refresh.fire("click");
  assert.match(demo.ids.mode.textContent, /DEMO/);
});
test("pair, refresh, clamp, preserve stale data, disconnect and reject HTTP", async () => {
  const app = start();
  const { ids } = app;
  const secret = "b".repeat(64);
  ids.endpoint.value = "http://bridge.test";
  ids.token.value = secret;
  ids["connect-form"].fire("submit");
  assert.equal(app.calls.length, 0);
  ids.endpoint.value = "https://other.test";
  ids["connect-form"].fire("submit");
  assert.equal(app.calls.length, 0);
  const observedAt = new Date().toISOString();
  app.reply({
    schemaVersion: 1,
    demo: true,
    generatedAt: observedAt,
    providers: [
      {
        id: "claude",
        plan: "Max",
        state: "available",
        source: "demo",
        observedAt,
        windows: [
          { label: "Session", remainingPercent: 120, resetsAt: null },
          { label: "Weekly", remainingPercent: 0, resetsAt: null },
        ],
      },
    ],
  });
  ids.endpoint.value = "https://dashboard.test";
  ids["connect-form"].fire("submit");
  await settle();
  assert.equal(app.calls[0].url, "https://dashboard.test/v1/snapshot");
  assert.equal(app.calls[0].options.headers.Authorization, `Bearer ${secret}`);
  assert.equal(ids.token.value, "");
  assert.equal(app.storage.get("quotadock.token"), secret);
  assert.ok(!text(ids.providers).includes(secret));
  assert.deepEqual(
    descendants(ids.providers)
      .filter((e) => e.tag === "progress")
      .map((e) => e.value),
    [100, 0],
  );
  assert.doesNotMatch(text(ids.providers), /STALE/);
  app.reply(new Error("private diagnostic"));
  app.tick();
  await settle();
  assert.match(text(ids.providers), /DEMO · STALE/);
  assert.match(text(ids.providers), /100%/);
  assert.doesNotMatch(
    ids["connection-message"].textContent,
    /private diagnostic/,
  );
  ids.disconnect.fire("click");
  assert.equal(app.storage.size, 0);
  assert.equal(ids.refresh.disabled, true);
  assert.doesNotMatch(text(ids.providers), /100%/);
});
test("foreground auto refresh defaults on; manual and hidden states stop requests", async () => {
  const app = start(),
    { ids, document } = app;
  assert.equal(ids["auto-refresh"].checked, true);
  app.reply({
    schemaVersion: 1,
    demo: false,
    generatedAt: new Date().toISOString(),
    providers: [],
  });
  ids.endpoint.value = "https://dashboard.test";
  ids.token.value = "c".repeat(64);
  ids["connect-form"].fire("submit");
  await settle();
  app.tick();
  await settle();
  assert.equal(app.calls.length, 2);
  ids["auto-refresh"].checked = false;
  ids["auto-refresh"].fire("change");
  app.tick();
  assert.equal(app.calls.length, 2);
  ids.refresh.fire("click");
  await settle();
  assert.equal(app.calls.length, 3);
  ids["auto-refresh"].checked = true;
  ids["auto-refresh"].fire("change");
  document.hidden = true;
  document.events.visibilitychange();
  app.tick();
  ids.refresh.fire("click");
  assert.equal(app.calls.length, 3);
  document.hidden = false;
  document.events.visibilitychange();
  await settle();
  assert.equal(app.calls.length, 4);
  ids.disconnect.fire("click");
  app.tick();
  assert.equal(app.calls.length, 4);
});
const snapshot = () => ({
  schemaVersion: 1, demo: false, generatedAt: new Date().toISOString(),
  providers: [{
    id: "claude", plan: "Max", state: "available", source: "codexbar",
    observedAt: new Date().toISOString(),
    windows: [{ label: "Session", remainingPercent: 42, resetsAt: null }],
  }],
});
function pair(app) {
  app.ids.endpoint.value = "https://dashboard.test";
  app.ids.token.value = "d".repeat(64);
  app.ids["connect-form"].fire("submit");
}
test("byte bound cancels oversized multibyte streams and preserves last good data", async () => {
  const app = start();
  app.reply(snapshot());
  pair(app);
  await settle();
  let cancelled = false;
  const bytes = new TextEncoder().encode("가".repeat(90000));
  assert.ok(bytes.byteLength > 262144);
  app.reply(() => new Response(new ReadableStream({
    start(controller) { controller.enqueue(bytes); },
    cancel() { cancelled = true; },
  })));
  app.ids.refresh.fire("click");
  await settle();
  assert.equal(cancelled, true);
  assert.match(text(app.ids.providers), /42% 남음/);
  assert.match(text(app.ids.providers), /STALE/);
  assert.match(app.ids.status.textContent, /연결 오류/);
});
test("malformed and duplicate snapshots fail closed without replacing the cache", async () => {
  const app = start();
  app.reply(snapshot());
  pair(app);
  await settle();
  const mutations = [
    s => s.providers.push(s.providers[0]),
    s => s.providers[0].windows.push(s.providers[0].windows[0]),
    s => s.providers[0].windows = Array.from({ length: 4 }, (_, i) => ({ label: String(i), remainingPercent: 10, resetsAt: null })),
    s => s.providers[0].observedAt = "not a date",
    s => s.providers[0].windows[0].resetsAt = "2026-02-30T00:00:00.000Z",
    s => s.generatedAt = "2026-01-01",
    s => s.providers[0].windows[0].remainingPercent = "0",
    s => s.providers[0].plan = "x".repeat(81),
    s => s.providers[0].windows[0] = null,
  ];
  for (const mutate of mutations) {
    const bad = snapshot();
    mutate(bad);
    app.reply(bad);
    app.ids.refresh.fire("click");
    await settle();
    assert.match(app.ids.status.textContent, /연결 오류/);
    assert.match(text(app.ids.providers), /42% 남음/);
    assert.match(text(app.ids.providers), /STALE/);
  }
});
test("only safe quota vocabulary is rendered; errors and nullable measurements have no bar", async () => {
  const app = start();
  const s = snapshot();
  const p = s.providers[0];
  p.plan = "private@example.test";
  p.message = "private diagnostic";
  p.identity = { email: "private@example.test" };
  p.windows[0].label = "private diagnostic";
  p.windows[0].remainingPercent = null;
  app.reply(s);
  pair(app);
  await settle();
  assert.doesNotMatch(text(app.ids.providers), /private/);
  assert.match(text(app.ids.providers), /알 수 없음/);
  assert.equal(descendants(app.ids.providers).filter(e => e.tag === "progress").length, 0);
  p.state = "error";
  p.windows[0].remainingPercent = 99;
  app.reply(s);
  app.ids.refresh.fire("click");
  await settle();
  assert.equal(descendants(app.ids.providers).filter(e => e.tag === "progress").length, 0);
  assert.doesNotMatch(text(app.ids.providers), /99%|private/);
});
test("late fetch completion after disconnect cannot restore data or pairing", async () => {
  const app = start();
  let resolve;
  app.reply(() => new Promise(r => { resolve = r; }));
  pair(app);
  app.ids.disconnect.fire("click");
  assert.equal(app.calls[0].options.signal.aborted, true);
  resolve(new Response(JSON.stringify(snapshot())));
  await settle();
  assert.equal(app.ids.mode.textContent, "NOT CONNECTED");
  assert.equal(app.ids.refresh.disabled, true);
  assert.equal(app.storage.size, 0);
  assert.doesNotMatch(text(app.ids.providers), /42%/);
  assert.equal(app.ids.status.textContent, "브리지를 연결해 주세요");
});
test("15 second deadline cancels a stalled body and permits a manual retry", async () => {
  const app = start();
  let cancelled = false;
  app.reply(() => new Response(new ReadableStream({
    cancel() { cancelled = true; },
  })));
  pair(app);
  await settle();
  assert.equal(app.ids.refresh.disabled, true);
  app.expire();
  await settle();
  assert.equal(cancelled, true);
  assert.equal(app.calls[0].options.signal.aborted, true);
  assert.equal(app.ids.refresh.disabled, false);
  assert.match(app.ids.status.textContent, /연결하지 못했습니다/);
  app.reply(snapshot());
  app.ids.refresh.fire("click");
  await settle();
  assert.match(text(app.ids.providers), /42% 남음/);
});
