import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocol_admin.dart' show SupabaseService;

// ═══════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════

enum _WidgetType { none, table }

class QuickReply {
  final String label;
  final String prompt;
  final IconData? icon;
  const QuickReply(this.label, this.prompt, {this.icon});
}

class ChatResponse {
  final String responseText;
  final List<QuickReply> suggestions;
  final _WidgetType widgetType;
  final List<List<String>>? tableData;   // [header, row, row, ...]
  final List<String>? tableHeaders;

  const ChatResponse({
    required this.responseText,
    this.suggestions = const [],
    this.widgetType = _WidgetType.none,
    this.tableData,
    this.tableHeaders,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SESSION STATE
// ═══════════════════════════════════════════════════════════════════════════

class _Session {
  double?  patientWeightKg;
  String?  lastProtocolViewed;
  String   lastIntent        = '';
  String?  pendingDrugName;   // waiting for weight before dosing
  bool     triageActive       = false;
  int      triageStep         = 0;   // 0-5
  String?  triageContext;            // rationale accumulator

  void clearDrug()   { pendingDrugName = null; }
  void clearTriage() { triageActive = false; triageStep = 0; triageContext = null; }
}

// ═══════════════════════════════════════════════════════════════════════════
// DRUG FORMULA MAP
// ═══════════════════════════════════════════════════════════════════════════

class _Drug {
  final String name;
  final List<String> keywords;
  final bool weightBased;
  final double? mgPerKgMin;
  final double? mgPerKgMax;
  final double? fixedMgMin;
  final double? fixedMgMax;
  final String unit;
  final double? maxDose;
  final String route;
  final String notes;

  const _Drug({
    required this.name,
    required this.keywords,
    this.weightBased = false,
    this.mgPerKgMin,
    this.mgPerKgMax,
    this.fixedMgMin,
    this.fixedMgMax,
    required this.unit,
    this.maxDose,
    required this.route,
    this.notes = '',
  });
}

const _kDrugs = <_Drug>[
  _Drug(name: 'Ketamine (pain)', keywords: ['ketamine', 'ket'],
      weightBased: true, mgPerKgMin: 0.3, mgPerKgMax: 0.5, unit: 'mg',
      maxDose: 500, route: 'IV/IM', notes: '0.3 mg/kg IV · 0.5 mg/kg IM'),
  _Drug(name: 'Ketamine (dissociative)', keywords: ['ketamine dissociative', 'ket diss'],
      weightBased: true, mgPerKgMin: 1.5, mgPerKgMax: 2.0, unit: 'mg',
      maxDose: 500, route: 'IV (IM: 4 mg/kg)', notes: '1.5–2 mg/kg IV · 4 mg/kg IM'),
  _Drug(name: 'Morphine', keywords: ['morphine'],
      weightBased: true, mgPerKgMin: 0.1, mgPerKgMax: 0.1, unit: 'mg',
      maxDose: 10, route: 'IV/IM'),
  _Drug(name: 'Fentanyl', keywords: ['fentanyl', 'fent'],
      weightBased: true, mgPerKgMin: 0.001, mgPerKgMax: 0.002, unit: 'mcg',
      maxDose: 0.2, route: 'IV/IN',
      notes: 'mcg/kg IV/IN — report as mcg'),
  _Drug(name: 'Naloxone (Narcan)', keywords: ['naloxone', 'narcan', 'narca'],
      fixedMgMin: 0.4, fixedMgMax: 2.0, unit: 'mg',
      route: 'IV/IM/IN', notes: 'Repeat q2–3 min prn'),
  _Drug(name: 'Epinephrine (anaphylaxis)', keywords: ['epi', 'epinephrine', 'anaphylaxis'],
      fixedMgMin: 0.3, unit: 'mg', route: 'IM',
      notes: '0.3 mg adult · 0.15 mg peds <30 kg'),
  _Drug(name: 'Epinephrine (cardiac arrest)', keywords: ['epi cardiac', 'epi arrest'],
      fixedMgMin: 1.0, unit: 'mg', route: 'IV', notes: '1 mg IV q3–5 min'),
  _Drug(name: 'Amiodarone', keywords: ['amiodarone'],
      fixedMgMin: 300, unit: 'mg', route: 'IV push', notes: 'VF/pVT — 300 mg'),
  _Drug(name: 'Adenosine', keywords: ['adenosine'],
      fixedMgMin: 6, fixedMgMax: 12, unit: 'mg',
      route: 'rapid IV push', notes: '6 mg × 1 → 12 mg × 2'),
  _Drug(name: 'Aspirin', keywords: ['aspirin', 'asa'],
      fixedMgMin: 324, unit: 'mg', route: 'PO chewed'),
  _Drug(name: 'Dextrose D50', keywords: ['dextrose', 'd50', 'glucose'],
      fixedMgMin: 25, unit: 'g (50 mL)', route: 'IV'),
  _Drug(name: 'Midazolam', keywords: ['midazolam', 'versed'],
      weightBased: true, mgPerKgMin: 0.1, mgPerKgMax: 0.1, unit: 'mg',
      maxDose: 5, route: 'IV/IM'),
  _Drug(name: 'Diphenhydramine', keywords: ['diphenhydramine', 'benadryl'],
      fixedMgMin: 25, fixedMgMax: 50, unit: 'mg', route: 'IV/IM'),
  _Drug(name: 'Ondansetron (Zofran)', keywords: ['ondansetron', 'zofran'],
      fixedMgMin: 4, unit: 'mg', route: 'IV/IM/ODT'),
  _Drug(name: 'TXA (Tranexamic Acid)', keywords: ['txa', 'tranexamic'],
      fixedMgMin: 1000, unit: 'mg (1 g)', route: 'IV over 10 min',
      notes: 'Within 3 hrs of injury'),
  _Drug(name: 'Atropine', keywords: ['atropine'],
      fixedMgMin: 0.5, fixedMgMax: 1.0, unit: 'mg',
      route: 'IV', notes: 'Bradycardia: 0.5–1 mg IV q3–5 min, max 3 mg'),
];

_Drug? _findDrug(String input) {
  final q = input.toLowerCase();
  for (final d in _kDrugs) {
    if (d.keywords.any((k) => q.contains(k))) return d;
  }
  return null;
}

String _formatDosing(_Drug drug, double? weightKg) {
  final buf = StringBuffer();
  buf.writeln('💊 ${drug.name}');
  if (weightKg != null) {
    buf.writeln('Patient: ${weightKg.toStringAsFixed(1)} kg');
  }
  buf.writeln('');
  if (drug.weightBased && weightKg != null) {
    double doseMin = (drug.mgPerKgMin ?? 0) * weightKg;
    double doseMax = (drug.mgPerKgMax ?? drug.mgPerKgMin ?? 0) * weightKg;
    // Special: fentanyl is mcg/kg, display in mcg
    if (drug.unit == 'mcg') {
      doseMin *= 1000; doseMax *= 1000;
    }
    if (drug.maxDose != null) {
      final max = drug.unit == 'mcg' ? drug.maxDose! * 1000 : drug.maxDose!;
      if (doseMin > max) doseMin = max;
      if (doseMax > max) doseMax = max;
    }
    final sameVal = (doseMin - doseMax).abs() < 0.05;
    buf.writeln('Route: ${drug.route}');
    buf.writeln(sameVal
        ? 'Dose: ${doseMin.toStringAsFixed(1)} ${drug.unit}'
        : 'Dose: ${doseMin.toStringAsFixed(1)} – ${doseMax.toStringAsFixed(1)} ${drug.unit}');
    if (drug.maxDose != null) {
      final maxDisp = drug.unit == 'mcg' ? drug.maxDose! * 1000 : drug.maxDose!;
      buf.writeln('Max: ${maxDisp.toStringAsFixed(0)} ${drug.unit}');
    }
  } else if (drug.fixedMgMin != null) {
    final sameVal = drug.fixedMgMax == null ||
        (drug.fixedMgMin! - drug.fixedMgMax!).abs() < 0.05;
    buf.writeln('Route: ${drug.route}');
    buf.writeln(sameVal
        ? 'Dose: ${drug.fixedMgMin!.toStringAsFixed(drug.fixedMgMin! < 1 ? 2 : 0)} ${drug.unit}'
        : 'Dose: ${drug.fixedMgMin!.toStringAsFixed(0)} – ${drug.fixedMgMax!.toStringAsFixed(0)} ${drug.unit}');
  }
  if (drug.notes.isNotEmpty) buf.writeln('ℹ️ ${drug.notes}');
  buf.write('\n⚠️ Confirm with medical direction and local protocols.');
  return buf.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// PROTOCOL KEYWORD MAP
// ═══════════════════════════════════════════════════════════════════════════

const _kProtocolMap = <String, List<String>>{
  'Needle Decompression Protocol':
      ['tension pneumo', 'pneumothorax', 'needle decompression', 'chest needle', 'ptx'],
  'Chest Wound Protocol':
      ['chest seal', 'sucking chest wound', 'open chest', 'occlusive dressing'],
  'Hemorrhage Control Protocol':
      ['tourniquet', 'hemorrhage', 'bleeding', 'massive bleed', 'junctional', 'wound packing'],
  'Airway Management Protocol':
      ['airway', 'intubation', 'rsi', 'rapid sequence', 'cric', 'cricothyrotomy',
       'supraglottic', 'igel', 'bvm', 'bag valve', 'obstruction', 'choking'],
  'Environmental Emergencies Protocol':
      ['hypothermia', 'cold exposure', 'frostbite', 'heat stroke', 'hyperthermia',
       'heat exhaustion', 'environmental'],
  'Crush Injury Protocol':
      ['crush', 'crush syndrome', 'compartment', 'rhabdomyolysis'],
  'Burn Management Protocol':
      ['burn', 'burns', 'thermal injury', 'chemical burn', 'inhalation'],
  'Seizure Protocol':
      ['seizure', 'convulsion', 'status epilepticus', 'tonic clonic'],
  'Stroke Protocol':
      ['stroke', 'cva', 'tia', 'facial droop', 'slurred speech', 'cincinnati'],
  'Anaphylaxis Protocol':
      ['anaphylaxis', 'anaphylactic', 'allergic reaction', 'angioedema', 'hives urticaria'],
  'Overdose Protocol':
      ['overdose', 'narcan', 'opioid', 'toxicology', 'ingestion', 'toxic ingestion',
       'polypharmacy', 'opiate'],
  'MCI Triage Protocol':
      ['triage', 'mci', 'mass casualty', 'start triage', 'salt triage', 'multiple patient'],
  'Firefighter Rehab Protocol':
      ['rehab', 'firefighter rehab', 'fire rehab', 'rehab sector'],
  'Altitude Illness Protocol':
      ['hace', 'hape', 'altitude', 'altitude sickness', 'ams', 'acute mountain'],
  'Cardiac Arrest Protocol':
      ['cardiac arrest', 'code', 'cpr', 'acls', 'vfib', 'vf pulseless', 'pea', 'asystole'],
  'Chest Pain Protocol':
      ['chest pain', 'stemi', 'acs', 'mi', 'heart attack', 'angina', 'nstemi'],
  'Diabetic Emergency Protocol':
      ['diabetic', 'hypoglycemia', 'hyperglycemia', 'low blood sugar', 'dka',
       'glucose', 'insulin'],
  'Altered Mental Status Protocol':
      ['altered mental', 'ams', 'confused', 'unconscious', 'unresponsive', 'gcs'],
  'Obstetric Emergency Protocol':
      ['delivery', 'birth', 'labor', 'obstetric', 'pregnant', 'eclampsia', 'preeclampsia'],
  'Drowning Protocol':
      ['drowning', 'submersion', 'near drowning'],
  'Spinal Restriction Protocol':
      ['spinal', 'c-spine', 'c spine', 'cervical', 'smr', 'spinal restriction'],
  'Sepsis Protocol':
      ['sepsis', 'septic', 'infection', 'meningitis', 'fever protocol'],
};

String _protocolSummary(String protocolName) {
  const summaries = <String, String>{
    'Needle Decompression Protocol':
        'Indicated for tension pneumothorax. Second ICS MCL or 4th/5th ICS AAL. '
        '14g or 10g needle. Confirm rush of air. Monitor for recurrence.',
    'Hemorrhage Control Protocol':
        'MARCH: Massive hemorrhage first. Apply tourniquet 2–3" above wound. '
        'Tighten until bleeding stops. Document time. Wound pack junctional bleeds.',
    'Airway Management Protocol':
        'BVM first. Consider OPA/NPA. iGel/Supraglottic if BVM inadequate. '
        'RSI with ketamine + succinylcholine/rocuronium if available. Surgical cric as last resort.',
    'Seizure Protocol':
        'Protect patient. Midazolam 0.1 mg/kg IM/IV (max 5 mg). '
        'Repeat × 1 if seizure continues. Check glucose. Transport.',
    'Anaphylaxis Protocol':
        'Epinephrine 0.3 mg IM (lateral thigh) immediately. '
        'Repeat q5–15 min × 2 if no improvement. Diphenhydramine + methylprednisolone. '
        'Establish IV. Prepare for airway compromise.',
    'Overdose Protocol':
        'Naloxone 0.4–2 mg IV/IM/IN. Titrate to adequate respirations (not full reversal). '
        'Repeat q2–3 min. Consider infusion for long-acting opioids.',
    'Cardiac Arrest Protocol':
        'High-quality CPR 30:2. Defibrillate VF/pVT immediately (200J biphasic). '
        'Epinephrine 1 mg IV q3–5 min. Amiodarone 300 mg VF/pVT. Treat reversible causes (H&T).',
    'MCI Triage Protocol':
        'START: Walking → Green. Not breathing (after airway) → Black. '
        'RR >30 or <10 → Red. No radial pulse → Red. '
        'Cannot follow commands → Red. Otherwise → Yellow.',
  };
  return summaries[protocolName] ??
      'Protocol: $protocolName\n\nOpen the Protocols section in the Med tab for full details and PDF.';
}

Map<String, List<String>> _matchProtocols(String input) {
  final q = input.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ');
  final matches = <String, List<String>>{};
  for (final entry in _kProtocolMap.entries) {
    final hitKws = entry.value.where((kw) => q.contains(kw)).toList();
    if (hitKws.isNotEmpty) matches[entry.key] = hitKws;
  }
  return matches;
}

// ═══════════════════════════════════════════════════════════════════════════
// DEFAULT QUICK REPLIES
// ═══════════════════════════════════════════════════════════════════════════

const _kDefaultReplies = <QuickReply>[
  QuickReply('Protocol Lookup',     'protocol lookup',      icon: Icons.menu_book_outlined),
  QuickReply('Drug Dose Calc',      'drug dose calculator', icon: Icons.medication_outlined),
  QuickReply('Cert Status',         'check cert status',    icon: Icons.workspace_premium_outlined),
  QuickReply('Team Availability',   'who is available',     icon: Icons.people_outlined),
  QuickReply('Active Deployments',  'deployment status',    icon: Icons.assignment_outlined),
  QuickReply('Run Triage',          'run triage',           icon: Icons.emergency_outlined),
];

const _kYesNoReplies = <QuickReply>[
  QuickReply('Yes ✅', 'yes'),
  QuickReply('No ❌',  'no'),
  QuickReply('Stop Triage', 'stop triage', icon: Icons.stop_circle_outlined),
];

// ═══════════════════════════════════════════════════════════════════════════
// CHAT INTENT ENGINE
// ═══════════════════════════════════════════════════════════════════════════

class ChatIntentEngine {
  final _Session _s = _Session();

  Future<ChatResponse> processInput(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return _fallback();

    final q = input.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ');

    // ── Triage flow (intercept YES/NO while triage is active) ──────────────
    if (_s.triageActive) {
      if (q.contains('stop') || q.contains('cancel') || q.contains('exit')) {
        _s.clearTriage();
        return ChatResponse(
          responseText: 'Triage stopped. How else can I help?',
          suggestions: _kDefaultReplies,
        );
      }
      final isYes = q.contains('yes') || q == 'y';
      final isNo  = q.contains('no')  || q == 'n';
      if (isYes || isNo) return _stepTriage(isYes);
    }

    // ── Follow-up: pending drug name, user just sends a weight ────────────
    if (_s.pendingDrugName != null &&
        RegExp(r'^\s*\d+(\.\d+)?\s*(kg|lb|lbs|pound)?\s*$').hasMatch(input)) {
      return _handleDosingWeight(input);
    }

    // ── Intent detection ───────────────────────────────────────────────────
    if (_matchesAny(q, ['protocol', 'procedure', 'how do i', 'how to', 'treat', 'treatment',
                          'manage', 'management', 'steps for', 'guide for'])) {
      _s.lastIntent = 'protocol';
      return _handleProtocol(q);
    }

    if (_matchesAny(q, ['dose', 'dosing', 'how much', ' mg', ' mcg', 'drip',
                          'medication', 'give me', 'administer', 'drug calc',
                          'drug dose', 'calculate'])) {
      _s.lastIntent = 'dosing';
      return _handleDosing(input, q);
    }

    if (_matchesAny(q, ['cert', 'certification', 'expired', 'expiring',
                          'valid', 'credential', 'who is certified', 'license'])) {
      _s.lastIntent = 'certs';
      return _handleCerts(q);
    }

    if (_matchesAny(q, ['available', 'on duty', 'off duty', 'team status',
                          "who's on", 'whos on', 'staffing', 'who is available',
                          'available now', 'team availability'])) {
      _s.lastIntent = 'team';
      return _handleTeam();
    }

    if (_matchesAny(q, ['deployment', 'deployed', 'mission', 'order', 'active op',
                          'current op', 'active mission', 'where is', 'active deployment'])) {
      _s.lastIntent = 'deployments';
      return _handleDeployments();
    }

    if (_matchesAny(q, ['triage', 'start triage', 'salt', 'mci', 'mass casualty',
                          'prioritize', 'tag', 'run triage'])) {
      _s.lastIntent = 'triage';
      return _startTriage();
    }

    if (_matchesAny(q, ['help', 'what can', 'commands', 'options', 'hi', 'hello', 'hey'])) {
      return _helpResponse();
    }

    // Last-resort follow-up: if last intent was dosing, try as weight
    if (_s.lastIntent == 'dosing' && _s.pendingDrugName != null) {
      return _handleDosingWeight(input);
    }

    return _fallback();
  }

  // ── Protocol ──────────────────────────────────────────────────────────────
  ChatResponse _handleProtocol(String q) {
    final matches = _matchProtocols(q);
    if (matches.isEmpty) {
      return ChatResponse(
        responseText: 'I couldn\'t find a protocol for that.\n\n'
            'Try a keyword like: airway, hemorrhage, cardiac arrest, seizure, '
            'anaphylaxis, overdose, burns, triage.\n\n'
            'Or open the Protocols section in the Med tab to search manually.',
        suggestions: [
          const QuickReply('Airway Protocol', 'airway protocol'),
          const QuickReply('Hemorrhage Control', 'hemorrhage protocol'),
          const QuickReply('Cardiac Arrest', 'cardiac arrest protocol'),
          const QuickReply('Seizure Protocol', 'seizure protocol'),
          ..._kDefaultReplies.take(2),
        ],
      );
    }

    if (matches.length == 1) {
      final name = matches.keys.first;
      _s.lastProtocolViewed = name;
      return ChatResponse(
        responseText: '📋 $name\n\n${_protocolSummary(name)}\n\n'
            'Open the Protocols tab for the full PDF.',
        suggestions: [
          QuickReply('More about $name', 'more about $name'),
          ..._kDefaultReplies.take(3),
        ],
      );
    }

    final list = matches.keys.map((k) => '• $k').join('\n');
    return ChatResponse(
      responseText: '📋 Found ${matches.length} matching protocols:\n\n$list\n\n'
          'Tap one for details:',
      suggestions: [
        ...matches.keys.take(5).map((n) => QuickReply(
              n.replaceAll(' Protocol', ''),
              'tell me about $n',
            )),
      ],
    );
  }

  // ── Drug dosing ───────────────────────────────────────────────────────────
  ChatResponse _handleDosing(String raw, String q) {
    final drug = _findDrug(q);
    if (drug == null) {
      return ChatResponse(
        responseText: 'Which drug? Try: ketamine, fentanyl, morphine, naloxone, '
            'epi, amiodarone, adenosine, midazolam, TXA, aspirin, dextrose, '
            'diphenhydramine, ondansetron.',
        suggestions: [
          const QuickReply('Ketamine dose',   'ketamine dose 70 kg'),
          const QuickReply('Fentanyl dose',   'fentanyl dose 70 kg'),
          const QuickReply('Naloxone dose',   'naloxone dose'),
          const QuickReply('Epi (anaphylax)', 'epinephrine anaphylaxis'),
          ..._kDefaultReplies.take(2),
        ],
      );
    }

    if (!drug.weightBased) {
      _s.clearDrug();
      return ChatResponse(
        responseText: _formatDosing(drug, null),
        suggestions: _kDefaultReplies,
      );
    }

    final weight = _parseWeight(raw);
    if (weight != null) {
      _s.patientWeightKg = weight;
      _s.clearDrug();
      return ChatResponse(
        responseText: _formatDosing(drug, weight),
        suggestions: _kDefaultReplies,
      );
    }

    // Need weight
    _s.pendingDrugName = drug.name;
    return ChatResponse(
      responseText: '${drug.name} is weight-based.\n\nWhat is the patient\'s weight? '
          '(e.g. "70 kg" or "154 lbs")',
      suggestions: [
        const QuickReply('50 kg',  '50 kg'),
        const QuickReply('70 kg',  '70 kg'),
        const QuickReply('90 kg',  '90 kg'),
        const QuickReply('100 kg', '100 kg'),
      ],
    );
  }

  ChatResponse _handleDosingWeight(String raw) {
    final weight = _parseWeight(raw);
    final drugName = _s.pendingDrugName;
    _s.clearDrug();
    if (weight == null) {
      return ChatResponse(
        responseText: 'I couldn\'t parse that weight. Try "70 kg" or "154 lbs".',
        suggestions: _kDefaultReplies,
      );
    }
    _s.patientWeightKg = weight;
    if (drugName == null) {
      return ChatResponse(
        responseText: 'Weight saved: ${weight.toStringAsFixed(1)} kg.\n\n'
            'Which drug dose would you like?',
        suggestions: [
          const QuickReply('Ketamine', 'ketamine dose'),
          const QuickReply('Fentanyl', 'fentanyl dose'),
          ..._kDefaultReplies.take(2),
        ],
      );
    }
    final drug = _kDrugs.firstWhere((d) => d.name == drugName,
        orElse: () => _kDrugs.first);
    return ChatResponse(
      responseText: _formatDosing(drug, weight),
      suggestions: _kDefaultReplies,
    );
  }

  // ── Cert check ────────────────────────────────────────────────────────────
  Future<ChatResponse> _handleCerts(String q) async {
    try {
      final ok = await SupabaseService.ensureInitialized();
      if (!ok) {
        return ChatResponse(
          responseText: '⚠️ Cert data requires a Supabase connection.',
          suggestions: _kDefaultReplies,
        );
      }
      final client = SupabaseService.client!;
      final rows = await client
          .from('team_certs')
          .select('user_id, callsign, license_type, state, expiration_date')
          .order('callsign') as List;

      if (rows.isEmpty) {
        return ChatResponse(
          responseText: '🏅 No certifications found.\n\nHave team members sync their certs via the Certs tab.',
          suggestions: _kDefaultReplies,
        );
      }

      final now = DateTime.now();
      final filtered = rows.where((r) {
        if (q.contains('expired') && !q.contains('expiring')) {
          final exp = DateTime.tryParse(r['expiration_date'] as String? ?? '');
          return exp != null && exp.isBefore(now);
        }
        if (q.contains('expiring') || q.contains('soon')) {
          final exp = DateTime.tryParse(r['expiration_date'] as String? ?? '');
          return exp != null && exp.difference(now).inDays <= 30 && exp.isAfter(now);
        }
        return true;
      }).toList();

      final headers = ['Name', 'Cert', 'State', 'Expires', 'Status'];
      final data = filtered.map((r) {
        final expStr = r['expiration_date'] as String?;
        final exp = expStr != null ? DateTime.tryParse(expStr) : null;
        final days = exp?.difference(now).inDays;
        final status = exp == null ? '—'
            : days! < 0 ? '🔴 Expired'
            : days <= 30 ? '🟡 <30 days'
            : '✅ Valid';
        final expDisplay = exp != null
            ? '${exp.month}/${exp.day}/${exp.year}'
            : 'No date';
        return [
          r['callsign'] as String? ?? 'Unknown',
          r['license_type'] as String? ?? '',
          r['state'] as String? ?? '',
          expDisplay,
          status,
        ];
      }).toList();

      final expiredCount = filtered.where((r) {
        final exp = DateTime.tryParse(r['expiration_date'] as String? ?? '');
        return exp != null && exp.isBefore(now);
      }).length;
      final soonCount = filtered.where((r) {
        final exp = DateTime.tryParse(r['expiration_date'] as String? ?? '');
        return exp != null && exp.difference(now).inDays <= 30 && exp.isAfter(now);
      }).length;

      final summary = '🏅 ${filtered.length} certification${filtered.length == 1 ? '' : 's'}'
          '${expiredCount > 0 ? " · 🔴 $expiredCount expired" : ""}'
          '${soonCount > 0 ? " · 🟡 $soonCount expiring soon" : ""}';

      return ChatResponse(
        responseText: summary,
        widgetType: _WidgetType.table,
        tableHeaders: headers,
        tableData: data,
        suggestions: [
          const QuickReply('Show expired',      'show expired certs'),
          const QuickReply('Expiring soon',     'show expiring certs'),
          ..._kDefaultReplies.take(2),
        ],
      );
    } catch (e) {
      return ChatResponse(
        responseText: '⚠️ Could not load certs: $e',
        suggestions: _kDefaultReplies,
      );
    }
  }

  // ── Team availability ─────────────────────────────────────────────────────
  Future<ChatResponse> _handleTeam() async {
    try {
      final ok = await SupabaseService.ensureInitialized();
      if (!ok) {
        return ChatResponse(
          responseText: '⚠️ Team data requires a Supabase connection.',
          suggestions: _kDefaultReplies,
        );
      }
      final client = SupabaseService.client!;
      final today = DateTime.now();
      final dateStr = '${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';

      final profiles = await client
          .from('user_profiles')
          .select('user_id, name, callsign, cert_level')
          .order('name') as List;
      final avail = await client
          .from('team_availability')
          .select('user_id, status')
          .eq('date', dateStr) as List;
      final statusMap = {for (final r in avail) r['user_id'] as String: r['status'] as String};

      if (profiles.isEmpty) {
        return ChatResponse(
          responseText: '👥 No team profiles found.\n\nUsers appear after logging in.',
          suggestions: _kDefaultReplies,
        );
      }

      final headers = ['Name', 'Callsign', 'Cert', 'Status'];
      final data = profiles.map((p) {
        final uid = p['user_id'] as String;
        final status = statusMap[uid] ?? 'Available';
        final statusEmoji = status == 'Deployed' ? '🚁 Deployed'
            : status == 'Unavailable' ? '⭕ Off-Duty'
            : '✅ Available';
        return [
          p['name'] as String? ?? '',
          p['callsign'] as String? ?? '—',
          p['cert_level'] as String? ?? '—',
          statusEmoji,
        ];
      }).toList();

      final available = data.where((r) => r[3].contains('Available')).length;
      final deployed  = data.where((r) => r[3].contains('Deployed')).length;
      final offDuty   = data.where((r) => r[3].contains('Off')).length;

      return ChatResponse(
        responseText: '👥 Team status for today:\n✅ $available available  🚁 $deployed deployed  ⭕ $offDuty off-duty',
        widgetType: _WidgetType.table,
        tableHeaders: headers,
        tableData: data,
        suggestions: _kDefaultReplies,
      );
    } catch (e) {
      return ChatResponse(
        responseText: '⚠️ Could not load team data: $e',
        suggestions: _kDefaultReplies,
      );
    }
  }

  // ── Deployment status ─────────────────────────────────────────────────────
  Future<ChatResponse> _handleDeployments() async {
    try {
      final ok = await SupabaseService.ensureInitialized();
      if (!ok) {
        return ChatResponse(
          responseText: '⚠️ Deployment data requires a Supabase connection.',
          suggestions: _kDefaultReplies,
        );
      }
      final client = SupabaseService.client!;
      final orders = await client
          .from('deployment_orders')
          .select('id, title, uploaded_at, uploaded_by, notes')
          .order('uploaded_at', ascending: false)
          .limit(10) as List;

      if (orders.isEmpty) {
        return ChatResponse(
          responseText: '📋 No active deployments at this time.',
          suggestions: _kDefaultReplies,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('tac_user_id') ?? '';
      List<String> viewedIds = [];
      if (userId.isNotEmpty) {
        try {
          final views = await client
              .from('deployment_order_views')
              .select('order_id')
              .eq('user_id', userId) as List;
          viewedIds = views.map((v) => v['order_id'] as String).toList();
        } catch (_) {}
      }

      final headers = ['Title', 'By', 'Date', 'Status'];
      final data = orders.map((o) {
        final id = o['id'] as String;
        final dt = DateTime.tryParse(o['uploaded_at'] as String? ?? '');
        final dateDisp = dt != null ? '${dt.month}/${dt.day}' : '—';
        return [
          o['title'] as String? ?? 'Untitled',
          o['uploaded_by'] as String? ?? 'Admin',
          dateDisp,
          viewedIds.contains(id) ? '✅ Read' : '🔴 Unread',
        ];
      }).toList();

      final unread = data.where((r) => r[3].contains('Unread')).length;
      return ChatResponse(
        responseText: '📋 ${orders.length} deployment order${orders.length == 1 ? '' : 's'}'
            '${unread > 0 ? " · 🔴 $unread unread" : " · all read"}',
        widgetType: _WidgetType.table,
        tableHeaders: headers,
        tableData: data,
        suggestions: _kDefaultReplies,
      );
    } catch (e) {
      return ChatResponse(
        responseText: '⚠️ Could not load deployments: $e',
        suggestions: _kDefaultReplies,
      );
    }
  }

  // ── Triage decision tree ──────────────────────────────────────────────────
  ChatResponse _startTriage() {
    _s.triageActive = true;
    _s.triageStep = 0;
    _s.triageContext = '';
    return ChatResponse(
      responseText: '🚨 Starting START Triage\n\nSTEP 1 / 5\nIs the patient WALKING?',
      suggestions: _kYesNoReplies,
    );
  }

  ChatResponse _stepTriage(bool yes) {
    switch (_s.triageStep) {
      case 0: // Walking?
        if (yes) {
          _s.clearTriage();
          return ChatResponse(
            responseText: '🟢 GREEN — Minor\nPatient is ambulatory. '
                'Assign to green (minor) treatment area and reassess.',
            suggestions: _kDefaultReplies,
          );
        }
        _s.triageStep = 1;
        return ChatResponse(
          responseText: 'STEP 2 / 5\nOpen the airway (head-tilt or jaw-thrust).\n\nIs the patient NOW BREATHING?',
          suggestions: _kYesNoReplies,
        );

      case 1: // Breathing after airway?
        if (!yes) {
          _s.clearTriage();
          return ChatResponse(
            responseText: '⚫ BLACK — Expectant\nNo breathing even after airway opening. '
                'Do not expend resources. Move to expectant area.',
            suggestions: _kDefaultReplies,
          );
        }
        _s.triageStep = 2;
        return ChatResponse(
          responseText: 'STEP 3 / 5\nIs the RESPIRATORY RATE greater than 30 or less than 10 breaths/min?',
          suggestions: _kYesNoReplies,
        );

      case 2: // Resp rate abnormal?
        if (yes) {
          _s.clearTriage();
          return ChatResponse(
            responseText: '🔴 RED — Immediate\nAbnormal respiratory rate (>30 or <10). '
                'Requires immediate life-saving intervention.',
            suggestions: _kDefaultReplies,
          );
        }
        _s.triageStep = 3;
        return ChatResponse(
          responseText: 'STEP 4 / 5\nIs the RADIAL PULSE present?',
          suggestions: _kYesNoReplies,
        );

      case 3: // Radial pulse?
        if (!yes) {
          _s.clearTriage();
          return ChatResponse(
            responseText: '🔴 RED — Immediate\nNo radial pulse — likely shock. '
                'Requires immediate hemorrhage control and vascular access.',
            suggestions: _kDefaultReplies,
          );
        }
        _s.triageStep = 4;
        return ChatResponse(
          responseText: 'STEP 5 / 5\nCan the patient FOLLOW SIMPLE COMMANDS?\n(e.g. "Squeeze my hand")',
          suggestions: _kYesNoReplies,
        );

      case 4: // Mental status / follows commands?
        _s.clearTriage();
        if (!yes) {
          return ChatResponse(
            responseText: '🔴 RED — Immediate\nAbnormal mental status. '
                'Cannot follow commands — critical neurological status.',
            suggestions: _kDefaultReplies,
          );
        }
        return ChatResponse(
          responseText: '🟡 YELLOW — Delayed\nPatient is breathing, has a pulse, and can follow commands. '
                'Stable enough to wait — reassess frequently.',
          suggestions: _kDefaultReplies,
        );

      default:
        _s.clearTriage();
        return _fallback();
    }
  }

  // ── Help / fallback ───────────────────────────────────────────────────────
  ChatResponse _helpResponse() => ChatResponse(
        responseText: '👋 Hi! I\'m your ResQruck assistant.\n\n'
            'I can help with:\n'
            '📋 Protocol lookup — "airway protocol"\n'
            '💊 Drug dosing — "ketamine dose 70 kg"\n'
            '🏅 Cert status — "who has expired certs"\n'
            '👥 Team status — "who is available today"\n'
            '📋 Deployments — "show active orders"\n'
            '🚨 Triage — "run triage"\n\n'
            'All protocol and dosing queries work offline.',
        suggestions: _kDefaultReplies,
      );

  ChatResponse _fallback() => ChatResponse(
        responseText: 'I didn\'t understand that. Here\'s what I can help with:',
        suggestions: _kDefaultReplies,
      );

  // ── Utilities ─────────────────────────────────────────────────────────────
  bool _matchesAny(String q, List<String> kws) => kws.any((k) => q.contains(k));

  double? _parseWeight(String raw) {
    final q = raw.toLowerCase();
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|kgs|kilo|lb|lbs|pound)?')
        .allMatches(q)
        .where((x) {
          final n = double.tryParse(x.group(1)!);
          return n != null && n > 5 && n < 500;
        })
        .firstOrNull;
    if (m == null) return null;
    final w = double.parse(m.group(1)!);
    final isLbs = m.group(2)?.startsWith('l') ?? q.contains('lb') || q.contains('pound');
    return isLbs ? w * 0.4536 : w;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE MODEL (internal UI)
// ═══════════════════════════════════════════════════════════════════════════

class _Msg {
  final bool isUser;
  final String text;
  final bool isLoading;
  final List<List<String>>? tableData;
  final List<String>? tableHeaders;

  _Msg.user(this.text)
      : isUser = true, isLoading = false, tableData = null, tableHeaders = null;
  _Msg.bot(this.text, {this.tableData, this.tableHeaders})
      : isUser = false, isLoading = false;
  _Msg.loading()
      : isUser = false, text = '', isLoading = true, tableData = null, tableHeaders = null;

  bool get hasTable => tableData != null && tableHeaders != null;
}

// ═══════════════════════════════════════════════════════════════════════════
// ASSISTANT BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════

class ResQruckAssistantSheet extends StatefulWidget {
  const ResQruckAssistantSheet({super.key});

  @override
  State<ResQruckAssistantSheet> createState() => _ResQruckAssistantSheetState();
}

class _ResQruckAssistantSheetState extends State<ResQruckAssistantSheet> {
  final _engine = ChatIntentEngine();
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _msgs   = <_Msg>[];
  List<QuickReply> _currentReplies = _kDefaultReplies;
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    _msgs.add(_Msg.bot(
      'Hi! I\'m your ResQruck assistant 🤖\n\n'
      'I can look up protocols, calculate drug doses, '
      'check cert status, review team availability, '
      'and show deployment orders.\n\n'
      'Tap a quick command or type your question.',
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    final input = raw.trim();
    if (input.isEmpty || _waiting) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(_Msg.user(input));
      _msgs.add(_Msg.loading());
      _waiting = true;
    });
    _scrollBottom();

    final response = await _engine.processInput(input);

    if (!mounted) return;
    setState(() {
      _msgs.removeLast();
      _msgs.add(_Msg.bot(
        response.responseText,
        tableData: response.tableData,
        tableHeaders: response.tableHeaders,
      ));
      _currentReplies = response.suggestions.isEmpty ? _kDefaultReplies : response.suggestions;
      _waiting = false;
    });
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sheetCtrl) => Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.primary,
              child: const Icon(Icons.health_and_safety, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ResQruck Assistant',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                        color: cs.onSurface)),
                Text('Protocols · Dosing · Team · Certs · Orders · Triage',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            )),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),

        // ── Quick replies ────────────────────────────────────────────────────
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _currentReplies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final r = _currentReplies[i];
              return ActionChip(
                avatar: r.icon != null ? Icon(r.icon!, size: 14) : null,
                label: Text(r.label, style: const TextStyle(fontSize: 12)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => _send(r.prompt),
              );
            },
          ),
        ),
        const Divider(height: 1),

        // ── Messages ─────────────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            controller: sheetCtrl,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            itemCount: _msgs.length,
            itemBuilder: (_, i) => _buildBubble(_msgs[i], cs),
          ),
        ),

        // ── Input ─────────────────────────────────────────────────────────────
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  enabled: !_waiting,
                  decoration: InputDecoration(
                    hintText: 'Ask about protocols, dosing, team…',
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: _waiting ? null : () => _send(_ctrl.text),
                icon: Icon(Icons.send_rounded,
                    color: _waiting ? cs.outlineVariant : cs.primary),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildBubble(_Msg msg, ColorScheme cs) {
    if (msg.isLoading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
            const SizedBox(width: 8),
            Text('Thinking…', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ]),
        ),
      );
    }

    final isUser = msg.isUser;

    // Table message
    if (!isUser && msg.hasTable) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Text summary bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(msg.text,
                style: TextStyle(fontSize: 13, color: cs.onSurface, height: 1.4)),
          ),
          const SizedBox(height: 6),
          // Table card
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 44,
                columnSpacing: 16,
                headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12, color: cs.primary),
                dataTextStyle: const TextStyle(fontSize: 12),
                columns: msg.tableHeaders!
                    .map((h) => DataColumn(label: Text(h)))
                    .toList(),
                rows: msg.tableData!
                    .map((row) => DataRow(
                          cells: row.map((cell) => DataCell(Text(cell))).toList(),
                        ))
                    .toList(),
              ),
            ),
          ),
        ]),
      );
    }

    // Regular text bubble
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.83),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          msg.text,
          style: TextStyle(
            fontSize: 13,
            color: isUser ? cs.onPrimary : cs.onSurface,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOATING ACTION BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class AssistantFab extends StatelessWidget {
  const AssistantFab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton(
      heroTag: 'assistant_fab',
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => const ResQruckAssistantSheet(),
      ),
      tooltip: 'ResQruck Assistant',
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      child: const Icon(Icons.health_and_safety_outlined, size: 26),
    );
  }
}
