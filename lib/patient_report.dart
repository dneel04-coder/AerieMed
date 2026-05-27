import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'report_transfer.dart';

// ── VitalSet ──────────────────────────────────────────────────────────────────

class VitalSet {
  final String id;
  final DateTime timestamp;
  final String avpu;
  final String gcs;
  final String bp;
  final String hr;
  final String rr;
  final String spo2;
  final String temp;
  final String glucose;
  final String pain;
  final String pupils;
  final String skin;

  const VitalSet({
    required this.id,
    required this.timestamp,
    this.avpu = '',
    this.gcs = '',
    this.bp = '',
    this.hr = '',
    this.rr = '',
    this.spo2 = '',
    this.temp = '',
    this.glucose = '',
    this.pain = '',
    this.pupils = '',
    this.skin = '',
  });

  factory VitalSet.now() => VitalSet(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
      );

  static String _z(int n) => n.toString().padLeft(2, '0');
  String get timeLabel {
    final t = timestamp.toLocal();
    return '${_z(t.hour)}:${_z(t.minute)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'avpu': avpu, 'gcs': gcs, 'bp': bp, 'hr': hr, 'rr': rr,
        'spo2': spo2, 'temp': temp, 'glucose': glucose,
        'pain': pain, 'pupils': pupils, 'skin': skin,
      };

  factory VitalSet.fromJson(Map<String, dynamic> j) => VitalSet(
        id: j['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
        avpu: j['avpu'] as String? ?? '',
        gcs: j['gcs'] as String? ?? '',
        bp: j['bp'] as String? ?? '',
        hr: j['hr'] as String? ?? '',
        rr: j['rr'] as String? ?? '',
        spo2: j['spo2'] as String? ?? '',
        temp: j['temp'] as String? ?? '',
        glucose: j['glucose'] as String? ?? '',
        pain: j['pain'] as String? ?? '',
        pupils: j['pupils'] as String? ?? '',
        skin: j['skin'] as String? ?? '',
      );

  VitalSet copyWith({
    String? avpu, String? gcs, String? bp, String? hr, String? rr,
    String? spo2, String? temp, String? glucose, String? pain,
    String? pupils, String? skin,
  }) =>
      VitalSet(
        id: id, timestamp: timestamp,
        avpu: avpu ?? this.avpu, gcs: gcs ?? this.gcs,
        bp: bp ?? this.bp, hr: hr ?? this.hr, rr: rr ?? this.rr,
        spo2: spo2 ?? this.spo2, temp: temp ?? this.temp,
        glucose: glucose ?? this.glucose, pain: pain ?? this.pain,
        pupils: pupils ?? this.pupils, skin: skin ?? this.skin,
      );
}

// ── BodyMarker ────────────────────────────────────────────────────────────────

class BodyMarker {
  final double x;
  final double y;
  final String label;
  final String side; // 'front' | 'back'

  const BodyMarker({
    required this.x,
    required this.y,
    required this.label,
    this.side = 'front',
  });

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'label': label, 'side': side};

  factory BodyMarker.fromJson(Map<String, dynamic> j) => BodyMarker(
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        label: j['label'] as String? ?? '',
        side: j['side'] as String? ?? 'front',
      );
}

// ── PatientReport ─────────────────────────────────────────────────────────────

class PatientReport {
  final String id;
  final DateTime createdAt;
  // Form type
  String formType; // 'MIST' | 'SOAP' | 'Pediatric'
  // Patient info
  String provider, unit, patientId, age, sex, weight, chiefComplaint, allergies;
  // Mechanism
  String mechanism;
  // Serial vitals
  List<VitalSet> vitalSets;
  // Injuries/findings
  String injuries;
  // SOAP sections
  String subjective, objective, assessment, plan;
  // Treatments & disposition
  String treatments, disposition, notes;
  // Body diagram
  List<BodyMarker> bodyMarkers;
  // Photos (file paths)
  List<String> photoPaths;
  // Pediatric extras
  String broselowColor;
  // Sync state
  bool isSynced;

  PatientReport({
    required this.id,
    required this.createdAt,
    this.formType = 'MIST',
    this.provider = '',
    this.unit = '',
    this.patientId = '',
    this.age = '',
    this.sex = '',
    this.weight = '',
    this.chiefComplaint = '',
    this.allergies = '',
    this.mechanism = '',
    List<VitalSet>? vitalSets,
    this.injuries = '',
    this.subjective = '',
    this.objective = '',
    this.assessment = '',
    this.plan = '',
    this.treatments = '',
    this.disposition = '',
    this.notes = '',
    List<BodyMarker>? bodyMarkers,
    List<String>? photoPaths,
    this.broselowColor = '',
    this.isSynced = false,
  })  : vitalSets = vitalSets ?? [],
        bodyMarkers = bodyMarkers ?? [],
        photoPaths = photoPaths ?? [];

  factory PatientReport.fresh() => PatientReport(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
      );

  static String _z(int n) => n.toString().padLeft(2, '0');
  static String _v(String s, [String f = '----']) => s.isEmpty ? f : s;

  String get timestampDisplay {
    return '${createdAt.year}-${_z(createdAt.month)}-${_z(createdAt.day)} '
        '${_z(createdAt.hour)}${_z(createdAt.minute)}Z';
  }

  // Formatted export text
  String get formattedText {
    final dt = '${createdAt.year}-${_z(createdAt.month)}-${_z(createdAt.day)} '
        '${_z(createdAt.hour)}:${_z(createdAt.minute)}:${_z(createdAt.second)}Z';
    final lines = <String>[
      '==========================================',
      '   PATIENT CARE REPORT  [$formType]',
      '==========================================',
      'REPORT #  : $id',
      'DATE/TIME : $dt',
      'PROVIDER  : ${_v(provider)}',
      'UNIT/AGCY : ${_v(unit)}',
      '------------------------------------------',
      'PT ID/NAME: ${_v(patientId)}',
      'AGE       : ${_v(age, '--')}   SEX: ${_v(sex, '--')}',
      if (weight.isNotEmpty) 'WEIGHT    : $weight',
      'COMPLAINT : ${_v(chiefComplaint)}',
      'ALLERGIES : ${_v(allergies, 'NKDA')}',
      '------------------------------------------',
      '[M] MECHANISM',
      _v(mechanism, '(not documented)'),
    ];

    if (formType == 'SOAP') {
      lines.addAll([
        '------------------------------------------',
        '[S] SUBJECTIVE',
        _v(subjective, '(not documented)'),
        '------------------------------------------',
        '[O] OBJECTIVE',
        _v(objective, '(not documented)'),
        '------------------------------------------',
        '[A] ASSESSMENT',
        _v(assessment, '(not documented)'),
        '------------------------------------------',
        '[P] PLAN',
        _v(plan, '(not documented)'),
      ]);
    } else {
      lines.addAll([
        '------------------------------------------',
        '[I] INJURIES / SIGNS & SYMPTOMS',
        _v(injuries, '(not documented)'),
      ]);
    }

    // Vitals
    lines.add('------------------------------------------');
    lines.add('[S] VITAL SIGNS');
    if (vitalSets.isEmpty) {
      lines.add('(no vitals recorded)');
    } else {
      for (final vs in vitalSets) {
        lines.add('TIME: ${vs.timeLabel}  AVPU: ${_v(vs.avpu, '--')}  GCS: ${_v(vs.gcs, '--')}');
        lines.add('BP: ${_v(vs.bp, '--/--')}  HR: ${_v(vs.hr, '--')}  RR: ${_v(vs.rr, '--')}');
        lines.add('SpO2: ${_v(vs.spo2, '--')}%  TEMP: ${_v(vs.temp, '--')}  BGL: ${_v(vs.glucose, '--')}');
        lines.add('PUPILS: ${_v(vs.pupils, '--')}  SKIN: ${_v(vs.skin, '--')}  PAIN: ${_v(vs.pain, '--')}/10');
        lines.add('- - -');
      }
    }

    lines.addAll([
      '------------------------------------------',
      '[T] TREATMENTS',
      _v(treatments, '(not documented)'),
      '------------------------------------------',
      'DISPOSITION: ${_v(disposition)}',
    ]);

    if (bodyMarkers.isNotEmpty) {
      lines.add('------------------------------------------');
      lines.add('INJURY LOCATIONS (body diagram)');
      for (final m in bodyMarkers) {
        lines.add('  • ${m.label} [${m.side}]');
      }
    }

    if (photoPaths.isNotEmpty) {
      lines.add('${photoPaths.length} photo(s) attached');
    }

    if (notes.isNotEmpty) {
      lines.addAll(['------------------------------------------', 'NOTES', notes]);
    }
    lines.add('==========================================');
    return lines.join('\n');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'formType': formType,
        'provider': provider, 'unit': unit,
        'patientId': patientId, 'age': age, 'sex': sex, 'weight': weight,
        'chiefComplaint': chiefComplaint, 'allergies': allergies,
        'mechanism': mechanism,
        'vitalSets': vitalSets.map((v) => v.toJson()).toList(),
        'injuries': injuries,
        'subjective': subjective, 'objective': objective,
        'assessment': assessment, 'plan': plan,
        'treatments': treatments, 'disposition': disposition, 'notes': notes,
        'bodyMarkers': bodyMarkers.map((m) => m.toJson()).toList(),
        'photoPaths': photoPaths,
        'broselowColor': broselowColor,
        'isSynced': isSynced,
      };

  factory PatientReport.fromJson(Map<String, dynamic> j) {
    // Handle legacy reports that stored vitals as flat fields
    List<VitalSet> vitals = [];
    if (j['vitalSets'] != null) {
      vitals = (j['vitalSets'] as List)
          .map((e) => VitalSet.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Migrate legacy flat vitals into a single VitalSet
      final legacy = VitalSet(
        id: '${j['id']}_v0',
        timestamp: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        avpu: j['avpu'] as String? ?? '',
        gcs: j['gcs'] as String? ?? '',
        bp: j['bp'] as String? ?? '',
        hr: j['hr'] as String? ?? '',
        rr: j['rr'] as String? ?? '',
        spo2: j['spo2'] as String? ?? '',
        temp: j['temp'] as String? ?? '',
        glucose: j['glucose'] as String? ?? '',
        pain: j['pain'] as String? ?? '',
        pupils: j['pupils'] as String? ?? '',
        skin: j['skin'] as String? ?? '',
      );
      // Only add it if it has any data
      final hasData = [legacy.avpu, legacy.gcs, legacy.bp, legacy.hr,
          legacy.rr, legacy.spo2, legacy.temp].any((s) => s.isNotEmpty);
      if (hasData) vitals = [legacy];
    }
    return PatientReport(
      id: j['id'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      formType: j['formType'] as String? ?? 'MIST',
      provider: j['provider'] as String? ?? '',
      unit: j['unit'] as String? ?? '',
      patientId: j['patientId'] as String? ?? '',
      age: j['age'] as String? ?? '',
      sex: j['sex'] as String? ?? '',
      weight: j['weight'] as String? ?? '',
      chiefComplaint: j['chiefComplaint'] as String? ?? '',
      allergies: j['allergies'] as String? ?? '',
      mechanism: j['mechanism'] as String? ?? '',
      vitalSets: vitals,
      injuries: j['injuries'] as String? ?? '',
      subjective: j['subjective'] as String? ?? '',
      objective: j['objective'] as String? ?? '',
      assessment: j['assessment'] as String? ?? '',
      plan: j['plan'] as String? ?? '',
      treatments: j['treatments'] as String? ?? '',
      disposition: j['disposition'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      bodyMarkers: (j['bodyMarkers'] as List? ?? [])
          .map((e) => BodyMarker.fromJson(e as Map<String, dynamic>))
          .toList(),
      photoPaths: (j['photoPaths'] as List? ?? []).cast<String>(),
      broselowColor: j['broselowColor'] as String? ?? '',
      isSynced: j['isSynced'] as bool? ?? false,
    );
  }
}

// ── Storage ───────────────────────────────────────────────────────────────────

class ReportStorage {
  static const _key = 'patient_reports_v1';

  static Future<List<PatientReport>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? [])
        .map((e) {
          try {
            return PatientReport.fromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<PatientReport>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> save(PatientReport r) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == r.id);
    list.insert(0, r);
    await prefs.setStringList(_key, list.map((x) => jsonEncode(x.toJson())).toList());
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == id);
    await prefs.setStringList(_key, list.map((x) => jsonEncode(x.toJson())).toList());
  }
}

// ── Report syncer (auto-send to Supabase when available) ─────────────────────

class ReportSyncer {
  static const _urlKey = 'tac_supabase_url';
  static const _anonKey = 'tac_supabase_anon_key';
  static const _userIdKey = 'tac_user_id';
  static const _callsignKey = 'tac_callsign';

  static Future<void> trySyncReport(PatientReport report) async {
    if (report.isSynced) return;
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlKey) ?? '';
    final key = prefs.getString(_anonKey) ?? '';
    if (url.isEmpty || key.isEmpty) return;

    SupabaseClient client;
    try {
      await Supabase.initialize(url: url, anonKey: key);
      client = Supabase.instance.client;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('already') || msg.contains('initialized')) {
        client = Supabase.instance.client;
      } else {
        return;
      }
    }

    try {
      final userId = prefs.getString(_userIdKey) ?? 'unknown';
      final callsign = prefs.getString(_callsignKey) ?? 'Unknown';
      await client.from('patient_reports').upsert({
        'id': report.id,
        'user_id': userId,
        'callsign': callsign,
        'report_data': report.toJson(),
        'submitted_at': DateTime.now().toIso8601String(),
      });
      report.isSynced = true;
      await ReportStorage.save(report);
    } catch (_) {}
  }

  static Future<void> syncPending() async {
    final reports = await ReportStorage.load();
    for (final r in reports.where((r) => !r.isSynced)) {
      await trySyncReport(r);
    }
  }
}

// ── Share helper ──────────────────────────────────────────────────────────────

void _shareReport(PatientReport r) {
  SharePlus.instance.share(ShareParams(
    text: r.formattedText,
    subject: 'PCR - ${r.patientId.isEmpty ? r.id : r.patientId}',
  ));
}

// ── List Screen ───────────────────────────────────────────────────────────────

class PatientReportListScreen extends StatefulWidget {
  const PatientReportListScreen({super.key});

  @override
  State<PatientReportListScreen> createState() => _PatientReportListScreenState();
}

class _PatientReportListScreenState extends State<PatientReportListScreen> {
  List<PatientReport> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    ReportSyncer.syncPending();
    final r = await ReportStorage.load();
    if (mounted) setState(() { _reports = r; _loading = false; });
  }

  Future<void> _confirmDelete(PatientReport r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Report?'),
        content: Text('Delete report for "${r.patientId.isEmpty ? 'Unknown Patient' : r.patientId}"?\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) { await ReportStorage.delete(r.id); _refresh(); }
  }

  Future<void> _newReport(String type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatientReportFormScreen(formType: type)),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Import Encrypted Report',
            onPressed: () => importEncryptedBundle(context, onImported: _refresh),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New Report',
            onSelected: _newReport,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'MIST', child: ListTile(leading: Icon(Icons.assignment), title: Text('MIST Report'))),
              PopupMenuItem(value: 'SOAP', child: ListTile(leading: Icon(Icons.medical_services), title: Text('SOAP Note'))),
              PopupMenuItem(value: 'Pediatric', child: ListTile(leading: Icon(Icons.child_care), title: Text('Pediatric Report'))),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.assignment_outlined, size: 72, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('No reports on file', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    Text('Tap + to create a report', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                  ]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _buildTile(_reports[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
        onPressed: () => _newReport('MIST'),
      ),
    );
  }

  Widget _buildTile(PatientReport r) {
    final cs = Theme.of(context).colorScheme;
    final typeColor = r.formType == 'SOAP'
        ? Colors.teal
        : r.formType == 'Pediatric'
            ? Colors.orange
            : cs.primary;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withValues(alpha: 0.15),
          child: Text(r.formType == 'Pediatric' ? 'PED' : r.formType,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor)),
        ),
        title: Text(r.patientId.isEmpty ? 'Unknown Patient' : r.patientId,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r.chiefComplaint.isNotEmpty)
            Text(r.chiefComplaint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          Row(children: [
            Text(r.timestampDisplay, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            if (r.vitalSets.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.monitor_heart, size: 12, color: Colors.grey[400]),
              Text(' ${r.vitalSets.length} vitals', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
            if (r.photoPaths.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.photo, size: 12, color: Colors.grey[400]),
              Text(' ${r.photoPaths.length}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ]),
        ]),
        isThreeLine: r.chiefComplaint.isNotEmpty,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (r.isSynced)
            const Tooltip(
              message: 'Sent to admin',
              child: Padding(
                padding: EdgeInsets.only(right: 2),
                child: Icon(Icons.cloud_done, color: Colors.green, size: 16),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.send_outlined),
            tooltip: 'Send / Export',
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (_) => TransferOptionsSheet(report: r),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red[400]),
            onPressed: () => _confirmDelete(r),
          ),
        ]),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PatientReportFormScreen(existing: r)),
          );
          _refresh();
        },
      ),
    );
  }
}

// ── Form Screen ───────────────────────────────────────────────────────────────

class PatientReportFormScreen extends StatefulWidget {
  final PatientReport? existing;
  final String formType;
  const PatientReportFormScreen({super.key, this.existing, this.formType = 'MIST'});

  @override
  State<PatientReportFormScreen> createState() => _PatientReportFormScreenState();
}

class _PatientReportFormScreenState extends State<PatientReportFormScreen>
    with SingleTickerProviderStateMixin {
  late PatientReport _draft;
  late TabController _tabs;

  // Controllers
  final _provider = TextEditingController();
  final _unit = TextEditingController();
  final _patientId = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _chiefComplaint = TextEditingController();
  final _allergies = TextEditingController();
  final _mechanism = TextEditingController();
  final _injuries = TextEditingController();
  final _subjective = TextEditingController();
  final _objective = TextEditingController();
  final _assessmentCtrl = TextEditingController();
  final _planCtrl = TextEditingController();
  final _treatments = TextEditingController();
  final _notes = TextEditingController();

  String? _sex, _disposition;
  String _formType = 'MIST';
  List<VitalSet> _vitalSets = [];
  List<BodyMarker> _bodyMarkers = [];
  List<String> _photoPaths = [];
  String _broselowColor = '';

  // Speech
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;
  TextEditingController? _activeListenCtrl;

  // Image picker
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    final e = widget.existing;
    _draft = e ?? PatientReport.fresh();
    _formType = e?.formType ?? widget.formType;
    if (e != null) {
      _provider.text = e.provider;
      _unit.text = e.unit;
      _patientId.text = e.patientId;
      _age.text = e.age;
      _weight.text = e.weight;
      _chiefComplaint.text = e.chiefComplaint;
      _allergies.text = e.allergies;
      _mechanism.text = e.mechanism;
      _injuries.text = e.injuries;
      _subjective.text = e.subjective;
      _objective.text = e.objective;
      _assessmentCtrl.text = e.assessment;
      _planCtrl.text = e.plan;
      _treatments.text = e.treatments;
      _notes.text = e.notes;
      _sex = e.sex.isEmpty ? null : e.sex;
      _disposition = e.disposition.isEmpty ? null : e.disposition;
      _vitalSets = List.from(e.vitalSets);
      _bodyMarkers = List.from(e.bodyMarkers);
      _photoPaths = List.from(e.photoPaths);
      _broselowColor = e.broselowColor;
    }
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(onError: (_) {});
    if (mounted) setState(() => _speechAvailable = available);
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _provider, _unit, _patientId, _age, _weight, _chiefComplaint,
      _allergies, _mechanism, _injuries, _subjective, _objective,
      _assessmentCtrl, _planCtrl, _treatments, _notes,
    ]) { c.dispose(); }
    _speech.cancel();
    super.dispose();
  }

  PatientReport _compile() {
    _draft.formType = _formType;
    _draft.provider = _provider.text.trim();
    _draft.unit = _unit.text.trim();
    _draft.patientId = _patientId.text.trim();
    _draft.age = _age.text.trim();
    _draft.sex = _sex ?? '';
    _draft.weight = _weight.text.trim();
    _draft.chiefComplaint = _chiefComplaint.text.trim();
    _draft.allergies = _allergies.text.trim();
    _draft.mechanism = _mechanism.text.trim();
    _draft.injuries = _injuries.text.trim();
    _draft.subjective = _subjective.text.trim();
    _draft.objective = _objective.text.trim();
    _draft.assessment = _assessmentCtrl.text.trim();
    _draft.plan = _planCtrl.text.trim();
    _draft.treatments = _treatments.text.trim();
    _draft.disposition = _disposition ?? '';
    _draft.notes = _notes.text.trim();
    _draft.vitalSets = List.from(_vitalSets);
    _draft.bodyMarkers = List.from(_bodyMarkers);
    _draft.photoPaths = List.from(_photoPaths);
    _draft.broselowColor = _broselowColor;
    return _draft;
  }

  Future<void> _save({bool silent = false}) async {
    final compiled = _compile();
    await ReportStorage.save(compiled);
    ReportSyncer.trySyncReport(compiled);
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report saved'), duration: Duration(seconds: 2)),
      );
    }
  }

  // ── Voice ─────────────────────────────────────────────────────────────────

  void _toggleListen(TextEditingController ctrl) {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available on this device.')),
      );
      return;
    }
    if (_listening) {
      _speech.stop();
      setState(() { _listening = false; _activeListenCtrl = null; });
    } else {
      _activeListenCtrl = ctrl;
      setState(() => _listening = true);
      _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          if (r.finalResult) {
            final text = r.recognizedWords.trim();
            if (text.isNotEmpty) {
              final existing = ctrl.text;
              ctrl.text = existing.isEmpty ? text : '$existing $text';
              ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
            }
            setState(() { _listening = false; _activeListenCtrl = null; });
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ── Photos ────────────────────────────────────────────────────────────────

  Future<void> _addPhoto(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory('${dir.path}/report_photos');
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final dest = '${destDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(file.path).copy(dest);
    setState(() => _photoPaths.add(dest));
    _save(silent: true);
  }

  void _removePhoto(int index) {
    setState(() => _photoPaths.removeAt(index));
    _save(silent: true);
  }

  // ── Vitals ────────────────────────────────────────────────────────────────

  void _addVitals() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VitalsEntrySheet(
        onSave: (vs) {
          setState(() => _vitalSets.add(vs));
          _save(silent: true);
        },
      ),
    );
  }

  void _editVitals(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VitalsEntrySheet(
        existing: _vitalSets[index],
        onSave: (vs) {
          setState(() => _vitalSets[index] = vs);
          _save(silent: true);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isNew ? 'New $_formType Report' : _patientId.text.isEmpty ? 'Edit Report' : _patientId.text),
            Text(_draft.timestampDisplay,
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ],
        ),
        actions: [
          if (_listening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.mic, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text('Listening…', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
              ]),
            ),
          IconButton(
            icon: const Icon(Icons.send_outlined),
            tooltip: 'Send / Export',
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (_) => TransferOptionsSheet(report: _compile()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
              onPressed: _save,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Patient'),
            Tab(icon: Icon(Icons.monitor_heart_outlined, size: 20), text: 'Vitals'),
            Tab(icon: Icon(Icons.accessibility_new, size: 20), text: 'Body'),
            Tab(icon: Icon(Icons.notes, size: 20), text: 'Notes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPatientTab(),
          _buildVitalsTab(),
          _buildBodyTab(),
          _buildNotesTab(),
        ],
      ),
    );
  }

  // ── Tab: Patient ──────────────────────────────────────────────────────────

  Widget _buildPatientTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Form type
        _sectionLabel('FORM TYPE'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'MIST', label: Text('MIST'), icon: Icon(Icons.assignment)),
            ButtonSegment(value: 'SOAP', label: Text('SOAP'), icon: Icon(Icons.medical_services)),
            ButtonSegment(value: 'Pediatric', label: Text('Pediatric'), icon: Icon(Icons.child_care)),
          ],
          selected: {_formType},
          onSelectionChanged: (s) => setState(() => _formType = s.first),
        ),
        const SizedBox(height: 16),

        _card('Provider', Colors.indigo, [
          Row(children: [
            Expanded(child: _tf('Provider Name', _provider)),
            const SizedBox(width: 8),
            Expanded(child: _tf('Unit / Agency', _unit)),
          ]),
        ]),

        _card('Patient Information', Colors.teal, [
          _tf('Patient ID / Name', _patientId),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 72, child: _tf('Age', _age)),
            const SizedBox(width: 8),
            if (_formType == 'Pediatric') ...[
              SizedBox(width: 90, child: _tf('Weight (kg)', _weight)),
              const SizedBox(width: 8),
            ],
            Expanded(child: _dd('Sex', _sex, ['Male', 'Female', 'Unknown'], (v) => setState(() => _sex = v))),
          ]),
          const SizedBox(height: 8),
          _tf('Chief Complaint', _chiefComplaint),
          const SizedBox(height: 8),
          _tf('Allergies (NKDA if none)', _allergies),
          if (_formType == 'Pediatric' && _weight.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _broselowRow(),
          ],
        ]),

        _card('Mechanism of Injury / Illness', Colors.orange, [
          _voiceTf('Describe how injury or illness occurred', _mechanism, maxLines: 3),
        ]),

        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _broselowRow() {
    final kg = double.tryParse(_weight.text);
    if (kg == null) return const SizedBox.shrink();
    final color = _broselowFromKg(kg);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _broselowColor.isNotEmpty
            ? _parseBroselowColor(_broselowColor).withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _parseBroselowColor(color)),
      ),
      child: Row(children: [
        Container(width: 24, height: 24, decoration: BoxDecoration(color: _parseBroselowColor(color), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Broselow: $color', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(_broselowWeightRange(kg), style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ]),
    );
  }

  // ── Tab: Vitals ───────────────────────────────────────────────────────────

  Widget _buildVitalsTab() {
    return Column(
      children: [
        // Auto-timestamp header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(children: [
            const Icon(Icons.schedule, size: 16),
            const SizedBox(width: 6),
            const Text('All entries auto-timestamped', style: TextStyle(fontSize: 12)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _addVitals,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Vitals'),
            ),
          ]),
        ),
        Expanded(
          child: _vitalSets.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.monitor_heart_outlined, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text('No vitals recorded yet', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addVitals,
                      icon: const Icon(Icons.add),
                      label: const Text('Record First Vitals'),
                    ),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  children: [
                    // Trend table (shown when 2+ sets)
                    if (_vitalSets.length >= 2) _buildTrendTable(),
                    const SizedBox(height: 8),
                    // Individual vital sets
                    ..._vitalSets.asMap().entries.map((e) => _buildVitalTile(e.key, e.value)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildVitalTile(int index, VitalSet vs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(vs.timeLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
          ]),
        ),
        title: Row(children: [
          if (vs.hr.isNotEmpty) _vitalChip('HR', vs.hr, Colors.red),
          if (vs.spo2.isNotEmpty) _vitalChip('SpO2', '${vs.spo2}%', Colors.blue),
          if (vs.bp.isNotEmpty) _vitalChip('BP', vs.bp, Colors.purple),
        ]),
        subtitle: vs.avpu.isNotEmpty ? Text('AVPU: ${vs.avpu}', style: const TextStyle(fontSize: 11)) : null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editVitals(index)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () { setState(() => _vitalSets.removeAt(index)); _save(silent: true); },
          ),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(spacing: 12, runSpacing: 6, children: [
              if (vs.gcs.isNotEmpty) _vitalDetail('GCS', vs.gcs),
              if (vs.bp.isNotEmpty) _vitalDetail('BP', vs.bp),
              if (vs.hr.isNotEmpty) _vitalDetail('HR', '${vs.hr} bpm'),
              if (vs.rr.isNotEmpty) _vitalDetail('RR', '${vs.rr}/min'),
              if (vs.spo2.isNotEmpty) _vitalDetail('SpO2', '${vs.spo2}%'),
              if (vs.temp.isNotEmpty) _vitalDetail('Temp', vs.temp),
              if (vs.glucose.isNotEmpty) _vitalDetail('BGL', '${vs.glucose} mg/dL'),
              if (vs.pain.isNotEmpty) _vitalDetail('Pain', '${vs.pain}/10'),
              if (vs.pupils.isNotEmpty) _vitalDetail('Pupils', vs.pupils),
              if (vs.skin.isNotEmpty) _vitalDetail('Skin', vs.skin),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendTable() {
    final headers = ['Time', 'BP', 'HR', 'RR', 'SpO2', 'GCS', 'Pain'];
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('VITALS TREND', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowHeight: 28,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 32,
              columns: headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))).toList(),
              rows: _vitalSets.asMap().entries.map((e) {
                final i = e.key;
                final vs = e.value;
                final prev = i > 0 ? _vitalSets[i - 1] : null;
                return DataRow(cells: [
                  DataCell(Text(vs.timeLabel, style: const TextStyle(fontSize: 12))),
                  DataCell(_trendCell(vs.bp, prev?.bp)),
                  DataCell(_trendCell(vs.hr, prev?.hr)),
                  DataCell(_trendCell(vs.rr, prev?.rr)),
                  DataCell(_trendCell(vs.spo2, prev?.spo2)),
                  DataCell(_trendCell(vs.gcs, prev?.gcs)),
                  DataCell(_trendCell(vs.pain, prev?.pain)),
                ]);
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _trendCell(String curr, String? prev) {
    if (curr.isEmpty) return const Text('—', style: TextStyle(fontSize: 12, color: Colors.grey));
    final indicator = _trendArrow(prev, curr);
    final color = indicator == '↑' ? Colors.green : indicator == '↓' ? Colors.red : null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(curr, style: const TextStyle(fontSize: 12)),
      if (indicator.isNotEmpty)
        Text(indicator, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    ]);
  }

  String _trendArrow(String? prev, String curr) {
    if (prev == null || prev.isEmpty) return '';
    final p = double.tryParse(prev.replaceAll(RegExp(r'[^0-9.]'), ''));
    final c = double.tryParse(curr.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (p == null || c == null) return '';
    if (c > p * 1.1) return '↑';
    if (c < p * 0.9) return '↓';
    return '';
  }

  // ── Tab: Body ─────────────────────────────────────────────────────────────

  Widget _buildBodyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionLabel('INJURY / BODY DIAGRAM'),
        const SizedBox(height: 4),
        const Text('Tap on the figure to mark an injury location.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        BodyDiagramWidget(
          markers: _bodyMarkers,
          onMarkersChanged: (markers) {
            setState(() => _bodyMarkers = markers);
            _save(silent: true);
          },
        ),
        const SizedBox(height: 20),
        // Photos
        Row(children: [
          _sectionLabel('PHOTOS'),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('Camera'),
            onPressed: () => _addPhoto(ImageSource.camera),
          ),
          TextButton.icon(
            icon: const Icon(Icons.photo_library, size: 16),
            label: const Text('Library'),
            onPressed: () => _addPhoto(ImageSource.gallery),
          ),
        ]),
        if (_photoPaths.isEmpty)
          Container(
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Text('No photos attached', style: TextStyle(color: Colors.grey))),
          )
        else
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoPaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_photoPaths[i]), width: 100, height: 100, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2, right: 2,
                    child: GestureDetector(
                      onTap: () => _removePhoto(i),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 80),
      ]),
    );
  }

  // ── Tab: Notes ────────────────────────────────────────────────────────────

  Widget _buildNotesTab() {
    final isMIST = _formType != 'SOAP';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (isMIST) ...[
          _card('[I]  Injuries / Signs & Symptoms', Colors.red, [
            _voiceTf('Document all injuries, complaints, and findings', _injuries, maxLines: 4),
          ]),
        ] else ...[
          _card('[S]  Subjective', Colors.indigo, [
            _voiceTf('History of present illness, symptoms, patient\'s own words', _subjective, maxLines: 3),
          ]),
          _card('[O]  Objective', Colors.teal, [
            _voiceTf('Physical exam findings, objective measurements', _objective, maxLines: 3),
          ]),
          _card('[A]  Assessment', Colors.orange, [
            _voiceTf('Clinical impression / differential diagnosis', _assessmentCtrl, maxLines: 3),
          ]),
          _card('[P]  Plan', Colors.purple, [
            _voiceTf('Treatment plan, interventions, next steps', _planCtrl, maxLines: 3),
          ]),
        ],

        _card('[T]  Treatments Administered', Colors.green, [
          _voiceTf('Document all treatments, medications, doses, and times', _treatments, maxLines: 5),
        ]),

        _card('Disposition', Theme.of(context).colorScheme.tertiary, [
          _dd('Disposition', _disposition, [
            'Transported to Hospital',
            'Transported by Air',
            'Transfer of Care',
            'Refused / AMA',
            'Treated on Scene',
            'Deceased',
            'Other',
          ], (v) => setState(() => _disposition = v)),
          const SizedBox(height: 8),
          _voiceTf('Additional Notes', _notes, maxLines: 3),
        ]),

        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send / Export'),
              onPressed: () => showModalBottomSheet(
                context: context,
                builder: (_) => TransferOptionsSheet(report: _compile()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Report'),
              onPressed: _save,
            ),
          ),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _card(String title, Color accent, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8, color: accent)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.outline)),
      );

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }

  Widget _voiceTf(String label, TextEditingController ctrl, {int maxLines = 1}) {
    final isActive = _listening && _activeListenCtrl == ctrl;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderSide: isActive ? const BorderSide(color: Colors.red, width: 2) : const BorderSide(),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: isActive ? const BorderSide(color: Colors.red, width: 2) : const BorderSide(),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: IconButton(
          icon: Icon(
            isActive ? Icons.mic : (_speechAvailable ? Icons.mic_none : Icons.mic_off),
            color: isActive ? Colors.red : (_speechAvailable ? null : Colors.grey),
            size: 20,
          ),
          tooltip: isActive ? 'Tap to stop' : 'Voice input',
          onPressed: _speechAvailable ? () => _toggleListen(ctrl) : null,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ),
    ]);
  }

  Widget _dd(String label, String? value, List<String> items, ValueChanged<String?> onChange) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChange,
    );
  }

  Widget _vitalChip(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label $value', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _vitalDetail(String label, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  // ── Broselow helpers ──────────────────────────────────────────────────────

  String _broselowFromKg(double kg) {
    if (kg <= 5) return 'Grey';
    if (kg <= 7) return 'Pink';
    if (kg <= 9) return 'Red';
    if (kg <= 11) return 'Purple';
    if (kg <= 14) return 'Yellow';
    if (kg <= 18) return 'White';
    if (kg <= 23) return 'Blue';
    if (kg <= 29) return 'Orange';
    return 'Green';
  }

  String _broselowWeightRange(double kg) {
    if (kg <= 5) return '3–5 kg';
    if (kg <= 7) return '6–7 kg';
    if (kg <= 9) return '8–9 kg';
    if (kg <= 11) return '10–11 kg';
    if (kg <= 14) return '12–14 kg';
    if (kg <= 18) return '15–18 kg';
    if (kg <= 23) return '19–23 kg';
    if (kg <= 29) return '24–29 kg';
    return '30–36 kg';
  }

  Color _parseBroselowColor(String name) {
    switch (name) {
      case 'Grey': return Colors.grey;
      case 'Pink': return Colors.pink;
      case 'Red': return Colors.red;
      case 'Purple': return Colors.purple;
      case 'Yellow': return Colors.yellow[700]!;
      case 'White': return Colors.blueGrey;
      case 'Blue': return Colors.blue;
      case 'Orange': return Colors.orange;
      case 'Green': return Colors.green;
      default: return Colors.grey;
    }
  }
}

// ── Vitals Entry Bottom Sheet ─────────────────────────────────────────────────

class _VitalsEntrySheet extends StatefulWidget {
  final VitalSet? existing;
  final ValueChanged<VitalSet> onSave;
  const _VitalsEntrySheet({this.existing, required this.onSave});

  @override
  State<_VitalsEntrySheet> createState() => _VitalsEntrySheetState();
}

class _VitalsEntrySheetState extends State<_VitalsEntrySheet> {
  late final TextEditingController _gcs, _bp, _hr, _rr, _spo2, _temp, _glucose, _pain;
  String? _avpu, _pupils, _skin;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _gcs = TextEditingController(text: e?.gcs ?? '');
    _bp = TextEditingController(text: e?.bp ?? '');
    _hr = TextEditingController(text: e?.hr ?? '');
    _rr = TextEditingController(text: e?.rr ?? '');
    _spo2 = TextEditingController(text: e?.spo2 ?? '');
    _temp = TextEditingController(text: e?.temp ?? '');
    _glucose = TextEditingController(text: e?.glucose ?? '');
    _pain = TextEditingController(text: e?.pain ?? '');
    _avpu = e?.avpu.isEmpty == true ? null : e?.avpu;
    _pupils = e?.pupils.isEmpty == true ? null : e?.pupils;
    _skin = e?.skin.isEmpty == true ? null : e?.skin;
  }

  @override
  void dispose() {
    for (final c in [_gcs, _bp, _hr, _rr, _spo2, _temp, _glucose, _pain]) { c.dispose(); }
    super.dispose();
  }

  void _submit() {
    final base = widget.existing ?? VitalSet.now();
    final vs = base.copyWith(
      avpu: _avpu ?? '', gcs: _gcs.text.trim(),
      bp: _bp.text.trim(), hr: _hr.text.trim(), rr: _rr.text.trim(),
      spo2: _spo2.text.trim(), temp: _temp.text.trim(),
      glucose: _glucose.text.trim(), pain: _pain.text.trim(),
      pupils: _pupils ?? '', skin: _skin ?? '',
    );
    Navigator.pop(context);
    widget.onSave(vs);
  }

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: children.map((c) => Expanded(child: c)).toList()
            .expand((w) => [w, const SizedBox(width: 8)]).toList()..removeLast()),
      );

  Widget _field(String label, TextEditingController ctrl, {String? hint}) => TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          isDense: true, filled: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      );

  Widget _drop(String label, String? value, List<String> items, ValueChanged<String?> fn) =>
      DropdownButtonFormField<String>(
        initialValue: value, isExpanded: true,
        decoration: InputDecoration(
          labelText: label, isDense: true, filled: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: fn,
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.schedule, size: 16, color: Colors.blue),
            const SizedBox(width: 6),
            Text(
              widget.existing != null ? 'Edit Vitals — ${widget.existing!.timeLabel}' : 'New Vitals — $ts',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ]),
          const SizedBox(height: 12),
          _row([
            _drop('AVPU', _avpu, ['Alert', 'Voice', 'Pain', 'Unresponsive'], (v) => setState(() => _avpu = v)),
            _field('GCS (3–15)', _gcs, hint: '15'),
          ]),
          _row([
            _field('BP (mmHg)', _bp, hint: '120/80'),
            _field('HR (bpm)', _hr, hint: '72'),
            _field('RR (/min)', _rr, hint: '16'),
          ]),
          _row([
            _field('SpO2 (%)', _spo2, hint: '98'),
            _field('Temp', _temp, hint: '98.6'),
            _field('BGL (mg/dL)', _glucose, hint: '100'),
          ]),
          _row([
            _field('Pain (0–10)', _pain, hint: '0'),
            _drop('Pupils', _pupils,
                ['PERL', 'Unequal', 'Dilated', 'Constricted', 'Non-reactive'],
                (v) => setState(() => _pupils = v)),
            _drop('Skin', _skin,
                ['Warm & Dry', 'Pale', 'Flushed', 'Cyanotic', 'Diaphoretic', 'Mottled'],
                (v) => setState(() => _skin = v)),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check),
            label: Text(widget.existing != null ? 'Update Vitals' : 'Record Vitals'),
          ),
        ]),
      ),
    );
  }
}

// ── Body Diagram Widget ───────────────────────────────────────────────────────

class BodyDiagramWidget extends StatefulWidget {
  final List<BodyMarker> markers;
  final ValueChanged<List<BodyMarker>> onMarkersChanged;
  const BodyDiagramWidget({super.key, required this.markers, required this.onMarkersChanged});

  @override
  State<BodyDiagramWidget> createState() => _BodyDiagramWidgetState();
}

class _BodyDiagramWidgetState extends State<BodyDiagramWidget> {
  String _view = 'front';
  late List<BodyMarker> _markers;

  @override
  void initState() {
    super.initState();
    _markers = List.from(widget.markers);
  }

  void _onTap(TapUpDetails details, Size size) {
    final rx = details.localPosition.dx / size.width;
    final ry = details.localPosition.dy / size.height;
    // Ignore taps outside figure bounds
    if (rx < 0.05 || rx > 0.95 || ry < 0.02 || ry > 0.98) return;
    _showLabelDialog(rx, ry);
  }

  void _showLabelDialog(double x, double y) {
    final ctrl = TextEditingController();
    const options = ['Laceration', 'Abrasion', 'Fracture', 'Burn', 'Contusion', 'Penetrating wound', 'Pain/Tenderness', 'Other'];
    String? selected = options.first;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Mark Injury'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Injury Type', border: OutlineInputBorder(), isDense: true),
              items: options.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) { setSt(() => selected = v); if (v != 'Other') ctrl.text = v ?? ''; },
            ),
            const SizedBox(height: 8),
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Custom label (optional)', border: OutlineInputBorder(), isDense: true)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final label = ctrl.text.trim().isEmpty ? (selected ?? 'Injury') : ctrl.text.trim();
                final m = BodyMarker(x: x, y: y, label: label, side: _view);
                setState(() => _markers.add(m));
                widget.onMarkersChanged(_markers);
                Navigator.pop(context);
              },
              child: const Text('Mark'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleMarkers = _markers.where((m) => m.side == _view).toList();
    return Column(
      children: [
        // Front/Back toggle
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'front', label: Text('Front'), icon: Icon(Icons.face, size: 16)),
            ButtonSegment(value: 'back', label: Text('Back'), icon: Icon(Icons.person_outline, size: 16)),
          ],
          selected: {_view},
          onSelectionChanged: (s) => setState(() => _view = s.first),
        ),
        const SizedBox(height: 12),
        // Diagram
        Center(
          child: LayoutBuilder(
            builder: (_, constraints) {
              final w = (constraints.maxWidth * 0.65).clamp(140.0, 240.0);
              final h = w * 1.6;
              return GestureDetector(
                onTapUp: (d) => _onTap(d, Size(w, h)),
                child: SizedBox(
                  width: w, height: h,
                  child: CustomPaint(
                    painter: _BodyPainter(
                      visibleMarkers,
                      Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Text('Tap on the figure to mark injury locations',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        // Marker list
        if (_markers.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...(_markers.asMap().entries.map((e) => ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.red.withValues(alpha: 0.15),
                  child: Text('${e.key + 1}', style: const TextStyle(fontSize: 10, color: Colors.red)),
                ),
                title: Text(e.value.label, style: const TextStyle(fontSize: 13)),
                subtitle: Text(e.value.side, style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    setState(() => _markers.removeAt(e.key));
                    widget.onMarkersChanged(_markers);
                  },
                ),
              ))),
        ],
      ],
    );
  }
}

class _BodyPainter extends CustomPainter {
  final List<BodyMarker> markers;
  final Color figureColor;
  const _BodyPainter(this.markers, this.figureColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = figureColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = figureColor.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    void shape(Path p) { canvas.drawPath(p, fill); canvas.drawPath(p, stroke); }

    // Head
    final hc = Offset(w * .50, h * .085);
    canvas.drawCircle(hc, w * .115, fill);
    canvas.drawCircle(hc, w * .115, stroke);

    // Neck
    shape(Path()..moveTo(w*.44,h*.17)..lineTo(w*.56,h*.17)..lineTo(w*.56,h*.20)..lineTo(w*.44,h*.20)..close());

    // Torso
    shape(Path()..moveTo(w*.26,h*.20)..lineTo(w*.74,h*.20)..lineTo(w*.71,h*.47)..lineTo(w*.29,h*.47)..close());

    // Pelvis
    shape(Path()..moveTo(w*.29,h*.47)..lineTo(w*.71,h*.47)..lineTo(w*.68,h*.535)..lineTo(w*.32,h*.535)..close());

    // L upper arm
    shape(Path()..moveTo(w*.26,h*.20)..lineTo(w*.16,h*.21)..lineTo(w*.10,h*.38)..lineTo(w*.18,h*.38)..close());
    // L forearm
    shape(Path()..moveTo(w*.10,h*.38)..lineTo(w*.18,h*.38)..lineTo(w*.13,h*.55)..lineTo(w*.07,h*.55)..close());
    // L hand
    canvas.drawCircle(Offset(w*.10,h*.585), w*.04, fill);
    canvas.drawCircle(Offset(w*.10,h*.585), w*.04, stroke);

    // R upper arm
    shape(Path()..moveTo(w*.74,h*.20)..lineTo(w*.84,h*.21)..lineTo(w*.90,h*.38)..lineTo(w*.82,h*.38)..close());
    // R forearm
    shape(Path()..moveTo(w*.82,h*.38)..lineTo(w*.90,h*.38)..lineTo(w*.93,h*.55)..lineTo(w*.87,h*.55)..close());
    // R hand
    canvas.drawCircle(Offset(w*.90,h*.585), w*.04, fill);
    canvas.drawCircle(Offset(w*.90,h*.585), w*.04, stroke);

    // L thigh
    shape(Path()..moveTo(w*.32,h*.535)..lineTo(w*.50,h*.535)..lineTo(w*.48,h*.73)..lineTo(w*.29,h*.73)..close());
    // L lower leg
    shape(Path()..moveTo(w*.29,h*.73)..lineTo(w*.48,h*.73)..lineTo(w*.47,h*.92)..lineTo(w*.29,h*.92)..close());
    // L foot
    shape(Path()..moveTo(w*.24,h*.92)..lineTo(w*.48,h*.92)..lineTo(w*.49,h*.97)..lineTo(w*.22,h*.97)..close());

    // R thigh
    shape(Path()..moveTo(w*.50,h*.535)..lineTo(w*.68,h*.535)..lineTo(w*.71,h*.73)..lineTo(w*.52,h*.73)..close());
    // R lower leg
    shape(Path()..moveTo(w*.52,h*.73)..lineTo(w*.71,h*.73)..lineTo(w*.71,h*.92)..lineTo(w*.53,h*.92)..close());
    // R foot
    shape(Path()..moveTo(w*.52,h*.92)..lineTo(w*.78,h*.92)..lineTo(w*.78,h*.97)..lineTo(w*.51,h*.97)..close());

    // Draw markers
    final mPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    final mBorder = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5;
    const tStyle = TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold);

    for (int i = 0; i < markers.length; i++) {
      final m = markers[i];
      final dx = m.x * w;
      final dy = m.y * h;
      canvas.drawCircle(Offset(dx, dy), 9, mPaint);
      canvas.drawCircle(Offset(dx, dy), 9, mBorder);
      final span = TextSpan(text: '${i + 1}', style: tStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.markers != markers || old.figureColor != figureColor;
}

// ── View Screen ───────────────────────────────────────────────────────────────

class PatientReportViewScreen extends StatelessWidget {
  final PatientReport report;
  const PatientReportViewScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(report.patientId.isEmpty ? 'Patient Report' : report.patientId),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report.formattedText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareReport(report)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          report.formattedText,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.6),
        ),
      ),
    );
  }
}
