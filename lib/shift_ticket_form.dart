import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shift_ticket_pdf.dart';
import 'form_email_service.dart';
import 'shift_ticket_record_service.dart';
import 'signature_pad.dart';

const _kAgreementNumberKey = 'shift_ticket_agreement_number';
const _kContractorAgencyNameKey = 'shift_ticket_contractor_agency_name';
const _kIncidentNameKey = 'shift_ticket_incident_name';
const _kIncidentNumberKey = 'shift_ticket_incident_number';
const _kFinancialCodeKey = 'shift_ticket_financial_code';

const _equipmentRowCount = 3;
const _personnelRowCount = 4;

/// The Emergency Equipment Shift Ticket (OF-297) form -- embedded directly in
/// the Team section's tab, matching CrewSwapFormScreen's "used often, one tap
/// away" placement.
class ShiftTicketFormScreen extends StatefulWidget {
  const ShiftTicketFormScreen({super.key});

  @override
  State<ShiftTicketFormScreen> createState() => _ShiftTicketFormScreenState();
}

class _ShiftTicketFormScreenState extends State<ShiftTicketFormScreen> {
  final _agreementNumber = TextEditingController();
  final _contractorAgencyName = TextEditingController();
  final _resourceOrderNumber = TextEditingController();
  final _incidentName = TextEditingController();
  final _incidentNumber = TextEditingController();
  final _financialCode = TextEditingController();
  final _equipmentMakeModel = TextEditingController();
  final _equipmentType = TextEditingController();
  final _serialVinNumber = TextEditingController();
  final _licenseIdNumber = TextEditingController();

  bool _transportRetained = false;
  bool _mobilization = false;
  bool _demobilization = false;
  bool _appliesMiles = false;
  bool _appliesHours = false;

  // Each row is a fixed set of named controllers, matching the paper form's
  // fixed number of blank rows rather than an open-ended add/remove list.
  final List<Map<String, TextEditingController>> _equipmentRows = List.generate(
    _equipmentRowCount,
    (_) => {
      'date': TextEditingController(),
      'start': TextEditingController(),
      'stop': TextEditingController(),
      'total': TextEditingController(),
      'quantity': TextEditingController(),
      'type': TextEditingController(),
      'note': TextEditingController(),
    },
  );

  final List<Map<String, TextEditingController>> _personnelRows = List.generate(
    _personnelRowCount,
    (_) => {
      'date': TextEditingController(),
      'operator': TextEditingController(),
      'start1': TextEditingController(),
      'stop1': TextEditingController(),
      'start2': TextEditingController(),
      'stop2': TextEditingController(),
      'total': TextEditingController(),
      'note': TextEditingController(),
    },
  );

  final _remarks = TextEditingController();
  final _contractorRepPrintedName = TextEditingController();
  final _incidentSupervisorPrintedName = TextEditingController();
  Uint8List? _contractorRepSignatureImage;
  Uint8List? _incidentSupervisorSignatureImage;

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStickyFields();
  }

  Future<void> _loadStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    _agreementNumber.text = prefs.getString(_kAgreementNumberKey) ?? '';
    _contractorAgencyName.text = prefs.getString(_kContractorAgencyNameKey) ?? '';
    _incidentName.text = prefs.getString(_kIncidentNameKey) ?? '';
    _incidentNumber.text = prefs.getString(_kIncidentNumberKey) ?? '';
    _financialCode.text = prefs.getString(_kFinancialCodeKey) ?? '';
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgreementNumberKey, _agreementNumber.text.trim());
    await prefs.setString(_kContractorAgencyNameKey, _contractorAgencyName.text.trim());
    await prefs.setString(_kIncidentNameKey, _incidentName.text.trim());
    await prefs.setString(_kIncidentNumberKey, _incidentNumber.text.trim());
    await prefs.setString(_kFinancialCodeKey, _financialCode.text.trim());
  }

  @override
  void dispose() {
    for (final c in [
      _agreementNumber, _contractorAgencyName, _resourceOrderNumber, _incidentName,
      _incidentNumber, _financialCode, _equipmentMakeModel, _equipmentType,
      _serialVinNumber, _licenseIdNumber, _remarks, _contractorRepPrintedName,
      _incidentSupervisorPrintedName,
    ]) {
      c.dispose();
    }
    for (final row in [..._equipmentRows, ..._personnelRows]) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  ShiftTicketData _compile() => ShiftTicketData(
        agreementNumber: _agreementNumber.text.trim(),
        contractorAgencyName: _contractorAgencyName.text.trim(),
        resourceOrderNumber: _resourceOrderNumber.text.trim(),
        incidentName: _incidentName.text.trim(),
        incidentNumber: _incidentNumber.text.trim(),
        financialCode: _financialCode.text.trim(),
        equipmentMakeModel: _equipmentMakeModel.text.trim(),
        equipmentType: _equipmentType.text.trim(),
        serialVinNumber: _serialVinNumber.text.trim(),
        licenseIdNumber: _licenseIdNumber.text.trim(),
        transportRetained: _transportRetained,
        mobilization: _mobilization,
        demobilization: _demobilization,
        appliesMiles: _appliesMiles,
        appliesHours: _appliesHours,
        equipmentRows: [
          for (final row in _equipmentRows)
            ShiftTicketEquipmentRow(
              date: row['date']!.text.trim(),
              start: row['start']!.text.trim(),
              stop: row['stop']!.text.trim(),
              total: row['total']!.text.trim(),
              quantity: row['quantity']!.text.trim(),
              type: row['type']!.text.trim(),
              note: row['note']!.text.trim(),
            ),
        ],
        personnelRows: [
          for (final row in _personnelRows)
            ShiftTicketPersonnelRow(
              date: row['date']!.text.trim(),
              operatorName: row['operator']!.text.trim(),
              start1: row['start1']!.text.trim(),
              stop1: row['stop1']!.text.trim(),
              start2: row['start2']!.text.trim(),
              stop2: row['stop2']!.text.trim(),
              total: row['total']!.text.trim(),
              note: row['note']!.text.trim(),
            ),
        ],
        remarks: _remarks.text.trim(),
        contractorRepPrintedName: _contractorRepPrintedName.text.trim(),
        contractorRepSignatureImage: _contractorRepSignatureImage,
        incidentSupervisorPrintedName: _incidentSupervisorPrintedName.text.trim(),
        incidentSupervisorSignatureImage: _incidentSupervisorSignatureImage,
      );

  String _filename() {
    String sanitize(String s) => s.trim().isEmpty
        ? 'UNK'
        : s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final now = DateTime.now();
    final yymmdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'ShiftTicket-${sanitize(_incidentName.text)}-${sanitize(_equipmentMakeModel.text)}-$yymmdd';
  }

  Future<void> _preview() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildShiftTicketPdf(_compile());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildShiftTicketPdf(_compile());
    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: '${_filename()}.pdf');
  }

  Future<void> _download() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveStickyFields();
    final bytes = await buildShiftTicketPdf(_compile());
    if (!mounted) return;
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Shift Ticket PDF',
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
    final data = _compile();
    final bytes = await buildShiftTicketPdf(data);
    final filename = '${_filename()}.pdf';
    if (!mounted) return;
    await showEmailFormDialog(
      context,
      pdfBytes: bytes,
      filename: filename,
      subject: 'Shift Ticket — ${_incidentName.text.trim().isEmpty ? 'ResQruck' : _incidentName.text.trim()}',
      onSent: (recipientEmail, subject) async {
        final prefs = await SharedPreferences.getInstance();
        final sentBy = prefs.getString('tac_callsign') ?? '';
        await recordAndUploadShiftTicket(
          pdfBytes: bytes,
          fileName: filename,
          data: data,
          recipientEmail: recipientEmail,
          subject: subject,
          sentBy: sentBy,
        );
      },
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
            _sectionLabel('AGREEMENT / RESOURCE'),
            _card('Agreement & Resource', Colors.indigo, [
              Row(children: [
                Expanded(child: _tf('Agreement Number', _agreementNumber)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Resource Order Number', _resourceOrderNumber)),
              ]),
              const SizedBox(height: 8),
              _tf('Contractor/Agency Name', _contractorAgencyName),
            ]),
            _card('Incident', Colors.deepPurple, [
              _tf('Incident Name', _incidentName),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Incident Number', _incidentNumber)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Financial Code', _financialCode)),
              ]),
            ]),
            _card('Equipment Details', Colors.teal, [
              Row(children: [
                Expanded(child: _tf('Equipment Make/Model', _equipmentMakeModel)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Equipment Type', _equipmentType)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Serial/VIN Number', _serialVinNumber)),
                const SizedBox(width: 8),
                Expanded(child: _tf('License/ID Number', _licenseIdNumber)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _switchChip('Transport Retained', _transportRetained, (v) => setState(() => _transportRetained = v)),
                _switchChip('Mobilization', _mobilization, (v) => setState(() => _mobilization = v)),
                _switchChip('Demobilization', _demobilization, (v) => setState(() => _demobilization = v)),
                _switchChip('Miles', _appliesMiles, (v) => setState(() => _appliesMiles = v)),
                _switchChip('Hours', _appliesHours, (v) => setState(() => _appliesHours = v)),
              ]),
            ]),
            _sectionLabel('EQUIPMENT LOG'),
            _card('Equipment', Colors.orange, [
              for (var i = 0; i < _equipmentRows.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                Text('Row ${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _tf('Date', _equipmentRows[i]['date']!)),
                  const SizedBox(width: 8),
                  // Not a time field: block 14 says these record miles OR
                  // hours (odometer/hour-meter reading), per the Miles/Hours
                  // toggle above -- unlike the Personnel table's Start/Stop.
                  Expanded(child: _tf('Start', _equipmentRows[i]['start']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Stop', _equipmentRows[i]['stop']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Total', _equipmentRows[i]['total']!)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tf('Quantity', _equipmentRows[i]['quantity']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Type', _equipmentRows[i]['type']!)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _tf('Note Travel/Other', _equipmentRows[i]['note']!)),
                ]),
              ],
            ]),
            _sectionLabel('PERSONNEL LOG'),
            _card('Personnel', Colors.brown, [
              for (var i = 0; i < _personnelRows.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                Text('Row ${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _tf('Date', _personnelRows[i]['date']!)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _tf('Operator Name (First & Last)', _personnelRows[i]['operator']!)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _timeField('Start', _personnelRows[i]['start1']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField('Stop', _personnelRows[i]['stop1']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField('Start', _personnelRows[i]['start2']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _timeField('Stop', _personnelRows[i]['stop2']!)),
                  const SizedBox(width: 8),
                  Expanded(child: _tf('Total', _personnelRows[i]['total']!)),
                ]),
                const SizedBox(height: 8),
                _tf('Note Travel/Other remarks', _personnelRows[i]['note']!),
              ],
            ]),
            _card('Remarks', Colors.blueGrey, [
              _tf('Equipment breakdown, operating issues, or other information', _remarks, maxLines: 4),
            ]),
            _card('Approvals', Colors.blueGrey, [
              _tf('Contractor/Agency Representative (Printed Name)', _contractorRepPrintedName),
              const SizedBox(height: 8),
              SignatureField(
                label: 'Contractor/Agency Representative (Signature)',
                signatureBytes: _contractorRepSignatureImage,
                onChanged: (bytes) => setState(() => _contractorRepSignatureImage = bytes),
              ),
              const SizedBox(height: 8),
              _tf('Incident Supervisor (Printed Name & Resource Order Number)', _incidentSupervisorPrintedName),
              const SizedBox(height: 8),
              SignatureField(
                label: 'Incident Supervisor (Signature)',
                signatureBytes: _incidentSupervisorSignatureImage,
                onChanged: (bytes) => setState(() => _incidentSupervisorSignatureImage = bytes),
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

  Widget _switchChip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
    );
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

  /// Start/Stop fields on the paper form are military time (block 11: "Use
  /// MILITARY TIME") -- digits only, capped at 4 (HHMM), with a hint showing
  /// the expected format.
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
