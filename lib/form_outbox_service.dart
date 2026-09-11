import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'form_email_service.dart' show sendFormPdfByEmail;
import 'transmitted_form_service.dart' show recordAndUploadTransmittedForm, newUuidV4;

/// Durable local outbox for emailed forms. A send attempt is tried
/// immediately; if it fails (no/poor connectivity, server error), the form
/// is already safely on disk and gets retried automatically -- on the next
/// app start, periodically while the app is open (see [startAutoFlush]), and
/// whenever [flushQueue] is called explicitly (e.g. a manual "Retry now").
///
/// The PDF + metadata are written to disk BEFORE the network attempt, not
/// after a failure is caught -- so a crash or force-quit mid-send can never
/// silently lose a filled-out form.
class FormOutboxService {
  FormOutboxService._();
  static final instance = FormOutboxService._();

  /// Number of forms currently queued, waiting to send. UI can listen to
  /// this to show a "3 forms queued" banner.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  bool _flushing = false;
  Timer? _timer;

  Future<Directory> _outboxDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/form_outbox');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Starts a periodic background retry (every [interval], default 45s)
  /// while the app is running. Safe to call multiple times -- restarts the
  /// timer rather than stacking multiple.
  void startAutoFlush({Duration interval = const Duration(seconds: 45)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => flushQueue());
    // Also try once immediately (e.g. right after app start).
    flushQueue();
  }

  /// Writes the form to the durable queue, then makes one immediate send
  /// attempt. Returns true if it went out right away, false if it's queued
  /// for later (not an error -- the caller should tell the user it's queued,
  /// not that it failed).
  Future<bool> enqueueOrSend({
    required Uint8List pdfBytes,
    required String filename,
    required String recipientEmail,
    required String subject,
    required String formType,
    required String formTitle,
    required String summary,
    required String sentBy,
  }) async {
    final id = newUuidV4();
    final dir = await _outboxDir();
    final pdfFile = File('${dir.path}/$id.pdf');
    final metaFile = File('${dir.path}/$id.json');
    await pdfFile.writeAsBytes(pdfBytes);
    await metaFile.writeAsString(jsonEncode({
      'filename': filename,
      'recipientEmail': recipientEmail,
      'subject': subject,
      'formType': formType,
      'formTitle': formTitle,
      'summary': summary,
      'sentBy': sentBy,
      'queuedAt': DateTime.now().toIso8601String(),
    }));
    await _updateCount();

    final sent = await _attemptSend(
      pdfFile: pdfFile,
      metaFile: metaFile,
      pdfBytes: pdfBytes,
      filename: filename,
      recipientEmail: recipientEmail,
      subject: subject,
      formType: formType,
      formTitle: formTitle,
      summary: summary,
      sentBy: sentBy,
    );
    return sent;
  }

  /// Retries every currently-queued form once. Safe to call frequently --
  /// no-ops if the queue is empty or a flush is already in progress.
  Future<void> flushQueue() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final dir = await _outboxDir();
      final entries = await dir.list().toList();
      final metaFiles = entries.whereType<File>().where((f) => f.path.endsWith('.json')).toList();
      for (final metaFile in metaFiles) {
        final id = metaFile.path.split(Platform.pathSeparator).last.replaceAll('.json', '');
        final pdfFile = File('${dir.path}/$id.pdf');
        if (!await pdfFile.exists()) {
          // Orphaned metadata with no PDF -- nothing usable to send.
          await metaFile.delete();
          continue;
        }
        Map<String, dynamic> meta;
        try {
          meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          await metaFile.delete();
          await pdfFile.delete();
          continue;
        }
        final pdfBytes = await pdfFile.readAsBytes();
        await _attemptSend(
          pdfFile: pdfFile,
          metaFile: metaFile,
          pdfBytes: pdfBytes,
          filename: meta['filename'] as String? ?? 'form.pdf',
          recipientEmail: meta['recipientEmail'] as String? ?? '',
          subject: meta['subject'] as String? ?? '',
          formType: meta['formType'] as String? ?? '',
          formTitle: meta['formTitle'] as String? ?? '',
          summary: meta['summary'] as String? ?? '',
          sentBy: meta['sentBy'] as String? ?? '',
        );
      }
    } finally {
      _flushing = false;
      await _updateCount();
    }
  }

  Future<bool> _attemptSend({
    required File pdfFile,
    required File metaFile,
    required Uint8List pdfBytes,
    required String filename,
    required String recipientEmail,
    required String subject,
    required String formType,
    required String formTitle,
    required String summary,
    required String sentBy,
  }) async {
    try {
      await sendFormPdfByEmail(
        pdfBytes: pdfBytes,
        filename: filename,
        recipientEmail: recipientEmail,
        subject: subject,
      );
      // Archiving to the Command Console is best-effort and never blocks or
      // fails the send itself -- see recordAndUploadTransmittedForm.
      await recordAndUploadTransmittedForm(
        pdfBytes: pdfBytes,
        fileName: filename,
        formType: formType,
        formTitle: formTitle,
        summary: summary,
        recipientEmail: recipientEmail,
        subject: subject,
        sentBy: sentBy,
      );
      if (await pdfFile.exists()) await pdfFile.delete();
      if (await metaFile.exists()) await metaFile.delete();
      await _updateCount();
      return true;
    } catch (_) {
      // Still queued -- left on disk for the next flush.
      return false;
    }
  }

  Future<void> _updateCount() async {
    final dir = await _outboxDir();
    final entries = await dir.list().toList();
    pendingCount.value = entries.whereType<File>().where((f) => f.path.endsWith('.json')).length;
  }
}
