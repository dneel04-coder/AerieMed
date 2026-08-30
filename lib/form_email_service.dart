import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocol_admin.dart' show SupabaseService;

const _kLastRecipientKey = 'form_email_last_recipient';

/// Emails a generated form PDF via the send-form-email Edge Function
/// (Resend-backed) -- a real backend send, not just an OS share-sheet
/// handoff, so it works even without a mail app configured on the device.
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
/// sender before it goes out), then sends [pdfBytes]. Shows its own snackbars
/// for progress/success/failure, matching this app's existing dialog/snackbar
/// conventions -- callers just need a BuildContext and the PDF to send.
Future<void> showEmailFormDialog(
  BuildContext context, {
  required Uint8List pdfBytes,
  required String filename,
  required String subject,
  Future<void> Function(String recipientEmail, String subject)? onSent,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final lastRecipient = prefs.getString(_kLastRecipientKey) ?? '';
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

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Sending…'), duration: Duration(seconds: 20)));
  try {
    final sentSubject = finalSubject.isEmpty ? subject : finalSubject;
    await sendFormPdfByEmail(
      pdfBytes: pdfBytes,
      filename: filename,
      recipientEmail: email,
      subject: sentSubject,
    );
    if (onSent != null) await onSent(email, sentSubject);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Sent to $email')));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text('Could not send: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4)));
  }
}
