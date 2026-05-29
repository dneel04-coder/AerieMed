import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'patient_report.dart';
import 'report_pdf.dart';

// 20 000 iterations of SHA-256 hash-chain keyed on a fixed app salt.
// Produces a 256-bit key from an arbitrary passphrase.

const _kSalt = 'AustereMed_field_v1_2026_salt';

Uint8List _deriveKey(String passphrase) {
  List<int> material = utf8.encode('$_kSalt:$passphrase');
  for (var i = 0; i < 20000; i++) {
    material = sha256.convert(material).bytes;
  }
  return Uint8List.fromList(material);
}


class TeamEncryption {
  /// Encrypt [plaintext] with AES-256-GCM. Returns a JSON bundle string.
  static String encrypt(String plaintext, String passphrase) {
    final key = enc.Key(_deriveKey(passphrase));
    final iv = enc.IV.fromSecureRandom(12); // 96-bit IV is standard for GCM
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final result = encrypter.encrypt(plaintext, iv: iv);
    return jsonEncode({
      'version': 1,
      'alg': 'AES-256-GCM',
      'iv': iv.base64,
      'data': result.base64,
    });
  }

  /// Decrypt a bundle produced by [encrypt]. Throws on wrong key or tampered data.
  static String decrypt(String bundleJson, String passphrase) {
    final m = jsonDecode(bundleJson) as Map<String, dynamic>;
    if ((m['alg'] as String?) != 'AES-256-GCM') {
      throw const FormatException('Unsupported algorithm');
    }
    final key = enc.Key(_deriveKey(passphrase));
    final iv = enc.IV.fromBase64(m['iv'] as String);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    return encrypter.decrypt(enc.Encrypted.fromBase64(m['data'] as String), iv: iv);
  }
}


const _kTeamKeyPref = 'team_encryption_key';

Future<String?> _loadTeamKey() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kTeamKeyPref);
}

Future<void> _saveTeamKey(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kTeamKeyPref, key);
}


Future<String?> _requireTeamKey(BuildContext context) async {
  final existing = await _loadTeamKey();
  if (existing != null && existing.isNotEmpty) return existing;
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _TeamKeyDialog(isFirstTime: true),
  );
}


Future<void> exportEncryptedBundle(BuildContext context, PatientReport report) async {
  final teamKey = await _requireTeamKey(context);
  if (teamKey == null || teamKey.isEmpty) return;

  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  try {
    final reportJson = jsonEncode(report.toJson());
    final bundle = TeamEncryption.encrypt(reportJson, teamKey);

    final dir = await getTemporaryDirectory();
    final safeId = report.id.length > 8 ? report.id.substring(report.id.length - 8) : report.id;
    final filename = 'ResQruck_$safeId.ResQruck';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(bundle);

    final subject = 'ResQruck — ${report.patientId.isEmpty ? "Patient Report" : report.patientId}';
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream', name: filename)],
      subject: subject,
      text: 'Encrypted patient report from ResQruck. Open with ResQruck to import.',
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}


Future<void> importEncryptedBundle(BuildContext context, {required VoidCallback onImported}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.any,
    allowMultiple: false,
  );
  if (result == null || result.files.single.path == null) return;
  final path = result.files.single.path!;

  if (!context.mounted) return;

  // Prompt for team key
  final teamKey = await _requireTeamKey(context);
  if (teamKey == null || teamKey.isEmpty) return;

  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  try {
    final bundleJson = await File(path).readAsString();
    final reportJson = TeamEncryption.decrypt(bundleJson, teamKey);
    final report = PatientReport.fromJson(jsonDecode(reportJson) as Map<String, dynamic>);
    await ReportStorage.save(report);
    messenger.showSnackBar(const SnackBar(
      content: Text('Report imported successfully.'),
      backgroundColor: Colors.green,
    ));
    onImported();
  } on ArgumentError {
    messenger.showSnackBar(const SnackBar(
      content: Text('Decryption failed — wrong team key or corrupted file.'),
      backgroundColor: Colors.red,
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('Import failed: $e'),
      backgroundColor: Colors.red,
    ));
  }
}


class TransferOptionsSheet extends StatelessWidget {
  final PatientReport report;
  const TransferOptionsSheet({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(children: [
              Icon(Icons.send_outlined),
              SizedBox(width: 10),
              Text('Send / Export', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          const Divider(height: 1),
          _option(
            context,
            icon: Icons.lock_outlined,
            color: Colors.indigo,
            title: 'Secure Transfer (Encrypted)',
            subtitle: 'AES-256-GCM • Share via AirDrop, Bluetooth, or any channel',
            onTap: () async {
              Navigator.pop(context);
              await exportEncryptedBundle(context, report);
            },
          ),
          _option(
            context,
            icon: Icons.picture_as_pdf_outlined,
            color: Colors.red,
            title: 'Export PDF Report',
            subtitle: 'Clean printable format for incident documentation',
            onTap: () {
              Navigator.pop(context);
              generateAndSharePdf(context, report);
            },
          ),
          _option(
            context,
            icon: Icons.text_snippet_outlined,
            color: Colors.teal,
            title: 'Share as Text (MIST)',
            subtitle: 'Plain-text MIST report — not encrypted',
            onTap: () {
              Navigator.pop(context);
              SharePlus.instance.share(ShareParams(
                text: report.formattedText,
                subject: 'PCR — ${report.patientId.isEmpty ? report.id : report.patientId}',
              ));
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}


class _TeamKeyDialog extends StatefulWidget {
  final bool isFirstTime;
  const _TeamKeyDialog({required this.isFirstTime});

  @override
  State<_TeamKeyDialog> createState() => _TeamKeyDialogState();
}

class _TeamKeyDialogState extends State<_TeamKeyDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.lock_outline, size: 20),
        const SizedBox(width: 8),
        Text(widget.isFirstTime ? 'Set Team Key' : 'Change Team Key'),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'The team key encrypts all transferred reports. Everyone on the team must use the same key to share reports.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Team Key / Passphrase',
            hintText: 'e.g. AlphaMed2026',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 14, color: Colors.blue),
            SizedBox(width: 6),
            Expanded(child: Text('AES-256-GCM encryption • Key never transmitted', style: TextStyle(fontSize: 11))),
          ]),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final key = _ctrl.text.trim();
            if (key.isEmpty) return;
            final nav = Navigator.of(context);
            await _saveTeamKey(key);
            nav.pop(key);
          },
          child: const Text('Save & Use'),
        ),
      ],
    );
  }
}


class TeamKeyTile extends StatefulWidget {
  const TeamKeyTile({super.key});

  @override
  State<TeamKeyTile> createState() => _TeamKeyTileState();
}

class _TeamKeyTileState extends State<TeamKeyTile> {
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final k = await _loadTeamKey();
    if (mounted) setState(() => _hasKey = k != null && k.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _hasKey
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        child: Icon(_hasKey ? Icons.lock : Icons.lock_open,
            color: _hasKey ? Colors.green : Colors.orange, size: 20),
      ),
      title: const Text('Team Encryption Key'),
      subtitle: Text(_hasKey ? 'Key configured — reports can be encrypted' : 'No key set — tap to configure'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await showDialog(context: context, builder: (_) => const _TeamKeyDialog(isFirstTime: false));
        _check();
      },
    );
  }
}


// Import separately to avoid loading pdf/printing until needed

Future<void> generateAndSharePdf(BuildContext context, PatientReport report) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildReportPdf(report);
    final filename = 'ResQruck_${report.patientId.isEmpty ? report.id : report.patientId.replaceAll(' ', '_')}.pdf';
    await _printingSharePdf(bytes, filename);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('PDF generation failed: $e')));
  }
}

Future<void> generateAndPreviewPdf(BuildContext context, PatientReport report) async {
  try {
    final bytes = await buildReportPdf(report);
    await _printingLayoutPdf(bytes);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF preview failed: $e')));
    }
  }
}

// These are wrapped so the pdf/printing imports stay in report_pdf.dart
Future<void> _printingSharePdf(Uint8List bytes, String filename) async {
  await _ReportPdfBridge.share(bytes, filename);
}

Future<void> _printingLayoutPdf(Uint8List bytes) async {
  await _ReportPdfBridge.preview(bytes);
}

// Bridge class — keeps printing calls in one place
class _ReportPdfBridge {
  static Future<void> share(Uint8List bytes, String filename) =>
      ReportPdfGenerator.share(bytes, filename);
  static Future<void> preview(Uint8List bytes) =>
      ReportPdfGenerator.preview(bytes);
}
