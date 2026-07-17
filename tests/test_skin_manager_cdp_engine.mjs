#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:http";
import {
  mkdtemp,
  mkdir,
  readFile,
  symlink,
  writeFile,
} from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

import { chromium } from "playwright";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const RESOURCES = join(ROOT, "skin-manager", "Sources", "CodexSkinManager", "Resources");
const ENGINE = join(RESOURCES, "Engine");
const TEMPLATES = join(RESOURCES, "Templates");
const INJECTOR = join(ENGINE, "injector.mjs");
const RENDERER = join(ENGINE, "renderer-inject.js");
const BROWSER_EXECUTABLE = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const TINY_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR42mNkYGD4z8DAwMDEAAUADgAB/2cZ1QAAAABJRU5ErkJggg==",
  "base64",
);

function reservePort() {
  return new Promise((resolvePort, rejectPort) => {
    const server = createServer();
    server.once("error", rejectPort);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => resolvePort(address.port));
    });
  });
}

function runProcess(command, args, options = {}) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, { ...options, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", rejectRun);
    child.once("exit", (status, signal) => resolveRun({ status, signal, stdout, stderr }));
  });
}

async function waitFor(url, timeoutMs = 15_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return response;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 100));
  }
  throw new Error(`Timed out waiting for ${url}: ${lastError ?? "not ready"}`);
}

async function createSkin(root, {
  id = "meng-chuan-nightblade",
  template = "nightblade-v1",
  hero = "assets/hero.png",
  background = "assets/background.png",
} = {}) {
  const skin = join(root, id);
  await mkdir(join(skin, "assets"), { recursive: true });
  await writeFile(join(skin, "manifest.json"), JSON.stringify({
    schemaVersion: 1,
    id,
    name: id,
    version: "1.0.0",
    template,
  }));
  await writeFile(join(skin, "theme.json"), JSON.stringify({
    tokens: { canvas: "#080D15", accent: "#9E2F28", panelRadius: "18" },
    assets: { hero, background },
    focalPoints: { hero: { x: 0.72, y: 0.36 } },
  }));
  await writeFile(join(skin, "assets", "hero.png"), TINY_PNG);
  await writeFile(join(skin, "assets", "background.png"), TINY_PNG);
  return skin;
}

test("payload uses only an allowlisted manager template and local declared raster assets", async () => {
  const temporary = await mkdtemp(join(tmpdir(), "skin-manager-payload-"));
  const skin = await createSkin(temporary);
  const module = await import(`${pathToFileURL(INJECTOR)}?payload=${Date.now()}`);

  const payload = await module.buildPayload(skin, TEMPLATES);

  assert.equal(payload.skinId, "meng-chuan-nightblade");
  assert.equal(payload.template, "nightblade-v1");
  assert.equal(payload.rootClass, "codex-skin-template-nightblade-v1");
  assert.match(payload.css, /:root\.codex-skin-template-nightblade-v1/);
  assert.match(payload.css, /--codex-skin-template-active:\s*nightblade-v1/);
  assert.match(payload.css, /#codex-skin-manager-chrome::before/);
  assert.doesNotMatch(payload.css, /codex-meng-chuan-nightblade/);
  assert.match(payload.version, /^meng-chuan-nightblade-1\.0\.0-[a-f0-9]{16}$/);
  assert.ok((payload.css.match(/data:image\/png;base64/g) ?? []).length >= 2);
  assert.match(payload.css, /--codex-skin-manager-canvas:\s*#080D15/);
  assert.ok(!payload.css.includes('url("./'), "template retained a relative asset URL");
  assert.doesNotMatch(payload.css, /https?:|file:|@import/i);

  const undyingPhoenix = await createSkin(temporary, {
    id: "liu-qiyue-undying-phoenix",
    template: "undying-phoenix-v1",
  });
  const phoenixPayload = await module.buildPayload(undyingPhoenix, TEMPLATES);
  assert.equal(phoenixPayload.rootClass, "codex-skin-template-undying-phoenix-v1");
  assert.match(phoenixPayload.css, /--codex-skin-template-active:\s*undying-phoenix-v1/);
  assert.match(phoenixPayload.css, /柳七月\s*·\s*不死凰焰/);
  assert.ok((phoenixPayload.css.match(/data:image\/png;base64/g) ?? []).length >= 2);
  assert.ok(!phoenixPayload.css.includes('url("./'), "phoenix template retained a relative asset URL");
  assert.doesNotMatch(phoenixPayload.css, /https?:|file:|@import/i);

  const unknown = await createSkin(temporary, { id: "unknown-template", template: "package-script" });
  await assert.rejects(() => module.buildPayload(unknown, TEMPLATES), /template|allowlist|unsupported/i);

  const outside = join(temporary, "outside.png");
  await writeFile(outside, TINY_PNG);
  const escaped = await createSkin(temporary, { id: "escaped-asset", hero: "assets/link.png" });
  await symlink(outside, join(escaped, "assets", "link.png"));
  await assert.rejects(() => module.buildPayload(escaped, TEMPLATES), /asset|outside|unsafe/i);
});

test("renderer is idempotent, switches template roots, repairs nodes, and cleans up", {
  skip: !existsSync(BROWSER_EXECUTABLE),
}, async (context) => {
  const source = await readFile(RENDERER, "utf8");
  const browser = await chromium.launch({ headless: true, executablePath: BROWSER_EXECUTABLE });
  context.after(() => browser.close().catch(() => {}));
  const page = await browser.newPage();
  await page.setContent("<main><button id='control'>Codex</button></main>");
  const nightblade = {
    skinId: "meng-chuan-nightblade",
    template: "nightblade-v1",
    version: "nightblade-1",
    rootClass: "codex-skin-template-nightblade-v1",
    css: ":root.codex-skin-template-nightblade-v1{--skin-manager-test:1;--codex-skin-template-active:nightblade-v1}",
  };
  const redLotus = {
    skinId: "meng-chuan-red-lotus",
    template: "red-lotus-v1",
    version: "red-lotus-1",
    rootClass: "codex-skin-template-red-lotus-v1",
    css: ":root.codex-skin-template-red-lotus-v1{--skin-manager-test:2;--codex-skin-template-active:red-lotus-v1}",
  };

  const first = await page.evaluate(({ source: code, payload }) => (0, eval)(code)(payload), { source, payload: nightblade });
  const reused = await page.evaluate(({ source: code, payload }) => (0, eval)(code)(payload), { source, payload: nightblade });
  assert.equal(first.reused, false);
  assert.equal(reused.reused, true);
  assert.equal(await page.locator("#codex-skin-manager-style").count(), 1);
  assert.equal(await page.locator("#codex-skin-manager-chrome").count(), 1);
  assert.equal(await page.locator("html.codex-skin-template-nightblade-v1").count(), 1);
  assert.equal(await page.evaluate(() => window.__CODEX_SKIN_MANAGER__.verify()), true);
  assert.equal(
    await page.locator("#codex-skin-manager-chrome").evaluate((element) => getComputedStyle(element).pointerEvents),
    "none",
  );

  await page.evaluate(() => {
    document.getElementById("codex-skin-manager-style")?.remove();
    document.getElementById("codex-skin-manager-chrome")?.remove();
    window.__CODEX_SKIN_MANAGER__.ensure();
  });
  assert.equal(await page.locator("#codex-skin-manager-style").count(), 1);
  assert.equal(await page.locator("#codex-skin-manager-chrome").count(), 1);

  const switched = await page.evaluate(({ source: code, payload }) => (0, eval)(code)(payload), { source, payload: redLotus });
  assert.equal(switched.reused, false);
  assert.equal(await page.locator("html.codex-skin-template-nightblade-v1").count(), 0);
  assert.equal(await page.locator("html.codex-skin-template-red-lotus-v1").count(), 1);
  assert.equal(await page.evaluate(() => window.__CODEX_SKIN_MANAGER__.skinId), "meng-chuan-red-lotus");

  assert.equal(await page.evaluate(() => window.__CODEX_SKIN_MANAGER__.cleanup()), true);
  assert.equal(await page.locator("#codex-skin-manager-style").count(), 0);
  assert.equal(await page.locator("#codex-skin-manager-chrome").count(), 0);
  assert.equal(await page.locator("[class*='codex-skin-template-']").count(), 0);
});

test("once mode waits through transient fetch failures while Codex CDP starts", {
  skip: !existsSync(BROWSER_EXECUTABLE),
}, async (context) => {
  const temporary = await mkdtemp(join(tmpdir(), "skin-manager-delayed-cdp-"));
  const stateRoot = join(temporary, "state");
  await mkdir(stateRoot, { recursive: true });
  const skin = await createSkin(temporary);
  const debugPort = await reservePort();
  const pageServer = createServer((_request, response) => {
    response.setHeader("content-type", "text/html; charset=utf-8");
    response.end("<!doctype html><html><body><main>Delayed Codex fixture</main></body></html>");
  });
  await new Promise((resolveListen) => pageServer.listen(0, "127.0.0.1", resolveListen));
  context.after(() => pageServer.close());
  const pagePort = pageServer.address().port;
  const pageUrl = `http://127.0.0.1:${pagePort}/`;
  const profile = await mkdtemp(join(tmpdir(), "skin-manager-delayed-cdp-profile-"));

  const attemptPromise = runProcess(process.execPath, [
    INJECTOR,
    "--skin", skin,
    "--templates", TEMPLATES,
    "--state-root", stateRoot,
    "--once",
    "--wait-timeout", "15000",
    "--port", String(debugPort),
    "--target-url-prefix", pageUrl,
  ]);
  await new Promise((resolveWait) => setTimeout(resolveWait, 300));
  const browserProcess = spawn(BROWSER_EXECUTABLE, [
    "--headless=new",
    "--no-first-run",
    "--no-default-browser-check",
    `--user-data-dir=${profile}`,
    "--remote-debugging-address=127.0.0.1",
    `--remote-debugging-port=${debugPort}`,
    pageUrl,
  ], { stdio: "ignore" });
  context.after(() => browserProcess.kill("SIGTERM"));

  const attempt = await attemptPromise;

  assert.equal(attempt.status, 0, attempt.stderr || attempt.stdout);
  assert.doesNotMatch(attempt.stderr + attempt.stdout, /fetch failed/i);
});

test("generic engine applies, verifies, switches, survives navigation, and restores through real CDP", {
  skip: !existsSync(BROWSER_EXECUTABLE),
}, async (context) => {
  const temporary = await mkdtemp(join(tmpdir(), "skin-manager-cdp-"));
  const stateRoot = join(temporary, "state");
  await mkdir(stateRoot, { recursive: true });
  const nightblade = await createSkin(temporary);
  const redLotus = await createSkin(temporary, {
    id: "meng-chuan-red-lotus",
    template: "red-lotus-v1",
  });
  const undyingPhoenix = await createSkin(temporary, {
    id: "liu-qiyue-undying-phoenix",
    template: "undying-phoenix-v1",
  });
  const debugPort = await reservePort();
  const pageServer = createServer((_request, response) => {
    response.setHeader("content-type", "text/html; charset=utf-8");
    response.end("<!doctype html><html><body><main>Codex manager fixture</main></body></html>");
  });
  await new Promise((resolveListen) => pageServer.listen(0, "127.0.0.1", resolveListen));
  const pagePort = pageServer.address().port;
  const pageUrl = `http://127.0.0.1:${pagePort}/`;
  const profile = await mkdtemp(join(tmpdir(), "skin-manager-cdp-profile-"));
  const browserProcess = spawn(BROWSER_EXECUTABLE, [
    "--headless=new",
    "--no-first-run",
    "--no-default-browser-check",
    `--user-data-dir=${profile}`,
    "--remote-debugging-address=127.0.0.1",
    `--remote-debugging-port=${debugPort}`,
    "about:blank",
  ], { stdio: "ignore" });
  context.after(() => {
    browserProcess.kill("SIGTERM");
    pageServer.close();
  });
  await waitFor(`http://127.0.0.1:${debugPort}/json/list`);
  const cdpBrowser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
  context.after(() => cdpBrowser.close().catch(() => {}));
  const page = cdpBrowser.contexts().flatMap((browserContext) => browserContext.pages())[0];
  await page.goto(pageUrl);

  const argsFor = (skin) => [
    INJECTOR,
    "--skin", skin,
    "--templates", TEMPLATES,
    "--state-root", stateRoot,
    "--port", String(debugPort),
    "--target-url-prefix", pageUrl,
  ];
  const injected = await runProcess(process.execPath, [...argsFor(nightblade), "--once", "--wait-timeout", "5000"]);
  assert.equal(injected.status, 0, injected.stderr || injected.stdout);
  const verify = spawnSync(process.execPath, [...argsFor(nightblade), "--verify"], { encoding: "utf8" });
  assert.equal(verify.status, 0, verify.stderr || verify.stdout);
  assert.equal(await page.locator("#codex-skin-manager-style").count(), 1);
  assert.equal(await page.locator("html.codex-skin-template-nightblade-v1").count(), 1);

  const watcher = spawn(process.execPath, [...argsFor(nightblade), "--watch"], { stdio: "ignore" });
  context.after(() => watcher.kill("SIGTERM"));
  await page.goto(`${pageUrl}after-navigation`);
  await page.locator("#codex-skin-manager-style").waitFor({ state: "attached", timeout: 10_000 });
  const second = await page.context().newPage();
  await second.goto(`${pageUrl}new-window`);
  await second.locator("#codex-skin-manager-style").waitFor({ state: "attached", timeout: 10_000 });
  watcher.kill("SIGTERM");
  await new Promise((resolveExit) => watcher.once("exit", resolveExit));

  const switched = await runProcess(process.execPath, [...argsFor(redLotus), "--once"]);
  assert.equal(switched.status, 0, switched.stderr || switched.stdout);
  assert.equal(await page.locator("html.codex-skin-template-nightblade-v1").count(), 0);
  assert.equal(await page.locator("html.codex-skin-template-red-lotus-v1").count(), 1);
  assert.equal(await page.evaluate(() => window.__CODEX_SKIN_MANAGER__.skinId), "meng-chuan-red-lotus");

  const switchedBack = await runProcess(process.execPath, [...argsFor(nightblade), "--once"]);
  assert.equal(switchedBack.status, 0, switchedBack.stderr || switchedBack.stdout);
  assert.equal(await page.locator("html.codex-skin-template-red-lotus-v1").count(), 0);
  assert.equal(await page.locator("html.codex-skin-template-nightblade-v1").count(), 1);
  assert.equal(await page.evaluate(() => window.__CODEX_SKIN_MANAGER__.skinId), "meng-chuan-nightblade");
  assert.equal(
    await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--startup-logo-shimmer-peak").trim()),
    "rgb(145 220 255 / 0.95)",
  );

  const switchedToPhoenix = await runProcess(process.execPath, [...argsFor(undyingPhoenix), "--once"]);
  assert.equal(switchedToPhoenix.status, 0, switchedToPhoenix.stderr || switchedToPhoenix.stdout);
  assert.equal(await page.locator("html.codex-skin-template-nightblade-v1").count(), 0);
  assert.equal(await page.locator("html.codex-skin-template-undying-phoenix-v1").count(), 1);
  assert.equal(await page.evaluate(() => window.__CODEX_SKIN_MANAGER__.skinId), "liu-qiyue-undying-phoenix");
  assert.equal(
    await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--startup-logo-shimmer-peak").trim()),
    "rgb(255 212 122 / 0.95)",
  );

  const restore = spawnSync(process.execPath, [...argsFor(undyingPhoenix), "--restore"], { encoding: "utf8" });
  assert.equal(restore.status, 0, restore.stderr || restore.stdout);
  assert.equal(await page.locator("#codex-skin-manager-style").count(), 0);
  assert.equal(await second.locator("#codex-skin-manager-style").count(), 0);

  const reappliedAfterRestore = await runProcess(process.execPath, [...argsFor(redLotus), "--once"]);
  assert.equal(reappliedAfterRestore.status, 0, reappliedAfterRestore.stderr || reappliedAfterRestore.stdout);
  assert.equal(await page.locator("html.codex-skin-template-undying-phoenix-v1").count(), 0);
  assert.equal(await page.locator("html.codex-skin-template-red-lotus-v1").count(), 1);
  assert.equal(await page.evaluate(() => window.__CODEX_SKIN_MANAGER__.verify()), true);

  const finalRestore = spawnSync(process.execPath, [...argsFor(redLotus), "--restore"], { encoding: "utf8" });
  assert.equal(finalRestore.status, 0, finalRestore.stderr || finalRestore.stdout);
});

test("generic engine rejects a non-loopback WebSocket returned by a local endpoint", async (context) => {
  const temporary = await mkdtemp(join(tmpdir(), "skin-manager-hostile-cdp-"));
  const skin = await createSkin(temporary);
  const stateRoot = join(temporary, "state");
  await mkdir(stateRoot, { recursive: true });
  const port = await reservePort();
  const hostileServer = createServer((_request, response) => {
    response.setHeader("content-type", "application/json");
    response.end(JSON.stringify([{
      id: "hostile",
      type: "page",
      url: "app://hostile/index.html",
      webSocketDebuggerUrl: "ws://example.com:4444/devtools/page/hostile",
    }]));
  });
  await new Promise((resolveListen) => hostileServer.listen(port, "127.0.0.1", resolveListen));
  context.after(() => hostileServer.close());

  const attempt = await runProcess(process.execPath, [
    INJECTOR,
    "--skin", skin,
    "--templates", TEMPLATES,
    "--state-root", stateRoot,
    "--once",
    "--port", String(port),
  ]);
  assert.notEqual(attempt.status, 0);
  assert.match(attempt.stderr + attempt.stdout, /unsafe|loopback|WebSocket/i);
});
