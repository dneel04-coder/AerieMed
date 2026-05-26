import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

// START triage tags
const _kImmediate = 'Immediate';  // Red
const _kDelayed = 'Delayed';      // Yellow
const _kMinor = 'Minor';          // Green
const _kDeceased = 'Deceased';    // Black / expectant

class McasCasualty {
  final String id;
  final DateTime taggedAt;
  String tag, location, age, sex, chiefComplaint, notes, assignedTo;
  bool walking;
  String respirations, pulse, mentalStatus;

  McasCasualty({
    required this.id,
    required this.taggedAt,
    this.tag = _kImmediate,
    this.location = '',
    this.age = '',
    this.sex = '',
    this.chiefComplaint = '',
    this.notes = '',
    this.assignedTo = '',
    this.walking = false,
    this.respirations = '',
    this.pulse = '',
    this.mentalStatus = '',
  });

  factory McasCasualty.fresh() => McasCasualty(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        taggedAt: DateTime.now(),
      );

  static String _z(int n) => n.toString().padLeft(2, '0');
  String get timeLabel {
    final t = taggedAt.toLocal();
    return '${_z(t.hour)}:${_z(t.minute)}';
  }

  // Sort priority: Immediate → Deceased → Delayed → Minor
  int get sortOrder {
    switch (tag) {
      case _kImmediate: return 0;
      case _kDeceased: return 1;
      case _kDelayed: return 2;
      case _kMinor: return 3;
      default: return 4;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'taggedAt': taggedAt.toIso8601String(),
        'tag': tag,
        'location': location,
        'age': age,
        'sex': sex,
        'chiefComplaint': chiefComplaint,
        'notes': notes,
        'assignedTo': assignedTo,
        'walking': walking,
        'respirations': respirations,
        'pulse': pulse,
        'mentalStatus': mentalStatus,
      };

  factory McasCasualty.fromJson(Map<String, dynamic> j) => McasCasualty(
        id: j['id'] as String? ?? '',
        taggedAt: DateTime.tryParse(j['taggedAt'] as String? ?? '') ?? DateTime.now(),
        tag: j['tag'] as String? ?? _kImmediate,
        location: j['location'] as String? ?? '',
        age: j['age'] as String? ?? '',
        sex: j['sex'] as String? ?? '',
        chiefComplaint: j['chiefComplaint'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        assignedTo: j['assignedTo'] as String? ?? '',
        walking: j['walking'] as bool? ?? false,
        respirations: j['respirations'] as String? ?? '',
        pulse: j['pulse'] as String? ?? '',
        mentalStatus: j['mentalStatus'] as String? ?? '',
      );
}

// ── Storage ───────────────────────────────────────────────────────────────────

class MciStorage {
  static const _k = 'mci_casualties_v1';

  static Future<List<McasCasualty>> load() async {
    final p = await SharedPreferences.getInstance();
    final list = (p.getStringList(_k) ?? []).map((e) {
      try { return McasCasualty.fromJson(jsonDecode(e) as Map<String, dynamic>); } catch (_) { return null; }
    }).whereType<McasCasualty>().toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  static Future<void> save(McasCasualty c) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == c.id);
    list.add(c);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }

  static Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == id);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
  }
}

// ── Tag colours / labels ──────────────────────────────────────────────────────

Color _tagColor(String tag) {
  switch (tag) {
    case _kImmediate: return Colors.red;
    case _kDelayed: return Colors.amber[700]!;
    case _kMinor: return Colors.green;
    case _kDeceased: return Colors.black87;
    default: return Colors.grey;
  }
}

IconData _tagIcon(String tag) {
  switch (tag) {
    case _kImmediate: return Icons.emergency;
    case _kDelayed: return Icons.schedule;
    case _kMinor: return Icons.directions_walk;
    case _kDeceased: return Icons.do_not_disturb;
    default: return Icons.help_outline;
  }
}

// ── Main MCI Screen ───────────────────────────────────────────────────────────

class MciTriageScreen extends StatefulWidget {
  const MciTriageScreen({super.key});

  @override
  State<MciTriageScreen> createState() => _MciTriageScreenState();
}

class _MciTriageScreenState extends State<MciTriageScreen> {
  List<McasCasualty> _casualties = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await MciStorage.load();
    if (mounted) setState(() { _casualties = d; _loading = false; });
  }

  // ── Tag counts ──────────────────────────────────────────────────────────────
  int _count(String tag) => _casualties.where((c) => c.tag == tag).length;

  // ── Start triage flow ───────────────────────────────────────────────────────
  Future<void> _startTriage() async {
    final tag = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _StartTriageDialog(),
    );
    if (tag == null || !mounted) return;
    // After tagging, collect casualty details
    final casualty = await showModalBottomSheet<McasCasualty>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CasualtyDetailSheet(initialTag: tag),
    );
    if (casualty == null) return;
    await MciStorage.save(casualty);
    _load();
  }

  Future<void> _editCasualty(McasCasualty c) async {
    final updated = await showModalBottomSheet<McasCasualty>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CasualtyDetailSheet(existing: c),
    );
    if (updated == null) return;
    await MciStorage.save(updated);
    _load();
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All Casualties?'),
        content: const Text('This will delete all triage records. Use at end of incident or before a new drill.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (ok == true) { await MciStorage.clearAll(); _load(); }
  }

  void _shareReport() {
    final lines = <String>[
      '══════════════════════════════',
      '   MCI TRIAGE SUMMARY',
      '══════════════════════════════',
      'Generated: ${DateTime.now().toLocal()}',
      '',
      '🔴 IMMEDIATE  : ${_count(_kImmediate)}',
      '🟡 DELAYED    : ${_count(_kDelayed)}',
      '🟢 MINOR      : ${_count(_kMinor)}',
      '⬛ DECEASED   : ${_count(_kDeceased)}',
      'TOTAL         : ${_casualties.length}',
      '──────────────────────────────',
    ];

    for (final tag in [_kImmediate, _kDeceased, _kDelayed, _kMinor]) {
      final group = _casualties.where((c) => c.tag == tag).toList();
      if (group.isEmpty) continue;
      lines.add('\n$tag (${group.length}):');
      for (int i = 0; i < group.length; i++) {
        final c = group[i];
        lines.add('  ${i + 1}. ${c.location.isEmpty ? "Unknown location" : c.location}'
            '${c.age.isNotEmpty ? " | ${c.age}${c.sex.isNotEmpty ? c.sex[0] : ""}" : ""}'
            '${c.chiefComplaint.isNotEmpty ? " — ${c.chiefComplaint}" : ""}'
            ' [${c.timeLabel}]');
      }
    }
    lines.add('\n══════════════════════════════');

    SharePlus.instance.share(ShareParams(
      text: lines.join('\n'),
      subject: 'MCI Triage Summary — ${_casualties.length} casualties',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = _casualties.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red[800],
        foregroundColor: Colors.white,
        title: Row(children: [
          const Icon(Icons.emergency, size: 20),
          const SizedBox(width: 8),
          const Text('MCI Triage', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          // Mini count chips
          for (final tag in [_kImmediate, _kDelayed, _kMinor, _kDeceased])
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _MiniTagChip(tag: tag, count: _count(tag)),
            ),
        ]),
        actions: [
          if (_casualties.isNotEmpty)
            IconButton(icon: const Icon(Icons.share_outlined), tooltip: 'Share summary', onPressed: _shareReport),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) { if (v == 'clear') _confirmClear(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: ListTile(
                leading: Icon(Icons.delete_sweep, color: Colors.red),
                title: Text('Clear All Casualties', style: TextStyle(color: Colors.red)),
                dense: true,
              )),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary bar
                _SummaryBar(
                  immediate: _count(_kImmediate),
                  delayed: _count(_kDelayed),
                  minor: _count(_kMinor),
                  deceased: _count(_kDeceased),
                  total: total,
                ),
                // Casualty list
                Expanded(
                  child: _casualties.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.health_and_safety_outlined, size: 72, color: Colors.red[100]),
                            const SizedBox(height: 16),
                            const Text('No casualties tagged yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                            const SizedBox(height: 8),
                            const Text('Tap the button below to begin START triage',
                                style: TextStyle(fontSize: 13, color: Colors.grey)),
                          ]),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                          itemCount: _casualties.length,
                          itemBuilder: (_, i) => _casualtyTile(_casualties[i], i + 1),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startTriage,
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Triage Patient', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _casualtyTile(McasCasualty c, int num) {
    final tagCol = _tagColor(c.tag);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Tag colour bar + number
            Container(
              width: 52,
              color: tagCol,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('#$num', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Icon(_tagIcon(c.tag), color: Colors.white, size: 16),
              ]),
            ),
            Expanded(
              child: ListTile(
                title: Row(children: [
                  Expanded(
                    child: Text(
                      c.chiefComplaint.isEmpty ? c.tag : c.chiefComplaint,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  Text(c.timeLabel, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (c.location.isNotEmpty || c.age.isNotEmpty || c.sex.isNotEmpty)
                    Text(
                      [
                        if (c.location.isNotEmpty) c.location,
                        if (c.age.isNotEmpty || c.sex.isNotEmpty) '${c.age}${c.sex.isEmpty ? '' : ' ${c.sex}'}',
                      ].join('  •  '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (c.assignedTo.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.person_outline, size: 11, color: Colors.grey),
                      Text(' ${c.assignedTo}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  if (c.notes.isNotEmpty)
                    Text(c.notes, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                ]),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editCasualty(c)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () async { await MciStorage.delete(c.id); _load(); },
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int immediate, delayed, minor, deceased, total;
  const _SummaryBar({required this.immediate, required this.delayed, required this.minor, required this.deceased, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        _cell('IMMEDIATE', immediate, Colors.red),
        _cell('DELAYED', delayed, Colors.amber),
        _cell('MINOR', minor, Colors.green),
        _cell('DECEASED', deceased, Colors.grey[400]!),
        const Spacer(),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          const Text('TOTAL', style: TextStyle(color: Colors.grey, fontSize: 9, letterSpacing: 0.5)),
        ]),
      ]),
    );
  }

  Widget _cell(String label, int count, Color color) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 8, letterSpacing: 0.4)),
        ]),
      );
}

// ── Mini tag chip (AppBar) ────────────────────────────────────────────────────

class _MiniTagChip extends StatelessWidget {
  final String tag;
  final int count;
  const _MiniTagChip({required this.tag, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _tagColor(tag).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ── START Triage guided dialog ────────────────────────────────────────────────

class _StartTriageDialog extends StatefulWidget {
  const _StartTriageDialog();

  @override
  State<_StartTriageDialog> createState() => _StartTriageDialogState();
}

class _StartTriageDialogState extends State<_StartTriageDialog> {
  int _step = 0;

  // Step definitions: each has a question, YES target, NO target, and an optional result
  // Step targets: positive int = go to step N, negative = tag result
  // Tags encoded: -1 = Minor, -2 = Immediate, -3 = Deceased

  static const _steps = <Map<String, dynamic>>[
    // Step 0
    {
      'q': 'Can the patient walk to a designated safe area?',
      'hint': 'Ask the patient to stand and walk a short distance.',
      'yes': -1,        // → Minor (Green)
      'no': 1,
    },
    // Step 1
    {
      'q': 'Is the patient breathing?',
      'hint': 'Look, listen, and feel for breathing.',
      'yes': 2,
      'no': -99,        // → Airway sub-step
    },
    // Step 2
    {
      'q': 'Respiratory rate — more than 30/min or fewer than 6/min?',
      'hint': 'Count breaths for 15 seconds and multiply by 4.',
      'yes': -2,        // → Immediate
      'no': 3,
    },
    // Step 3
    {
      'q': 'Is the radial pulse absent or barely palpable?',
      'hint': 'Feel the wrist. Absent or very weak = immediate.',
      'yes': -2,        // → Immediate
      'no': 4,
    },
    // Step 4
    {
      'q': 'Can the patient follow a simple command?\n(e.g. "Squeeze my hand.")',
      'hint': 'Mental status check — assess for altered consciousness.',
      'yes': -3,        // → Delayed
      'no': -2,         // → Immediate
    },
  ];

  // Airway sub-step: reposition and check again
  bool _awaitingAirway = false;

  void _answer(bool yes) {
    if (_awaitingAirway) {
      // After repositioning airway: breathing now?
      setState(() {
        _awaitingAirway = false;
        if (yes) {
          // Now breathing → check rate (step 2)
          _step = 2;
        } else {
          // Still not breathing → Deceased
          Navigator.pop(context, _kDeceased);
        }
      });
      return;
    }

    final step = _steps[_step];
    final target = yes ? step['yes'] as int : step['no'] as int;

    if (target == -99) {
      // Airway maneuver sub-step
      setState(() => _awaitingAirway = true);
      return;
    }

    if (target < 0) {
      // Terminal: tag
      switch (target) {
        case -1: Navigator.pop(context, _kMinor); break;
        case -2: Navigator.pop(context, _kImmediate); break;
        case -3: Navigator.pop(context, _kDelayed); break;
      }
      return;
    }

    setState(() => _step = target);
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_awaitingAirway) {
      content = _stepContent(
        question: 'Reposition the airway (head-tilt/chin-lift or jaw thrust).\n\nIs the patient NOW breathing?',
        hint: 'Open the airway and reassess.',
        stepLabel: '1b',
        total: 5,
      );
    } else {
      final step = _steps[_step];
      content = _stepContent(
        question: step['q'] as String,
        hint: step['hint'] as String,
        stepLabel: '${_step + 1}',
        total: 5,
      );
    }

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              ),
              child: Row(children: [
                const Icon(Icons.emergency, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('START Triage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ]),
            ),
            content,
          ],
        ),
      ),
    );
  }

  Widget _stepContent({
    required String question,
    required String hint,
    required String stepLabel,
    required int total,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Step $stepLabel of $total',
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text(question,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 6),
          Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text('NO', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red, width: 1.5),
                ),
                onPressed: () => _answer(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('YES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                ),
                onPressed: () => _answer(true),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          // Tag legend
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final t in [_kImmediate, _kDelayed, _kMinor, _kDeceased])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: _tagColor(t), shape: BoxShape.circle)),
                  const SizedBox(width: 3),
                  Text(t[0], style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                ]),
              ),
          ]),
        ],
      ),
    );
  }
}

// ── Casualty detail sheet ─────────────────────────────────────────────────────

class _CasualtyDetailSheet extends StatefulWidget {
  final String? initialTag;
  final McasCasualty? existing;
  const _CasualtyDetailSheet({this.initialTag, this.existing});

  @override
  State<_CasualtyDetailSheet> createState() => _CasualtyDetailSheetState();
}

class _CasualtyDetailSheetState extends State<_CasualtyDetailSheet> {
  late String _tag;
  late final TextEditingController _location, _age, _complaint, _notes, _assignedTo;
  String? _sex;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tag = e?.tag ?? widget.initialTag ?? _kImmediate;
    _location = TextEditingController(text: e?.location ?? '');
    _age = TextEditingController(text: e?.age ?? '');
    _complaint = TextEditingController(text: e?.chiefComplaint ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _assignedTo = TextEditingController(text: e?.assignedTo ?? '');
    _sex = e?.sex.isEmpty == true ? null : e?.sex;
  }

  @override
  void dispose() {
    for (final c in [_location, _age, _complaint, _notes, _assignedTo]) { c.dispose(); }
    super.dispose();
  }

  void _save() {
    final c = widget.existing ?? McasCasualty.fresh();
    c.tag = _tag;
    c.location = _location.text.trim();
    c.age = _age.text.trim();
    c.sex = _sex ?? '';
    c.chiefComplaint = _complaint.text.trim();
    c.notes = _notes.text.trim();
    c.assignedTo = _assignedTo.text.trim();
    Navigator.pop(context, c);
  }

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label, hintText: hint,
            border: const OutlineInputBorder(), isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tagCol = _tagColor(_tag);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tag selector header
            Container(
              color: tagCol,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.existing == null ? 'Tag Patient' : 'Edit Casualty',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                // Tag buttons
                Row(children: [
                  for (final tag in [_kImmediate, _kDelayed, _kMinor, _kDeceased])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _tag = tag),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _tag == tag ? Colors.white : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(children: [
                              Icon(_tagIcon(tag),
                                  color: _tag == tag ? _tagColor(tag) : Colors.white, size: 18),
                              const SizedBox(height: 2),
                              Text(
                                tag == _kImmediate ? 'IMM' : tag == _kDeceased ? 'EXP' : tag.substring(0, 3).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold,
                                  color: _tag == tag ? _tagColor(tag) : Colors.white,
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
            // Detail fields
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _tf('Location / Scene Position', _location, hint: 'e.g. Trail 4, near bridge'),
                Row(children: [
                  SizedBox(width: 80, child: _tf('Age', _age, hint: '35')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sex,
                      decoration: const InputDecoration(labelText: 'Sex', border: OutlineInputBorder(), isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                        DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
                      ],
                      onChanged: (v) => setState(() => _sex = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _tf('Chief Complaint / Mechanism', _complaint, maxLines: 2),
                _tf('Assigned Provider / Team', _assignedTo),
                _tf('Notes', _notes, maxLines: 2),
                FilledButton.icon(
                  onPressed: _save,
                  style: FilledButton.styleFrom(backgroundColor: tagCol),
                  icon: const Icon(Icons.check),
                  label: Text(widget.existing == null ? 'Tag & Record' : 'Save Changes'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
