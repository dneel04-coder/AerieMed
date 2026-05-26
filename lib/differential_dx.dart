import 'package:flutter/material.dart';

// ── Data Model ────────────────────────────────────────────────────────────────

class DxCondition {
  final String name;
  final String category;
  final String severity;
  final List<String> symptoms;
  final List<String> signs;
  final List<String> diagnostics;
  final List<String> treatment;
  final String? pitfalls;
  final Color color;
  const DxCondition({
    required this.name,
    required this.category,
    required this.severity,
    required this.symptoms,
    required this.signs,
    required this.diagnostics,
    required this.treatment,
    this.pitfalls,
    required this.color,
  });
}

// ── Static Data ───────────────────────────────────────────────────────────────

const List<DxCondition> kConditions = [
  // ── Altitude Illness ──────────────────────────────────────────────────────
  DxCondition(
    name: 'Acute Mountain Sickness (AMS)',
    category: 'Altitude Illness',
    severity: 'Mild–Moderate',
    symptoms: ['Headache (cardinal symptom, >2500m)', 'Fatigue / weakness', 'Nausea ± vomiting', 'Dizziness / light-headedness', 'Insomnia'],
    signs: ['No focal neurological deficits', 'Normal oxygen saturation (relative to altitude)', 'Lake Louise Score ≥3'],
    diagnostics: ['Clinical diagnosis', 'Lake Louise Score (headache + ≥1 symptom = AMS)', 'SpO₂ (low but non-specific)'],
    treatment: ['STOP ascent — do NOT ascend further', 'Descend 300–500m if not improving within 24 hrs', 'Ibuprofen 600 mg q8h OR Acetaminophen 1000 mg q6h for headache', 'Acetazolamide (Diamox) 250 mg PO BID — accelerates acclimatisation', 'Dexamethasone 4 mg PO q6h for symptom relief (does NOT acclimatise)', 'Supplemental O₂ 1–2 L/min if available', 'Hydration — avoid alcohol/sedatives'],
    pitfalls: 'AMS can progress to HACE within hours. Reassess every 4–6 hours. Any worsening neurological symptoms = HACE until proven otherwise. Never ascend with AMS.',
    color: Color(0xFF1565C0),
  ),
  DxCondition(
    name: 'High Altitude Cerebral Oedema (HACE)',
    category: 'Altitude Illness',
    severity: 'LIFE-THREATENING',
    symptoms: ['Severe headache unresponsive to analgesia', 'Confusion / altered mental status', 'Ataxia (stumbling — hallmark sign)', 'Progressive loss of consciousness'],
    signs: ['Ataxia on tandem gait test (cannot walk heel-to-toe)', 'Altered LOC — confusion, drowsiness, stupor', 'Papilloedema (late)', 'Retinal haemorrhages'],
    diagnostics: ['Clinical diagnosis — DO NOT delay descent for diagnostics', 'MRI: T2 white matter oedema (if available)'],
    treatment: ['IMMEDIATE DESCENT — minimum 300–500 m, more if possible', 'Dexamethasone 8 mg IV/IM/PO loading, then 4 mg q6h', 'Supplemental O₂ 4–6 L/min by NRB mask', 'Gamow Bag (portable hyperbaric chamber) if descent impossible', 'Airway protection if unconscious', 'Evacuation to hospital — ICU care may be required'],
    pitfalls: 'HACE is fatal if not treated. Descend FIRST — medications are adjuncts. The Gamow Bag buys time but is NOT a substitute for descent. Any ataxia at altitude = HACE until proven otherwise.',
    color: Color(0xFFD32F2F),
  ),
  DxCondition(
    name: 'High Altitude Pulmonary Oedema (HAPE)',
    category: 'Altitude Illness',
    severity: 'LIFE-THREATENING',
    symptoms: ['Decreased exercise tolerance', 'Dry cough progressing to productive (pink frothy sputum)', 'Dyspnoea at rest', 'Extreme fatigue'],
    signs: ['Cyanosis', 'Tachycardia (HR >100)', 'Tachypnoea (RR >20)', 'Crackles (bilateral, initially basal)', 'SpO₂ markedly low for altitude'],
    diagnostics: ['Clinical diagnosis', 'Chest X-ray: bilateral patchy infiltrates (if available)', 'SpO₂ disproportionately low vs. peers at same altitude'],
    treatment: ['IMMEDIATE DESCENT — most effective treatment', 'Supplemental O₂ 4–8 L/min by NRB mask (target SpO₂ >90%)', 'Nifedipine 30 mg SR PO then 30 mg q12h (pulmonary vasodilator)', 'Tadalafil 10 mg BID or Sildenafil 50 mg q8h (if Nifedipine unavailable)', 'Dexamethasone 8 mg loading dose (adjunct)', 'Gamow Bag if descent not possible', 'Portable altitude chamber 2–4 psi × 1–2 hrs'],
    pitfalls: 'HAPE is the most common cause of altitude-related death. Occurs without preceding AMS. Most cases respond dramatically to O₂ alone — but do not delay descent.',
    color: Color(0xFFD32F2F),
  ),

  // ── Environmental ────────────────────────────────────────────────────────
  DxCondition(
    name: 'Mild / Moderate Hypothermia',
    category: 'Environmental',
    severity: 'Mild: 32–35°C | Moderate: 28–32°C',
    symptoms: ['Shivering (present in mild, absent in moderate)', 'Slurred speech', 'Impaired judgement / confusion', 'Stumbling / incoordination'],
    signs: ['Core temperature <35°C (95°F)', 'Tachycardia → bradycardia as cools', 'Decreased level of consciousness', 'Skin: cool, pale, possible cyanosis'],
    diagnostics: ['Low-reading thermometer (rectal preferred)', 'ECG: Osborne (J) waves, bradyarrhythmias', 'BGL (hypoglycaemia common)', 'Monitor for VF'],
    treatment: ['Remove wet clothing — insulate from ground first', 'Passive rewarming: sleeping bag, blankets, dry environment', 'Active external rewarming: warm packs to axillae/groin/neck', 'Warm humidified O₂', 'Warm IV fluids (40–42°C) — avoid cold fluids', 'High-calorie food/drink if conscious and able to swallow', 'Gentle handling — rough movement can precipitate VF', 'Avoid alcohol'],
    pitfalls: 'Paradoxical undressing (patient removes clothing — thinks they are warm) = severe hypothermia sign. "Not dead until warm and dead" — CPR and resuscitation until core temp >32°C.',
    color: Color(0xFF1565C0),
  ),
  DxCondition(
    name: 'Severe Hypothermia',
    category: 'Environmental',
    severity: 'LIFE-THREATENING (<28°C)',
    symptoms: ['Unconscious or minimally responsive', 'No shivering', 'Rigid muscles'],
    signs: ['Core temperature <28°C', 'Bradycardia or absent pulse', 'Slow/absent respirations', 'Fixed dilated pupils (do NOT use to diagnose death)', 'VF or asystole on ECG'],
    diagnostics: ['Low-reading thermometer', 'ECG continuously', 'Full labs when available'],
    treatment: ['CPR — check pulse for 60 seconds before starting (bradycardia may be present)', 'Minimise all movement — VF risk', 'Do NOT defibrillate if <30°C (ineffective) — continue CPR', 'Core active rewarming: warm IV fluids, warm humidified O₂', 'ECMO / cardiopulmonary bypass at definitive care (best outcome)', 'Do not pronounce dead until rewarmed to ≥32°C and no ROSC', 'Evacuate immediately'],
    pitfalls: '"Not dead until warm and dead." ECMO has resulted in neurologically intact survival from core temp as low as 13.7°C. Continue resuscitation until hospital rewarming.',
    color: Color(0xFFD32F2F),
  ),
  DxCondition(
    name: 'Heat Stroke',
    category: 'Environmental',
    severity: 'LIFE-THREATENING',
    symptoms: ['Altered mental status / confusion / seizures', 'Hot, red, DRY skin (classic) or wet skin (exertional)', 'Nausea / vomiting'],
    signs: ['Core temperature >40°C (104°F)', 'AMS — ranges from confusion to coma', 'Anhidrosis (classic) or diaphoresis (exertional)', 'Tachycardia, hypotension', 'Hot, flushed skin'],
    diagnostics: ['Rectal temperature (most accurate)', 'BGL, electrolytes, lactate, renal function', 'Rhabdomyolysis: CK, urine myoglobin', 'Coagulopathy (DIC screen)'],
    treatment: ['COOL FIRST, transport second — aggressive cooling is primary treatment', 'Cold water immersion (most effective): full-body ice-water bath', 'Evaporative cooling: remove clothing, mist water + fan', 'Cold packs to neck, axillae, groin', 'Ice water gastric/bladder lavage at hospital', 'IV fluid resuscitation: NS 1 L boluses for hypotension', 'Benzodiazepines for shivering (prevents heat generation)', 'Target core temp: 38.5–39°C — stop cooling to avoid overshoot'],
    pitfalls: 'Every 30 min of delay in cooling = worse outcome. Do NOT give antipyretics (not effective for heat stroke). Exertional heat stroke — young fit athlete after exercise — still dangerous.',
    color: Color(0xFFD32F2F),
  ),

  // ── Envenomation ──────────────────────────────────────────────────────────
  DxCondition(
    name: 'Snake Envenomation',
    category: 'Envenomation',
    severity: 'Mild to Life-threatening (species-dependent)',
    symptoms: ['Pain and swelling at bite site', 'Nausea / vomiting', 'Fang marks (may be single in some species)', 'Paraesthesia / numbness'],
    signs: ['Local oedema and erythema progressing proximally', 'Ecchymosis / vesicles (cytotoxic venom)', 'Ptosis / diplopia (neurotoxic venom)', 'Coagulopathy: bleeding from gums, IV sites', 'Hypotension (shock)'],
    diagnostics: ['Clinical: identify snake if safe to do so (photograph — do NOT handle)', 'FBC, coagulation, BMP, LFT, CK, urinalysis', 'Serial measurements of swelling (mark edge with pen q15min)'],
    treatment: ['Immobilise affected limb below heart level', 'Remove jewellery/constricting items from affected limb', 'Pressure immobilisation bandage for NEUROTOXIC snakes (elapids: coral, mamba, cobra)', 'Do NOT use tourniquet, incision, suction, or ice', 'IV access, IV fluids', 'Antivenom (species-specific) — contact poison centre for guidance', 'Monitor: vitals, swelling progress, coagulation every 30 min', 'Analgesics: Morphine IV (avoid NSAIDs — coagulopathy)'],
    pitfalls: 'Dry bite in up to 25% of pit viper bites. Pressure immobilisation is for NEUROTOXIC only — may worsen cytotoxic envenomation. "Dead" snake heads can still envenomate by reflex for up to 1 hour.',
    color: Color(0xFF6A1B9A),
  ),

  // ── Trauma ───────────────────────────────────────────────────────────────
  DxCondition(
    name: 'Tension Pneumothorax',
    category: 'Trauma / Respiratory',
    severity: 'IMMEDIATELY LIFE-THREATENING',
    symptoms: ['Sudden severe respiratory distress', 'Chest pain (ipsilateral)', 'Air hunger'],
    signs: ['Absent / decreased breath sounds ipsilateral (most reliable sign)', 'Tracheal deviation AWAY from affected side (late sign)', 'Distended neck veins (JVD)', 'Hypotension', 'Tachycardia', 'Cyanosis (late)'],
    diagnostics: ['CLINICAL DIAGNOSIS — do NOT wait for imaging in arrest', 'FAST / thoracic ultrasound: absent lung sliding', 'CXR: mediastinal shift, absent lung markings (if time permits)'],
    treatment: ['Immediate needle decompression — 2nd ICS MCL or 4th/5th ICS AAL', '14G catheter ≥3.25 cm', 'Confirm air release', 'Convert to finger thoracostomy / chest tube at definitive care', 'BVM ventilation if apnoeic (tension will rapidly recur)'],
    pitfalls: 'Tracheal deviation is a LATE sign — do not wait for it. Diagnose clinically in arrest. In intubated patients, tension pneumo presents as ventilator alarm + cardiovascular collapse. Bilateral tension pneumo after trauma = needle both sides.',
    color: Color(0xFFD32F2F),
  ),
  DxCondition(
    name: 'Traumatic Brain Injury (TBI)',
    category: 'Trauma',
    severity: 'Mild (GCS 13–15) | Moderate (9–12) | Severe (≤8)',
    symptoms: ['Headache', 'Nausea / vomiting', 'Amnesia — retrograde or anterograde', 'Loss of consciousness (any duration)', 'Confusion'],
    signs: ['GCS score', 'Pupil asymmetry (herniation sign)', 'Battle\'s sign (mastoid ecchymosis)', 'Raccoon eyes (periorbital ecchymosis)', 'CSF from ears/nose', 'Cushing\'s Triad: HTN + bradycardia + irregular respirations (imminent herniation)'],
    diagnostics: ['CT head without contrast (gold standard)', 'GCS serial measurements', 'Cervical spine assessment'],
    treatment: ['Airway — intubate GCS ≤8 (definitive airway)', 'Maintain SpO₂ ≥95% and ETCO₂ 35–40 mmHg', 'Avoid hypotension: target SBP ≥90 (≥110 preferred)', 'HOB 30°, head midline, avoid jugular compression', 'Avoid hypotonic fluids (use NS)', 'Seizure prophylaxis: Levetiracetam 500 mg IV', 'Herniation: Mannitol 1 g/kg IV bolus OR 3% NaCl 250 mL IV over 20 min', 'Controlled hyperventilation ETCO₂ 30–35 ONLY for imminent herniation'],
    pitfalls: 'Secondary injury from hypoxia and hypotension is preventable and worse than primary injury. Hyperventilation causes cerebral vasoconstriction — only for herniation and only briefly. AVOID hypotonic fluids.',
    color: Color(0xFFE65100),
  ),

  // ── Medical ──────────────────────────────────────────────────────────────
  DxCondition(
    name: 'Anaphylaxis',
    category: 'Medical',
    severity: 'LIFE-THREATENING',
    symptoms: ['Pruritus / urticaria', 'Throat/tongue swelling — stridor', 'Wheezing / bronchospasm', 'Nausea / vomiting / abdominal cramps', 'Dizziness / syncope'],
    signs: ['Urticaria / angioedema', 'Stridor / hoarseness', 'Wheeze', 'Hypotension (SBP <90)', 'Tachycardia (>100)', 'Cyanosis (severe)'],
    diagnostics: ['CLINICAL diagnosis — rapid recognition and treatment', 'Serum tryptase: elevated 1–6 hrs post-reaction (confirms diagnosis)', 'Check allergen exposure history'],
    treatment: ['Epinephrine 0.3 mg IM (1:1,000) anterolateral thigh — IMMEDIATELY', 'Repeat every 5–15 min if no improvement', 'Supine with legs elevated', 'High-flow O₂', 'IV access: 1 L NS for hypotension', 'Diphenhydramine 50 mg IV/IM (H1)', 'Ranitidine 50 mg IV (H2)', 'Methylprednisolone 125 mg IV', 'Albuterol nebulised for bronchospasm', 'Observe ≥4 hrs for biphasic reaction'],
    pitfalls: 'Do NOT delay Epinephrine for antihistamines or steroids. Antihistamines treat urticaria — they do NOT treat anaphylaxis. Biphasic reaction in 5–20% of cases up to 72 hrs — mandatory observation.',
    color: Color(0xFFD32F2F),
  ),
  DxCondition(
    name: 'Hypoglycaemia',
    category: 'Medical',
    severity: 'BGL <70 mg/dL',
    symptoms: ['Diaphoresis (most sensitive)', 'Tremor / shakiness', 'Palpitations', 'Hunger', 'Anxiety / irritability'],
    signs: ['Diaphoresis', 'Pallor', 'Tachycardia', 'Confusion / AMS', 'Focal neurological deficits', 'Seizures', 'Unconsciousness'],
    diagnostics: ['Capillary blood glucose (POC)', 'Repeat BGL 15 min after treatment', 'Consider underlying cause: insulin, sulfonylurea, alcohol, infection'],
    treatment: ['Conscious, can swallow: 15–20 g fast-acting glucose (4 glucose tablets, 150 mL juice)', 'Reassess in 15 min — repeat if BGL still <70 mg/dL', 'Follow with complex carbohydrate snack once >80 mg/dL', 'Unconscious / unable to swallow: Dextrose 25 g (50 mL D50W) IV/IO', 'No IV access: Glucagon 1 mg IM (adult); 0.5 mg (<25 kg)', 'Treat underlying cause (insulin overdose, missed meal)'],
    pitfalls: 'Alcohol hypoglycaemia — always check BGL in intoxicated patient. Sulfonylurea-induced hypoglycaemia recurs despite treatment — requires admission and Octreotide. Glucagon ineffective in malnourished patients (depleted glycogen stores).',
    color: Color(0xFF1565C0),
  ),
];

// ── Screens ───────────────────────────────────────────────────────────────────

class DifferentialDxScreen extends StatefulWidget {
  const DifferentialDxScreen({super.key});

  @override
  State<DifferentialDxScreen> createState() => _DifferentialDxScreenState();
}

class _DifferentialDxScreenState extends State<DifferentialDxScreen> {
  String _query = '';
  final TextEditingController _ctrl = TextEditingController();

  Map<String, List<DxCondition>> get _grouped {
    final filtered = kConditions.where((c) {
      final q = _query.toLowerCase();
      return q.isEmpty ||
          c.name.toLowerCase().contains(q) ||
          c.category.toLowerCase().contains(q) ||
          c.symptoms.any((s) => s.toLowerCase().contains(q)) ||
          c.signs.any((s) => s.toLowerCase().contains(q));
    }).toList();
    final Map<String, List<DxCondition>> grouped = {};
    for (final c in filtered) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final categories = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Differential Diagnosis'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'Search by symptom or condition...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { setState(() { _query = ''; _ctrl.clear(); }); })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                isDense: true,
                fillColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.grey[800],
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: grouped.isEmpty
          ? const Center(child: Text('No conditions match your search.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: categories.map((cat) {
                final conds = grouped[cat]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                      child: Text(cat, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    ...conds.map((c) => _ConditionCard(condition: c)),
                  ],
                );
              }).toList(),
            ),
    );
  }
}

class _ConditionCard extends StatelessWidget {
  final DxCondition condition;
  const _ConditionCard({required this.condition});

  @override
  Widget build(BuildContext context) {
    final c = condition;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Container(
          width: 10,
          decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(4)),
        ),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(c.severity, style: TextStyle(
          color: c.severity.contains('LIFE') || c.severity.contains('IMMEDIATELY') ? Colors.red[700] : null,
          fontSize: 12,
          fontWeight: c.severity.contains('LIFE') ? FontWeight.bold : null,
        )),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _section('Symptoms', c.symptoms),
              const Divider(),
              _section('Clinical Signs', c.signs),
              const Divider(),
              _section('Diagnostics', c.diagnostics),
              const Divider(),
              _section('Treatment', c.treatment, highlight: true),
              if (c.pitfalls != null) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.amber),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.warning_amber, size: 16, color: Colors.amber),
                        SizedBox(width: 6),
                        Text('PITFALLS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
                      ]),
                      const SizedBox(height: 4),
                      Text(c.pitfalls!, style: const TextStyle(fontSize: 13, height: 1.5)),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<String> items, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(highlight ? '→ ' : '• ', style: TextStyle(color: highlight ? Colors.green[700] : null, fontWeight: highlight ? FontWeight.bold : null)),
            Expanded(child: Text(item, style: TextStyle(fontSize: 13, height: 1.4, color: highlight ? Colors.green[700] : null))),
          ]),
        )),
      ]),
    );
  }
}
