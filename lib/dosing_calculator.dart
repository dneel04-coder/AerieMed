import 'package:flutter/material.dart';


class DoseFormula {
  final String route;
  final double dosePerKg;
  final String unit;
  final double? minDose;
  final double? maxDose;
  final String? concentration;
  final String notes;
  const DoseFormula({
    required this.route,
    required this.dosePerKg,
    required this.unit,
    this.minDose,
    this.maxDose,
    this.concentration,
    this.notes = '',
  });
}

class CalcDrug {
  final String name;
  final String category;
  final Color color;
  final List<DoseFormula> formulas;
  const CalcDrug({
    required this.name,
    required this.category,
    required this.color,
    required this.formulas,
  });
}


const List<CalcDrug> kCalcDrugs = [
  CalcDrug(
    name: 'Epinephrine — Anaphylaxis',
    category: 'Resuscitation',
    color: Color(0xFFD32F2F),
    formulas: [
      DoseFormula(route: 'IM (1:1,000)', dosePerKg: 0.01, unit: 'mg', maxDose: 0.5,
          concentration: '1 mg/mL — draw volume = dose (mg) in mL',
          notes: 'Anterolateral thigh. Repeat q5–15 min.'),
    ],
  ),
  CalcDrug(
    name: 'Epinephrine — Cardiac Arrest',
    category: 'Resuscitation',
    color: Color(0xFFD32F2F),
    formulas: [
      DoseFormula(route: 'IV / IO (1:10,000)', dosePerKg: 0.01, unit: 'mg', maxDose: 1.0,
          concentration: '0.1 mg/mL — volume = dose (mg) ÷ 0.1',
          notes: 'Repeat q3–5 min during CPR.'),
    ],
  ),
  CalcDrug(
    name: 'Fentanyl',
    category: 'Pain Management',
    color: Color(0xFFE53935),
    formulas: [
      DoseFormula(route: 'IV / IO', dosePerKg: 1.0, unit: 'mcg', maxDose: 100,
          concentration: '50 mcg/mL standard — volume = dose ÷ 50',
          notes: 'Give slowly over 2–3 min. Reduce 50% if elderly or haemodynamically unstable.'),
      DoseFormula(route: 'IN (intranasal)', dosePerKg: 1.5, unit: 'mcg', maxDose: 150,
          concentration: 'Use 500 mcg/10 mL concentration via MAD',
          notes: 'Divide between nares. Onset 5–10 min.'),
      DoseFormula(route: 'IM', dosePerKg: 1.0, unit: 'mcg', maxDose: 100,
          notes: 'Onset 7–8 min. Duration 1–2 hrs.'),
    ],
  ),
  CalcDrug(
    name: 'Ketamine — Analgesia',
    category: 'Pain Management',
    color: Color(0xFFE53935),
    formulas: [
      DoseFormula(route: 'IV (sub-dissociative)', dosePerKg: 0.3, unit: 'mg', maxDose: 30,
          concentration: '10 mg/mL — volume = dose ÷ 10',
          notes: 'Give over 10–15 min to reduce dysphoria.'),
      DoseFormula(route: 'IN (intranasal)', dosePerKg: 0.7, unit: 'mg', maxDose: 100,
          concentration: 'Use 500 mg/10 mL concentration',
          notes: 'Divide between nares. Good for paediatrics.'),
    ],
  ),
  CalcDrug(
    name: 'Ketamine — Sedation / RSI',
    category: 'Sedation',
    color: Color(0xFFE53935),
    formulas: [
      DoseFormula(route: 'IV (dissociative)', dosePerKg: 2.0, unit: 'mg', maxDose: 200,
          concentration: '10 mg/mL — volume = dose ÷ 10',
          notes: 'Onset 1 min. Duration 10–15 min. Consider Midazolam 1–2 mg to reduce emergence.'),
      DoseFormula(route: 'IM', dosePerKg: 5.0, unit: 'mg', maxDose: 500,
          concentration: '500 mg/10 mL',
          notes: 'Onset 3–5 min. Duration 15–30 min.'),
    ],
  ),
  CalcDrug(
    name: 'Midazolam — Seizure',
    category: 'Seizure',
    color: Color(0xFF6A1B9A),
    formulas: [
      DoseFormula(route: 'IM (preferred pre-hospital)', dosePerKg: 0.2, unit: 'mg',
          minDose: 5.0, maxDose: 10.0,
          concentration: '5 mg/mL — volume = dose ÷ 5',
          notes: 'RAMPART trial — IM midazolam superior to IV diazepam pre-hospital.'),
      DoseFormula(route: 'IN (intranasal)', dosePerKg: 0.2, unit: 'mg', maxDose: 10.0,
          notes: 'Use concentrated 5 mg/mL formulation via MAD.'),
      DoseFormula(route: 'IV / IO', dosePerKg: 0.1, unit: 'mg', maxDose: 5.0,
          notes: 'Titrate slowly. Monitor respiration.'),
    ],
  ),
  CalcDrug(
    name: 'Morphine',
    category: 'Pain Management',
    color: Color(0xFFE53935),
    formulas: [
      DoseFormula(route: 'IV / IO', dosePerKg: 0.1, unit: 'mg', maxDose: 4.0,
          concentration: '10 mg/mL or 1 mg/mL (diluted)',
          notes: 'Titrate 2 mg increments q5 min. Avoid in haemodynamic instability.'),
      DoseFormula(route: 'IM / SQ', dosePerKg: 0.1, unit: 'mg', maxDose: 10.0,
          notes: 'Onset 5–15 min. Duration 3–4 hrs.'),
    ],
  ),
  CalcDrug(
    name: 'Diphenhydramine (Benadryl)',
    category: 'Allergy',
    color: Color(0xFF1565C0),
    formulas: [
      DoseFormula(route: 'IV / IM', dosePerKg: 1.0, unit: 'mg', maxDose: 50.0,
          concentration: '50 mg/mL — volume = dose ÷ 50',
          notes: 'Give IV slowly over 5 min. Max 50 mg/dose adult.'),
      DoseFormula(route: 'PO', dosePerKg: 1.0, unit: 'mg', maxDose: 50.0,
          notes: 'Tablet or liquid. Every 6 hrs PRN.'),
    ],
  ),
  CalcDrug(
    name: 'Dexamethasone',
    category: 'Corticosteroid',
    color: Color(0xFF2E7D32),
    formulas: [
      DoseFormula(route: 'IV / IM — asthma/altitude', dosePerKg: 0.15, unit: 'mg',
          minDose: 4.0, maxDose: 10.0,
          concentration: '4 mg/mL or 10 mg/mL',
          notes: 'Single dose effective. For altitude: 8 mg loading then 4 mg q6h.'),
      DoseFormula(route: 'PO — croup', dosePerKg: 0.6, unit: 'mg', maxDose: 16.0,
          notes: 'Single dose. Give at least 2 hrs before discharge.'),
    ],
  ),
  CalcDrug(
    name: 'Adenosine — SVT',
    category: 'Cardiac',
    color: Color(0xFF1565C0),
    formulas: [
      DoseFormula(route: 'IV — 1st dose', dosePerKg: 0.1, unit: 'mg', maxDose: 6.0,
          concentration: '3 mg/mL',
          notes: 'Give as RAPID bolus + 20 mL NS flush. Use proximal large vein.'),
      DoseFormula(route: 'IV — 2nd dose', dosePerKg: 0.2, unit: 'mg', maxDose: 12.0,
          notes: 'If no response after 1–2 min. Warn patient of transient asystole.'),
    ],
  ),
  CalcDrug(
    name: 'Tranexamic Acid (TXA)',
    category: 'Haemostasis',
    color: Color(0xFFD32F2F),
    formulas: [
      DoseFormula(route: 'IV loading dose', dosePerKg: 15.0, unit: 'mg', maxDose: 1000,
          concentration: '100 mg/mL — dilute to 100 mL NS',
          notes: 'Give over 10 min. MUST be within 3 hrs of injury.'),
    ],
  ),
  CalcDrug(
    name: 'Naloxone',
    category: 'Antidote',
    color: Color(0xFF1565C0),
    formulas: [
      DoseFormula(route: 'IV / IO', dosePerKg: 0.01, unit: 'mg', maxDose: 2.0,
          concentration: '0.4 mg/mL or 1 mg/mL',
          notes: 'Titrate every 2–3 min. Repeat as needed. Half-life 30–90 min — may re-sedate.'),
      DoseFormula(route: 'IM', dosePerKg: 0.01, unit: 'mg', maxDose: 2.0,
          notes: 'When IV/IO unavailable.'),
      DoseFormula(route: 'IN (intranasal)', dosePerKg: 0.02, unit: 'mg', maxDose: 4.0,
          concentration: 'Use 2 mg/2 mL — 1 mg per nare',
          notes: 'Community/bystander use. Onset 3–5 min.'),
    ],
  ),
];


int _broslow(double heightCm) {
  if (heightCm < 46.1) return 3;
  if (heightCm < 52.1) return 4;
  if (heightCm < 58.5) return 5;
  if (heightCm < 62.5) return 6;
  if (heightCm < 66.5) return 7;
  if (heightCm < 69.5) return 8;
  if (heightCm < 73.0) return 9;
  if (heightCm < 76.0) return 10;
  if (heightCm < 81.5) return 11;
  if (heightCm < 86.0) return 12;
  if (heightCm < 91.5) return 13;
  if (heightCm < 96.5) return 14;
  if (heightCm < 101.5) return 15;
  if (heightCm < 106.5) return 16;
  if (heightCm < 111.5) return 18;
  if (heightCm < 116.5) return 20;
  if (heightCm < 121.5) return 22;
  if (heightCm < 126.5) return 24;
  if (heightCm < 131.5) return 26;
  if (heightCm < 136.0) return 28;
  if (heightCm < 141.0) return 30;
  if (heightCm < 146.5) return 32;
  return 36;
}


class DosingCalculatorScreen extends StatefulWidget {
  final bool embedded;
  const DosingCalculatorScreen({super.key, this.embedded = false});

  @override
  State<DosingCalculatorScreen> createState() => _DosingCalculatorScreenState();
}

class _DosingCalculatorScreenState extends State<DosingCalculatorScreen> {
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  bool _useLbs = false;
  String _filter = 'All';

  double? get _weightKg {
    final raw = double.tryParse(_weightCtrl.text);
    if (raw == null || raw <= 0) return null;
    return _useLbs ? raw * 0.4536 : raw;
  }

  List<String> get _categories {
    final cats = kCalcDrugs.map((d) => d.category).toSet().toList()..sort();
    return ['All', ...cats];
  }

  List<CalcDrug> get _filtered =>
      kCalcDrugs.where((d) => _filter == 'All' || d.category == _filter).toList();

  String _calcVolume(DoseFormula f, double weightKg) {
    double raw = f.dosePerKg * weightKg;
    if (f.minDose != null && raw < f.minDose!) raw = f.minDose!;
    if (f.maxDose != null && raw > f.maxDose!) raw = f.maxDose!;
    return raw.toStringAsFixed(2);
  }

  bool _isCapped(DoseFormula f, double weightKg) {
    final raw = f.dosePerKg * weightKg;
    return f.maxDose != null && raw >= f.maxDose!;
  }

  Widget _buildBody(BuildContext context) {
    final wKg = _weightKg;
    final heightRaw = double.tryParse(_heightCtrl.text);
    final broslowEst = heightRaw != null && heightRaw > 0 ? _broslow(heightRaw) : null;
    return Column(
        children: [
          // Weight input panel
          Container(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _useLbs ? 'Weight (lbs)' : 'Weight (kg)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      suffixText: _useLbs ? 'lbs' : 'kg',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Column(children: [
                  const Text('lbs', style: TextStyle(fontSize: 12)),
                  Switch(value: _useLbs, onChanged: (v) => setState(() { _useLbs = v; _weightCtrl.clear(); })),
                  const Text('kg', style: TextStyle(fontSize: 12)),
                ]),
              ]),
              if (wKg != null) ...[
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${wKg.toStringAsFixed(1)} kg${_useLbs ? " (${_weightCtrl.text} lbs)" : ""}',
                    style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _heightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Height (cm) — optional pediatric estimator',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      suffixText: 'cm',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              if (broslowEst != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal),
                  ),
                  child: Row(children: [
                    const Icon(Icons.child_care, color: Colors.teal, size: 18),
                    const SizedBox(width: 8),
                    Text('Broselow estimate: ~$broslowEst kg',
                        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _useLbs = false;
                          _weightCtrl.text = broslowEst.toString();
                        });
                      },
                      child: const Text('Use this weight'),
                    ),
                  ]),
                ),
              ],
            ]),
          ),

          // Category filter
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                return FilterChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: _filter == cat,
                  onSelected: (_) => setState(() => _filter = cat),
                );
              },
            ),
          ),

          // Drug results
          Expanded(
            child: wKg == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calculate_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Enter patient weight to calculate doses',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      ]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _DrugResult(drug: _filtered[i], weightKg: wKg,
                        calcVolume: _calcVolume, isCapped: _isCapped),
                  ),
          ),
        ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dosing Calculator')),
      body: _buildBody(context),
    );
  }
}

class _DrugResult extends StatelessWidget {
  final CalcDrug drug;
  final double weightKg;
  final String Function(DoseFormula, double) calcVolume;
  final bool Function(DoseFormula, double) isCapped;

  const _DrugResult({
    required this.drug,
    required this.weightKg,
    required this.calcVolume,
    required this.isCapped,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 4, height: 24, decoration: BoxDecoration(color: drug.color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(child: Text(drug.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: drug.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Text(drug.category, style: TextStyle(color: drug.color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 10),
          ...drug.formulas.map((f) {
            final dose = calcVolume(f, weightKg);
            final capped = isCapped(f, weightKg);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.route, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Row(children: [
                  Text('$dose ${f.unit}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: drug.color)),
                  if (capped) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                      child: Text('MAX ${f.maxDose} ${f.unit}',
                          style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
                Text('${f.dosePerKg} ${f.unit}/kg × ${weightKg.toStringAsFixed(1)} kg',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                if (f.concentration != null) ...[
                  const SizedBox(height: 4),
                  Text(f.concentration!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                ],
                if (f.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(f.notes, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ]),
            );
          }),
        ]),
      ),
    );
  }
}
