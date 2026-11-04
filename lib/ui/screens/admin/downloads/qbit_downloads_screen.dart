import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../data/services/picker/downloads_service.dart';

// Admin qBittorrent Downloads manager — Flutter port of the TV app's views/Downloads/Downloads.js.
// Stats grid + filter chips + on-completion policy + speed-mode toggle, and a list GROUPED by title
// (collapsible groups, each with Pause/Resume all + Remove all; expand for per-copy rows). Polls every 2s.

// ── state helpers (mirror the TV regexes) ──
final _reActive = RegExp(r'downloading|stalledDL|metaDL|forcedDL', caseSensitive: false);
final _reSeeding = RegExp(r'uploading|stalledUP|forcedUP|queuedUP', caseSensitive: false);
final _rePaused = RegExp(r'paus', caseSensitive: false);
final _reChecking = RegExp(r'checking', caseSensitive: false);
final _reComplete = RegExp(r'pausedUP|complete', caseSensitive: false);

bool _isActive(String s) => _reActive.hasMatch(s);
bool _isSeeding(String s) => _reSeeding.hasMatch(s);
bool _isPaused(String s) => _rePaused.hasMatch(s);
bool _isChecking(String s) => _reChecking.hasMatch(s);
bool _isComplete(String s) => _isSeeding(s) || _reComplete.hasMatch(s);

String _fmtBytes(num n) {
  if (n <= 0) return '0 B';
  const s = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final i = math.min(s.length - 1, (math.log(n) / math.log(1024)).floor());
  return '${(n / math.pow(1024, i)).toStringAsFixed(2)} ${s[i]}';
}

String? _fmtEta(int? sec) {
  if (sec == null || sec <= 0 || sec >= 8640000) return null;
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

// Collapse a torrent name to the underlying movie/show so every copy/episode lands in ONE group.
final _groupCut =
    RegExp(r'\b(s\d{1,2}(e\d{1,3})?|\d{3,4}p|19\d{2}|20\d{2}|complete|season)\b', caseSensitive: false);
String _groupTitle(String name) {
  final clean = name
      .replaceAll(RegExp(r'^www\.[^ ]+ - ', caseSensitive: false), '')
      .replaceAll(RegExp(r'[._]+'), ' ');
  final m = _groupCut.firstMatch(clean);
  final base = (m != null && m.start > 0 ? clean.substring(0, m.start) : clean)
      .replaceAll(RegExp(r'[\s\-([{]+$'), '')
      .trim();
  if (base.isNotEmpty) return base;
  final t = clean.trim();
  return t.isNotEmpty ? t : (name.isNotEmpty ? name : '?');
}

String _groupKey(String name) =>
    _groupTitle(name).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

class _Group {
  final String key;
  final String title;
  final List<DownloadItem> items;
  const _Group(this.key, this.title, this.items);
}

const _amber = Color(0xFFFFB86B);
const _green = Color(0xFF5FD97E);
const _danger = Color(0xFFEF4444);

class QbitDownloadsScreen extends StatefulWidget {
  const QbitDownloadsScreen({super.key});

  @override
  State<QbitDownloadsScreen> createState() => _QbitDownloadsScreenState();
}

class _QbitDownloadsScreenState extends State<QbitDownloadsScreen> {
  final DownloadsService _service = DownloadsService();

  List<DownloadItem> _items = [];
  DownloadTotals _totals = const DownloadTotals();
  String? _error;
  String _filter = 'All';
  bool _busy = false;
  String _policy = 'none';
  bool _altSpeed = false;
  final Set<String> _expanded = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _service.getPolicy().then((p) => mounted ? setState(() => _policy = p) : null).catchError((_) => null);
    _service.getSpeedMode().then((v) => mounted ? setState(() => _altSpeed = v) : null).catchError((_) => false);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final snap = await _service.list();
      if (!mounted) return;
      setState(() {
        _items = snap.items;
        _totals = snap.totals;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _act(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  void _onToggle(DownloadItem it) =>
      _act(() => _isPaused(it.state) ? _service.resume(it.id) : _service.pause(it.id));
  void _onRecheck(DownloadItem it) => _act(() => _service.recheck(it.id));
  void _onDelete(DownloadItem it) => _act(() => _service.remove(it.id, withData: true));
  void _onToggleAll(_Group g) => _act(() async {
        final anyActive = g.items.any((i) => !_isPaused(i.state));
        for (final it in g.items) {
          await (anyActive ? _service.pause(it.id) : _service.resume(it.id));
        }
      });
  void _onRemoveAll(_Group g) =>
      _act(() async {
        for (final it in g.items) {
          await _service.remove(it.id, withData: true);
        }
      });

  void _changePolicy(String p) {
    setState(() => _policy = p);
    _service.setPolicy(p).then((v) => mounted ? setState(() => _policy = v) : null).catchError(
        (e) => mounted ? setState(() => _error = e.toString()) : null);
  }

  void _toggleSpeed() {
    _service.toggleSpeedMode().then((v) => mounted ? setState(() => _altSpeed = v) : null).catchError(
        (e) => mounted ? setState(() => _error = e.toString()) : null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _items.where((i) {
      switch (_filter) {
        case 'Active':
          return _isActive(i.state);
        case 'Paused':
          return _isPaused(i.state);
        case 'Complete':
          return _isComplete(i.state);
        default:
          return true;
      }
    }).toList();

    final map = <String, List<DownloadItem>>{};
    for (final it in filtered) {
      map.putIfAbsent(_groupKey(it.title), () => []).add(it);
    }
    final groups = map.entries
        .map((e) => _Group(e.key, _groupTitle(e.value.first.title), e.value))
        .toList()
      ..sort((a, b) =>
          b.items.length - a.items.length != 0 ? b.items.length - a.items.length : a.title.compareTo(b.title));

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D12),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _headerAndStats(cs)),
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF8F8F))),
                    ),
                  ),
                if (filtered.isEmpty && _error == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: Text('Nothing here.',
                              style: TextStyle(color: Colors.white60))),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: groups.length,
                    itemBuilder: (_, i) => _groupTile(cs, groups[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerAndStats(ColorScheme cs) {
    final activeN = _items.where((i) => _isActive(i.state)).length;
    final seedN = _items.where((i) => _isComplete(i.state)).length;
    final dlSpeed =
        _items.where((i) => _isActive(i.state)).fold<int>(0, (s, i) => s + i.speed);
    final upSpeed =
        _items.where((i) => _isSeeding(i.state)).fold<int>(0, (s, i) => s + i.upspeed);
    final anyActiveAll = _items.any((i) => !_isPaused(i.state));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      const Text('Downloads',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(width: 6),
                      Text('${_items.length}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54)),
                    ]),
                    const Text('Manage active transfers, queue and seeding torrents',
                        style: TextStyle(fontSize: 13, color: Colors.white54)),
                  ],
                ),
              ),
              _pill('Refresh', _busy ? null : _refresh),
              const SizedBox(width: 8),
              _pill(anyActiveAll ? 'Pause all' : 'Resume all',
                  _busy ? null : () => _act(anyActiveAll ? _service.pauseAll : _service.resumeAll)),
              const SizedBox(width: 8),
              _pill(_altSpeed ? 'Metered' : 'Standard', _busy ? null : _toggleSpeed,
                  icon: _altSpeed ? Icons.bolt : Icons.rocket_launch, amber: _altSpeed),
              const SizedBox(width: 8),
              _circleClose(cs),
            ],
          ),
          const SizedBox(height: 14),
          _statsRow(activeN, seedN, dlSpeed, upSpeed),
          const SizedBox(height: 12),
          Wrap(
            children: [
              for (final f in const ['All', 'Active', 'Paused', 'Complete'])
                _chip(cs, f, _filter == f, () => setState(() => _filter = f)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 12, bottom: 8),
                child: Text('When a download finishes:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white60)),
              ),
              for (final p in const [
                ['none', 'Keep seeding'],
                ['pause', 'Pause when done'],
                ['remove', 'Remove when done'],
              ])
                _chip(cs, p[1], _policy == p[0], () => _changePolicy(p[0])),
              if (_policy == 'remove')
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('(removed only after it lands safely in your library)',
                      style: TextStyle(fontSize: 12, color: Colors.white38)),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _statsRow(int activeN, int seedN, int dlSpeed, int upSpeed) {
    return Row(
      children: [
        _statCard('Active', '$activeN', '${_fmtBytes(dlSpeed)}/s combined'),
        _statCard('Seeding', '$seedN', '↑ ${_fmtBytes(upSpeed)}/s', tintUp: true),
        _statCard('Queue size', '${_totals.queueSize}', 'across ${_items.length} items'),
        _statCard('Disk free', _fmtBytes(_totals.diskFree), 'Manage storage ›',
            link: true, onTap: _openStorage),
      ],
    );
  }

  void _openStorage() {
    // Storage manager is a separate (upcoming) screen; wire it here once built.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Storage manager — coming soon')),
    );
  }

  Widget _statCard(String label, String value, String tail,
      {bool tintUp = false, bool link = false, VoidCallback? onTap}) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 4),
          Text(tail,
              style: TextStyle(
                  fontSize: 12,
                  color: link ? const Color(0xFF7FB5FF) : (tintUp ? _green : Colors.white70),
                  fontWeight: link ? FontWeight.w600 : FontWeight.normal)),
        ],
      ),
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: onTap == null
            ? card
            : InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: card),
      ),
    );
  }

  Widget _groupTile(ColorScheme cs, _Group g) {
    final open = _expanded.contains(g.key);
    final totalSize = g.items.fold<int>(0, (s, i) => s + i.size);
    final dlN = g.items.where((i) => _isActive(i.state)).length;
    final anyActive = g.items.any((i) => !_isPaused(i.state));
    final copies = g.items.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(
                        () => open ? _expanded.remove(g.key) : _expanded.add(g.key)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.keyboard_arrow_down,
                                size: 20, color: Colors.white54),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(g.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$copies ${copies == 1 ? 'copy' : 'copies'} · ${_fmtBytes(totalSize)}${dlN > 0 ? ' · $dlN downloading' : ''}',
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _pill(anyActive ? 'Pause all' : 'Resume all', _busy ? null : () => _onToggleAll(g)),
                const SizedBox(width: 8),
                _pill('Remove all', _busy ? null : () => _onRemoveAll(g), danger: true),
                const SizedBox(width: 12),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 10),
              child: Column(children: g.items.map((it) => _row(cs, it)).toList()),
            ),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, DownloadItem it) {
    final paused = _isPaused(it.state);
    final seeding = _isSeeding(it.state);
    final checking = _isChecking(it.state);
    final complete = _isComplete(it.state);
    final stateColor =
        checking || _isActive(it.state) ? _amber : (seeding ? _green : Colors.white38);
    final stateLabel = checking
        ? 'Rechecking…'
        : seeding
            ? '↑ Seeding'
            : complete && paused
                ? 'Paused (seeded)'
                : paused
                    ? 'Paused'
                    : 'Downloading';
    final pct = (it.progress * 1000).round() / 10;
    final eta = _fmtEta(it.eta);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _sub(_fmtBytes(it.size)),
                        _dot(),
                        _sub(stateLabel, color: stateColor),
                        if (it.source != null && it.source!.isNotEmpty) ...[
                          _dot(),
                          _sub(it.source!),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _pill(paused ? 'Resume' : 'Pause', _busy ? null : () => _onToggle(it), amber: true),
              const SizedBox(width: 8),
              _pill('Recheck', (_busy || checking) ? null : () => _onRecheck(it)),
              const SizedBox(width: 8),
              _pill('Delete', _busy ? null : () => _onDelete(it), danger: true),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFF9F40)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _statCell('Progress', '$pct%')),
              Expanded(
                child: Text(
                  seeding
                      ? '↑ ${_fmtBytes(it.upspeed)}/s'
                      : paused
                          ? '↓ —'
                          : '${_fmtBytes(it.speed)}/s ↓',
                  style: TextStyle(fontSize: 12.5, color: seeding ? _green : Colors.white70),
                ),
              ),
              Expanded(
                child: Text('Seeds: ${it.seeds} · Peers: ${it.peers}',
                    style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
              ),
              Expanded(
                child: Text(
                  complete
                      ? 'Ratio ${it.ratio.toStringAsFixed(2)}'
                      : eta != null
                          ? 'ETA: $eta'
                          : '—',
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCell(String k, String v) => RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, color: Colors.white70),
          children: [
            TextSpan(text: '$k ', style: const TextStyle(color: Colors.white38)),
            TextSpan(text: v),
          ],
        ),
      );

  Widget _sub(String t, {Color? color}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(t, style: TextStyle(fontSize: 12.5, color: color ?? Colors.white38)),
      );

  Widget _dot() => Container(
        margin: const EdgeInsets.only(right: 8),
        width: 3,
        height: 3,
        decoration: const BoxDecoration(color: Colors.white38, shape: BoxShape.circle),
      );

  Widget _pill(String text, VoidCallback? onTap,
      {IconData? icon, bool amber = false, bool danger = false}) {
    final Color bg = amber
        ? const Color(0xFFFFB86B)
        : danger
            ? _danger.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.1);
    final Color fg = amber
        ? const Color(0xFF2A1500)
        : Colors.white;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: StadiumBorder(
            side: BorderSide(
                color: (amber || danger) ? Colors.transparent : Colors.white.withValues(alpha: 0.14))),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
                Text(text,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 8),
      child: Material(
        color: active ? cs.primary : Colors.white.withValues(alpha: 0.08),
        shape: StadiumBorder(
            side: BorderSide(
                color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.12))),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : Colors.white.withValues(alpha: 0.9))),
          ),
        ),
      ),
    );
  }

  Widget _circleClose(ColorScheme cs) => Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          customBorder: const CircleBorder(),
          child: const SizedBox(
              width: 34, height: 34, child: Icon(Icons.close, size: 18, color: Colors.white70)),
        ),
      );
}
