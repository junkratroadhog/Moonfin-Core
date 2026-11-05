import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/picker/picker_models.dart';
import '../../../data/services/picker/picker_service.dart';
import '../../navigation/destinations.dart';
import '../../widgets/expandable_icon_button.dart';

// Flutter port of the TV app's views/SeerrRegional — the "Regional" Seerr section. Lists the available
// indexer catalogs as tiles (1TamilMV), each with Refresh / Soft Sync / Hard Sync buttons plus a header
// "Refresh All". Tapping a tile opens that indexer's catalog content (RegionalCatalogScreen). Polls every
// 5s to keep running/lastSync fresh. Reached from Seerr -> Regional (NOT the left sidebar).
class SeerrRegionalScreen extends StatefulWidget {
  const SeerrRegionalScreen({super.key});

  @override
  State<SeerrRegionalScreen> createState() => _SeerrRegionalScreenState();
}

class _SeerrRegionalScreenState extends State<SeerrRegionalScreen> {
  final PickerService _service = PickerService();

  List<IndexerInfo> _indexers = [];
  bool _isLoading = true;
  String? _error;
  String _note = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load().then((_) => mounted ? setState(() => _isLoading = false) : null);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _service.getIndexers();
      if (mounted) setState(() => _indexers = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // Per-tile Refresh = reload the displayed state from the DB (no scraping), like the TV screen.
  void _refreshTile() {
    setState(() => _note = 'Refreshed');
    _load();
  }

  void _softSync(String id) {
    setState(() => _note = 'Soft sync started…');
    _service.syncIndexer(id, mode: 'soft').then((_) => _load()).catchError(
        (e) => mounted ? setState(() => _note = e.toString()) : null);
  }

  void _hardSync(String id) {
    setState(() => _note = 'Hard sync started…');
    _service.syncIndexer(id, mode: 'hard').then((_) => _load()).catchError(
        (e) => mounted ? setState(() => _note = e.toString()) : null);
  }

  void _refreshAll() {
    setState(() => _note = 'Refreshing all indexers…');
    _service.refreshAllIndexers().then((_) => _load()).catchError(
        (e) => mounted ? setState(() => _note = e.toString()) : null);
  }

  void _open(IndexerInfo ix) {
    context.push(
      '${Destinations.regionalCatalog}?id=${Uri.encodeComponent(ix.id)}&name=${Uri.encodeComponent(ix.name)}',
    );
  }

  String _fmtWhen(String? s) {
    if (s == null || s.isEmpty) return '';
    final d = DateTime.tryParse(s.replaceFirst(' ', 'T'))?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onSurface;
    final anyRunning = _indexers.any((i) => i.running);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
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
                        Text('REGIONAL',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: ink.withValues(alpha: 0.5))),
                        Text('Indexers',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w700, color: ink)),
                        if (_note.isNotEmpty)
                          Text(_note,
                              style: TextStyle(
                                  fontSize: 13, color: ink.withValues(alpha: 0.55))),
                      ],
                    ),
                  ),
                  ExpandableIconButton(
                    icon: Icons.refresh,
                    label: anyRunning ? 'Refreshing…' : 'Refresh All',
                    baseColor: cs.primary,
                    onPressed: _refreshAll,
                  ),
                ],
              ),
            ),
            Expanded(child: _body(cs)),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    final ink = cs.onSurface;
    if (_isLoading && _indexers.isEmpty) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    if (_error != null && _indexers.isEmpty) {
      return Center(
        child: Text(_error!,
            style: TextStyle(color: ink.withValues(alpha: 0.6))),
      );
    }
    if (_indexers.isEmpty) {
      return Center(
        child: Text('No indexers available',
            style: TextStyle(color: ink.withValues(alpha: 0.5))),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: _indexers.map((ix) => _tile(cs, ix)).toList(),
      ),
    );
  }

  Widget _tile(ColorScheme cs, IndexerInfo ix) {
    final ink = cs.onSurface;
    final updated = _fmtWhen(ix.lastSync);
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _open(ix),
            child: Container(
              height: 140,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.55),
                    cs.primary.withValues(alpha: 0.18),
                  ],
                ),
                border: Border.all(color: ink.withValues(alpha: 0.1)),
              ),
              child: Text(ix.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Circular icon buttons that expand into a labeled pill on hover/focus — the TV app's
              // ActionButton, reusing the app's native ExpandableIconButton (same as the toolbar/sidebar).
              ExpandableIconButton(
                icon: Icons.autorenew,
                label: ix.running ? 'Refreshing…' : 'Refresh',
                baseColor: cs.primary,
                onPressed: _refreshTile,
              ),
              const SizedBox(width: 8),
              ExpandableIconButton(
                icon: Icons.sync,
                label: 'Soft Sync',
                baseColor: cs.primary,
                onPressed: () => _softSync(ix.id),
              ),
              const SizedBox(width: 8),
              ExpandableIconButton(
                icon: Icons.cloud_sync_outlined,
                label: 'Hard Sync',
                baseColor: cs.primary,
                onPressed: () => _hardSync(ix.id),
              ),
            ],
          ),
          if (updated.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Updated: $updated',
                style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.5))),
          ],
        ],
      ),
    );
  }

}
