import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// wildfire.gov uses a government CA absent from Dart's trust store.
// SecurityContext(withTrustedRoots:false) + badCertificateCallback bypass
// both cert-chain failures and the HandshakeException that occurs when the
// server drops a TLS connection before the certificate is even presented.
http.Client wildfireHttpClient() => IOClient(
      HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..badCertificateCallback = (_, __, ___) => true,
    );

/// Rotates [point] about [center] by [degrees] counterclockwise, using a
/// locally-flat approximation (longitude scaled by cos(latitude) to account
/// for meridian convergence) -- accurate enough over the few-mile extent of
/// a single incident map. Used for KML <rotation> and any other
/// rotated-rectangle overlay math.
LatLng rotateAroundCenter(LatLng point, LatLng center, double degrees) {
  final centerLatRad = center.latitude * pi / 180;
  final cosLat = cos(centerLatRad);
  final dx = (point.longitude - center.longitude) * cosLat;
  final dy = point.latitude - center.latitude;
  final theta = degrees * pi / 180;
  final rotatedDx = dx * cos(theta) - dy * sin(theta);
  final rotatedDy = dx * sin(theta) + dy * cos(theta);
  return LatLng(center.latitude + rotatedDy, center.longitude + (cosLat == 0 ? 0 : rotatedDx / cosLat));
}

class IncidentOverlay {
  final String name;
  final Uint8List? imageBytes;       // null for polygon-only KMZ
  final LatLngBounds bounds;
  final List<List<LatLng>> polygons; // fire perimeter polygons (may be empty)
  // The image's actual three corners (top-left, bottom-left, bottom-right)
  // for RotatedOverlayImage -- NOT necessarily bounds' own NW/SW/SE, since
  // many wildfire.gov products (KML <rotation>, non-north-up GeoPDFs) are
  // rotated relative to true north. Defaults to bounds' own corners (an
  // unrotated rectangle) when there's no rotation to account for.
  final LatLng topLeft;
  final LatLng bottomLeft;
  final LatLng bottomRight;
  IncidentOverlay({
    required this.name,
    this.imageBytes,
    required this.bounds,
    this.polygons = const [],
    LatLng? topLeft,
    LatLng? bottomLeft,
    LatLng? bottomRight,
  })  : topLeft = topLeft ?? bounds.northWest,
        bottomLeft = bottomLeft ?? bounds.southWest,
        bottomRight = bottomRight ?? bounds.southEast;
}

/// Downloads (or reads a local `file://`/absolute path) and parses a KML or
/// KMZ fire map into an [IncidentOverlay]. Throws a plain [Exception] with a
/// user-presentable message on failure -- callers are expected to catch and
/// surface `$e` directly, matching this codebase's existing error-display
/// convention.
Future<IncidentOverlay> loadWildfireKmz(String url, String name) async {
  final isLocal = url.startsWith('/') || url.startsWith('file://');
  final Uint8List bodyBytes;
  if (isLocal) {
    final path = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
    bodyBytes = await File(path).readAsBytes();
  } else {
    final client = wildfireHttpClient();
    final resp = await client.get(Uri.parse(url));
    client.close();
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    bodyBytes = resp.bodyBytes;
  }

  // KML files are plain XML — skip the zip decoder
  String? kmlContent;
  Uint8List? imgBytes;
  List<String> archiveFiles = []; // for debug messaging

  final lowerUrl = url.toLowerCase();
  // Strip double-extension saved by downloader (e.g. file.kmz.kmz → treat as kmz)
  final effectiveExt = lowerUrl.endsWith('.kml') && !lowerUrl.endsWith('.kmz.kml')
      ? '.kml'
      : '.kmz';

  if (effectiveExt == '.kml') {
    kmlContent = String.fromCharCodes(bodyBytes);
  } else {
    final archive = ZipDecoder().decodeBytes(bodyBytes);
    archiveFiles = archive.files.where((f) => f.isFile).map((f) => f.name).toList();

    // Pass 1: find KML only.
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name.toLowerCase().endsWith('.kml') && kmlContent == null) {
        kmlContent = String.fromCharCodes(file.content);
      }
    }

    if (kmlContent != null) {
      // Read the image name the KML actually references in its GroundOverlay.
      // This is the ONLY reliable source — picking the first image in the ZIP
      // can yield a thumbnail/legend instead of the overlay.
      final groundMatch = RegExp(
          r'<GroundOverlay[\s\S]*?<Icon[\s\S]*?<href>\s*(.*?)\s*</href>',
          caseSensitive: false).firstMatch(kmlContent);
      final overlayHref = groundMatch?.group(1)?.trim();

      // Pass 2: find the overlay image by href, then fall back to first
      // supported-format image if href lookup fails.
      Uint8List? firstImg;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final fn = file.name;
        final lc = fn.toLowerCase();
        final isSupportedImg = lc.endsWith('.png') || lc.endsWith('.jpg') ||
            lc.endsWith('.jpeg') || lc.endsWith('.gif') || lc.endsWith('.webp');

        if (overlayHref != null) {
          // Targeted lookup: exact path, case-insensitive path, or basename match.
          final hrefLc = overlayHref.toLowerCase();
          if (fn == overlayHref ||
              lc == hrefLc ||
              fn.split('/').last.toLowerCase() == hrefLc.split('/').last.toLowerCase()) {
            imgBytes = Uint8List.fromList(file.content);
            break;
          }
        }
        // Keep a reference to the first supported image as a fallback.
        if (isSupportedImg && firstImg == null) {
          firstImg = Uint8List.fromList(file.content);
        }
      }
      // If the href-named file wasn't found (or no href), use first image.
      imgBytes ??= firstImg;
    }

    // Validate image format via magic bytes. If unsupported by Flutter's
    // native decoder (e.g. TIFF from NIFC fire maps), transcode to PNG
    // via the image package so the overlay always renders.
    if (imgBytes != null && imgBytes.isNotEmpty) {
      final isPng  = imgBytes.length > 3 &&
          imgBytes[0] == 0x89 && imgBytes[1] == 0x50 &&
          imgBytes[2] == 0x4E && imgBytes[3] == 0x47;
      final isJpeg = imgBytes.length > 2 &&
          imgBytes[0] == 0xFF && imgBytes[1] == 0xD8 && imgBytes[2] == 0xFF;
      final isGif  = imgBytes.length > 2 &&
          imgBytes[0] == 0x47 && imgBytes[1] == 0x49 && imgBytes[2] == 0x46;
      final isWebp = imgBytes.length > 11 &&
          imgBytes[0] == 0x52 && imgBytes[1] == 0x49 &&
          imgBytes[8] == 0x57 && imgBytes[9] == 0x45;
      if (!isPng && !isJpeg && !isGif && !isWebp) {
        // Transcode unsupported formats (TIFF, BMP, etc.) to PNG.
        try {
          final decoded = img.decodeImage(imgBytes);
          imgBytes = decoded != null
              ? Uint8List.fromList(img.encodePng(decoded))
              : null;
        } catch (_) {
          imgBytes = null;
        }
      }
    }
  }

  if (kmlContent == null) {
    throw Exception('No KML found in archive. Files: ${archiveFiles.join(', ')}');
  }

  final northM = RegExp(r'<north>\s*([\d.\-]+)\s*</north>').firstMatch(kmlContent);
  final southM = RegExp(r'<south>\s*([\d.\-]+)\s*</south>').firstMatch(kmlContent);
  final eastM  = RegExp(r'<east>\s*([\d.\-]+)\s*</east>').firstMatch(kmlContent);
  final westM  = RegExp(r'<west>\s*([\d.\-]+)\s*</west>').firstMatch(kmlContent);

  final north = double.tryParse(northM?.group(1) ?? '');
  final south = double.tryParse(southM?.group(1) ?? '');
  final east  = double.tryParse(eastM?.group(1)  ?? '');
  final west  = double.tryParse(westM?.group(1)  ?? '');
  // <LatLonBox> may also carry a <rotation> in degrees (KML spec: positive =
  // counterclockwise, applied about the box's center) -- common on
  // wildfire.gov products generated from non-north-up source imagery.
  // Ignoring it (as this code used to) renders the image as an unrotated
  // rectangle, which lines up at the center but drifts toward the edges.
  final rotationM = RegExp(r'<rotation>\s*([\d.\-]+)\s*</rotation>').firstMatch(kmlContent);
  final rotationDeg = double.tryParse(rotationM?.group(1) ?? '') ?? 0.0;

  LatLngBounds bounds;
  List<List<LatLng>> polygons = [];
  LatLng? topLeft, bottomLeft, bottomRight;

  if (north != null && south != null && east != null && west != null) {
    // Image overlay with explicit bounds
    if (imgBytes == null) {
      throw Exception('No overlay image found. Archive contents: ${archiveFiles.join(', ')}');
    }
    bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));
    if (rotationDeg != 0.0) {
      final center = LatLng((north + south) / 2, (east + west) / 2);
      topLeft = rotateAroundCenter(LatLng(north, west), center, rotationDeg);
      bottomLeft = rotateAroundCenter(LatLng(south, west), center, rotationDeg);
      bottomRight = rotateAroundCenter(LatLng(south, east), center, rotationDeg);
    }
  } else {
    // No LatLonBox — try to extract polygon perimeter from coordinates
    final coordRe = RegExp(r'<coordinates>\s*([\s\S]*?)\s*</coordinates>');
    final allPoints = <LatLng>[];
    for (final m in coordRe.allMatches(kmlContent)) {
      final ring = <LatLng>[];
      for (final token in (m.group(1) ?? '').trim().split(RegExp(r'\s+'))) {
        final parts = token.split(',');
        if (parts.length >= 2) {
          final lng = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          if (lat != null && lng != null) {
            ring.add(LatLng(lat, lng));
            allPoints.add(LatLng(lat, lng));
          }
        }
      }
      if (ring.length >= 3) polygons.add(ring);
    }
    if (allPoints.isEmpty) throw Exception('Could not parse map bounds from KML');
    final lats = allPoints.map((p) => p.latitude);
    final lngs = allPoints.map((p) => p.longitude);
    bounds = LatLngBounds(
      LatLng(lats.reduce(min), lngs.reduce(min)),
      LatLng(lats.reduce(max), lngs.reduce(max)),
    );
  }

  return IncidentOverlay(
    name: name, imageBytes: imgBytes, bounds: bounds, polygons: polygons,
    topLeft: topLeft, bottomLeft: bottomLeft, bottomRight: bottomRight,
  );
}

class GeoPdfGeoref {
  final LatLngBounds bounds;
  final LatLng topLeft;
  final LatLng bottomLeft;
  final LatLng bottomRight;
  // [x0, y0, x1, y1] in PDF points (bottom-left origin) of the specific
  // Viewport this georeferencing came from, when one was found -- null means
  // the whole rendered page should be used as-is (no per-frame crop needed).
  final List<double>? pageBBox;
  const GeoPdfGeoref({
    required this.bounds,
    required this.topLeft,
    required this.bottomLeft,
    required this.bottomRight,
    this.pageBBox,
  });
}

/// Extract georeferencing from a GeoPDF's /GPTS (and, when present, /LPTS)
/// arrays. Returns null if no georeferencing data is found.
///
/// /GPTS gives the lat/lng of each ground-control point; /LPTS gives that
/// same point's position within its Viewport's own on-page rectangle as a
/// 0..1 fraction (PDF's bottom-left origin). Many wildfire.gov GeoPDFs are
/// NOT north-up, so collapsing GPTS to a min/max axis-aligned box (the old
/// behavior) and rendering it as an unrotated rectangle lines up at the
/// center but drifts toward the edges. Pairing GPTS with LPTS recovers the
/// true (possibly rotated) quadrilateral -- falling back to the unrotated
/// box when LPTS is missing/mismatched.
///
/// A single page commonly carries MULTIPLE Viewport dictionaries -- e.g. a
/// wildfire.gov Division/IAP map's main tactical map plus a small locator
////vicinity inset in a corner, each with its own /BBox (on-page rectangle)
/// and its own /Measure/GPTS. Picking the wrong one, or ignoring /BBox
/// entirely and treating the whole page as if it were one frame, silently
/// stretches the image across the wrong geographic extent -- the symptom is
/// roads/terrain drifting out of alignment with the base map, worse on
/// whichever axis has more title/legend/margin space outside the real map
/// frame. Confirmed against a real wildfire.gov product (RoweCreekComplex
/// DIV P map, 2026-08-28): the main map frame's BBox covered 2520x3042pt of
/// a 2592x3456pt page -- stretching the full page over just that frame's
/// GPTS bounds was ~3% too wide and ~14% too tall.
GeoPdfGeoref? parseGeoPdfGeoref(Uint8List pdfBytes) {
  // Scan printable-ASCII portion of the PDF bytes for the /GPTS key.
  // Binary sections are replaced with spaces so the regex can't cross them.
  final sb = StringBuffer();
  for (final b in pdfBytes) {
    sb.writeCharCode((b >= 32 && b < 127) ? b : 32);
  }
  final str = sb.toString();

  // A Viewport dictionary lays out as
  // <</BBox[...]/Measure<<.../GPTS[...]/LPTS[...]/Subtype/GEO.../Type/Measure>>/Type/Viewport>>
  // -- exactly one Measure block (and so exactly one GPTS/LPTS pair) sits
  // between a given /BBox and the next one, so a non-greedy match pairs each
  // triple correctly even with several Viewports back-to-back in the array.
  final vpRe = RegExp(
    r'/BBox\s*\[\s*([\d.\-\s]+?)\s*\][\s\S]*?/GPTS\s*\[\s*([\d.\-\s]+?)\s*\][\s\S]*?/LPTS\s*\[\s*([\d.\-\s]+?)\s*\]',
  );

  List<double>? bestBBox;
  List<double>? bestGpts;
  List<double>? bestLpts;
  var bestArea = -1.0;
  for (final m in vpRe.allMatches(str)) {
    final bbox = m.group(1)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList();
    final gpts = m.group(2)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList();
    final lpts = m.group(3)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList();
    if (bbox.length != 4 || gpts.length < 8 || lpts.length != gpts.length) continue;
    // The main map frame is always the largest on-page rectangle -- locator
    // /vicinity insets are, by convention, much smaller than the map they
    // accompany.
    final area = (bbox[2] - bbox[0]).abs() * (bbox[3] - bbox[1]).abs();
    if (area > bestArea) {
      bestArea = area;
      bestBBox = bbox;
      bestGpts = gpts;
      bestLpts = lpts;
    }
  }

  List<double> gptsNums;
  List<double>? lptsNums;
  final pageBBox = bestBBox;

  if (bestGpts != null) {
    gptsNums = bestGpts;
    lptsNums = bestLpts;
  } else {
    // Fall back to a bare top-level /GPTS (+ optional /LPTS) for files that
    // don't expose a plain-text /BBox/Viewport structure (e.g. the geospatial
    // metadata sits inside a compressed object stream this raw-byte scan
    // can't see into) -- no per-frame cropping is possible in that case.
    final gptsMatch = RegExp(r'/GPTS\s*\[\s*([\d\s.\-]+)\s*\]').firstMatch(str);
    if (gptsMatch == null) return null;
    gptsNums = gptsMatch.group(1)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList();
    if (gptsNums.length < 8) return null;
    final lptsMatch = RegExp(r'/LPTS\s*\[\s*([\d\s.\-]+)\s*\]').firstMatch(str);
    lptsNums = lptsMatch != null
        ? lptsMatch.group(1)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList()
        : null;
  }

  // GPTS pairs are (lat, lng) for each ground-control point.
  final geoPoints = <LatLng>[];
  for (var i = 0; i + 1 < gptsNums.length; i += 2) {
    geoPoints.add(LatLng(gptsNums[i], gptsNums[i + 1]));
  }

  final lats = geoPoints.map((p) => p.latitude);
  final lngs = geoPoints.map((p) => p.longitude);
  final south = lats.reduce(min);
  final north = lats.reduce(max);
  final west  = lngs.reduce(min);
  final east  = lngs.reduce(max);
  if (south >= north || west >= east) return null;
  if (south < -90 || north > 90 || west < -180 || east > 180) return null;
  final bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));

  if (lptsNums != null && lptsNums.length == gptsNums.length) {
    final pagePoints = <(double, double)>[];
    for (var i = 0; i + 1 < lptsNums.length; i += 2) {
      pagePoints.add((lptsNums[i], lptsNums[i + 1]));
    }
    // Nearest ground-control point (in frame-fraction space) to each of
    // the three corners RotatedOverlayImage needs: top-left=(0,1),
    // bottom-left=(0,0), bottom-right=(1,0) -- PDF's y axis runs bottom-up.
    LatLng nearestTo(double tx, double ty) {
      var bestIdx = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < pagePoints.length && i < geoPoints.length; i++) {
        final dx = pagePoints[i].$1 - tx;
        final dy = pagePoints[i].$2 - ty;
        final d = dx * dx + dy * dy;
        if (d < bestDist) { bestDist = d; bestIdx = i; }
      }
      return geoPoints[bestIdx];
    }
    return GeoPdfGeoref(
      bounds: bounds,
      topLeft: nearestTo(0, 1),
      bottomLeft: nearestTo(0, 0),
      bottomRight: nearestTo(1, 0),
      pageBBox: pageBBox,
    );
  }

  return GeoPdfGeoref(
    bounds: bounds, topLeft: bounds.northWest, bottomLeft: bounds.southWest, bottomRight: bounds.southEast,
    pageBBox: pageBBox,
  );
}

/// Downloads (or reads a local `file://`/absolute path) a GeoPDF, rasterizes
/// its first page, and returns an [IncidentOverlay]. Throws a plain
/// [Exception] with a user-presentable message on failure.
Future<IncidentOverlay> loadWildfirePdf(String url, String name) async {
  final isLocal = url.startsWith('/') || url.startsWith('file://');
  final Uint8List pdfBytes;
  if (isLocal) {
    final path = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
    pdfBytes = await File(path).readAsBytes();
  } else {
    final client = wildfireHttpClient();
    final resp = await client.get(Uri.parse(url));
    client.close();
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    pdfBytes = resp.bodyBytes;
  }

  // Extract georeferencing from the GeoPDF /GPTS + /LPTS viewport metadata.
  final georef = parseGeoPdfGeoref(pdfBytes);
  if (georef == null) {
    throw Exception(
        'No geographic coordinates found.\n'
        'Only georeferenced (GeoPDF) files are supported.');
  }

  // Render first page to a raster image capped at 4096px on longest side --
  // GeoPDFs often cover large areas, so more source pixels are needed than
  // a typical on-screen image to stay legible when zoomed in close.
  final doc = await PdfDocument.openData(pdfBytes);
  final page = doc.pages[0];
  const maxPx = 4096.0;
  final scale = maxPx / max(page.width, page.height);
  final pdfImage = await page.render(
      fullWidth: page.width * scale, fullHeight: page.height * scale);
  if (pdfImage == null) {
    doc.dispose();
    throw Exception('Failed to render PDF page.');
  }

  // BGRA pixels → dart:ui Image → PNG bytes
  final uiImage = await pdfImage.createImage();
  pdfImage.dispose();
  final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
  uiImage.dispose();
  if (byteData == null) {
    doc.dispose();
    throw Exception('Failed to encode PDF as PNG.');
  }
  var pngBytes = byteData.buffer.asUint8List();

  // If georeferencing came from a specific Viewport's own on-page BBox
  // rather than the whole page, crop the rendered raster down to just that
  // rectangle. Otherwise the image -- which also includes title blocks,
  // legends, and any locator/vicinity inset outside the main map frame --
  // gets stretched across the main frame's geographic bounds, throwing off
  // the scale on whichever axis has more margin (see parseGeoPdfGeoref).
  final bbox = georef.pageBBox;
  if (bbox != null) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded != null) {
      final x0 = (bbox[0] * scale).round().clamp(0, decoded.width);
      final x1 = (bbox[2] * scale).round().clamp(0, decoded.width);
      // PDF points are bottom-up; image pixels are top-down.
      final y0 = ((page.height - bbox[3]) * scale).round().clamp(0, decoded.height);
      final y1 = ((page.height - bbox[1]) * scale).round().clamp(0, decoded.height);
      final w = x1 - x0;
      final h = y1 - y0;
      if (w > 0 && h > 0) {
        final cropped = img.copyCrop(decoded, x: x0, y: y0, width: w, height: h);
        pngBytes = Uint8List.fromList(img.encodePng(cropped));
      }
    }
  }
  doc.dispose();

  return IncidentOverlay(
    name: name, imageBytes: pngBytes, bounds: georef.bounds, polygons: const [],
    topLeft: georef.topLeft, bottomLeft: georef.bottomLeft, bottomRight: georef.bottomRight,
  );
}

/// Single entry point for loading either a KMZ/KML or a GeoPDF fire map,
/// dispatching by file extension.
Future<IncidentOverlay> loadWildfireOverlay(String url, String name) {
  if (url.toLowerCase().endsWith('.pdf')) return loadWildfirePdf(url, name);
  return loadWildfireKmz(url, name);
}

const kWildfireRootUrl = 'https://ftp.wildfire.gov/public/incident_specific_maps/';

class WildfireDirectoryEntry {
  final String name;
  final String url;
  final bool isDirectory;
  final bool isPdf;
  final bool isKml;
  const WildfireDirectoryEntry({
    required this.name,
    required this.url,
    required this.isDirectory,
    this.isPdf = false,
    this.isKml = false,
  });
  bool get isLoadable => !isDirectory; // KMZ, KML, and PDF (GeoPDF) can be overlaid
}

List<WildfireDirectoryEntry> parseWildfireApacheIndex(String html, String baseUrl) {
  final entries = <WildfireDirectoryEntry>[];
  final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  final pattern = RegExp(r'href="([^"?#][^"]*?)"', caseSensitive: false);
  for (final m in pattern.allMatches(html)) {
    final href = m.group(1)!;
    // Skip parent dirs, absolute paths, absolute URLs, and empty
    if (href.isEmpty) continue;
    if (href.startsWith('..') || href.startsWith('/') || href.startsWith('http')) continue;
    final isDir = href.endsWith('/');
    final lower = href.toLowerCase();
    final isKmz = lower.endsWith('.kmz');
    final isKml = lower.endsWith('.kml');
    final isPdf = lower.endsWith('.pdf');
    if (!isDir && !isKmz && !isKml && !isPdf) continue;
    entries.add(WildfireDirectoryEntry(
      name: Uri.decodeComponent(href.replaceAll('/', '')),
      url: '$base$href',
      isDirectory: isDir,
      isKml: isKml,
      isPdf: isPdf,
    ));
  }
  return entries;
}

/// Browses the wildfire.gov incident-specific-maps directory and lets the
/// user pick a KMZ/KML/GeoPDF to load as a map overlay. Reused by both the
/// mobile field app (inside a bottom sheet, [scrollController] supplied) and
/// the desktop Command Console (inside a plain dialog, no controller needed).
///
/// [enableDownloadCache] controls whether files get cached to local storage
/// (SharedPreferences-tracked, under the app's documents directory) so they
/// can be reloaded without re-downloading -- this matters on a phone with
/// spotty field connectivity, but not on a desktop machine with a normal
/// network connection, so the Console passes `false`.
class WildfireIncidentBrowser extends StatefulWidget {
  final ScrollController? scrollController;
  final void Function(String url, String name, {bool asBase}) onLoad;
  final bool enableDownloadCache;

  const WildfireIncidentBrowser({
    super.key,
    this.scrollController,
    required this.onLoad,
    this.enableDownloadCache = true,
  });

  @override
  State<WildfireIncidentBrowser> createState() => _WildfireIncidentBrowserState();
}

class _WildfireIncidentBrowserState extends State<WildfireIncidentBrowser> {
  static const _prefsKey = 'fire_dl_paths';

  List<WildfireDirectoryEntry>? _entries;
  String? _error;
  String _currentUrl = kWildfireRootUrl;
  final List<String> _breadcrumbs = [kWildfireRootUrl];

  /// url -> local file path for downloaded KMZes
  Map<String, String> _dlPaths = {};
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    if (widget.enableDownloadCache) _loadDownloads();
    _fetchDirectory(kWildfireRootUrl);
  }

  Future<void> _loadDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final map = Map<String, String>.from(jsonDecode(raw) as Map);
      // Prune entries whose files were deleted
      final valid = <String, String>{};
      for (final e in map.entries) {
        if (await File(e.value).exists()) valid[e.key] = e.value;
      }
      if (mounted) setState(() => _dlPaths = valid);
    }
  }

  Future<void> _downloadKmz(WildfireDirectoryEntry e) async {
    if (_downloading.contains(e.url)) return;
    setState(() => _downloading.add(e.url));
    try {
      final client = wildfireHttpClient();
      final resp = await client.get(Uri.parse(e.url));
      client.close();
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final dir = await getApplicationDocumentsDirectory();
      final mapsDir = Directory('${dir.path}/fire_maps');
      await mapsDir.create(recursive: true);

      // e.name already includes extension (e.g. "Fire_Map.kmz") — don't append another
      final safe = e.name.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_');
      final file = File('${mapsDir.path}/$safe');
      await file.writeAsBytes(resp.bodyBytes);

      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_prefsKey);
      final map = existing != null
          ? Map<String, String>.from(jsonDecode(existing) as Map)
          : <String, String>{};
      map[e.url] = file.path;
      await prefs.setString(_prefsKey, jsonEncode(map));

      if (mounted) setState(() => _dlPaths[e.url] = file.path);
    } catch (ex) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Download failed: $ex'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(e.url));
    }
  }

  Future<void> _fetchDirectory(String url) async {
    if (mounted) setState(() { _entries = null; _error = null; });
    try {
      final client = wildfireHttpClient();
      final resp = await client.get(Uri.parse(url));
      client.close();
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final parsed = parseWildfireApacheIndex(resp.body, url);
      if (mounted) setState(() { _entries = parsed; _currentUrl = url; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _clearDownloads() async {
    for (final path in _dlPaths.values) {
      try { await File(path).delete(); } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    if (mounted) setState(() => _dlPaths.clear());
  }

  void _navigate(String url) {
    _breadcrumbs.add(url);
    _fetchDirectory(url);
  }

  void _back() {
    if (_breadcrumbs.length > 1) {
      _breadcrumbs.removeLast();
      _fetchDirectory(_breadcrumbs.last);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _currentUrl.length > kWildfireRootUrl.length
        ? _currentUrl.substring(kWildfireRootUrl.length)
        : '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
          child: Row(
            children: [
              if (_breadcrumbs.length > 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _back,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text('Wildfire Incident Maps',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (widget.enableDownloadCache && _dlPaths.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: 'Clear all downloads',
                  onPressed: _clearDownloads,
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _fetchDirectory(_currentUrl),
              ),
            ],
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        const Divider(height: 8),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : _entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : _entries!.isEmpty
                      ? const Center(
                          child: Text('No maps or subdirectories found.'))
                      : ListView.builder(
                          controller: widget.scrollController,
                          itemCount: _entries!.length,
                          itemBuilder: (_, i) {
                            final e = _entries![i];
                            final isDownloaded = widget.enableDownloadCache && _dlPaths.containsKey(e.url);
                            final isDownloading = widget.enableDownloadCache && _downloading.contains(e.url);

                            // Leading icon
                            final leadIcon = e.isDirectory
                                ? const Icon(Icons.folder, color: Colors.amber)
                                : e.isPdf
                                    ? Icon(Icons.picture_as_pdf,
                                        color: isDownloaded ? Colors.red : Colors.red.shade300)
                                    : Icon(Icons.map,
                                        color: isDownloaded ? Colors.green : Colors.grey);

                            // Download widget (shared for all non-directory entries)
                            Widget? dlWidget;
                            if (!widget.enableDownloadCache) {
                              dlWidget = null;
                            } else if (isDownloaded) {
                              dlWidget = const Tooltip(
                                  message: 'Downloaded',
                                  child: Icon(Icons.check_circle, color: Colors.green, size: 20));
                            } else if (isDownloading) {
                              dlWidget = const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2));
                            } else {
                              dlWidget = IconButton(
                                icon: const Icon(Icons.download, size: 20),
                                tooltip: 'Download for offline use',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _downloadKmz(e),
                              );
                            }

                            return ListTile(
                              dense: true,
                              leading: leadIcon,
                              title: Text(e.name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: e.isPdf
                                  ? const Text('GeoPDF — Load/Base to overlay on map',
                                      style: TextStyle(fontSize: 10, color: Colors.grey))
                                  : null,
                              trailing: e.isDirectory
                                  ? const Icon(Icons.chevron_right)
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (dlWidget != null) dlWidget,
                                        if (e.isLoadable) ...[
                                          const SizedBox(width: 6),
                                          FilledButton.tonal(
                                            onPressed: () {
                                              final local = _dlPaths[e.url];
                                              widget.onLoad(local ?? e.url, e.name);
                                            },
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                              minimumSize: const Size(44, 28),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            child: const Text('Load',
                                                style: TextStyle(fontSize: 12)),
                                          ),
                                          const SizedBox(width: 4),
                                          OutlinedButton(
                                            onPressed: () {
                                              final local = _dlPaths[e.url];
                                              widget.onLoad(local ?? e.url, e.name,
                                                  asBase: true);
                                            },
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              minimumSize: const Size(44, 28),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              foregroundColor: Colors.deepOrange,
                                              side: const BorderSide(color: Colors.deepOrange),
                                            ),
                                            child: const Text('Base',
                                                style: TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ],
                                    ),
                              onTap: e.isDirectory ? () => _navigate(e.url) : null,
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

/// Mobile presentation: same bottom-sheet/DraggableScrollableSheet chrome
/// this feature has always used.
void showWildfireBrowserSheet(
  BuildContext context, {
  required void Function(String url, String name, {bool asBase}) onLoad,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => WildfireIncidentBrowser(
        scrollController: ctrl,
        onLoad: onLoad,
      ),
    ),
  );
}

/// Desktop presentation: a plain dialog, matching the Command Console's
/// established "browse/pick a remote item" convention (dialogs, not bottom
/// sheets) -- and no download cache, since the Console runs on a normal
/// networked machine with no field/offline use case.
Future<void> showWildfireBrowserDialog(
  BuildContext context, {
  required void Function(String url, String name, {bool asBase}) onLoad,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(
        width: 560,
        height: 640,
        child: WildfireIncidentBrowser(
          onLoad: onLoad,
          enableDownloadCache: false,
        ),
      ),
    ),
  );
}
