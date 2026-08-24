import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crew_swap_pdf.dart';
import 'form_email_service.dart';

enum CrewSwapSectionKind { crewSwap, extensionRnr }

/// Plain data snapshot of the form, compiled on demand for PDF generation --
/// mirrors PatientReport's shape (a model class separate from the widget
/// holding the live TextEditingControllers).
class CrewSwapData {
  final String incidentName, currentDivision, resourceNumber, resourceNameInIap, resourceType;
  final CrewSwapSectionKind section;
  // Section A
  final String oldOperatorName, oldOperatorPhone, oldPositionOnEquipment, lastWorkDay;
  final bool returning;
  final String returnDate;
  final String newOperatorNamesQuals, namePrimaryOnEquipment, primaryPhone, firstWorkDay, numberOfDays;
  // Section B
  final String extName, extPhone, extPosition, justification;
  final bool rnrAndReturn;
  final String rnrDates, rnrReturnDate;
  final bool sevenDayExtension;
  final String newLastWorkDay;
  // Approvals
  final String homeUnitSupervisor, homeUnitSupervisorDate;
  final String divisionSupervisorApproval, divisionSupervisorDate;
  final String opsSectionChiefApproval, opsSectionChiefDate;

  const CrewSwapData({
    required this.incidentName,
    required this.currentDivision,
    required this.resourceNumber,
    required this.resourceNameInIap,
    required this.resourceType,
    required this.section,
    required this.oldOperatorName,
    required this.oldOperatorPhone,
    required this.oldPositionOnEquipment,
    required this.lastWorkDay,
    required this.returning,
    required this.returnDate,
    required this.newOperatorNamesQuals,
    required this.namePrimaryOnEquipment,
    required this.primaryPhone,
    required this.firstWorkDay,
    required this.numberOfDays,
    required this.extName,
    required this.extPhone,
    required this.extPosition,
    required this.justification,
    required this.rnrAndReturn,
    required this.rnrDates,
    required this.rnrReturnDate,
    required this.sevenDayExtension,
    required this.newLastWorkDay,
    required this.homeUnitSupervisor,
    required this.homeUnitSupervisorDate,
    required this.divisionSupervisorApproval,
    required this.divisionSupervisorDate,
    required this.opsSectionChiefApproval,
    required this.opsSectionChiefDate,
  });
}

const _kIncidentNameKey = 'crew_swap_incident_name';
const _kCurrentDivisionKey = 'crew_swap_current_division';
const _kResourceNumberKey = 'crew_swap_resource_number';
const _kResourceNameKey = 'crew_swap_resource_name';
const _kResourceTypeKey = 'crew_swap_resource_type';

/// The Crew Swap form -- embedded directly in the Team section's tab (not
/// pushed as a separate screen) so it's always one tap away, per this being
/// "used often" and needing to stay "readily available."
class CrewSwapFormScreen extends StatefulWidget {
  const CrewSwapFormScreen({super.key});

  @override
  State<CrewSwapFormScreen> createState() => _CrewSwapFormScreenState();
}

class _CrewSwapFormScreenState extends State<CrewSwapFormScreen> {
  final _incidentName = TextEditingController();
  final _currentDivision = TextEditingController();
  final _resourceNumber = TextEditingController();
  final _resourceNameInIap = TextEditingController();
  final _resourceType = TextEditingController();

  CrewSwapSectionKind _section = CrewSwapSectionKind.crewSwap;

  // Section A
  final _oldOperatorName = TextEditingController();
  final _oldOperatorPhone = TextEditingController();
  final _oldPositionOnEquipment = TextEditingController();
  final _lastWorkDay = TextEditingController();
  bool _returning = false;
  final _returnDate = TextEditingController();
  final _newOperatorNamesQuals = TextEditingController();
  final _namePrimaryOnEquipment = TextEditingController();
  final _primaryPhone = TextEditingController();
  final _firstWorkDay = TextEditingController();
  final _numberOfDays = TextEditingController();

  // Section B
  final _extName = TextEditingController();
  final _extPhone = TextEditingController();
  final _extPosition = TextEditingController();
  final _justification = TextEditingController();
  bool _rnrAndReturn = false;
  final _rnrDates = TextEditingController();
  final _rnrReturnDate = TextEditingController();
  bool _sevenDayExtension = false;
  final _newLastWorkDay = TextEditingController();

  // Approvals
  final _homeUnitSupervisor = TextEditingController();
  final _homeUnitSupervisorDate = TextEditingController();
  final _divisionSupervisorApproval = TextEditingController();
  final _divisionSupervisorDate = TextEditingController();
  final _opsSectionChiefApproval = TextEditingController();
  final _opsSectionChiefDate = TextEditingController();

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStickyFields();
  }

  Future<void> _loadStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    _incidentName.text = prefs.getString(_kIncidentNameKey) ?? '';
    _currentDivision.text = prefs.getString(_kCurrentDivisionKey) ?? '';
    _resourceNumber.text = prefs.getString(_kResourceNumberKey) ?? '';
    _resourceNameInIap.text = prefs.getString(_kResourceNameKey) ?? '';
    _resourceType.text = prefs.getString(_kResourceTypeKey) ?? '';
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveStickyFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIncidentNameKey, _incidentName.text.trim());
    await prefs.setString(_kCurrentDivisionKey, _currentDivision.text.trim());
    await prefs.setString(_kResourceNumberKey, _resourceNumber.text.trim());
    await prefs.setString(_kResourceNameKey, _resourceNameInIap.text.trim());
    await prefs.setString(_kResourceTypeKey, _resourceType.text.trim());
  }

  @override
  void dispose() {
    for (final c in [
      _incidentName, _currentDivision, _resourceNumber, _resourceNameInIap, _resourceType,
      _oldOperatorName, _oldOperatorPhone, _oldPositionOnEquipment, _lastWorkDay, _returnDate,
      _newOperatorNamesQuals, _namePrimaryOnEquipment, _primaryPhone, _firstWorkDay, _numberOfDays,
      _extName, _extPhone, _extPosition, _justification, _rnrDates, _rnrReturnDate, _newLastWorkDay,
      _homeUnitSupervisor, _homeUnitSupervisorDate, _divisionSupervisorApproval,
      _divisionSupervisorDate, _opsSectionChiefApproval, _opsSectionChiefDate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  CrewSwapData _compile() => CrewSwapData(
        incidentName: _incidentName.text.trim(),
        currentDivision: _currentDivision.text.trim(),
        resourceNumber: _resourceNumber.text.trim(),
        resourceNameInIap: _resourceNameInIap.text.trim(),
        resourceType: _resourceType.text.trim(),
        section: _section,
        oldOperatorName: _oldOperatorName.text.trim(),
        oldOperatorPhone: _oldOperatorPhone.text.trim(),
        oldPositionOnEquipment: _oldPositionOnEquipment.text.trim(),
        lastWorkDay: _lastWorkDay.text.trim(),
        returning: _returning,
        returnDate: _returnDate.text.trim(),
        newOperatorNamesQuals: _newOperatorNamesQuals.text.trim(),
        namePrimaryOnEquipment: _namePrimaryOnEquipment.text.trim(),
        primaryPhone: _primaryPhone.text.trim(),
        firstWorkDay: _firstWorkDay.text.trim(),
        numberOfDays: _numberOfDays.text.trim(),
        extName: _extName.text.trim(),
        extPhone: _extPhone.text.trim(),
        extPosition: _extPosition.text.trim(),
        justification: _justification.text.trim(),
        rnrAndReturn: _rnrAndReturn,
        rnrDates: _rnrDates.text.trim(),
        rnrReturnDate: _rnrReturnDate.text.trim(),
        sevenDayExtension: _sevenDayExtension,
        newLastWorkDay: _newLastWorkDay.text.trim(),
        homeUnitSupervisor: _homeUnitSupervisor.text.trim(),
        homeUnitSupervisorDate: _homeUnitSupervisorDate.text.trim(),
        divisionSupervisorApproval: _divisionSupervisorApproval.text.trim(),
        divisionSupervisorDate: _divisionSupervisorDate.text.trim(),
        opsSectionChiefApproval: _opsSectionChiefApproval.text.trim(),
        opsSectionChiefDate: _opsSectionChiefDate.text.trim(),
      );

  String _filename() {
    String sanitize(String s) => s.trim().isEmpty
        ? 'UNK'
        : s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final now = DateTime.now();
    final yymmdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'CrewSwap-${sanitize(_incidentName.text)}-${sanitize(_resourceNumber.text)}-$yymmdd';
  }

  Future<void> _preview() async {
    await _saveStickyFields();
    final bytes = await buildCrewSwapPdf(_compile());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    await _saveStickyFields();
    final bytes = await buildCrewSwapPdf(_compile());
    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: '${_filename()}.pdf');
  }

  Future<void> _email() async {
    await _saveStickyFields();
    final bytes = await buildCrewSwapPdf(_compile());
    if (!mounted) return;
    await showEmailFormDialog(
      context,
      pdfBytes: bytes,
      filename: '${_filename()}.pdf',
      subject: 'Crew Change Form — ${_incidentName.text.trim().isEmpty ? 'ResQruck' : _incidentName.text.trim()}',
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
            _sectionLabel('INCIDENT / RESOURCE'),
            _card('Incident Details', Colors.indigo, [
              _tf('Incident Name', _incidentName),
              const SizedBox(height: 8),
              _tf('Current Division of Resource', _currentDivision),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _tf('Resource #', _resourceNumber)),
                const SizedBox(width: 8),
                Expanded(child: _tf('Resource Type', _resourceType)),
              ]),
              const SizedBox(height: 8),
              _tf('Resource Name in IAP', _resourceNameInIap),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<CrewSwapSectionKind>(
              segments: const [
                ButtonSegment(value: CrewSwapSectionKind.crewSwap, label: Text('Crew Swap'), icon: Icon(Icons.swap_horiz)),
                ButtonSegment(value: CrewSwapSectionKind.extensionRnr, label: Text('Extension / R&R'), icon: Icon(Icons.event_repeat)),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
            ),
            const SizedBox(height: 16),
            if (_section == CrewSwapSectionKind.crewSwap) _buildCrewSwapSection() else _buildExtensionSection(),
            const SizedBox(height: 8),
            _card('Approvals', Colors.blueGrey, [
              _tfWithDate('Home Unit Supervisor', _homeUnitSupervisor, _homeUnitSupervisorDate),
              const SizedBox(height: 8),
              _tfWithDate('Division Supervisor Approval', _divisionSupervisorApproval, _divisionSupervisorDate),
              const SizedBox(height: 8),
              _tfWithDate('Operations Section Chief Approval', _opsSectionChiefApproval, _opsSectionChiefDate),
            ]),
          ]),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
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
        ),
      ),
    ]);
  }

  Widget _buildCrewSwapSection() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: _card('Old Operator', Colors.deepOrange, [
          _tf('Old Operator Name', _oldOperatorName),
          const SizedBox(height: 8),
          _tf('Phone', _oldOperatorPhone),
          const SizedBox(height: 8),
          _tf('Position on Equipment', _oldPositionOnEquipment),
          const SizedBox(height: 8),
          _tf('Last Work Day', _lastWorkDay),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Returning:'),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('No'), selected: !_returning, onSelected: (_) => setState(() => _returning = false)),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('Yes'), selected: _returning, onSelected: (_) => setState(() => _returning = true)),
          ]),
          if (_returning) ...[
            const SizedBox(height: 8),
            _tf('Return Date', _returnDate),
            const SizedBox(height: 6),
            const Text('If Yes, also complete the Extension / R&R section.',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
          ],
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _card('New Operator / Crew', Colors.teal, [
          _tf('New Operator/Crew Names and Quals', _newOperatorNamesQuals, maxLines: 3),
          const SizedBox(height: 8),
          _tf('Name of Primary on Equipment', _namePrimaryOnEquipment),
          const SizedBox(height: 8),
          _tf('Primary Phone', _primaryPhone),
          const SizedBox(height: 8),
          _tf('First Work Day', _firstWorkDay),
          const SizedBox(height: 8),
          _tf('Number of Days', _numberOfDays),
        ]),
      ),
    ]);
  }

  Widget _buildExtensionSection() {
    return _card('Operator/Crew/Equipment Extension', Colors.purple, [
      _tf('Name', _extName),
      const SizedBox(height: 8),
      _tf('Phone', _extPhone),
      const SizedBox(height: 8),
      _tf('Position on Equipment', _extPosition),
      const SizedBox(height: 8),
      _tf('Justification for Extension', _justification, maxLines: 3),
      const SizedBox(height: 12),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('R&R and Return'),
        value: _rnrAndReturn,
        onChanged: (v) => setState(() => _rnrAndReturn = v ?? false),
      ),
      if (_rnrAndReturn)
        Row(children: [
          Expanded(child: _tf('Dates of R&R', _rnrDates)),
          const SizedBox(width: 8),
          Expanded(child: _tf('Return Date', _rnrReturnDate)),
        ]),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('7 Day Extension'),
        value: _sevenDayExtension,
        onChanged: (v) => setState(() => _sevenDayExtension = v ?? false),
      ),
      if (_sevenDayExtension) _tf('New Last Work Day', _newLastWorkDay),
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
        padding: const EdgeInsets.only(bottom: 6),
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

  Widget _tfWithDate(String label, TextEditingController nameCtrl, TextEditingController dateCtrl) {
    return Row(children: [
      Expanded(flex: 2, child: _tf(label, nameCtrl)),
      const SizedBox(width: 8),
      Expanded(child: _tf('Date', dateCtrl)),
    ]);
  }
}
