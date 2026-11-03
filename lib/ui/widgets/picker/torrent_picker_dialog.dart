import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/services/picker/picker_models.dart';
import '../../../data/services/picker/picker_service.dart';
import '../track_selector_dialog.dart';

void showTorrentPickerDialog(
  BuildContext context, {
  required int tmdbId,
  required String title,
  int? year,
  String? backdrop,
}) {
  showStyledPlayerDialog<void>(
    context,
    title: 'Pick a Torrent — $title',
    maxWidth: 720,
    builder: (_) => TorrentPickerDialog(
      tmdbId: tmdbId,
      title: title,
      year: year,
      backdrop: backdrop,
    ),
  );
}

class TorrentPickerDialog extends StatefulWidget {
  final int tmdbId;
  final String title;
  final int? year;
  final String? backdrop;

  const TorrentPickerDialog({
    super.key,
    required this.tmdbId,
    required this.title,
    this.year,
    this.backdrop,
  });

  @override
  State<TorrentPickerDialog> createState() => _TorrentPickerDialogState();
}

class _TorrentPickerDialogState extends State<TorrentPickerDialog> {
  final PickerService _service = PickerService();

  bool _isLoading = true;
  String? _error;
  List<TorrentRelease> _releases = [];
  String _activeFilter = 'all'; // all, 4k, 1080p, 720p, tamilmv

  GrabStatus? _grabStatus;
  Timer? _statusTimer;
  bool _isGrabbing = false;

  @override
  void initState() {
    super.initState();
    _loadReleases();
    _checkGrabStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _checkGrabStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadReleases() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _service.fetchReleases(
        tmdbId: widget.tmdbId,
        title: widget.title,
        year: widget.year,
      );

      if (mounted) {
        setState(() {
          _releases = response.releases;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load releases: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkGrabStatus() async {
    final status = await _service.getGrabStatus(widget.title);
    if (mounted) {
      setState(() {
        _grabStatus = status;
      });
    }
  }

  Future<void> _onGrab(TorrentRelease release) async {
    setState(() => _isGrabbing = true);
    final success = await _service.grabRelease(
      guid: release.guid,
      indexerId: release.indexerId,
    );
    setState(() => _isGrabbing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Grabbed "${release.title}" successfully!'
                : 'Failed to trigger grab for this release.',
          ),
          backgroundColor: success ? Colors.green.shade800 : Colors.red.shade800,
        ),
      );
      _checkGrabStatus();
    }
  }

  Future<void> _onCancelGrab() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Cancel Download?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to stop and delete this download?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Grab', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await _service.deleteGrab(widget.title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Download cancelled & removed.' : 'Failed to cancel grab.'),
          ),
        );
        setState(() => _grabStatus = null);
      }
    }
  }

  List<TorrentRelease> get _filteredReleases {
    return _releases.where((r) {
      switch (_activeFilter) {
        case '4k':
          return r.is4K;
        case '1080p':
          return r.is1080p;
        case '720p':
          return r.is720p;
        case 'tamilmv':
          return r.isTamilMV;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active Grab Banner (if downloading)
          if (_grabStatus != null && _grabStatus!.isDownloading) _buildGrabStatusBar(),

          // Filter bar
          _buildFilterBar(),
          const SizedBox(height: 8),

          // Content body
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildGrabStatusBar() {
    final s = _grabStatus!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF14243B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.downloading, color: Colors.blueAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Downloading: ${s.progress.toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      '${s.speed} • ETA: ${s.timeleft}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: s.progress / 100.0,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent),
            tooltip: 'Cancel Download',
            onPressed: _onCancelGrab,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip('all', 'All (${_releases.length})'),
          _filterChip('4k', '4K UHD'),
          _filterChip('1080p', '1080p'),
          _filterChip('720p', '720p'),
          _filterChip('tamilmv', '1TamilMV'),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final active = _activeFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        selectedColor: Colors.blue.shade700,
        backgroundColor: Colors.white10,
        labelStyle: TextStyle(
          color: active ? Colors.white : Colors.white70,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) => setState(() => _activeFilter = key),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 16),
            Text('Searching torrent indexers & 1TamilMV...', style: TextStyle(color: Colors.white70)),
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
            ElevatedButton(onPressed: _loadReleases, child: const Text('Retry')),
          ],
        ),
      );
    }

    final list = _filteredReleases;
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'No releases found for this filter.',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (ctx, idx) => _buildReleaseCard(list[idx]),
    );
  }

  Widget _buildReleaseCard(TorrentRelease r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Quality badge
              if (r.quality.isNotEmpty)
                _badge(
                  r.quality,
                  r.is4K ? Colors.purple.shade400 : Colors.blue.shade400,
                ),
              // Indexer badge
              _badge(
                r.indexer,
                r.isTamilMV ? Colors.orange.shade400 : Colors.teal.shade400,
              ),
              // Size badge
              _badge(r.formattedSize, Colors.grey.shade400),
              const Spacer(),
              // Seeders & Leechers
              Row(
                children: [
                  const Icon(Icons.arrow_upward, size: 14, color: Colors.greenAccent),
                  Text('${r.seeders}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_downward, size: 14, color: Colors.redAccent),
                  Text('${r.leechers}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Grab'),
                onPressed: _isGrabbing ? null : () => _onGrab(r),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

