import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'crew_swap_form.dart' show CrewSwapData;

// Matches the approved CIMT 2 Crew Change Form exactly: plain black/white,
// boxed sections, fill-in-the-blank lines -- not a generic label/value
// table. Both Section A and Section B always render (blank if unused),
// same as the paper form.

final _sTitle = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
final _sSubtitle = pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic);
final _sSectionNote = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
final _sInstruction = pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic);
final _sBoxHeader = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
const _sBody = pw.TextStyle(fontSize: 9);
final _sBodyBold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
const _sSmall = pw.TextStyle(fontSize: 8);
final _sSmallItalic = pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic);

Future<Uint8List> buildCrewSwapPdf(CrewSwapData f) async {
  final doc = pw.Document(title: 'CIMT 2 Crew Change Form', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      footer: (ctx) => _pageFooter(ctx),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

pw.Widget _pageFooter(pw.Context ctx) => pw.Row(children: [
      pw.Text('V.2 7/1/2026', style: _sSmall),
      pw.Spacer(),
      _fillLine('Date Entered:', '', width: 140),
    ]);

List<pw.Widget> _buildContent(CrewSwapData f) {
  return [
    pw.Center(child: pw.Text('CIMT 2 Crew Change Form', style: _sTitle)),
    pw.SizedBox(height: 3),
    pw.Center(
        child: pw.Text('All crews and equipment are responsible for maintaining proper work/rest ratio',
            style: _sSubtitle)),
    pw.SizedBox(height: 10),

    pw.Row(children: [
      pw.Expanded(flex: 3, child: _fillLine('Incident Name:', f.incidentName)),
      pw.SizedBox(width: 12),
      pw.Expanded(flex: 3, child: _fillLine('Current Division of Resource:', f.currentDivision)),
    ]),
    pw.SizedBox(height: 6),
    pw.Row(children: [
      pw.Expanded(flex: 2, child: _fillLine('Resource #:', f.resourceNumber)),
      pw.SizedBox(width: 12),
      pw.Expanded(flex: 3, child: _fillLine('Resource Name in IAP:', f.resourceNameInIap)),
      pw.SizedBox(width: 12),
      pw.Expanded(flex: 2, child: _fillLine('Resource Type:', f.resourceType)),
    ]),
    pw.SizedBox(height: 10),

    pw.Center(child: pw.Text('Section A - CREW/OPERATOR SWAP ONLY', style: _sSectionNote)),
    pw.Center(child: pw.Text('Section B - EXTENSION, R&R AND RETURN', style: _sSectionNote)),
    pw.SizedBox(height: 6),

    pw.Text('Section A - CREW SWAP ONLY - Complete for crew swap. For Extension R&R, complete section B.',
        style: _sInstruction),
    pw.SizedBox(height: 4),
    _crewSwapBox(f),
    pw.SizedBox(height: 10),

    pw.Text('Section B - EXTENSION/R&R - Complete for 7-day extension or R&R only.', style: _sInstruction),
    pw.SizedBox(height: 4),
    _extensionBox(f),
    pw.SizedBox(height: 12),

    _fillLine('Home Unit Supervisor (if required):', f.homeUnitSupervisor, trailing: _fillLine('Date:', f.homeUnitSupervisorDate, width: 90)),
    pw.SizedBox(height: 8),
    _fillLine('Division Supervisor Approval:', f.divisionSupervisorApproval, trailing: _fillLine('Date:', f.divisionSupervisorDate, width: 90)),
    pw.SizedBox(height: 8),
    _fillLine('Operations Section Chief Approval:', f.opsSectionChiefApproval, trailing: _fillLine('Date:', f.opsSectionChiefDate, width: 90)),
  ];
}

/// "Label: [underlined value or blank]" -- mirrors the paper form's
/// fill-in-the-blank style rather than a boxed table cell. [trailing], if
/// given, renders as a second fill-line immediately after this one on the
/// same row (e.g. a name field followed by its own Date field).
pw.Widget _fillLine(String label, String value, {double? width, pw.Widget? trailing}) {
  final line = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
    pw.Text('$label ', style: _sBody),
    pw.Expanded(
      child: pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
        padding: const pw.EdgeInsets.only(bottom: 1),
        child: pw.Text(value, style: _sBody),
      ),
    ),
  ]);
  final content = width != null ? pw.SizedBox(width: width, child: line) : line;
  if (trailing == null) return content;
  return pw.Row(children: [
    pw.Expanded(child: content),
    pw.SizedBox(width: 12),
    trailing,
  ]);
}

pw.Widget _checkbox(bool checked) => pw.Container(
      width: 9,
      height: 9,
      margin: const pw.EdgeInsets.only(right: 4),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.75)),
      alignment: pw.Alignment.center,
      child: checked ? pw.Text('X', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)) : null,
    );

pw.Widget _boxHeader(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.75))),
      child: pw.Center(child: pw.Text(title, style: _sBoxHeader)),
    );

pw.Widget _crewSwapBox(CrewSwapData f) {
  return pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.75)),
    child: pw.Column(children: [
      _boxHeader('CREW/OPERATOR SWAP'),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          // Left column
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _fillLine('Old Operator Name:', f.oldOperatorName),
              pw.SizedBox(height: 14),
              _fillLine('Phone:', f.oldOperatorPhone),
              pw.SizedBox(height: 6),
              _fillLine('Position on Equipment:', f.oldPositionOnEquipment),
              pw.SizedBox(height: 6),
              _fillLine('Last Work Day:', f.lastWorkDay),
              pw.SizedBox(height: 6),
              pw.Row(children: [
                pw.Text('Returning: ', style: _sBody),
                _checkbox(!f.returning),
                pw.Text('No  ', style: _sBody),
                _checkbox(f.returning),
                pw.Expanded(child: pw.Text('Yes - Return Date: ${f.returning ? f.returnDate : ''}', style: _sBody)),
              ]),
              pw.SizedBox(height: 2),
              pw.Text('***If YES, complete Section B***', style: _sSmallItalic),
            ]),
          ),
          pw.SizedBox(width: 14),
          // Right column
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('New Operator/Crew Names and Quals:', style: _sBody),
              pw.SizedBox(height: 2),
              pw.Container(
                width: double.infinity,
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
                padding: const pw.EdgeInsets.only(bottom: 1),
                child: pw.Text(f.newOperatorNamesQuals, style: _sBody),
              ),
              pw.SizedBox(height: 16),
              _fillLine('Name of Primary on Equipment:', f.namePrimaryOnEquipment),
              pw.SizedBox(height: 6),
              _fillLine('Primary Phone:', f.primaryPhone),
              pw.SizedBox(height: 6),
              _fillLine('First Work Day:', f.firstWorkDay),
              pw.SizedBox(height: 6),
              _fillLine('Number of Days:', f.numberOfDays),
            ]),
          ),
        ]),
      ),
    ]),
  );
}

pw.Widget _extensionBox(CrewSwapData f) {
  return pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.75)),
    child: pw.Column(children: [
      _boxHeader('OPERATOR/CREW/EQUIPMENT EXTENSION'),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _fillLine('Name:', f.extName),
          pw.SizedBox(height: 6),
          _fillLine('Phone:', f.extPhone),
          pw.SizedBox(height: 6),
          _fillLine('Position on Equipment:', f.extPosition),
          pw.SizedBox(height: 6),
          _fillLine('Justification for Extension:', f.justification),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            _checkbox(f.rnrAndReturn),
            pw.Text('R&R and Return', style: _sBodyBold),
            pw.SizedBox(width: 16),
            pw.Text('(if checked) ', style: _sSmallItalic),
            pw.Expanded(
              child: _fillLine('Dates of R&R:', f.rnrAndReturn ? f.rnrDates : '',
                  trailing: _fillLine('Return Date:', f.rnrAndReturn ? f.rnrReturnDate : '', width: 130)),
            ),
          ]),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            _checkbox(f.sevenDayExtension),
            pw.Text('7 Day Extension', style: _sBodyBold),
            pw.SizedBox(width: 16),
            pw.Text('(if checked) ', style: _sSmallItalic),
            pw.Expanded(child: _fillLine('New Last Work Day:', f.sevenDayExtension ? f.newLastWorkDay : '')),
          ]),
        ]),
      ),
    ]),
  );
}
