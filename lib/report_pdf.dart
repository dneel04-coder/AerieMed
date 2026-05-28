import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'patient_report.dart';


Future<Uint8List> buildReportPdf(PatientReport r) async {
  final doc = pw.Document(title: 'AustereMed PCR', creator: 'AustereMed');

  final photos = <pw.MemoryImage>[];
  for (final path in r.photoPaths) {
    try {
      photos.add(pw.MemoryImage(await File(path).readAsBytes()));
    } catch (_) {}
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      header: (_) => _pageHeader(r),
      footer: (ctx) => _pageFooter(ctx),
      build: (_) => _buildContent(r, photos),
    ),
  );

  return doc.save();
}

class ReportPdfGenerator {
  static Future<void> share(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

  static Future<void> preview(Uint8List bytes) =>
      Printing.layoutPdf(onLayout: (_) async => bytes);
}


const _kAccent = PdfColors.indigo700;
const _kAccentLight = PdfColors.indigo50;
const _kGrid = PdfColors.grey300;
const _kAltRow = PdfColors.grey100;

final _sH1 = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _kAccent);
final _sH2 = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kAccent, letterSpacing: 0.6);
const _sBody = pw.TextStyle(fontSize: 10);
const _sSmall = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);
final _sWhiteBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
final _sLabelCell = pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold);


pw.Widget _pageHeader(PatientReport r) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
      ),
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: pw.BoxDecoration(
            color: _kAccent,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Text(r.formType, style: _sWhiteBold),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(r.patientId.isEmpty ? 'Unknown Patient' : r.patientId, style: _sH1),
        ),
        pw.Text(r.timestampDisplay, style: _sSmall),
      ]),
    );

pw.Widget _pageFooter(pw.Context ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(children: [
        pw.Text('AustereMed Patient Care Report', style: _sSmall),
        pw.Spacer(),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: _sSmall),
      ]),
    );


List<pw.Widget> _buildContent(PatientReport r, List<pw.MemoryImage> photos) {
  String v(String s, [String fb = '—']) => s.isEmpty ? fb : s;

  return [
    _sectionHead('PATIENT INFORMATION'),
    _patientTable(r),

    if (r.mechanism.isNotEmpty) ...[
      _gap,
      _sectionHead('MECHANISM OF INJURY / ILLNESS'),
      _bodyText(r.mechanism),
    ],

    if (r.vitalSets.isNotEmpty) ...[
      _gap,
      _sectionHead('VITAL SIGNS'),
      _vitalsTable(r),
    ],

    _gap,
    ..._notesWidgets(r),

    _gap,
    _sectionHead('TREATMENTS ADMINISTERED'),
    _bodyText(v(r.treatments, '(none documented)')),

    _gap,
    _sectionHead('DISPOSITION'),
    _bodyText(v(r.disposition, '(not documented)')),

    if (r.notes.isNotEmpty) ...[
      _gap,
      _sectionHead('ADDITIONAL NOTES'),
      _bodyText(r.notes),
    ],

    if (r.bodyMarkers.isNotEmpty) ...[
      _gap,
      _sectionHead('INJURY LOCATIONS  (body diagram)'),
      _markersWidget(r),
    ],

    if (photos.isNotEmpty) ...[
      _gap,
      _sectionHead('ATTACHED PHOTOS  (${photos.length})'),
      _photosWidget(photos),
    ],
  ];
}


final _gap = pw.SizedBox(height: 10);

pw.Widget _sectionHead(String title) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const pw.BoxDecoration(color: _kAccentLight),
      child: pw.Text(title, style: _sH2),
    );

pw.Widget _bodyText(String text) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(text, style: _sBody),
    );


pw.Widget _patientTable(PatientReport r) {
  String v(String s, [String fb = '—']) => s.isEmpty ? fb : s;

  final rows = <List<String>>[
    ['Provider', v(r.provider), 'Unit / Agency', v(r.unit)],
    ['Age', v(r.age), 'Sex', v(r.sex)],
    ['Chief Complaint', v(r.chiefComplaint), 'Allergies', v(r.allergies, 'NKDA')],
    if (r.weight.isNotEmpty || r.broselowColor.isNotEmpty)
      ['Weight', v(r.weight), 'Broselow', v(r.broselowColor)],
    ['Report ID', r.id, 'Form Type', r.formType],
  ];

  pw.Widget lbl(String s) => pw.Container(
        color: _kAccentLight,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(s, style: _sLabelCell),
      );

  pw.Widget val(String s) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(s, style: _sBody),
      );

  return pw.Table(
    border: pw.TableBorder.all(color: _kGrid, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.3),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(1.3),
      3: pw.FlexColumnWidth(2),
    },
    children: rows.map((row) => pw.TableRow(children: [
          lbl(row[0]), val(row[1]),
          lbl(row[2]), val(row[3]),
        ])).toList(),
  );
}


pw.Widget _vitalsTable(PatientReport r) {
  const cols = ['Time', 'AVPU', 'GCS', 'BP', 'HR', 'RR', 'SpO2', 'Temp', 'BGL', 'Pain'];

  pw.Widget hdr(String s) => pw.Container(
        color: _kAccent,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(s, style: _sWhiteBold, textAlign: pw.TextAlign.center),
      );

  pw.Widget cell(String s, bool alt) => pw.Container(
        color: alt ? _kAltRow : null,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(s.isEmpty ? '—' : s, style: _sSmall, textAlign: pw.TextAlign.center),
      );

  return pw.Table(
    border: pw.TableBorder.all(color: _kGrid, width: 0.5),
    children: [
      pw.TableRow(children: cols.map(hdr).toList()),
      ...r.vitalSets.asMap().entries.map((e) {
        final vs = e.value;
        final alt = e.key.isOdd;
        return pw.TableRow(children: [
          cell(vs.timeLabel, alt),
          cell(vs.avpu, alt),
          cell(vs.gcs, alt),
          cell(vs.bp, alt),
          cell(vs.hr.isEmpty ? '' : '${vs.hr} bpm', alt),
          cell(vs.rr.isEmpty ? '' : '${vs.rr}/min', alt),
          cell(vs.spo2.isEmpty ? '' : '${vs.spo2}%', alt),
          cell(vs.temp, alt),
          cell(vs.glucose, alt),
          cell(vs.pain.isEmpty ? '' : '${vs.pain}/10', alt),
        ]);
      }),
    ],
  );
}


List<pw.Widget> _notesWidgets(PatientReport r) {
  String v(String s) => s.isEmpty ? '(not documented)' : s;

  if (r.formType == 'SOAP') {
    return [
      _sectionHead('SUBJECTIVE'), _bodyText(v(r.subjective)),
      _gap,
      _sectionHead('OBJECTIVE'), _bodyText(v(r.objective)),
      _gap,
      _sectionHead('ASSESSMENT'), _bodyText(v(r.assessment)),
      _gap,
      _sectionHead('PLAN'), _bodyText(v(r.plan)),
    ];
  }
  return [
    _sectionHead('INJURIES / SIGNS & SYMPTOMS'),
    _bodyText(v(r.injuries)),
  ];
}


pw.Widget _markersWidget(PatientReport r) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: r.bodyMarkers.asMap().entries.map((e) {
        final m = e.value;
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: pw.Text(
            '${e.key + 1}.  ${m.label}  [${m.side}]',
            style: _sBody,
          ),
        );
      }).toList(),
    );


pw.Widget _photosWidget(List<pw.MemoryImage> photos) {
  const perRow = 2;
  final rows = <pw.Widget>[];
  for (var i = 0; i < photos.length; i += perRow) {
    final slice = photos.sublist(i, (i + perRow).clamp(0, photos.length));
    rows.add(pw.Row(
      children: [
        for (final img in slice)
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.all(4),
              height: 180,
              child: pw.Image(img, fit: pw.BoxFit.contain),
            ),
          ),
        if (slice.length < perRow) pw.Expanded(child: pw.SizedBox()),
      ],
    ));
  }
  return pw.Column(children: rows);
}
