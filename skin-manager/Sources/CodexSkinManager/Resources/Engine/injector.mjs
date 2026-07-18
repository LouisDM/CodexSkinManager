#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  access,
  mkdir,
  readFile,
  realpath,
  stat,
  unlink,
  writeFile,
} from "node:fs/promises";
import {
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_TEMPLATES = join(dirname(HERE), "Templates");
const DEFAULT_PORT = 9340;
const POLL_INTERVAL_MS = 1_200;
const EXIT_AFTER_MISSING_POLLS = 10;
const COMMAND_TIMEOUT_MS = 5_000;
const STATE_KEY = "__CODEX_SKIN_MANAGER__";
const DISABLED_STATE_KEY = "__CODEX_SKIN_MANAGER_DISABLED__";
const STYLE_ID = "codex-skin-manager-style";
const CHROME_ID = "codex-skin-manager-chrome";
const ROOT_PREFIX = "codex-skin-template-";
const MAX_ASSET_BYTES = 32 * 1_024 * 1_024;

const TEMPLATE_CATALOG = Object.freeze({
  "nightblade-v1": Object.freeze({
    file: "nightblade-v1.css",
    rootClass: "codex-skin-template-nightblade-v1",
    assetReferences: Object.freeze({
      hero: "./hero-character.png",
      background: "./hero-background.png",
    }),
  }),
  "paw-atelier-v1": Object.freeze({
    file: "paw-atelier-v1.css",
    rootClass: "codex-skin-template-paw-atelier-v1",
    assetReferences: Object.freeze({
      hero: "./hero-character.png",
      background: "./hero-background.png",
    }),
  }),
  "red-lotus-v1": Object.freeze({
    file: "red-lotus-v1.css",
    rootClass: "codex-skin-template-red-lotus-v1",
    assetReferences: Object.freeze({
      hero: "./meng-chuan-portrait.png",
      background: "./meng-chuan-hero-background.png",
    }),
  }),
  "seventh-heaven-v1": Object.freeze({
    file: "seventh-heaven-v1.css",
    rootClass: "codex-skin-template-seventh-heaven-v1",
    assetReferences: Object.freeze({
      hero: "./hero-character.png",
      background: "./hero-background.png",
    }),
  }),
  "stage-check-v1": Object.freeze({
    file: "stage-check-v1.css",
    rootClass: "codex-skin-template-stage-check-v1",
    assetReferences: Object.freeze({
      hero: "./hero-character.png",
      background: "./hero-background.png",
    }),
  }),
  "undying-phoenix-v1": Object.freeze({
    file: "undying-phoenix-v1.css",
    rootClass: "codex-skin-template-undying-phoenix-v1",
    assetReferences: Object.freeze({
      hero: "./hero-character.png",
      background: "./hero-background.png",
    }),
  }),
});

const TOKEN_PROPERTIES = Object.freeze({
  canvas: ["--startup-background", "--color-background-surface-under", "--color-token-bg-primary"],
  surface: ["--color-background-surface", "--color-token-main-surface-primary"],
  surfaceRaised: ["--color-background-elevated-primary-opaque", "--color-token-bg-secondary"],
  ink: ["--vscode-foreground", "--color-text-foreground", "--color-token-text-primary"],
  mutedInk: ["--color-text-foreground-secondary", "--color-token-text-secondary"],
  accent: ["--codex-base-accent", "--color-background-accent", "--color-token-primary"],
  accentStrong: ["--color-background-accent-active", "--color-text-accent"],
  line: ["--color-token-border", "--color-token-border-default"],
  focus: ["--vscode-focusBorder", "--color-token-focus-border"],
  panelRadius: ["--radius-token-row"],
  controlRadius: ["--radius-token-composer-single-line"],
  motionDuration: ["--codex-skin-manager-motion-duration"],
});

const cachedBundles = new Map();

export function parseArguments(argv) {
  const options = {
    mode: "once",
    port: DEFAULT_PORT,
    targetUrlPrefix: "app://",
    waitTimeoutMs: 0,
    skinDirectory: undefined,
    templatesDirectory: DEFAULT_TEMPLATES,
    stateRoot: undefined,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--once") options.mode = "once";
    else if (value === "--watch") options.mode = "watch";
    else if (value === "--verify") options.mode = "verify";
    else if (value === "--restore") options.mode = "restore";
    else if (value === "--port") options.port = Number(argv[++index]);
    else if (value === "--target-url-prefix") options.targetUrlPrefix = argv[++index];
    else if (value === "--wait-timeout") options.waitTimeoutMs = Number(argv[++index]);
    else if (value === "--skin") options.skinDirectory = argv[++index];
    else if (value === "--templates") options.templatesDirectory = argv[++index];
    else if (value === "--state-root") options.stateRoot = argv[++index];
    else throw new Error(`Unknown argument: ${value}`);
  }
  if (!Number.isInteger(options.port) || options.port < 1 || options.port > 65_535) {
    throw new Error(`Invalid CDP port: ${options.port}`);
  }
  if (!options.targetUrlPrefix) throw new Error("Target URL prefix cannot be empty");
  if (!Number.isFinite(options.waitTimeoutMs) || options.waitTimeoutMs < 0) {
    throw new Error(`Invalid wait timeout: ${options.waitTimeoutMs}`);
  }
  if (!options.skinDirectory) throw new Error("--skin is required");
  if (!options.templatesDirectory) throw new Error("--templates cannot be empty");
  if (!options.stateRoot) throw new Error("--state-root is required");
  options.skinDirectory = resolve(options.skinDirectory);
  options.templatesDirectory = resolve(options.templatesDirectory);
  options.stateRoot = resolve(options.stateRoot);
  return options;
}

function markerPath(options) {
  return join(options.stateRoot, "skin-disabled");
}

function assertPlainObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value;
}

function validateSkinIdentity(manifest) {
  if (manifest.schemaVersion !== 1) throw new Error("Unsupported skin schema version");
  if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$/.test(manifest.id ?? "")) {
    throw new Error("Unsafe skin id");
  }
  if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(manifest.version ?? "")) {
    throw new Error("Unsafe skin version");
  }
}

function safeAssetPath(rawPath) {
  if (
    typeof rawPath !== "string"
    || !rawPath
    || isAbsolute(rawPath)
    || rawPath.includes("\\")
    || rawPath.includes("\0")
    || rawPath.includes("//")
  ) {
    throw new Error(`Unsafe skin asset path: ${String(rawPath)}`);
  }
  const parts = rawPath.split("/");
  if (parts.length > 8 || parts.some((part) => !part || part === "." || part === "..")) {
    throw new Error(`Unsafe skin asset path: ${rawPath}`);
  }
  const extension = extname(rawPath).toLowerCase();
  if (!new Set([".jpeg", ".jpg", ".png"]).has(extension)) {
    throw new Error(`Unsupported skin asset type: ${rawPath}`);
  }
  return rawPath;
}

async function readLocalAsset(skinRoot, rawPath) {
  const assetPath = safeAssetPath(rawPath);
  const resolvedAsset = await realpath(join(skinRoot, assetPath));
  const fromRoot = relative(skinRoot, resolvedAsset);
  if (!fromRoot || fromRoot.startsWith("..") || isAbsolute(fromRoot)) {
    throw new Error(`Skin asset resolves outside its package: ${assetPath}`);
  }
  const info = await stat(resolvedAsset);
  if (!info.isFile() || info.size <= 0 || info.size > MAX_ASSET_BYTES) {
    throw new Error(`Unsafe skin asset size: ${assetPath}`);
  }
  return { bytes: await readFile(resolvedAsset), extension: extname(assetPath).toLowerCase() };
}

function imageDataUrl(bytes, extension) {
  const mime = extension === ".png" ? "image/png" : "image/jpeg";
  return `data:${mime};base64,${bytes.toString("base64")}`;
}

function tokenValue(name, rawValue) {
  if (typeof rawValue !== "string" || !(name in TOKEN_PROPERTIES)) {
    throw new Error(`Unsupported theme token: ${name}`);
  }
  if (["panelRadius", "controlRadius", "motionDuration"].includes(name)) {
    const number = Number(rawValue);
    if (!Number.isFinite(number) || number < 0 || number > 1_000) {
      throw new Error(`Unsafe numeric theme token: ${name}`);
    }
    return `${number}${name === "motionDuration" ? "ms" : "px"}`;
  }
  if (!/^#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$/.test(rawValue)) {
    throw new Error(`Unsafe color theme token: ${name}`);
  }
  return rawValue;
}

function tokenOverrides(rootClass, rawTokens) {
  const tokens = assertPlainObject(rawTokens ?? {}, "theme.tokens");
  const declarations = [];
  for (const name of Object.keys(tokens).sort()) {
    const value = tokenValue(name, tokens[name]);
    const kebab = name.replaceAll(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
    declarations.push(`  --codex-skin-manager-${kebab}: ${value} !important;`);
    for (const property of TOKEN_PROPERTIES[name]) {
      declarations.push(`  ${property}: ${value} !important;`);
    }
  }
  return declarations.length ? `\nhtml.${rootClass} {\n${declarations.join("\n")}\n}\n` : "";
}

function assertSafeTemplate(css) {
  if (/@import|https?:|file:/i.test(css)) {
    throw new Error("Manager template contains a remote or imported resource");
  }
}

export async function buildPayload(skinDirectory, templatesDirectory = DEFAULT_TEMPLATES) {
  const skinRoot = await realpath(resolve(skinDirectory));
  const templateRoot = await realpath(resolve(templatesDirectory));
  const [manifestBytes, themeBytes, rendererBytes] = await Promise.all([
    readFile(join(skinRoot, "manifest.json")),
    readFile(join(skinRoot, "theme.json")),
    readFile(join(HERE, "renderer-inject.js")),
  ]);
  const manifest = assertPlainObject(JSON.parse(manifestBytes), "manifest");
  const theme = assertPlainObject(JSON.parse(themeBytes), "theme");
  validateSkinIdentity(manifest);
  const template = TEMPLATE_CATALOG[manifest.template];
  if (!template) throw new Error(`Unsupported manager template allowlist entry: ${manifest.template}`);
  const templatePath = await realpath(join(templateRoot, template.file));
  const templateRelativePath = relative(templateRoot, templatePath);
  if (!templateRelativePath || templateRelativePath.startsWith("..") || isAbsolute(templateRelativePath)) {
    throw new Error("Manager template resolves outside its signed resource directory");
  }
  const templateBytes = await readFile(templatePath);
  let css = templateBytes.toString("utf8");
  assertSafeTemplate(css);
  const assets = assertPlainObject(theme.assets ?? {}, "theme.assets");
  const hash = createHash("sha256").update(templateBytes).update(themeBytes).update(rendererBytes);

  for (const [slot, reference] of Object.entries(template.assetReferences)) {
    if (!(slot in assets)) throw new Error(`Skin is missing required asset slot: ${slot}`);
    const asset = await readLocalAsset(skinRoot, assets[slot]);
    const literal = `url("${reference}")`;
    if (!css.includes(literal)) throw new Error(`Manager template is missing its signed asset marker: ${slot}`);
    css = css.replaceAll(literal, `url("${imageDataUrl(asset.bytes, asset.extension)}")`);
    hash.update(asset.bytes);
  }
  for (const slot of Object.keys(assets)) {
    if (!new Set(["avatar", "background", "hero"]).has(slot)) {
      throw new Error(`Unsupported theme asset slot: ${slot}`);
    }
    safeAssetPath(assets[slot]);
  }
  if (/url\(\s*["']?\.\.?(?:\/|\\)/i.test(css)) {
    throw new Error("Manager template retained an unsupported relative asset URL");
  }
  css += tokenOverrides(template.rootClass, theme.tokens);
  const digest = hash.update(manifestBytes).digest("hex").slice(0, 16);
  return {
    skinId: manifest.id,
    template: manifest.template,
    version: `${manifest.id}-${manifest.version}-${digest}`,
    rootClass: template.rootClass,
    css,
  };
}

async function restoreIsRequested(options) {
  try {
    await access(markerPath(options));
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

async function clearRestoreRequest(options) {
  try {
    await unlink(markerPath(options));
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}

function safeWebSocketUrl(rawUrl, port) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error("Unsafe CDP WebSocket URL: invalid URL");
  }
  const loopbackHosts = new Set(["127.0.0.1", "localhost", "[::1]", "::1"]);
  if (
    url.protocol !== "ws:"
    || !loopbackHosts.has(url.hostname)
    || Number(url.port || 80) !== port
    || url.username
    || url.password
  ) {
    throw new Error(`Unsafe CDP WebSocket URL; expected loopback port ${port}`);
  }
  return url.href;
}

class CdpConnection {
  static async connect(webSocketUrl) {
    const socket = new WebSocket(webSocketUrl);
    try {
      await new Promise((resolveOpen, rejectOpen) => {
        const timeout = setTimeout(() => {
          try {
            socket.close();
          } catch {
            // Some WebSocket implementations reject close while CONNECTING.
          }
          rejectOpen(new Error("CDP WebSocket connection timed out"));
        }, COMMAND_TIMEOUT_MS);
        socket.addEventListener("open", () => {
          clearTimeout(timeout);
          resolveOpen();
        }, { once: true });
        socket.addEventListener("error", () => {
          clearTimeout(timeout);
          rejectOpen(new Error("CDP WebSocket connection failed"));
        }, { once: true });
      });
    } catch (error) {
      try { socket.close(); } catch { /* already closed */ }
      throw error;
    }
    return new CdpConnection(socket);
  }

  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    socket.addEventListener("message", (event) => {
      let message;
      try {
        message = JSON.parse(String(event.data));
      } catch {
        return;
      }
      if (!message.id) return;
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error(message.error.message));
      else pending.resolve(message.result);
    });
    socket.addEventListener("close", () => {
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error("CDP WebSocket closed"));
      }
      this.pending.clear();
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolveMessage, rejectMessage) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        rejectMessage(new Error(`CDP command timed out: ${method}`));
      }, COMMAND_TIMEOUT_MS);
      this.pending.set(id, { resolve: resolveMessage, reject: rejectMessage, timer });
      try {
        this.socket.send(JSON.stringify({ id, method, params }));
      } catch (error) {
        clearTimeout(timer);
        this.pending.delete(id);
        rejectMessage(error);
      }
    });
  }

  resultValue(response) {
    if (response.exceptionDetails) {
      const description = response.exceptionDetails.exception?.description
        ?? response.exceptionDetails.text
        ?? "Renderer evaluation failed";
      throw new Error(description);
    }
    return response.result?.value;
  }

  async evaluate(expression) {
    await this.send("Runtime.enable");
    return this.resultValue(await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    }));
  }

  async applyRenderer(rendererSource, payload) {
    await this.send("Runtime.enable");
    const renderer = await this.send("Runtime.evaluate", {
      expression: `(${rendererSource})`,
      returnByValue: false,
    });
    if (renderer.exceptionDetails || !renderer.result?.objectId) {
      this.resultValue(renderer);
      throw new Error("Manager renderer did not produce a callable object");
    }
    return this.resultValue(await this.send("Runtime.callFunctionOn", {
      objectId: renderer.result.objectId,
      functionDeclaration: "function(payload) { return this(payload); }",
      arguments: [{ value: payload }],
      awaitPromise: true,
      returnByValue: true,
    }));
  }

  close() {
    try { this.socket.close(); } catch { /* already closed */ }
  }
}

async function listTargets(port, targetUrlPrefix) {
  const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
    signal: AbortSignal.timeout(2_500),
  });
  if (!response.ok) throw new Error(`CDP target listing failed with HTTP ${response.status}`);
  const targets = await response.json();
  if (!Array.isArray(targets)) throw new Error("CDP target listing did not return an array");
  return targets
    .filter((target) => (
      target.type === "page"
      && typeof target.webSocketDebuggerUrl === "string"
      && target.url?.startsWith(targetUrlPrefix)
    ))
    .map((target) => ({
      ...target,
      webSocketDebuggerUrl: safeWebSocketUrl(target.webSocketDebuggerUrl, port),
    }));
}

async function runTargets(targets, operation, requireAll = true) {
  const results = [];
  const failures = [];
  for (const target of targets) {
    let connection;
    try {
      connection = await CdpConnection.connect(target.webSocketDebuggerUrl);
      results.push({ target, value: await operation(connection) });
    } catch (error) {
      failures.push(`${target.id ?? target.url}: ${error.message}`);
    } finally {
      connection?.close();
    }
  }
  if (failures.length && (requireAll || results.length === 0)) {
    throw new Error(`CDP operation failed for ${failures.length} target(s): ${failures.join("; ")}`);
  }
  if (failures.length) console.error(`Skipped ${failures.length} stale CDP target(s): ${failures.join("; ")}`);
  return results;
}

async function injectionBundle(options) {
  const cacheKey = `${options.skinDirectory}\0${options.templatesDirectory}`;
  if (!cachedBundles.has(cacheKey)) {
    cachedBundles.set(cacheKey, Promise.all([
      readFile(join(HERE, "renderer-inject.js"), "utf8"),
      buildPayload(options.skinDirectory, options.templatesDirectory),
    ]).then(([renderer, payload]) => ({ renderer, payload })));
  }
  try {
    return await cachedBundles.get(cacheKey);
  } catch (error) {
    cachedBundles.delete(cacheKey);
    throw error;
  }
}

async function waitForTargets(options, allowNoTargets) {
  const deadline = Date.now() + (allowNoTargets ? 0 : options.waitTimeoutMs);
  let lastListingError;
  while (true) {
    try {
      const targets = await listTargets(options.port, options.targetUrlPrefix);
      lastListingError = undefined;
      if (targets.length || allowNoTargets) return targets;
    } catch (error) {
      if (allowNoTargets) throw error;
      lastListingError = error;
    }
    if (Date.now() >= deadline) {
      if (lastListingError) {
        const detail = lastListingError instanceof Error ? lastListingError.message : String(lastListingError);
        throw new Error(`Codex CDP did not become ready: ${detail}`);
      }
      throw new Error(`No matching Codex renderer target found for ${options.targetUrlPrefix}`);
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 200));
  }
}

async function injectOnce(options, allowNoTargets = false) {
  const targets = await waitForTargets(options, allowNoTargets);
  if (!targets.length) return 0;
  const { renderer, payload } = await injectionBundle(options);
  const enabledPayload = { ...payload, clearDisabledState: true };
  const results = await runTargets(
    targets,
    (connection) => connection.applyRenderer(renderer, enabledPayload),
    false,
  );
  return results.length;
}

function verificationExpression(payload) {
  return `(() => {
    const state = window[${JSON.stringify(STATE_KEY)}];
    return Boolean(
      state
      && state.skinId === ${JSON.stringify(payload.skinId)}
      && state.version === ${JSON.stringify(payload.version)}
      && typeof state.verify === "function"
      && state.verify()
    );
  })()`;
}

async function verify(options) {
  const targets = await listTargets(options.port, options.targetUrlPrefix);
  if (!targets.length) throw new Error("No matching renderer target available for verification");
  const { payload } = await injectionBundle(options);
  const results = await runTargets(targets, (connection) => connection.evaluate(verificationExpression(payload)));
  const invalid = results.filter(({ value }) => value !== true);
  if (invalid.length) throw new Error(`Skin Manager verification failed in ${invalid.length} target(s)`);
  return results.length;
}

async function restore(options) {
  await mkdir(options.stateRoot, { recursive: true });
  await writeFile(markerPath(options), `${new Date().toISOString()}\n`, { mode: 0o600 });
  const targets = await listTargets(options.port, options.targetUrlPrefix);
  if (!targets.length) throw new Error("No matching renderer target available for restore");
  const expression = `(() => {
    window[${JSON.stringify(DISABLED_STATE_KEY)}] = true;
    const state = window[${JSON.stringify(STATE_KEY)}];
    if (typeof state?.cleanup === "function") return state.cleanup();
    document.getElementById(${JSON.stringify(STYLE_ID)})?.remove();
    document.getElementById(${JSON.stringify(CHROME_ID)})?.remove();
    for (const className of [...(document.documentElement?.classList ?? [])]) {
      if (className.startsWith(${JSON.stringify(ROOT_PREFIX)})) document.documentElement.classList.remove(className);
    }
    delete window[${JSON.stringify(STATE_KEY)}];
    return false;
  })()`;
  await runTargets(targets, (connection) => connection.evaluate(expression));
  return targets.length;
}

async function repairTargets(options) {
  const targets = await listTargets(options.port, options.targetUrlPrefix);
  if (!targets.length) return 0;
  const { renderer, payload } = await injectionBundle(options);
  let successes = 0;
  const failures = [];
  for (const target of targets) {
    let connection;
    try {
      connection = await CdpConnection.connect(target.webSocketDebuggerUrl);
      const healthy = await connection.evaluate(verificationExpression(payload));
      if (healthy !== true) {
        if (await restoreIsRequested(options)) return 0;
        await connection.applyRenderer(renderer, payload);
      }
      successes += 1;
    } catch (error) {
      failures.push(`${target.id ?? target.url}: ${error.message}`);
    } finally {
      connection?.close();
    }
  }
  if (failures.length === targets.length) {
    throw new Error(`All CDP targets failed: ${failures.join("; ")}`);
  }
  return successes;
}

async function watch(options) {
  let everInjected = false;
  let missingPolls = 0;
  let stopping = false;
  process.on("SIGINT", () => { stopping = true; });
  process.on("SIGTERM", () => { stopping = true; });

  while (!stopping) {
    if (await restoreIsRequested(options)) break;
    try {
      const count = await repairTargets(options);
      if (count > 0) {
        if (!everInjected) console.log(`Watching ${count} Codex renderer target(s) for the active skin`);
        everInjected = true;
        missingPolls = 0;
      } else if (everInjected) {
        missingPolls += 1;
      }
    } catch (error) {
      if (everInjected) missingPolls += 1;
      else console.error(`Waiting for Codex CDP: ${error.message}`);
    }
    if (everInjected && missingPolls >= EXIT_AFTER_MISSING_POLLS) break;
    await new Promise((resolveWait) => setTimeout(resolveWait, POLL_INTERVAL_MS));
  }
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.mode === "once") {
    await mkdir(options.stateRoot, { recursive: true });
    await clearRestoreRequest(options);
    const count = await injectOnce(options);
    const verified = await verify(options);
    console.log(`Applied skin in ${count} target(s) and verified ${verified} target(s)`);
  } else if (options.mode === "verify") {
    const count = await verify(options);
    console.log(`Skin verified in ${count} target(s)`);
  } else if (options.mode === "restore") {
    const count = await restore(options);
    console.log(`Restored ${count} renderer target(s)`);
  } else {
    await watch(options);
  }
}

const invokedPath = process.argv[1]
  ? await realpath(resolve(process.argv[1])).catch(() => resolve(process.argv[1]))
  : undefined;
const modulePath = await realpath(fileURLToPath(import.meta.url));
if (invokedPath === modulePath) {
  main().catch((error) => {
    console.error(`Skin Manager injector: ${error.message}`);
    process.exitCode = 1;
  });
}
