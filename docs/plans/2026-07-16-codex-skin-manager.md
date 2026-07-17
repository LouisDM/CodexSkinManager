# Codex Skin Manager Implementation Plan

> Historical implementation plan. Its original private-only asset assumptions were superseded by the versioned `1.0.1` public non-commercial release contract in `docs/skin-manager/ARCHITECTURE.md`.

> **For Claude:** Use `${SUPERPOWERS_SKILLS_ROOT}/skills/collaboration/executing-plans/SKILL.md` to implement this plan task-by-task.

**Goal:** Build and install a native macOS SwiftUI app that safely imports, previews, applies, switches, restores, deletes, and exports declarative `.codexskin` packages without modifying the official Codex app.

**Architecture:** A Swift package contains a testable `SkinCore` library and a `CodexSkinManager` SwiftUI executable. `SkinCore` validates a store-only ZIP v1 container, persists installed skins atomically, checks the official app, and drives a manager-owned generic CDP helper; skin packages contain only JSON, raster assets, previews, rights, and licenses. Nightblade and Red Lotus are built-in signed templates selected by package metadata, while all package-provided values cross the CDP boundary as structured data.

**Tech Stack:** Swift 6.3, SwiftUI/AppKit, Foundation/CryptoKit, XCTest, Node.js manager-owned CDP helper, Playwright Chromium integration tests, Python app-bundle packaging tests, macOS `codesign` and `xcodebuild`/SwiftPM.

---

### Task 1: Scaffold the Swift package and define the package contract

**Files:**
- Create: `skin-manager/Package.swift`
- Create: `skin-manager/Sources/SkinCore/SkinPackageModels.swift`
- Create: `skin-manager/Tests/SkinCoreTests/SkinPackageModelsTests.swift`

**Step 1: Create the SwiftPM manifest and failing model tests**

Create a macOS 13 package with library target `SkinCore`, executable target `CodexSkinManager`, and test target `SkinCoreTests`. Write tests that decode a v1 manifest containing `schemaVersion`, reverse-DNS-safe `id`, SemVer `version`, built-in `template`, `minManagerVersion`, file descriptors, author, and optional base64 Ed25519 public key. Write separate tests for `theme.json` token/media slots and `rights.json` export policy.

**Step 2: Run the test and verify RED**

Run: `cd skin-manager && swift test --filter SkinPackageModelsTests`

Expected: FAIL because `SkinManifest`, `SkinTheme`, `SkinRights`, and validation errors do not exist.

**Step 3: Implement the minimal Codable models and validation**

Implement strongly typed models and a validator that accepts only schema `1`, `[a-z0-9][a-z0-9.-]{2,63}`, `major.minor.patch`, known template IDs, relative normalized file paths, SHA-256 hex, and approved media slots. Keep product actions and DOM selectors out of the schema.

**Step 4: Verify GREEN and commit**

Run: `cd skin-manager && swift test --filter SkinPackageModelsTests`

Expected: all model tests pass with no warnings.

Commit: `feat: define codex skin package contract`

### Task 2: Implement the restricted `.codexskin` container reader

**Files:**
- Create: `skin-manager/Sources/SkinCore/StoredZipArchive.swift`
- Create: `skin-manager/Sources/SkinCore/SkinPackageImporter.swift`
- Create: `skin-manager/Tests/SkinCoreTests/StoredZipArchiveTests.swift`
- Create: `skin-manager/Tests/SkinCoreTests/SkinPackageImporterTests.swift`

**Step 1: Write archive attack tests first**

Build tiny in-memory store-only ZIP fixtures and assert rejection of absolute paths, `..`, backslashes, NUL, path depth over 8, Unicode/case-fold collisions, duplicate central-directory entries, symlinks, encrypted entries, non-store compression, nested archives, more than 128 files, package size over 64 MiB, expanded size over 128 MiB, a file over 32 MiB, and compression ratios over 100:1. Assert CRC-32 and local/central header agreement.

**Step 2: Verify RED**

Run: `cd skin-manager && swift test --filter StoredZipArchiveTests`

Expected: FAIL because the archive reader is absent.

**Step 3: Implement a bounded store-only ZIP parser**

Parse EOCD, central-directory records, and local headers directly from `Data`; accept methods `0` only because PNG/JPEG are already compressed. Normalize paths with UTF-8 NFC plus case folding before collision checks. Never call `unzip`, never follow links, and expose entry bytes only after all bounds and CRC checks pass.

**Step 4: Write importer behavior tests and verify RED**

Assert the importer requires exactly one root `manifest.json`, `theme.json`, `rights.json`, preview, declared licenses, and declared raster assets; rejects undeclared files, JS/shell/binaries, `@import`, remote URLs, SVG/font/animated media, mismatched bytes/hashes/MIME/dimensions, unsupported template/API versions, and invalid signatures.

**Step 5: Implement validated import**

Use ImageIO to decode PNG/JPEG, enforce a total pixel budget, re-encode to fresh PNG/JPEG without metadata, verify SHA-256 before sanitization, and return an immutable staged package plus trust state (`verified`, `unknownKey`, `unsigned`). Verify optional Ed25519 signatures over the exact `manifest.json` bytes with CryptoKit.

**Step 6: Run focused and full tests, then commit**

Run: `cd skin-manager && swift test --filter 'StoredZipArchiveTests|SkinPackageImporterTests'`

Expected: all import/security tests pass.

Commit: `feat: validate restricted codex skin archives`

### Task 3: Add atomic repository, active state, and safe export

**Files:**
- Create: `skin-manager/Sources/SkinCore/SkinRepository.swift`
- Create: `skin-manager/Sources/SkinCore/SkinPackageExporter.swift`
- Create: `skin-manager/Tests/SkinCoreTests/SkinRepositoryTests.swift`
- Create: `skin-manager/Tests/SkinCoreTests/SkinPackageExporterTests.swift`

**Step 1: Write failing repository tests**

Use temporary homes to assert atomic install under `skins/<id>/<version>`, stable inventory sorting, duplicate id/version/hash handling, rollback after injected filesystem failure, active-state persistence, refusal to delete the active skin, and cleanup of abandoned staging directories.

**Step 2: Verify RED**

Run: `cd skin-manager && swift test --filter SkinRepositoryTests`

Expected: FAIL because repository APIs are missing.

**Step 3: Implement minimal repository APIs**

Implement `importPackage`, `listInstalled`, `setActive`, `clearActive`, and `delete`. Write JSON via a sibling temporary file and use same-volume rename for commit. Do not touch paths outside `~/Library/Application Support/CodexSkinManager`.

**Step 4: Write failing export tests**

Assert export is blocked unless `rights.redistributionAllowed == true`; assert store-only ZIP output is deterministic, contains no undeclared files, round-trips through the importer, and never carries manager runtime code.

**Step 5: Implement export writer and verify GREEN**

Generate local/central headers and EOCD with fixed ordering and preserved manifest bytes. Export to a temporary sibling then atomically replace the chosen destination.

Run: `cd skin-manager && swift test --filter 'SkinRepositoryTests|SkinPackageExporterTests'`

Commit: `feat: persist and export validated skins`

### Task 4: Generalize the CDP renderer and package the two Meng Chuan templates

**Files:**
- Create: `skin-manager/Sources/CodexSkinManager/Resources/Engine/injector.mjs`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/Engine/renderer-inject.js`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/Templates/nightblade-v1.css`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/Templates/red-lotus-v1.css`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/nightblade/manifest.json`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/nightblade/theme.json`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/nightblade/rights.json`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/red-lotus/manifest.json`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/red-lotus/theme.json`
- Create: `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/red-lotus/rights.json`
- Create: `tests/test_skin_manager_cdp_engine.mjs`
- Create: `tests/test_builtin_skin_packages.py`
- Modify: `package.json`

**Step 1: Write failing generic engine tests**

Adapt the proven Nightblade CDP tests to assert one manager state key/style/chrome node, structured theme switching, generic asset-slot inlining, built-in template allowlisting, loopback-only WebSocket validation, `app://` target filtering, once/watch/verify/restore, navigation/new-window repair, and persistent restore.

**Step 2: Verify RED**

Run: `node --test tests/test_skin_manager_cdp_engine.mjs`

Expected: FAIL because the generic engine resources are missing.

**Step 3: Implement the generic manager-owned engine**

Refactor the existing Nightblade injector behavior into a manager engine that accepts only an installed skin directory plus a manager-owned template ID. Load asset paths declared by validated theme data, convert them to data URLs, and pass `{skinId, version, templateId, tokens, assets}` to a fixed renderer function through CDP arguments. Never evaluate package-provided code or CSS.

**Step 4: Add failing built-in package tests**

Assert both packages use built-in templates, include required preview/media/license/rights metadata, remain private-only while current asset rights are unresolved, and produce no public export. Assert Nightblade template preserves its current responsive/focus/reduced-motion contracts; assert Red Lotus source is migrated from the existing local implementation without weakening CDP security.

**Step 5: Add templates and private packages**

Copy the current Nightblade and Red Lotus visual CSS into signed app template resources. Place only data and rights metadata in package directories. Use `redistributionAllowed: false` for both current Meng Chuan packages.

**Step 6: Verify and commit**

Run: `npm run test:manager-engine && python3 tests/test_builtin_skin_packages.py`

Commit: `feat: add safe skin templates and generic cdp engine`

### Task 5: Implement official-app inspection and application state machine

**Files:**
- Create: `skin-manager/Sources/SkinCore/CodexAppInspector.swift`
- Create: `skin-manager/Sources/SkinCore/SkinApplicationController.swift`
- Create: `skin-manager/Sources/SkinCore/ProcessRunner.swift`
- Create: `skin-manager/Tests/SkinCoreTests/CodexAppInspectorTests.swift`
- Create: `skin-manager/Tests/SkinCoreTests/SkinApplicationControllerTests.swift`

**Step 1: Write failing inspector tests**

Inject a process runner and assert exact fixed-argument `codesign --verify --deep --strict`, app executable/bundled Node checks, loopback port conflict handling, listener executable verification, and no write under the app bundle. Include a fixture representing the machine's current invalid-signature state and expect Apply to be disabled while import remains available.

**Step 2: Verify RED, implement, verify GREEN**

Run: `cd skin-manager && swift test --filter CodexAppInspectorTests`

Implement fixed-command process execution without shell interpolation. Treat any signature failure as blocking for Apply and return user-facing diagnostics.

**Step 3: Write failing state-machine tests**

Cover `idle → checking → waitingForQuit → startingCodex → applying → active`, cancellation while waiting, active-skin switching, previous-skin rollback after injection failure, bounded watcher restart, restore, and delete-current refusal. Assert the controller never sends SIGKILL/SIGTERM to the Codex app.

**Step 4: Implement the minimal controller**

Use dependency-injected app lifecycle, engine launcher, repository, clock, and status sink. Launch Codex through `NSWorkspace.OpenConfiguration` with `--remote-debugging-address=127.0.0.1` and port `9340`; launch only the manager-owned helper with the official bundled Node. Persist PID/log files in the manager state directory.

**Step 5: Verify and commit**

Run: `cd skin-manager && swift test --filter 'CodexAppInspectorTests|SkinApplicationControllerTests'`

Commit: `feat: manage safe codex skin application lifecycle`

### Task 6: Build the native SwiftUI library, preview, and settings UI

**Files:**
- Create: `skin-manager/Sources/CodexSkinManager/CodexSkinManagerApp.swift`
- Create: `skin-manager/Sources/CodexSkinManager/AppModel.swift`
- Create: `skin-manager/Sources/CodexSkinManager/ContentView.swift`
- Create: `skin-manager/Sources/CodexSkinManager/SkinLibraryView.swift`
- Create: `skin-manager/Sources/CodexSkinManager/SkinDetailView.swift`
- Create: `skin-manager/Sources/CodexSkinManager/SettingsView.swift`
- Create: `skin-manager/Sources/CodexSkinManager/TerminationCoordinator.swift`
- Create: `skin-manager/Tests/SkinCoreTests/AppPresentationTests.swift`

**Step 1: Write failing presentation-model tests**

Assert sidebar filters, trust badges, rights labels, Apply/Restore/Delete/Export enablement, progress copy for every controller state, signature-error banner, long author/name handling, and private-only export messaging.

**Step 2: Verify RED and implement the app model**

Run: `cd skin-manager && swift test --filter AppPresentationTests`

Keep all button enablement and copy in testable presentation values rather than hiding logic in SwiftUI view bodies.

**Step 3: Implement the SwiftUI shell**

Use a neutral graphite `NavigationSplitView`, skin cards, large preview/details, drag-and-drop import, `onOpenURL` document opening, import panel, status/progress, Apply/Restore/Delete/Export actions, settings/log view, keyboard shortcuts, accessibility labels, reduced-motion behavior, and a `MenuBarExtra` status item. Do not theme the manager UI with the selected Codex skin.

**Step 4: Implement termination behavior**

When the manager owns an active watcher, intercept Quit with an AppKit alert offering “restore and quit”, “leave current page styled and quit watcher”, or cancel. Never terminate Codex.

**Step 5: Build and commit**

Run: `cd skin-manager && swift test && swift build`

Expected: all Swift tests pass and both debug products compile with no warnings.

Commit: `feat: add native codex skin manager interface`

### Task 7: Bundle, install, and register `.codexskin`

**Files:**
- Create: `skin-manager/Resources/Info.plist`
- Create: `scripts/build_codex_skin_manager_app.py`
- Create: `tests/test_codex_skin_manager_bundle.py`
- Modify: `README.md`
- Modify: `.gitignore`

**Step 1: Write the failing bundle contract test**

Assert the built app contains the executable and resources, is executable, has bundle ID `com.opcspace.codex-skin-manager`, declares `com.opcspace.codexskin` and extension `codexskin`, supports macOS 13+, uses high-resolution rendering, has no worktree absolute paths, is ad-hoc signed for local installation, and installs only under the requested destination plus manager Application Support.

**Step 2: Verify RED**

Run: `python3 tests/test_codex_skin_manager_bundle.py`

Expected: FAIL because the bundle builder and app do not exist.

**Step 3: Implement deterministic app bundling**

Build release with SwiftPM, stage `Codex 皮肤管理器.app`, copy the executable/resources/Info.plist, ad-hoc sign locally, verify with `codesign --verify --deep --strict`, and atomically install to `~/Applications`. Do not alter `/Applications/ChatGPT.app` and do not overwrite legacy launchers.

**Step 4: Verify, document, and commit**

Run: `python3 tests/test_codex_skin_manager_bundle.py --install`

Commit: `build: package native codex skin manager app`

### Task 8: Automated end-to-end verification and handoff

**Files:**
- Create: `tests/test_skin_manager_end_to_end.py`
- Create: `docs/screenshots/codex-skin-manager.png`
- Modify: `package.json`
- Modify: `README.md`

**Step 1: Write an end-to-end test around a temporary home**

Build a valid fixture `.codexskin`, import it through the app's diagnostic CLI entry point, assert inventory/preview/trust/rights state, reject attack fixtures, export only a rights-cleared fixture, and verify install/delete/active-state rollback. Launch the manager app in a seeded UI-test mode and verify it remains running with its main window.

**Step 2: Exercise the generic CDP engine against real Chromium**

Run both built-in templates through apply, verify, switch, navigation, new window, restore, and watcher shutdown. Verify only `127.0.0.1:9340` is accepted and hostile WebSocket URLs are rejected.

**Step 3: Run the complete fresh verification matrix**

Run:

```bash
cd skin-manager && swift test && swift build -c release
cd .. && npm run test:manager && python3 tests/test_codex_skin_manager_bundle.py --installed
python3 skills/redesign-codex-ui/scripts/validate_theme_library.py skills/redesign-codex-ui/assets/theme-library
python3 tests/test_nightblade_theme.py
python3 tests/test_source_installer.py
npm run test:cdp
/usr/bin/codesign --verify --deep --strict "$HOME/Applications/Codex 皮肤管理器.app"
git diff --check
```

Expected: all tests/builds exit `0`; official ChatGPT signature failure is reported as an external blocked-Apply fixture, not hidden or changed.

**Step 4: Visual and accessibility QA**

Inspect the real app window at wide and compact sizes; verify drag target, keyboard focus, VoiceOver labels, reduced-motion state, long metadata, missing preview, private-rights warning, invalid-signature banner, progress, and error presentation. Save one representative screenshot.

**Step 5: Independent review and final commit**

Review security, package parser, process lifecycle, official-app non-modification, rights gating, and installed bundle/source equality. Fix every Critical/Important issue with a failing regression test, rerun the full matrix, and commit the verified handoff.
