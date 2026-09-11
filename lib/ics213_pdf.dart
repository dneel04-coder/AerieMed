import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_form_widgets.dart';

// Matches FEMA ICS Form 213 "General Message" (v3) exactly -- block numbers,
// bordered grid. Two independent signature blocks: Approved by (8) and
// Replied by (10).

class Ics213Data {
  final String incidentName;
  final String to, from, subject, date, time;
  final String message;
  final String approvedByName, approvedByTitle;
  final Uint8List? approvedBySignatureImage;
  final String reply;
  final String repliedByName, repliedByTitle, repliedByDateTime;
  final Uint8List? repliedBySignatureImage;

  const Ics213Data({
    required this.incidentName,
    required this.to,
    required this.from,
    required this.subject,
    required this.date,
    required this.time,
    required this.message,
    required this.approvedByName,
    required this.approvedByTitle,
    this.approvedBySignatureImage,
    required this.reply,
    required this.repliedByName,
    required this.repliedByTitle,
    required this.repliedByDateTime,
    this.repliedBySignatureImage,
  });
}

Future<Uint8List> buildIcs213Pdf(Ics213Data f) async {
  final doc = pw.Document(title: 'General Message (ICS 213)', creator: 'ResQruck');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      footer: (ctx) => pw.Row(children: [pw.Text('ICS 213', style: formSmallStyle)]),
      build: (_) => _buildContent(f),
    ),
  );

  return doc.save();
}

List<pw.Widget> _buildContent(Ics213Data f) {
  return [
    pw.Center(child: pw.Text('General Message (ICS 213)', style: formTitleStyle)),
    pw.SizedBox(height: 8),

    formGridRow([formCell('1. Incident Name (Optional)', f.incidentName, flex: 1)]),
    formGridRow([formCell('2. To (Name and Position)', f.to, flex: 1)]),
    formGridRow([formCell('3. From (Name and Position)', f.from, flex: 1)]),
    formGridRow([
      formCell('4. Subject', f.subject, flex: 2),
      formCell('5. Date', f.date, flex: 1),
      formCell('6. Time', f.time, flex: 1),
    ]),

    pw.SizedBox(height: 6),
    pw.Text('7. Message', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formTextBox(f.message, height: 160),

    pw.SizedBox(height: 8),
    pw.Text('8. Approved by', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formGridRow([
      formCell('Name', f.approvedByName, flex: 1),
      formSignatureCell('Signature', f.approvedBySignatureImage, flex: 1),
      formCell('Position/Title', f.approvedByTitle, flex: 1),
    ]),

    pw.SizedBox(height: 10),
    pw.Text('9. Reply', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formTextBox(f.reply, height: 160),

    pw.SizedBox(height: 8),
    pw.Text('10. Replied by', style: formTableHeaderStyle),
    pw.SizedBox(height: 3),
    formGridRow([
      formCell('Name', f.repliedByName, flex: 1),
      formCell('Position/Title', f.repliedByTitle, flex: 1),
      formSignatureCell('Signature', f.repliedBySignatureImage, flex: 1),
      formCell('Date/Time', f.repliedByDateTime, flex: 1),
    ]),
  ];
}
