#!/usr/bin/env node

import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { chromium } from "playwright";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const RESOURCES = join(ROOT, "skin-manager", "Sources", "CodexSkinManager", "Resources");
const ENGINE = join(RESOURCES, "Engine");
const TEMPLATES = join(RESOURCES, "Templates");
const INJECTOR = join(ENGINE, "injector.mjs");
const RENDERER = join(ENGINE, "renderer-inject.js");
const DEFAULT_BROWSER = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function parseArguments(argv) {
  const options = {
    source: undefined,
    output: undefined,
    browserExecutable: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || DEFAULT_BROWSER,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--source") options.source = resolve(argv[++index]);
    else if (value === "--output") options.output = resolve(argv[++index]);
    else if (value === "--browser-executable") options.browserExecutable = resolve(argv[++index]);
    else throw new Error(`Unknown argument: ${value}`);
  }
  if (!options.source) throw new Error("--source is required");
  if (!options.output) options.output = join(options.source, "preview.png");
  return options;
}

async function prepareSkinRoot(sourceRoot) {
  const skin = JSON.parse(await readFile(join(sourceRoot, "skin.json"), "utf8"));
  const temporary = await mkdtemp(join(tmpdir(), "codex-skin-preview-"));
  await writeFile(join(temporary, "manifest.json"), JSON.stringify({
    schemaVersion: skin.schemaVersion,
    id: skin.id,
    name: skin.name,
    version: skin.version,
    template: skin.template,
  }));
  await writeFile(join(temporary, "theme.json"), JSON.stringify(skin.theme));

  for (const assetPath of Object.values(skin.theme.assets ?? {})) {
    const from = join(sourceRoot, assetPath);
    const to = join(temporary, assetPath);
    await mkdir(dirname(to), { recursive: true });
    await copyFile(from, to);
  }
  return temporary;
}

function previewHtml() {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; }
    html, body, #root { width: 100%; height: 100%; margin: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
      background: #05080d;
      color: #f1f5f7;
      overflow: hidden;
    }
    #root {
      display: grid;
      grid-template-columns: 252px minmax(0, 1fr);
      min-height: 100vh;
    }
    nav.sidebar-foreground-muted {
      position: relative;
      display: flex;
      flex-direction: column;
      gap: 4px;
      min-width: 0;
      height: 100vh;
      padding: 12px 10px;
      color: #bbc9d3;
    }
    .sidebar-row {
      order: 0;
      min-height: 34px;
      padding: 8px 10px;
      border-radius: 7px;
      color: inherit;
      font-size: 13px;
    }
    .sidebar-row.active { color: #f1f5f7; }
    .sidebar-spacer { flex: 1 1 auto; }
    .account {
      margin-top: auto;
      border-top: 1px solid rgb(255 255 255 / 0.08);
      color: #8fa0ad;
      font-size: 12px;
    }
    main.main-surface {
      position: relative;
      min-width: 0;
      min-height: 100vh;
      border-left: 1px solid rgb(255 255 255 / 0.07);
      overflow: hidden;
    }
    div[role="main"].container-name\\:home-main-content {
      position: relative;
      display: flex;
      flex-direction: column;
      justify-content: center;
      gap: 26px;
      width: 100%;
      height: 100vh;
      padding: 78px clamp(44px, 7vw, 116px);
      overflow: hidden;
    }
    .group\\/home-suggestions {
      width: min(720px, 58vw);
    }
    .group\\/home-suggestions > div:last-child > div {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 13px;
    }
    .suggestion {
      min-height: 82px;
      padding: 16px;
      color: #dce8ee;
      font-size: 14px;
      line-height: 1.45;
    }
    .composer-surface-chrome {
      width: min(740px, 62vw);
      min-height: 72px;
      padding: 18px 20px;
      border-radius: 13px;
      color: #91a8b6;
      font-size: 14px;
    }
    h1 { margin: 0; }
  </style>
</head>
<body>
  <div id="root">
    <nav class="sidebar-foreground-muted">
      <div class="sidebar-row active" aria-current="page">任务 · 新皮肤验证</div>
      <div class="sidebar-row">导入流程</div>
      <div class="sidebar-row">运行时应用</div>
      <div class="sidebar-row">回归测试</div>
      <div class="sidebar-spacer"></div>
      <div class="sidebar-row account">OPCspace</div>
    </nav>
    <main class="main-surface">
      <div role="main" class="container-name:home-main-content">
        <h1>Codex</h1>
        <div class="group/home-suggestions">
          <div></div>
          <div>
            <div>
              <div class="suggestion">检查导入 manifest、rights 和 assets</div>
              <div class="suggestion">应用模板并验证 Root Class</div>
              <div class="suggestion">回导包并对比 SHA-256</div>
              <div class="suggestion">记录可复现问题和优化项</div>
            </div>
          </div>
        </div>
        <div class="composer-surface-chrome">Ask Codex to validate this skin...</div>
      </div>
    </main>
  </div>
</body>
</html>`;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (!existsSync(options.browserExecutable)) {
    throw new Error(`Browser executable not found: ${options.browserExecutable}`);
  }
  const skinRoot = await prepareSkinRoot(options.source);
  try {
    const injector = await import(`${pathToFileURL(INJECTOR)}?preview=${Date.now()}`);
    const payload = await injector.buildPayload(skinRoot, TEMPLATES);
    const renderer = await readFile(RENDERER, "utf8");
    const browser = await chromium.launch({
      headless: true,
      executablePath: options.browserExecutable,
    });
    try {
      const page = await browser.newPage({
        viewport: { width: 1600, height: 1000 },
        deviceScaleFactor: 1,
      });
      await page.setContent(previewHtml(), { waitUntil: "load" });
      await page.evaluate(
        ({ source, payload: nextPayload }) => (0, eval)(source)(nextPayload),
        { source: renderer, payload },
      );
      await page.screenshot({ path: options.output, type: "png" });
      console.log(`Rendered ${payload.skinId} ${payload.template} preview to ${options.output}`);
    } finally {
      await browser.close();
    }
  } finally {
    await rm(skinRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
