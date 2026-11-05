# Moonfin-Core (Flutter) — contributor + AI guide

Customized fork of `Moonfin-Client/Moonfin-Core`. Flutter client for Jellyfin/Emby/Plex/Silo —
one codebase → **Android, Web, Windows** (+ iOS/macOS/Linux/Android-TV/tvOS).

## ⚠️ BRANCH MODEL — read `PLATFORM_BRANCHES.md` before editing ANY code
This repo uses **one shared base (`main`) + long-lived platform branches** (`android`, `web`,
`windows`, and `webos` off `web`). It is NOT split into per-platform repos.

**Hard rule — where a change goes:**
- Shared feature / screen / widget / logic (anything in `lib/**` that isn't platform-guarded) → **`main`**.
- Platform-only change (native host folder, that platform's manifest/build/plugin/behavior) → **that
  platform's branch** (`android` / `web` / `windows` / `webos`). Never on `main`.
- `webos` branches off `web` and has **extra deps of its own** (webOS packaging) — edit webOS-only
  things there, and keep its shared code in sync by merging `web`.

Editing the wrong branch silently ships a fix to one platform and skips the rest. When unsure → it's
shared → `main`. Keep the **per-platform divergence ledger** in `PLATFORM_BRANCHES.md` updated whenever
you add a platform override — that ledger is how the next contributor (AI or human) knows what is
platform-specific vs shared.

## Porting context
This app is receiving a feature port from the Enact/React TV app (`moonfin-smart-tv`), which is the
**UI/UX source of truth** — recreate its screens exactly, do not invent new UX.
**Provisional:** the TV app stays the truth until the maintainer confirms each reworked Flutter screen is
good; only then does this Flutter build become the reference. Do not treat `main` as the truth before
that sign-off — when a screen differs, the TV app wins. The shared backend
(scraper/picker API on `:5056/picker/api`, `:9898`) is reused unchanged; clients only call it. See the
parent `MOONFIN_PORT_SPEC.md` for the feature map, and **`PORTING_NOTES.md`** for the hard-won
per-screen gotchas (web same-origin fetch, Dio-doesn't-stream-on-web, NavigationLayout, etc.) — read it
before porting the next screen.

## UI conventions (do not miss these)
- **Action buttons** (the circular icon that expands into a labeled pill on hover/focus — Play, Delete,
  Download, Refresh, Sync, etc.) MUST use **`lib/ui/widgets/action_pill_button.dart`** (`ActionPillButton`).
  It mirrors the detail screen's secondary action button exactly: `AnimatedContainer` 200ms `Curves.ease`
  (== the TV's `transition: 0.2s ease`) and the app's own `AppColorScheme` tokens (`buttonFocused` /
  `white@0.06` fill, `onButtonFocused`/`onButtonNormal` icon, `focusColor`/`onSurface@0.35` border).
  - Do **NOT** use `ExpandableIconButton` for these (that's the nav/toolbar button; it felt choppy here),
    and do **NOT** invent button colours (no `colorScheme.primary` fills). Reuse the tokens above.
- **Colours**: use `AppColorScheme` tokens / `Theme.of(context).colorScheme`; never hardcode bespoke colours.

## Build targets (all from this one repo)
- `flutter build apk`  → Android   (edit Android-only config on the `android` branch)
- `flutter build web`  → Web        (`web` branch)   → webOS `.ipk` packaging on `webos`
- `flutter build windows` → Windows (`windows` branch)

## Remotes
- `upstream` → official `Moonfin-Client/Moonfin-Core` (sync from here).
- `origin`   → your fork `junkratroadhog/moonfin-core` (add on first push).
