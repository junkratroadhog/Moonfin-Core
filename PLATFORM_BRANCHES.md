# Moonfin-Core — Platform Branch Model (READ BEFORE EDITING)

> ⚠️ **AI + human contributors: read this first.** Editing the wrong branch here silently ships a
> fix to one platform and skips the others — or breaks a platform that had a deliberate override.
> This file is the single source of truth for *what differs per platform and where to change it.*

This is **one repository** (Flutter). It is **not** split into separate per-platform repos — Android,
Web, and Windows build from the **same** Dart code. Platform differences are handled with **long-lived
platform branches layered on a shared base**, not code duplication.

## Branch map

```
main  ← SHARED BASE. All feature/UI/logic work lands here. Undisturbed by platform-only edits.
 ├── android   ← Android-only divergence (manifest, Gradle, Android plugins/perms, Media3, TV)
 ├── web        ← Web-only divergence (web/index.html, canvaskit, web download/storage shims)
 │    └── webos ← Web build repackaged for LG webOS. Branches off `web`, NOT main.
 │               ADDITIONAL DEPENDENCIES live only here (appinfo.json, webOS libs, .ipk packaging).
 └── windows   ← Windows-only divergence (windows/runner, MSIX, media_kit windows libs)
```

- **`upstream`** remote → `https://github.com/Moonfin-Client/Moonfin-Core.git` (official, for syncing).
- **`origin`** remote → **your fork** (`junkratroadhog/moonfin-core`), added on first push.

## The golden rules (where does my change go?)

| What you're changing | Branch to edit |
|---|---|
| A feature, screen, widget, bug in **shared Dart** (`lib/**` that isn't platform-guarded) | **`main`** |
| Android manifest / Gradle / Android plugin / Android-only runtime behavior | **`android`** |
| `web/index.html`, web build config, a `*_web.dart` web shim | **`web`** |
| webOS packaging / `appinfo.json` / webOS-only deps / `.ipk` build | **`webos`** (off `web`) |
| `windows/runner`, MSIX, Windows-only plugin/behavior | **`windows`** |

**If a change belongs on `main` but you make it on a platform branch, the other platforms never get
it.** When unsure, it's shared → put it on `main`.

## Propagating shared work (main → platform branches)

After shared work lands on `main`, fan it out so every platform picks it up:

```bash
for b in android web windows; do
  git checkout "$b" && git merge main    # resolve conflicts only in that platform's overridden files
done
git checkout webos && git merge web      # webos tracks web, which already merged main
```

Only files a branch has *deliberately overridden* should ever conflict. If a shared file conflicts on a
platform branch, that's a signal it was wrongly edited on the branch — move the shared part back to `main`.

## Per-platform divergence ledger (KEEP THIS UPDATED)

The whole point of this file: an at-a-glance list of **exactly which files/areas are platform-specific**,
so no one edits a shared file thinking it's platform-specific (or vice-versa). Update this list whenever
you add a platform-only override.

### Shared (on `main`, identical everywhere) — do NOT special-case per platform
- All of `lib/**` except the guarded files listed below.
- The reworked Torrent Picker (`lib/ui/widgets/picker/`, `lib/data/services/picker/`) — fully shared.

### Already platform-aware *within shared code* (stay on `main`; they branch at runtime, not per git-branch)
- `kIsWeb` / `Platform.is*` guards (~17 files each) and conditional imports (~25 files).
- `*_web.dart` / `*_io.dart` pairs (e.g. `data/services/web_download_helper_*`,
  `settings_stream_transport_*`). These are the correct Flutter way to differ web vs native — keep them
  on `main`; do not move them to platform branches.

### `android` branch overrides
- _(none yet — add entries as you create them, e.g. `android/app/build.gradle`, `AndroidManifest.xml`)_

### `web` branch overrides
- _(none yet — e.g. `web/index.html`, canvaskit config)_

### `webos` branch overrides (⚠️ extra dependencies — this branch alone)
- _(none yet — e.g. `webos/appinfo.json`, webOS packaging scripts, `.ipk` build config, webOS
  polyfills/libs. This branch builds the Flutter **web** output, then wraps it for webOS.)_

### `windows` branch overrides
- _(none yet — e.g. `windows/runner/*`, MSIX config, media_kit windows libs)_

## Not this repo
- **webOS *Enact/React* app** (`moonfin-smart-tv`) is a **separate** project and the UI/UX **source of
  truth** for the port. The `webos` branch here is a *different* thing (Flutter web wrapped for webOS).
  Don't confuse them.

## Checkpoints
- `backup/old-<date>` branch + `checkpoint-old-<date>` tag mark restore points. Tag before risky work.
