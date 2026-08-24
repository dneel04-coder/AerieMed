import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'ics206wf_pdf.dart';
import 'form_email_service.dart';

enum Ics206WfSeverity { none, red, yellow, green }

class Ics206WfPatient {
  final TextEditingController assessment = TextEditingController();
  final TextEditingController treatment = TextEditingController();
  void dispose() {
    assessment.dispose();
    treatment.dispose();
  }
}

/// Plain data snapshot compiled on demand for PDF generation, mirroring
/// PatientReport/CrewSwapData's shape.
class Ics206WfData {
  final Ics206WfSeverity severity;
  final String natureOfInjury, evacuationRequest, patientLocation, incidentName, onSceneIc, patientCare;
  final List<({String assessment, String treatment})> patients;
  final String evacLocation, patientEta, helispotHazards;
  final String additionalResources;
  final String commandChannel, commandRx, commandRxTone, commandTx, commandTxTone;
  final String airGrndChannel, airGrndRx, airGrndRxTone, airGrndTx, airGrndTxTone;
  final String tacticalChannel, tacticalRx, tacticalRxTone, tacticalTx, tacticalTxTone;
  final String contingency;
  final String additionalInfo;

  const Ics206WfData({
    required this.severity,
    required this.natureOfInjury,
    required this.evacuationRequest,
    required this.patientLocation,
    required this.incidentName,
    required this.onSceneIc,
    required this.patientCare,
    required this.patients,
    required this.evacLocation,
    required this.patientEta,
    required this.helispotHazards,
    required this.additionalResources,
    required this.commandChannel,
    required this.commandRx,
    required this.commandRxTone,
    required this.commandTx,
    required this.commandTxTone,
    required this.airGrndChannel,
    required this.airGrndRx,
    required this.airGrndRxTone,
    required this.airGrndTx,
    required this.airGrndTxTone,
    required this.tacticalChannel,
    required this.tacticalRx,
    required this.tacticalRxTone,
    required this.tacticalTx,
    required this.tacticalTxTone,
    required this.contingency,
    required this.additionalInfo,
  });
}

/// 8-Line/206WF Medical Incident Report -- reference/fillable checklist for
/// calling in a medical emergency or resource request over radio. Fields
/// mirror ics206wf_field_manifest.json exactly (the user-supplied reference)
/// rather than anything reconstructed from memory, since getting wildland
/// fire medical radio terminology wrong has real consequences.
class Ics206WfFormScreen extends StatefulWidget {
  const Ics206WfFormScreen({super.key});

  @override
  State<Ics206WfFormScreen> createState() => _Ics206WfFormScreenState();
}

class _Ics206WfFormScreenState extends State<Ics206WfFormScreen> {
  Ics206WfSeverity _severity = Ics206WfSeverity.none;

  final _natureOfInjury = TextEditingController();
  final _evacuationRequest = TextEditingController();
  final _patientLocation = TextEditingController();
  final _incidentName = TextEditingController();
  final _onSceneIc = TextEditingController();
  final _patientCare = TextEditingController();

  final List<Ics206WfPatient> _patients = [Ics206WfPatient()];

  final _evacLocation = TextEditingController();
  final _patientEta = TextEditingController();
  final _helispotHazards = TextEditingController();

  final _additionalResources = TextEditingController();

  final _commandChannel = TextEditingController();
  final _commandRx = TextEditingController();
  final _commandRxTone = TextEditingController();
  final _commandTx = TextEditingController();
  final _commandTxTone = TextEditingController();
  final _airGrndChannel = TextEditingController();
  final _airGrndRx = TextEditingController();
  final _airGrndRxTone = TextEditingController();
  final _airGrndTx = TextEditingController();
  final _airGrndTxTone = TextEditingController();
  final _tacticalChannel = TextEditingController();
  final _tacticalRx = TextEditingController();
  final _tacticalRxTone = TextEditingController();
  final _tacticalTx = TextEditingController();
  final _tacticalTxTone = TextEditingController();

  final _contingency = TextEditingController();
  final _additionalInfo = TextEditingController();

  bool _showScript = false;

  @override
  void dispose() {
    for (final p in _patients) {
      p.dispose();
    }
    for (final c in [
      _natureOfInjury, _evacuationRequest, _patientLocation, _incidentName, _onSceneIc, _patientCare,
      _evacLocation, _patientEta, _helispotHazards, _additionalResources,
      _commandChannel, _commandRx, _commandRxTone, _commandTx, _commandTxTone,
      _airGrndChannel, _airGrndRx, _airGrndRxTone, _airGrndTx, _airGrndTxTone,
      _tacticalChannel, _tacticalRx, _tacticalRxTone, _tacticalTx, _tacticalTxTone,
      _contingency, _additionalInfo,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Ics206WfData _compile() => Ics206WfData(
        severity: _severity,
        natureOfInjury: _natureOfInjury.text.trim(),
        evacuationRequest: _evacuationRequest.text.trim(),
        patientLocation: _patientLocation.text.trim(),
        incidentName: _incidentName.text.trim(),
        onSceneIc: _onSceneIc.text.trim(),
        patientCare: _patientCare.text.trim(),
        patients: _patients
            .map((p) => (assessment: p.assessment.text.trim(), treatment: p.treatment.text.trim()))
            .where((p) => p.assessment.isNotEmpty || p.treatment.isNotEmpty)
            .toList(),
        evacLocation: _evacLocation.text.trim(),
        patientEta: _patientEta.text.trim(),
        helispotHazards: _helispotHazards.text.trim(),
        additionalResources: _additionalResources.text.trim(),
        commandChannel: _commandChannel.text.trim(),
        commandRx: _commandRx.text.trim(),
        commandRxTone: _commandRxTone.text.trim(),
        commandTx: _commandTx.text.trim(),
        commandTxTone: _commandTxTone.text.trim(),
        airGrndChannel: _airGrndChannel.text.trim(),
        airGrndRx: _airGrndRx.text.trim(),
        airGrndRxTone: _airGrndRxTone.text.trim(),
        airGrndTx: _airGrndTx.text.trim(),
        airGrndTxTone: _airGrndTxTone.text.trim(),
        tacticalChannel: _tacticalChannel.text.trim(),
        tacticalRx: _tacticalRx.text.trim(),
        tacticalRxTone: _tacticalRxTone.text.trim(),
        tacticalTx: _tacticalTx.text.trim(),
        tacticalTxTone: _tacticalTxTone.text.trim(),
        contingency: _contingency.text.trim(),
        additionalInfo: _additionalInfo.text.trim(),
      );

  String _filename() {
    String sanitize(String s) => s.trim().isEmpty
        ? 'UNK'
        : s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final now = DateTime.now();
    final yymmdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'ICS206WF-${sanitize(_incidentName.text)}-$yymmdd';
  }

  Future<void> _preview() async {
    final bytes = await buildIcs206WfPdf(_compile());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    final bytes = await buildIcs206WfPdf(_compile());
    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: '${_filename()}.pdf');
  }

  Future<void> _email() async {
    final bytes = await buildIcs206WfPdf(_compile());
    if (!mounted) return;
    await showEmailFormDialog(
      context,
      pdfBytes: bytes,
      filename: '${_filename()}.pdf',
      subject: '8-Line/206WF Medical Incident Report — ${_incidentName.text.trim().isEmpty ? 'ResQruck' : _incidentName.text.trim()}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('8-Line/206WF Medical Report'),
        actions: [
          IconButton(
            icon: Icon(_showScript ? Icons.menu_book : Icons.menu_book_outlined),
            tooltip: 'Radio script reference',
            onPressed: () => setState(() => _showScript = !_showScript),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_showScript) _buildScriptCard(),

              _sectionLabel('SEVERITY OF EMERGENCY / TRANSPORT PRIORITY'),
              _card('Severity', Colors.red, [
                _severityOption(Ics206WfSeverity.red, 'RED / PRIORITY 1',
                    'Life or limb threatening injury or illness. Evacuation need is IMMEDIATE.', Colors.red),
                const SizedBox(height: 8),
                _severityOption(Ics206WfSeverity.yellow, 'YELLOW / PRIORITY 2',
                    'Serious injury or illness. Evacuation may be DELAYED if necessary.', Colors.orange),
                const SizedBox(height: 8),
                _severityOption(Ics206WfSeverity.green, 'GREEN / PRIORITY 3',
                    'Minor injury or illness. Non-emergency transport.', Colors.green),
              ]),

              _sectionLabel('INCIDENT DETAILS'),
              _card('Incident Details', Colors.indigo, [
                _tf('Nature of Injury or Illness & Mechanism of Injury', _natureOfInjury,
                    maxLines: 3, hint: 'Ex: Unconscious, Struck by Falling Tree'),
                const SizedBox(height: 8),
                _tf('Evacuation Request', _evacuationRequest,
                    maxLines: 2, hint: 'Air Ambulance / Short Haul/Hoist / Ground Ambulance / Other'),
                const SizedBox(height: 8),
                _tf('Patient Location', _patientLocation, hint: 'Descriptive Location & Lat./Long. (WGS84)'),
                const SizedBox(height: 8),
                _tf('Incident Name', _incidentName, hint: 'Geographic Name + Medical (Ex: Trout Meadow Medical)'),
                const SizedBox(height: 8),
                _tf('On-Scene Incident Commander', _onSceneIc, hint: 'Ex: TFLD Jones'),
                const SizedBox(height: 8),
                _tf('Patient Care', _patientCare, hint: 'Name of Care Provider (Ex: EMT Smith)'),
              ]),

              _sectionLabel('INITIAL PATIENT ASSESSMENT'),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Complete for each patient (start with the most severe). See IRPG Page 106.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
              for (int i = 0; i < _patients.length; i++) _buildPatientCard(i),
              OutlinedButton.icon(
                onPressed: () => setState(() => _patients.add(Ics206WfPatient())),
                icon: const Icon(Icons.add),
                label: const Text('Add Patient'),
              ),

              _sectionLabel('EVACUATION PLAN'),
              _card('Evacuation Plan', Colors.teal, [
                _tf('Evacuation Location (if different)', _evacLocation,
                    maxLines: 2, hint: 'Drop point, intersection, etc. or Lat./Long.'),
                const SizedBox(height: 8),
                _tf("Patient's ETA to Evacuation Location", _patientEta),
                const SizedBox(height: 8),
                _tf('Helispot / Extraction Site Size and Hazards', _helispotHazards, maxLines: 2),
              ]),

              _sectionLabel('ADDITIONAL RESOURCES / EQUIPMENT NEEDS'),
              _card('Additional Resources', Colors.purple, [
                _tf('Additional Resources / Equipment Needs', _additionalResources,
                    maxLines: 2,
                    hint: 'Paramedic/EMT, crews, immobilization devices, AED, oxygen, trauma bag, IV/fluid(s), splints, rope rescue, wheeled litter, HAZMAT, extrication'),
              ]),

              _sectionLabel('COMMUNICATIONS'),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Identify State Air/Ground EMS Frequencies and Hospital Contacts as applicable.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
              _commsCard(),

              _sectionLabel('CONTINGENCY'),
              _card('Contingency', Colors.brown, [
                _tf('Contingency', _contingency,
                    maxLines: 2,
                    hint: 'If primary options fail, what actions can be implemented in conjunction with primary evacuation method?'),
              ]),

              _sectionLabel('ADDITIONAL INFORMATION'),
              _card('Additional Information', Colors.blueGrey, [
                _tf('Additional Information', _additionalInfo, maxLines: 2, hint: 'Updates/Changes, etc.'),
              ]),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Reminder: Confirm ETAs of resources ordered. Act according to your level of training. '
                  'Be Alert. Keep Calm. Think Clearly. Act Decisively.',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ),
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
      ]),
    );
  }

  Widget _buildScriptCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('RADIO PROTOCOL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 10),
        const Text('1. Contact Communications / Dispatch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const Text('Verify correct frequency prior to starting report.', style: TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
        const Text('"Communications, Div. Alpha. Stand-by for Emergency Traffic."',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
        const SizedBox(height: 10),
        const Text('2. Incident Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const Text('Provide incident summary (including number of patients) and command structure.',
            style: TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
        const Text(
          '"Communications, I have a Red priority patient, unconscious, struck by a falling tree. '
          'Requesting air ambulance to Forest Road 1 at (Lat./Long.) This will be the Trout Meadow '
          'Medical, IC is TFLD Jones. EMT Smith is providing medical care."',
          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }

  Widget _severityOption(Ics206WfSeverity value, String label, String description, Color color) {
    final selected = _severity == value;
    return InkWell(
      onTap: () => setState(() => _severity = selected ? Ics206WfSeverity.none : value),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : null,
          border: Border.all(color: selected ? color : Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              Text(description, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildPatientCard(int index) {
    final p = _patients[index];
    return _card('Patient ${index + 1}', Colors.deepOrange, [
      _tf('Patient Assessment', p.assessment, maxLines: 3),
      const SizedBox(height: 8),
      _tf('Treatment', p.treatment, maxLines: 3),
      if (_patients.length > 1) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() {
              p.dispose();
              _patients.removeAt(index);
            }),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Remove'),
          ),
        ),
      ],
    ]);
  }

  Widget _commsCard() {
    Widget row(String label, TextEditingController channel, TextEditingController rx,
        TextEditingController rxTone, TextEditingController tx, TextEditingController txTone) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 4),
          _tf('Channel Name/Number', channel),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _tf('Receive (RX)', rx)),
            const SizedBox(width: 6),
            Expanded(child: _tf('RX Tone/NAC', rxTone)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _tf('Transmit (TX)', tx)),
            const SizedBox(width: 6),
            Expanded(child: _tf('TX Tone/NAC', txTone)),
          ]),
        ]),
      );
    }

    return _card('Communications', Colors.blue, [
      row('COMMAND', _commandChannel, _commandRx, _commandRxTone, _commandTx, _commandTxTone),
      row('AIR-TO-GRND', _airGrndChannel, _airGrndRx, _airGrndRxTone, _airGrndTx, _airGrndTxTone),
      row('TACTICAL', _tacticalChannel, _tacticalRx, _tacticalRxTone, _tacticalTx, _tacticalTxTone),
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

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }
}
