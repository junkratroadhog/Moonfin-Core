import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../data/services/picker/picker_models.dart';
import '../../../data/services/picker/picker_service.dart';
import '../../widgets/picker/torrent_picker_dialog.dart';

// Flutter port of the TV SeerrIndexerCatalog (tv-client views/SeerrIndexerCatalog). A library-styled
// view of ONE indexer's pre-scraped catalog (e.g. 1TamilMV): header (name + item count), a toolbar
// search box, then ONE continuous scroll with two sections — "Top Releases This Week" then
// "Recently Added" — of library-style poster cards. Hovering a card drifts a blurred-poster backdrop.
// Tapping a card opens the reworked Torrent Picker in preset mode (the card brings its own magnets).
class RegionalCatalogScreen extends StatefulWidget {
  final String indexerId;
  final String indexerName;

  const RegionalCatalogScreen({
    super.key,
    this.indexerId = '1tamilmv',
    this.indexerName = '1TamilMV',
  });

  @override
  State<RegionalCatalogScreen> createState() => _RegionalCatalogScreenState();
}

class _RegionalCatalogScreenState extends State<RegionalCatalogScreen> {
  final PickerService _service = PickerService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<CatalogItem> _all = [];
  String? _syncedAt;
  String _search = '';
  String? _backdropUrl;

  Timer? _poll;
  Timer? _backdropDebounce;

  static const _pollInterval = Duration(seconds: 20);
  static const _backdropDebounceMs = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh: when the scraper's syncedAt advances (a metadata fetch completed), reload.
    _poll = Timer.periodic(_pollInterval, (_) async {
      try {
        final r = await _service.getCatalog(widget.indexerId, all: true);
        if (!mounted) return;
        if (r.syncedAt != null && r.syncedAt != _syncedAt) {
          setState(() {
            _syncedAt = r.syncedAt;
            _all = r.results;
          });
        }
      } catch (_) {/* try next tick */}
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _backdropDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final r = await _service.getCatalog(widget.indexerId, all: true);
      if (!mounted) return;
      setState(() {
        _all = r.results;
        _syncedAt = r.syncedAt;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load catalog: $e';
        _isLoading = false;
      });
    }
  }

  // Two sections from one catalog, each narrowed by the shared search box (token match on title).
  List<CatalogItem> _filter(Iterable<CatalogItem> base) {
    final q = _search.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (q.isEmpty) return base.toList();
    return base.where((it) {
      final t = it.title.toLowerCase();
      return q.every(t.contains);
    }).toList();
  }

  List<CatalogItem> get _weekItems =>
      _filter(_all.where((it) => it.section == 'week'));
  List<CatalogItem> get _recentItems =>
      _filter(_all.where((it) => it.section != 'week'));

  void _updateBackdrop(CatalogItem item) {
    if (item.posterPath == null || item.posterPath!.isEmpty) return;
    final url = _service.posterUrl(item.posterPath, width: 342);
    _backdropDebounce?.cancel();
    _backdropDebounce = Timer(_backdropDebounceMs, () {
      if (mounted) setState(() => _backdropUrl = url);
    });
  }

  void _openPicker(CatalogItem item) {
    showTorrentPickerDialog(
      context,
      title: item.title,
      year: item.year,
      mediaType: item.mediaType,
      presetReleases: item.releases,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          _backdrop(cs),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(cs),
                _searchBox(cs),
                const SizedBox(height: 8),
                Expanded(child: _body(cs)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _backdrop(ColorScheme cs) {
    final scrim = cs.scrim;
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _backdropUrl == null
                ? const SizedBox.shrink()
                : Opacity(
                    key: ValueKey(_backdropUrl),
                    opacity: 0.55,
                    child: Transform.scale(
                      scale: 1.18,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                        child: Image.network(
                          _backdropUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scrim.withValues(alpha: 0.35),
                  scrim.withValues(alpha: 0.55),
                  scrim.withValues(alpha: 0.82),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    final ink = cs.onSurface;
    final total = _weekItems.length + _recentItems.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.indexerName,
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700, color: ink)),
                Text(total > 0 ? '$total items' : '',
                    style: TextStyle(
                        fontSize: 13, color: ink.withValues(alpha: 0.55))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox(ColorScheme cs) {
    final ink = cs.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: ink.withValues(alpha: 0.6)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(fontSize: 16, color: ink),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search ${widget.indexerName} titles',
                  hintStyle:
                      TextStyle(fontSize: 14, color: ink.withValues(alpha: 0.4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    final ink = cs.onSurface;
    if (_isLoading && _all.isEmpty) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    if (_error != null && _all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: ink.withValues(alpha: 0.7))),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final week = _weekItems;
    final recent = _recentItems;
    if (week.isEmpty && recent.isEmpty) {
      return Center(
        child: Text(
          _search.isNotEmpty ? 'No titles match your search' : 'No items found',
          style: TextStyle(fontSize: 16, color: ink.withValues(alpha: 0.5)),
        ),
      );
    }

    // ONE continuous scroll for both sections (CustomScrollView slivers = virtualized, the Flutter
    // equivalent of the TV single Scroller + content-visibility).
    return CustomScrollView(
      slivers: [
        if (week.isNotEmpty) ...[
          _sectionHeading(cs, 'Top Releases This Week', week.length),
          _sectionGrid(week),
        ],
        _sectionHeading(cs, 'Recently Added', recent.length),
        _sectionGrid(recent),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _sectionHeading(ColorScheme cs, String label, int count) {
    final ink = cs.onSurface;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: ink)),
            const SizedBox(width: 10),
            Text('$count',
                style: TextStyle(
                    fontSize: 15, color: ink.withValues(alpha: 0.55))),
          ],
        ),
      ),
    );
  }

  Widget _sectionGrid(List<CatalogItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          childAspectRatio: 0.52,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _CatalogCard(
            item: items[i],
            posterUrl: _service.posterUrl(items[i].posterPath, width: 342),
            onTap: () => _openPicker(items[i]),
            onHover: () => _updateBackdrop(items[i]),
          ),
          childCount: items.length,
        ),
      ),
    );
  }
}

// Library-style poster card: poster + gold-4K/silver-1080p quality badge + title + year/languages
// (ellipsis, like the Movies grid — no marquee). Mirrors TV renderCardBody.
class _CatalogCard extends StatelessWidget {
  final CatalogItem item;
  final String posterUrl;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _CatalogCard({
    required this.item,
    required this.posterUrl,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final langs = item.languages.isNotEmpty ? item.languages.join(', ') : '';
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: ink.withValues(alpha: 0.05)),
                    if (posterUrl.isNotEmpty)
                      Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.movie_outlined,
                            size: 40, color: ink.withValues(alpha: 0.2)),
                        loadingBuilder: (c, child, p) => p == null
                            ? child
                            : Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: ink.withValues(alpha: 0.2)),
                                ),
                              ),
                      )
                    else
                      Icon(Icons.movie_outlined,
                          size: 40, color: ink.withValues(alpha: 0.2)),
                    if (item.quality != null && item.quality!.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _QualityBadge(quality: item.quality!),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
            const SizedBox(height: 2),
            Row(
              children: [
                if (item.year != null && item.year! > 0) ...[
                  Text('${item.year}',
                      style: TextStyle(
                          fontSize: 11, color: ink.withValues(alpha: 0.5))),
                  const SizedBox(width: 6),
                ],
                if (langs.isNotEmpty)
                  Expanded(
                    child: Text(langs,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: ink.withValues(alpha: 0.5))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Gold 4K / silver 1080p badge (else a plain quality pill), matching the TV QualityBadge.
class _QualityBadge extends StatelessWidget {
  final String quality;
  const _QualityBadge({required this.quality});

  @override
  Widget build(BuildContext context) {
    final q = quality.toLowerCase();
    final is4k = q.contains('4k') || q.contains('2160') || q.contains('uhd');
    final is1080 = q.contains('1080');
    final Color fg = is4k
        ? const Color(0xFFE6B422) // gold
        : is1080
            ? const Color(0xFFCFD4DA) // silver
            : Colors.white;
    final label = is4k ? '4K' : (is1080 ? '1080p' : quality);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: (is4k || is1080) ? fg : Colors.white.withValues(alpha: 0.25),
            width: 1.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1)),
              ])),
    );
  }
}
