import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'protocol_admin.dart' show SupabaseService;


enum CertStatus { ok, warningSix, warning30, expired, unknown }

class UserCert {
  final String id;
  final String licenseType;
  final String state;
  final String filePath;
  final String originalFileName;
  final DateTime uploadedAt;
  final DateTime? expirationDate;

  const UserCert({
    required this.id,
    required this.licenseType,
    required this.state,
    required this.filePath,
    required this.originalFileName,
    required this.uploadedAt,
    this.expirationDate,
  });

  bool get isPdf => filePath.toLowerCase().endsWith('.pdf');

  CertStatus get expirationStatus {
    if (expirationDate == null) return CertStatus.unknown;
    final days = expirationDate!.difference(DateTime.now()).inDays;
    if (days < 0) return CertStatus.expired;
    if (days <= 30) return CertStatus.warning30;
    if (days <= 180) return CertStatus.warningSix;
    return CertStatus.ok;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'licenseType': licenseType,
        'state': state,
        'filePath': filePath,
        'originalFileName': originalFileName,
        'uploadedAt': uploadedAt.toIso8601String(),
        if (expirationDate != null) 'expirationDate': expirationDate!.toIso8601String(),
      };

  factory UserCert.fromJson(Map<String, dynamic> j) => UserCert(
        id: j['id'] as String,
        licenseType: j['licenseType'] as String,
        state: j['state'] as String,
        filePath: j['filePath'] as String,
        originalFileName: j['originalFileName'] as String,
        uploadedAt: DateTime.parse(j['uploadedAt'] as String),
        expirationDate: j['expirationDate'] != null
            ? DateTime.tryParse(j['expirationDate'] as String)
            : null,
      );
}


const List<String> kCertTypes = [
  'CPR/AED',
  'BLS',
  'ACLS',
  'PALS',
  'PHTLS',
  'ITLS',
  'TCCC',
  'EMR',
  'EMT',
  'AEMT',
  'Paramedic',
  'NREMT',
  'RN',
  'LPN',
  'NP',
  'PA',
  'MD/DO',
  'Other',
];

const List<String> kUsStates = [
  'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado',
  'Connecticut', 'Delaware', 'Florida', 'Georgia', 'Hawaii', 'Idaho',
  'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky', 'Louisiana',
  'Maine', 'Maryland', 'Massachusetts', 'Michigan', 'Minnesota',
  'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada',
  'New Hampshire', 'New Jersey', 'New Mexico', 'New York',
  'North Carolina', 'North Dakota', 'Ohio', 'Oklahoma', 'Oregon',
  'Pennsylvania', 'Rhode Island', 'South Carolina', 'South Dakota',
  'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia', 'Washington',
  'West Virginia', 'Wisconsin', 'Wyoming', 'District of Columbia',
];

const Map<String, String> _stateAbbr = {
  'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas',
  'CA': 'California', 'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware',
  'FL': 'Florida', 'GA': 'Georgia', 'HI': 'Hawaii', 'ID': 'Idaho',
  'IL': 'Illinois', 'IN': 'Indiana', 'IA': 'Iowa', 'KS': 'Kansas',
  'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland',
  'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota', 'MS': 'Mississippi',
  'MO': 'Missouri', 'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada',
  'NH': 'New Hampshire', 'NJ': 'New Jersey', 'NM': 'New Mexico', 'NY': 'New York',
  'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio', 'OK': 'Oklahoma',
  'OR': 'Oregon', 'PA': 'Pennsylvania', 'RI': 'Rhode Island', 'SC': 'South Carolina',
  'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah',
  'VT': 'Vermont', 'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia',
  'WI': 'Wisconsin', 'WY': 'Wyoming', 'DC': 'District of Columbia',
};


class _CertStorage {
  static const _key = 'user_certs_v1';

  static Future<List<UserCert>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list
        .map((e) {
          try {
            return UserCert.fromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<UserCert>()
        .toList();
  }

  static Future<void> save(List<UserCert> certs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, certs.map((c) => jsonEncode(c.toJson())).toList());
  }
}


class CertSyncer {
  static Future<void> _trySyncCert(
      UserCert cert, String userId, String callsign) async {
    final client = SupabaseService.client;
    if (client == null) return;
    final ext = cert.filePath.contains('.')
        ? cert.filePath.split('.').last.toLowerCase()
        : 'jpg';
    final storagePath = '$userId/${cert.id}.$ext';

    // Delete old Supabase rows for this user + cert type + state before uploading.
    try {
      final oldRows = await client
          .from('team_certs')
          .select('id, file_path')
          .eq('user_id', userId)
          .eq('license_type', cert.licenseType)
          .eq('state', cert.state)
          .neq('id', cert.id) as List;
      for (final old in oldRows) {
        final oldPath = old['file_path'] as String? ?? '';
        if (oldPath.isNotEmpty) {
          try { await client.storage.from('certs').remove([oldPath]); } catch (_) {}
        }
        try { await client.from('team_certs').delete().eq('id', old['id']); } catch (_) {}
      }
    } catch (_) {}

    // Storage upload is best-effort — if the bucket doesn't exist yet the
    // metadata row still gets written so the cert appears in the admin panel.
    try {
      final bytes = await File(cert.filePath).readAsBytes();
      final contentType = cert.isPdf ? 'application/pdf' : 'image/jpeg';
      await client.storage.from('certs').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
    } catch (_) {}

    // Always upsert metadata regardless of storage outcome.
    try {
      await client.from('team_certs').upsert({
        'id': cert.id,
        'user_id': userId,
        'callsign': callsign,
        'license_type': cert.licenseType,
        'state': cert.state,
        'original_file_name': cert.originalFileName,
        'uploaded_at': cert.uploadedAt.toIso8601String(),
        'file_path': storagePath,
        'expiration_date': cert.expirationDate != null
            ? '${cert.expirationDate!.year}-${cert.expirationDate!.month.toString().padLeft(2,'0')}-${cert.expirationDate!.day.toString().padLeft(2,'0')}'
            : null,
      }, onConflict: 'id');
    } catch (_) {}
  }

  static Future<void> syncAll(List<UserCert> certs) async {
    await SupabaseService.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString('tac_user_id');
    if (userId == null) {
      final rng = Random.secure();
      userId =
          List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString('tac_user_id', userId);
    }
    final callsign = prefs.getString('tac_callsign') ?? 'Unknown';
    for (final cert in certs) {
      await _trySyncCert(cert, userId, callsign);
    }
  }
}

// Only called on Android/iOS — Windows falls back to manual entry.

Future<String?> _runOcr(String imagePath) async {
  if (!Platform.isAndroid && !Platform.isIOS) return null;
  try {
    final recognizer = TextRecognizer();
    final image = InputImage.fromFilePath(imagePath);
    final result = await recognizer.processImage(image);
    await recognizer.close();
    return result.text.trim().isEmpty ? null : result.text;
  } catch (_) {
    return null;
  }
}


class _CertParser {
  static String? parseType(String text) {
    final u = text.toUpperCase();
    const ordered = <String, List<String>>{
      'Paramedic': ['PARAMEDIC', 'EMT-PARAMEDIC', 'EMT-P', 'NREMT-P'],
      'NREMT':     ['NATIONAL REGISTRY'],
      'AEMT':      ['ADVANCED EMERGENCY MEDICAL TECHNICIAN', 'ADVANCED EMT', 'AEMT', 'EMT-INTERMEDIATE', 'EMT-I'],
      'EMT':       ['EMERGENCY MEDICAL TECHNICIAN', 'EMT-BASIC', 'EMT-B'],
      'EMR':       ['EMERGENCY MEDICAL RESPONDER', 'FIRST RESPONDER'],
      'ACLS':      ['ADVANCED CARDIAC LIFE SUPPORT', 'ADVANCED CARDIOVASCULAR LIFE SUPPORT', 'ACLS'],
      'PALS':      ['PEDIATRIC ADVANCED LIFE SUPPORT', 'PALS'],
      'PHTLS':     ['PRE-HOSPITAL TRAUMA LIFE SUPPORT', 'PHTLS'],
      'ITLS':      ['INTERNATIONAL TRAUMA LIFE SUPPORT', 'ITLS'],
      'TCCC':      ['TACTICAL COMBAT CASUALTY CARE', 'TCCC'],
      'BLS':       ['BASIC LIFE SUPPORT', 'BLS'],
      'CPR/AED':   ['CARDIOPULMONARY RESUSCITATION', 'CPR'],
      'RN':        ['REGISTERED NURSE'],
      'LPN':       ['LICENSED PRACTICAL NURSE'],
      'NP':        ['NURSE PRACTITIONER'],
      'PA':        ['PHYSICIAN ASSISTANT'],
      'MD/DO':     ['MEDICAL DOCTOR', 'PHYSICIAN'],
    };
    for (final entry in ordered.entries) {
      for (final kw in entry.value) {
        if (u.contains(kw)) return entry.key;
      }
    }
    // Short-token fallbacks with word boundaries
    for (final tok in ['NREMT', 'AEMT', 'EMT', 'EMR', 'ACLS', 'PALS', 'PHTLS', 'ITLS', 'TCCC', 'BLS']) {
      if (RegExp(r'\b' + tok + r'\b').hasMatch(u)) return tok;
    }
    return null;
  }

  static String? parseState(String text) {
    final u = text.toUpperCase();
    // "State of ___" pattern
    final m = RegExp(r'STATE\s+OF\s+([A-Z][A-Z\s]+)', caseSensitive: false).firstMatch(u);
    if (m != null) {
      final candidate = _title(m.group(1)!.trim());
      if (kUsStates.contains(candidate)) return candidate;
    }
    // Full state name
    for (final s in kUsStates) {
      if (u.contains(s.toUpperCase())) return s;
    }
    // Two-letter abbreviation (word boundary)
    for (final e in _stateAbbr.entries) {
      if (RegExp(r'\b' + e.key + r'\b').hasMatch(u)) return e.value;
    }
    return null;
  }

  static String _title(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

  static DateTime? parseExpiration(String text) {
    final now = DateTime.now();
    // Try labeled patterns first: EXP, EXPIR, EXPIRATION, EXPIRES, VALID THROUGH, VALID UNTIL
    final labeled = RegExp(
      r'(?:exp(?:ir(?:ation|es?)?)?|valid\s+(?:through|until))[:\s]*'
      r'(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2}|'
      r'\d{1,2}[\/\-]\d{4}|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s,]+\d{1,2}[\s,]+\d{4})',
      caseSensitive: false,
    );
    for (final m in labeled.allMatches(text)) {
      final d = _parseRaw(m.group(1)!);
      if (d != null && d.isAfter(now.subtract(const Duration(days: 365 * 5)))) return d;
    }
    // Fall back to any date-like token that looks like a future/recent expiry
    final bare = RegExp(
      r'\b(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})\b');
    for (final m in bare.allMatches(text)) {
      final d = _parseRaw(m.group(1)!);
      if (d != null && d.isAfter(now)) return d; // only future dates as expiry candidates
    }
    return null;
  }

  static final _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _parseRaw(String s) {
    s = s.trim();
    try {
      // Month name: "March 15, 2027" or "Mar 2027"
      final named = RegExp(r'^([a-z]+)[,\s]+(\d{1,2})?[,\s]*(\d{4})$', caseSensitive: false);
      final nm = named.firstMatch(s);
      if (nm != null) {
        final mo = _months[nm.group(1)!.substring(0, 3).toLowerCase()];
        final day = int.tryParse(nm.group(2) ?? '1') ?? 1;
        final yr = int.tryParse(nm.group(3)!)!;
        if (mo != null) return DateTime(yr, mo, day);
      }
      // ISO: 2027-03-15
      if (RegExp(r'^\d{4}[-\/]\d{1,2}[-\/]\d{1,2}$').hasMatch(s)) {
        return DateTime.tryParse(s.replaceAll('/', '-'));
      }
      final parts = s.split(RegExp(r'[\/\-]'));
      if (parts.length == 3) {
        var a = int.parse(parts[0]), b = int.parse(parts[1]);
        var y = int.parse(parts[2]);
        if (y < 100) y += 2000;
        // MM/DD/YYYY
        if (a <= 12 && b <= 31) return DateTime(y, a, b);
      }
      if (parts.length == 2) {
        var mo = int.parse(parts[0]), y = int.parse(parts[1]);
        if (y < 100) y += 2000;
        if (mo >= 1 && mo <= 12) return DateTime(y, mo, 1);
      }
    } catch (_) {}
    return null;
  }
}


class CertVaultScreen extends StatefulWidget {
  const CertVaultScreen({super.key});

  @override
  State<CertVaultScreen> createState() => _CertVaultScreenState();
}

class _CertVaultScreenState extends State<CertVaultScreen> {
  List<UserCert> _certs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final certs = await _CertStorage.load();
    if (mounted) setState(() { _certs = certs; _loading = false; });
  }

  Future<void> _addCert() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _showMobileSourceSheet();
    } else {
      await _pickFile();
    }
  }

  Future<void> _showMobileSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () { Navigator.pop(context); _captureCamera(); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(context); _pickGallery(); },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Browse Files (PDF / Image)'),
              onTap: () { Navigator.pop(context); _pickFile(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureCamera() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (x != null) await _process(x.path, x.name, isImage: true);
  }

  Future<void> _pickGallery() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x != null) await _process(x.path, x.name, isImage: true);
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
    );
    if (r != null && r.files.single.path != null) {
      final f = r.files.single;
      final ext = (f.extension ?? '').toLowerCase();
      await _process(f.path!, f.name, isImage: ext != 'pdf');
    }
  }

  Future<void> _process(String src, String name, {required bool isImage}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final vault = Directory('${dir.path}/cert_vault');
      if (!await vault.exists()) await vault.create(recursive: true);

      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final ext = name.contains('.') ? name.split('.').last : 'jpg';
      final dest = '${vault.path}/${id}_cert.$ext';
      await File(src).copy(dest);

      String? ocr;
      if (isImage) ocr = await _runOcr(dest);

      final autoType       = ocr != null ? _CertParser.parseType(ocr)       : null;
      final autoState      = ocr != null ? _CertParser.parseState(ocr)      : null;
      final autoExpiration = ocr != null ? _CertParser.parseExpiration(ocr) : null;

      if (!mounted) return;
      setState(() => _loading = false);

      String?   chosenType       = autoType;
      String?   chosenState      = autoState;
      DateTime? chosenExpiration = autoExpiration;

      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ConfirmDialog(
          filePath: dest,
          isImage: isImage,
          initialType: autoType,
          initialState: autoState,
          initialExpiration: autoExpiration,
          onSave: (t, s, exp) { chosenType = t; chosenState = s; chosenExpiration = exp; },
        ),
      );

      if (saved == true && chosenType != null && chosenState != null) {
        final cert = UserCert(
          id: id,
          licenseType: chosenType!,
          state: chosenState!,
          filePath: dest,
          originalFileName: name,
          uploadedAt: DateTime.now(),
          expirationDate: chosenExpiration,
        );
        // Replace an existing cert only when both type AND state match.
        final oldCerts = _certs
            .where((c) => c.licenseType == cert.licenseType && c.state == cert.state)
            .toList();
        for (final old in oldCerts) {
          try { await File(old.filePath).delete(); } catch (_) {}
        }
        setState(() {
          _certs.removeWhere((c) => c.licenseType == cert.licenseType && c.state == cert.state);
          _certs.add(cert);
        });
        await _CertStorage.save(_certs);
        CertSyncer.syncAll(_certs); // fire-and-forget
      } else {
        try { await File(dest).delete(); } catch (_) {}
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _delete(UserCert cert) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Certification?'),
        content: Text('Remove ${cert.licenseType} — ${cert.state}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try { await File(cert.filePath).delete(); } catch (_) {}
      setState(() => _certs.removeWhere((c) => c.id == cert.id));
      await _CertStorage.save(_certs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cert Vault'),
        actions: [
          if (_certs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Sync to Team',
              onPressed: _loading ? null : () async {
                final messenger = ScaffoldMessenger.of(context);
                await CertSyncer.syncAll(_certs);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Certs synced to team')),
                  );
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Certification',
            onPressed: _loading ? null : _addCert,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _certs.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _certs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _CertCard(
                    cert: _certs[i],
                    onView: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => _DetailScreen(cert: _certs[i]))),
                    onDelete: () => _delete(_certs[i]),
                  ),
                ),
      floatingActionButton: _certs.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _loading ? null : _addCert,
              tooltip: 'Add Certification',
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspace_premium, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No certifications added',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Upload a license or certification card',
                style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addCert,
              icon: const Icon(Icons.upload_file),
              label: const Text('Add Certification'),
            ),
          ],
        ),
      );
}


class _CertCard extends StatelessWidget {
  final UserCert cert;
  final VoidCallback onView;
  final VoidCallback onDelete;

  const _CertCard({required this.cert, required this.onView, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cert.licenseType,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 2),
                      Flexible(
                          child: Text(cert.state,
                              style:
                                  TextStyle(color: Colors.grey[600], fontSize: 13))),
                    ]),
                    const SizedBox(height: 2),
                    if (cert.expirationDate != null)
                      _ExpirationBadge(cert: cert)
                    else
                      Text('Uploaded ${_fmt(cert.uploadedAt)}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.visibility_outlined),
                      tooltip: 'View',
                      onPressed: onView),
                  IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Delete',
                      onPressed: onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 64,
        child: cert.isPdf
            ? Container(
                color: Colors.red[50],
                child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 36))
            : Image.file(
                File(cert.filePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[200],
                    child:
                        const Icon(Icons.image_outlined, color: Colors.grey, size: 36)),
              ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
}


class _ExpirationBadge extends StatelessWidget {
  final UserCert cert;
  const _ExpirationBadge({required this.cert});

  @override
  Widget build(BuildContext context) {
    final exp = cert.expirationDate!;
    final days = exp.difference(DateTime.now()).inDays;
    final Color color;
    final String label;
    final IconData icon;
    if (days < 0) {
      color = Colors.red;
      label = 'Expired ${_fmt(exp)}';
      icon = Icons.cancel_outlined;
    } else if (days <= 30) {
      color = Colors.red;
      label = 'Expires in $days day${days == 1 ? '' : 's'} (${_fmt(exp)})';
      icon = Icons.warning_amber_rounded;
    } else if (days <= 180) {
      color = Colors.orange;
      label = 'Expires ${_fmt(exp)} (~${(days / 30).round()} mo)';
      icon = Icons.warning_amber_rounded;
    } else {
      color = Colors.green;
      label = 'Exp: ${_fmt(exp)}';
      icon = Icons.check_circle_outline;
    }
    return Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 3),
      Flexible(child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))),
    ]);
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
}


class _DetailScreen extends StatelessWidget {
  final UserCert cert;
  const _DetailScreen({required this.cert});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(cert.licenseType)),
      body: Column(
        children: [
          Expanded(child: _viewer()),
          _metaBar(context),
        ],
      ),
    );
  }

  Widget _viewer() {
    if (cert.isPdf) {
      return PdfViewer.file(cert.filePath);
    }
    final file = File(cert.filePath);
    return InteractiveViewer(
      child: Center(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, size: 80, color: Colors.grey)),
        ),
      ),
    );
  }

  Widget _metaBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: cs.surfaceContainerHighest,
      child: Wrap(
        spacing: 24,
        runSpacing: 4,
        children: [
          _chip(context, Icons.workspace_premium, cert.licenseType),
          _chip(context, Icons.location_on_outlined, cert.state),
          _chip(context, Icons.calendar_today_outlined,
              '${cert.uploadedAt.month}/${cert.uploadedAt.day}/${cert.uploadedAt.year}'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}


class _ConfirmDialog extends StatefulWidget {
  final String filePath;
  final bool isImage;
  final String? initialType;
  final String? initialState;
  final DateTime? initialExpiration;
  final void Function(String type, String state, DateTime? expiration) onSave;

  const _ConfirmDialog({
    required this.filePath,
    required this.isImage,
    required this.initialType,
    required this.initialState,
    required this.onSave,
    this.initialExpiration,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  String?   _type;
  String?   _state;
  DateTime? _expiration;

  @override
  void initState() {
    super.initState();
    _type       = widget.initialType;
    _state      = widget.initialState;
    _expiration = widget.initialExpiration;
  }

  bool get _ready => _type != null && _state != null;

  @override
  Widget build(BuildContext context) {
    final autoDetected = widget.initialType != null || widget.initialState != null;
    final mobileNoOcr  = (Platform.isAndroid || Platform.isIOS) &&
        widget.isImage && !autoDetected;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Certification Details',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _statusBanner(autoDetected, mobileNoOcr),
            // Image preview
            if (widget.isImage) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Image.file(File(widget.filePath),
                      width: double.infinity, fit: BoxFit.contain),
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                  labelText: 'License / Cert Type *',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: kCertTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _state,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Issuing State *',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: kUsStates
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _state = v),
            ),
            const SizedBox(height: 12),
            // Expiration date picker
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_expiration == null
                  ? 'Set Expiration Date (optional)'
                  : 'Expires: ${_expiration!.month}/${_expiration!.day}/${_expiration!.year}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _expiration == null ? null : Colors.orange,
                side: BorderSide(
                    color: _expiration == null
                        ? Colors.grey.shade400
                        : Colors.orange),
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expiration ?? DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2050),
                );
                if (picked != null) setState(() => _expiration = picked);
              },
            ),
            if (_expiration != null)
              TextButton(
                onPressed: () => setState(() => _expiration = null),
                child: const Text('Clear expiration date',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _ready
                      ? () {
                          widget.onSave(_type!, _state!, _expiration);
                          Navigator.pop(context, true);
                        }
                      : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner(bool autoDetected, bool mobileNoOcr) {
    if (autoDetected) {
      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green[200]!)),
        child: Row(children: [
          Icon(Icons.auto_awesome, size: 15, color: Colors.green[700]),
          const SizedBox(width: 6),
          Flexible(
              child: Text('Auto-detected from scan — review and confirm.',
                  style: TextStyle(color: Colors.green[800], fontSize: 13))),
        ]),
      );
    }
    if (mobileNoOcr) {
      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.orange[200]!)),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: Colors.orange[700]),
          const SizedBox(width: 6),
          Flexible(
              child: Text('Could not auto-detect. Please fill in manually.',
                  style: TextStyle(color: Colors.orange[800], fontSize: 13))),
        ]),
      );
    }
    return const SizedBox.shrink();
  }
}
