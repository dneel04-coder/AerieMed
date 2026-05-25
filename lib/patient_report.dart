import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';

// ─────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────

class PatientReport {
  final String id;
  final DateTime createdAt;
  String provider;
  String unit;
  String patientId;
  String age;
  String sex;
  String chiefComplaint;
  String allergies;
  String mechanism;
  String injuries;
  String vitalsTime;
  String avpu;
  String gcs;
  String bp;
  String hr;
  String rr;
  String spo2;
  String temp;
  String glucose;
  String pain;
  String pupils;
  String skin;
  String treatments;
  String disposition;
  String notes;

  PatientReport({
    required this.id,
    required this.createdAt,
    this.provider = '',
    this.unit = '',
    this.patientId = '',
    this.age = '',
    this.sex = '',
    this.chiefComplaint = '',
    this.allergies = '',
    this.mechanism = '',
    this.injuries = '',
    this.vitalsTime = '',
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
    this.treatments = '',
    this.disposition = '',
    this.notes = '',
  });

  factory PatientReport.fresh() => PatientReport(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
      );

  static String _z(int n) => n.toString().padLeft(2, '0');

  String get timestampDisplay =>
      '${createdAt.year}-${_z(createdAt.month)}-${_z(createdAt.day)} '
      '${_z(createdAt.hour)}${_z(createdAt.minute)}Z';

  static String _v(String s, [String fallback = '----']) =>
      s.isEmpty ? fallback : s;

  String get formattedText {
    final dt =
        '${createdAt.year}-${_z(createdAt.month)}-${_z(createdAt.day)} '
        '${_z(createdAt.hour)}:${_z(createdAt.minute)}:${_z(createdAt.second)}Z';
    final lines = [
      '==========================================',
      '        PATIENT CARE REPORT - MIST',
      '==========================================',
      'REPORT #  : $id',
      'DATE/TIME : $dt',
      'PROVIDER  : ${_v(provider)}',
      'UNIT/AGCY : ${_v(unit)}',
      '------------------------------------------',
      'PATIENT INFORMATION',
      '------------------------------------------',
      'PT ID/NAME: ${_v(patientId)}',
      'AGE       : ${_v(age, '--')}   SEX: ${_v(sex, '--')}',
      'COMPLAINT : ${_v(chiefComplaint)}',
      'ALLERGIES : ${_v(allergies, 'NKDA')}',
      '------------------------------------------',
      '[M] MECHANISM OF INJURY / ILLNESS',
      '------------------------------------------',
      _v(mechanism, '(not documented)'),
      '------------------------------------------',
      '[I] INJURIES / SIGNS & SYMPTOMS',
      '------------------------------------------',
      _v(injuries, '(not documented)'),
      '------------------------------------------',
      '[S] VITAL SIGNS',
      '------------------------------------------',
      'TIME      : ${vitalsTime.isEmpty ? dt : vitalsTime}',
      'AVPU      : ${_v(avpu, '--')}   GCS: ${_v(gcs, '--')}',
      'BP        : ${_v(bp, '--/--')}',
      'HR        : ${_v(hr, '--')} bpm   RR: ${_v(rr, '--')} /min',
      'SpO2      : ${_v(spo2, '--')}%   TEMP: ${_v(temp, '--')}',
      'BGL       : ${_v(glucose, '--')} mg/dL',
      'PUPILS    : ${_v(pupils)}',
      'SKIN      : ${_v(skin)}',
      'PAIN      : ${_v(pain, '--')} / 10',
      '------------------------------------------',
      '[T] TREATMENTS ADMINISTERED',
      '------------------------------------------',
      _v(treatments, '(not documented)'),
      '------------------------------------------',
      'DISPOSITION : ${_v(disposition)}',
    ];
    if (notes.isNotEmpty) {
      lines.addAll([
        '------------------------------------------',
        'ADDITIONAL NOTES',
        '------------------------------------------',
        notes,
      ]);
    }
    lines.add('==========================================');
    return lines.join('\n');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'provider': provider,
        'unit': unit,
        'patientId': patientId,
        'age': age,
        'sex': sex,
        'chiefComplaint': chiefComplaint,
        'allergies': allergies,
        'mechanism': mechanism,
        'injuries': injuries,
        'vitalsTime': vitalsTime,
        'avpu': avpu,
        'gcs': gcs,
        'bp': bp,
        'hr': hr,
        'rr': rr,
        'spo2': spo2,
        'temp': temp,
        'glucose': glucose,
        'pain': pain,
        'pupils': pupils,
        'skin': skin,
        'treatments': treatments,
        'disposition': disposition,
        'notes': notes,
      };

  factory PatientReport.fromJson(Map<String, dynamic> j) => PatientReport(
        id: j['id'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        provider: j['provider'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        patientId: j['patientId'] as String? ?? '',
        age: j['age'] as String? ?? '',
        sex: j['sex'] as String? ?? '',
        chiefComplaint: j['chiefComplaint'] as String? ?? '',
        allergies: j['allergies'] as String? ?? '',
        mechanism: j['mechanism'] as String? ?? '',
        injuries: j['injuries'] as String? ?? '',
        vitalsTime: j['vitalsTime'] as String? ?? '',
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
        treatments: j['treatments'] as String? ?? '',
        disposition: j['disposition'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────
// Storage
// ─────────────────────────────────────────────────────────────

class ReportStorage {
  static const _key = 'patient_reports_v1';

  static Future<List<PatientReport>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? [])
        .map((e) {
          try {
            return PatientReport.fromJson(
                jsonDecode(e) as Map<String, dynamic>);
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
    await prefs.setStringList(
        _key, list.map((x) => jsonEncode(x.toJson())).toList());
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == id);
    await prefs.setStringList(
        _key, list.map((x) => jsonEncode(x.toJson())).toList());
  }
}

// ─────────────────────────────────────────────────────────────
// Shared share helper
// ─────────────────────────────────────────────────────────────

void _shareReport(PatientReport r) {
  SharePlus.instance.share(ShareParams(
    text: r.formattedText,
    subject: 'MIST Report - ${r.patientId.isEmpty ? r.id : r.patientId}',
  ));
}

// ─────────────────────────────────────────────────────────────
// Report List Screen
// ─────────────────────────────────────────────────────────────

class PatientReportListScreen extends StatefulWidget {
  const PatientReportListScreen({super.key});

  @override
  State<PatientReportListScreen> createState() =>
      _PatientReportListScreenState();
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
    final r = await ReportStorage.load();
    if (mounted) {
      setState(() {
        _reports = r;
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(PatientReport r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Report'),
        content: Text(
          'Delete the report for '
          '"${r.patientId.isEmpty ? 'Unknown Patient' : r.patientId}"?\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ReportStorage.delete(r.id);
      _refresh();
    }
  }

  Future<void> _openNewReport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PatientReportFormScreen()),
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
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New Report',
            onPressed: _openNewReport,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _buildTile(_reports[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
        onPressed: _openNewReport,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 72, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No reports on file',
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('Tap + to create a new MIST report',
              style: TextStyle(fontSize: 13, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildTile(PatientReport r) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.person, color: cs.onPrimaryContainer),
        ),
        title: Text(
          r.patientId.isEmpty ? 'Unknown Patient' : r.patientId,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.chiefComplaint.isNotEmpty)
              Text(r.chiefComplaint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
            Text(r.timestampDisplay,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        isThreeLine: r.chiefComplaint.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Transmit',
              onPressed: () => _shareReport(r),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red[400]),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(r),
            ),
          ],
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PatientReportViewScreen(report: r)),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Report Form Screen  (always opens blank)
// ─────────────────────────────────────────────────────────────

class PatientReportFormScreen extends StatefulWidget {
  const PatientReportFormScreen({super.key});

  @override
  State<PatientReportFormScreen> createState() =>
      _PatientReportFormScreenState();
}

class _PatientReportFormScreenState extends State<PatientReportFormScreen> {
  late final PatientReport _draft;

  final _provider = TextEditingController();
  final _unit = TextEditingController();
  final _patientId = TextEditingController();
  final _age = TextEditingController();
  final _chiefComplaint = TextEditingController();
  final _allergies = TextEditingController();
  final _mechanism = TextEditingController();
  final _injuries = TextEditingController();
  final _vitalsTime = TextEditingController();
  final _gcs = TextEditingController();
  final _bp = TextEditingController();
  final _hr = TextEditingController();
  final _rr = TextEditingController();
  final _spo2 = TextEditingController();
  final _temp = TextEditingController();
  final _glucose = TextEditingController();
  final _pain = TextEditingController();
  final _treatments = TextEditingController();
  final _notes = TextEditingController();

  String? _sex;
  String? _avpu;
  String? _pupils;
  String? _skin;
  String? _disposition;

  @override
  void initState() {
    super.initState();
    _draft = PatientReport.fresh();
  }

  @override
  void dispose() {
    for (final c in [
      _provider, _unit, _patientId, _age, _chiefComplaint, _allergies,
      _mechanism, _injuries, _vitalsTime, _gcs, _bp, _hr, _rr, _spo2,
      _temp, _glucose, _pain, _treatments, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  PatientReport _compile() => PatientReport(
        id: _draft.id,
        createdAt: _draft.createdAt,
        provider: _provider.text.trim(),
        unit: _unit.text.trim(),
        patientId: _patientId.text.trim(),
        age: _age.text.trim(),
        sex: _sex ?? '',
        chiefComplaint: _chiefComplaint.text.trim(),
        allergies: _allergies.text.trim(),
        mechanism: _mechanism.text.trim(),
        injuries: _injuries.text.trim(),
        vitalsTime: _vitalsTime.text.trim(),
        avpu: _avpu ?? '',
        gcs: _gcs.text.trim(),
        bp: _bp.text.trim(),
        hr: _hr.text.trim(),
        rr: _rr.text.trim(),
        spo2: _spo2.text.trim(),
        temp: _temp.text.trim(),
        glucose: _glucose.text.trim(),
        pain: _pain.text.trim(),
        pupils: _pupils ?? '',
        skin: _skin ?? '',
        treatments: _treatments.text.trim(),
        disposition: _disposition ?? '',
        notes: _notes.text.trim(),
      );

  Future<void> _save() async {
    await ReportStorage.save(_compile());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Report saved'),
            duration: Duration(seconds: 2)),
      );
      Navigator.pop(context);
    }
  }

  void _transmit() => _shareReport(_compile());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('New MIST Report'),
            Text(
              _draft.timestampDisplay,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withAlpha(150)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Transmit',
            onPressed: _transmit,
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header
            _section(
              label: 'HEADER',
              accent: cs.primary,
              children: [
                Row(children: [
                  Expanded(child: _tf('Provider Name', _provider)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Unit / Agency', _unit)),
                ]),
              ],
            ),

            // ── Patient Info
            _section(
              label: 'PATIENT INFORMATION',
              accent: cs.secondary,
              children: [
                _tf('Patient ID / Name', _patientId),
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(width: 84, child: _tf('Age', _age)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dd('Sex', _sex,
                        ['Male', 'Female', 'Unknown'],
                        (v) => setState(() => _sex = v)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _tf('Chief Complaint', _chiefComplaint),
                  ),
                ]),
                const SizedBox(height: 8),
                _tf('Allergies (NKDA if none)', _allergies),
              ],
            ),

            // ── M – Mechanism
            _section(
              label: '[M]  MECHANISM OF INJURY / ILLNESS',
              accent: Colors.orange,
              children: [
                _tf('Describe how injury or illness occurred',
                    _mechanism, maxLines: 3),
              ],
            ),

            // ── I – Injuries
            _section(
              label: '[I]  INJURIES / SIGNS & SYMPTOMS',
              accent: Colors.red,
              children: [
                _tf('Document all injuries, complaints, and findings',
                    _injuries, maxLines: 4),
              ],
            ),

            // ── S – Vitals
            _section(
              label: '[S]  VITAL SIGNS',
              accent: Colors.blue,
              children: [
                _tf('Time of Vitals (blank = use report timestamp)',
                    _vitalsTime),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 160,
                      child: _dd(
                          'AVPU',
                          _avpu,
                          ['Alert', 'Voice', 'Pain', 'Unresponsive'],
                          (v) => setState(() => _avpu = v)),
                    ),
                    SizedBox(width: 90, child: _tf('GCS (3–15)', _gcs)),
                    SizedBox(
                        width: 110,
                        child: _tf('BP (mmHg)', _bp, hint: '120/80')),
                    SizedBox(
                        width: 90,
                        child: _tf('HR (bpm)', _hr, hint: '72')),
                    SizedBox(
                        width: 90,
                        child: _tf('RR (/min)', _rr, hint: '16')),
                    SizedBox(
                        width: 90,
                        child: _tf('SpO2 (%)', _spo2, hint: '98')),
                    SizedBox(
                        width: 90,
                        child: _tf('Temp', _temp, hint: '98.6°F')),
                    SizedBox(
                        width: 110,
                        child: _tf('BGL (mg/dL)', _glucose, hint: '100')),
                    SizedBox(
                        width: 100,
                        child: _tf('Pain (0–10)', _pain, hint: '0')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _dd(
                      'Pupils',
                      _pupils,
                      [
                        'PERL',
                        'Unequal',
                        'Dilated',
                        'Constricted',
                        'Non-reactive',
                      ],
                      (v) => setState(() => _pupils = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dd(
                      'Skin',
                      _skin,
                      [
                        'Warm & Dry',
                        'Pale',
                        'Flushed',
                        'Cyanotic',
                        'Diaphoretic',
                        'Mottled',
                      ],
                      (v) => setState(() => _skin = v),
                    ),
                  ),
                ]),
              ],
            ),

            // ── T – Treatments
            _section(
              label: '[T]  TREATMENTS ADMINISTERED',
              accent: Colors.green,
              children: [
                _tf(
                    'Document all treatments, medications, doses, and times',
                    _treatments,
                    maxLines: 5),
              ],
            ),

            // ── Disposition
            _section(
              label: 'DISPOSITION',
              accent: cs.tertiary,
              children: [
                _dd(
                  'Disposition',
                  _disposition,
                  [
                    'Transported to Hospital',
                    'Transported by Air',
                    'Transfer of Care',
                    'Refused / AMA',
                    'Treated on Scene',
                    'Deceased',
                    'Other',
                  ],
                  (v) => setState(() => _disposition = v),
                ),
                const SizedBox(height: 8),
                _tf('Additional Notes', _notes, maxLines: 3),
              ],
            ),

            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Transmit'),
                  onPressed: _transmit,
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Section card with colored left border
  Widget _section({
    required String label,
    required Color accent,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: accent, width: 4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: accent)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _tf(String label, TextEditingController ctrl,
      {int maxLines = 1, String? hint}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }

  Widget _dd(String label, String? value, List<String> items,
      ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      items: items
          .map((s) => DropdownMenuItem(
              value: s,
              child: Text(s, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Report View Screen
// ─────────────────────────────────────────────────────────────

class PatientReportViewScreen extends StatelessWidget {
  final PatientReport report;
  const PatientReportViewScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            report.patientId.isEmpty ? 'Patient Report' : report.patientId),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy to Clipboard',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report.formattedText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 2)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Transmit / Share',
            onPressed: () => _shareReport(report),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          report.formattedText,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 13, height: 1.6),
        ),
      ),
    );
  }
}
