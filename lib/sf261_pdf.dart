import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_form_widgets.dart';

// Matches Standard Form 261 "Crew Time Report" (Rev. 11/2021, NWCG PMS 902,
// NFES 000891) exactly -- block numbers, bordered grid.

class Sf261CrewRow {
  final String remarksNumber, employeeName, classification;
  final String date1, timeOn1, timeOff1;
  final String date2, timeOn2, timeOff2;
  const Sf261CrewRow({
    this.remarksNumber = '',
    this.employeeName = '',
    this.classification = '',
    this.date1 = '',
    this.timeOn1 = '',
    this.timeOff1 = '',
    this.date2 = '',
    this.timeOn2 = '',
    this.timeOff2 = '',
  });
}

class Sf261Data {
  final String crewName, crewNumber;
  final String officeResponsibleForFire, fireName, fireNumber;
  final List<Sf261CrewRow> rows;
  final String remarks;
  final Uint8List? officerInChargeSignatureImage;
  final String officerInChargeTitle;
  final String preparerName;
  final String date;

  const Sf261Data({
    required this.crewName,
    required this.crewNumber,
    required this.officeResponsibleForFire,
    required this.fireName,
    required this.fireNumber,
    required this.rows,
    required this.remarks,
    this.officerInChargeSignatureImage,
    required this.officerInChargeTitle,
    required this.preparerName,
    required this.date,
  });
}

Future<Uint8List> buildSf261Pdf(Sf261Data f) async {
  final doc = pw.Document(title: 'Crew Time Report (SF-261)', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      footer: (ctx) => pw.Row(children: [
        pw.Text('NFES 000891', style: formSmallStyle),
        pw.Spacer(),
        pw.Text('STANDARD FORM 261 (REV. 11/2021)', style: formSmallStyle),
      ]),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

List<pw.Widget> _buildContent(Sf261Data f) {
  return [
    pw.Center(child: pw.Text('Crew Time Report', style: formTitleStyle)),
    pw.SizedBox(height: 8),

    formGridRow([
      formCell('1. Crew Name', f.crewName, flex: 3),
      formCell('2. Crew Number', f.crewNumber, flex: 1),
    ]),
    formGridRow([
      formCell('3. Office Responsible for Fire', f.officeResponsibleForFire, flex: 2),
      formCell('4. Fire Name', f.fireName, flex: 1),
      formCell('5. Fire Number', f.fireNumber, flex: 1),
    ]),
    pw.SizedBox(height: 6),

    _crewTable(f.rows),

    pw.SizedBox(height: 8),
    pw.Text('11. Remarks', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formTextBox(f.remarks, height: 60),

    pw.SizedBox(height: 10),
    formGridRow([
      formSignatureCell('12. Officer-in-Charge (Signature)', f.officerInChargeSignatureImage, flex: 1),
      formCell('13. Title (Officer-in-Charge)', f.officerInChargeTitle, flex: 1),
    ]),
    formGridRow([
      formCell('14. Name (Person Posting to Emergency Time Report)', f.preparerName, flex: 2),
      formCell('15. Date', f.date, flex: 1),
    ]),
  ];
}

pw.Widget _crewTable(List<Sf261CrewRow> rows) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.75),
    columnWidths: const {
      0: pw.FlexColumnWidth(0.7),
      1: pw.FlexColumnWidth(2.2),
      2: pw.FlexColumnWidth(1.2),
      3: pw.FlexColumnWidth(0.8),
      4: pw.FlexColumnWidth(0.7),
      5: pw.FlexColumnWidth(0.7),
      6: pw.FlexColumnWidth(0.8),
      7: pw.FlexColumnWidth(0.7),
      8: pw.FlexColumnWidth(0.7),
    },
    children: [
      pw.TableRow(children: [
        formTableHeaderCell('6. Remarks\nNumber'),
        formTableHeaderCell('7. Name of Employee'),
        formTableHeaderCell('8. Classification'),
        formTableHeaderCell('9. Date'),
        formTableHeaderCell('ON'),
        formTableHeaderCell('OFF'),
        formTableHeaderCell('10. Date'),
        formTableHeaderCell('ON'),
        formTableHeaderCell('OFF'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          formTableCell(r.remarksNumber),
          formTableCell(r.employeeName),
          formTableCell(r.classification),
          formTableCell(r.date1),
          formTableCell(r.timeOn1),
          formTableCell(r.timeOff1),
          formTableCell(r.date2),
          formTableCell(r.timeOn2),
          formTableCell(r.timeOff2),
        ]),
    ],
  );
}
