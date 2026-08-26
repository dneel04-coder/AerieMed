import 'package:flutter/material.dart';
import 'protocol_version.dart' show MedicalCitationBanner;


class DrugDose {
  final String route;
  final String adultDose;
  final String? pediatricDose;
  final String? notes;
  const DrugDose({required this.route, required this.adultDose, this.pediatricDose, this.notes});
}

class Drug {
  final String name;
  final String category;
  final String mechanism;
  final List<String> indications;
  final List<DrugDose> dosing;
  final List<String> contraindications;
  final List<String> sideEffects;
  final String? fieldNotes;
  final Color categoryColor;
  const Drug({
    required this.name,
    required this.category,
    required this.mechanism,
    required this.indications,
    required this.dosing,
    required this.contraindications,
    required this.sideEffects,
    this.fieldNotes,
    required this.categoryColor,
  });
}


const List<Drug> kDrugs = [
  // ── Pain Management ──────────────────────────────────────────────────────
  Drug(
    name: 'Fentanyl',
    category: 'Pain Management',
    mechanism: 'Synthetic opioid — μ-receptor agonist. Rapid onset (1–2 min IV), short duration (30–60 min).',
    indications: ['Moderate–severe acute pain', 'Procedural sedation adjunct', 'Intubation pre-medication'],
    dosing: [
      DrugDose(route: 'IV / IO', adultDose: '1–2 mcg/kg slow IV push; titrate in 25 mcg increments q5min', pediatricDose: '1–2 mcg/kg IV, max 100 mcg/dose'),
      DrugDose(route: 'IM', adultDose: '1–2 mcg/kg IM', pediatricDose: '1–2 mcg/kg IM'),
      DrugDose(route: 'IN (intranasal)', adultDose: '1.5–2 mcg/kg divided between nares via MAD', pediatricDose: '1.5 mcg/kg IN'),
    ],
    contraindications: ['Known hypersensitivity', 'Significant respiratory depression', 'Acute bronchospasm (relative)'],
    sideEffects: ['Respiratory depression', 'Nausea/vomiting', 'Hypotension', 'Chest wall rigidity (high doses)', 'Bradycardia'],
    fieldNotes: 'Have Naloxone immediately available. Reduce dose 50% in elderly, renal impairment, or hemodynamic instability. Preferred over morphine in haemodynamic instability.',
    categoryColor: Color(0xFFE53935),
  ),
  Drug(
    name: 'Ketamine',
    category: 'Pain Management / Sedation',
    mechanism: 'NMDA receptor antagonist. Dissociative anaesthetic. Maintains airway reflexes and haemodynamic stability. Bronchodilator.',
    indications: ['Moderate–severe pain (sub-dissociative dose)', 'Procedural sedation', 'RSI induction', 'Refractory bronchospasm', 'Excited delirium'],
    dosing: [
      DrugDose(route: 'IV — analgesia', adultDose: '0.1–0.3 mg/kg IV over 10 min', pediatricDose: '0.5 mg/kg IV over 10 min', notes: 'Sub-dissociative dose for pain'),
      DrugDose(route: 'IV — sedation', adultDose: '1–2 mg/kg IV', pediatricDose: '1–2 mg/kg IV', notes: 'Dissociative sedation'),
      DrugDose(route: 'IM — sedation', adultDose: '4–6 mg/kg IM', pediatricDose: '4–5 mg/kg IM', notes: 'Onset 3–5 min'),
      DrugDose(route: 'IN — analgesia', adultDose: '0.5–0.75 mg/kg IN via MAD', pediatricDose: '0.5–1 mg/kg IN'),
    ],
    contraindications: ['Schizophrenia / active psychosis (relative)', 'Thyrotoxicosis (relative)', 'SBP >180 uncontrolled (relative)'],
    sideEffects: ['Emergence reactions / dysphoria (reduce with Midazolam 1–2 mg IV)', 'Hypersalivation (Atropine 0.01 mg/kg pretreatment)', 'Laryngospasm (rare)', 'Transient BP/HR increase'],
    fieldNotes: 'Drug of choice for haemodynamically unstable patients requiring analgesia or sedation. Does NOT suppress airway reflexes at analgesic doses. Administer slowly IV to reduce adverse effects.',
    categoryColor: Color(0xFFE53935),
  ),
  Drug(
    name: 'Morphine Sulfate',
    category: 'Pain Management',
    mechanism: 'Opioid — μ, κ, δ receptor agonist. Slower onset than fentanyl. Histamine release.',
    indications: ['Moderate–severe acute pain', 'Acute pulmonary oedema (high-altitude)'],
    dosing: [
      DrugDose(route: 'IV / IO', adultDose: '2–4 mg IV q5–10min; max 0.1 mg/kg', pediatricDose: '0.05–0.1 mg/kg IV, max 4 mg/dose'),
      DrugDose(route: 'IM / SQ', adultDose: '5–10 mg IM q4h PRN', pediatricDose: '0.1 mg/kg IM'),
    ],
    contraindications: ['Hypotension (SBP <90)', 'Respiratory depression', 'Renal failure (metabolite accumulation)', 'Raised ICP (relative)'],
    sideEffects: ['Respiratory depression', 'Histamine release / pruritus', 'Nausea/vomiting', 'Hypotension', 'Urinary retention'],
    fieldNotes: 'Use Fentanyl preferentially in haemodynamically unstable patients. Avoid in renal failure. Monitor SpO₂ continuously.',
    categoryColor: Color(0xFFE53935),
  ),
  Drug(
    name: 'Ketorolac (Toradol)',
    category: 'Pain Management',
    mechanism: 'NSAID — COX-1/COX-2 inhibitor. Non-opioid analgesic. Limit IV/IM use to ≤5 days.',
    indications: ['Moderate acute pain', 'Renal colic', 'Musculoskeletal pain', 'Opioid-sparing adjunct'],
    dosing: [
      DrugDose(route: 'IV', adultDose: '15–30 mg IV over 15 sec (≤65 yrs: 30 mg; >65 yrs/renal/low weight: 15 mg)'),
      DrugDose(route: 'IM', adultDose: '30–60 mg IM single dose'),
    ],
    contraindications: ['Active GI bleed', 'Renal impairment (CrCl <30)', 'Aspirin-exacerbated respiratory disease', 'Pregnancy (3rd trimester)', 'Concurrent anticoagulation'],
    sideEffects: ['GI irritation / ulceration', 'Renal impairment', 'Bleeding (platelet inhibition)', 'Hypertension'],
    fieldNotes: 'Excellent non-opioid option for moderate pain. Avoid in trauma with haemorrhage (platelet inhibition). Max 5 days use.',
    categoryColor: Color(0xFFE53935),
  ),

  // ── Resuscitation ────────────────────────────────────────────────────────
  Drug(
    name: 'Epinephrine (Adrenaline)',
    category: 'Resuscitation / Anaphylaxis',
    mechanism: 'Catecholamine — α1, α2, β1, β2 agonist. Increases HR, BP, bronchodilation. Vasoconstriction at α doses.',
    indications: ['Cardiac arrest (PEA, VF, asystole)', 'Anaphylaxis', 'Severe bronchospasm', 'Bradycardia (refractory)', 'Croup (nebulised)'],
    dosing: [
      DrugDose(route: 'Cardiac arrest IV/IO', adultDose: '1 mg (1:10,000) IV/IO q3–5min', pediatricDose: '0.01 mg/kg (0.1 mL/kg of 1:10,000) IV/IO q3–5min, max 1 mg'),
      DrugDose(route: 'Anaphylaxis IM', adultDose: '0.3–0.5 mg (1:1,000) IM anterolateral thigh', pediatricDose: '0.01 mg/kg IM (1:1,000), max 0.5 mg', notes: 'Repeat q5–15 min if no improvement'),
      DrugDose(route: 'Infusion (vasopressor)', adultDose: '0.1–0.5 mcg/kg/min IV', notes: 'Titrate to MAP ≥65 mmHg'),
      DrugDose(route: 'Nebulised (croup)', adultDose: '5 mg (1:1,000) nebulised', pediatricDose: '0.5 mL/kg of 1:1,000, max 5 mL', notes: 'Racemic epi preferred if available'),
    ],
    contraindications: ['No absolute contraindications in cardiac arrest or anaphylaxis'],
    sideEffects: ['Tachycardia', 'Hypertension', 'Arrhythmias', 'Anxiety', 'Ischaemia (high doses)'],
    fieldNotes: 'Anaphylaxis: ALWAYS give IM first — IV only in cardiac arrest or refractory shock. Rotate injection sites if repeating. EpiPen: 0.3 mg auto-injector adult, 0.15 mg pediatric.',
    categoryColor: Color(0xFFD32F2F),
  ),
  Drug(
    name: 'Tranexamic Acid (TXA)',
    category: 'Haemostasis',
    mechanism: 'Antifibrinolytic — competitive inhibitor of plasminogen activation. Stabilises formed clots.',
    indications: ['Traumatic haemorrhage (within 3 hrs of injury)', 'Major bleeding', 'Postpartum haemorrhage'],
    dosing: [
      DrugDose(route: 'IV loading dose', adultDose: '1 g in 100 mL NS over 10 min', notes: 'Must be given within 3 hrs of injury'),
      DrugDose(route: 'IV maintenance', adultDose: '1 g in 250 mL NS over 8 hrs', notes: 'Give within 3 hrs of first dose'),
    ],
    contraindications: ['>3 hours post-injury (may worsen mortality)', 'Subarachnoid haemorrhage (relative)', 'Active intravascular clotting', 'Thromboembolic history (relative)'],
    sideEffects: ['Nausea/vomiting (slow infusion rate)', 'Hypotension (if given too fast)', 'Thrombosis (rare)', 'Seizures (high doses in cardiac surgery)'],
    fieldNotes: 'TIME CRITICAL — give as early as possible. TXA given >3 hrs after injury may increase mortality. Safe to give in the field. No dose adjustment for weight in adults.',
    categoryColor: Color(0xFFD32F2F),
  ),
  Drug(
    name: 'Naloxone (Narcan)',
    category: 'Antidotes',
    mechanism: 'Competitive opioid receptor antagonist. Reverses respiratory depression, sedation, and analgesia caused by opioids.',
    indications: ['Opioid-induced respiratory depression', 'Opioid overdose', 'Empiric treatment of AMS'],
    dosing: [
      DrugDose(route: 'IV / IO', adultDose: '0.4–2 mg IV q2–3min until RR >12 or responsive', pediatricDose: '0.01 mg/kg IV (max 2 mg)'),
      DrugDose(route: 'IM', adultDose: '0.4–2 mg IM', pediatricDose: '0.01 mg/kg IM'),
      DrugDose(route: 'IN (intranasal)', adultDose: '2–4 mg IN (1 mg per nare via MAD)', pediatricDose: '0.1 mg/kg IN, max 2 mg'),
    ],
    contraindications: ['None absolute in overdose setting'],
    sideEffects: ['Acute opioid withdrawal (agitation, vomiting, tachycardia, seizures in dependent patients)', 'Re-sedation after 30–90 min (opioid half-life > naloxone)', 'Pulmonary oedema (rare)'],
    fieldNotes: 'Half-life: 30–90 min — patient may re-sedate. Monitor continuously and repeat doses as needed. In buprenorphine overdose, higher doses may be required (4–10 mg). Do not withhold in suspected overdose.',
    categoryColor: Color(0xFF1565C0),
  ),

  // ── Cardiac ──────────────────────────────────────────────────────────────
  Drug(
    name: 'Aspirin',
    category: 'Cardiac',
    mechanism: 'Irreversible COX-1/COX-2 inhibitor → thromboxane A2 synthesis inhibition → antiplatelet aggregation.',
    indications: ['Suspected ACS / STEMI', 'UA/NSTEMI', 'Ischaemic stroke (after haemorrhage excluded)'],
    dosing: [
      DrugDose(route: 'PO — ACS', adultDose: '324 mg (chewed, not swallowed whole)', notes: 'Non-enteric coated. Chewing achieves faster absorption.'),
    ],
    contraindications: ['Active GI bleed', 'Known aspirin allergy', 'Haemorrhagic stroke', 'Children with viral illness (Reye\'s syndrome)'],
    sideEffects: ['GI irritation', 'Bleeding', 'Bronchospasm (aspirin-sensitive asthma)'],
    fieldNotes: 'Give immediately when ACS suspected — do not delay for IV access. Chew, don\'t swallow. Withhold if active bleeding is the primary problem.',
    categoryColor: Color(0xFF1565C0),
  ),
  Drug(
    name: 'Adenosine',
    category: 'Cardiac — Antiarrhythmic',
    mechanism: 'Endogenous purine nucleoside — slows AV node conduction. Terminates re-entrant arrhythmias through AV node.',
    indications: ['SVT (narrow complex stable tachycardia)', 'Diagnosis of wide-complex tachycardia'],
    dosing: [
      DrugDose(route: 'IV — 1st dose', adultDose: '6 mg rapid IV push + 20 mL NS flush', pediatricDose: '0.1 mg/kg rapid IV (max 6 mg)', notes: 'Must be given FAST via proximal large vein'),
      DrugDose(route: 'IV — 2nd dose', adultDose: '12 mg rapid IV push + 20 mL NS flush', pediatricDose: '0.2 mg/kg (max 12 mg)', notes: 'If no response after 1–2 min'),
      DrugDose(route: 'IV — 3rd dose', adultDose: '12 mg rapid IV push + 20 mL NS flush', notes: 'Final dose if still no response'),
    ],
    contraindications: ['2nd/3rd degree AV block (without pacemaker)', 'SSS', 'WPW with AF/flutter', 'Dipyridamole use (potentiates — use 3 mg)', 'Theophylline (inhibits — may need higher dose)', 'Severe asthma (relative)'],
    sideEffects: ['Transient asystole (seconds — warn patient)', 'Chest tightness', 'Flushing', 'Dyspnoea', 'Sense of impending doom'],
    fieldNotes: 'Warn patient: "This will feel strange for a few seconds but is normal." Must be given rapidly (within 1–3 seconds) via AC or above. Ineffective for A-flutter, AF, or WPW-AF.',
    categoryColor: Color(0xFF1565C0),
  ),
  Drug(
    name: 'Amiodarone',
    category: 'Cardiac — Antiarrhythmic',
    mechanism: 'Class III antiarrhythmic — prolongs action potential, blocks sodium/potassium/calcium channels and β-adrenergic receptors.',
    indications: ['VF / pulseless VT (cardiac arrest)', 'Haemodynamically stable VT', 'AF/flutter rate control', 'Refractory SVT'],
    dosing: [
      DrugDose(route: 'Cardiac arrest IV/IO', adultDose: '300 mg IV/IO push; then 150 mg if VF/pVT recurs', pediatricDose: '5 mg/kg IV/IO, max 300 mg'),
      DrugDose(route: 'Stable VT IV', adultDose: '150 mg in 100 mL D5W over 10 min, then 1 mg/min × 6 hrs', notes: 'Continuous cardiac monitoring required'),
    ],
    contraindications: ['Iodine allergy (contains iodine)', 'Thyroid disease (relative)', 'Bradycardia/AV block without pacemaker'],
    sideEffects: ['Hypotension (acute)', 'Phlebitis at injection site', 'Thyroid dysfunction (chronic)', 'Pulmonary toxicity (chronic)', 'QT prolongation'],
    fieldNotes: 'Preferred antiarrhythmic in cardiac arrest per ACLS guidelines. Dilute in D5W — incompatible with NS. Use central line if possible for infusion (irritates peripheral veins).',
    categoryColor: Color(0xFF1565C0),
  ),
  Drug(
    name: 'Atropine',
    category: 'Cardiac / Anticholinergic',
    mechanism: 'Competitive muscarinic acetylcholine receptor antagonist. Increases HR by blocking vagal tone. Reduces secretions.',
    indications: ['Symptomatic bradycardia', 'Organophosphate / nerve agent poisoning', 'Pre-medication before intubation (reduces secretions)', 'Asystole (cardiac arrest — no longer first-line but used)'],
    dosing: [
      DrugDose(route: 'IV — bradycardia', adultDose: '0.5 mg IV q3–5 min; max 3 mg', pediatricDose: '0.02 mg/kg IV (min 0.1 mg, max 0.5 mg)'),
      DrugDose(route: 'IM/IV — organophosphate', adultDose: '2–4 mg IV/IM; repeat q5–10 min until secretions dry', notes: 'Endpoint is drying of secretions, not HR'),
    ],
    contraindications: ['Narrow-angle glaucoma', 'Tachycardia (except organophosphate poisoning)', 'Doses <0.5 mg can paradoxically worsen bradycardia'],
    sideEffects: ['Tachycardia', 'Urinary retention', 'Mydriasis', 'Dry mouth', 'AMS (high doses)', 'Hyperthermia'],
    fieldNotes: 'For organophosphate/nerve agent (e.g. Sarin): titrate to drying of secretions — may need 10–20 mg or more. Use Pralidoxime concurrently if available within 24–48 hrs.',
    categoryColor: Color(0xFF1565C0),
  ),

  // ── Respiratory ──────────────────────────────────────────────────────────
  Drug(
    name: 'Albuterol (Salbutamol)',
    category: 'Respiratory',
    mechanism: 'Short-acting β2 agonist (SABA). Bronchodilation. Onset 5–15 min, duration 4–6 hrs.',
    indications: ['Acute bronchospasm (asthma, COPD exacerbation)', 'Anaphylaxis with bronchospasm', 'Hyperkalaemia (shift K⁺ into cells)'],
    dosing: [
      DrugDose(route: 'Nebulised', adultDose: '2.5 mg in 3 mL NS over 10–15 min; can repeat q20 min × 3 or continuous', pediatricDose: '0.15 mg/kg (min 2.5 mg, max 5 mg) neb'),
      DrugDose(route: 'MDI (metered dose inhaler)', adultDose: '4–8 puffs with spacer q20min × 3', pediatricDose: '2–4 puffs with spacer'),
      DrugDose(route: 'IV (severe/intubated)', adultDose: '5 mcg/min IV infusion, titrate up', notes: 'Specialist use only'),
    ],
    contraindications: ['Hypokalaemia (worsens)', 'Tachyarrhythmias (relative)'],
    sideEffects: ['Tachycardia', 'Tremor', 'Hypokalaemia', 'Hypomagnesaemia', 'Paradoxical bronchospasm (rare)'],
    fieldNotes: 'Add Ipratropium 0.5 mg to first 3 nebulisers for synergistic effect. IV Magnesium Sulphate 2 g over 20 min for severe attacks. Consider early Dexamethasone 8–10 mg IV/IM.',
    categoryColor: Color(0xFF2E7D32),
  ),
  Drug(
    name: 'Dexamethasone',
    category: 'Corticosteroid',
    mechanism: 'Potent long-acting corticosteroid. Anti-inflammatory, reduces oedema. Duration 36–72 hrs.',
    indications: ['Altitude illness (HACE, HAPE)', 'Severe asthma / COPD exacerbation', 'Allergic reaction / anaphylaxis', 'Croup', 'Spinal cord compression', 'Cerebral oedema (tumour)'],
    dosing: [
      DrugDose(route: 'IV / IM — altitude illness', adultDose: '8–10 mg IV/IM loading dose; then 4 mg q6h', notes: 'Treats, does not acclimatize — patient must descend'),
      DrugDose(route: 'IV — asthma', adultDose: '10 mg IV or 0.6 mg/kg IM single dose'),
      DrugDose(route: 'PO — croup', adultDose: '0.6 mg/kg PO single dose (max 16 mg)', pediatricDose: '0.6 mg/kg PO/IM/IV'),
    ],
    contraindications: ['Active systemic fungal infection', 'Live vaccines (relative)', 'GI perforation risk (relative)'],
    sideEffects: ['Hyperglycaemia', 'GI irritation', 'Adrenal suppression (prolonged use)', 'Mood changes', 'Immunosuppression'],
    fieldNotes: 'For HACE: Dexamethasone 8 mg IM/IV then 4 mg q6h AND descend. For HAPE: Nifedipine preferred but Dex useful if Nifedipine unavailable. Single dose very safe.',
    categoryColor: Color(0xFF2E7D32),
  ),

  // ── Sedation / Neuro ─────────────────────────────────────────────────────
  Drug(
    name: 'Midazolam (Versed)',
    category: 'Sedation / Seizure',
    mechanism: 'Benzodiazepine — enhances GABA-A. Anxiolytic, amnestic, anticonvulsant, muscle relaxant. Short-acting.',
    indications: ['Status epilepticus (first-line IM)', 'Procedural sedation adjunct', 'Emergence reaction prophylaxis (with Ketamine)', 'Pre-intubation sedation', 'Agitation'],
    dosing: [
      DrugDose(route: 'IM — seizure', adultDose: '10 mg IM (≥40 kg); 5 mg IM (13–40 kg)', pediatricDose: '0.2 mg/kg IM, max 10 mg', notes: 'First-line for pre-hospital status epilepticus'),
      DrugDose(route: 'IV — sedation', adultDose: '0.02–0.05 mg/kg IV; titrate slowly', pediatricDose: '0.05–0.1 mg/kg IV'),
      DrugDose(route: 'IN', adultDose: '5 mg IN via MAD', pediatricDose: '0.2 mg/kg IN, max 10 mg', notes: 'Use concentrated formulation (5 mg/mL)'),
      DrugDose(route: 'Buccal', adultDose: '10 mg buccal solution', pediatricDose: '0.3 mg/kg buccal', notes: 'Alternative if no IV/IM access'),
    ],
    contraindications: ['Respiratory depression (without airway management ready)', 'Hypotension (caution)', 'Alcohol/CNS depressant combination (reduce dose 50%)'],
    sideEffects: ['Respiratory depression', 'Hypotension', 'Paradoxical agitation (elderly)', 'Amnesia', 'Apnoea (rapid IV)'],
    fieldNotes: 'IM Midazolam has now superseded IV Diazepam for pre-hospital seizure management (RAMPART trial). Airway equipment must be immediately available. Flumazenil reversal: 0.2 mg IV q1min (max 1 mg).',
    categoryColor: Color(0xFF6A1B9A),
  ),
  Drug(
    name: 'Ondansetron (Zofran)',
    category: 'Antiemetic',
    mechanism: '5-HT3 receptor antagonist — blocks serotonin peripherally and centrally at CTZ.',
    indications: ['Nausea and vomiting (any cause)', 'Post-operative N/V', 'Opioid-induced nausea', 'Head injury / TBI nausea'],
    dosing: [
      DrugDose(route: 'IV / IO', adultDose: '4–8 mg IV over 2–5 min', pediatricDose: '0.1–0.15 mg/kg IV (max 4 mg)'),
      DrugDose(route: 'ODT (orally disintegrating)', adultDose: '4–8 mg ODT SL', pediatricDose: '2–4 mg ODT (≥8 kg)'),
      DrugDose(route: 'IM', adultDose: '4–8 mg IM', pediatricDose: '0.1 mg/kg IM'),
    ],
    contraindications: ['Congenital long-QT syndrome', 'Concurrent QT-prolonging drugs (relative)'],
    sideEffects: ['QT prolongation (dose-dependent)', 'Headache', 'Constipation', 'Serotonin syndrome (rare, with other serotonergic agents)'],
    fieldNotes: 'First-line antiemetic in field medicine. ODT formulation excellent for patients unable to swallow. Give SLOWLY IV to reduce QT risk. Very safe in pregnancy.',
    categoryColor: Color(0xFF6A1B9A),
  ),
];


class DrugReferenceScreen extends StatefulWidget {
  final bool embedded;
  const DrugReferenceScreen({super.key, this.embedded = false});

  @override
  State<DrugReferenceScreen> createState() => _DrugReferenceScreenState();
}

class _DrugReferenceScreenState extends State<DrugReferenceScreen> {
  String _query = '';
  String _categoryFilter = 'All';
  final TextEditingController _searchCtrl = TextEditingController();

  List<String> get _categories {
    final cats = kDrugs.map((d) => d.category).toSet().toList()..sort();
    return ['All', ...cats];
  }

  List<Drug> get _filtered {
    return kDrugs.where((d) {
      final matchCat = _categoryFilter == 'All' || d.category == _categoryFilter;
      final q = _query.toLowerCase();
      final matchQ = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.category.toLowerCase().contains(q) ||
          d.indications.any((i) => i.toLowerCase().contains(q));
      return matchCat && matchQ;
    }).toList();
  }

  Widget _buildBody() {
    return Column(children: [
      const MedicalCitationBanner(),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search drugs...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() { _query = ''; _searchCtrl.clear(); }))
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            isDense: true,
            fillColor: Theme.of(context).brightness == Brightness.light
                ? Colors.white
                : Colors.grey[800],
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: _categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final cat = _categories[i];
            final selected = _categoryFilter == cat;
            return FilterChip(
              label: Text(cat, style: const TextStyle(fontSize: 12)),
              selected: selected,
              onSelected: (_) => setState(() => _categoryFilter = cat),
            );
          },
        ),
      ),
      Expanded(
        child: _filtered.isEmpty
            ? const Center(child: Text('No drugs match your search.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => _DrugCard(drug: _filtered[i]),
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody();
    return Scaffold(
      appBar: AppBar(title: const Text('Drug Reference')),
      body: _buildBody(),
    );
  }
}

class _DrugCard extends StatelessWidget {
  final Drug drug;
  const _DrugCard({required this.drug});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: drug.categoryColor.withValues(alpha: 0.15),
          child: Text(drug.name[0], style: TextStyle(color: drug.categoryColor, fontWeight: FontWeight.bold)),
        ),
        title: Text(drug.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(drug.category, style: TextStyle(color: drug.categoryColor, fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section('Mechanism', drug.mechanism),
                const Divider(),
                _section('Indications', drug.indications.map((i) => '• $i').join('\n')),
                const Divider(),
                _dosingSection(context),
                const Divider(),
                _section('Contraindications', drug.contraindications.map((c) => '• $c').join('\n'), color: Colors.red[700]),
                const Divider(),
                _section('Side Effects', drug.sideEffects.map((s) => '• $s').join('\n')),
                if (drug.fieldNotes != null) ...[
                  const Divider(),
                  _section('Field Notes', drug.fieldNotes!, color: Colors.orange[800]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String body, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        Text(body, style: TextStyle(fontSize: 13, color: color, height: 1.5)),
      ]),
    );
  }

  Widget _dosingSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DOSING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
        const SizedBox(height: 6),
        ...drug.dosing.map((d) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.route, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Adult: ${d.adultDose}', style: const TextStyle(fontSize: 13)),
            if (d.pediatricDose != null)
              Text('Pediatric: ${d.pediatricDose}', style: const TextStyle(fontSize: 13, color: Colors.teal)),
            if (d.notes != null)
              Text(d.notes!, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
          ]),
        )),
      ]),
    );
  }
}
