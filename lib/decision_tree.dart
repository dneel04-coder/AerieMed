import 'package:flutter/material.dart';

// ── Data Model ────────────────────────────────────────────────────────────────

enum NodeType { question, action, terminal }

class TreeBranch {
  final String label;
  final String nextId;
  const TreeBranch({required this.label, required this.nextId});
}

class TreeNode {
  final String id;
  final NodeType type;
  final String text;
  final String? detail;
  final List<TreeBranch> branches;
  final Color? color;
  const TreeNode({
    required this.id,
    required this.type,
    required this.text,
    this.detail,
    this.branches = const [],
    this.color,
  });
}

class DecisionTree {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Map<String, TreeNode> nodes;
  final String startId;
  const DecisionTree({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.nodes,
    required this.startId,
  });
}

// ── Static Data ───────────────────────────────────────────────────────────────

final List<DecisionTree> kDecisionTrees = [
  // MARCH Protocol
  const DecisionTree(
    id: 'march',
    title: 'MARCH Protocol',
    subtitle: 'Tactical casualty assessment',
    icon: Icons.health_and_safety,
    color: Colors.red,
    startId: 'start',
    nodes: {
      'start': const TreeNode(
        id: 'start', type: NodeType.question,
        text: 'Is the scene safe to approach?',
        branches: [
          TreeBranch(label: 'Yes — scene safe', nextId: 'm_bleed'),
          TreeBranch(label: 'No — threat present', nextId: 'scene_unsafe'),
        ],
      ),
      'scene_unsafe': const TreeNode(
        id: 'scene_unsafe', type: NodeType.terminal,
        text: 'STOP — Do not approach.',
        detail: 'Move to cover. Request support. Do not become a second casualty. Suppress threat before rendering care.',
        color: Color(0xFFD32F2F),
      ),
      'm_bleed': const TreeNode(
        id: 'm_bleed', type: NodeType.question,
        text: 'M — Massive Hemorrhage\nIs there life-threatening external bleeding?',
        detail: 'Extremity amputation, junctional bleed, arterial pumping, or blood-soaked clothing.',
        branches: [
          TreeBranch(label: 'Yes — severe bleeding', nextId: 'm_tourniquet'),
          TreeBranch(label: 'No — no severe bleeding', nextId: 'a_airway'),
        ],
      ),
      'm_tourniquet': const TreeNode(
        id: 'm_tourniquet', type: NodeType.action,
        text: 'Apply tourniquet / wound packing',
        detail: '• Extremity: Apply tourniquet 2–3 inches above wound. Tighten until bleeding stops. Note time.\n• Junctional / torso: Pack wound firmly with Combat Gauze or hemostatic dressing. Apply direct pressure ≥3 min.\n• Reassess: confirm bleeding controlled before moving on.',
        branches: [TreeBranch(label: 'Bleeding controlled — continue', nextId: 'a_airway')],
      ),
      'a_airway': const TreeNode(
        id: 'a_airway', type: NodeType.question,
        text: 'A — Airway\nIs the airway patent?',
        detail: 'Look for gurgling, stridor, snoring, apnea, cyanosis, or altered LOC.',
        branches: [
          TreeBranch(label: 'Patent — airway open', nextId: 'r_resp'),
          TreeBranch(label: 'Compromised — needs intervention', nextId: 'a_open'),
        ],
      ),
      'a_open': const TreeNode(
        id: 'a_open', type: NodeType.action,
        text: 'Open and secure the airway',
        detail: '• Unconscious: Recovery position (if no spinal injury) or jaw thrust / chin lift.\n• NPA: Insert nasopharyngeal airway if gag reflex intact.\n• Supraglottic: Place iGel / King if NPA insufficient.\n• Surgical airway: Needle or surgical cric if above fail.\n• Suction secretions as needed.',
        branches: [TreeBranch(label: 'Airway secured — continue', nextId: 'r_resp')],
      ),
      'r_resp': const TreeNode(
        id: 'r_resp', type: NodeType.question,
        text: 'R — Respiration\nRR ____/min. Is breathing adequate?',
        detail: 'Normal RR: 12–20/min adult. Assess depth, symmetry, SpO₂. Inspect chest for wounds.',
        branches: [
          TreeBranch(label: 'Adequate (12–20, good depth)', nextId: 'c_circ'),
          TreeBranch(label: 'Tachypneic / labored / apneic', nextId: 'r_chest'),
          TreeBranch(label: 'Open chest wound visible', nextId: 'r_ocw'),
        ],
      ),
      'r_chest': const TreeNode(
        id: 'r_chest', type: NodeType.action,
        text: 'Support ventilation',
        detail: '• Apneic / agonal: BVM ventilations at 10–12/min. Supplement O₂.\n• Tachypneic: Administer high-flow O₂. Reassess for tension pneumo (tracheal deviation, absent breath sounds, hypotension).\n• If tension pneumo suspected: Needle decompression 2nd ICS MCL or 4th/5th ICS AAL.',
        branches: [TreeBranch(label: 'Breathing stabilised — continue', nextId: 'c_circ')],
      ),
      'r_ocw': const TreeNode(
        id: 'r_ocw', type: NodeType.action,
        text: 'Seal open chest wound',
        detail: '• Apply vented chest seal (Hyfin / Russell) over wound.\n• If no vented seal: use 3-sided dressing.\n• Monitor for developing tension pneumothorax — burp seal or perform needle decompression if deteriorates.',
        branches: [TreeBranch(label: 'Wound sealed — continue', nextId: 'c_circ')],
      ),
      'c_circ': const TreeNode(
        id: 'c_circ', type: NodeType.question,
        text: 'C — Circulation / Shock\nIs the patient showing signs of shock?',
        detail: 'HR >100, weak/absent radial pulse, pale/cool/clammy skin, AMS, SBP <90 mmHg.',
        branches: [
          TreeBranch(label: 'Signs of shock present', nextId: 'c_shock'),
          TreeBranch(label: 'Circulation adequate', nextId: 'h_hypo'),
        ],
      ),
      'c_shock': const TreeNode(
        id: 'c_shock', type: NodeType.action,
        text: 'Manage hemorrhagic shock',
        detail: '• Establish IV/IO access (18G or larger).\n• Permissive hypotension: target SBP 80–90 mmHg in penetrating trauma.\n• Fluid: 250 mL NS boluses, reassess after each; avoid over-resuscitation.\n• If available: 1:1 pRBC:FFP.\n• Control all bleeding sources — reassess tourniquet and wounds.\n• TXA: 1 g IV over 10 min if within 3 hrs of injury.',
        branches: [TreeBranch(label: 'Resuscitation initiated — continue', nextId: 'h_hypo')],
      ),
      'h_hypo': const TreeNode(
        id: 'h_hypo', type: NodeType.question,
        text: 'H — Hypothermia\nIs the patient at risk for hypothermia?',
        detail: 'Cold environment, wet clothing, exposed wounds, shock, altered LOC.',
        branches: [
          TreeBranch(label: 'Yes — hypothermia risk', nextId: 'h_warm'),
          TreeBranch(label: 'No — normothermic', nextId: 'march_complete'),
        ],
      ),
      'h_warm': const TreeNode(
        id: 'h_warm', type: NodeType.action,
        text: 'Prevent / treat hypothermia',
        detail: '• Remove wet clothing, insulate from ground.\n• Wrap in hypothermia prevention blanket / sleeping bag.\n• Cover head — significant heat loss via scalp.\n• Warm IV fluids if available.\n• Avoid rough handling (risk of VF in severe hypothermia).',
        branches: [TreeBranch(label: 'Hypothermia prevention applied', nextId: 'march_complete')],
      ),
      'march_complete': const TreeNode(
        id: 'march_complete', type: NodeType.terminal,
        text: 'MARCH complete — prepare for evacuation',
        detail: '• Reassess all interventions every 5 minutes.\n• Document time of tourniquet application.\n• Establish IV access if not done.\n• Administer analgesia (Ketamine 0.3 mg/kg IV or Fentanyl 1 mcg/kg IV) if patient is not in shock and airway is protected.\n• MIST handoff to receiving provider.',
        color: Color(0xFF2E7D32),
      ),
    },
  ),

  // Airway Assessment
  const DecisionTree(
    id: 'airway',
    title: 'Airway Assessment',
    subtitle: 'Rapid airway management',
    icon: Icons.air,
    color: Colors.blue,
    startId: 'start',
    nodes: {
      'start': const TreeNode(
        id: 'start', type: NodeType.question,
        text: 'Is the patient responsive?',
        branches: [
          TreeBranch(label: 'Yes — responsive', nextId: 'resp_airway'),
          TreeBranch(label: 'No — unresponsive', nextId: 'unresponsive'),
        ],
      ),
      'resp_airway': const TreeNode(
        id: 'resp_airway', type: NodeType.question,
        text: 'Can the patient speak clearly?',
        detail: 'Hoarse voice, stridor, inability to speak in full sentences, drooling — all suggest airway compromise.',
        branches: [
          TreeBranch(label: 'Yes — clear voice', nextId: 'airway_ok'),
          TreeBranch(label: 'No — voice changes / stridor', nextId: 'partial_obstruct'),
        ],
      ),
      'unresponsive': const TreeNode(
        id: 'unresponsive', type: NodeType.action,
        text: 'Open airway — jaw thrust / chin lift',
        detail: '• Jaw thrust (trauma): fingers behind mandible, lift anteriorly without extending neck.\n• Chin lift (no trauma concern): tilt head back, lift chin.\n• Look, Listen, Feel for breathing for no more than 10 seconds.',
        branches: [
          TreeBranch(label: 'Breathing present', nextId: 'recovery'),
          TreeBranch(label: 'Not breathing / agonal', nextId: 'bvm'),
        ],
      ),
      'recovery': const TreeNode(
        id: 'recovery', type: NodeType.action,
        text: 'Place in recovery position, insert NPA',
        detail: '• NPA: lubricate and insert bevel toward septum. Select size = distance from nostril to earlobe.\n• Recovery position: lateral, dependent arm extended, mouth slightly down to drain secretions.\n• Monitor continuously, reassess every 2–3 min.',
        branches: [TreeBranch(label: 'Patient stable — monitor', nextId: 'airway_ok')],
      ),
      'bvm': const TreeNode(
        id: 'bvm', type: NodeType.action,
        text: 'BVM ventilations — call for ALS',
        detail: '• Establish 2-person BVM if available (one seals, one squeezes).\n• Ventilate at 10–12/min adult; 1 breath / 5–6 seconds.\n• Supplement 15 L/min O₂.\n• Consider supraglottic airway (iGel) if BVM ineffective.\n• Prepare for intubation or surgical airway if above fail.',
        branches: [TreeBranch(label: 'Ventilating — reassess', nextId: 'airway_ok')],
      ),
      'partial_obstruct': const TreeNode(
        id: 'partial_obstruct', type: NodeType.question,
        text: 'Is there a visible obstruction?',
        detail: 'Foreign body, food, blood, secretions, swelling (angioedema, infection, burns).',
        branches: [
          TreeBranch(label: 'Foreign body — conscious patient', nextId: 'fb_conscious'),
          TreeBranch(label: 'Swelling / secretions / other', nextId: 'suction_pos'),
        ],
      ),
      'fb_conscious': const TreeNode(
        id: 'fb_conscious', type: NodeType.action,
        text: 'Partial obstruction — encourage coughing',
        detail: '• If coughing effectively: encourage coughing, do NOT intervene.\n• If cough ineffective: 5 back blows between shoulder blades, then 5 abdominal thrusts (Heimlich).\n• If unconscious: lower to ground, start CPR (compressions may dislodge FB), look in mouth each time before ventilating.',
        branches: [TreeBranch(label: 'Obstruction cleared', nextId: 'airway_ok')],
      ),
      'suction_pos': const TreeNode(
        id: 'suction_pos', type: NodeType.action,
        text: 'Suction, position, consider NPA / SGA',
        detail: '• Suction with rigid Yankauer catheter ≤15 seconds at a time.\n• Position: sniffing position (adult) or neutral (pediatric).\n• Angioedema / epiglottitis: administer Epinephrine 0.3 mg IM, prepare for surgical airway — do NOT attempt blind intubation.\n• Prepare RSI / surgical airway if deteriorating.',
        branches: [TreeBranch(label: 'Airway managed', nextId: 'airway_ok')],
      ),
      'airway_ok': const TreeNode(
        id: 'airway_ok', type: NodeType.terminal,
        text: 'Airway patent — continue assessment',
        detail: '• Continue monitoring: SpO₂, ETCO₂ if available, respiratory rate.\n• Maintain positioning: 30–45° HOB if not contraindicated.\n• Have suction and airway adjuncts immediately available.\n• Reassess after any patient movement.',
        color: Color(0xFF1565C0),
      ),
    },
  ),

  // Shock Assessment
  const DecisionTree(
    id: 'shock',
    title: 'Shock Assessment',
    subtitle: 'Identify and manage shock',
    icon: Icons.favorite,
    color: Colors.orange,
    startId: 'start',
    nodes: {
      'start': const TreeNode(
        id: 'start', type: NodeType.question,
        text: 'Does the patient have signs of shock?\n\nHR >100, weak pulse, pale/cool/clammy skin, AMS, SBP <90, cap refill >2 sec',
        branches: [
          TreeBranch(label: 'Yes — shock suspected', nextId: 'type'),
          TreeBranch(label: 'No — hemodynamically stable', nextId: 'no_shock'),
        ],
      ),
      'no_shock': const TreeNode(
        id: 'no_shock', type: NodeType.terminal,
        text: 'No shock — continue monitoring',
        detail: 'Reassess vitals every 5 minutes. Establish IV access. Identify and treat underlying cause.',
        color: Color(0xFF2E7D32),
      ),
      'type': const TreeNode(
        id: 'type', type: NodeType.question,
        text: 'What is the most likely cause of shock?',
        branches: [
          TreeBranch(label: 'Trauma / visible bleeding', nextId: 'hemorrhagic'),
          TreeBranch(label: 'Rash, hives, allergic exposure', nextId: 'anaphylactic'),
          TreeBranch(label: 'Chest pain, abnormal ECG', nextId: 'cardiogenic'),
          TreeBranch(label: 'Fever, infection suspected', nextId: 'septic'),
        ],
      ),
      'hemorrhagic': const TreeNode(
        id: 'hemorrhagic', type: NodeType.action,
        text: 'Hemorrhagic Shock — control bleeding',
        detail: '• Immediately control all bleeding: tourniquet, wound packing, pressure.\n• IV/IO access × 2 large bore (16G+).\n• Permissive hypotension: SBP 80–90 in penetrating trauma; SBP 90–100 if TBI suspected.\n• Fluid: 250 mL boluses, reassess HR and skin perfusion.\n• TXA 1 g IV over 10 min (within 3 hrs of injury).\n• Warm fluids. Prevent hypothermia.\n• Emergent surgical intervention required — call for evacuation.',
        branches: [TreeBranch(label: 'Interventions applied', nextId: 'reassess')],
      ),
      'anaphylactic': const TreeNode(
        id: 'anaphylactic', type: NodeType.action,
        text: 'Anaphylactic Shock',
        detail: '• Epinephrine 0.3 mg IM (1:1,000) anterolateral thigh — repeat in 5–15 min if no improvement.\n• Remove/identify allergen.\n• Position: supine with legs elevated (unless SOB — then seated).\n• IV access: 1 L NS bolus.\n• Diphenhydramine 50 mg IV/IM.\n• Methylprednisolone 125 mg IV.\n• Albuterol nebuliser if bronchospasm.\n• If refractory: Epinephrine infusion.',
        branches: [TreeBranch(label: 'Treatment given', nextId: 'reassess')],
      ),
      'cardiogenic': const TreeNode(
        id: 'cardiogenic', type: NodeType.action,
        text: 'Cardiogenic Shock',
        detail: '• 12-lead ECG immediately — identify STEMI.\n• Aspirin 324 mg PO (chewed) if not contraindicated.\n• Oxygen to maintain SpO₂ ≥94%.\n• Cautious fluid challenge: 250 mL (avoid in pulmonary oedema).\n• Do NOT give nitroglycerin if SBP <90.\n• Prepare for cath lab / advanced intervention — urgent evacuation.\n• Consider vasopressors per ALS protocol.',
        branches: [TreeBranch(label: 'Treatment initiated', nextId: 'reassess')],
      ),
      'septic': const TreeNode(
        id: 'septic', type: NodeType.action,
        text: 'Septic Shock — Hour-1 Bundle',
        detail: '• IV/IO access × 2.\n• 30 mL/kg crystalloid bolus (NS or LR) within 1 hour — reassess after each 500 mL.\n• Blood cultures × 2 before antibiotics if possible.\n• Broad-spectrum antibiotics ASAP (within 1 hour).\n• Vasopressors (Norepinephrine) if refractory to fluids: target MAP ≥65 mmHg.\n• Lactate: if ≥4 mmol/L = poor prognosis, aggressive resuscitation.\n• Foley catheter: target UO ≥0.5 mL/kg/hr.',
        branches: [TreeBranch(label: 'Bundle initiated', nextId: 'reassess')],
      ),
      'reassess': const TreeNode(
        id: 'reassess', type: NodeType.question,
        text: 'Reassess after interventions.\nIs the patient responding to treatment?',
        detail: 'Improving: HR trending down, BP improving, skin warmer, more alert.\nNot improving: HR still >120, BP <80, deteriorating LOC.',
        branches: [
          TreeBranch(label: 'Improving — continue care', nextId: 'improving'),
          TreeBranch(label: 'Not responding — escalate', nextId: 'escalate'),
        ],
      ),
      'improving': const TreeNode(
        id: 'improving', type: NodeType.terminal,
        text: 'Patient responding — continue monitoring',
        detail: '• Vitals every 5 minutes.\n• Maintain IV access.\n• Reassess for secondary injuries.\n• Arrange appropriate transport / definitive care.',
        color: Color(0xFF2E7D32),
      ),
      'escalate': const TreeNode(
        id: 'escalate', type: NodeType.terminal,
        text: 'No response — escalate care immediately',
        detail: '• Reassess airway and breathing.\n• Consider missed injury (tension pneumo, cardiac tamponade).\n• Beck\'s Triad for tamponade: hypotension + distended neck veins + muffled heart sounds → pericardiocentesis.\n• Needle decompression if tension pneumo suspected.\n• Urgent evacuation. Continue resuscitation en route.',
        color: Color(0xFFD32F2F),
      ),
    },
  ),

  // Altered Mental Status
  const DecisionTree(
    id: 'ams',
    title: 'Altered Mental Status',
    subtitle: 'AEIOU-TIPS assessment',
    icon: Icons.psychology,
    color: Colors.purple,
    startId: 'start',
    nodes: {
      'start': const TreeNode(
        id: 'start', type: NodeType.question,
        text: 'Is the patient responsive?\n\nCheck AVPU: Alert / Voice / Pain / Unresponsive',
        branches: [
          TreeBranch(label: 'Alert and oriented (A&Ox4)', nextId: 'aox4'),
          TreeBranch(label: 'Confused / disoriented', nextId: 'glucose'),
          TreeBranch(label: 'Responds to voice/pain only', nextId: 'airway_protect'),
          TreeBranch(label: 'Unresponsive (U)', nextId: 'unresponsive'),
        ],
      ),
      'aox4': const TreeNode(
        id: 'aox4', type: NodeType.terminal,
        text: 'Patient alert and oriented — no AMS',
        detail: 'Continue monitoring. Establish baseline. Document orientation and GCS.',
        color: Color(0xFF2E7D32),
      ),
      'glucose': const TreeNode(
        id: 'glucose', type: NodeType.question,
        text: 'Check blood glucose immediately.\n\nBGL result?',
        branches: [
          TreeBranch(label: '<70 mg/dL — hypoglycaemic', nextId: 'hypoglycaemia'),
          TreeBranch(label: '>300 mg/dL — hyperglycaemic', nextId: 'hyperglycaemia'),
          TreeBranch(label: '70–300 mg/dL — normal BGL', nextId: 'aeiou'),
        ],
      ),
      'hypoglycaemia': const TreeNode(
        id: 'hypoglycaemia', type: NodeType.action,
        text: 'Treat hypoglycaemia',
        detail: '• Conscious, can swallow: 15–20 g oral glucose (juice, glucose gel, 4 glucose tablets).\n• Unconscious / unable to swallow: Dextrose 25–50 g IV (D50W 50 mL IV) or Glucagon 1 mg IM.\n• Recheck BGL in 15 minutes.\n• Once >80 mg/dL: give complex carbohydrate snack.\n• Identify and treat underlying cause (insulin overdose, missed meal).',
        branches: [TreeBranch(label: 'Glucose given — reassess', nextId: 'reassess_ams')],
      ),
      'hyperglycaemia': const TreeNode(
        id: 'hyperglycaemia', type: NodeType.action,
        text: 'Manage hyperglycaemia / DKA',
        detail: '• Check ketones if possible. Fruity breath, Kussmaul respirations → DKA.\n• IV access: 1 L NS over 1 hour.\n• Monitor K⁺ before insulin (insulin drops K⁺).\n• Insulin per ALS protocol.\n• DKA requires ICU — arrange urgent evacuation.\n• Hyperosmolar hyperglycaemic state (HHS): gradual correction with fluids.',
        branches: [TreeBranch(label: 'Treatment initiated', nextId: 'reassess_ams')],
      ),
      'aeiou': const TreeNode(
        id: 'aeiou', type: NodeType.question,
        text: 'AEIOU-TIPS — What is the most likely cause?',
        detail: 'A=Alcohol/Acidosis, E=Epilepsy, I=Infection/Insulin, O=Overdose/O₂, U=Uraemia\nT=Trauma, I=Infection, P=Psychiatric/Poisoning, S=Stroke/Structural',
        branches: [
          TreeBranch(label: 'Seizure activity (E)', nextId: 'seizure'),
          TreeBranch(label: 'Overdose / intoxication (O)', nextId: 'overdose'),
          TreeBranch(label: 'Stroke symptoms (S)', nextId: 'stroke'),
          TreeBranch(label: 'Head trauma (T)', nextId: 'tbi'),
        ],
      ),
      'seizure': const TreeNode(
        id: 'seizure', type: NodeType.action,
        text: 'Active seizure management',
        detail: '• Protect from injury — do NOT restrain, clear area.\n• Time the seizure.\n• Position: recovery position after convulsion ends.\n• If >5 min (status): Midazolam 5 mg IM (buccal or IN) or Diazepam 10 mg PR.\n• Second line: Lorazepam 4 mg IV.\n• Third line: Levetiracetam 60 mg/kg IV or Phenytoin 20 mg/kg IV.\n• Correct hypoglycaemia, hypoxia, hyponatraemia.',
        branches: [TreeBranch(label: 'Seizure controlled', nextId: 'reassess_ams')],
      ),
      'overdose': const TreeNode(
        id: 'overdose', type: NodeType.action,
        text: 'Suspected overdose',
        detail: '• Opioid (miosis, bradypnoea, unresponsive): Naloxone 0.4–2 mg IV/IM/IN — repeat every 2–3 min.\n• Benzodiazepine (sedated): supportive care; Flumazenil rarely used (precipitates seizures).\n• Stimulants (agitation, tachycardia): Midazolam 5 mg IM for agitation.\n• Unknown: protect airway, supportive care, contact poison control.\n• Decontamination: Activated charcoal if <1 hr, awake, protected airway.',
        branches: [TreeBranch(label: 'Treatment given', nextId: 'reassess_ams')],
      ),
      'stroke': const TreeNode(
        id: 'stroke', type: NodeType.action,
        text: 'Suspected stroke — BE-FAST assessment',
        detail: '• BE-FAST: Balance, Eyes, Face droop, Arm drift, Speech, Time to call.\n• Last known well time — critical for thrombolysis eligibility (<4.5 hrs).\n• Glucose: correct if <60 mg/dL.\n• O₂: maintain SpO₂ ≥94%.\n• Do NOT lower BP unless >220/120 or ordered.\n• NPO — aspiration risk.\n• Urgent CT head required — activate stroke alert, evacuate.',
        branches: [TreeBranch(label: 'Stroke alert activated', nextId: 'reassess_ams')],
      ),
      'tbi': const TreeNode(
        id: 'tbi', type: NodeType.action,
        text: 'Traumatic Brain Injury',
        detail: '• GCS score: E+V+M (mild ≥13, moderate 9–12, severe ≤8).\n• Maintain SpO₂ ≥95%, PaCO₂ 35–40 mmHg.\n• Target SBP ≥90 mmHg (cerebral perfusion pressure).\n• HOB 30°, midline head position.\n• Avoid hypotonic fluids (NS preferred).\n• Seizure prophylaxis: Levetiracetam 500 mg IV.\n• Herniation signs (Cushing\'s triad, unequal pupils): controlled hyperventilation ETCO₂ 30–35.',
        branches: [TreeBranch(label: 'TBI management initiated', nextId: 'reassess_ams')],
      ),
      'airway_protect': const TreeNode(
        id: 'airway_protect', type: NodeType.action,
        text: 'Diminished consciousness — protect airway',
        detail: '• GCS ≤8: definitive airway strongly recommended (intubation).\n• Position: recovery / lateral decubitus.\n• Suction: clear secretions.\n• NPA: insert to maintain airway patency.\n• Reassess BGL, SpO₂, pupils.\n• Consider RSI if available and indicated.',
        branches: [TreeBranch(label: 'Airway protected — check BGL', nextId: 'glucose')],
      ),
      'unresponsive': const TreeNode(
        id: 'unresponsive', type: NodeType.action,
        text: 'Unresponsive patient — simultaneous actions',
        detail: '• Open airway, ventilate as needed.\n• Check pulse — begin CPR if absent.\n• IV/IO access, BGL, SpO₂, ECG.\n• Naloxone 2 mg IV/IM/IN empirically.\n• Dextrose 25 g IV empirically if BGL unavailable.\n• Thiamine 100 mg IV before dextrose if alcoholism suspected.',
        branches: [TreeBranch(label: 'Resuscitation initiated', nextId: 'reassess_ams')],
      ),
      'reassess_ams': const TreeNode(
        id: 'reassess_ams', type: NodeType.terminal,
        text: 'Reassess mental status — monitor closely',
        detail: '• Repeat AVPU / GCS every 5 minutes.\n• Continue monitoring BGL, SpO₂, vitals.\n• Document any changes.\n• Prepare for transport to definitive care.',
        color: Color(0xFF6A1B9A),
      ),
    },
  ),

  // Anaphylaxis
  const DecisionTree(
    id: 'anaphylaxis',
    title: 'Anaphylaxis',
    subtitle: 'Rapid recognition and treatment',
    icon: Icons.warning_amber,
    color: Colors.deepOrange,
    startId: 'start',
    nodes: {
      'start': const TreeNode(
        id: 'start', type: NodeType.question,
        text: 'Suspect anaphylaxis?\n\nSudden onset after exposure to potential allergen with ≥2 organ systems involved.',
        branches: [
          TreeBranch(label: 'Yes — anaphylaxis suspected', nextId: 'severity'),
          TreeBranch(label: 'Mild allergic reaction only', nextId: 'mild'),
        ],
      ),
      'mild': const TreeNode(
        id: 'mild', type: NodeType.action,
        text: 'Mild allergic reaction',
        detail: '• Diphenhydramine 25–50 mg PO/IV/IM.\n• Prednisone 40–60 mg PO.\n• Monitor for progression to anaphylaxis × 4–6 hours.\n• Avoid known allergen.\n• Consider auto-injector prescription on discharge.',
        branches: [TreeBranch(label: 'Monitor — watch for progression', nextId: 'mild_monitor')],
      ),
      'mild_monitor': const TreeNode(
        id: 'mild_monitor', type: NodeType.question,
        text: 'Is the reaction progressing?',
        detail: 'New symptoms: throat tightness, stridor, urticaria spreading, hypotension, nausea/vomiting.',
        branches: [
          TreeBranch(label: 'Yes — progressing', nextId: 'severity'),
          TreeBranch(label: 'No — stable', nextId: 'discharge'),
        ],
      ),
      'discharge': const TreeNode(
        id: 'discharge', type: NodeType.terminal,
        text: 'Mild reaction — safe for discharge',
        detail: '• Ensure allergen avoided.\n• Prescribe EpiPen × 2 + instruction on use.\n• Antihistamine course 3–5 days.\n• Return precautions: throat tightness, difficulty breathing, dizziness → 911 immediately.',
        color: Color(0xFF2E7D32),
      ),
      'severity': const TreeNode(
        id: 'severity', type: NodeType.question,
        text: 'What is the severity?',
        detail: 'Severe: stridor, wheeze, hypotension (SBP <90), collapse, loss of consciousness.\nModerate: urticaria + angioedema + nausea/vomiting/abdominal pain.',
        branches: [
          TreeBranch(label: 'Severe — cardiovascular/respiratory', nextId: 'epi_im'),
          TreeBranch(label: 'Moderate — skin + GI only', nextId: 'epi_im'),
        ],
      ),
      'epi_im': const TreeNode(
        id: 'epi_im', type: NodeType.action,
        text: 'EPINEPHRINE — administer immediately',
        detail: '• Epinephrine 0.3–0.5 mg IM (1:1,000) anterolateral mid-thigh.\n• Pediatric: 0.01 mg/kg IM (max 0.5 mg).\n• Can repeat every 5–15 min × 3 doses.\n• This is the FIRST and MOST IMPORTANT treatment — do not delay for antihistamines.',
        branches: [TreeBranch(label: 'Epi given — assess response', nextId: 'position')],
      ),
      'position': const TreeNode(
        id: 'position', type: NodeType.action,
        text: 'Position and support',
        detail: '• Supine with legs elevated — unless dyspnoeic (then semi-reclined) or vomiting (lateral).\n• Oxygen: 10–15 L/min NRB mask.\n• IV access: large bore × 2.\n• 1 L NS bolus if hypotensive.\n• Albuterol 2.5 mg nebulised if bronchospasm.',
        branches: [TreeBranch(label: 'Positioned and supported', nextId: 'secondary')],
      ),
      'secondary': const TreeNode(
        id: 'secondary', type: NodeType.action,
        text: 'Secondary medications',
        detail: '• Diphenhydramine 50 mg IV/IM (H1 blocker).\n• Ranitidine 50 mg IV or famotidine 20 mg IV (H2 blocker).\n• Methylprednisolone 125 mg IV (onset 4–6 hrs, prevents biphasic reaction).\n• Glucagon 1–5 mg IV if on beta-blockers (refractory hypotension).',
        branches: [TreeBranch(label: 'Secondary meds given', nextId: 'resp_epi')],
      ),
      'resp_epi': const TreeNode(
        id: 'resp_epi', type: NodeType.question,
        text: 'Response to Epinephrine?',
        branches: [
          TreeBranch(label: 'Improving — HR ↓, BP ↑, wheeze ↓', nextId: 'monitor_anaphylaxis'),
          TreeBranch(label: 'No response after 2 doses', nextId: 'refractory'),
        ],
      ),
      'monitor_anaphylaxis': const TreeNode(
        id: 'monitor_anaphylaxis', type: NodeType.terminal,
        text: 'Improving — observe ≥4–6 hours for biphasic reaction',
        detail: '• Biphasic reaction in 5–20% of cases, up to 72 hrs.\n• Continue O₂ and IV access.\n• Repeat vitals every 15 min × 4, then every 30 min.\n• Discharge with EpiPen × 2, antihistamines, steroid course, allergy referral.',
        color: Color(0xFF2E7D32),
      ),
      'refractory': const TreeNode(
        id: 'refractory', type: NodeType.terminal,
        text: 'Refractory anaphylaxis — escalate',
        detail: '• Epinephrine infusion: 0.1–1 mcg/kg/min titrated to MAP ≥65.\n• Vasopressin 40 units IV bolus (if beta-blocker on board).\n• Intubation if airway threatened.\n• ICU admission required — urgent evacuation.\n• Methylene blue 1–2 mg/kg IV for refractory vasodilation (last resort).',
        color: Color(0xFFD32F2F),
      ),
    },
  ),
];

// ── Screens ───────────────────────────────────────────────────────────────────

class DecisionTreeScreen extends StatelessWidget {
  const DecisionTreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Decision Trees')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kDecisionTrees.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final tree = kDecisionTrees[index];
          return Card(
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: tree.color.withValues(alpha: 0.15),
                child: Icon(tree.icon, color: tree.color),
              ),
              title: Text(tree.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(tree.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TreeRunnerScreen(tree: tree)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class TreeRunnerScreen extends StatefulWidget {
  final DecisionTree tree;
  const TreeRunnerScreen({super.key, required this.tree});

  @override
  State<TreeRunnerScreen> createState() => _TreeRunnerScreenState();
}

class _TreeRunnerScreenState extends State<TreeRunnerScreen> {
  late String _currentId;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _currentId = widget.tree.startId;
  }

  TreeNode get _current => widget.tree.nodes[_currentId]!;

  void _navigate(String nextId) {
    setState(() {
      _history.add(_currentId);
      _currentId = nextId;
    });
  }

  void _back() {
    if (_history.isEmpty) return;
    setState(() {
      _currentId = _history.removeLast();
    });
  }

  void _restart() {
    setState(() {
      _history.clear();
      _currentId = widget.tree.startId;
    });
  }

  Color _nodeColor(BuildContext context) {
    if (_current.color != null) return _current.color!;
    switch (_current.type) {
      case NodeType.question: return Theme.of(context).colorScheme.primaryContainer;
      case NodeType.action: return Theme.of(context).colorScheme.secondaryContainer;
      case NodeType.terminal: return Theme.of(context).colorScheme.tertiaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = _current;
    final nodeColor = _nodeColor(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tree.title),
        actions: [
          if (_history.isNotEmpty)
            IconButton(icon: const Icon(Icons.undo), tooltip: 'Back', onPressed: _back),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Restart', onPressed: _restart),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Step ${_history.length + 1}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
                ),
              ),
            Card(
              color: nodeColor,
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                        node.type == NodeType.question ? Icons.help_outline
                            : node.type == NodeType.action ? Icons.build_circle_outlined
                            : Icons.flag_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        node.type == NodeType.question ? 'ASSESS' : node.type == NodeType.action ? 'INTERVENE' : 'RESULT',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Text(node.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    if (node.detail != null) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(node.detail!, style: const TextStyle(fontSize: 14, height: 1.6)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (node.branches.isNotEmpty) ...[
              Text('Choose action:', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              ...node.branches.map((branch) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => _navigate(branch.nextId),
                  child: Text(branch.label, style: const TextStyle(fontSize: 15)),
                ),
              )),
            ],
            if (node.type == NodeType.terminal) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh),
                label: const Text('Start Over'),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
