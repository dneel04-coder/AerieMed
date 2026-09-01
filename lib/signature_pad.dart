import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A finger/mouse-drawn signature capture ("Tap to Sign"). Strokes are
/// rendered on a white canvas and exported as PNG bytes via a
/// RepaintBoundary -- the standard Flutter widget-to-image pattern -- so the
/// result can be embedded directly as an image in a generated PDF.
class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

class _SignatureCanvas extends StatefulWidget {
  final GlobalKey boundaryKey;
  const _SignatureCanvas({super.key, required this.boundaryKey});

  @override
  State<_SignatureCanvas> createState() => _SignatureCanvasState();
}

class _SignatureCanvasState extends State<_SignatureCanvas> {
  final List<List<Offset>> _strokes = [];

  bool get isEmpty => _strokes.isEmpty;

  void clear() => setState(() => _strokes.clear());

  void _onPanStart(DragStartDetails d) {
    setState(() => _strokes.add([d.localPosition]));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _strokes.last.add(d.localPosition));
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: widget.boundaryKey,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        child: Container(
          color: Colors.white,
          width: double.infinity,
          height: double.infinity,
          child: CustomPaint(painter: _SignaturePainter(_strokes)),
        ),
      ),
    );
  }
}

/// Shows a "Tap to Sign" dialog. Returns PNG bytes of the drawn signature on
/// Done, or null if the user cancels. An empty (untouched) canvas cannot be
/// confirmed -- Done stays disabled until at least one stroke is drawn.
Future<Uint8List?> showSignatureDialog(BuildContext context, {String title = 'Sign Here'}) async {
  final boundaryKey = GlobalKey();
  final canvasKey = GlobalKey<_SignatureCanvasState>();

  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        content: SizedBox(
          width: 420,
          height: 220,
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
            child: _SignatureCanvas(key: canvasKey, boundaryKey: boundaryKey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              canvasKey.currentState?.clear();
              setDialogState(() {});
            },
            child: const Text('Clear'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (canvasKey.currentState?.isEmpty ?? true) return;
              final boundary =
                  boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
              if (boundary == null) {
                Navigator.pop(ctx);
                return;
              }
              final image = await boundary.toImage(pixelRatio: 3.0);
              final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
              if (ctx.mounted) Navigator.pop(ctx, byteData?.buffer.asUint8List());
            },
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}

/// A signature field for a form: shows a bordered "Tap to Sign" placeholder,
/// or a thumbnail of the captured signature with a clear (X) action once
/// signed. [onChanged] fires with the new PNG bytes, or null when cleared.
class SignatureField extends StatelessWidget {
  final String label;
  final Uint8List? signatureBytes;
  final ValueChanged<Uint8List?> onChanged;

  const SignatureField({
    super.key,
    required this.label,
    required this.signatureBytes,
    required this.onChanged,
  });

  Future<void> _tap(BuildContext context) async {
    final bytes = await showSignatureDialog(context, title: label);
    if (bytes != null) onChanged(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      InkWell(
        onTap: () => _tap(context),
        child: Container(
          height: 64,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: signatureBytes == null
              ? const Center(
                  child: Text('Tap to Sign', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                )
              : Stack(children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(signatureBytes!, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear signature',
                      onPressed: () => onChanged(null),
                    ),
                  ),
                ]),
        ),
      ),
    ]);
  }
}
