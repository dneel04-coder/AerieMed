import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class LzAssessment {
  final String id;
  final String siteName;
  final String coordinates;
  final String lengthM;
  final String widthM;
  final String surface;
  final String windDirection;
  final String windSpeedKts;
  final String obstacles;
  final String approachPath;
  final String departurePath;
  final String hazards;
  final String rating; // Go / No-Go / Conditional
  final String notes;
  final String timestamp;

  const LzAssessment({
    required this.id,
    required this.siteName,
    required this.coordinates,
    required this.lengthM,
    required this.widthM,
    required this.surface,
    required this.windDirection,
    required this.windSpeedKts,
    required this.obstacles,
    required this.approachPath,
    required this.departurePath,
    required this.hazards,
    required this.rating,
    required this.notes,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id, 'siteName': siteName, 'coordinates': coordinates,
        'lengthM': lengthM, 'widthM': widthM, 'surface': surface,
        'windDirection': windDirection, 'windSpeedKts': windSpeedKts,
        'obstacles': obstacles, 'approachPath': approachPath,
        'departurePath': departurePath, 'hazards': hazards,
        'rating': rating, 'notes': notes, 'timestamp': timestamp,
      };

  factory LzAssessment.fromMap(Map<String, dynamic> m) => LzAssessment(
        id: m['id'] ?? '', siteName: m['siteName'] ?? '',
        coordinates: m['coordinates'] ?? '', lengthM: m['lengthM'] ?? '',
        widthM: m['widthM'] ?? '', surface: m['surface'] ?? '',
        windDirection: m['windDirection'] ?? '', windSpeedKts: m['windSpeedKts'] ?? '',
        obstacles: m['obstacles'] ?? '', approachPath: m['approachPath'] ?? '',
        departurePath: m['departurePath'] ?? '', hazards: m['hazards'] ?? '',
        rating: m['rating'] ?? 'Conditional', notes: m['notes'] ?? '',
        timestamp: m['timestamp'] ?? '',
      );

  String toJson() => json.encode(toMap());
  static LzAssessment fromJson(String s) => LzAssessment.fromMap(json.decode(s));

  Color get ratingColor {
    switch (rating) {
      case 'Go': return Colors.green;
      case 'No-Go': return Colors.red;
      default: return Colors.orange;
    }
  }
}


class LzAssessmentScreen extends StatefulWidget {
  const LzAssessmentScreen({super.key});

  @override
  State<LzAssessmentScreen> createState() => _LzAssessmentScreenState();
}

class _LzAssessmentScreenState extends State<LzAssessmentScreen> {
  List<LzAssessment> _assessments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('lz_assessments') ?? [];
    setState(() => _assessments = list.map(LzAssessment.fromJson).toList());
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('lz_assessments', _assessments.map((a) => a.toJson()).toList());
  }

  void _delete(int index) {
    setState(() => _assessments.removeAt(index));
    _save();
  }

  Future<void> _openForm({LzAssessment? existing}) async {
    final result = await Navigator.push<LzAssessment>(
      context,
      MaterialPageRoute(builder: (_) => _LzFormScreen(existing: existing)),
    );
    if (result != null) {
      setState(() {
        final idx = _assessments.indexWhere((a) => a.id == result.id);
        if (idx >= 0) {
          _assessments[idx] = result;
        } else {
          _assessments.insert(0, result);
        }
      });
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LZ Assessment')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New LZ'),
      ),
      body: _assessments.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.flight_land, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                const Text('No LZ assessments yet.\nTap + to add one.', textAlign: TextAlign.center),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: _assessments.length,
              itemBuilder: (context, index) {
                final lz = _assessments[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: lz.ratingColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: lz.ratingColor, width: 2),
                      ),
                      child: Center(
                        child: Text(lz.rating == 'Conditional' ? 'COND' : lz.rating,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: lz.ratingColor)),
                      ),
                    ),
                    title: Text(lz.siteName.isEmpty ? 'Unnamed LZ' : lz.siteName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (lz.coordinates.isNotEmpty) Text(lz.coordinates, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      Text('${lz.lengthM}×${lz.widthM} m  •  ${lz.surface}  •  ${lz.timestamp}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _openForm(existing: lz)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete LZ?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                              FilledButton(onPressed: () { Navigator.pop(context); _delete(index); }, child: const Text('Delete')),
                            ],
                          ),
                        ),
                      ),
                    ]),
                    onTap: () => _openForm(existing: lz),
                  ),
                );
              },
            ),
    );
  }
}


class _LzFormScreen extends StatefulWidget {
  final LzAssessment? existing;
  const _LzFormScreen({this.existing});

  @override
  State<_LzFormScreen> createState() => _LzFormScreenState();
}

class _LzFormScreenState extends State<_LzFormScreen> {
  late final TextEditingController _siteName, _coords, _length, _width,
      _surface, _windDir, _windSpeed, _obstacles, _approach, _departure,
      _hazards, _notes;
  String _rating = 'Conditional';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _siteName = TextEditingController(text: e?.siteName ?? '');
    _coords = TextEditingController(text: e?.coordinates ?? '');
    _length = TextEditingController(text: e?.lengthM ?? '');
    _width = TextEditingController(text: e?.widthM ?? '');
    _surface = TextEditingController(text: e?.surface ?? '');
    _windDir = TextEditingController(text: e?.windDirection ?? '');
    _windSpeed = TextEditingController(text: e?.windSpeedKts ?? '');
    _obstacles = TextEditingController(text: e?.obstacles ?? '');
    _approach = TextEditingController(text: e?.approachPath ?? '');
    _departure = TextEditingController(text: e?.departurePath ?? '');
    _hazards = TextEditingController(text: e?.hazards ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _rating = e?.rating ?? 'Conditional';
  }

  @override
  void dispose() {
    for (final c in [_siteName, _coords, _length, _width, _surface, _windDir,
        _windSpeed, _obstacles, _approach, _departure, _hazards, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final result = LzAssessment(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      siteName: _siteName.text.trim(),
      coordinates: _coords.text.trim(),
      lengthM: _length.text.trim(),
      widthM: _width.text.trim(),
      surface: _surface.text.trim(),
      windDirection: _windDir.text.trim(),
      windSpeedKts: _windSpeed.text.trim(),
      obstacles: _obstacles.text.trim(),
      approachPath: _approach.text.trim(),
      departurePath: _departure.text.trim(),
      hazards: _hazards.text.trim(),
      rating: _rating,
      notes: _notes.text.trim(),
      timestamp: DateTime.now().toLocal().toString().substring(0, 16),
    );
    Navigator.pop(context, result);
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New LZ Assessment' : 'Edit LZ'),
        actions: [
          TextButton(onPressed: _submit, child: const Text('Save')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _section('Site Information'),
          _field('Site Name / Callsign', _siteName, hint: 'e.g. LZ Alpha'),
          _field('Coordinates', _coords, hint: '37.7749, -122.4194'),
          _section('Dimensions & Surface'),
          Row(children: [
            Expanded(child: _field('Length (m)', _length, hint: '60')),
            const SizedBox(width: 12),
            Expanded(child: _field('Width (m)', _width, hint: '30')),
          ]),
          _field('Surface Type', _surface, hint: 'e.g. Flat grass, Gravel, Slope'),
          _section('Wind'),
          Row(children: [
            Expanded(child: _field('Wind Direction', _windDir, hint: 'e.g. 270° (W)')),
            const SizedBox(width: 12),
            Expanded(child: _field('Wind Speed (kts)', _windSpeed, hint: 'e.g. 10')),
          ]),
          _section('Hazards & Paths'),
          _field('Obstacles', _obstacles, maxLines: 2, hint: 'Trees, power lines, fences…'),
          _field('Approach Path', _approach, hint: 'e.g. From the south, over the ridge'),
          _field('Departure Path', _departure, hint: 'e.g. Straight north, climbing 500 ft'),
          _field('Other Hazards', _hazards, maxLines: 2),
          _section('Overall Rating'),
          Row(children: [
            for (final r in ['Go', 'Conditional', 'No-Go'])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: r == 'No-Go' ? 0 : 8),
                  child: ChoiceChip(
                    label: Text(r),
                    selected: _rating == r,
                    onSelected: (_) => setState(() => _rating = r),
                    selectedColor: r == 'Go'
                        ? Colors.green.withValues(alpha: 0.3)
                        : r == 'No-Go'
                            ? Colors.red.withValues(alpha: 0.3)
                            : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          _field('Additional Notes', _notes, maxLines: 3),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text('Save Assessment'),
            ),
          ),
        ]),
      ),
    );
  }
}
