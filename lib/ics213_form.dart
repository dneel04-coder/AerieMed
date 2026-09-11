import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ics213_pdf.dart';
import 'form_email_service.dart';
import 'signature_pad.dart';

const _kIncidentNameKey = 'ics213_incident_name';

/// The ICS 213 General Message form -- a fillable replica of the FEMA ICS
/// Form 213 (v3), following the same pattern as ShiftTicketFormScreen.
class Ics213FormScreen extends StatefulWidget {
  const Ics213FormScreen({super.key});

  @override
  State<Ics213FormScreen> createState() => _Ics213FormScreenState();
}

class _Ics213FormScreenState extends State<Ics213FormScreen> {
  final _incidentName = TextEditingController();
  final _to = TextEditingController();
  final _from = TextEditingController();
  final _subject = TextEditingController();
  final _date = TextEditingController();
  final _time = TextEditingController();
  final _message = TextEditingController();
  final _approvedByName = TextEditingController();
  final _approvedByTitle = TextEditingController();
  Uint8List? _approvedBySignature;
  final _reply = TextEditingController();
  final _repliedByName = TextEditingController();
  final _repliedByTitle = TextEditingController();
  final _repliedByDateTime = TextEditingController();
  Uint8List? _repliedBySignature;

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStickyFields();
  }

  Future<void> _loadStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    _incidentName.text = prefs.getString(_kIncidentNameKey) ?? '';
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIncidentNameKey, _incidentName.text.trim());
  }

  @override
  void dispose() {
    for (final c in [
      _incidentName, _to, _from, _subject, _date, _time, _message,
      _approvedByName, _approvedByTitle, _reply, _repliedByName,
      _repliedByTitle, _repliedByDateTime,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Ics213Data _compile() => Ics213Data(
        incidentName: _incidentName.text.trim(),
        to: _to.text.trim(),
        from: _from.text.trim(),
        subject: _subject.text.trim(),
        date: _date.text.trim(),
        time: _time.text.trim(),
        message: _message.text.trim(),
        approvedByName: _approvedByName.text.trim(),
        approvedByTitle: _approvedByTitle.text.trim(),
        approvedBySignatureImage: _approvedBySignature,
        reply: _reply.text.trim(),
        repliedByName: _repliedByName.text.trim(),
        repliedByTitle: _repliedByTitle.text.trim(),
        repliedByDateTime: _repliedByDateTime.text.trim(),
        repliedBySignatureImage: _repliedBySignature,
      );

  String _filename() {
    String sanitize(String s) => s.trim().isEmpty
        ? 'UNK'
        : s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final now = DateTime.now();
    final yymmdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'ICS213-${sanitize(_subject.text)}-$yymmdd';
  }

  Future<void> _preview() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs213Pdf(_compile());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs213Pdf(_compile());
    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: '${_filename()}.pdf');
  }

  Future<void> _download() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs213Pdf(_compile());
    if (!mounted) return;
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ICS 213 PDF',
        fileName: '${_filename()}.pdf',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (!mounted || savePath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $savePath')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _email() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs213Pdf(_compile());
    if (!mounted) return;
    await showEmailFormDialog(
      context,
      pdfBytes: bytes,
      filename: '${_filename()}.pdf',
      subject: 'General Message (ICS 213) — ${_subject.text.trim().isEmpty ? 'ResQruck' : _subject.text.trim()}',
      formType: 'ics213',
      formTitle: 'General Message (ICS 213)',
      summary: '${_subject.text.trim().isEmpty ? 'No subject' : _subject.text.trim()}'
          '${_to.text.trim().isEmpty ? '' : ' — To: ${_to.text.trim()}'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _card('Message', Colors.indigo, [
              _tf('Incident Name (Optional)', _incidentName),
              const SizedBox(height: 8),
              _tf('To (Name and Position)', _to),
              const SizedBox(height: 8),
              _tf('From (Name and Position)', _from),
              const SizedBox(height: 8),
              _tf('Subject', _subject),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Date', _date)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Time', _time)),
              ]),
              const SizedBox(height: 8),
              _tf('Message', _message, maxLines: 6),
            ]),
            _card('Approved By', Colors.teal, [
              _tf('Name', _approvedByName),
              const SizedBox(height: 8),
              _tf('Position/Title', _approvedByTitle),
              const SizedBox(height: 8),
              SignatureField(
                label: 'Signature',
                signatureBytes: _approvedBySignature,
                onChanged: (bytes) => setState(() => _approvedBySignature = bytes),
              ),
            ]),
            _card('Reply', Colors.deepOrange, [
              _tf('Reply', _reply, maxLines: 6),
            ]),
            _card('Replied By', Colors.blueGrey, [
              _tf('Name', _repliedByName),
              const SizedBox(height: 8),
              _tf('Position/Title', _repliedByTitle),
              const SizedBox(height: 8),
              _tf('Date/Time', _repliedByDateTime),
              const SizedBox(height: 8),
              SignatureField(
                label: 'Signature',
                signatureBytes: _repliedBySignature,
                onChanged: (bytes) => setState(() => _repliedBySignature = bytes),
              ),
            ]),
          ]),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _email,
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _card(String title, Color accent, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8, color: accent)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }
}
