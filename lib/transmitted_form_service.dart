import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'protocol_admin.dart' show SupabaseService;

String newUuidV4() {
  final rng = Random.secure();
  final bytes = List.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Any transmitted form -- Shift Ticket, Crew Swap, SF-261, ICS 214/205/213
/// -- archived so the Command Console can browse everything that's actually
/// gone out, regardless of which form it was. One shared table/bucket
/// instead of one per form type, distinguished by [formType]/[formTitle].
/// Mirrors DeploymentOrderService's storage-bucket + metadata-table shape in
/// protocol_admin.dart (same bucket-then-base64 fallback, same
/// SDK-download-then-public-URL fallback).
class TransmittedFormRecord {
  final String id;
  final String formType;
  final String formTitle;
  final String summary;
  final String recipientEmail;
  final String subject;
  final String filePath;
  final String fileName;
  final DateTime sentAt;
  final String sentBy;

  const TransmittedFormRecord({
    required this.id,
    required this.formType,
    required this.formTitle,
    required this.summary,
    required this.recipientEmail,
    required this.subject,
    required this.filePath,
    required this.fileName,
    required this.sentAt,
    required this.sentBy,
  });

  factory TransmittedFormRecord.fromMap(Map<String, dynamic> m) => TransmittedFormRecord(
        id: m['id'] as String,
        formType: m['form_type'] as String? ?? '',
        formTitle: m['form_title'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        recipientEmail: m['recipient_email'] as String? ?? '',
        subject: m['subject'] as String? ?? '',
        filePath: m['file_path'] as String? ?? '',
        fileName: m['file_name'] as String? ?? '',
        sentAt: DateTime.tryParse(m['sent_at'] as String? ?? '') ?? DateTime.now(),
        sentBy: m['sent_by'] as String? ?? '',
      );
}

const _kBucket = 'transmitted_forms';
const _kTable = 'transmitted_forms';
const _kSupabaseBaseUrl = 'https://vlgiclyuxaleyusalexo.supabase.co';
const _kSupabaseAnonKey = 'sb_publishable_U6M_YMbubI1Y8qD4a3SKCA_Oeo6L75B';

/// Uploads the PDF and inserts a metadata row -- called right after a
/// successful send (immediate or via FormOutboxService's later retry) so the
/// archive reflects only forms that actually went out, not ones a user
/// filled in but never sent. Best-effort: a missing table/bucket (schema
/// not run yet) never blocks or fails the send itself.
Future<void> recordAndUploadTransmittedForm({
  required Uint8List pdfBytes,
  required String fileName,
  required String formType,
  required String formTitle,
  required String summary,
  required String recipientEmail,
  required String subject,
  required String sentBy,
}) async {
  final ok = await SupabaseService.ensureInitialized();
  final client = SupabaseService.client;
  if (!ok || client == null) return;

  final id = newUuidV4();
  final storagePath = '$id.pdf';
  var savedPath = storagePath;

  try {
    await client.storage.from(_kBucket).uploadBinary(
          storagePath,
          pdfBytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'),
        );
  } catch (_) {
    // Bucket not set up yet -- embed as base64 so the record still exists.
    savedPath = 'base64:${base64.encode(pdfBytes)}';
  }

  try {
    await client.from(_kTable).insert({
      'id': id,
      'form_type': formType,
      'form_title': formTitle,
      'summary': summary,
      'recipient_email': recipientEmail,
      'subject': subject,
      'file_path': savedPath,
      'file_name': fileName,
      'sent_at': DateTime.now().toIso8601String(),
      'sent_by': sentBy,
    });
  } catch (_) {
    // Table not created yet -- see the Command Console's Show Schema dialog.
  }
}

Future<List<TransmittedFormRecord>> allTransmittedForms() async {
  final ok = await SupabaseService.ensureInitialized();
  final client = SupabaseService.client;
  if (!ok || client == null) return [];
  try {
    return (await client.from(_kTable).select().order('sent_at', ascending: false) as List)
        .map((r) => TransmittedFormRecord.fromMap(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<Uint8List?> fetchTransmittedFormBytes(TransmittedFormRecord r) async {
  if (r.filePath.startsWith('base64:')) {
    try {
      return base64.decode(r.filePath.substring(7));
    } catch (_) {
      return null;
    }
  }
  if (r.filePath.isEmpty) return null;
  final ok = await SupabaseService.ensureInitialized();
  final client = SupabaseService.client;
  if (ok && client != null) {
    try {
      return await client.storage.from(_kBucket).download(r.filePath);
    } catch (_) {}
  }
  try {
    final url = '$_kSupabaseBaseUrl/storage/v1/object/public/$_kBucket/${r.filePath}';
    final resp = await http
        .get(Uri.parse(url), headers: {'Authorization': 'Bearer $_kSupabaseAnonKey', 'apikey': _kSupabaseAnonKey})
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) return resp.bodyBytes;
  } catch (_) {}
  return null;
}

Future<void> deleteTransmittedFormRecord(TransmittedFormRecord r) async {
  final ok = await SupabaseService.ensureInitialized();
  final client = SupabaseService.client;
  if (!ok || client == null) return;
  try {
    await client.storage.from(_kBucket).remove([r.filePath]);
  } catch (_) {}
  try {
    await client.from(_kTable).delete().eq('id', r.id);
  } catch (_) {}
}
