import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ics205_pdf.dart';
import 'form_email_service.dart';
import 'signature_pad.dart';

const _kIncidentNameKey = 'ics205_incident_name';
const _channelRowCount = 7;

/// The ICS 205 Incident Radio Communications Plan form -- a fillable
/// replica of the FEMA ICS Form 205 (v3.1).
class Ics205FormScreen extends StatefulWidget {
  const Ics205FormScreen({super.key});

  @override
  State<Ics205FormScreen> createState() => _Ics205FormScreenState();
}

class _Ics205FormScreenState extends State<Ics205FormScreen> {
  final _incidentName = TextEditingController();
  final _datePrepared = TextEditingController();
  final _timePrepared = TextEditingController();
  final _opDateFrom = TextEditingController();
  final _opDateTo = TextEditingController();
  final _opTimeFrom = TextEditingController();
  final _opTimeTo = TextEditingController();

  final List<Map<String, TextEditingController>> _channelRows = List.generate(
    _channelRowCount,
    (_) => {
      'zoneGroup': TextEditingController(),
      'channelNumber': TextEditingController(),
      'function': TextEditingController(),
      'channelName': TextEditingController(),
      'assignment': TextEditingController(),
      'rxFreq': TextEditingController(),
      'rxTone': TextEditingController(),
      'txFreq': TextEditingController(),
      'txTone': TextEditingController(),
      'mode': TextEditingController(),
      'remarks': TextEditingController(),
    },
  );

  final _specialInstructions = TextEditingController();
  final _preparedByName = TextEditingController();
  Uint8List? _preparedBySignature;
  final _iapPage = TextEditingController();
  final _preparedByDateTime = TextEditingController();

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
      _incidentName, _datePrepared, _timePrepared, _opDateFrom, _opDateTo,
      _opTimeFrom, _opTimeTo, _specialInstructions, _preparedByName,
      _iapPage, _preparedByDateTime,
    ]) {
      c.dispose();
    }
    for (final row in _channelRows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Ics205Data _compile() => Ics205Data(
        incidentName: _incidentName.text.trim(),
        datePrepared: _datePrepared.text.trim(),
        timePrepared: _timePrepared.text.trim(),
        opPeriodDateFrom: _opDateFrom.text.trim(),
        opPeriodDateTo: _opDateTo.text.trim(),
        opPeriodTimeFrom: _opTimeFrom.text.trim(),
        opPeriodTimeTo: _opTimeTo.text.trim(),
        channels: [
          for (final row in _channelRows)
            Ics205ChannelRow(
              zoneGroup: row['zoneGroup']!.text.trim(),
              channelNumber: row['channelNumber']!.text.trim(),
              function: row['function']!.text.trim(),
              channelName: row['channelName']!.text.trim(),
              assignment: row['assignment']!.text.trim(),
              rxFreq: row['rxFreq']!.text.trim(),
              rxTone: row['rxTone']!.text.trim(),
              txFreq: row['txFreq']!.text.trim(),
              txTone: row['txTone']!.text.trim(),
              mode: row['mode']!.text.trim(),
              remarks: row['remarks']!.text.trim(),
            ),
        ],
        specialInstructions: _specialInstructions.text.trim(),
        preparedByName: _preparedByName.text.trim(),
        preparedBySignatureImage: _preparedBySignature,
        iapPage: _iapPage.text.trim(),
        preparedByDateTime: _preparedByDateTime.text.trim(),
      );

  String _filename() {
    String sanitize(String s) => s.trim().isEmpty
        ? 'UNK'
        : s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final now = DateTime.now();
    final yymmdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'ICS205-${sanitize(_incidentName.text)}-$yymmdd';
  }

  Future<void> _preview() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs205Pdf(_compile());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs205Pdf(_compile());
    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: '${_filename()}.pdf');
  }

  Future<void> _download() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs205Pdf(_compile());
    if (!mounted) return;
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ICS 205 PDF',
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
    final bytes = await buildIcs205Pdf(_compile());
    if (!mounted) return;
    await showEmailFormDialog(
      context,
      pdfBytes: bytes,
      filename: '${_filename()}.pdf',
      subject: 'Incident Radio Communications Plan (ICS 205) — ${_incidentName.text.trim().isEmpty ? 'ResQruck' : _incidentName.text.trim()}',
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
            _card('Incident', Colors.indigo, [
              _tf('Incident Name', _incidentName),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Date Prepared', _datePrepared)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Time Prepared', _timePrepared)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Op. Period Date From', _opDateFrom)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Date To', _opDateTo)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Op. Period Time From', _opTimeFrom)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Time To', _opTimeTo)),
              ]),
            ]),
            _sectionLabel('BASIC RADIO CHANNEL USE'),
            _card('Channels', Colors.teal, [
              for (var i = 0; i < _channelRows.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                Text('Channel ${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _tf('Zone Grp.', _channelRows[i]['zoneGroup']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Ch #', _channelRows[i]['channelNumber']!)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _tf('Function', _channelRows[i]['function']!)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tf('Channel Name/Talkgroup', _channelRows[i]['channelName']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Assignment', _channelRows[i]['assignment']!)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tf('RX Freq', _channelRows[i]['rxFreq']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('RX Tone/NAC', _channelRows[i]['rxTone']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('TX Freq', _channelRows[i]['txFreq']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('TX Tone/NAC', _channelRows[i]['txTone']!)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tf('Mode (A, D, or M)', _channelRows[i]['mode']!)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _tf('Remarks', _channelRows[i]['remarks']!)),
                ]),
              ],
            ]),
            _card('Special Instructions', Colors.deepOrange, [
              _tf('Special Instructions', _specialInstructions, maxLines: 3),
            ]),
            _card('Prepared By (Communications Unit Leader)', Colors.blueGrey, [
              _tf('Name', _preparedByName),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('IAP Page', _iapPage)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Date/Time', _preparedByDateTime)),
              ]),
              const SizedBox(height: 8),
              SignatureField(
                label: 'Signature',
                signatureBytes: _preparedBySignature,
                onChanged: (bytes) => setState(() => _preparedBySignature = bytes),
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

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.outline)),
      );

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
