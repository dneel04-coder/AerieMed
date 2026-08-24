import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'crew_swap_form.dart' show CrewSwapData, CrewSwapSectionKind;

const _kAccent = PdfColors.indigo700;
const _kAccentLight = PdfColors.indigo50;
const _kGrid = PdfColors.grey300;

final _sH1 = pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _kAccent);
final _sH2 = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
const _sBody = pw.TextStyle(fontSize: 9);
const _sSmall = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);
final _sLabelCell = pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold);

Future<Uint8List> buildCrewSwapPdf(CrewSwapData f) async {
  final doc = pw.Document(title: 'CIMT 2 Crew Change Form', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      header: (_) => _pageHeader(),
      footer: (ctx) => _pageFooter(ctx),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

pw.Widget _pageHeader() => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
      ),
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('CIMT 2 Crew Change Form', style: _sH1),
        pw.SizedBox(height: 2),
        pw.Text('All crews and equipment are responsible for maintaining proper work/rest ratio', style: _sSmall),
      ]),
    );

pw.Widget _pageFooter(pw.Context ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(children: [
        pw.Text('V.2 7/1/2026', style: _sSmall),
        pw.Spacer(),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: _sSmall),
      ]),
    );

List<pw.Widget> _buildContent(CrewSwapData f) {
  return [
    _headerTable(f),
    _gap,
    if (f.section == CrewSwapSectionKind.crewSwap) ...[
      _sectionHead('CREW/OPERATOR SWAP'),
      _crewSwapTable(f),
    ] else ...[
      _sectionHead('OPERATOR/CREW/EQUIPMENT EXTENSION'),
      _extensionTable(f),
    ],
    _gap,
    _sectionHead('APPROVALS'),
    _approvalsTable(f),
  ];
}

final _gap = pw.SizedBox(height: 12);

pw.Widget _sectionHead(String title) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: const pw.BoxDecoration(color: _kAccent),
      child: pw.Text(title, style: _sH2),
    );

pw.Widget _lbl(String s) => pw.Container(
      color: _kAccentLight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(s, style: _sLabelCell),
    );

pw.Widget _val(String s) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(s.isEmpty ? '—' : s, style: _sBody),
    );

pw.Widget _headerTable(CrewSwapData f) => pw.Table(
      border: pw.TableBorder.all(color: _kGrid, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(children: [_lbl('Incident Name'), _val(f.incidentName)]),
        pw.TableRow(children: [_lbl('Current Division of Resource'), _val(f.currentDivision)]),
        pw.TableRow(children: [_lbl('Resource #'), _val(f.resourceNumber)]),
        pw.TableRow(children: [_lbl('Resource Name in IAP'), _val(f.resourceNameInIap)]),
        pw.TableRow(children: [_lbl('Resource Type'), _val(f.resourceType)]),
      ],
    );

pw.Widget _crewSwapTable(CrewSwapData f) {
  final returningText = f.returning
      ? 'Yes — Return Date: ${f.returnDate.isEmpty ? '—' : f.returnDate}'
      : 'No';
  return pw.Table(
    border: pw.TableBorder.all(color: _kGrid, width: 0.5),
    columnWidths: const {0: pw.FlexColumnWidth(1.3), 1: pw.FlexColumnWidth(2)},
    children: [
      pw.TableRow(children: [_lbl('Old Operator Name'), _val(f.oldOperatorName)]),
      pw.TableRow(children: [_lbl('Phone'), _val(f.oldOperatorPhone)]),
      pw.TableRow(children: [_lbl('Position on Equipment'), _val(f.oldPositionOnEquipment)]),
      pw.TableRow(children: [_lbl('Last Work Day'), _val(f.lastWorkDay)]),
      pw.TableRow(children: [_lbl('Returning'), _val(returningText)]),
      pw.TableRow(children: [_lbl('New Operator/Crew Names and Quals'), _val(f.newOperatorNamesQuals)]),
      pw.TableRow(children: [_lbl('Name of Primary on Equipment'), _val(f.namePrimaryOnEquipment)]),
      pw.TableRow(children: [_lbl('Primary Phone'), _val(f.primaryPhone)]),
      pw.TableRow(children: [_lbl('First Work Day'), _val(f.firstWorkDay)]),
      pw.TableRow(children: [_lbl('Number of Days'), _val(f.numberOfDays)]),
    ],
  );
}

pw.Widget _extensionTable(CrewSwapData f) {
  final rows = <pw.TableRow>[
    pw.TableRow(children: [_lbl('Name'), _val(f.extName)]),
    pw.TableRow(children: [_lbl('Phone'), _val(f.extPhone)]),
    pw.TableRow(children: [_lbl('Position on Equipment'), _val(f.extPosition)]),
    pw.TableRow(children: [_lbl('Justification for Extension'), _val(f.justification)]),
  ];
  if (f.rnrAndReturn) {
    rows.add(pw.TableRow(children: [
      _lbl('R&R and Return'),
      _val('Dates of R&R: ${f.rnrDates.isEmpty ? '—' : f.rnrDates}   Return Date: ${f.rnrReturnDate.isEmpty ? '—' : f.rnrReturnDate}'),
    ]));
  }
  if (f.sevenDayExtension) {
    rows.add(pw.TableRow(children: [
      _lbl('7 Day Extension'),
      _val('New Last Work Day: ${f.newLastWorkDay.isEmpty ? '—' : f.newLastWorkDay}'),
    ]));
  }
  return pw.Table(
    border: pw.TableBorder.all(color: _kGrid, width: 0.5),
    columnWidths: const {0: pw.FlexColumnWidth(1.3), 1: pw.FlexColumnWidth(2)},
    children: rows,
  );
}

pw.Widget _approvalsTable(CrewSwapData f) => pw.Table(
      border: pw.TableBorder.all(color: _kGrid, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(1.3), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(0.8), 3: pw.FlexColumnWidth(0.9)},
      children: [
        pw.TableRow(children: [
          _lbl('Home Unit Supervisor'), _val(f.homeUnitSupervisor),
          _lbl('Date'), _val(f.homeUnitSupervisorDate),
        ]),
        pw.TableRow(children: [
          _lbl('Division Supervisor Approval'), _val(f.divisionSupervisorApproval),
          _lbl('Date'), _val(f.divisionSupervisorDate),
        ]),
        pw.TableRow(children: [
          _lbl('Operations Section Chief Approval'), _val(f.opsSectionChiefApproval),
          _lbl('Date'), _val(f.opsSectionChiefDate),
        ]),
      ],
    );
