// One-time migration: uploads the ~65 medical protocol PDFs that used to be
// hardcoded/bundled from assets/protocols/ (main.dart's old _initRootProtocols)
// into Supabase as admin-controlled 'medical' category protocols, broadcast
// to everyone (matching today's "ships to every install" behavior). Run once
// via `dart run scripts/migrate_root_protocols.dart` from the project root,
// then delete these specific files from assets/protocols/ (leave the
// procedure/medication PDFs referenced by staticCategories/medicationData in
// main.dart in place -- those are unrelated and stay bundled).
//
// Not shipped with the app; safe to delete after a successful run.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

const _supabaseUrl = 'https://vlgiclyuxaleyusalexo.supabase.co';
const _supabaseAnonKey = 'sb_publishable_U6M_YMbubI1Y8qD4a3SKCA_Oeo6L75B';

const _rootProtocolFiles = [
  'Bites.pdf', 'Hazmat.pdf', 'Stings.pdf', 'Stroke.pdf', 'Seizure.pdf', 'Drowning.pdf',
  'Crush Injury.pdf', 'Hypertension.pdf', 'Dead on Scene.pdf', 'EXPANDED SCOPE.pdf',
  'Cyanide Poisoning.pdf', 'Hydrocarbon Fumes.pdf', 'Activated Charcoal.pdf',
  'Behavior Emergency.pdf', 'Adult Resuscitation.pdf', 'Trauma - Antibiotics.pdf',
  'Trauma - Head Injury.pdf', 'Trauma - Neck Trauma.pdf', 'Altered Mental Status.pdf',
  'Trauma - Sexual Assault.pdf', 'Trauma Arrest Guideline.pdf', 'Trauma - Burns - General.pdf',
  'Headache - Expanded Scope.pdf', 'Spinal Motion Restriction.pdf', 'Epistaxis - Expanded Scope.pdf',
  'Toxic Ingestion - Overdose.pdf', 'Chest Pain - Expanded Scope.pdf', 'Firefighter Rehab Guidelines.pdf',
  'GI Bleeding - Expanded Scope.pdf', 'Special Consideration - Rabies.pdf', 'Trauma - Eye Injury - Chemical.pdf',
  'Abdominal Pain - Expanded Scope.pdf', 'Trauma - Blunt - Expanded Scope.pdf', 'Pain Management w expanded scope.pdf',
  'Shock - Medical - Expanded Scope.pdf', 'Trauma - General - Expanded Scope.pdf', 'Vaginal Bleeding - Expanded Scope.pdf',
  'Adult Cardiac Arrest - Initial Care.pdf', 'Diabetic Emergency - Expanded Scope.pdf',
  'Difficulty Breathing - SCAPE or CHF.pdf', 'Electrical Injury and Electrocution.pdf',
  'High Altitude Cerebral Edema - HACE.pdf', 'Dislocations in Austere Environments.pdf',
  'High Altitude Pulmonary Edema - HAPE.pdf', 'Nausea and Vomiting - Expanded Scope.pdf',
  'Trauma - Eye Injury - Expanded Scope.pdf', 'General Medical Care - Expanded Scope.pdf',
  'Trauma - Penetrating - Expanded Scope.pdf', 'Adult Cardiac Arrest - VF-Pulseless VT.pdf',
  'Tranexamic Acid - TXA - Expanded Scope.pdf', 'Adult Cardiac Arrest - PEA and Asystole.pdf',
  'Allergy-Anaphylaxis with expanded scope.pdf', 'Bradycardia with pulse - Expanded Scope.pdf',
  'Acute Mountain Sickness - Expanded Scope.pdf', 'Rabies_postexposure_prophylaxis_algorithm.pdf',
  'Syncope - Weak and Dizzy - Expanded Scope.pdf', 'Airway Obstruction - Foreign Body - Choking.pdf',
  'Difficulty Breathing - Respiratory Distress.pdf', 'Environmental Hyperthermia - Expanded Scope.pdf',
  'Tachycardia - Wide Complex - Expanded Scope.pdf', 'Tachycardia - Narrow Complex - Expanded Scope.pdf',
  'Adult Cardiac Arrest - Additional Treatments to Consider.pdf', 'Difficulty Breathing - Asthma and COPD with expanded scope.pdf',
  'Termination of Resuscitation - Non-traumatic Cardiac Arrest.pdf', 'Adult Cardiac Arrest - Post Resuscitative Care - Expanded Scope.pdf',
  'Rabies World_Health_Organization_post_exposure_rabies_management.pdf',
];

String _newUuid() {
  final rng = Random.secure();
  final bytes = List.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<void> main() async {
  final dir = Directory('assets/protocols');
  if (!await dir.exists()) {
    stderr.writeln('assets/protocols/ not found -- run this from the aeriemed/ project root.');
    exit(1);
  }

  var ok = 0, missing = 0, failed = 0;
  for (final filename in _rootProtocolFiles) {
    final file = File('${dir.path}/$filename');
    if (!await file.exists()) {
      stdout.writeln('SKIP (not found): $filename');
      missing++;
      continue;
    }
    final bytes = await file.readAsBytes();
    final id = _newUuid();
    final name = filename.replaceAll('.pdf', '');

    final uploadRes = await http.post(
      Uri.parse('$_supabaseUrl/storage/v1/object/protocols/$id.pdf'),
      headers: {
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $_supabaseAnonKey',
        'Content-Type': 'application/pdf',
      },
      body: bytes,
    );
    if (uploadRes.statusCode >= 300) {
      stderr.writeln('UPLOAD FAILED: $filename -> ${uploadRes.statusCode} ${uploadRes.body}');
      failed++;
      continue;
    }

    final insertRes = await http.post(
      Uri.parse('$_supabaseUrl/rest/v1/protocols'),
      headers: {
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $_supabaseAnonKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: jsonEncode({
        'id': id,
        'name': name,
        'version': 1,
        'file_path': '$id.pdf',
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': 'Migration Script',
        'notes': '',
        'target_user_ids': null,
        'target_team_id': null,
        'category': 'medical',
      }),
    );
    if (insertRes.statusCode >= 300) {
      stderr.writeln('INSERT FAILED: $filename -> ${insertRes.statusCode} ${insertRes.body}');
      failed++;
      continue;
    }

    stdout.writeln('OK: $filename -> $id');
    ok++;
  }

  stdout.writeln('\nDone. $ok uploaded, $missing missing locally, $failed failed.');
  if (failed == 0 && missing == 0) {
    stdout.writeln('All ${_rootProtocolFiles.length} protocols migrated successfully.');
    stdout.writeln('You can now delete these specific files from assets/protocols/ (leave everything else).');
  }
}
