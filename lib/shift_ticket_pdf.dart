import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Matches OF-297 "Emergency Equipment Shift Ticket" (Rev. 5/2024, USDA/USDI):
// a bordered-grid form, not a fill-in-the-blank one -- every field renders as
// its own boxed cell, same as the paper form.

class ShiftTicketEquipmentRow {
  final String date, start, stop, total, quantity, type, note;
  const ShiftTicketEquipmentRow({
    this.date = '',
    this.start = '',
    this.stop = '',
    this.total = '',
    this.quantity = '',
    this.type = '',
    this.note = '',
  });
}

class ShiftTicketPersonnelRow {
  final String date, operatorName, start1, stop1, start2, stop2, total, note;
  const ShiftTicketPersonnelRow({
    this.date = '',
    this.operatorName = '',
    this.start1 = '',
    this.stop1 = '',
    this.start2 = '',
    this.stop2 = '',
    this.total = '',
    this.note = '',
  });
}

class ShiftTicketData {
  final String agreementNumber, contractorAgencyName, resourceOrderNumber;
  final String incidentName, incidentNumber, financialCode;
  final String equipmentMakeModel, equipmentType, serialVinNumber, licenseIdNumber;
  final bool transportRetained;
  final bool mobilization, demobilization;
  final bool appliesMiles, appliesHours;
  final List<ShiftTicketEquipmentRow> equipmentRows;
  final List<ShiftTicketPersonnelRow> personnelRows;
  final String remarks;
  final String contractorRepPrintedName;
  final String incidentSupervisorPrintedName;
  // Drawn ("Tap to Sign") signatures, PNG bytes -- null means unsigned, which
  // renders as a blank box, same as an unsigned paper form.
  final Uint8List? contractorRepSignatureImage;
  final Uint8List? incidentSupervisorSignatureImage;

  const ShiftTicketData({
    required this.agreementNumber,
    required this.contractorAgencyName,
    required this.resourceOrderNumber,
    required this.incidentName,
    required this.incidentNumber,
    required this.financialCode,
    required this.equipmentMakeModel,
    required this.equipmentType,
    required this.serialVinNumber,
    required this.licenseIdNumber,
    required this.transportRetained,
    required this.mobilization,
    required this.demobilization,
    required this.appliesMiles,
    required this.appliesHours,
    required this.equipmentRows,
    required this.personnelRows,
    required this.remarks,
    required this.contractorRepPrintedName,
    this.contractorRepSignatureImage,
    required this.incidentSupervisorPrintedName,
    this.incidentSupervisorSignatureImage,
  });
}

final _sTitle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
final _sBoxHeader = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
final _sLabel = pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700);
const _sValue = pw.TextStyle(fontSize: 8.5);
final _sTableHeader = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
const _sTableCell = pw.TextStyle(fontSize: 7.5);
final _sInstruction = pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic);
const _sSmall = pw.TextStyle(fontSize: 7);
final _border = pw.Border.all(width: 0.75);

Future<Uint8List> buildShiftTicketPdf(ShiftTicketData f) async {
  final doc = pw.Document(title: 'Emergency Equipment Shift Ticket', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      footer: (ctx) => pw.Row(children: [
        pw.Text('ResQruck', style: _sSmall),
        pw.Spacer(),
        pw.Text('OPTIONAL FORM 297 (REV. 5/2024) - USDA/USDI', style: _sSmall),
      ]),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

List<pw.Widget> _buildContent(ShiftTicketData f) {
  return [
    pw.Center(child: pw.Text('Emergency Equipment Shift Ticket', style: _sTitle)),
    pw.SizedBox(height: 8),

    // Blocks 1-3: Agreement / Contractor-Agency / Resource Order
    _gridRow([
      _cell('1. Agreement Number:', f.agreementNumber, flex: 2),
      _cell('2. Contractor/Agency Name:', f.contractorAgencyName, flex: 3),
      _cell('3. Resource Order Number:', f.resourceOrderNumber, flex: 2),
    ]),
    // Blocks 4-6: Incident Name / Incident Number / Financial Code
    _gridRow([
      _cell('4. Incident Name:', f.incidentName, flex: 3),
      _cell('5. Incident Number:', f.incidentNumber, flex: 2),
      _cell('6. Financial Code:', f.financialCode, flex: 2),
    ]),
    // Blocks 7-10: Equipment Make/Model / Type / Serial/VIN / License/ID
    _gridRow([
      _cell('7. Equipment Make/Model:', f.equipmentMakeModel, flex: 2),
      _cell('8. Equipment Type:', f.equipmentType, flex: 2),
      _cell('9. Serial/VIN Number:', f.serialVinNumber, flex: 2),
      _cell('10. License/ID Number:', f.licenseIdNumber, flex: 2),
    ]),

    // Blocks 11-12
    _dividedRow(
      flexes: const [3, 2],
      [
        pw.Text(
          '11. If applicable check and complete the following boxes. '
          'Use MILITARY TIME and/or real odometer reading.',
          style: _sInstruction,
        ),
        pw.Row(children: [
          pw.Text('12. Transport Retained?  ', style: _sTableHeader),
          _checkboxLabel('Yes', f.transportRetained),
          pw.SizedBox(width: 6),
          _checkboxLabel('No', !f.transportRetained),
        ]),
      ],
    ),

    _sectionHeader('Equipment'),

    // Blocks 13-14 + the (unnumbered) Blocks 19-20 special-rates note
    _dividedRow(
      flexes: const [2, 2, 3],
      [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('13. Is this a First/Last Ticket? (Check if yes)', style: _sTableHeader),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            _checkboxLabel('Mobilization', f.mobilization),
            pw.SizedBox(width: 10),
            _checkboxLabel('Demobilization', f.demobilization),
          ]),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            _checkboxLabel('14. Miles', f.appliesMiles),
            pw.SizedBox(width: 10),
            _checkboxLabel('Hours', f.appliesHours),
          ]),
          pw.SizedBox(height: 3),
          pw.Text('(Applies to blocks 16-18 below)', style: _sInstruction),
        ]),
        pw.Text('Blocks 19-20 Special Rates, indicate type and quantity (ex: 1 Day)', style: _sInstruction),
      ],
    ),
    _equipmentTable(f.equipmentRows),

    pw.SizedBox(height: 10),
    _sectionHeader('Personnel'),
    _personnelTable(f.personnelRows),

    pw.SizedBox(height: 10),
    pw.Text(
      '30. Remarks - Provide details of any equipment breakdown or operating issues. '
      'Include other information as necessary.',
      style: _sTableHeader,
    ),
    pw.SizedBox(height: 3),
    pw.Container(
      width: double.infinity,
      height: 50,
      decoration: pw.BoxDecoration(border: _border),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(f.remarks, style: _sValue),
    ),

    pw.SizedBox(height: 10),
    _gridRow([
      _cell('31. Contractor/Agency Representative (Printed Name)', f.contractorRepPrintedName, flex: 1),
      _signatureCell('32. Contractor/Agency Representative (Signature)', f.contractorRepSignatureImage, flex: 1),
    ]),
    _gridRow([
      _cell('33. Incident Supervisor (Printed Name & Resource Order number)', f.incidentSupervisorPrintedName, flex: 1),
      _signatureCell('34. Incident Supervisor (Signature)', f.incidentSupervisorSignatureImage, flex: 1),
    ]),
  ];
}

pw.Widget _sectionHeader(String title) => pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(color: PdfColors.grey300, border: _border),
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: pw.Center(child: pw.Text(title, style: _sBoxHeader)),
    );

pw.Widget _checkboxLabel(String label, bool checked) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 9,
          height: 9,
          margin: const pw.EdgeInsets.only(right: 3),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.75)),
          alignment: pw.Alignment.center,
          child: checked ? pw.Text('X', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)) : null,
        ),
        pw.Text(label, style: _sTableHeader),
      ],
    );

/// A single bordered strip split into vertically-divided segments (a right
/// border on every segment but the last) -- matches the paper form's blocks
/// 11-12 and 13-14 rows, which are one bordered band internally split into
/// several fields rather than independent boxed cells like blocks 1-10.
pw.Widget _dividedRow(List<pw.Widget> segments, {List<int>? flexes}) => pw.Container(
      decoration: pw.BoxDecoration(border: _border),
      child: pw.Row(children: [
        for (var i = 0; i < segments.length; i++)
          pw.Expanded(
            flex: flexes != null ? flexes[i] : 1,
            child: pw.Container(
              decoration: i < segments.length - 1
                  ? const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.75)))
                  : null,
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: segments[i],
            ),
          ),
      ]),
    );

/// A row of bordered grid cells (label above value), each already sized via
/// its own [_cell] flex -- mirrors the paper form's numbered boxed fields.
/// Note: no CrossAxisAlignment.stretch here -- this package's Row computes
/// unbounded cross-axis (height) for stretch when used inside a MultiPage's
/// vertically-flowing content, which throws ("height Infinity exceeds a
/// page height"). Cells with uneven content just end up mismatched by a
/// couple points instead, which is a fine trade for not crashing PDF
/// generation.
pw.Widget _gridRow(List<pw.Widget> cells) => pw.Row(children: cells);

pw.Widget _cell(String label, String value, {int flex = 1}) => pw.Expanded(
      flex: flex,
      child: pw.Container(
        decoration: pw.BoxDecoration(border: _border),
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: _sLabel),
          pw.SizedBox(height: 2),
          pw.Text(value, style: _sValue),
        ]),
      ),
    );

/// Same box style as [_cell] but for a drawn ("Tap to Sign") signature --
/// renders the captured PNG in place of a text value, or stays blank
/// (matching an unsigned paper form) when [signatureImage] is null. A fixed
/// height keeps the Column bounded, which is required for pw.Expanded to
/// lay out the image safely inside it.
pw.Widget _signatureCell(String label, Uint8List? signatureImage, {int flex = 1}) => pw.Expanded(
      flex: flex,
      child: pw.Container(
        height: 44,
        decoration: pw.BoxDecoration(border: _border),
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: _sLabel),
          pw.SizedBox(height: 2),
          if (signatureImage != null)
            pw.Expanded(
              child: pw.Image(pw.MemoryImage(signatureImage),
                  fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft),
            ),
        ]),
      ),
    );

pw.Widget _tableHeaderCell(String text) => pw.Container(
      color: PdfColors.grey300,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      alignment: pw.Alignment.center,
      child: pw.Text(text, style: _sTableHeader, textAlign: pw.TextAlign.center),
    );

pw.Widget _tableCell(String text) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(text, style: _sTableCell),
    );

pw.Widget _equipmentTable(List<ShiftTicketEquipmentRow> rows) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.75),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.3),
      1: pw.FlexColumnWidth(1),
      2: pw.FlexColumnWidth(1),
      3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1),
      5: pw.FlexColumnWidth(1),
      6: pw.FlexColumnWidth(2.4),
    },
    children: [
      pw.TableRow(children: [
        _tableHeaderCell('15. Date'),
        _tableHeaderCell('16. Start'),
        _tableHeaderCell('17. Stop'),
        _tableHeaderCell('18. Total'),
        _tableHeaderCell('19. Quantity'),
        _tableHeaderCell('20. Type'),
        _tableHeaderCell('21. Note Travel/Other remarks'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          _tableCell(r.date),
          _tableCell(r.start),
          _tableCell(r.stop),
          _tableCell(r.total),
          _tableCell(r.quantity),
          _tableCell(r.type),
          _tableCell(r.note),
        ]),
    ],
  );
}

pw.Widget _personnelTable(List<ShiftTicketPersonnelRow> rows) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.75),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.1),
      1: pw.FlexColumnWidth(1.8),
      2: pw.FlexColumnWidth(0.8),
      3: pw.FlexColumnWidth(0.8),
      4: pw.FlexColumnWidth(0.8),
      5: pw.FlexColumnWidth(0.8),
      6: pw.FlexColumnWidth(0.8),
      7: pw.FlexColumnWidth(2.2),
    },
    children: [
      pw.TableRow(children: [
        _tableHeaderCell('22. Date'),
        _tableHeaderCell('23. Operator Name\n(First & Last)'),
        _tableHeaderCell('24. Start'),
        _tableHeaderCell('25. Stop'),
        _tableHeaderCell('26. Start'),
        _tableHeaderCell('27. Stop'),
        _tableHeaderCell('28. Total'),
        _tableHeaderCell('29. Note Travel/Other remarks'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          _tableCell(r.date),
          _tableCell(r.operatorName),
          _tableCell(r.start1),
          _tableCell(r.stop1),
          _tableCell(r.start2),
          _tableCell(r.stop2),
          _tableCell(r.total),
          _tableCell(r.note),
        ]),
    ],
  );
}
