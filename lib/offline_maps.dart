import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

// ── Cached Tile Provider ──────────────────────────────────────────────────────

class _CachedTileProvider extends TileProvider {
  final Directory cacheDir;
  _CachedTileProvider(this.cacheDir);

  @override
  ImageProvider<Object> getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    final file = File('${cacheDir.path}/${coordinates.z}_${coordinates.x}_${coordinates.y}.png');
    return _CachedNetworkImageProvider(url, file);
  }
}

class _CachedNetworkImageProvider extends ImageProvider<_CachedNetworkImageProvider> {
  final String url;
  final File cacheFile;
  const _CachedNetworkImageProvider(this.url, this.cacheFile);

  @override
  Future<_CachedNetworkImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1.0);

  Future<ui.Codec> _load(_CachedNetworkImageProvider key, ImageDecoderCallback decode) async {
    Uint8List bytes;
    if (await key.cacheFile.exists()) {
      bytes = await key.cacheFile.readAsBytes();
    } else {
      try {
        final response = await http
            .get(Uri.parse(key.url), headers: {'User-Agent': 'AustereMed/1.3 Flutter'})
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          bytes = response.bodyBytes;
          await key.cacheFile.parent.create(recursive: true);
          await key.cacheFile.writeAsBytes(bytes);
        } else {
          bytes = _kTransparent;
        }
      } catch (_) {
        bytes = _kTransparent;
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _CachedNetworkImageProvider && url == other.url);

  @override
  int get hashCode => url.hashCode;
}

// 1×1 transparent PNG
final Uint8List _kTransparent = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41,
  0x54, 0x08, 0xD7, 0x63, 0x60, 0x00, 0x00, 0x00,
  0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

// ── Tile Sources ──────────────────────────────────────────────────────────────

const Map<String, String> kTileSources = {
  'OpenTopoMap': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
  'OpenStreetMap': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  'ESRI Imagery': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
};

// ── Tile Coordinate Helper ────────────────────────────────────────────────────

({int x, int y}) _latLonToTile(double lat, double lon, int zoom) {
  final n = 1 << zoom;
  final x = ((lon + 180) / 360 * n).floor();
  final latRad = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor();
  return (x: x, y: y);
}

// ── Region Downloader ─────────────────────────────────────────────────────────

Future<int> downloadRegion({
  required LatLng center,
  required int radiusTiles,
  required int zoom,
  required String urlTemplate,
  required Directory cacheDir,
  required void Function(int done, int total) onProgress,
}) async {
  final origin = _latLonToTile(center.latitude, center.longitude, zoom);
  final tiles = <(int, int)>[];
  for (int dx = -radiusTiles; dx <= radiusTiles; dx++) {
    for (int dy = -radiusTiles; dy <= radiusTiles; dy++) {
      tiles.add((origin.x + dx, origin.y + dy));
    }
  }

  int done = 0;
  for (final (x, y) in tiles) {
    final file = File('${cacheDir.path}/${zoom}_${x}_$y.png');
    if (!await file.exists()) {
      final url = urlTemplate
          .replaceAll('{z}', '$zoom')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
      try {
        final response = await http
            .get(Uri.parse(url), headers: {'User-Agent': 'AustereMed/1.3 Flutter'})
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          await file.parent.create(recursive: true);
          await file.writeAsBytes(response.bodyBytes);
        }
      } catch (_) {}
    }
    done++;
    onProgress(done, tiles.length);
  }
  return done;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(37.7749, -122.4194);
  String _tileSource = 'OpenTopoMap';
  Directory? _cacheDir;
  bool _downloading = false;
  double _downloadProgress = 0;
  String _statusMsg = '';

  @override
  void initState() {
    super.initState();
    _initCache();
  }

  Future<void> _initCache() async {
    final base = await getApplicationDocumentsDirectory();
    setState(() => _cacheDir = Directory('${base.path}/tile_cache'));
  }

  Future<void> _goToMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _center = loc);
      _mapController.move(loc, 13);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location. Check permissions.')),
        );
      }
    }
  }

  Future<void> _downloadArea() async {
    if (_cacheDir == null || _downloading) return;
    setState(() { _downloading = true; _downloadProgress = 0; _statusMsg = 'Downloading…'; });

    final urlTemplate = kTileSources[_tileSource]!;
    int overallDone = 0;

    for (int z = 10; z <= 14; z++) {
      await downloadRegion(
        center: _center,
        radiusTiles: 3,
        zoom: z,
        urlTemplate: urlTemplate,
        cacheDir: _cacheDir!,
        onProgress: (done, total) {
          overallDone++;
          setState(() => _downloadProgress = overallDone / (total * 5));
        },
      );
    }

    setState(() {
      _downloading = false;
      _statusMsg = 'Download complete — region cached for offline use.';
    });
  }

  Future<void> _clearCache() async {
    if (_cacheDir == null) return;
    if (await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create();
    }
    setState(() => _statusMsg = 'Cache cleared.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Tile source',
            onSelected: (s) => setState(() => _tileSource = s),
            itemBuilder: (_) => kTileSources.keys
                .map((k) => PopupMenuItem(value: k, child: Text(k)))
                .toList(),
          ),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Clear cache', onPressed: _clearCache),
        ],
      ),
      body: Column(
        children: [
          if (_statusMsg.isNotEmpty)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_statusMsg, style: const TextStyle(fontSize: 13)),
            ),
          if (_downloading)
            LinearProgressIndicator(value: _downloadProgress),
          Expanded(
            child: _cacheDir == null
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 12,
                      onPositionChanged: (pos, _) {
                        setState(() => _center = pos.center);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: kTileSources[_tileSource]!,
                        tileProvider: _CachedTileProvider(_cacheDir!),
                        userAgentPackageName: 'com.aerie.AustereMed1',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: _center,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                        ),
                      ]),
                    ],
                  ),
          ),
          // Bottom toolbar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _downloading ? null : _downloadArea,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Area'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _goToMyLocation,
                  icon: const Icon(Icons.my_location),
                  tooltip: 'My location',
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
