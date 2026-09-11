import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocol_admin.dart' show SupabaseService;
import 'form_outbox_service.dart';

const _kLastRecipientKey = 'form_email_last_recipient';

/// Emails a generated form PDF via the send-form-email Edge Function
/// (Resend-backed) -- a real backend send, not just an OS share-sheet
/// handoff, so it works even without a mail app configured on the device.
/// Throws on any failure (network, server) -- callers that need offline
/// durability should go through FormOutboxService.enqueueOrSend instead of
/// calling this directly, which is what showEmailFormDialog below does.
Future<void> sendFormPdfByEmail({
  required Uint8List pdfBytes,
  required String filename,
  required String recipientEmail,
  required String subject,
  String body = '',
}) async {
  final ok = await SupabaseService.ensureInitialized();
  if (!ok || SupabaseService.client == null) {
    throw Exception('Cannot reach server. Check your connection.');
  }
  final resp = await SupabaseService.client!.functions.invoke('send-form-email', body: {
    'to': recipientEmail,
    'subject': subject,
    'text': body,
    'filename': filename,
    'pdfBase64': base64Encode(pdfBytes),
  });
  if (resp.status != 200) {
    throw Exception('Send failed (${resp.status}): ${resp.data}');
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastRecipientKey, recipientEmail);
}

/// Prompts for a recipient address (pre-filled with the last one used across
/// any form) and a subject line (pre-filled with [subject], editable by the
/// sender before it goes out), then hands the PDF to FormOutboxService,
/// which tries to send immediately and durably queues it for automatic
/// retry if that fails (no/poor connectivity). [formType]/[formTitle]/
/// [summary] describe the form for the Command Console's transmitted-forms
/// archive, which every successful send (immediate or delayed) is recorded
/// into. Shows its own snackbars for progress/success/queued/failure.
Future<void> showEmailFormDialog(
  BuildContext context, {
  required Uint8List pdfBytes,
  required String filename,
  required String subject,
  required String formType,
  required String formTitle,
  required String summary,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final lastRecipient = prefs.getString(_kLastRecipientKey) ?? '';
  final sentBy = prefs.getString('tac_callsign') ?? '';
  final emailCtrl = TextEditingController(text: lastRecipient);
  final subjectCtrl = TextEditingController(text: subject);
  if (!context.mounted) return;
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Email This Form'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Recipient Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: subjectCtrl,
          decoration: const InputDecoration(
            labelText: 'Subject',
            border: OutlineInputBorder(),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, (emailCtrl.text.trim(), subjectCtrl.text.trim())),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  emailCtrl.dispose();
  subjectCtrl.dispose();
  if (result == null || result.$1.isEmpty || !context.mounted) return;
  final (email, finalSubject) = result;
  final sentSubject = finalSubject.isEmpty ? subject : finalSubject;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Sending…'), duration: Duration(seconds: 20)));
  try {
    final sentNow = await FormOutboxService.instance.enqueueOrSend(
      pdfBytes: pdfBytes,
      filename: filename,
      recipientEmail: email,
      subject: sentSubject,
      formType: formType,
      formTitle: formTitle,
      summary: summary,
      sentBy: sentBy,
    );
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(sentNow
          ? 'Sent to $email'
          : 'No connection — queued, will send to $email automatically once connected'),
      backgroundColor: sentNow ? null : Colors.amber[800],
      duration: Duration(seconds: sentNow ? 4 : 6),
    ));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text('Could not queue: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4)));
  }
}
