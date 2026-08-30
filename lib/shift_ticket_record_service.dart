import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'protocol_admin.dart' show SupabaseService;
import 'shift_ticket_pdf.dart' show ShiftTicketData;

String _newUuidV4() {
  final rng = Random.secure();
  final bytes = List.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A transmitted Shift Ticket, archived so the Command Console can browse
/// what's gone out -- mirrors DeploymentOrderService's storage-bucket +
/// metadata-table shape in protocol_admin.dart (same bucket-then-base64
/// fallback, same SDK-download-then-public-URL fallback), kept in its own
/// file since that shape doesn't need access to ProtocolSyncService's
/// private helpers.
class ShiftTicketRecord {
  final String id;
  final String incidentName;
  final String agreementNumber;
  final String resourceOrderNumber;
  final String equipmentMakeModel;
  final String recipientEmail;
  final String subject;
  final String filePath;
  final String fileName;
  final DateTime sentAt;
  final String sentBy;

  const ShiftTicketRecord({
    required this.id,
    required this.incidentName,
    required this.agreementNumber,
    required this.resourceOrderNumber,
    required this.equipmentMakeModel,
    required this.recipientEmail,
    required this.subject,
    required this.filePath,
    required this.fileName,
    required this.sentAt,
    required this.sentBy,
  });

  factory ShiftTicketRecord.fromMap(Map<String, dynamic> m) => ShiftTicketRecord(
        id: m['id'] as String,
        incidentName: m['incident_name'] as String? ?? '',
        agreementNumber: m['agreement_number'] as String? ?? '',
        resourceOrderNumber: m['resource_order_number'] as String? ?? '',
        equipmentMakeModel: m['equipment_make_model'] as String? ?? '',
        recipientEmail: m['recipient_email'] as String? ?? '',
        subject: m['subject'] as String? ?? '',
        filePath: m['file_path'] as String? ?? '',
        fileName: m['file_name'] as String? ?? '',
        sentAt: DateTime.tryParse(m['sent_at'] as String? ?? '') ?? DateTime.now(),
        sentBy: m['sent_by'] as String? ?? '',
      );
}

const _kBucket = 'shift_tickets';
const _kTable = 'shift_tickets';
const _kSupabaseBaseUrl = 'https://vlgiclyuxaleyusalexo.supabase.co';
const _kSupabaseAnonKey = 'sb_publishable_U6M_YMbubI1Y8qD4a3SKCA_Oeo6L75B';

/// Uploads the PDF and inserts a metadata row -- called right after a
/// successful send so the archive reflects only tickets that actually went
/// out, not ones a user filled in but never sent.
Future<void> recordAndUploadShiftTicket({
  required Uint8List pdfBytes,
  required String fileName,
  required ShiftTicketData data,
  required String recipientEmail,
  required String subject,
  required String sentBy,
}) async {
  final ok = await SupabaseService.ensureInitialized();
  final client = SupabaseService.client;
  if (!ok || client == null) return; // Archiving is best-effort; don't block the send.

  final id = _newUuidV4();
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
      'incident_name': data.incidentName,
      'agreement_number': data.agreementNumber,
      'resource_order_number': data.resourceOrderNumber,
      'equipment_make_model': data.equipmentMakeModel,
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

Future<List<ShiftTicketRecord>> allShiftTicketRecords() async {
  final ok = await SupabaseService.ensureInitialized();
  final client = SupabaseService.client;
  if (!ok || client == null) return [];
  try {
    return (await client.from(_kTable).select().order('sent_at', ascending: false) as List)
        .map((r) => ShiftTicketRecord.fromMap(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<Uint8List?> fetchShiftTicketRecordBytes(ShiftTicketRecord r) async {
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

Future<void> deleteShiftTicketRecord(ShiftTicketRecord r) async {
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
