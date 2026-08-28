// Home-screen widget support (Android App Widget + iOS WidgetKit extension).
// Neither platform can host a live/interactive map inside a widget -- both
// only support a periodically-refreshed static snapshot, tappable to deep
// link into the real app. This service produces that snapshot and routes
// widget taps.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';

const kHomeWidgetAppGroupId = 'group.com.peninsulathreat.resqruck';
const _kAndroidWidgetProvider = 'ResqruckWidgetProvider';
const _kIosWidgetKind = 'ResqruckWidget';

// Same OSM tile source already used everywhere else in the app
// (tac_map.dart's private _kBaseTileUrl) -- duplicated here rather than
// exported since it's a single literal.
const _kTileUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const _kTileSubdomains = ['a', 'b', 'c'];
const _kZoom = 15;
const _kSnapshotPx = 320; // square, @1x -- matches the widget's ImageView

class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();

  Timer? _timer;
  bool _initialized = false;

  /// Call once after the authenticated app shell is up. Starts a 5-minute
  /// foreground refresh loop; background refresh (app closed) is handled by
  /// each platform's own widget update mechanism (Android's periodic
  /// AppWidgetProvider callback, iOS's WidgetKit timeline) on a best-effort
  /// basis -- neither platform guarantees fast background updates.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await HomeWidget.setAppGroupId(kHomeWidgetAppGroupId);
    } catch (_) {}
    unawaited(refreshNow());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => refreshNow());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _initialized = false;
  }

  /// Fetches current position, renders a map snapshot centered on it, and
  /// pushes both to the platform widget. Silently no-ops on failure (no GPS
  /// fix, no permission, offline) -- the widget just keeps showing whatever
  /// it last had, same as any other map-snapshot widget.
  Future<void> refreshNow() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 12));
      await _saveSnapshot(pos.latitude, pos.longitude);
      await HomeWidget.saveWidgetData(
          'coords', '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
      await HomeWidget.updateWidget(androidName: _kAndroidWidgetProvider, iOSName: _kIosWidgetKind);
    } catch (e) {
      debugPrint('HomeWidgetService.refreshNow skipped: $e');
    }
  }

  static int _lonToTileX(double lon, int z) => ((lon + 180.0) / 360.0 * (1 << z)).floor();
  static int _latToTileY(double lat, int z) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2.0 * (1 << z)).floor();
  }

  static double _lonToPx(double lon, int z) => (lon + 180.0) / 360.0 * (256 << z);
  static double _latToPx(double lat, int z) {
    final latRad = lat * pi / 180.0;
    return (1.0 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2.0 * (256 << z);
  }

  /// Composites a 3x3 mosaic of 256px OSM tiles centered on (lat, lng),
  /// draws a location dot at the exact pixel position, crops a centered
  /// square, and writes the PNG wherever home_widget expects to find it
  /// (App Group container on iOS, app-support dir on Android) -- mirroring
  /// what HomeWidget.renderFlutterWidget does internally, done manually here
  /// because that helper's single synchronous paint pass can't wait on
  /// flutter_map's async network tile loads.
  Future<void> _saveSnapshot(double lat, double lng) async {
    const gridSize = 3;
    final centerTileX = _lonToTileX(lng, _kZoom);
    final centerTileY = _latToTileY(lat, _kZoom);
    final topLeftTileX = centerTileX - gridSize ~/ 2;
    final topLeftTileY = centerTileY - gridSize ~/ 2;

    final tiles = <(int, int, Uint8List)>[];
    var subdomainIdx = 0;
    for (var dy = 0; dy < gridSize; dy++) {
      for (var dx = 0; dx < gridSize; dx++) {
        final tx = topLeftTileX + dx;
        final ty = topLeftTileY + dy;
        final subdomain = _kTileSubdomains[subdomainIdx++ % _kTileSubdomains.length];
        final url = _kTileUrl
            .replaceFirst('{s}', subdomain)
            .replaceFirst('{z}', '$_kZoom')
            .replaceFirst('{x}', '$tx')
            .replaceFirst('{y}', '$ty');
        try {
          final resp = await http.get(Uri.parse(url), headers: const {'User-Agent': 'com.resqruck.app'});
          if (resp.statusCode == 200) tiles.add((dx, dy, resp.bodyBytes));
        } catch (_) {}
      }
    }
    if (tiles.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final mosaicSize = (256 * gridSize).toDouble();
    canvas.drawRect(Rect.fromLTWH(0, 0, mosaicSize, mosaicSize), Paint()..color = const Color(0xFFE0E0E0));
    for (final (dx, dy, bytes) in tiles) {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      canvas.drawImage(frame.image, Offset(dx * 256.0, dy * 256.0), Paint());
      frame.image.dispose();
    }

    // Marker's pixel position within the mosaic.
    final mosaicOriginPxX = topLeftTileX * 256.0;
    final mosaicOriginPxY = topLeftTileY * 256.0;
    final markerX = _lonToPx(lng, _kZoom) - mosaicOriginPxX;
    final markerY = _latToPx(lat, _kZoom) - mosaicOriginPxY;
    canvas.drawCircle(Offset(markerX, markerY), 9, Paint()..color = const Color(0xFF00B4D8));
    canvas.drawCircle(Offset(markerX, markerY), 9, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);

    final mosaicPicture = recorder.endRecording();
    final mosaicImage = await mosaicPicture.toImage(mosaicSize.toInt(), mosaicSize.toInt());

    // Crop a centered square of the target snapshot size around the marker.
    final cropRecorder = ui.PictureRecorder();
    final cropCanvas = Canvas(cropRecorder);
    const half = _kSnapshotPx / 2;
    final srcRect = Rect.fromLTWH(markerX - half, markerY - half, _kSnapshotPx.toDouble(), _kSnapshotPx.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, _kSnapshotPx.toDouble(), _kSnapshotPx.toDouble());
    cropCanvas.drawImageRect(mosaicImage, srcRect, dstRect, Paint());
    final finalPicture = cropRecorder.endRecording();
    final finalImage = await finalPicture.toImage(_kSnapshotPx, _kSnapshotPx);
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
    mosaicImage.dispose();
    finalImage.dispose();
    if (byteData == null) return;

    final directory = defaultTargetPlatform == TargetPlatform.iOS
        ? await PathProviderFoundation().getContainerPath(appGroupIdentifier: kHomeWidgetAppGroupId)
        : (await getApplicationSupportDirectory()).path;
    if (directory == null) return;
    final file = File('$directory/home_widget/map_snapshot.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(byteData.buffer.asUint8List());
    await HomeWidget.saveWidgetData('map_snapshot', file.path);
  }

  /// Routes a widget-tap deep link (or the app's own initial launch URI) to
  /// the right screen. Called once at startup and on every widgetClicked
  /// event while running.
  static WidgetRoute? routeFor(Uri? uri) {
    if (uri == null) return null;
    switch (uri.host.isNotEmpty ? uri.host : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '')) {
      case 'protocols':
        return WidgetRoute.protocols;
      case '8line':
        return WidgetRoute.eightLine;
      default:
        return WidgetRoute.map;
    }
  }
}

enum WidgetRoute { map, protocols, eightLine }
