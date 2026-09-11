import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sf261_pdf.dart';
import 'form_email_service.dart';
import 'signature_pad.dart';

const _kFireNameKey = 'sf261_fire_name';
const _kFireNumberKey = 'sf261_fire_number';
const _kOfficeKey = 'sf261_office';
const _crewRowCount = 20;

/// The SF-261 Crew Time Report form -- a fillable replica of Standard Form
/// 261 (Rev. 11/2021, NWCG PMS 902).
class Sf261FormScreen extends StatefulWidget {
  const Sf261FormScreen({super.key});

  @override
  State<Sf261FormScreen> createState() => _Sf261FormScreenState();
}

class _Sf261FormScreenState extends State<Sf261FormScreen> {
  final _crewName = TextEditingController();
  final _crewNumber = TextEditingController();
  final _officeResponsibleForFire = TextEditingController();
  final _fireName = TextEditingController();
  final _fireNumber = TextEditingController();

  final List<Map<String, TextEditingController>> _crewRows = List.generate(
    _crewRowCount,
    (_) => {
      'remarksNumber': TextEditingController(),
      'employeeName': TextEditingController(),
      'classification': TextEditingController(),
      'date1': TextEditingController(),
      'timeOn1': TextEditingController(),
      'timeOff1': TextEditingController(),
      'date2': TextEditingController(),
      'timeOn2': TextEditingController(),
      'timeOff2': TextEditingController(),
    },
  );

  final _remarks = TextEditingController();
  Uint8List? _officerInChargeSignature;
  final _officerInChargeTitle = TextEditingController();
  final _preparerName = TextEditingController();
  final _date = TextEditingController();

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStickyFields();
  }

  Future<void> _loadStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    _fireName.text = prefs.getString(_kFireNameKey) ?? '';
    _fireNumber.text = prefs.getString(_kFireNumberKey) ?? '';
    _officeResponsibleForFire.text = prefs.getString(_kOfficeKey) ?? '';
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFireNameKey, _fireName.text.trim());
    await prefs.setString(_kFireNumberKey, _fireNumber.text.trim());
    await prefs.setString(_kOfficeKey, _officeResponsibleForFire.text.trim());
  }

  @override
  void dispose() {
    for (final c in [
      _crewName, _crewNumber, _officeResponsibleForFire, _fireName, _fireNumber,
      _remarks, _officerInChargeTitle, _preparerName, _date,
    ]) {
      c.dispose();
    }
    for (final row in _crewRows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Sf261Data _compile() => Sf261Data(
        crewName: _crewName.text.trim(),
        crewNumber: _crewNumber.text.trim(),
        officeResponsibleForFire: _officeResponsibleForFire.text.trim(),
        fireName: _fireName.text.trim(),
        fireNumber: _fireNumber.text.trim(),
        rows: [
          for (final row in _crewRows)
            Sf261CrewRow(
              remarksNumber: row['remarksNumber']!.text.trim(),
              employeeName: row['employeeName']!.text.trim(),
              classification: row['classification']!.text.trim(),
              date1: row['date1']!.text.trim(),
              timeOn1: row['timeOn1']!.text.trim(),
              timeOff1: row['timeOff1']!.text.trim(),
              date2: row['date2']!.text.trim(),
              timeOn2: row['timeOn2']!.text.trim(),
              timeOff2: row['timeOff2']!.text.trim(),
            ),
        ],
        remarks: _remarks.text.trim(),
        officerInChargeSignatureImage: _officerInChargeSignature,
        officerInChargeTitle: _officerInChargeTitle.text.trim(),
        preparerName: _preparerName.text.trim(),
        date: _date.text.trim(),
      );

  String _filename() {
    String sanitize(String s) => s.trim().isEmpty
        ? 'UNK'
        : s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final now = DateTime.now();
    final yymmdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'SF261-${sanitize(_crewName.text)}-$yymmdd';
  }

  Future<void> _preview() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildSf261Pdf(_compile());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildSf261Pdf(_compile());
    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: '${_filename()}.pdf');
  }

  Future<void> _download() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildSf261Pdf(_compile());
    if (!mounted) return;
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save SF-261 PDF',
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
    final bytes = await buildSf261Pdf(_compile());
    if (!mounted) return;
    await showEmailFormDialog(
      context,
      pdfBytes: bytes,
      filename: '${_filename()}.pdf',
      subject: 'Crew Time Report (SF-261) — ${_crewName.text.trim().isEmpty ? 'ResQruck' : _crewName.text.trim()}',
      formType: 'sf261',
      formTitle: 'Crew Time Report (SF-261)',
      summary: '${_crewName.text.trim().isEmpty ? 'Unknown crew' : _crewName.text.trim()}'
          '${_fireName.text.trim().isEmpty ? '' : ' — ${_fireName.text.trim()}'}',
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
            _card('Crew & Fire', Colors.indigo, [
              Row(children: [
                Expanded(flex: 2, child: _tf('Crew Name', _crewName)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Crew Number', _crewNumber)),
              ]),
              const SizedBox(height: 8),
              _tf('Office Responsible for Fire', _officeResponsibleForFire),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Fire Name', _fireName)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Fire Number', _fireNumber)),
              ]),
            ]),
            _sectionLabel('CREW MEMBERS'),
            _card('Crew Members', Colors.teal, [
              for (var i = 0; i < _crewRows.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                Text('Row ${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  SizedBox(width: 70, child: _tf('Remarks #', _crewRows[i]['remarksNumber']!)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _tf('Name of Employee', _crewRows[i]['employeeName']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Classification', _crewRows[i]['classification']!)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tf('Date', _crewRows[i]['date1']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField('On', _crewRows[i]['timeOn1']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField('Off', _crewRows[i]['timeOff1']!)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tf('Date', _crewRows[i]['date2']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField('On', _crewRows[i]['timeOn2']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField('Off', _crewRows[i]['timeOff2']!)),
                ]),
              ],
            ]),
            _card('Remarks', Colors.deepOrange, [
              _tf('Remarks', _remarks, maxLines: 4),
            ]),
            _card('Approval', Colors.blueGrey, [
              SignatureField(
                label: 'Officer-in-Charge (Signature)',
                signatureBytes: _officerInChargeSignature,
                onChanged: (bytes) => setState(() => _officerInChargeSignature = bytes),
              ),
              const SizedBox(height: 8),
              _tf('Title (Officer-in-Charge)', _officerInChargeTitle),
              const SizedBox(height: 8),
              _tf('Name (Person Posting to Emergency Time Report)', _preparerName),
              const SizedBox(height: 8),
              _tf('Date', _date),
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

  /// Crew Time Report times are military time (block 9/10 instructions: "ON"
  /// and "OFF" the job) -- digits only, capped at 4 (HHMM), matching the
  /// Shift Ticket's Personnel table Start/Stop fields.
  Widget _timeField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HHMM',
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }
}
