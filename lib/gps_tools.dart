import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';


String _toDMS(double decimal, bool isLat) {
  final dir = isLat ? (decimal >= 0 ? 'N' : 'S') : (decimal >= 0 ? 'E' : 'W');
  final abs = decimal.abs();
  final deg = abs.floor();
  final minRaw = (abs - deg) * 60;
  final min = minRaw.floor();
  final sec = ((minRaw - min) * 60).toStringAsFixed(1);
  return '$deg° $min\' $sec" $dir';
}

String _fmtCoord(double lat, double lon) =>
    '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';

String _fmtDMS(double lat, double lon) =>
    '${_toDMS(lat, true)}  ${_toDMS(lon, false)}';

Future<Position?> _getLocation(BuildContext context) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
    }
    return null;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
      }
      return null;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission permanently denied. Enable in Settings.')),
      );
    }
    return null;
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}


Future<String?> _coordsToW3W(double lat, double lon, String apiKey) async {
  try {
    final uri = Uri.parse(
      'https://api.what3words.com/v3/convert-to-3wa?coordinates=$lat,$lon&language=en&format=json&key=$apiKey',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['words'] as String?;
    }
  } catch (_) {}
  return null;
}


class SavedLocation {
  final String label;
  final double lat;
  final double lon;
  final double? accuracy;
  final String timestamp;

  const SavedLocation({
    required this.label,
    required this.lat,
    required this.lon,
    this.accuracy,
    required this.timestamp,
  });

  String toJson() => json.encode({
        'label': label, 'lat': lat, 'lon': lon,
        'accuracy': accuracy, 'timestamp': timestamp,
      });

  static SavedLocation fromJson(String s) {
    final m = json.decode(s);
    return SavedLocation(
      label: m['label'], lat: m['lat'], lon: m['lon'],
      accuracy: m['accuracy'], timestamp: m['timestamp'],
    );
  }
}


class GpsToolsScreen extends StatefulWidget {
  const GpsToolsScreen({super.key});

  @override
  State<GpsToolsScreen> createState() => _GpsToolsScreenState();
}

class _GpsToolsScreenState extends State<GpsToolsScreen> {
  Position? _position;
  bool _loading = false;
  String? _w3wResult;
  bool _w3wLoading = false;
  String _w3wApiKey = '';
  List<SavedLocation> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _w3wApiKey = prefs.getString('w3w_api_key') ?? '';
      _saved = (prefs.getStringList('saved_locations') ?? [])
          .map(SavedLocation.fromJson)
          .toList();
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('w3w_api_key', _w3wApiKey);
    await prefs.setStringList('saved_locations', _saved.map((s) => s.toJson()).toList());
  }

  Future<void> _capture() async {
    setState(() { _loading = true; _w3wResult = null; });
    final pos = await _getLocation(context);
    setState(() { _position = pos; _loading = false; });
  }

  Future<void> _lookupW3W() async {
    if (_position == null || _w3wApiKey.isEmpty) return;
    setState(() => _w3wLoading = true);
    final words = await _coordsToW3W(_position!.latitude, _position!.longitude, _w3wApiKey);
    setState(() { _w3wResult = words ?? 'Lookup failed (check API key or connection)'; _w3wLoading = false; });
  }

  void _saveLocation() {
    if (_position == null) return;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save Location'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Label (e.g. Patient 1, LZ Alpha)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final label = ctrl.text.trim().isEmpty ? 'Location ${_saved.length + 1}' : ctrl.text.trim();
              final loc = SavedLocation(
                label: label,
                lat: _position!.latitude,
                lon: _position!.longitude,
                accuracy: _position!.accuracy,
                timestamp: DateTime.now().toLocal().toString().substring(0, 16),
              );
              setState(() => _saved.insert(0, loc));
              _savePrefs();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editApiKey() {
    final ctrl = TextEditingController(text: _w3wApiKey);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('What3Words API Key'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your free W3W API key from developer.what3words.com', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'API key', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() => _w3wApiKey = ctrl.text.trim());
              _savePrefs();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Tools'),
        actions: [
          IconButton(icon: const Icon(Icons.vpn_key_outlined), tooltip: 'W3W API Key', onPressed: _editApiKey),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Capture card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.my_location, size: 20),
                  const SizedBox(width: 8),
                  const Text('Current Position', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  if (pos != null)
                    IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Save', onPressed: _saveLocation),
                ]),
                const SizedBox(height: 12),
                if (pos == null && !_loading)
                  const Text('Tap Capture to get current GPS coordinates.', style: TextStyle(color: Colors.grey)),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
                if (pos != null) ...[
                  _coordRow('Decimal', _fmtCoord(pos.latitude, pos.longitude), Icons.content_copy),
                  const SizedBox(height: 6),
                  _coordRow('DMS', _fmtDMS(pos.latitude, pos.longitude), Icons.content_copy),
                  const SizedBox(height: 6),
                  if (pos.accuracy > 0)
                    Text('Accuracy: ±${pos.accuracy.toStringAsFixed(0)} m',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Divider(height: 20),
                  // W3W row
                  Row(children: [
                    Image.asset('assets/w3w_logo.png', width: 20, height: 20,
                        errorBuilder: (_, __, ___) => const Icon(Icons.grid_3x3, size: 20, color: Colors.red)),
                    const SizedBox(width: 8),
                    const Text('What3Words', style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_w3wLoading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    if (!_w3wLoading)
                      TextButton(
                        onPressed: _w3wApiKey.isEmpty ? _editApiKey : _lookupW3W,
                        child: Text(_w3wApiKey.isEmpty ? 'Set API Key' : 'Lookup'),
                      ),
                  ]),
                  if (_w3wResult != null)
                    GestureDetector(
                      onTap: () => _copyToClipboard('///$_w3wResult'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.grid_3x3, size: 16, color: Colors.red),
                          const SizedBox(width: 6),
                          Text('///$_w3wResult', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          const Spacer(),
                          const Icon(Icons.content_copy, size: 14, color: Colors.grey),
                        ]),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _capture,
                    icon: const Icon(Icons.gps_fixed),
                    label: const Text('Capture Location'),
                  ),
                ),
              ]),
            ),
          ),

          if (_saved.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(children: [
              Text('Saved Locations', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Clear all?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        FilledButton(
                          onPressed: () {
                            setState(() => _saved.clear());
                            _savePrefs();
                            Navigator.pop(context);
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Clear all'),
              ),
            ]),
            const SizedBox(height: 8),
            ..._saved.asMap().entries.map((e) => _savedTile(e.key, e.value)),
          ],
        ],
      ),
    );
  }

  Widget _coordRow(String label, String value, IconData icon) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
      Expanded(child: Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
      IconButton(icon: Icon(icon, size: 16), onPressed: () => _copyToClipboard(value), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
    ]);
  }

  Widget _savedTile(int index, SavedLocation loc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(loc.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_fmtCoord(loc.lat, loc.lon), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.content_copy, size: 18),
            onPressed: () => _copyToClipboard('${loc.label}: ${_fmtCoord(loc.lat, loc.lon)}'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () {
              setState(() => _saved.removeAt(index));
              _savePrefs();
            },
          ),
        ]),
      ),
    );
  }
}
