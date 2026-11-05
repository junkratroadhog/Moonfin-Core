import 'dart:async';
import 'dart:ui' show ImageFilter, FontFeature;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/picker/picker_models.dart';
import '../../../data/services/picker/picker_service.dart';
import '../action_pill_button.dart';
import '../detail_glyph.dart';

// "Pick a Torrent" — a faithful Flutter port of the TV app's SelectTorrentPopup
// (tv-client/packages/app/src/components/seerr/SelectTorrentPopup.js + .module.less).
// Themed dark-glass card on a dimmed, blurred backdrop using the app's own theme tokens
// (colorScheme.primary == --theme-accent, .surface == --theme-surface, .onSurface == --theme-on-surface)
// so it matches the rest of the app. Streams per-indexer; NO filtering — pick any release, it downloads.

// ---- helpers (mirrors of the TV module) ----------------------------------------------------------

String _fmtSize(int b) {
  if (b <= 0) return '?';
  if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
  return '${(b / 1048576).round()} MB';
}

final RegExp _tamilPrefix = RegExp(r'^www\.1TamilMV\.[a-z]+ - ', caseSensitive: false);
String _cleanTitle(String? t) => (t ?? '').replaceAll(_tamilPrefix, '');

String _keyOf(TorrentRelease r) =>
    r.guid.isNotEmpty ? r.guid : (r.downloadUrl?.isNotEmpty == true ? r.downloadUrl! : r.title);

const Map<String, int> _qrankMap = {
  '2160p': 4, '4k': 4, 'uhd': 4, '1080p': 3, '720p': 2, '480p': 1, 'cam': 0, 'sd': 0,
};
int _qrank(String? q) => _qrankMap[(q ?? '').toLowerCase()] ?? 0;

// Normalise titles AND the search query the same way so "season 2" / "s2" both match "S02".
final RegExp _seasonWord = RegExp(r'season\s*0*(\d+)');
final RegExp _seasonShort = RegExp(r'\bs0*(\d+)(?=\D|$)');
String _normSearch(String? s) => (s ?? '')
    .toLowerCase()
    .replaceAllMapped(_seasonWord, (m) => 's${m[1]!.padLeft(2, '0')}')
    .replaceAllMapped(_seasonShort, (m) => 's${m[1]!.padLeft(2, '0')}');

// Sort categories, matching the TV CATS array.
class _SortCat {
  final String label;
  final num Function(TorrentRelease) val;
  const _SortCat(this.label, this.val);
}

final List<_SortCat> _cats = [
  _SortCat('Size', (r) => r.size),
  _SortCat('Seeders', (r) => r.seeders),
  _SortCat('Quality', (r) => _qrank(r.quality) * 1e13 + r.size),
];

// Per-release download state keyed by _keyOf(release).
class _Dl {
  final String status; // sending | downloading | completed | failed
  final double progress; // 0..1
  final String? hash;
  const _Dl(this.status, {this.progress = 0, this.hash});
}

// Remembered Sort/Quality across popups (SharedPreferences, mirrors the TV localStorage mfp.* keys).
const _kQuality = 'mfp.quality';
const _kSortCat = 'mfp.sortCat';
const _kSortDir = 'mfp.sortDir';

// ---- entry point ---------------------------------------------------------------------------------

void showTorrentPickerDialog(
  BuildContext context, {
  int? tmdbId,
  required String title,
  int? year,
  String? backdrop,
  String mediaType = 'movie',
  List<TorrentRelease>? presetReleases,
  // Wire this to enable the completed-row Play button (resolves + plays the library item). When null,
  // a finished pick shows "In Library" + Delete only — exactly like the TV app with no onPlay wired.
  void Function(TorrentRelease release)? onPlay,
}) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Pick a Torrent',
    barrierColor: Colors.transparent, // the dialog draws its own blurred scrim
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) => TorrentPickerDialog(
      tmdbId: tmdbId ?? 0,
      title: title,
      year: year,
      mediaType: mediaType,
      presetReleases: presetReleases,
      onPlay: onPlay,
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class TorrentPickerDialog extends StatefulWidget {
  final int tmdbId;
  final String title;
  final int? year;
  final String mediaType;
  final List<TorrentRelease>? presetReleases;
  final void Function(TorrentRelease release)? onPlay;

  const TorrentPickerDialog({
    super.key,
    required this.tmdbId,
    required this.title,
    this.year,
    this.mediaType = 'movie',
    this.presetReleases,
    this.onPlay,
  });

  @override
  State<TorrentPickerDialog> createState() => _TorrentPickerDialogState();
}

class _TorrentPickerDialogState extends State<TorrentPickerDialog> {
  final PickerService _service = PickerService();
  final TextEditingController _searchCtl = TextEditingController();

  List<TorrentRelease> _releases = [];
  Map<String, _Dl> _dl = {};
  bool _dlLoaded = false; // false until the first /grab/status for the current list resolves
  bool _searching = false;
  String? _error;
  int? _progDone;
  int? _progTotal;

  String _search = '';
  String _quality = 'All';
  int _catIdx = 0;
  String _dir = 'desc';

  int _runId = 0;
  CancelToken? _cancel;
  Timer? _poll;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _openLoad();
    _poll = Timer.periodic(const Duration(milliseconds: 2500), (_) => _pollStatus());
  }

  @override
  void dispose() {
    _runId++;
    _cancel?.cancel('closed');
    _poll?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _quality = p.getString(_kQuality) ?? 'All';
      _catIdx = p.getInt(_kSortCat) ?? 0;
      _dir = p.getString(_kSortDir) ?? 'desc';
    });
  }

  void _savePrefs() {
    _prefs
      ?..setString(_kQuality, _quality)
      ..setInt(_kSortCat, _catIdx)
      ..setString(_kSortDir, _dir);
  }

  // On open: preset mode shows the row's own magnets; otherwise show cached results instantly, only
  // stream if nothing is cached. Repeat opens are therefore instant; Refresh always re-streams fresh.
  Future<void> _openLoad() async {
    final preset = widget.presetReleases;
    if (preset != null) {
      setState(() {
        _dl = {};
        _dlLoaded = false;
        _error = null;
        _progDone = null;
        _progTotal = null;
        _releases = preset;
        _searching = false;
      });
      _pollStatus();
      return;
    }
    // No tmdbId (e.g. a Seerr title whose id didn't resolve) → don't show an empty list; go straight to
    // a title-based indexer search so clicking Download always kicks off a live search.
    if (widget.tmdbId <= 0) {
      if (widget.title.isNotEmpty) _startSearch();
      return;
    }
    setState(() {
      _dl = {};
      _dlLoaded = false;
      _error = null;
      _progDone = null;
      _progTotal = null;
    });
    try {
      final cached = await _service.getReleasesCacheOnly(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
      );
      if (!mounted) return;
      if (cached.releases.isNotEmpty) {
        setState(() {
          _releases = cached.releases;
          _searching = false;
        });
        _pollStatus();
        return;
      }
    } catch (_) {
      /* fall through to stream */
    }
    _startSearch();
  }

  // tmdbId path (Details) or title-only path (Regional/1TamilMV catalog items have no tmdbId).
  void _startSearch() {
    if (widget.tmdbId <= 0 && widget.title.isEmpty) return;
    _cancel?.cancel('superseded');
    final ac = CancelToken();
    _cancel = ac;
    final myRun = ++_runId;

    // In preset mode keep the row's own 1TamilMV magnets and dedupe live results against them, so a
    // Refresh ADDS every other indexer's torrents rather than replacing 1TamilMV's.
    final seeded = widget.presetReleases ?? const <TorrentRelease>[];
    final seen = seeded.map(_keyOf).toSet();

    setState(() {
      _releases = List.of(seeded);
      _error = null;
      _progDone = null;
      _progTotal = null;
      _searching = true;
    });

    _service
        .streamReleasesEvents(
          tmdbId: widget.tmdbId > 0 ? widget.tmdbId : null,
          title: widget.title,
          year: widget.year,
          mediaType: widget.mediaType,
          cancelToken: ac,
          onStart: (total) {
            if (myRun != _runId || !mounted) return;
            setState(() {
              _progDone = 0;
              _progTotal = total;
            });
          },
          onIndexer: (done, total, rels) {
            if (myRun != _runId || !mounted) return;
            final incoming = <TorrentRelease>[];
            for (final r in rels) {
              final k = _keyOf(r);
              if (seen.add(k)) incoming.add(r);
            }
            setState(() {
              _progDone = done;
              _progTotal = total;
              if (incoming.isNotEmpty) _releases = [..._releases, ...incoming];
            });
          },
          onError: (e) {
            if (myRun != _runId || !mounted) return;
            setState(() => _error = e);
          },
        )
        .then((_) {
      if (myRun == _runId && mounted) setState(() => _searching = false);
    }).catchError((e) {
      if (e is DioException && CancelToken.isCancel(e)) return; // expected on close/supersede
      if (myRun == _runId && mounted) {
        setState(() {
          _error = e.toString();
          _searching = false;
        });
      }
    });
  }

  // Poll per-release download status so rows reflect reality (downloading w/ live % / on the server /
  // not grabbed). A row mid-grab ('sending') is left untouched by the poll.
  Future<void> _pollStatus() async {
    if (!mounted || _releases.isEmpty) return;
    final keys = _releases.map(_keyOf).where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty) return;
    try {
      final st = await _service.getGrabStatusKeys(keys);
      if (!mounted) return;
      setState(() {
        final next = Map<String, _Dl>.of(_dl);
        st.forEach((k, v) {
          if (next[k]?.status == 'sending') return; // don't clobber an in-flight grab
          if (v is Map<String, dynamic>) {
            final g = GrabStatus.fromJson(v);
            next[k] = _Dl(
              g.status,
              progress: g.progress > 1.0 ? g.progress / 100.0 : g.progress,
              hash: g.hash,
            );
          }
        });
        _dl = next;
        _dlLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _dlLoaded = true); // first status in (even on error → Download)
    }
  }

  Future<void> _onGrab(TorrentRelease rel) async {
    final k = _keyOf(rel);
    setState(() => _dl = {..._dl, k: const _Dl('sending')});
    try {
      final hash = await _service.grabReleaseResult(
        release: rel,
        tmdbId: widget.tmdbId,
        title: widget.title,
        year: widget.year,
        mediaType: widget.mediaType,
      );
      if (!mounted) return;
      setState(() => _dl = {..._dl, k: _Dl('downloading', progress: 0, hash: hash)});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dl = {..._dl, k: const _Dl('failed')};
        _error = e.toString();
      });
    }
  }

  Future<void> _onCancel(TorrentRelease rel) async {
    final k = _keyOf(rel);
    final hash = _dl[k]?.hash;
    setState(() => _dl = {..._dl}..remove(k)); // back to Download immediately
    try {
      await _service.cancelGrab(hash: hash, key: k);
    } catch (_) {/* next poll reconciles */}
  }

  Future<void> _onDelete(TorrentRelease rel) async {
    final k = _keyOf(rel);
    final hash = _dl[k]?.hash;
    setState(() => _dl = {..._dl, k: const _Dl('sending')}); // disable the row while it tears down
    try {
      final ok = await _service.deleteGrab(hash: hash, key: k);
      if (!mounted) return;
      if (ok) {
        setState(() => _dl = {..._dl}..remove(k));
      } else {
        setState(() => _dl = {..._dl, k: _Dl('completed', hash: hash)});
      }
    } catch (_) {
      if (mounted) setState(() => _dl = {..._dl, k: _Dl('completed', hash: hash)});
    }
  }

  void _cycleCat() {
    setState(() => _catIdx = (_catIdx + 1) % _cats.length);
    _savePrefs();
  }

  void _toggleDir() {
    setState(() => _dir = _dir == 'desc' ? 'asc' : 'desc');
    _savePrefs();
  }

  void _pickQuality(String q) {
    setState(() => _quality = q);
    _savePrefs();
  }

  List<String> get _qualities {
    final set = _releases.map((r) => r.quality).where((q) => q.isNotEmpty).toSet().toList();
    set.sort((a, b) => _qrank(b) - _qrank(a));
    return ['All', ...set];
  }

  List<TorrentRelease> get _visible {
    var list = List<TorrentRelease>.of(_releases);
    final quals = _qualities;
    if (_quality != 'All' && quals.contains(_quality)) {
      list = list.where((r) => r.quality == _quality).toList();
    }
    final q = _normSearch(_search).trim();
    if (q.isNotEmpty) {
      final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
      list = list.where((r) {
        final h = _normSearch(r.title);
        return tokens.every(h.contains);
      }).toList();
    }
    final val = _cats[_catIdx].val;
    list.sort((a, b) =>
        _dir == 'desc' ? val(b).compareTo(val(a)) : val(a).compareTo(val(b)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final width = (820.0).clamp(0.0, mq.size.width * 0.94);
    final height = (mq.size.height * 0.84)
        .clamp(0.0, mq.size.height - mq.viewInsets.bottom - 24);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Blurred, dimmed scrim — tap to close (mirrors the TV .scrim + backdrop-filter).
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: cs.scrim.withValues(alpha: 0.6)),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: width.toDouble(),
              height: height.toDouble(),
              child: _surface(cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _surface(ColorScheme cs) {
    final ink = cs.onSurface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 14),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: ink.withValues(alpha: 0.12)),
            boxShadow: const [
              BoxShadow(color: Color(0x80000000), blurRadius: 29, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(cs),
              const SizedBox(height: 14),
              _searchBox(cs),
              const SizedBox(height: 10),
              _filters(cs),
              const SizedBox(height: 10),
              Expanded(child: _body(cs)),
              const SizedBox(height: 12),
              Center(child: _pill(cs, 'Close', () => Navigator.of(context).maybePop())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    final ink = cs.onSurface;
    final vis = _visible.length;
    final total = _releases.length;
    final results = total == 0
        ? ''
        : ' · $vis${vis != total ? ' of $total' : ''} results';
    final progressText =
        _searching && _progTotal != null ? '${_progDone ?? 0}/$_progTotal' : null;
    return Row(
      children: [
        Text('Pick a Torrent',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${widget.title}$results',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.5)),
          ),
        ),
        if (progressText != null) ...[
          const SizedBox(width: 10),
          Text(progressText,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ink.withValues(alpha: 0.6),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
        const SizedBox(width: 10),
        // Circular icon that expands into a labeled pill on hover/focus (the TV ActionButton).
        ActionPillButton(
          height: 40,
          iconBuilder: _searching
              ? (size, color) => _Spinner(
                  color: color,
                  size: size,
                  path: PickerChromeIconPaths.refresh,
                  viewBox: PickerChromeIconPaths.viewBox)
              : (size, color) => DetailGlyph(PickerChromeIconPaths.refresh,
                  size: size, color: color, viewBox: PickerChromeIconPaths.viewBox),
          label: 'Refresh',
          onPressed: _searching ? () {} : _startSearch,
        ),
        const SizedBox(width: 8),
        _circleBtn(
          cs,
          size: 39,
          onTap: () => Navigator.of(context).maybePop(),
          child: DetailGlyph(PickerChromeIconPaths.close,
              size: 20,
              color: ink.withValues(alpha: 0.8),
              viewBox: PickerChromeIconPaths.viewBox),
          tooltip: 'Close',
        ),
      ],
    );
  }

  Widget _searchBox(ColorScheme cs) {
    final ink = cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          DetailGlyph(PickerChromeIconPaths.search,
              size: 20,
              color: ink.withValues(alpha: 0.6),
              viewBox: PickerChromeIconPaths.viewBox),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) => setState(() => _search = v),
              style: TextStyle(fontSize: 16, color: ink),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search the list — e.g. season 2, complete, 1080p, S02E05',
                hintStyle: TextStyle(fontSize: 14, color: ink.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(ColorScheme cs) {
    final ink = cs.onSurface;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: ink.withValues(alpha: 0.4))),
        );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: [
        label('Sort by'),
        _chip(cs, _cats[_catIdx].label, active: false, onTap: _cycleCat),
        _chip(cs,
            null,
            active: false,
            onTap: _toggleDir,
            iconPath: _dir == 'desc' ? PickerChromeIconPaths.down : PickerChromeIconPaths.up),
        const SizedBox(width: 16),
        label('Quality'),
        for (final q in _qualities)
          _chip(cs, q, active: q == _quality, onTap: () => _pickQuality(q)),
      ],
    );
  }

  Widget _body(ColorScheme cs) {
    final ink = cs.onSurface;
    final vis = _visible;
    if (_searching && vis.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Spinner(
                color: cs.primary,
                size: 40,
                path: PickerChromeIconPaths.refresh,
                viewBox: PickerChromeIconPaths.viewBox),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Fetching data',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ink.withValues(alpha: 0.8))),
                _BlinkingDots(color: ink.withValues(alpha: 0.8)),
              ],
            ),
          ],
        ),
      );
    }
    if (_error != null && vis.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFFFF8F8F))),
        ),
      );
    }
    if (vis.isEmpty) {
      final t = widget.year != null ? '${widget.title} (${widget.year})' : widget.title;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _releases.isEmpty
                ? 'No matching torrents found for $t.'
                : 'No results match your filter — clear the search box or Quality filter above.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.6)),
          ),
        ),
      );
    }
    final canPlay = widget.onPlay != null && widget.mediaType != 'tv';
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: vis.length,
      itemBuilder: (_, i) {
        final r = vis[i];
        return _TorrentRow(
          cs: cs,
          rel: r,
          dl: _dl[_keyOf(r)],
          loaded: _dlLoaded,
          canPlay: canPlay,
          onGrab: () => _onGrab(r),
          onCancel: () => _onCancel(r),
          onDelete: () => _onDelete(r),
          onPlay: () => widget.onPlay?.call(r),
        );
      },
    );
  }

  // ---- small shared chrome ----

  Widget _circleBtn(ColorScheme cs,
      {required double size, VoidCallback? onTap, required Widget child, String? tooltip}) {
    final ink = cs.onSurface;
    final btn = Material(
      color: ink.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        focusColor: cs.primary.withValues(alpha: 0.24),
        hoverColor: ink.withValues(alpha: 0.14),
        child: SizedBox(width: size, height: size, child: Center(child: child)),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }

  Widget _chip(ColorScheme cs, String? text,
      {required bool active, required VoidCallback onTap, String? iconPath}) {
    final ink = cs.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? cs.primary : ink.withValues(alpha: 0.08),
        shape: StadiumBorder(
            side: BorderSide(
                color: active ? Colors.transparent : ink.withValues(alpha: 0.12))),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          focusColor: cs.primary.withValues(alpha: 0.24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: iconPath != null
                ? DetailGlyph(iconPath,
                    size: 15,
                    color: active ? Colors.white : ink.withValues(alpha: 0.9),
                    viewBox: PickerChromeIconPaths.viewBox)
                : Text(text ?? '',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : ink.withValues(alpha: 0.9))),
          ),
        ),
      ),
    );
  }

  Widget _pill(ColorScheme cs, String text, VoidCallback onTap) {
    final ink = cs.onSurface;
    return Material(
      color: ink.withValues(alpha: 0.08),
      shape: StadiumBorder(side: BorderSide(color: ink.withValues(alpha: 0.12))),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        focusColor: cs.primary.withValues(alpha: 0.24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 9),
          child: Text(text,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
        ),
      ),
    );
  }
}

// ---- row -----------------------------------------------------------------------------------------

class _TorrentRow extends StatelessWidget {
  final ColorScheme cs;
  final TorrentRelease rel;
  final _Dl? dl;
  final bool loaded;
  final bool canPlay;
  final VoidCallback onGrab;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onPlay;

  const _TorrentRow({
    required this.cs,
    required this.rel,
    required this.dl,
    required this.loaded,
    required this.canPlay,
    required this.onGrab,
    required this.onCancel,
    required this.onDelete,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final ink = cs.onSurface;
    final status = dl?.status;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_cleanTitle(rel.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ink.withValues(alpha: 0.95))),
                const SizedBox(height: 5),
                _meta(ink, status == 'completed'),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 76,
            child: Text(_fmtSize(rel.size),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ink.withValues(alpha: 0.78))),
          ),
          // Half the previous gap; the action is content-sized (not a fixed cell) so when it expands on
          // hover the title (Expanded) gives way and the size slides left — the button never overlaps it.
          const SizedBox(width: 7),
          _action(context),
        ],
      ),
    );
  }

  Widget _meta(Color ink, bool completed) {
    final r = _qrank(rel.quality);
    final Color qBg, qFg;
    if (r >= 4) {
      qBg = cs.primary.withValues(alpha: 0.2);
      qFg = cs.primary;
    } else if (r >= 2) {
      qBg = const Color(0xFF78B4FF).withValues(alpha: 0.16);
      qFg = const Color(0xFF8FBCFF);
    } else {
      qBg = ink.withValues(alpha: 0.06);
      qFg = ink.withValues(alpha: 0.5);
    }
    return Row(
      children: [
        _mchip(rel.quality.isEmpty ? '?' : rel.quality, qBg, qFg),
        const SizedBox(width: 8),
        _mchip('${rel.seeders} seeds', const Color(0xFF34C759).withValues(alpha: 0.18),
            const Color(0xFF5FD97E),
            leading: const DetailGlyph(PickerChromeIconPaths.seed,
                size: 13,
                color: Color(0xFF5FD97E),
                viewBox: PickerChromeIconPaths.viewBox)),
        if (completed) ...[
          const SizedBox(width: 8),
          _mchip('In Library', const Color(0xFF34C759).withValues(alpha: 0.18),
              const Color(0xFF5FD97E),
              bold: true),
        ],
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            rel.indexer.replaceAll(' (Prowlarr)', ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: ink.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }

  Widget _mchip(String text, Color bg, Color fg, {Widget? leading, bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 3)],
          Text(text,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: fg)),
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    final ink = cs.onSurface;
    final status = dl?.status;
    final pct = (((dl?.progress ?? 0) * 100).round()).clamp(0, 100);

    if (!loaded && status == null) {
      return const SizedBox.shrink(); // fixed-width cell; nothing until first status resolves
    }
    if (status == 'downloading') {
      final frac = (pct / 100).clamp(0.0, 1.0);
      return _progressPill(
        onTap: onCancel,
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary, ink.withValues(alpha: 0.12), ink.withValues(alpha: 0.12)],
          stops: [0.0, frac, frac, 1.0],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DetailGlyph(DetailIconPaths.cancelRequest, size: 18, color: Colors.white),
            const SizedBox(width: 7),
            Text('Cancel · $pct%',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      );
    }
    if (status == 'completed') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPlay) ...[
            ActionPillButton(
              iconBuilder: (s, c) => DetailGlyph(DetailIconPaths.play, size: s, color: c),
              label: 'Play',
              onPressed: onPlay,
            ),
            const SizedBox(width: 8),
          ],
          ActionPillButton(
            iconBuilder: (s, c) => DetailGlyph(DetailIconPaths.delete, size: s, color: c),
            label: 'Delete',
            onPressed: onDelete,
          ),
        ],
      );
    }
    if (status == 'sending') {
      return _circleChild(context, _Spinner(color: ink, size: 24), null, 'Working');
    }
    return ActionPillButton(
      iconBuilder: (s, c) => DetailGlyph(DetailIconPaths.download, size: s, color: c),
      label: status == 'failed' ? 'Retry' : 'Download',
      onPressed: onGrab,
    );
  }

  Widget _circleChild(BuildContext ctx, Widget child, VoidCallback? onTap, String tip) {
    final ink = cs.onSurface;
    return Tooltip(
      message: tip,
      child: Material(
        color: ink.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          focusColor: cs.primary.withValues(alpha: 0.24),
          hoverColor: ink.withValues(alpha: 0.14),
          child: SizedBox(width: 46, height: 46, child: Center(child: child)),
        ),
      ),
    );
  }

  Widget _progressPill(
      {required VoidCallback onTap, required Widget child, Gradient? gradient}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minWidth: 132),
        height: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

// ---- tiny animation widgets ----------------------------------------------------------------------

class _Spinner extends StatefulWidget {
  final Color color;
  final double size;
  // The glyph that spins. Defaults to the TV `restart` icon (row "sending" state); the
  // header Refresh + "Fetching data" overlay pass the TV `refresh` two-arrows glyph,
  // matching the TV's `css.spinning` on each respective icon.
  final String path;
  final String? viewBox;
  const _Spinner(
      {required this.color,
      required this.size,
      this.path = DetailIconPaths.restart,
      this.viewBox});

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 850))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: DetailGlyph(widget.path,
            size: widget.size, color: widget.color, viewBox: widget.viewBox),
      );
}

class _BlinkingDots extends StatefulWidget {
  final Color color;
  const _BlinkingDots({required this.color});

  @override
  State<_BlinkingDots> createState() => _BlinkingDotsState();
}

class _BlinkingDotsState extends State<_BlinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _op(int i) {
    final v = ((_c.value + i * 0.22) % 1.0);
    final o = v < 0.5 ? 0.2 + 1.6 * v : 1.0 - 1.6 * (v - 0.5);
    return o.clamp(0.2, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Opacity(
              opacity: _op(i),
              child: Text('.',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: widget.color)),
            ),
        ],
      ),
    );
  }
}
