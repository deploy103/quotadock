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
  let interval, response;
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
    setTimeout: () => 1,
    clearTimeout() {},
    fetch: async (url, options) => {
      calls.push({ url, options });
      if (response instanceof Error) throw response;
      return { ok: true, text: async () => JSON.stringify(response) };
    },
  });
  return {
    ids,
    storage,
    calls,
    document,
    tick: () => interval?.(),
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
