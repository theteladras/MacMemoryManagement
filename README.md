# MacMemClean

A native macOS storage-cleanup app — finds caches, logs, developer junk, large/old files,
duplicates, compressible files, and uninstallable apps with leftovers, and shows you exactly
what will be removed (and why it's rated safe or not) before anything is deleted.

## Features

- **Overview dashboard** — a segmented capacity bar (à la "About This Mac → Storage") that's
  tappable per segment for a one-level drill-down (e.g. what's actually inside Documents &
  Desktop), a file-type breakdown (photos/video/audio/docs, wherever they're hiding on disk), a
  storage-over-time trend chart, and a one-click **Quick Clean** that scans and lands you straight
  in the Review screen.
- **Storage Explorer** — a drill-down folder tree, sized on demand as you expand each folder, so
  opening it never has to walk the whole disk up front.
- **Caches & Junk** — known-safe cache, log, browser-cache, developer-tool, and Trash locations.
- **Large & Old Files** — configurable size/age thresholds, any folder.
- **Duplicates** — hash-based, keeps the oldest copy selected by default.
- **Compress Files** — transparent, lossless APFS compression (via `ditto --hfsCompression`, the
  same mechanism macOS uses for its own system files) for compressible file types. Files stay
  byte-identical when opened — verified with `cmp` before ever touching the original — they just
  use less space on disk.
- **Applications** — uninstaller that finds an app's leftover Application Support/Caches/
  Preferences/Saved State/Container files elsewhere on disk, grouped by kind, with "last used"
  dates (via Spotlight metadata) and a "clean leftovers only, keep the app" option.
- **History** — a permanent log of everything actually deleted (and anything that failed, with
  why), independent of any single scan's on-screen results.
- **Automatic Cleanup** — an optional background check (configurable frequency and
  aggressiveness) that proposes a cleanup via an approval banner + system notification — it only
  ever *finds* things, exactly like a manual scan; nothing is deleted without you confirming in
  the Review screen.
- **Menu bar** — MacMemClean lives in the menu bar so the background check keeps running with the
  window closed; the dropdown shows a live capacity bar plus quick actions.
- **AI Assist (optional)** — an "Ask AI what this is" button per item in the Review screen, for
  when you don't recognize a file. Only sends metadata (name, path, size, dates) to the Anthropic
  API, never file contents, and is completely inert until you add your own API key in Settings.

## Safety model

Every scanner only ever *finds* things — `[ScanItem]` results, never a deletion. Selections flow
into a `ReviewManifest`, and the Review Sheet is the single mandatory gate before
`SafeDeleteService` runs: itemized list grouped by category, full paths, a per-item safety rating
(Safe / Caution / Personal — review), and a running "you'll free up X" total. Deletion defaults to
moving items to the Trash (recoverable); permanent deletion is an explicit, separate choice.

Every item gets an automatic safety rating (`SafetyAssessor`) from its category *and* its content —
a cache folder is `Safe`; a `.heic` in Downloads or a `.docx` in Documents is `Personal`,
regardless of size or age. Only `Safe` items are ever pre-selected after a scan; personal/caution
items are always visible but require you to check them by hand. Flows that hand over raw,
unfiltered results (Quick Clean, the background auto-cleanup) apply the same rule via
`ReviewManifest.preExcludedIDs` — caution/personal items start unchecked there too, exactly like a
manually curated selection would.

## Requirements

- macOS 13 Ventura or later, Xcode 14+ (Swift 5.7+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — generates the
  `.xcodeproj` from `project.yml`. The `.xcodeproj` itself isn't committed (see `.gitignore`);
  regenerate it any time with `xcodegen generate`.

## Build & run

```sh
xcodegen generate
open MacMemClean.xcodeproj   # then Cmd+R in Xcode
```

or from the command line:

```sh
xcodegen generate
xcodebuild -scheme MacMemClean -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/MacMemClean-*/Build/Products/Debug/MacMemClean.app
```

## Full Disk Access

MacMemClean is **not sandboxed** (distributed outside the App Store on purpose — see "Why not
sandboxed?" below), so it can reach system-wide caches, logs, and other apps' leftover files. To
scan those locations, grant it Full Disk Access:

**System Settings → Privacy & Security → Full Disk Access → enable MacMemClean**

The in-app **Permissions** screen shows current status and links straight there — it's also where
you'd come back to grant this later if you skipped it initially. Without it, the app still works
fully for your own files (Downloads, Documents, per-app caches in `~/Library`) — system-wide
locations are just skipped with a note instead of erroring, and reads that would otherwise hang on
a blocked permission prompt are hard-capped with a timeout so nothing in the app can freeze.

### Why not sandboxed?

A Mac App Store build must run inside Apple's sandbox, which would only let it touch its own
container and files the user explicitly picks one at a time — it couldn't see `~/Library/Caches`,
system logs, or other apps' support files, which is most of what a cleaner app needs to find.
Distributing outside the App Store (direct download, notarized for a real release) trades App
Store convenience for that capability, same as DaisyDisk/CleanMyMac.

## Distribution (building a DMG)

```sh
./scripts/build-dmg.sh
```

This builds a Release configuration and packages it into `dist/MacMemClean.dmg` (the app plus an
`Applications` shortcut, the standard drag-to-install layout). See the comment block at the top of
the script for the full explanation, but the short version:

**This repo has no Apple Developer Team configured**, so the build is only ad-hoc signed, not
signed with a real Developer ID and not notarized. Anyone you hand the DMG to will hit a Gatekeeper
warning on first launch (macOS refuses to just double-click-open software from an "unidentified
developer" that was downloaded from the internet). They can get past it by right-clicking the app
in `Applications` → **Open** → confirming once, or via **System Settings → Privacy & Security →
Open Anyway** after the first blocked attempt.

To distribute without that warning, you'd need an Apple Developer Program membership ($99/year), a
Developer ID Application certificate, and to notarize the build with `notarytool` — a deliberate,
separate step this script doesn't do automatically.

## Project layout

```
MacMemClean/
  App/            App entry point, AppDelegate (keeps the app alive for the menu bar), AppState
  Models/         ScanItem, ScanCategory, SafetyLevel, ReviewManifest, DiskUsageSummary, ...
  Core/           Scanners (Junk/LargeOldFiles/Duplicate/Compression/AppUninstaller/FileType),
                  SafeDeleteService, SafetyAssessor, ProtectedPaths, PermissionsManager,
                  BackgroundCleanupScheduler, KeychainService, AIAssistService, ...
  ViewModels/     One per screen — Overview, JunkScan, LargeOldFiles, Duplicates, Compression,
                  Uninstaller, StorageTree
  Views/          One folder per screen, plus Components/ (shared building blocks) and MenuBar/
  Resources/      Assets.xcassets (app icon), entitlements
scripts/
  build-dmg.sh    Release build + DMG packaging (see Distribution above)
```

## Not yet implemented

- Real code signing / notarization for distributing outside this machine without a Gatekeeper
  warning (see Distribution above)
- Launch-at-login is available (Settings / menu bar), but there's no full menu-bar-only "agent"
  mode (no Dock icon) — the app currently keeps a normal Dock presence alongside the menu bar icon
- On-device/local AI as an alternative to the cloud-based AI Assist — Apple's on-device Foundation
  Models framework would be the natural fit, but it requires macOS 26+, well above this project's
  macOS 13 deployment target, so it'd need to be wired in as an optional, runtime-gated path
  rather than a replacement
