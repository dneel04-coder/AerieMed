import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_form_widgets.dart';

// Matches FEMA ICS Form 205 "Incident Radio Communications Plan" (v3.1)
// exactly -- block numbers, bordered grid.

class Ics205ChannelRow {
  final String zoneGroup, channelNumber, function, channelName, assignment;
  final String rxFreq, rxTone, txFreq, txTone, mode, remarks;
  const Ics205ChannelRow({
    this.zoneGroup = '',
    this.channelNumber = '',
    this.function = '',
    this.channelName = '',
    this.assignment = '',
    this.rxFreq = '',
    this.rxTone = '',
    this.txFreq = '',
    this.txTone = '',
    this.mode = '',
    this.remarks = '',
  });
}

class Ics205Data {
  final String incidentName;
  final String datePrepared, timePrepared;
  final String opPeriodDateFrom, opPeriodDateTo, opPeriodTimeFrom, opPeriodTimeTo;
  final List<Ics205ChannelRow> channels;
  final String specialInstructions;
  final String preparedByName;
  final Uint8List? preparedBySignatureImage;
  final String iapPage;
  final String preparedByDateTime;

  const Ics205Data({
    required this.incidentName,
    required this.datePrepared,
    required this.timePrepared,
    required this.opPeriodDateFrom,
    required this.opPeriodDateTo,
    required this.opPeriodTimeFrom,
    required this.opPeriodTimeTo,
    required this.channels,
    required this.specialInstructions,
    required this.preparedByName,
    this.preparedBySignatureImage,
    required this.iapPage,
    required this.preparedByDateTime,
  });
}

Future<Uint8List> buildIcs205Pdf(Ics205Data f) async {
  final doc = pw.Document(title: 'Incident Radio Communications Plan (ICS 205)', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      footer: (ctx) => pw.Row(children: [pw.Text('ICS 205', style: formSmallStyle)]),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

List<pw.Widget> _buildContent(Ics205Data f) {
  return [
    pw.Center(child: pw.Text('Incident Radio Communications Plan (ICS 205)', style: formTitleStyle)),
    pw.SizedBox(height: 8),

    formGridRow([
      formCell('1. Incident Name', f.incidentName, flex: 1),
      pw.Expanded(
        flex: 1,
        child: pw.Container(
          decoration: pw.BoxDecoration(border: formBorder),
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('2. Date/Time Prepared', style: formLabelStyle),
            pw.SizedBox(height: 2),
            pw.Text('Date: ${f.datePrepared}', style: formValueStyle),
            pw.Text('Time: ${f.timePrepared}', style: formValueStyle),
          ]),
        ),
      ),
      pw.Expanded(
        flex: 1,
        child: pw.Container(
          decoration: pw.BoxDecoration(border: formBorder),
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('3. Operational Period', style: formLabelStyle),
            pw.SizedBox(height: 2),
            pw.Text('Date From: ${f.opPeriodDateFrom}   Date To: ${f.opPeriodDateTo}', style: formValueStyle),
            pw.Text('Time From: ${f.opPeriodTimeFrom}   Time To: ${f.opPeriodTimeTo}', style: formValueStyle),
          ]),
        ),
      ),
    ]),

    pw.SizedBox(height: 8),
    pw.Text('4. Basic Radio Channel Use', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    _channelTable(f.channels),

    pw.SizedBox(height: 8),
    pw.Text('5. Special Instructions', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formTextBox(f.specialInstructions, height: 50),

    pw.SizedBox(height: 10),
    pw.Text('6. Prepared by (Communications Unit Leader)', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formGridRow([
      formCell('Name', f.preparedByName, flex: 2),
      formSignatureCell('Signature', f.preparedBySignatureImage, flex: 2),
      formCell('IAP Page', f.iapPage, flex: 1),
      formCell('Date/Time', f.preparedByDateTime, flex: 1),
    ]),
  ];
}

pw.Widget _channelTable(List<Ics205ChannelRow> rows) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.75),
    columnWidths: const {
      0: pw.FlexColumnWidth(0.7),
      1: pw.FlexColumnWidth(0.6),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(1.4),
      4: pw.FlexColumnWidth(1.1),
      5: pw.FlexColumnWidth(0.8),
      6: pw.FlexColumnWidth(0.8),
      7: pw.FlexColumnWidth(0.8),
      8: pw.FlexColumnWidth(0.8),
      9: pw.FlexColumnWidth(0.7),
      10: pw.FlexColumnWidth(1.6),
    },
    children: [
      pw.TableRow(children: [
        formTableHeaderCell('Zone\nGrp.'),
        formTableHeaderCell('Ch\n#'),
        formTableHeaderCell('Function'),
        formTableHeaderCell('Channel Name/\nTalkgroup'),
        formTableHeaderCell('Assignment'),
        formTableHeaderCell('RX Freq\nN or W'),
        formTableHeaderCell('RX\nTone/NAC'),
        formTableHeaderCell('TX Freq\nN or W'),
        formTableHeaderCell('TX\nTone/NAC'),
        formTableHeaderCell('Mode\n(A,D,M)'),
        formTableHeaderCell('Remarks'),
      ]),
      for (final r in rows)
        pw.TableRow(children: [
          formTableCell(r.zoneGroup),
          formTableCell(r.channelNumber),
          formTableCell(r.function),
          formTableCell(r.channelName),
          formTableCell(r.assignment),
          formTableCell(r.rxFreq),
          formTableCell(r.rxTone),
          formTableCell(r.txFreq),
          formTableCell(r.txTone),
          formTableCell(r.mode),
          formTableCell(r.remarks),
        ]),
    ],
  );
}
