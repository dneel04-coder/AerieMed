import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared building blocks for rendering government/agency-form-style PDFs --
/// bordered, numbered-block grids matching paper forms like OF-297, ICS 213,
/// ICS 214, ICS 205, and SF-261 -- factored out of shift_ticket_pdf.dart (the
/// first form built this way) so each additional form doesn't re-implement
/// the same cell/table/signature styling and layout quirks.

final formTitleStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
final formBoxHeaderStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
final formLabelStyle = pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700);
const formValueStyle = pw.TextStyle(fontSize: 8.5);
final formTableHeaderStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
const formTableCellStyle = pw.TextStyle(fontSize: 7.5);
final formInstructionStyle = pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic);
const formSmallStyle = pw.TextStyle(fontSize: 7);
final formBorder = pw.Border.all(width: 0.75);

pw.Widget formSectionHeader(String title) => pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(color: PdfColors.grey300, border: formBorder),
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: pw.Center(child: pw.Text(title, style: formBoxHeaderStyle)),
    );

pw.Widget formCheckboxLabel(String label, bool checked) => pw.Row(
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
        pw.Text(label, style: formTableHeaderStyle),
      ],
    );

/// A single bordered strip split into vertically-divided segments (a right
/// border on every segment but the last) -- for a paper form's bands that
/// are one bordered row internally split into several fields, rather than
/// independent boxed cells.
pw.Widget formDividedRow(List<pw.Widget> segments, {List<int>? flexes}) => pw.Container(
      decoration: pw.BoxDecoration(border: formBorder),
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
/// its own [formCell] flex -- mirrors a paper form's numbered boxed fields.
/// Note: no CrossAxisAlignment.stretch here -- this package's Row computes
/// unbounded cross-axis (height) for stretch when used inside a MultiPage's
/// vertically-flowing content, which throws ("height Infinity exceeds a
/// page height"). Cells with uneven content just end up mismatched by a
/// couple points instead, which is a fine trade for not crashing PDF
/// generation.
pw.Widget formGridRow(List<pw.Widget> cells) => pw.Row(children: cells);

pw.Widget formCell(String label, String value, {int flex = 1}) => pw.Expanded(
      flex: flex,
      child: pw.Container(
        decoration: pw.BoxDecoration(border: formBorder),
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: formLabelStyle),
          pw.SizedBox(height: 2),
          pw.Text(value, style: formValueStyle),
        ]),
      ),
    );

/// Same box style as [formCell] but for a drawn ("Tap to Sign") signature --
/// renders the captured PNG in place of a text value, or stays blank
/// (matching an unsigned paper form) when [signatureImage] is null. A fixed
/// height keeps the Column bounded, which is required for pw.Expanded to
/// lay out the image safely inside it.
pw.Widget formSignatureCell(String label, Uint8List? signatureImage, {int flex = 1, double height = 44}) =>
    pw.Expanded(
      flex: flex,
      child: pw.Container(
        height: height,
        decoration: pw.BoxDecoration(border: formBorder),
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: formLabelStyle),
          pw.SizedBox(height: 2),
          if (signatureImage != null)
            pw.Expanded(
              child: pw.Image(pw.MemoryImage(signatureImage),
                  fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft),
            ),
        ]),
      ),
    );

pw.Widget formTableHeaderCell(String text) => pw.Container(
      color: PdfColors.grey300,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      alignment: pw.Alignment.center,
      child: pw.Text(text, style: formTableHeaderStyle, textAlign: pw.TextAlign.center),
    );

pw.Widget formTableCell(String text) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(text, style: formTableCellStyle),
    );

/// A plain bordered box for a free-text block (Remarks, Message, Reply,
/// Special Instructions, etc.) with a fixed height matching a paper form's
/// blank writing area.
pw.Widget formTextBox(String value, {double height = 50}) => pw.Container(
      width: double.infinity,
      height: height,
      decoration: pw.BoxDecoration(border: formBorder),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(value, style: formValueStyle),
    );
