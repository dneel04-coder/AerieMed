import 'package:flutter/material.dart';

// ── Data Model ────────────────────────────────────────────────────────────────

class CheckStep {
  final String text;
  final String? detail;
  final bool isCritical;
  const CheckStep({required this.text, this.detail, this.isCritical = false});
}

class Procedure {
  final String id;
  final String title;
  final String category;
  final String description;
  final IconData icon;
  final Color color;
  final List<CheckStep> steps;
  const Procedure({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.icon,
    required this.color,
    required this.steps,
  });
}

// ── Static Data ───────────────────────────────────────────────────────────────

const List<Procedure> kProcedures = [
  Procedure(
    id: 'tourniquet',
    title: 'Tourniquet Application',
    category: 'Haemorrhage Control',
    description: 'For life-threatening extremity bleeding.',
    icon: Icons.healing,
    color: Color(0xFFD32F2F),
    steps: [
      CheckStep(text: 'Expose the wound — cut away clothing', isCritical: true),
      CheckStep(text: 'Identify correct placement site: 2–3 inches (5–7 cm) proximal to wound', isCritical: true,
          detail: 'Do NOT place over a joint. Place over clothing or directly on skin.'),
      CheckStep(text: 'Route tourniquet around limb and thread free end through buckle'),
      CheckStep(text: 'Pull strap TIGHT and secure', isCritical: true),
      CheckStep(text: 'Twist windlass rod until bleeding STOPS', isCritical: true,
          detail: 'Tighten until bright red arterial bleeding ceases. Expect patient to report pain.'),
      CheckStep(text: 'Secure windlass rod in keeper loop or clip'),
      CheckStep(text: 'Mark time of application on tourniquet tab or patient forehead', isCritical: true,
          detail: 'Write "TK" and time in 24-hr format (e.g. TK 14:32). Do NOT remove tourniquet in field.'),
      CheckStep(text: 'Apply second tourniquet proximal to first if bleeding not controlled', detail: 'Overlap is acceptable; gap between tourniquets should be <2 cm.'),
      CheckStep(text: 'Monitor tourniquet site every 5 minutes for re-bleeding'),
      CheckStep(text: 'Document in MIST report and hand off to receiving provider'),
    ],
  ),

  Procedure(
    id: 'wound_packing',
    title: 'Wound Packing (Junctional / Torso)',
    category: 'Haemorrhage Control',
    description: 'For non-compressible wounds where tourniquet cannot be applied.',
    icon: Icons.healing,
    color: Color(0xFFD32F2F),
    steps: [
      CheckStep(text: 'Protect yourself — gloves on', isCritical: true),
      CheckStep(text: 'Expose wound fully — cut away all clothing', isCritical: true),
      CheckStep(text: 'Identify wound cavity and bleeding source'),
      CheckStep(text: 'If haemostatic dressing available (Combat Gauze / Celox): unroll into wound starting at bleeding source', isCritical: true,
          detail: 'Pack directly against the bleeding vessel, not just on top of blood.'),
      CheckStep(text: 'Pack additional gauze on top, layer by layer, filling cavity completely'),
      CheckStep(text: 'Apply firm direct pressure with both hands for MINIMUM 3 minutes', isCritical: true,
          detail: 'Use body weight. Do not lift hands to check — maintain continuous pressure.'),
      CheckStep(text: 'Apply pressure dressing over wound to maintain pressure'),
      CheckStep(text: 'If bleeding continues: remove dressing, re-pack, and reapply pressure for 5 minutes'),
      CheckStep(text: 'Do NOT remove packing in field — definitive surgical haemostasis required'),
      CheckStep(text: 'Monitor closely for recurrent bleeding and shock signs'),
    ],
  ),

  Procedure(
    id: 'ncd',
    title: 'Needle Chest Decompression',
    category: 'Respiratory',
    description: 'For suspected tension pneumothorax.',
    icon: Icons.air,
    color: Color(0xFF1565C0),
    steps: [
      CheckStep(text: 'Confirm clinical diagnosis of tension pneumothorax', isCritical: true,
          detail: 'Absent breath sounds, tracheal deviation (late), severe respiratory distress, hypotension, JVD. Do NOT wait for X-ray.'),
      CheckStep(text: 'Identify landmark — 2nd intercostal space (ICS), midclavicular line (MCL)', isCritical: true,
          detail: 'Alternative site: 4th or 5th ICS anterior axillary line (AAL) — preferred by some guidelines, less chest wall thickness.'),
      CheckStep(text: 'Prepare: 14G (adult) or 16G (pediatric) IV catheter ≥3.25 cm length',
          detail: 'A shorter catheter may fail to penetrate chest wall in obese patients. 8 cm catheters preferred in austere environments.'),
      CheckStep(text: 'Swab site with antiseptic if available and time permits'),
      CheckStep(text: 'Insert needle PERPENDICULAR to chest wall, directly over top of rib (avoid neurovascular bundle underneath)', isCritical: true),
      CheckStep(text: 'Advance until air rushes out (audible hiss) or resistance decreases', isCritical: true,
          detail: 'Confirm air release — if no hiss, may not be in pneumothorax or needle too short.'),
      CheckStep(text: 'Remove needle stylet — leave catheter in place'),
      CheckStep(text: 'Reassess: breath sounds, BP, HR, SpO₂, RR'),
      CheckStep(text: 'Secure catheter with tape — mark site clearly'),
      CheckStep(text: 'Prepare for finger thoracostomy or chest tube at definitive care'),
      CheckStep(text: 'Repeat on same side if symptoms recur (catheter may kink/occlude)'),
    ],
  ),

  Procedure(
    id: 'cpr_adult',
    title: 'Adult CPR',
    category: 'Resuscitation',
    description: 'AHA/BLS guidelines for adult cardiac arrest.',
    icon: Icons.favorite,
    color: Color(0xFFD32F2F),
    steps: [
      CheckStep(text: 'ENSURE SCENE SAFETY', isCritical: true),
      CheckStep(text: 'Check responsiveness — tap shoulders and shout "Are you OK?"'),
      CheckStep(text: 'Call for help / activate EMS — get AED if available', isCritical: true),
      CheckStep(text: 'Check for breathing and pulse simultaneously for NO MORE than 10 seconds', isCritical: true,
          detail: 'Carotid pulse in adults. If no pulse or pulse <60 with inadequate perfusion, begin CPR.'),
      CheckStep(text: 'Position patient: supine on firm flat surface', isCritical: true),
      CheckStep(text: 'Begin chest compressions — heel of hands on lower half of sternum', isCritical: true,
          detail: 'Rate: 100–120/min. Depth: 2–2.4 inches (5–6 cm). Allow full chest recoil. Minimise interruptions.'),
      CheckStep(text: 'Open airway after 30 compressions — head-tilt/chin-lift (or jaw thrust if trauma)'),
      CheckStep(text: 'Give 2 rescue breaths over 1 second each — visible chest rise', isCritical: true,
          detail: 'With BVM: squeeze to produce visible chest rise. Do NOT hyperventilate. If untrained: compression-only CPR is acceptable.'),
      CheckStep(text: 'Continue 30:2 ratio — minimize compression pauses to <10 sec'),
      CheckStep(text: 'Attach AED as soon as available — analyse rhythm and shock if advised', isCritical: true),
      CheckStep(text: 'Rotate compressors every 2 minutes to prevent fatigue'),
      CheckStep(text: 'Establish IV/IO access and administer Epinephrine 1 mg IV/IO q3–5 min'),
      CheckStep(text: 'Identify and treat reversible causes (H\'s and T\'s)',
          detail: 'Hypoxia, Hypovolaemia, H⁺ (acidosis), Hypo/hyperkalaemia, Hypothermia\nTension pneumo, Tamponade, Toxins, Thrombosis (PE/MI)'),
      CheckStep(text: 'ROSC check: rhythm, pulse, spontaneous breathing, pupil response'),
    ],
  ),

  Procedure(
    id: 'litter',
    title: 'Litter / Casualty Packaging',
    category: 'Evacuation',
    description: 'Prepare casualty for field evacuation.',
    icon: Icons.local_shipping,
    color: Color(0xFF6A1B9A),
    steps: [
      CheckStep(text: 'Complete MARCH assessment — all immediate threats addressed', isCritical: true),
      CheckStep(text: 'Document vital signs, interventions, medications, and times'),
      CheckStep(text: 'Position patient: supine unless contraindicated', detail: 'Recovery position for unconscious with intact airway. Semi-reclined for SOB/CHF. Lateral if vomiting.'),
      CheckStep(text: 'Ensure all bleeding controlled — check all dressings and tourniquets', isCritical: true),
      CheckStep(text: 'Secure all IV/IO lines — note insertion site and flow rate'),
      CheckStep(text: 'Protect airway device if in place — confirm position, secure tubing'),
      CheckStep(text: 'Apply hypothermia prevention: wool blanket + vapour barrier + reflect space blanket', isCritical: true,
          detail: 'Ground insulation critical — place sleeping pad under patient before blanket wrap.'),
      CheckStep(text: 'Pad all bony prominences: heels, sacrum, scapulae'),
      CheckStep(text: 'Secure patient with minimum 3 straps: chest, pelvis, thighs', detail: 'Chest strap: below axillae, not over arms. Allow chest wall movement for breathing.'),
      CheckStep(text: 'Secure head if spinal precautions required — use head blocks or improvised padding'),
      CheckStep(text: 'Ensure airway accessible during transport — check before moving'),
      CheckStep(text: 'Complete MIST/ATMIST handoff to receiving provider', isCritical: true,
          detail: 'M: Mechanism | I: Injuries found | S: Signs (vitals) | T: Treatments given\nA: Age/Sex | T: Time of injury'),
      CheckStep(text: 'Mark triage category on litter — T1 (immediate) / T2 (delayed) / T3 (minimal)'),
    ],
  ),

  Procedure(
    id: 'iv_access',
    title: 'Peripheral IV Access',
    category: 'Vascular Access',
    description: 'Standard peripheral intravenous cannulation.',
    icon: Icons.water_drop,
    color: Color(0xFF00796B),
    steps: [
      CheckStep(text: 'Gather equipment: IV catheter, tourniquet, swab, tape, IV fluid/flush', isCritical: true),
      CheckStep(text: 'Wash hands / don gloves'),
      CheckStep(text: 'Select vein: antecubital fossa (fastest) or dorsum of hand', detail: 'Use largest catheter feasible: 14G (major trauma), 16G (moderate bleed), 18G (standard), 20–22G (routine)'),
      CheckStep(text: 'Apply tourniquet 4–6 inches above intended site'),
      CheckStep(text: 'Clean site with antiseptic and allow to dry'),
      CheckStep(text: 'Anchor skin with non-dominant hand — insert catheter bevel up at 15–30° angle', isCritical: true),
      CheckStep(text: 'Advance until flash of blood in flashback chamber'),
      CheckStep(text: 'Lower angle — advance catheter over needle 2–3 mm further into vein, then advance catheter off needle'),
      CheckStep(text: 'Release tourniquet, remove needle, apply digital pressure over vein tip'),
      CheckStep(text: 'Attach extension set / cap — flush with 10 mL NS and confirm no infiltration', isCritical: true),
      CheckStep(text: 'Secure with transparent dressing and tape — label with date, time, gauge'),
      CheckStep(text: 'Dispose of sharp safely in sharps container immediately'),
    ],
  ),

  Procedure(
    id: 'io_access',
    title: 'IO Access (EZ-IO)',
    category: 'Vascular Access',
    description: 'Intraosseous access when IV access unobtainable.',
    icon: Icons.water_drop,
    color: Color(0xFF00796B),
    steps: [
      CheckStep(text: 'Indication: failed IV × 2 attempts in emergency, or cardiac arrest', isCritical: true),
      CheckStep(text: 'Select site: proximal tibia (preferred), distal tibia, or proximal humerus',
          detail: 'Proximal tibia: 2 cm distal and 2 cm medial to tibial tuberosity on flat medial surface.'),
      CheckStep(text: 'Assemble EZ-IO: select needle (pink 15 mm, blue 25 mm, yellow 45 mm)'),
      CheckStep(text: 'Identify landmarks — palpate flat medial tibial surface', isCritical: true),
      CheckStep(text: 'Clean site with antiseptic swab'),
      CheckStep(text: 'Position EZ-IO driver perpendicular to bone surface', isCritical: true),
      CheckStep(text: 'Apply firm pressure and engage drill — advance through cortex until loss of resistance', isCritical: true,
          detail: 'Stop when hub is at skin level or 5 mm of catheter visible. Do NOT advance too far.'),
      CheckStep(text: 'Remove EZ-IO driver while holding catheter hub firmly'),
      CheckStep(text: 'Attach syringe — aspirate bone marrow (confirms placement)', detail: 'Aspiration not always successful — absence does not confirm misplacement.'),
      CheckStep(text: 'Flush with 10 mL NS (lidocaine 40 mg IO first in conscious patients for pain)'),
      CheckStep(text: 'Attach IV tubing — use pressure bag or pump (IO flow rate is slow by gravity)'),
      CheckStep(text: 'Secure with EZ-Connect or tape — limit use to 24 hours then establish IV access'),
    ],
  ),

  Procedure(
    id: 'o2_admin',
    title: 'Oxygen Administration',
    category: 'Respiratory',
    description: 'Supplemental oxygen delivery in the field.',
    icon: Icons.air,
    color: Color(0xFF1565C0),
    steps: [
      CheckStep(text: 'Confirm indication: SpO₂ <94%, respiratory distress, altered LOC, shock, trauma', isCritical: true),
      CheckStep(text: 'Check O₂ cylinder: valve open, flow confirmed, adequate volume remaining'),
      CheckStep(text: 'Select delivery device based on clinical need:'),
      CheckStep(text: 'Nasal cannula: 1–6 L/min → FiO₂ 24–44%',
          detail: 'Best tolerated. Use for mild hypoxia in cooperative patients.'),
      CheckStep(text: 'Simple face mask: 6–10 L/min → FiO₂ 40–60%',
          detail: 'Must maintain ≥6 L/min to flush CO₂. For moderate hypoxia.'),
      CheckStep(text: 'Non-rebreather mask (NRB): 10–15 L/min → FiO₂ 60–90%', isCritical: true,
          detail: 'For severe hypoxia. Fill reservoir bag before placing. Valve must be intact.'),
      CheckStep(text: 'BVM with O₂: 15 L/min → FiO₂ ≥90%',
          detail: 'For apnoeic patients or those requiring assisted ventilation.'),
      CheckStep(text: 'Apply device, adjust fit, confirm O₂ flowing', isCritical: true),
      CheckStep(text: 'Reassess SpO₂ every 5 minutes — titrate to SpO₂ 94–99% (88–92% in COPD)'),
      CheckStep(text: 'Document: delivery device, flow rate, starting SpO₂, response'),
    ],
  ),
];

// ── Screens ───────────────────────────────────────────────────────────────────

class ProcedureListScreen extends StatelessWidget {
  const ProcedureListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Procedure>> grouped = {};
    for (final p in kProcedures) {
      grouped.putIfAbsent(p.category, () => []).add(p);
    }
    final categories = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Procedure Checklists')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: categories.map((cat) {
          final procs = grouped[cat]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text(cat, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              ...procs.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: p.color.withValues(alpha: 0.15),
                    child: Icon(p.icon, color: p.color, size: 20),
                  ),
                  title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p.steps.length} steps • ${p.description}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProcedureRunnerScreen(procedure: p))),
                ),
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class ProcedureRunnerScreen extends StatefulWidget {
  final Procedure procedure;
  const ProcedureRunnerScreen({super.key, required this.procedure});

  @override
  State<ProcedureRunnerScreen> createState() => _ProcedureRunnerScreenState();
}

class _ProcedureRunnerScreenState extends State<ProcedureRunnerScreen> {
  late List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = List.filled(widget.procedure.steps.length, false);
  }

  int get _completed => _checked.where((c) => c).length;
  bool get _allDone => _completed == widget.procedure.steps.length;

  void _reset() => setState(() => _checked = List.filled(widget.procedure.steps.length, false));

  @override
  Widget build(BuildContext context) {
    final proc = widget.procedure;
    return Scaffold(
      appBar: AppBar(
        title: Text(proc.title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reset', onPressed: _reset),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: proc.color.withValues(alpha: 0.1),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(proc.description, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: proc.steps.isEmpty ? 0 : _completed / proc.steps.length,
                backgroundColor: Colors.grey[300],
                color: _allDone ? Colors.green : proc.color,
              ),
              const SizedBox(height: 4),
              Text('$_completed / ${proc.steps.length} steps complete',
                  style: TextStyle(fontSize: 12, color: _allDone ? Colors.green : null)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: proc.steps.length,
              itemBuilder: (_, i) {
                final step = proc.steps[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: _checked[i]
                      ? Colors.green.withValues(alpha: 0.08)
                      : step.isCritical
                          ? Colors.red.withValues(alpha: 0.05)
                          : null,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _checked[i] = !_checked[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _checked[i] ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: _checked[i] ? Colors.green : step.isCritical ? Colors.red : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                if (step.isCritical)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('CRITICAL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                Expanded(
                                  child: Text(
                                    '${i + 1}. ${step.text}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: step.isCritical ? FontWeight.bold : FontWeight.normal,
                                      decoration: _checked[i] ? TextDecoration.lineThrough : null,
                                      color: _checked[i] ? Colors.grey : null,
                                    ),
                                  ),
                                ),
                              ]),
                              if (step.detail != null && !_checked[i]) ...[
                                const SizedBox(height: 4),
                                Text(step.detail!, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4)),
                              ],
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_allDone)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.green,
              child: const Text('✓ All steps complete', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
    );
  }
}
