# Porting notes — TV (Enact) → Flutter (core-client)

Hard-won gotchas + patterns from porting the custom Moonfin features (picker, regional, downloads, …)
from the Enact TV app into this Flutter app. **Read this before porting the next screen** — most of
these recur on every screen. The TV app (`moonfin-smart-tv`) is the UI/UX truth; recreate it exactly,
don't invent. See also `MOONFIN_PORT_SPEC.md` (feature map) and `CLAUDE.md` (branch model + UI rules).

## Web-specific gotchas (bite on nearly every screen)

1. **Fetch the shared backend SAME-ORIGIN on web.** `baseUrl` is `${Uri.base.origin}/picker/api` when
   `kIsWeb`; native derives `<jellyfin-host>:5056` (same as the TV app's `getMoonfinConnection`). The
   `coreweb` nginx (`../coreweb.nginx.conf`) proxies `/picker/` → `scraper:9898`. This avoids
   cross-origin host/scheme guessing **and** makes cached posters/images render (web CanvasKit draws
   images to a canvas → needs same-origin or CORS). Applied in `PickerService` + `DownloadsService`.
   → any NEW service that calls the scraper must do the same `kIsWeb` → same-origin branch.

2. **Dio does NOT stream on web** — its browser adapter buffers the whole response until it finishes, so
   NDJSON/progress streams all arrive at the end (no live "N/total", no progressive rows). Use a
   conditional transport: native = Dio stream, web = `fetch` + `ReadableStream.getReader()`. Pattern:
   `data/services/picker/picker_stream_transport.dart` (io/web) — mirror `settings_stream_transport.dart`.

3. **Escape/back pops the TV exit dialog.** `app.dart`'s back-key handler treats Escape as back and shows
   the exit-confirmation at the root — a TV/desktop affordance. Gate it with `kIsWeb` (a browser tab has
   no app to quit). Watch for other TV-only overlays leaking onto web.

## UI/UX reuse — do NOT invent

4. **Expand-on-hover action buttons → `ui/widgets/action_pill_button.dart` (`ActionPillButton`).** Icon
   that grows into a labeled pill on hover/focus, `AnimatedContainer` **200ms `Curves.ease`** (== the TV
   `transition: 0.2s ease`) + `AppColorScheme` tokens (`buttonFocused`/`white@0.06` fill,
   `onButtonFocused`/`onButtonNormal` icon, `focusColor`/`onSurface@0.35` border). NOT
   `ExpandableIconButton` (that's the nav/toolbar button — felt choppy). Never invent button colours
   (no `colorScheme.primary` fills).

5. **Full-screen custom routes must wrap content in `NavigationLayout`** so the always-present left
   sidebar icon-rail (expands on hover) stays. Inset the content past the collapsed rail:
   `PlatformDetection.useMobileUi ? 0.0 : 72.0` (`_kCollapsedWidthTV`). Keep `showBackButton: false` if the
   screen has its own header back button.

6. **Colours from tokens only** — `AppColorScheme` / `Theme.of(context).colorScheme`; never hardcode.

## Navigation structure (match the TV app exactly)

7. **1TamilMV / Regional is a Seerr sub-section, NOT a sidebar item.** Flow: Seerr → Regional →
   `SeerrRegionalScreen` (indexer tiles, each with Refresh / Soft Sync / Hard Sync + a header Refresh All)
   → tap tile → `RegionalCatalogScreen` (the catalog content). Wired via the `SeerrShortcut.regional`
   enum → `Destinations.seerrRegional`.

8. **Downloads / Indexers / Storage ARE admin sidebar items** (below Settings in the TV sidebar). Gate on
   Moonfin-stack availability (`PluginSyncService.seerrAvailable`) and ideally the admin role.

## Behaviour gotchas

9. **Picker auto-search:** on Download, if there's no tmdbId, search indexers by **title** (don't return
   early) so the list never shows empty without searching. Show the `N/total` indexer progress next to
   Refresh (it only renders while a stream is in flight — needs gotcha #2 to show live on web).

10. **Download role gate:** `canDownload = AUTO_APPROVE(128) || MANAGE_REQUESTS(16)`, admin(2) auto-passes
    via `hasPermission`. Guests keep the native Request button. (`SeerrMediaDetailViewModel.canDownload`.)

11. **The left-menu SEARCH** is Jellyfin library (`/Items`, owned) + Seerr-via-Moonbase (new/requestable)
    in tabs — it does NOT hit the scraper/picker. Both sources swallow errors silently (return `[]`), so
    "no results" can hide a real failure. Not a bug in the port.

12. **Picker "already downloaded" = Play/Delete + "In Library" chip** is driven ENTIRELY by
    `/grab/status` returning `completed` for the row's key (`guid || downloadUrl(=magnet) || title`, which
    the Flutter model + backend `grabKeyOf` already agree on). The completed-state UI is in
    `torrent_picker_dialog.dart`. Gotcha: a pick that finished, imported, and had its qBit torrent cleared
    while no picker was polling it left its registry row stuck at `downloading` → `/grab/status` returned
    `gone` → BOTH clients showed "Download" for a file that's actually in the library. Fixed in the SHARED
    backend `scraper-server.js` `/grab/status`: a `downloading` row absent from qBit now consults *arr
    import history (`downloadFolderImported` by infohash); if imported → `completed` (+ mark the registry).
    User-removed (`removed`) rows stay `gone`. **Play** only renders when the picker is given an `onPlay`;
    wiring it needs the app's real playback bring-up (a `PlaybackManager`/queue — `VideoPlayerScreen` takes
    no item arg), so it's a separate piece (deferred). Delete + In Library need no `onPlay`.

13. **Poster cards reuse the app's own focus treatment on hover** — `AnimatedScale` to
    `MediaCard.focusScale` + a focus-colour (`UserPreferences.focusColor`) border on the poster, 200ms
    `Curves.ease`. This mirrors the TV `.itemCard:focus { transform: scale(1.05) }` + `.poster` border AND
    the Flutter `MediaCard`'s own focus ring. Don't invent a bespoke hover effect — use these tokens.

## Screens ported (status)

- ✅ Torrent picker (`ui/widgets/picker/torrent_picker_dialog.dart`) + `data/services/picker/*`
- ✅ 1TamilMV catalog (`ui/screens/regional/regional_catalog_screen.dart`)
- ✅ Seerr→Regional indexer tiles (`ui/screens/regional/seerr_regional_screen.dart`)
- ✅ Admin Downloads manager (`ui/screens/admin/downloads/qbit_downloads_screen.dart` + `downloads_service.dart`)
- ✅ Detail "Download" button (relabel + role gate)
- ⬜ Net-new remaining: **Indexers manager**, **Storage manager**, client-log upload, year-aware search
  parity, library-delete *arr/qBit teardown.

## Deploy

- Web: `flutter build web --release` → `rsync -a --delete build/web/ webroot/` → the `moonfin-coreweb`
  nginx (`:8100`) serves `webroot` live (no restart). `coreweb` also proxies `/picker/` → scraper.
- APK / Windows `.exe`: NOT buildable on the Linux box here (no Android SDK; Windows needs a Windows
  host/CI). Use a toolchained machine or CI in `moonfin-builds`.

## Change log — every fine-tune this session (newest first, with commits)

The gotchas above are the distilled rules; this is the full trail so nothing's lost.

- picker: downloaded-content **Delete + "In Library"** restored — shared backend `/grab/status` now
  reports `completed` for an imported-but-qBit-cleared pick (consults *arr import history); the picker's
  completed-state UI was already present. (`scraper-server.js`, parent repo). Play deferred (needs the
  playback pipeline).
- catalog: **poster hover highlight** — scale to `MediaCard.focusScale` + focus-colour poster border,
  200ms `Curves.ease` (reuses the app's own card-focus treatment; matches the TV `.itemCard:focus`).
- `c13649a` picker: stream the indexer search incrementally **on web** (fetch+getReader); live `N/total`.
- `6889573` picker: auto-search indexers by **title** when no tmdbId (Download never shows empty).
- `14df0e7` nav: wrap 1TamilMV / Regional / Downloads screens in `NavigationLayout` (left sidebar stays).
- `e0751c4` buttons: smoother animation **200ms `Curves.ease`** (== TV); standardized `ActionPillButton`
  (also in `CLAUDE.md` UI rules + memory).
- `e5b6dee` picker: size↔action gap **7px** + content-sized action so an expanding button never overlaps.
- `7af023f` buttons: picker/regional use the **detail button's exact expand + colours** (`ActionPillButton`,
  `AppColorScheme` tokens) — replaced the choppy `ExpandableIconButton`/bespoke-colour attempt.
- `50677ff` picker buttons expand on hover; **no TV exit-dialog on web** (`kIsWeb` gate in `app.dart`).
- `e3d2fdc` regional indexer-tile buttons expand on hover (first pass).
- `8c5bdb5` web: fetch picker API **+ posters same-origin** (`coreweb.nginx.conf` `/picker` proxy;
  `${Uri.base.origin}/picker/api` on web) — fixed thumbnails not loading.
- `bc2204f` nav: match TV — Seerr→Regional→indexer tiles→catalog; removed the bogus sidebar item.
- `3cefe93` **Downloads manager** (admin qBit) — net-new port of the TV Downloads view.
- `8c64b82` detail "Pick Torrent" → **"Download"**, download-arrow icon, gated to downloader role.
- `665da5a` **1TamilMV catalog** reworked to the TV SeerrIndexerCatalog (two sections, hover backdrop).
- `b686ae3` **Torrent picker** reworked to the TV SelectTorrentPopup (glass card, streaming, split Sort +
  Quality chips, remembered filters, loader, per-row Download/Cancel/In-Library/Delete).
- `df6944f` / `eca294e` docs: provisional-truth rule + platform-branch model.

**Infra (in the parent `moonfin/` repo, not this one):** added the `moonfin-coreweb` nginx container
(`:8100`, serves `core-client/webroot`, proxies `/picker/` → scraper) in `docker-compose.yml` +
`coreweb.nginx.conf`.
