import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_form_widgets.dart';

// Matches FEMA ICS Form 214 "Activity Log" (v3.1) exactly -- block numbers,
// bordered grid.

class Ics214ResourceRow {
  final String name, icsPosition, homeAgency;
  const Ics214ResourceRow({this.name = '', this.icsPosition = '', this.homeAgency = ''});
}

class Ics214LogEntry {
  final String dateTime, activity;
  const Ics214LogEntry({this.dateTime = '', this.activity = ''});
}

class Ics214Data {
  final String incidentName;
  final String opPeriodDateFrom, opPeriodDateTo, opPeriodTimeFrom, opPeriodTimeTo;
  final String name, icsPosition, homeAgency;
  final List<Ics214ResourceRow> resources;
  final List<Ics214LogEntry> log;
  final String preparedByName, preparedByTitle, preparedByDateTime;
  final Uint8List? preparedBySignatureImage;

  const Ics214Data({
    required this.incidentName,
    required this.opPeriodDateFrom,
    required this.opPeriodDateTo,
    required this.opPeriodTimeFrom,
    required this.opPeriodTimeTo,
    required this.name,
    required this.icsPosition,
    required this.homeAgency,
    required this.resources,
    required this.log,
    required this.preparedByName,
    required this.preparedByTitle,
    required this.preparedByDateTime,
    this.preparedBySignatureImage,
  });
}

Future<Uint8List> buildIcs214Pdf(Ics214Data f) async {
  final doc = pw.Document(title: 'Activity Log (ICS 214)', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      footer: (ctx) => pw.Row(children: [
        pw.Text('ICS 214, Page 1', style: formSmallStyle),
      ]),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

List<pw.Widget> _buildContent(Ics214Data f) {
  return [
    pw.Center(child: pw.Text('Activity Log (ICS 214)', style: formTitleStyle)),
    pw.SizedBox(height: 8),

    formGridRow([
      formCell('1. Incident Name', f.incidentName, flex: 1),
      pw.Expanded(
        flex: 1,
        child: pw.Container(
          decoration: pw.BoxDecoration(border: formBorder),
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('2. Operational Period', style: formLabelStyle),
            pw.SizedBox(height: 2),
            pw.Text('Date From: ${f.opPeriodDateFrom}   Date To: ${f.opPeriodDateTo}', style: formValueStyle),
            pw.SizedBox(height: 2),
            pw.Text('Time From: ${f.opPeriodTimeFrom}   Time To: ${f.opPeriodTimeTo}', style: formValueStyle),
          ]),
        ),
      ),
    ]),
    formGridRow([
      formCell('3. Name', f.name, flex: 1),
      formCell('4. ICS Position', f.icsPosition, flex: 1),
      formCell('5. Home Agency (and Unit)', f.homeAgency, flex: 1),
    ]),

    pw.SizedBox(height: 8),
    pw.Text('6. Resources Assigned', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    _resourcesTable(f.resources),

    pw.SizedBox(height: 8),
    pw.Text('7. Activity Log', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    _logTable(f.log),

    pw.SizedBox(height: 10),
    pw.Text('8. Prepared By', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formGridRow([
      formCell('Name', f.preparedByName, flex: 1),
      formCell('Position/Title', f.preparedByTitle, flex: 1),
      formSignatureCell('Signature', f.preparedBySignatureImage, flex: 1),
      formCell('Date/Time', f.preparedByDateTime, flex: 1),
    ]),
  ];
}

pw.Widget _resourcesTable(List<Ics214ResourceRow> rows) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.75),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.3),
      1: pw.FlexColumnWidth(1),
      2: pw.FlexColumnWidth(1.3),
    },
    children: [
      pw.TableRow(children: [
        formTableHeaderCell('Name'),
        formTableHeaderCell('ICS Position'),
        formTableHeaderCell('Home Agency (and Unit)'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          formTableCell(r.name),
          formTableCell(r.icsPosition),
          formTableCell(r.homeAgency),
        ]),
    ],
  );
}

pw.Widget _logTable(List<Ics214LogEntry> rows) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.75),
    columnWidths: const {
      0: pw.FlexColumnWidth(1),
      1: pw.FlexColumnWidth(3.5),
    },
    children: [
      pw.TableRow(children: [
        formTableHeaderCell('Date/Time'),
        formTableHeaderCell('Notable Activities'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          formTableCell(r.dateTime),
          formTableCell(r.activity),
        ]),
    ],
  );
}
