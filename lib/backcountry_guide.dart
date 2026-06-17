import 'package:flutter/material.dart';


// ── Data model ────────────────────────────────────────────────────────────────

class FieldStep {
  final String text;
  final String? detail;
  final bool isCritical;
  const FieldStep({required this.text, this.detail, this.isCritical = false});
}

class BackcountryCondition {
  final String id;
  final String title;
  final String category;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> symptoms;
  final List<FieldStep> steps;
  final List<String> prevention;
  final String evacuate;
  const BackcountryCondition({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.icon,
    required this.color,
    required this.symptoms,
    required this.steps,
    required this.prevention,
    required this.evacuate,
  });
}


// ── Condition data ────────────────────────────────────────────────────────────

const List<BackcountryCondition> kBackcountryConditions = [

  // ── Skin & Wounds ──────────────────────────────────────────────────────────

  BackcountryCondition(
    id: 'blister',
    title: 'Blisters',
    category: 'Skin & Wounds',
    description: 'Fluid-filled pockets caused by friction or heat.',
    icon: Icons.circle_outlined,
    color: Color(0xFFE65100),
    symptoms: [
      'Localized burning or hot spot on skin',
      'Raised fluid-filled bubble',
      'Pain with pressure or movement',
      'Surrounding redness',
    ],
    steps: [
      FieldStep(text: 'Do NOT drain small, intact blisters — the roof protects against infection',
          detail: 'If the blister is in a high-pressure area (sole, heel) and walking must continue, draining may be necessary.'),
      FieldStep(text: 'Clean the area with antiseptic wipe or soap and water', isCritical: true),
      FieldStep(text: 'To drain (large or painful): sterilize a needle with flame or alcohol',
          detail: 'Pierce blister at the edge in 1–2 spots. Allow fluid to drain completely. Do NOT remove the roof.'),
      FieldStep(text: 'Apply antibiotic ointment (if available) to the drained blister surface'),
      FieldStep(text: 'Cover with a non-stick dressing or moleskin donut pad',
          detail: 'Cut a hole in the center of moleskin the size of the blister. Hole protects the blister; donut wall distributes pressure.'),
      FieldStep(text: 'Secure dressing with medical tape'),
      FieldStep(text: 'Change dressing daily or when wet/soiled; inspect for signs of infection',
          detail: 'Warning signs: increasing redness, warmth, pus, red streaks radiating from site, fever.'),
    ],
    prevention: [
      'Wear moisture-wicking socks and properly fitted boots',
      'Break in footwear before extended trips',
      'Apply moleskin or athletic tape to known hot spots before hiking',
      'Keep feet dry; change socks when wet',
      'Use foot powder to reduce friction',
    ],
    evacuate: 'Evacuate if signs of infection develop: pus, spreading redness, red streaks, fever, or increasing pain beyond 48 hours.',
  ),

  BackcountryCondition(
    id: 'abrasion',
    title: 'Abrasions & Road Rash',
    category: 'Skin & Wounds',
    description: 'Superficial skin scrape from friction with rough surface.',
    icon: Icons.healing,
    color: Color(0xFFE65100),
    symptoms: [
      'Raw, scraped skin surface',
      'Bleeding (usually oozing, not flowing)',
      'Embedded debris (dirt, gravel)',
      'Pain and burning',
    ],
    steps: [
      FieldStep(text: 'Control bleeding with direct pressure using clean cloth', isCritical: true),
      FieldStep(text: 'Irrigate wound aggressively with clean water — use a syringe if available',
          detail: 'Flush for 2–5 minutes. High-pressure irrigation removes debris and bacteria. Saline preferred; clean drinking water acceptable.'),
      FieldStep(text: 'Remove embedded debris with tweezers if visible and accessible',
          detail: 'Do NOT dig for deeply embedded debris. Leave for definitive care.'),
      FieldStep(text: 'Apply antibiotic ointment (bacitracin or triple antibiotic) if available'),
      FieldStep(text: 'Cover with non-stick dressing or moist gauze; secure with tape'),
      FieldStep(text: 'Inspect and re-irrigate daily; change dressing when wet or soiled'),
    ],
    prevention: [
      'Wear long pants and sleeves in technical terrain',
      'Use gloves during scrambling or climbing',
      'Stay alert on loose or rocky trails',
    ],
    evacuate: 'Evacuate if wound is deep (muscle visible), heavily contaminated, cannot be cleaned, or shows infection signs.',
  ),

  BackcountryCondition(
    id: 'laceration',
    title: 'Lacerations (Minor)',
    category: 'Skin & Wounds',
    description: 'Clean cut to the skin requiring closure.',
    icon: Icons.healing,
    color: Color(0xFFD32F2F),
    symptoms: [
      'Defined cut with clean or ragged edges',
      'Bleeding — may be moderate',
      'Pain at wound site',
      'Possible gaping wound edges',
    ],
    steps: [
      FieldStep(text: 'Control bleeding — apply direct pressure for 5–10 minutes without lifting', isCritical: true,
          detail: 'If bleeding through: add more gauze on top, do NOT remove existing. Elevate if extremity.'),
      FieldStep(text: 'Once bleeding controlled — irrigate copiously with clean water', isCritical: true),
      FieldStep(text: 'Inspect wound: check depth, assess for tendon/nerve/vessel involvement',
          detail: 'If unable to fully see the wound base, assume it is deep. Do not probe with fingers.'),
      FieldStep(text: 'Close the wound with steri-strips, wound closure strips, or butterfly closures',
          detail: 'Approximate wound edges — do not pull tightly. Apply strips perpendicular to wound. Leave small gaps for drainage.'),
      FieldStep(text: 'Apply antibiotic ointment and cover with non-stick dressing'),
      FieldStep(text: 'Inspect daily for infection signs — redness, warmth, swelling, pus, fever'),
    ],
    prevention: [
      'Handle knives and sharp tools carefully',
      'Keep tools sharp — dull tools require more force and slip',
      'Wear gloves when handling tools in the field',
    ],
    evacuate: 'Evacuate for: deep or gaping wounds, wounds over joints, facial wounds, suspected tendon/nerve damage, animal bite lacerations, wounds showing infection.',
  ),

  BackcountryCondition(
    id: 'splinter',
    title: 'Splinters & Embedded Objects',
    category: 'Skin & Wounds',
    description: 'Foreign material embedded in skin.',
    icon: Icons.linear_scale,
    color: Color(0xFFE65100),
    symptoms: [
      'Visible or palpable foreign object under skin',
      'Point tenderness',
      'Localized redness',
      'Difficulty bearing weight or using affected area',
    ],
    steps: [
      FieldStep(text: 'Clean the area and sterilize tweezers with alcohol or flame', isCritical: true),
      FieldStep(text: 'Grasp the splinter as close to the skin surface as possible with tweezers'),
      FieldStep(text: 'Pull in the same direction the splinter entered — steady, controlled traction',
          detail: 'Avoid squeezing the splinter — can break it and drive it deeper.'),
      FieldStep(text: 'If splinter breaks or is deeply embedded: use a sterilized needle to enlarge the entry point, then extract'),
      FieldStep(text: 'Irrigate the site after removal'),
      FieldStep(text: 'Apply antibiotic ointment and cover with bandage'),
      FieldStep(text: 'Monitor for infection over 24–48 hours'),
    ],
    prevention: [
      'Wear gloves when handling wood or brush',
      'Check hands and feet after moving through dense vegetation',
    ],
    evacuate: 'Evacuate if object is deeply embedded and cannot be removed, if located near an eye, or if infection develops.',
  ),


  // ── Musculoskeletal ────────────────────────────────────────────────────────

  BackcountryCondition(
    id: 'ankle_sprain',
    title: 'Ankle Sprain',
    category: 'Musculoskeletal',
    description: 'Ligament stretch or tear from ankle rolling or twisting.',
    icon: Icons.accessibility_new,
    color: Color(0xFF6A1B9A),
    symptoms: [
      'Immediate pain at ankle following a twist or roll',
      'Swelling within minutes to hours',
      'Bruising (may develop over hours)',
      'Tenderness to palpation over ligament',
      'Reduced range of motion',
      'Pain with weight bearing (mild–severe)',
    ],
    steps: [
      FieldStep(text: 'RICE — Rest, Ice, Compression, Elevation', isCritical: true),
      FieldStep(text: 'Rest: stop activity and minimize weight bearing initially'),
      FieldStep(text: 'Ice (or cold stream water): apply 15–20 minutes, 3–4× per day',
          detail: 'Wrap ice in cloth to prevent frostbite. Cold stream immersion is highly effective in the field.'),
      FieldStep(text: 'Compression: apply elastic bandage figure-eight around ankle',
          detail: 'Start at ball of foot, wrap figure-eight around ankle and lower leg. Firm but not circulation-restricting. Check toes for color/feeling.'),
      FieldStep(text: 'Elevation: keep ankle above heart level when resting'),
      FieldStep(text: 'Assess Ottawa Rules — palpate base of 5th metatarsal and medial/lateral malleolus',
          detail: 'X-ray needed if: bony tenderness at posterior tip of malleolus OR base of 5th metatarsal, OR inability to bear weight 4 steps.'),
      FieldStep(text: 'If must continue walking: tape or brace ankle for stability',
          detail: 'Closed basket-weave taping or an ankle brace provides significant support. Use trekking poles to off-load.'),
      FieldStep(text: 'Ibuprofen or naproxen for pain and swelling if not contraindicated'),
    ],
    prevention: [
      'Wear supportive, well-fitted boots with ankle height',
      'Use trekking poles on uneven terrain',
      'Strengthen ankles with balance and proprioception exercises before trip',
      'Move slowly and deliberately on loose or rocky ground',
    ],
    evacuate: 'Evacuate if: unable to bear any weight, suspected fracture (severe bony tenderness, significant deformity, Ottawa criteria positive), neurovascular compromise (numbness, pallor, absent pulse).',
  ),

  BackcountryCondition(
    id: 'muscle_cramp',
    title: 'Muscle Cramps',
    category: 'Musculoskeletal',
    description: 'Sudden involuntary muscle contraction, often from exertion or dehydration.',
    icon: Icons.airline_seat_legroom_reduced,
    color: Color(0xFF6A1B9A),
    symptoms: [
      'Sudden, intense muscle pain',
      'Visible or palpable muscle knot/hardening',
      'Temporary inability to use affected muscle',
      'Usually self-resolving within minutes',
    ],
    steps: [
      FieldStep(text: 'Stop activity — rest the affected muscle', isCritical: true),
      FieldStep(text: 'Stretch the cramping muscle gently and hold',
          detail: 'Calf cramp: straighten knee and flex foot toward shin. Hamstring: straighten leg. Quad: bend knee toward buttocks.'),
      FieldStep(text: 'Massage the muscle belly firmly after initial stretch'),
      FieldStep(text: 'Hydrate with water and electrolyte solution (sports drink, electrolyte tablets)',
          detail: 'Cramps during exertion are commonly driven by sodium and fluid loss, not just dehydration.'),
      FieldStep(text: 'Apply heat (warm compress or sun-warmed water bottle) after cramping stops'),
      FieldStep(text: 'Resume activity gradually once resolved'),
    ],
    prevention: [
      'Maintain hydration — drink before thirst develops',
      'Include electrolytes (salt, potassium) during prolonged exertion',
      'Condition muscles before demanding trips',
      'Warm up and stretch before sustained activity',
    ],
    evacuate: 'Evacuate if cramps are severe, widespread, or accompanied by confusion, nausea, and high body temperature — could indicate heat illness.',
  ),

  BackcountryCondition(
    id: 'suspected_fracture',
    title: 'Suspected Fracture',
    category: 'Musculoskeletal',
    description: 'Broken bone — field management focuses on splinting and evacuation.',
    icon: Icons.hardware,
    color: Color(0xFFD32F2F),
    symptoms: [
      'Mechanism of injury (fall, impact)',
      'Severe pain at injury site',
      'Point tenderness over bone',
      'Swelling and bruising',
      'Deformity or abnormal angulation',
      'Inability to use extremity normally',
      'Crepitus (grinding sensation)',
    ],
    steps: [
      FieldStep(text: 'Check and document circulation, sensation, and movement (CSM) distal to injury', isCritical: true,
          detail: 'Pulse, capillary refill, skin temperature, ability to wiggle fingers/toes, sensation to light touch. Check before and after splinting.'),
      FieldStep(text: 'Do NOT attempt to realign fracture UNLESS neurovascular compromise is present',
          detail: 'If no pulse distal: one attempt at gentle traction in-line with the limb to restore circulation is appropriate.'),
      FieldStep(text: 'Splint the extremity in the position of comfort — immobilize joint above AND below fracture', isCritical: true,
          detail: 'Use SAM splints, trekking poles, sticks, or sleeping pad as rigid elements. Pad bony prominences. Splint snugly, not tight.'),
      FieldStep(text: 'Reassess CSM immediately after splinting and every 30 minutes',
          detail: 'If circulation worsens: loosen splint. Never leave a splint in place for hours without reassessment.'),
      FieldStep(text: 'Elevate injured limb if possible'),
      FieldStep(text: 'Administer pain medication if available: ibuprofen, acetaminophen, or stronger if carried'),
      FieldStep(text: 'Keep patient warm — fractures trigger systemic stress response; protect from hypothermia'),
      FieldStep(text: 'Arrange evacuation — fractures require imaging and definitive care', isCritical: true),
    ],
    prevention: [
      'Move carefully in technical terrain',
      'Use trekking poles for support and balance',
      'Maintain physical conditioning before demanding trips',
      'Avoid hiking in poor visibility or at night when terrain judgment is impaired',
    ],
    evacuate: 'ALL suspected fractures require evacuation. Priority evacuation for: femur fractures (blood loss risk), open fractures, spinal injury, neurovascular compromise.',
  ),


  // ── Environmental ──────────────────────────────────────────────────────────

  BackcountryCondition(
    id: 'heat_exhaustion',
    title: 'Heat Exhaustion',
    category: 'Environmental',
    description: 'Body overheating — serious but manageable in the field.',
    icon: Icons.wb_sunny,
    color: Color(0xFFE65100),
    symptoms: [
      'Heavy sweating',
      'Cool, pale, clammy skin',
      'Weakness, dizziness, nausea',
      'Headache',
      'Rapid, weak pulse',
      'Muscle cramps',
      'Normal or mildly elevated mental status',
    ],
    steps: [
      FieldStep(text: 'Move patient to shade or cool environment immediately', isCritical: true),
      FieldStep(text: 'Remove excess clothing and equipment'),
      FieldStep(text: 'Begin active cooling — wet skin and fan vigorously',
          detail: 'Apply cool water to skin (especially neck, armpits, groin). Fanning accelerates evaporative cooling.'),
      FieldStep(text: 'If alert and able to swallow: oral rehydration with water + electrolytes',
          detail: 'Sports drink, oral rehydration salts, or water with a pinch of salt and sugar. Small sips every few minutes.'),
      FieldStep(text: 'Have patient lie down with legs elevated (if no spinal concern)',
          detail: 'Improves cerebral perfusion if dizzy or faint.'),
      FieldStep(text: 'Monitor mental status closely — deterioration indicates progression to heatstroke', isCritical: true),
      FieldStep(text: 'Rest until fully recovered — typically 30–60 minutes before considering light activity'),
    ],
    prevention: [
      'Hydrate proactively — drink before feeling thirsty',
      'Schedule strenuous activity for cooler parts of day (early morning)',
      'Wear light-colored, breathable, loose clothing',
      'Acclimatize gradually to hot environments over 7–14 days',
      'Eat salty snacks to maintain electrolyte balance',
    ],
    evacuate: 'Evacuate if condition does not improve within 30 minutes, mental status changes, or patient cannot tolerate oral fluids.',
  ),

  BackcountryCondition(
    id: 'heatstroke',
    title: 'Heatstroke',
    category: 'Environmental',
    description: 'Life-threatening — core temperature > 40°C (104°F) with CNS dysfunction.',
    icon: Icons.local_fire_department,
    color: Color(0xFFD32F2F),
    symptoms: [
      'High body temperature (feels very hot to touch)',
      'Altered mental status: confusion, agitation, slurred speech, seizure, unconsciousness',
      'Skin may be hot and DRY (classic) or wet (exertional)',
      'Rapid, strong pulse progressing to weak',
      'Nausea, vomiting',
    ],
    steps: [
      FieldStep(text: 'COOL THE PATIENT IMMEDIATELY — this is the treatment', isCritical: true,
          detail: 'Every minute of elevated core temperature causes organ damage. Cooling is the priority over everything except airway.'),
      FieldStep(text: 'Move to shade; remove ALL clothing', isCritical: true),
      FieldStep(text: 'Immerse in cold water if available (stream, lake) — most effective method', isCritical: true,
          detail: 'If immersion not possible: pour cold water continuously over entire body and fan aggressively.'),
      FieldStep(text: 'Apply ice or cold packs to neck, armpits, and groin — high blood flow areas'),
      FieldStep(text: 'Maintain airway — recovery position if unconscious but breathing'),
      FieldStep(text: 'Do NOT give oral fluids to altered patient — aspiration risk', isCritical: true),
      FieldStep(text: 'Cool until patient is alert and oriented OR until evacuation transport arrives'),
      FieldStep(text: 'Activate emergency evacuation immediately — this is a life threat', isCritical: true),
    ],
    prevention: [
      'Monitor teammates for early heat illness signs',
      'Never push through significant heat exhaustion symptoms',
      'Avoid exertion in extreme heat without acclimatization',
    ],
    evacuate: 'IMMEDIATE evacuation. Heatstroke is fatal without definitive cooling and IV fluids. Do not wait.',
  ),

  BackcountryCondition(
    id: 'hypothermia',
    title: 'Hypothermia',
    category: 'Environmental',
    description: 'Dangerous drop in core body temperature below 35°C (95°F).',
    icon: Icons.ac_unit,
    color: Color(0xFF1565C0),
    symptoms: [
      'Shivering (may be absent in severe cases)',
      'Slurred speech, confusion, poor coordination',
      'Cold, pale, or cyanotic skin',
      'Slow, shallow breathing',
      'Weak or irregular pulse',
      'Severe: unconscious, rigid muscles, minimal pulse',
    ],
    steps: [
      FieldStep(text: 'Move patient out of wind, rain, and cold environment', isCritical: true),
      FieldStep(text: 'Remove wet clothing — cut if necessary; handle patient GENTLY',
          detail: 'Rough handling of a severely hypothermic patient can trigger ventricular fibrillation.'),
      FieldStep(text: 'Insulate from ground — place on sleeping pad or pack',
          detail: 'Conductive heat loss to cold ground is massive. Insulation from below is critical.'),
      FieldStep(text: 'Apply heat to trunk — NOT extremities',
          detail: 'Heat packs or warm water bottles to armpits, groin, and chest. Heating extremities first causes cold blood to rush to core (afterdrop).'),
      FieldStep(text: 'Wrap patient in sleeping bag or emergency blanket — vapor barrier helps'),
      FieldStep(text: 'If alert and able to swallow: warm sweet fluids (no alcohol)', isCritical: true),
      FieldStep(text: 'For severe hypothermia: handle as if cardiac patient — avoid CPR unless no signs of life for > 30 seconds',
          detail: 'Cold heart is prone to VF. The field rule: "Not dead until warm and dead." Continue rewarming.'),
      FieldStep(text: 'Arrange evacuation for anything beyond mild hypothermia (shivering, intact mentation)', isCritical: true),
    ],
    prevention: [
      'Dress in moisture-wicking base layer, insulating mid-layer, windproof/waterproof shell',
      'Stay dry — carry rain gear always',
      'Eat and drink regularly — maintain caloric intake in cold',
      'Know the signs and act before mild becomes moderate',
    ],
    evacuate: 'Evacuate for: moderate or severe hypothermia, no shivering (paradoxically worse), altered mental status, or any cardiac irregularity.',
  ),

  BackcountryCondition(
    id: 'frostbite',
    title: 'Frostbite & Frostnip',
    category: 'Environmental',
    description: 'Freezing injury to skin and underlying tissues.',
    icon: Icons.ac_unit,
    color: Color(0xFF1565C0),
    symptoms: [
      'Frostnip: red, cold, numb skin — still pliable',
      'Superficial frostbite: white or grayish skin, hard surface but soft underneath',
      'Deep frostbite: white/mottled, completely hard, no sensation',
      'Pain and burning on rewarming',
      'Blisters (clear = superficial; bloody = deep)',
    ],
    steps: [
      FieldStep(text: 'Frostnip: rewarm with skin-to-skin contact immediately', isCritical: true,
          detail: 'Hold frostnipped fingers in armpits, toes against partner\'s warm abdomen. Full recovery expected.'),
      FieldStep(text: 'Protect frozen tissue from further trauma — do NOT rub or massage', isCritical: true),
      FieldStep(text: 'Do NOT rewarm if refreezing is possible — walking on frozen feet is less damaging than freeze-thaw-freeze', isCritical: true),
      FieldStep(text: 'If evacuation not imminent and no risk of refreezing: rapid rewarming in 37–40°C (99–104°F) water',
          detail: 'Water thermometer recommended — too hot causes burns. Maintain water temperature. Expect severe pain on rewarming.'),
      FieldStep(text: 'After rewarming: wrap loosely in dry bandages; place gauze between toes/fingers'),
      FieldStep(text: 'Ibuprofen 400 mg q12h if available — reduces inflammatory injury'),
      FieldStep(text: 'Do NOT allow refreezing after rewarming — this causes severe tissue loss', isCritical: true),
      FieldStep(text: 'Arrange evacuation for all frostbite beyond frostnip'),
    ],
    prevention: [
      'Wear appropriate layered gloves and insulated footwear',
      'Check extremities regularly in cold conditions',
      'Keep moving to maintain circulation',
      'Avoid tight-fitting boots that restrict circulation',
      'Stay well hydrated and nourished — vasoconstriction worsens with dehydration',
    ],
    evacuate: 'Evacuate all frostbite beyond frostnip. Deep frostbite is a surgical emergency — tissue demarcation and debridement requires definitive care.',
  ),

  BackcountryCondition(
    id: 'sunburn',
    title: 'Sunburn',
    category: 'Environmental',
    description: 'UV radiation damage to skin.',
    icon: Icons.wb_sunny_outlined,
    color: Color(0xFFE65100),
    symptoms: [
      'Red, hot, painful skin (1st degree)',
      'Swelling and blistering (2nd degree)',
      'Peeling in 3–5 days',
      'Systemic: fever, chills, nausea (sun poisoning)',
    ],
    steps: [
      FieldStep(text: 'Move out of direct sun; cover exposed skin'),
      FieldStep(text: 'Cool burned skin with cool (not ice-cold) water or wet cloth', isCritical: true,
          detail: 'Do not use ice — can worsen tissue damage. Apply cool compresses for 15–20 min.'),
      FieldStep(text: 'Hydrate aggressively — sunburn draws fluid to the skin surface'),
      FieldStep(text: 'Apply aloe vera gel or fragrance-free moisturizer to intact (unbroken) skin'),
      FieldStep(text: 'Do NOT break blisters — roof protects against infection'),
      FieldStep(text: 'Ibuprofen or acetaminophen for pain and inflammation'),
      FieldStep(text: 'Keep burned skin out of sun until healed'),
    ],
    prevention: [
      'Apply SPF 30+ sunscreen 30 minutes before sun exposure; reapply every 2 hours and after sweating',
      'Wear UV-protective clothing, wide-brim hat, and sunglasses',
      'Seek shade during peak UV hours (10am–4pm)',
      'Snow, water, and altitude dramatically increase UV exposure',
    ],
    evacuate: 'Evacuate if: extensive blistering, face/eyes involved, high fever, severe dehydration, or altered mental status (sun poisoning).',
  ),

  BackcountryCondition(
    id: 'altitude_sickness',
    title: 'Altitude Sickness (AMS)',
    category: 'Environmental',
    description: 'Acute Mountain Sickness from too-rapid ascent above 2,500 m (8,200 ft).',
    icon: Icons.landscape,
    color: Color(0xFF1565C0),
    symptoms: [
      'Headache (primary symptom)',
      'Fatigue and weakness',
      'Nausea or vomiting',
      'Dizziness or lightheadedness',
      'Difficulty sleeping',
      'SEVERE: confusion, ataxia, shortness of breath at rest — indicates HACE/HAPE',
    ],
    steps: [
      FieldStep(text: 'Stop ascent — do not go higher with AMS symptoms', isCritical: true),
      FieldStep(text: 'Rest at current altitude — mild AMS often resolves in 12–24 hours'),
      FieldStep(text: 'Hydrate well; eat light carbohydrate meals'),
      FieldStep(text: 'Ibuprofen 600 mg or acetaminophen for headache',
          detail: 'Ibuprofen has been shown in studies to reduce AMS severity.'),
      FieldStep(text: 'Acetazolamide (Diamox) 250 mg twice daily if available — accelerates acclimatization',
          detail: 'Contraindicated in sulfa allergy. Causes increased urination — maintain hydration.'),
      FieldStep(text: 'Descend 300–500 m (1,000–1,500 ft) if symptoms do not improve or worsen', isCritical: true,
          detail: 'Descent is the definitive treatment. Even a small descent dramatically improves AMS.'),
      FieldStep(text: 'HACE/HAPE: IMMEDIATE descent + supplemental oxygen + evacuation', isCritical: true,
          detail: 'HACE: confusion, ataxia. HAPE: breathlessness at rest, pink frothy sputum. Both are immediately life-threatening.'),
    ],
    prevention: [
      'Ascend gradually — no more than 300–500 m gain in sleeping altitude per day above 3,000 m',
      '"Climb high, sleep low" — day hikes above sleeping altitude are safe',
      'Allow acclimatization days every 3 days of ascent',
      'Consider prophylactic acetazolamide for rapid ascents',
      'Avoid alcohol and sedatives at altitude',
    ],
    evacuate: 'Descend immediately for: HACE (confusion, ataxia), HAPE (breathlessness at rest), or AMS not improving with 24 hours of rest.',
  ),


  // ── Bites & Stings ────────────────────────────────────────────────────────

  BackcountryCondition(
    id: 'bee_sting',
    title: 'Bee & Wasp Stings',
    category: 'Bites & Stings',
    description: 'Venom injection from hymenoptera — watch for anaphylaxis.',
    icon: Icons.bug_report,
    color: Color(0xFFE65100),
    symptoms: [
      'Immediate sharp pain at sting site',
      'Local redness, swelling, itching',
      'Visible stinger (bees only)',
      'ANAPHYLAXIS: hives, throat tightening, difficulty breathing, hypotension — life threatening',
    ],
    steps: [
      FieldStep(text: 'Immediately assess for anaphylaxis — throat tightness, difficulty breathing, widespread hives', isCritical: true,
          detail: 'If anaphylaxis: administer epinephrine (EpiPen) FIRST, then manage airway and evacuate immediately.'),
      FieldStep(text: 'Remove bee stinger by scraping with a card or fingernail — do NOT squeeze',
          detail: 'Squeezing the venom sac injects more venom. Scrape or flick out.'),
      FieldStep(text: 'Wash sting site with soap and water'),
      FieldStep(text: 'Apply cold pack or cool compress to reduce swelling and pain'),
      FieldStep(text: 'Oral antihistamine (diphenhydramine/Benadryl 25–50 mg) for itching and mild local reaction'),
      FieldStep(text: 'Ibuprofen or acetaminophen for pain'),
      FieldStep(text: 'Monitor for 30–60 minutes for delayed allergic reaction'),
    ],
    prevention: [
      'Avoid wearing bright colors or floral patterns in areas with bee activity',
      'Keep food and sweet drinks covered',
      'Move calmly away from nests — do not swat',
      'Carry epinephrine autoinjector if known allergic',
    ],
    evacuate: 'Evacuate immediately for any signs of anaphylaxis. Evacuate for multiple stings (>10 in adult, >5 in child) — systemic toxicity risk.',
  ),

  BackcountryCondition(
    id: 'tick_bite',
    title: 'Tick Bite',
    category: 'Bites & Stings',
    description: 'Tick removal and monitoring for tick-borne illness.',
    icon: Icons.bug_report,
    color: Color(0xFF6A1B9A),
    symptoms: [
      'Visible tick embedded in skin',
      'Local redness around bite',
      'Possible itching or burning',
      'Bull\'s-eye rash (erythema migrans) — indicates Lyme disease',
      'Delayed: fever, headache, muscle aches (3–30 days)',
    ],
    steps: [
      FieldStep(text: 'Remove tick promptly — disease transmission risk increases with attachment time', isCritical: true),
      FieldStep(text: 'Use fine-tipped tweezers — grasp tick as close to skin surface as possible',
          detail: 'Do NOT use petroleum jelly, nail polish, heat, or twisting. These can cause tick to release infected fluids.'),
      FieldStep(text: 'Pull upward with steady, even pressure — do not twist or jerk',
          detail: 'Goal: remove tick mouthparts cleanly. If mouthparts remain, remove with clean tweezers or leave and let skin heal.'),
      FieldStep(text: 'Clean bite site with rubbing alcohol or soap and water'),
      FieldStep(text: 'Preserve tick in sealed bag or jar with date noted',
          detail: 'Tick identification can guide treatment decisions at the hospital.'),
      FieldStep(text: 'Monitor bite site and patient for 30 days for rash, fever, joint pain',
          detail: 'Bull\'s eye rash (expanding ring) appearing 3–14 days is diagnostic of Lyme. Photograph and seek medical care.'),
    ],
    prevention: [
      'Use DEET or permethrin repellent on skin and clothing',
      'Wear long pants tucked into socks; light-colored clothing to see ticks',
      'Conduct thorough body checks after being in tick habitat (tall grass, brush, wooded areas)',
      'Shower within 2 hours of coming indoors',
    ],
    evacuate: 'Evacuate if bull\'s-eye rash develops, or systemic symptoms (fever, severe headache, paralysis) appear after tick bite.',
  ),

  BackcountryCondition(
    id: 'snake_bite',
    title: 'Snake Bite',
    category: 'Bites & Stings',
    description: 'Venomous snake envenomation — evacuation is the treatment.',
    icon: Icons.warning_amber,
    color: Color(0xFFD32F2F),
    symptoms: [
      'Fang marks at bite site (one or two punctures)',
      'Immediate burning pain and swelling',
      'Discoloration and bruising',
      'Nausea, dizziness, sweating',
      'Neurotoxic: numbness, tingling, weakness (coral snakes, some rattlesnakes)',
      'Pit viper: rapid local swelling, tissue necrosis',
    ],
    steps: [
      FieldStep(text: 'Stay calm — panic increases venom spread via elevated heart rate', isCritical: true),
      FieldStep(text: 'Move patient away from snake immediately — do NOT attempt to capture or kill it'),
      FieldStep(text: 'Remove rings, watches, and tight clothing from affected limb — swelling can be severe', isCritical: true),
      FieldStep(text: 'Immobilize the bitten extremity at or below heart level',
          detail: 'Minimize muscle movement to slow venom distribution. Improvise a splint.'),
      FieldStep(text: 'Mark the leading edge of swelling with pen and time every 15 minutes — tracks progression'),
      FieldStep(text: 'Do NOT: cut and suck, apply tourniquet, apply ice, use electric shock',
          detail: 'These "treatments" cause additional harm and delay definitive care. The only treatment is antivenom.'),
      FieldStep(text: 'Initiate evacuation immediately — antivenom is the treatment', isCritical: true),
      FieldStep(text: 'Note snake appearance if seen safely — color, pattern, head shape helps ID'),
    ],
    prevention: [
      'Watch where you step and place your hands',
      'Wear gaiters or tall boots in snake country',
      'Use a light at night when walking in warm climates',
      'Do not reach under rocks or logs',
    ],
    evacuate: 'IMMEDIATE evacuation for all suspected venomous bites. Antivenom must be administered in a hospital setting.',
  ),

  BackcountryCondition(
    id: 'scorpion_sting',
    title: 'Scorpion Sting',
    category: 'Bites & Stings',
    description: 'Most stings are painful but not life-threatening (except bark scorpion).',
    icon: Icons.bug_report,
    color: Color(0xFFE65100),
    symptoms: [
      'Immediate intense pain at sting site',
      'Local burning, numbness, tingling',
      'Minimal local swelling (unlike other envenomations)',
      'Severe (Centruroides/bark scorpion): muscle twitching, drooling, rapid eye movements, difficulty swallowing',
    ],
    steps: [
      FieldStep(text: 'Assess severity — local reaction only vs. systemic symptoms', isCritical: true),
      FieldStep(text: 'Clean sting site with soap and water'),
      FieldStep(text: 'Apply cold compress to reduce pain'),
      FieldStep(text: 'Oral analgesics: ibuprofen or acetaminophen for local pain'),
      FieldStep(text: 'For severe/systemic symptoms: keep patient calm, monitor airway, prepare for evacuation', isCritical: true),
      FieldStep(text: 'Do NOT apply tourniquet or cut/suck the site'),
    ],
    prevention: [
      'Shake out boots, clothing, and sleeping bags before use in desert environments',
      'Avoid reaching into crevices or under rocks',
      'Use a sleeping cot in scorpion habitat',
      'Inspect campsite area before setting up sleeping area',
    ],
    evacuate: 'Evacuate for: children stung by any scorpion, adults with systemic symptoms, known bark scorpion sting (Southwest US/Mexico).',
  ),


  // ── Plants ────────────────────────────────────────────────────────────────

  BackcountryCondition(
    id: 'poison_ivy',
    title: 'Poison Ivy / Oak / Sumac',
    category: 'Plants',
    description: 'Allergic contact dermatitis from urushiol oil.',
    icon: Icons.eco,
    color: Color(0xFF2E7D32),
    symptoms: [
      'Intense itching (develops 12–72 hours after exposure)',
      'Red, streaky rash following contact pattern',
      'Fluid-filled blisters',
      'Swelling (especially on face)',
      'Blisters do NOT spread rash — urushiol spread during contact does',
    ],
    steps: [
      FieldStep(text: 'Wash all exposed skin with soap and cold water AS SOON AS POSSIBLE', isCritical: true,
          detail: 'Cold water keeps pores closed. Wash all contact areas thoroughly including under fingernails. Urushiol binds within 10–30 minutes.'),
      FieldStep(text: 'Remove and bag all clothing worn during exposure — wash before reuse'),
      FieldStep(text: 'Do not touch face or eyes after potential exposure — urushiol spreads until washed off'),
      FieldStep(text: 'Calamine lotion or hydrocortisone cream for mild itching'),
      FieldStep(text: 'Oral antihistamine (diphenhydramine) for itching, especially at night'),
      FieldStep(text: 'Cool compresses for soothing — oatmeal baths help widespread rash'),
      FieldStep(text: 'Do NOT scratch — increases infection risk; does not spread rash'),
      FieldStep(text: 'Rash typically peaks at 3–5 days and resolves in 1–3 weeks'),
    ],
    prevention: [
      '"Leaves of three, let it be" — also "Leaflets three, let it be"',
      'Wear long pants, long sleeves, and gloves in known habitat',
      'Apply Tecnu or Ivy Block before exposure in high-risk areas',
      'Wash skin and gear within 30 minutes of possible exposure',
    ],
    evacuate: 'Evacuate for: rash on face/eyelids causing significant swelling, rash near mouth or genitals, widespread rash, difficulty breathing (inhaled smoke from burning plant), or signs of secondary infection.',
  ),

  BackcountryCondition(
    id: 'stinging_nettle',
    title: 'Stinging Nettle',
    category: 'Plants',
    description: 'Contact with nettle causes immediate burning rash from formic acid.',
    icon: Icons.eco,
    color: Color(0xFF2E7D32),
    symptoms: [
      'Immediate burning and stinging on contact',
      'Raised white welts (urticaria) surrounded by redness',
      'Itching lasting 30 minutes to several hours',
      'Tingling or numbness in affected area',
    ],
    steps: [
      FieldStep(text: 'Do NOT rub the affected area — this drives stinging hairs deeper'),
      FieldStep(text: 'Remove visible stinging hairs with tape or by scraping with a credit card'),
      FieldStep(text: 'Wash area gently with soap and water'),
      FieldStep(text: 'Apply dock leaf juice if available — traditional remedy with some evidence',
          detail: 'Dock leaves (Rumex species) often grow near nettles. Crush leaf and apply juice to affected area.'),
      FieldStep(text: 'Cool compress to reduce burning and itching'),
      FieldStep(text: 'Oral antihistamine if available for persistent itching'),
      FieldStep(text: 'Symptoms typically resolve within 1–6 hours'),
    ],
    prevention: [
      'Learn to identify stinging nettle — serrated heart-shaped leaves with fine hairs',
      'Wear gloves and long sleeves when moving through dense vegetation',
    ],
    evacuate: 'Evacuation rarely needed. Evacuate for: allergic reaction (hives beyond contact site, throat tightening, difficulty breathing).',
  ),


  // ── GI & Illness ──────────────────────────────────────────────────────────

  BackcountryCondition(
    id: 'dehydration',
    title: 'Dehydration',
    category: 'GI & Illness',
    description: 'Insufficient fluid intake — common and preventable.',
    icon: Icons.water_drop,
    color: Color(0xFF1565C0),
    symptoms: [
      'Thirst (late sign — already 1–2% dehydrated)',
      'Dark yellow or amber urine (normal = pale yellow)',
      'Decreased urination frequency',
      'Headache, fatigue, decreased performance',
      'Dizziness on standing (orthostatic hypotension)',
      'Severe: confusion, rapid weak pulse, dry mouth, sunken eyes',
    ],
    steps: [
      FieldStep(text: 'Begin oral rehydration immediately if alert and able to swallow', isCritical: true),
      FieldStep(text: 'Water alone is adequate for mild dehydration',
          detail: 'For moderate dehydration or after significant sweat loss, add electrolytes: oral rehydration salts, sports drink, or water with a pinch of salt and a teaspoon of sugar.'),
      FieldStep(text: 'Mild-moderate: drink 500–1000 mL over 1–2 hours at a comfortable pace',
          detail: 'Do not force large volumes rapidly — can cause vomiting. Small, frequent sips if nauseated.'),
      FieldStep(text: 'Rest in shade and reduce activity during rehydration'),
      FieldStep(text: 'Monitor urine output and color — aim for pale yellow'),
      FieldStep(text: 'Treat underlying cause: heat exposure, diarrhea, excessive sweating'),
    ],
    prevention: [
      'Drink 0.5 L (16 oz) per hour during moderate activity; more in heat',
      'Do not rely on thirst — drink on a schedule',
      'Eat regular meals — food contains significant water',
      'Drink extra before, during, and after exercise',
      'Avoid alcohol and caffeine in high-heat or high-exertion environments',
    ],
    evacuate: 'Evacuate for: severe dehydration with altered mental status or inability to keep fluids down, signs of shock (rapid weak pulse, pale skin, confusion).',
  ),

  BackcountryCondition(
    id: 'gi_illness',
    title: 'GI Illness / Diarrhea',
    category: 'GI & Illness',
    description: 'Traveler\'s diarrhea or foodborne illness from contaminated water or food.',
    icon: Icons.sick,
    color: Color(0xFF6A1B9A),
    symptoms: [
      'Loose, watery, or frequent stools',
      'Abdominal cramping and bloating',
      'Nausea, vomiting',
      'Low-grade fever',
      'Weakness and fatigue',
    ],
    steps: [
      FieldStep(text: 'Prioritize hydration — replace fluid and electrolytes lost with diarrhea', isCritical: true,
          detail: 'Oral rehydration salts (ORS) are ideal. Mix: 1L water + 6 tsp sugar + ½ tsp salt. Drink 200–400 mL after each loose stool.'),
      FieldStep(text: 'BRAT diet: bananas, rice, applesauce, toast — easy to digest and bulking'),
      FieldStep(text: 'Avoid dairy, fatty, spicy foods until recovered'),
      FieldStep(text: 'Loperamide (Imodium) 2 mg for cramping or to allow activity',
          detail: 'Loperamide slows gut motility. Do NOT use if blood in stool or high fever — may worsen bacterial infections.'),
      FieldStep(text: 'Antibiotics (if carried): azithromycin or ciprofloxacin for moderate-severe traveler\'s diarrhea',
          detail: 'Single dose azithromycin 1g is highly effective. Use if diarrhea is disabling, frequent, or associated with fever.'),
      FieldStep(text: 'Maintain strict hand hygiene to prevent spread to group members', isCritical: true),
      FieldStep(text: 'Purify all water — do not assume current source is safe'),
    ],
    prevention: [
      'Treat all water: boil, filter, or chemically treat',
      'Wash hands thoroughly before eating and after toilet',
      'Store food at appropriate temperatures; discard questionable food',
      'Cook meat thoroughly',
    ],
    evacuate: 'Evacuate for: blood in stool, high fever (>39°C/102°F), signs of dehydration that cannot be corrected orally, symptoms persisting > 72 hours despite treatment.',
  ),
];


// ── List screen ───────────────────────────────────────────────────────────────

class BackcountryGuideScreen extends StatefulWidget {
  const BackcountryGuideScreen({super.key});
  @override
  State<BackcountryGuideScreen> createState() => _BackcountryGuideScreenState();
}

class _BackcountryGuideScreenState extends State<BackcountryGuideScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final filtered = kBackcountryConditions.where((c) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.title.toLowerCase().contains(q) ||
          c.category.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          c.symptoms.any((s) => s.toLowerCase().contains(q));
    }).toList();

    final Map<String, List<BackcountryCondition>> grouped = {};
    for (final c in filtered) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }
    final categories = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backcountry Field Guide'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search conditions…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () { _search.clear(); setState(() => _query = ''); })
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('No conditions match your search.', style: TextStyle(color: Colors.grey)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: categories.map((cat) {
                final items = grouped[cat]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                      child: Row(children: [
                        Container(
                          width: 4, height: 18,
                          decoration: BoxDecoration(
                              color: items.first.color,
                              borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 8),
                        Text(cat,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ]),
                    ),
                    ...items.map((c) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: c.color.withValues(alpha: 0.15),
                          child: Icon(c.icon, color: c.color, size: 20),
                        ),
                        title: Text(c.title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.description,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) =>
                                BackcountryConditionScreen(condition: c))),
                      ),
                    )),
                  ],
                );
              }).toList(),
            ),
    );
  }
}


// ── Detail screen ─────────────────────────────────────────────────────────────

class BackcountryConditionScreen extends StatefulWidget {
  final BackcountryCondition condition;
  const BackcountryConditionScreen({super.key, required this.condition});
  @override
  State<BackcountryConditionScreen> createState() =>
      _BackcountryConditionScreenState();
}

class _BackcountryConditionScreenState
    extends State<BackcountryConditionScreen> {
  late List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = List.filled(widget.condition.steps.length, false);
  }

  int get _completed => _checked.where((c) => c).length;
  bool get _allDone => _completed == widget.condition.steps.length;

  void _reset() =>
      setState(() => _checked = List.filled(widget.condition.steps.length, false));

  @override
  Widget build(BuildContext context) {
    final c = widget.condition;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(c.title),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset steps',
              onPressed: _reset),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [

          // Header banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.color.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              CircleAvatar(
                  radius: 22,
                  backgroundColor: c.color.withValues(alpha: 0.20),
                  child: Icon(c.icon, color: c.color, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(c.category,
                    style: TextStyle(fontSize: 11, color: c.color,
                        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(c.description,
                    style: const TextStyle(fontSize: 13)),
              ])),
            ]),
          ),

          const SizedBox(height: 16),

          // Symptoms
          _SectionHeader(label: 'Signs & Symptoms', color: c.color),
          const SizedBox(height: 8),
          ...c.symptoms.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.circle, size: 7, color: c.color),
              const SizedBox(width: 10),
              Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
            ]),
          )),

          const SizedBox(height: 16),

          // Treatment steps
          _SectionHeader(label: 'Treatment Steps', color: c.color),
          const SizedBox(height: 4),
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(
                value: c.steps.isEmpty ? 0 : _completed / c.steps.length,
                backgroundColor: Colors.grey[300],
                color: _allDone ? Colors.green : c.color,
              ),
              const SizedBox(height: 4),
              Text('$_completed / ${c.steps.length} steps complete',
                  style: TextStyle(
                      fontSize: 11,
                      color: _allDone ? Colors.green : cs.onSurfaceVariant)),
            ]),
          ),
          ...List.generate(c.steps.length, (i) {
            final step = c.steps[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: _checked[i]
                  ? Colors.green.withValues(alpha: 0.08)
                  : step.isCritical
                      ? c.color.withValues(alpha: 0.06)
                      : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _checked[i] = !_checked[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(
                      _checked[i]
                          ? Icons.check_circle
                          : step.isCritical
                              ? Icons.warning_rounded
                              : Icons.radio_button_unchecked,
                      color: _checked[i]
                          ? Colors.green
                          : step.isCritical
                              ? c.color
                              : Colors.grey,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${i + 1}. ${step.text}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: step.isCritical ? FontWeight.w600 : FontWeight.normal,
                                decoration: _checked[i]
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: _checked[i]
                                    ? Colors.grey
                                    : null)),
                        if (step.detail != null) ...[
                          const SizedBox(height: 4),
                          Text(step.detail!,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          }),

          const SizedBox(height: 16),

          // Prevention
          _SectionHeader(label: 'Prevention', color: c.color),
          const SizedBox(height: 8),
          ...c.prevention.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.shield_outlined, size: 16, color: Colors.green),
              const SizedBox(width: 10),
              Expanded(child: Text(p, style: const TextStyle(fontSize: 13))),
            ]),
          )),

          const SizedBox(height: 16),

          // Evacuation criteria
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.local_hospital, color: Colors.red, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Evacuation Criteria',
                    style: TextStyle(fontWeight: FontWeight.bold,
                        color: Colors.red, fontSize: 13)),
                const SizedBox(height: 4),
                Text(c.evacuate, style: const TextStyle(fontSize: 12.5)),
              ])),
            ]),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionHeader({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 3, height: 16,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    ]);
  }
}
