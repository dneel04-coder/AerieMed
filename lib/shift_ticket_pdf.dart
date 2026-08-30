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
  final String contractorRepPrintedName, contractorRepSignature;
  final String incidentSupervisorPrintedName, incidentSupervisorSignature;

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
    required this.contractorRepSignature,
    required this.incidentSupervisorPrintedName,
    required this.incidentSupervisorSignature,
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
        pw.Text('OPTIONAL FORM 297 (REV. 5/2024) — USDA/USDI', style: _sSmall),
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

    // Row: Agreement / Contractor-Agency / Resource Order
    _gridRow([
      _cell('Agreement Number', f.agreementNumber, flex: 2),
      _cell('Contractor/Agency Name', f.contractorAgencyName, flex: 3),
      _cell('Resource Order Number', f.resourceOrderNumber, flex: 2),
    ]),
    // Row: Incident Name / Incident Number / Financial Code
    _gridRow([
      _cell('Incident Name', f.incidentName, flex: 3),
      _cell('Incident Number', f.incidentNumber, flex: 2),
      _cell('Financial Code', f.financialCode, flex: 2),
    ]),
    // Row: Equipment Make/Model / Type / Serial/VIN / License/ID
    _gridRow([
      _cell('Equipment Make/Model', f.equipmentMakeModel, flex: 2),
      _cell('Equipment Type', f.equipmentType, flex: 2),
      _cell('Serial/VIN Number', f.serialVinNumber, flex: 2),
      _cell('License/ID Number', f.licenseIdNumber, flex: 2),
    ]),

    pw.SizedBox(height: 4),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Expanded(
        child: pw.Text(
          'If applicable check and complete the following boxes. Use MILITARY TIME and/or real odometer reading.',
          style: _sInstruction,
        ),
      ),
      pw.SizedBox(width: 10),
      pw.Text('Transport Retained?  ', style: _sTableHeader),
      _checkboxLabel('Yes', f.transportRetained),
      pw.SizedBox(width: 6),
      _checkboxLabel('No', !f.transportRetained),
    ]),
    pw.SizedBox(height: 8),

    _sectionHeader('Equipment'),
    pw.SizedBox(height: 4),
    pw.Row(children: [
      pw.Text('Is this a First/Last Ticket?  ', style: _sTableHeader),
      _checkboxLabel('Mobilization', f.mobilization),
      pw.SizedBox(width: 10),
      _checkboxLabel('Demobilization', f.demobilization),
      pw.SizedBox(width: 16),
      pw.Text('Miles/Hours applies to Start/Stop/Total:  ', style: _sTableHeader),
      _checkboxLabel('Miles', f.appliesMiles),
      pw.SizedBox(width: 10),
      _checkboxLabel('Hours', f.appliesHours),
    ]),
    pw.SizedBox(height: 4),
    _equipmentTable(f.equipmentRows),

    pw.SizedBox(height: 10),
    _sectionHeader('Personnel'),
    pw.SizedBox(height: 4),
    _personnelTable(f.personnelRows),

    pw.SizedBox(height: 10),
    pw.Text('Remarks — equipment breakdown, operating issues, or other information:', style: _sTableHeader),
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
      _cell('Contractor/Agency Representative (Printed Name)', f.contractorRepPrintedName, flex: 1),
      _cell('Contractor/Agency Representative (Signature)', f.contractorRepSignature, flex: 1),
    ]),
    _gridRow([
      _cell('Incident Supervisor (Printed Name & Resource Order Number)', f.incidentSupervisorPrintedName, flex: 1),
      _cell('Incident Supervisor (Signature)', f.incidentSupervisorSignature, flex: 1),
    ]),
  ];
}

pw.Widget _sectionHeader(String title) => pw.Container(
      width: double.infinity,
      color: PdfColors.grey300,
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: pw.Text(title, style: _sBoxHeader),
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

/// A row of bordered grid cells (label above value), each already sized via
/// its own [_cell] flex -- mirrors the paper form's numbered boxed fields.
pw.Widget _gridRow(List<pw.Widget> cells) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: cells,
    );

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
        _tableHeaderCell('Date'),
        _tableHeaderCell('Start'),
        _tableHeaderCell('Stop'),
        _tableHeaderCell('Total'),
        _tableHeaderCell('Quantity'),
        _tableHeaderCell('Type'),
        _tableHeaderCell('Note Travel/Other remarks'),
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
        _tableHeaderCell('Date'),
        _tableHeaderCell('Operator Name\n(First & Last)'),
        _tableHeaderCell('Start'),
        _tableHeaderCell('Stop'),
        _tableHeaderCell('Start'),
        _tableHeaderCell('Stop'),
        _tableHeaderCell('Total'),
        _tableHeaderCell('Note Travel/Other remarks'),
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
