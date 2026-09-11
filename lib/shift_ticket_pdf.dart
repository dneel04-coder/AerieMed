import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_form_widgets.dart';

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

Future<Uint8List> buildShiftTicketPdf(ShiftTicketData f) async {
  final doc = pw.Document(title: 'Emergency Equipment Shift Ticket', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      footer: (ctx) => pw.Row(children: [
        pw.Text('ResQruck', style: formSmallStyle),
        pw.Spacer(),
        pw.Text('OPTIONAL FORM 297 (REV. 5/2024) - USDA/USDI', style: formSmallStyle),
      ]),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

List<pw.Widget> _buildContent(ShiftTicketData f) {
  return [
    pw.Center(child: pw.Text('Emergency Equipment Shift Ticket', style: formTitleStyle)),
    pw.SizedBox(height: 8),

    // Blocks 1-3: Agreement / Contractor-Agency / Resource Order
    formGridRow([
      formCell('1. Agreement Number:', f.agreementNumber, flex: 2),
      formCell('2. Contractor/Agency Name:', f.contractorAgencyName, flex: 3),
      formCell('3. Resource Order Number:', f.resourceOrderNumber, flex: 2),
    ]),
    // Blocks 4-6: Incident Name / Incident Number / Financial Code
    formGridRow([
      formCell('4. Incident Name:', f.incidentName, flex: 3),
      formCell('5. Incident Number:', f.incidentNumber, flex: 2),
      formCell('6. Financial Code:', f.financialCode, flex: 2),
    ]),
    // Blocks 7-10: Equipment Make/Model / Type / Serial/VIN / License/ID
    formGridRow([
      formCell('7. Equipment Make/Model:', f.equipmentMakeModel, flex: 2),
      formCell('8. Equipment Type:', f.equipmentType, flex: 2),
      formCell('9. Serial/VIN Number:', f.serialVinNumber, flex: 2),
      formCell('10. License/ID Number:', f.licenseIdNumber, flex: 2),
    ]),

    // Blocks 11-12
    formDividedRow(
      flexes: const [3, 2],
      [
        pw.Text(
          '11. If applicable check and complete the following boxes. '
          'Use MILITARY TIME and/or real odometer reading.',
          style: formInstructionStyle,
        ),
        pw.Row(children: [
          pw.Text('12. Transport Retained?  ', style: formTableHeaderStyle),
          formCheckboxLabel('Yes', f.transportRetained),
          pw.SizedBox(width: 6),
          formCheckboxLabel('No', !f.transportRetained),
        ]),
      ],
    ),

    formSectionHeader('Equipment'),

    // Blocks 13-14 + the (unnumbered) Blocks 19-20 special-rates note
    formDividedRow(
      flexes: const [2, 2, 3],
      [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('13. Is this a First/Last Ticket? (Check if yes)', style: formTableHeaderStyle),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            formCheckboxLabel('Mobilization', f.mobilization),
            pw.SizedBox(width: 10),
            formCheckboxLabel('Demobilization', f.demobilization),
          ]),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            formCheckboxLabel('14. Miles', f.appliesMiles),
            pw.SizedBox(width: 10),
            formCheckboxLabel('Hours', f.appliesHours),
          ]),
          pw.SizedBox(height: 3),
          pw.Text('(Applies to blocks 16-18 below)', style: formInstructionStyle),
        ]),
        pw.Text('Blocks 19-20 Special Rates, indicate type and quantity (ex: 1 Day)', style: formInstructionStyle),
      ],
    ),
    _equipmentTable(f.equipmentRows),

    pw.SizedBox(height: 10),
    formSectionHeader('Personnel'),
    _personnelTable(f.personnelRows),

    pw.SizedBox(height: 10),
    pw.Text(
      '30. Remarks - Provide details of any equipment breakdown or operating issues. '
      'Include other information as necessary.',
      style: formTableHeaderStyle,
    ),
    pw.SizedBox(height: 3),
    formTextBox(f.remarks),

    pw.SizedBox(height: 10),
    formGridRow([
      formCell('31. Contractor/Agency Representative (Printed Name)', f.contractorRepPrintedName, flex: 1),
      formSignatureCell('32. Contractor/Agency Representative (Signature)', f.contractorRepSignatureImage, flex: 1),
    ]),
    formGridRow([
      formCell('33. Incident Supervisor (Printed Name & Resource Order number)', f.incidentSupervisorPrintedName, flex: 1),
      formSignatureCell('34. Incident Supervisor (Signature)', f.incidentSupervisorSignatureImage, flex: 1),
    ]),
  ];
}

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
        formTableHeaderCell('15. Date'),
        formTableHeaderCell('16. Start'),
        formTableHeaderCell('17. Stop'),
        formTableHeaderCell('18. Total'),
        formTableHeaderCell('19. Quantity'),
        formTableHeaderCell('20. Type'),
        formTableHeaderCell('21. Note Travel/Other remarks'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          formTableCell(r.date),
          formTableCell(r.start),
          formTableCell(r.stop),
          formTableCell(r.total),
          formTableCell(r.quantity),
          formTableCell(r.type),
          formTableCell(r.note),
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
        formTableHeaderCell('22. Date'),
        formTableHeaderCell('23. Operator Name\n(First & Last)'),
        formTableHeaderCell('24. Start'),
        formTableHeaderCell('25. Stop'),
        formTableHeaderCell('26. Start'),
        formTableHeaderCell('27. Stop'),
        formTableHeaderCell('28. Total'),
        formTableHeaderCell('29. Note Travel/Other remarks'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          formTableCell(r.date),
          formTableCell(r.operatorName),
          formTableCell(r.start1),
          formTableCell(r.stop1),
          formTableCell(r.start2),
          formTableCell(r.stop2),
          formTableCell(r.total),
          formTableCell(r.note),
        ]),
    ],
  );
}
