import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ics214_pdf.dart';
import 'form_email_service.dart';
import 'signature_pad.dart';

const _kIncidentNameKey = 'ics214_incident_name';
const _resourceRowCount = 7;
const _logRowCount = 20;

/// The ICS 214 Activity Log form -- a fillable replica of the FEMA ICS Form
/// 214 (v3.1).
class Ics214FormScreen extends StatefulWidget {
  const Ics214FormScreen({super.key});

  @override
  State<Ics214FormScreen> createState() => _Ics214FormScreenState();
}

class _Ics214FormScreenState extends State<Ics214FormScreen> {
  final _incidentName = TextEditingController();
  final _opDateFrom = TextEditingController();
  final _opDateTo = TextEditingController();
  final _opTimeFrom = TextEditingController();
  final _opTimeTo = TextEditingController();
  final _name = TextEditingController();
  final _icsPosition = TextEditingController();
  final _homeAgency = TextEditingController();

  final List<Map<String, TextEditingController>> _resourceRows = List.generate(
    _resourceRowCount,
    (_) => {
      'name': TextEditingController(),
      'icsPosition': TextEditingController(),
      'homeAgency': TextEditingController(),
    },
  );

  final List<Map<String, TextEditingController>> _logRows = List.generate(
    _logRowCount,
    (_) => {
      'dateTime': TextEditingController(),
      'activity': TextEditingController(),
    },
  );

  final _preparedByName = TextEditingController();
  final _preparedByTitle = TextEditingController();
  Uint8List? _preparedBySignature;
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
      _incidentName, _opDateFrom, _opDateTo, _opTimeFrom, _opTimeTo,
      _name, _icsPosition, _homeAgency, _preparedByName, _preparedByTitle,
      _preparedByDateTime,
    ]) {
      c.dispose();
    }
    for (final row in [..._resourceRows, ..._logRows]) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Ics214Data _compile() => Ics214Data(
        incidentName: _incidentName.text.trim(),
        opPeriodDateFrom: _opDateFrom.text.trim(),
        opPeriodDateTo: _opDateTo.text.trim(),
        opPeriodTimeFrom: _opTimeFrom.text.trim(),
        opPeriodTimeTo: _opTimeTo.text.trim(),
        name: _name.text.trim(),
        icsPosition: _icsPosition.text.trim(),
        homeAgency: _homeAgency.text.trim(),
        resources: [
          for (final row in _resourceRows)
            Ics214ResourceRow(
              name: row['name']!.text.trim(),
              icsPosition: row['icsPosition']!.text.trim(),
              homeAgency: row['homeAgency']!.text.trim(),
            ),
        ],
        log: [
          for (final row in _logRows)
            Ics214LogEntry(
              dateTime: row['dateTime']!.text.trim(),
              activity: row['activity']!.text.trim(),
            ),
        ],
        preparedByName: _preparedByName.text.trim(),
        preparedByTitle: _preparedByTitle.text.trim(),
        preparedByDateTime: _preparedByDateTime.text.trim(),
        preparedBySignatureImage: _preparedBySignature,
      );

  String _filename() {
    String sanitize(String s) => s.trim().isEmpty
        ? 'UNK'
        : s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final now = DateTime.now();
    final yymmdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'ICS214-${sanitize(_incidentName.text)}-$yymmdd';
  }

  Future<void> _preview() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs214Pdf(_compile());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs214Pdf(_compile());
    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: '${_filename()}.pdf');
  }

  Future<void> _download() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildIcs214Pdf(_compile());
    if (!mounted) return;
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ICS 214 PDF',
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
    final bytes = await buildIcs214Pdf(_compile());
    if (!mounted) return;
    await showEmailFormDialog(
      context,
      pdfBytes: bytes,
      filename: '${_filename()}.pdf',
      subject: 'Activity Log (ICS 214) — ${_incidentName.text.trim().isEmpty ? 'ResQruck' : _incidentName.text.trim()}',
      formType: 'ics214',
      formTitle: 'Activity Log (ICS 214)',
      summary: '${_incidentName.text.trim().isEmpty ? 'Unknown incident' : _incidentName.text.trim()}'
          '${_name.text.trim().isEmpty ? '' : ' — ${_name.text.trim()}'}',
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
            _card('Unit / Resource', Colors.teal, [
              _tf('Name', _name),
              const SizedBox(height: 8),
              _tf('ICS Position', _icsPosition),
              const SizedBox(height: 8),
              _tf('Home Agency (and Unit)', _homeAgency),
            ]),
            _sectionLabel('RESOURCES ASSIGNED'),
            _card('Resources', Colors.deepOrange, [
              for (var i = 0; i < _resourceRows.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                Text('Resource ${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _tf('Name', _resourceRows[i]['name']!),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tf('ICS Position', _resourceRows[i]['icsPosition']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Home Agency (and Unit)', _resourceRows[i]['homeAgency']!)),
                ]),
              ],
            ]),
            _sectionLabel('ACTIVITY LOG'),
            _card('Activity Log', Colors.purple, [
              for (var i = 0; i < _logRows.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                Row(children: [
                  SizedBox(width: 110, child: _tf('Date/Time', _logRows[i]['dateTime']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Notable Activities', _logRows[i]['activity']!)),
                ]),
              ],
            ]),
            _card('Prepared By', Colors.blueGrey, [
              _tf('Name', _preparedByName),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Position/Title', _preparedByTitle)),
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
