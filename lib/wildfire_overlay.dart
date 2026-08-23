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

class IncidentOverlay {
  final String name;
  final Uint8List? imageBytes;       // null for polygon-only KMZ
  final LatLngBounds bounds;
  final List<List<LatLng>> polygons; // fire perimeter polygons (may be empty)
  const IncidentOverlay({
    required this.name,
    this.imageBytes,
    required this.bounds,
    this.polygons = const [],
  });
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

  LatLngBounds bounds;
  List<List<LatLng>> polygons = [];

  if (north != null && south != null && east != null && west != null) {
    // Image overlay with explicit bounds
    if (imgBytes == null) {
      throw Exception('No overlay image found. Archive contents: ${archiveFiles.join(', ')}');
    }
    bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));
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

  return IncidentOverlay(name: name, imageBytes: imgBytes, bounds: bounds, polygons: polygons);
}

/// Extract geographic bounds from a GeoPDF's /GPTS array.
/// Returns null if no georeferencing data is found.
LatLngBounds? parseGeoPdfBounds(Uint8List pdfBytes) {
  // Scan printable-ASCII portion of the PDF bytes for the /GPTS key.
  // Binary sections are replaced with spaces so the regex can't cross them.
  final sb = StringBuffer();
  for (final b in pdfBytes) {
    sb.writeCharCode((b >= 32 && b < 127) ? b : 32);
  }
  final str = sb.toString();

  final gptsMatch = RegExp(r'/GPTS\s*\[\s*([\d\s.\-]+)\s*\]').firstMatch(str);
  if (gptsMatch == null) return null;

  final nums = gptsMatch
      .group(1)!
      .trim()
      .split(RegExp(r'\s+'))
      .map(double.tryParse)
      .whereType<double>()
      .toList();

  if (nums.length < 8) return null;

  // GPTS pairs are (lat, lng) for each LPTS corner — grab all lats/lngs.
  final lats = <double>[];
  final lngs = <double>[];
  for (var i = 0; i + 1 < nums.length; i += 2) {
    lats.add(nums[i]);
    lngs.add(nums[i + 1]);
  }

  final south = lats.reduce(min);
  final north = lats.reduce(max);
  final west  = lngs.reduce(min);
  final east  = lngs.reduce(max);

  if (south >= north || west >= east) return null;
  if (south < -90 || north > 90 || west < -180 || east > 180) return null;

  return LatLngBounds(LatLng(south, west), LatLng(north, east));
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

  // Extract geographic bounds from the GeoPDF /GPTS viewport metadata.
  final bounds = parseGeoPdfBounds(pdfBytes);
  if (bounds == null) {
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
  doc.dispose();
  final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
  uiImage.dispose();
  if (byteData == null) throw Exception('Failed to encode PDF as PNG.');
  final pngBytes = byteData.buffer.asUint8List();

  return IncidentOverlay(name: name, imageBytes: pngBytes, bounds: bounds, polygons: const []);
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
