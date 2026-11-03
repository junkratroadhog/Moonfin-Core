import 'dart:async';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/picker/picker_models.dart';
import '../../../data/services/picker/picker_service.dart';
import '../../widgets/picker/torrent_picker_dialog.dart';

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
  List<CatalogItem> _allItems = [];
  String? _syncedAt;
  bool _syncRunning = false;

  String _searchQuery = '';
  String _activeFilter = 'all'; // all, 4k, 1080p, tamil, telugu, hindi, malayalam, kannada

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _service.getCatalog(widget.indexerId, all: true);
      if (mounted) {
        setState(() {
          _allItems = res.results;
          _syncedAt = res.syncedAt;
          _syncRunning = res.syncRunning;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load catalog: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _triggerSync(String mode) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting $mode sync for ${widget.indexerName}...'),
        duration: const Duration(seconds: 2),
      ),
    );
    final ok = await _service.syncIndexer(widget.indexerId, mode: mode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Sync initiated in background.' : 'Failed to trigger sync.',
          ),
          backgroundColor:
              ok ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
        ),
      );
      if (ok) {
        // Reload after a short delay
        Future.delayed(const Duration(seconds: 3), _loadCatalog);
      }
    }
  }

  List<CatalogItem> get _filteredItems {
    var list = _allItems;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((item) {
        final title = item.title.toLowerCase();
        final langs = item.languages.join(' ').toLowerCase();
        return title.contains(q) || langs.contains(q);
      }).toList();
    }

    if (_activeFilter == '4k') {
      list = list.where((item) {
        final q = (item.quality ?? '').toLowerCase();
        return q.contains('4k') || q.contains('2160');
      }).toList();
    } else if (_activeFilter == '1080p') {
      list = list.where((item) {
        final q = (item.quality ?? '').toLowerCase();
        return q.contains('1080');
      }).toList();
    } else if (_activeFilter != 'all') {
      // Language filter
      final lang = _activeFilter.toLowerCase();
      list = list.where((item) {
        return item.languages
            .any((l) => l.toLowerCase() == lang || l.toLowerCase().contains(lang));
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${widget.indexerName} Regional',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${_allItems.length} titles',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (_syncedAt != null)
              Text(
                'Synced: $_syncedAt',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              Icons.sync,
              color: _syncRunning ? Colors.amber : Colors.white70,
            ),
            tooltip: 'Sync Indexer',
            onSelected: _triggerSync,
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'soft',
                child: Text('Soft Sync (New Releases)'),
              ),
              const PopupMenuItem(
                value: 'hard',
                child: Text('Hard Sync (Full Re-scrape)'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loadCatalog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCatalog,
        color: Colors.blueAccent,
        backgroundColor: const Color(0xFF1E1E24),
        child: Column(
          children: [
            _buildSearchAndFilters(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search box
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search ${widget.indexerName} titles or languages...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 10),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('all', 'All'),
                _chip('tamil', 'Tamil'),
                _chip('telugu', 'Telugu'),
                _chip('hindi', 'Hindi'),
                _chip('malayalam', 'Malayalam'),
                _chip('kannada', 'Kannada'),
                _chip('4k', '4K UHD'),
                _chip('1080p', '1080p'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String key, String label) {
    final active = _activeFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        selectedColor: Colors.blue.shade700,
        backgroundColor: Colors.white10,
        labelStyle: TextStyle(
          color: active ? Colors.white : Colors.white70,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        onSelected: (_) => setState(() => _activeFilter = key),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 16),
            Text('Loading Regional Catalog...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadCatalog, child: const Text('Retry')),
          ],
        ),
      );
    }

    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_filter_outlined,
                size: 48, color: Colors.white30),
            const SizedBox(height: 12),
            const Text(
              'No titles match your filter or search.',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            if (_searchQuery.isNotEmpty || _activeFilter != 'all')
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _activeFilter = 'all';
                  });
                },
                child: const Text('Reset Filters'),
              ),
          ],
        ),
      );
    }

    // Responsive grid layout: 2 columns on phones (<600px width), 3-5 on tablets
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth < 450
        ? 2
        : screenWidth < 750
            ? 3
            : screenWidth < 1100
                ? 4
                : 5;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.58, // Poster 2:3 + info area
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, idx) => _buildCatalogCard(items[idx]),
    );
  }

  Widget _buildCatalogCard(CatalogItem item) {
    final posterUrl = _service.posterUrl(item.posterPath, width: 342);
    final langs = item.languages.isNotEmpty ? item.languages.join(' • ') : '';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        showTorrentPickerDialog(
          context,
          title: item.title,
          year: item.year,
          presetReleases: item.releases,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster container
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.05),
                    child: posterUrl.isNotEmpty
                        ? Image.network(
                            posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.movie,
                                  size: 40, color: Colors.white24),
                            ),
                            loadingBuilder: (ctx, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: Colors.white.withValues(alpha: 0.03),
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : const Center(
                            child: Icon(Icons.movie,
                                size: 40, color: Colors.white24),
                          ),
                  ),
                ),
                // Quality badge overlay
                if (item.quality != null && item.quality!.isNotEmpty)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _buildQualityBadge(item.quality!),
                  ),
                // Torrent count badge
                if (item.releases.isNotEmpty)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt,
                              size: 11, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            '${item.releases.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Title
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Year & Languages
          Row(
            children: [
              if (item.year != null && item.year! > 0) ...[
                Text(
                  '${item.year}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(width: 6),
              ],
              if (langs.isNotEmpty)
                Expanded(
                  child: Text(
                    langs,
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.shade300),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQualityBadge(String quality) {
    final q = quality.toLowerCase();
    final is4k = q.contains('4k') || q.contains('2160');
    final is1080 = q.contains('1080');

    final color = is4k
        ? const Color(0xFFFFD700) // Gold
        : is1080
            ? const Color(0xFF90CAF9) // Light blue
            : Colors.white70;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1),
      ),
      child: Text(
        is4k
            ? '4K UHD'
            : is1080
                ? '1080p'
                : quality,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

