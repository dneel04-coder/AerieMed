import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Data ──────────────────────────────────────────────────────────────────────

class _RItem {
  final String text;
  final String key;
  const _RItem(this.text, this.key);
}

class _RSub {
  final String title;
  final List<_RItem> items;
  const _RSub(this.title, this.items);
}

class _RSection {
  final String title;
  final List<_RItem> items;
  final List<_RSub> subs;
  const _RSection(this.title, {this.items = const [], this.subs = const []});
}

const List<_RSection> _kSections = [
  _RSection('1 | CREDENTIALS & DOCUMENTATION', items: [
    _RItem('EMS license — current, home state', 's1_01'),
    _RItem('Medical director authorization / standing orders', 's1_02'),
    _RItem('NFPA 1006 rope rescue certification card (Technician or Operations level)', 's1_03'),
    _RItem('Wildland quals card (FFT1/FFT2, S-130/S-190, L-180)', 's1_04'),
    _RItem('RT-130 current year completion', 's1_05'),
    _RItem('ROHVA / OHV operator cert (if UTV qualified)', 's1_06'),
    _RItem('Vehicle extrication cert (Type I required / Type II recommended)', 's1_07'),
    _RItem('Pack test — Arduous (3 mi, 45 lb, 45 min)', 's1_08'),
    _RItem('ICS-100, ICS-200, IS-700 completion records', 's1_09'),
    _RItem('Government-issued photo ID', 's1_10'),
  ]),
  _RSection('2 | PERSONAL PROTECTIVE EQUIPMENT', items: [
    _RItem('Nomex shirt and pants (yellow)', 's2_01'),
    _RItem('Helmet with chinstrap (fire rated)', 's2_02'),
    _RItem('Leather gloves — fireline rated', 's2_03'),
    _RItem('Fire boots — 8" lace-up, Vibram sole', 's2_04'),
    _RItem('Fire shelter — in pouch, immediately accessible', 's2_05'),
    _RItem('Eye protection', 's2_06'),
    _RItem('Hearing protection', 's2_07'),
    _RItem('N95 / smoke respirator', 's2_08'),
  ]),
  _RSection('3 | PERSONAL RESCUE & TECHNICAL GEAR', items: [
    _RItem('Personal Class II or III harness (agency / AHJ approved)', 's3_01'),
    _RItem('Personal belay/rappel device (ATC, ATS, or equivalent)', 's3_02'),
    _RItem('Locking carabiners — 3 to 4 (personal set)', 's3_03'),
    _RItem('Prusik loops — 2 to 3 (eye-to-eye sewn preferred)', 's3_04'),
    _RItem('Personal anchor system (PAS) or 120 cm sling', 's3_05'),
    _RItem('Rescue-rated helmet (if required separately from fire helmet)', 's3_06'),
    _RItem('Technical rescue gloves', 's3_07'),
    _RItem('Knife / line cutter — accessible on harness or belt', 's3_08'),
  ]),
  _RSection('4 | INDIVIDUAL MEDICAL CARRY (by licensure)', subs: [
    _RSub('ALL PROVIDERS', [
      _RItem('Tourniquet — CAT or SOFTT-W, worn on body', 's4_01'),
      _RItem('Pressure dressing / Israeli bandage', 's4_02'),
      _RItem('Chest seals — vented x2', 's4_03'),
      _RItem('Nitrile gloves — multiple pairs', 's4_04'),
      _RItem('Trauma shears', 's4_05'),
      _RItem('SAM splint', 's4_06'),
      _RItem('Nasopharyngeal airway (NPA) with lube', 's4_07'),
      _RItem('Pulse oximeter', 's4_08'),
      _RItem('Penlight', 's4_09'),
      _RItem('CPR mask / pocket BVM', 's4_10'),
      _RItem('SALT / SOAP documentation cards or equivalent', 's4_11'),
    ]),
    _RSub('EMT AND ABOVE — add:', [
      _RItem('Blood glucose meter + strips', 's4_12'),
      _RItem('BVM — full size', 's4_13'),
      _RItem('Blood pressure cuff + stethoscope', 's4_14'),
      _RItem('OPA set (oropharyngeal airways)', 's4_15'),
    ]),
    _RSub('PARAMEDIC — add:', [
      _RItem('IV / IO start kit (personal pouch)', 's4_16'),
      _RItem('Drug box access key / authorization documents', 's4_17'),
      _RItem('Advanced airway adjuncts per medical director protocol', 's4_18'),
    ]),
  ]),
  _RSection('5 | COMMUNICATIONS & NAVIGATION', items: [
    _RItem('Portable radio — cloned to incident comms plan prior to departure', 's5_01'),
    _RItem('Spare radio battery (fully charged)', 's5_02'),
    _RItem('Cell phone — charged, incident numbers saved', 's5_03'),
    _RItem('Satellite communicator (Garmin inReach or equivalent) — recommended', 's5_04'),
    _RItem('GPS device or app with offline maps downloaded', 's5_05'),
    _RItem('Laminated incident map — obtain at check-in briefing', 's5_06'),
  ]),
  _RSection('6 | PERSONAL SUSTAINMENT (14–21 day deployment)', items: [
    _RItem('Line pack — packed for operational period', 's6_01'),
    _RItem('Water — minimum 3 L on person', 's6_02'),
    _RItem('Electrolyte packets (critical for heat ops)', 's6_03'),
    _RItem('Food — 24 to 72 hrs supply', 's6_04'),
    _RItem('Headlamp + extra batteries', 's6_05'),
    _RItem('Sleeping bag + sleeping pad (spike camp capable)', 's6_06'),
    _RItem('Personal hygiene kit', 's6_07'),
    _RItem('Prescription medications — 30-day supply minimum', 's6_08'),
    _RItem('Sunscreen / lip balm', 's6_09'),
    _RItem('Boot gaiters (terrain dependent)', 's6_10'),
  ]),
  _RSection('7 | ADMINISTRATIVE & LOGISTICS', items: [
    _RItem('Red card / resource order', 's7_01'),
    _RItem('Travel documents (if fly-in deployment)', 's7_02'),
    _RItem('Credit card for incidentals', 's7_03'),
    _RItem('Personal weight recorded for flight manifest', 's7_04'),
    _RItem('Emergency contact info filed with your organization', 's7_05'),
    _RItem('Blank ICS 214 (Unit Log) copies', 's7_06'),
    _RItem('Crew manifest info ready to provide', 's7_07'),
  ]),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class RemsChecklistScreen extends StatefulWidget {
  const RemsChecklistScreen({super.key});

  @override
  State<RemsChecklistScreen> createState() => _RemsChecklistScreenState();
}

class _RemsChecklistScreenState extends State<RemsChecklistScreen> {
  final _name = TextEditingController();
  final _emsLicense = TextEditingController();
  final _incidentName = TextEditingController();
  final _resourceOrder = TextEditingController();
  final _mobDate = TextEditingController();
  final _remsType = TextEditingController();
  final _dispatchCenter = TextEditingController();
  final _teamLeader = TextEditingController();
  final _signature = TextEditingController();
  final _sigDate = TextEditingController();
  final _tlInitials = TextEditingController();

  Map<String, bool> _checked = {};
  bool _loading = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _emsLicense.dispose();
    _incidentName.dispose();
    _resourceOrder.dispose();
    _mobDate.dispose();
    _remsType.dispose();
    _dispatchCenter.dispose();
    _teamLeader.dispose();
    _signature.dispose();
    _sigDate.dispose();
    _tlInitials.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final checked = <String, bool>{};
    for (final s in _kSections) {
      for (final item in s.items) {
        checked[item.key] = prefs.getBool('rems_${item.key}') ?? false;
      }
      for (final sub in s.subs) {
        for (final item in sub.items) {
          checked[item.key] = prefs.getBool('rems_${item.key}') ?? false;
        }
      }
    }
    setState(() {
      _name.text = prefs.getString('rems_name') ?? '';
      _emsLicense.text = prefs.getString('rems_ems') ?? '';
      _incidentName.text = prefs.getString('rems_incident') ?? '';
      _resourceOrder.text = prefs.getString('rems_resource') ?? '';
      _mobDate.text = prefs.getString('rems_mobdate') ?? '';
      _remsType.text = prefs.getString('rems_type') ?? '';
      _dispatchCenter.text = prefs.getString('rems_dispatch') ?? '';
      _teamLeader.text = prefs.getString('rems_tl') ?? '';
      _signature.text = prefs.getString('rems_sig') ?? '';
      _sigDate.text = prefs.getString('rems_sigdate') ?? '';
      _tlInitials.text = prefs.getString('rems_tlinit') ?? '';
      _checked = checked;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rems_name', _name.text);
    await prefs.setString('rems_ems', _emsLicense.text);
    await prefs.setString('rems_incident', _incidentName.text);
    await prefs.setString('rems_resource', _resourceOrder.text);
    await prefs.setString('rems_mobdate', _mobDate.text);
    await prefs.setString('rems_type', _remsType.text);
    await prefs.setString('rems_dispatch', _dispatchCenter.text);
    await prefs.setString('rems_tl', _teamLeader.text);
    await prefs.setString('rems_sig', _signature.text);
    await prefs.setString('rems_sigdate', _sigDate.text);
    await prefs.setString('rems_tlinit', _tlInitials.text);
    for (final entry in _checked.entries) {
      await prefs.setBool('rems_${entry.key}', entry.value);
    }
  }

  void _toggle(String key, bool? val) {
    setState(() => _checked[key] = val ?? false);
    _saveKey(key, val ?? false);
  }

  Future<void> _saveKey(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rems_$key', val);
  }

  Future<void> _generateAndShare() async {
    setState(() => _sharing = true);
    try {
      await _save();
      final bytes = await _buildPdf();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/rems_predeploy_checklist.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], subject: 'REMS Pre-Deployment Checklist'));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<List<int>> _buildPdf() async {
    final doc = pw.Document();
    final headerColor = PdfColor.fromHex('#0D47A1');
    final subColor = PdfColor.fromHex('#1565C0');
    final lightBlue = PdfColor.fromHex('#E3F2FD');
    final whiteSubtle = PdfColor.fromHex('#B3FFFFFF');

    pw.Widget infoRow(String label, String val) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 140,
                child: pw.Text(label,
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Expanded(
                child: pw.Container(
                    decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))),
                    child: pw.Text(val, style: const pw.TextStyle(fontSize: 8)))),
          ]),
        );

    pw.Widget checkRow(String text, bool checked) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5, horizontal: 4),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(
                width: 14,
                height: 14,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.8)),
                  child: checked
                      ? pw.Center(
                          child: pw.Text('✓',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromHex('#0D47A1'))))
                      : null,
                )),
            pw.SizedBox(width: 6),
            pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 8))),
          ]),
        );

    pw.Widget sectionHeader(String title) => pw.Container(
          color: headerColor,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Text(title,
              style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget subGroupHeader(String title) => pw.Container(
          color: subColor,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: pw.Text(title,
              style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold)),
        );

    List<pw.Widget> buildSection(_RSection s) {
      final widgets = <pw.Widget>[sectionHeader(s.title)];
      for (int i = 0; i < s.items.length; i++) {
        final item = s.items[i];
        widgets.add(pw.Container(
          color: i.isEven ? lightBlue : PdfColors.white,
          child: checkRow(item.text, _checked[item.key] ?? false),
        ));
      }
      for (final sub in s.subs) {
        widgets.add(subGroupHeader(sub.title));
        for (int i = 0; i < sub.items.length; i++) {
          final item = sub.items[i];
          widgets.add(pw.Container(
            color: i.isEven ? lightBlue : PdfColors.white,
            child: checkRow(item.text, _checked[item.key] ?? false),
          ));
        }
      }
      widgets.add(pw.SizedBox(height: 6));
      return widgets;
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => pw.Column(children: [
        pw.Container(
          color: headerColor,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('REMS Individual Pre-Deployment Checklist',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rescue EMS — Individual Gear & Credentials Verification',
                      style: pw.TextStyle(color: whiteSubtle, fontSize: 8)),
                ]),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(color: whiteSubtle, fontSize: 8)),
              ]),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
          child: pw.Column(children: [
            pw.Row(children: [
              pw.Expanded(child: infoRow('Name:', _name.text)),
              pw.SizedBox(width: 12),
              pw.Expanded(child: infoRow('EMS License #:', _emsLicense.text)),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(children: [
              pw.Expanded(child: infoRow('Incident Name:', _incidentName.text)),
              pw.SizedBox(width: 12),
              pw.Expanded(child: infoRow('Resource Order #:', _resourceOrder.text)),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(children: [
              pw.Expanded(child: infoRow('Mobilization Date:', _mobDate.text)),
              pw.SizedBox(width: 12),
              pw.Expanded(child: infoRow('REMS Type (I/II/III):', _remsType.text)),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(children: [
              pw.Expanded(child: infoRow('Dispatch Center:', _dispatchCenter.text)),
              pw.SizedBox(width: 12),
              pw.Expanded(child: infoRow('Team Leader:', _teamLeader.text)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 8),
      ]),
      footer: (ctx) => pw.Column(children: [
        pw.Divider(),
        pw.Row(children: [
          pw.Expanded(child: infoRow('Member Signature:', _signature.text)),
          pw.SizedBox(width: 12),
          pw.SizedBox(width: 100, child: infoRow('Date:', _sigDate.text)),
          pw.SizedBox(width: 12),
          pw.SizedBox(width: 120, child: infoRow('TL Initials:', _tlInitials.text)),
        ]),
        pw.SizedBox(height: 4),
        pw.Text(
            'All items must be verified prior to departure. Incomplete checklists require supervisor sign-off.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ]),
      build: (ctx) => [
        for (final s in _kSections) ...buildSection(s),
      ],
    ));

    return await doc.save();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-Deploy Checklist'),
        actions: [
          if (_sharing)
            const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Generate & Share PDF',
              onPressed: _generateAndShare,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _buildHeader(cs),
          const SizedBox(height: 16),
          for (final section in _kSections) _buildSection(section, cs),
          _buildSignature(cs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sharing ? null : _generateAndShare,
        icon: const Icon(Icons.share),
        label: const Text('Share PDF'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Deployment Information',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                  fontSize: 14)),
          const SizedBox(height: 12),
          _field('Name', _name, 'Full legal name'),
          _field('EMS License #', _emsLicense, 'License number'),
          _field('Incident Name', _incidentName, 'Fire / incident name'),
          _field('Resource Order #', _resourceOrder, 'Order number'),
          _field('Mobilization Date', _mobDate, 'MM/DD/YYYY'),
          _field('REMS Type', _remsType, 'Type I, II, or III'),
          _field('Dispatch Center', _dispatchCenter, 'Dispatch center name'),
          _field('Team Leader', _teamLeader, 'Team leader name'),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (_) {},
      ),
    );
  }

  Widget _buildSection(_RSection section, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(color: Color(0xFF0D47A1)),
          child: Text(section.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
        for (int i = 0; i < section.items.length; i++)
          _checkTile(section.items[i], i.isEven),
        for (final sub in section.subs) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(color: Color(0xFF1565C0)),
            child: Text(sub.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          for (int i = 0; i < sub.items.length; i++)
            _checkTile(sub.items[i], i.isEven),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _checkTile(_RItem item, bool shaded) {
    final checked = _checked[item.key] ?? false;
    return InkWell(
      onTap: () => _toggle(item.key, !checked),
      child: Container(
        color: shaded ? const Color(0xFFE3F2FD) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: CheckboxListTile(
          value: checked,
          onChanged: (v) => _toggle(item.key, v),
          title: Text(item.text, style: const TextStyle(fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF0D47A1),
        ),
      ),
    );
  }

  Widget _buildSignature(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Certification',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                  fontSize: 14)),
          const SizedBox(height: 4),
          const Text(
              'I certify that all applicable items above have been verified and are present and serviceable for deployment.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          _field('Member Signature (type name)', _signature, 'Type full name as signature'),
          _field('Date', _sigDate, 'MM/DD/YYYY'),
          _field('Team Leader Initials', _tlInitials, 'TL initials'),
        ]),
      ),
    );
  }
}
