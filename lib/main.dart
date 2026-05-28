import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'patient_report.dart';
import 'decision_tree.dart';
import 'drug_reference.dart';
import 'procedure_checklist.dart';
import 'differential_dx.dart';
import 'dosing_calculator.dart';
import 'protocol_version.dart';
import 'gps_tools.dart';
import 'offline_maps.dart';
import 'lz_assessment.dart';
import 'sun_weather.dart';
import 'team_command.dart';
import 'mci_triage.dart';
import 'cert_vault.dart';
import 'tac_map.dart';
import 'protocol_admin.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the Android navigation bar (edge-to-edge)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const AustereMedApp());
}

class AustereMedApp extends StatefulWidget {
  const AustereMedApp({super.key});

  @override
  State<AustereMedApp> createState() => _AustereMedAppState();
}

class _AustereMedAppState extends State<AustereMedApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode');
    if (isDark != null) {
      setState(() {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AustereMed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      // Prevent content from going under the Android navigation bar on all screens
      builder: (context, child) => SafeArea(top: false, child: child!),
      home: TableOfContentsScreen(onThemeToggle: toggleTheme),
    );
  }
}

class TableOfContentsScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const TableOfContentsScreen({super.key, required this.onThemeToggle});

  @override
  State<TableOfContentsScreen> createState() => _TableOfContentsScreenState();
}

class _TableOfContentsScreenState extends State<TableOfContentsScreen> {
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Set<String> favorites = {};
  List<Map<String, String>> userUploads = [];
  bool _isAdmin = false;

  final Map<String, Map<String, dynamic>> medicationData = {
    'Acetaminophen': {'types': ['Pain Management'], 'abc': []},
    'Adenosine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Albuterol': {'types': ['Respiratory'], 'abc': ['breathing']},
    'Amiodarone': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Aspirin': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Atropine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Calcium Chloride': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Dexamethasone': {'types': ['Allergy & Anaphylaxis', 'Respiratory'], 'abc': ['breathing']},
    'Diphenhydramine': {'types': ['Allergy & Anaphylaxis'], 'abc': []},
    'Droperidol': {'types': ['Sedation & Seizure'], 'abc': []},
    'Duo-Dote': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Epinephrine': {'types': ['Allergy & Anaphylaxis', 'Respiratory', 'Cardiac & Circulation'], 'abc': ['breathing', 'circulation']},
    'Fentanyl': {'types': ['Pain Management'], 'abc': []},
    'Glucagon': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Glucose Gel': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Hydromorphone': {'types': ['Pain Management'], 'abc': []},
    'Ipratropium': {'types': ['Respiratory'], 'abc': ['breathing']},
    'Ketamine': {'types': ['Pain Management', 'Sedation & Seizure'], 'abc': ['airway']},
    'Ketorolac': {'types': ['Pain Management'], 'abc': []},
    'Lidocaine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Magnesium Sulfate': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Metoprolol': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Methylprednisolone': {'types': ['Allergy & Anaphylaxis', 'Respiratory'], 'abc': ['breathing']},
    'Midazolam': {'types': ['Sedation & Seizure'], 'abc': ['airway']},
    'Naloxone': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Nitroglycerin': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Norepinephrine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Ondansetron': {'types': ['Others'], 'abc': []},
    'Prednisone': {'types': ['Allergy & Anaphylaxis', 'Respiratory'], 'abc': ['breathing']},
    'Rocuronium': {'types': ['Others'], 'abc': ['airway']},
    'Sodium Bicarbonate': {'types': ['Cardiac & Circulation', 'Antidotes & Metabolic'], 'abc': ['circulation']},
    'Tetracaine': {'types': ['Others'], 'abc': []},
    'Tranexamic Acid': {'types': ['Others'], 'abc': ['circulation']},
  };

  final List<Map<String, dynamic>> staticCategories = [
    {
      'title': 'Appendix Material',
      'items': [
        {'title': 'EXPANDED SCOPE - california version', 'asset': 'EXPANDED SCOPE - california version.pdf'},
        {'title': 'Igel - Ideal Body Weight Chart', 'asset': 'Igel - Ideal Body Weight Chart.pdf'},
        {'title': 'APGAR', 'asset': 'APGAR.pdf'},
        {'title': 'Glasgow Coma Scale', 'asset': 'GCS.pdf'},
        {'title': 'Pediatric Normal Vital Signs', 'asset': 'Pediatric Normal Vital Signs.pdf'},
        {'title': 'Pain Rating Scales', 'asset': 'Pain Rating Scales.pdf'},
        {'title': 'Sedation Score', 'asset': 'Sedation Score.pdf'},
        {'title': 'Acceptable Abbreviations for PCR', 'asset': 'Acceptable Abbreviations for PCR.pdf'},
        {'title': 'Stroke Alert Criteria', 'asset': 'Stroke Alert Criteria.pdf'},
        {'title': 'Respiratory Treatments Guide', 'asset': 'Respiratory Treatments Guide.pdf'},
      ]
    },
    {
      'title': 'Procedures',
      'items': [
        {'title': 'Synchronized Cardioversion', 'asset': 'Synchronized Cardioversion.pdf'},
        {'title': 'Transcutaneous Pacing', 'asset': 'Transcutaneous Pacing.pdf'},
        {'title': 'Nasogastric and Orogastric Tubes', 'asset': 'Nasogastric and Orogastric Tubes.pdf'},
        {'title': 'Failed Airway', 'asset': 'Failed Airway.pdf'},
        {'title': 'Finger Thoracostomy Procedure', 'asset': 'Finger Thoracostomy Procedure.pdf'},
        {'title': 'Needle Cricothyrotomy', 'asset': 'Needle Cricothyrotomy.pdf'},
        {'title': 'EZ IO Procedure', 'asset': 'EZ IO Procedure.pdf'},
        {'title': 'Noninvasive Ventilation', 'asset': 'Noninvasive Ventilation.pdf'},
        {'title': 'Needle Thoracostomy Procedure', 'asset': 'Needle Thoracostomy Procedure.pdf'},
        {'title': 'Supraglottic Airway Management - iGel', 'asset': 'Supraglottic Airway Management - iGel.pdf'},
        {'title': 'Surgical Cricothyrotomy', 'asset': 'Surgical Cricothyrotomy.pdf'},
        {'title': 'Ventilation Procedure', 'asset': 'Ventilation Procedure.pdf'},
      ]
    },
  ];

  late final List<Map<String, String>> rootProtocols;

  @override
  void initState() {
    super.initState();
    _initRootProtocols();
    _loadData();
    _checkAdminMode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkAdminMode() async {
    final isAdmin = await ProtocolSyncService.instance.isAdminMode;
    if (mounted) setState(() => _isAdmin = isAdmin);
  }

  Future<void> _checkForUpdates() async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;

    // Protocols
    final pending = await ProtocolSyncService.instance.pendingProtocols();
    if (pending.isNotEmpty && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProtocolUpdateDialog(protocols: pending),
      );
    }

    // Deployment orders
    if (!mounted) return;
    final newOrders = await ProtocolSyncService.instance.pendingDeploymentOrders();
    if (newOrders.isNotEmpty && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeploymentOrdersDialog(orders: newOrders),
      );
    }
  }

  Future<void> _toggleAdminMode() async {
    if (_isAdmin) {
      await ProtocolSyncService.instance.setAdminMode(false);
      if (mounted) setState(() => _isAdmin = false);
      return;
    }
    if (!mounted) return;
    final ok = await showAdminPinDialog(context);
    if (!ok || !mounted) return;
    await ProtocolSyncService.instance.setAdminMode(true);
    if (!mounted) return;
    setState(() => _isAdmin = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Admin mode activated')));
  }

  void _initRootProtocols() {
    final List<String> allAssets = [
      'Bites.pdf', 'Hazmat.pdf', 'Stings.pdf', 'Stroke.pdf', 'Seizure.pdf', 'Drowning.pdf',
      'Crush Injury.pdf', 'Hypertension.pdf', 'Dead on Scene.pdf', 'EXPANDED SCOPE.pdf',
      'Cyanide Poisoning.pdf', 'Hydrocarbon Fumes.pdf', 'Activated Charcoal.pdf',
      'Behavior Emergency.pdf', 'Adult Resuscitation.pdf', 'Trauma - Antibiotics.pdf',
      'Trauma - Head Injury.pdf', 'Trauma - Neck Trauma.pdf', 'Altered Mental Status.pdf',
      'Trauma - Sexual Assault.pdf', 'Trauma Arrest Guideline.pdf', 'Trauma - Burns - General.pdf',
      'Headache - Expanded Scope.pdf', 'Spinal Motion Restriction.pdf', 'Epistaxis - Expanded Scope.pdf',
      'Toxic Ingestion - Overdose.pdf', 'Chest Pain - Expanded Scope.pdf', 'Firefighter Rehab Guidelines.pdf',
      'GI Bleeding - Expanded Scope.pdf', 'Special Consideration - Rabies.pdf', 'Trauma - Eye Injury - Chemical.pdf',
      'Abdominal Pain - Expanded Scope.pdf', 'Trauma - Blunt - Expanded Scope.pdf', 'Pain Management w expanded scope.pdf',
      'Shock - Medical - Expanded Scope.pdf', 'Trauma - General - Expanded Scope.pdf', 'Vaginal Bleeding - Expanded Scope.pdf',
      'Adult Cardiac Arrest - Initial Care.pdf', 'Diabetic Emergency - Expanded Scope.pdf',
      'Difficulty Breathing - SCAPE or CHF.pdf', 'Electrical Injury and Electrocution.pdf',
      'High Altitude Cerebral Edema - HACE.pdf', 'Dislocations in Austere Environments.pdf',
      'High Altitude Pulmonary Edema - HAPE.pdf', 'Nausea and Vomiting - Expanded Scope.pdf',
      'Trauma - Eye Injury - Expanded Scope.pdf', 'General Medical Care - Expanded Scope.pdf',
      'Trauma - Penetrating - Expanded Scope.pdf', 'Adult Cardiac Arrest - VF-Pulseless VT.pdf',
      'Tranexamic Acid - TXA - Expanded Scope.pdf', 'Adult Cardiac Arrest - PEA and Asystole.pdf',
      'Allergy-Anaphylaxis with expanded scope.pdf', 'Bradycardia with pulse - Expanded Scope.pdf',
      'Acute Mountain Sickness - Expanded Scope.pdf', 'Rabies_postexposure_prophylaxis_algorithm.pdf',
      'Syncope - Weak and Dizzy - Expanded Scope.pdf', 'Airway Obstruction - Foreign Body - Choking.pdf',
      'Difficulty Breathing - Respiratory Distress.pdf', 'Environmental Hyperthermia - Expanded Scope.pdf',
      'Tachycardia - Wide Complex - Expanded Scope.pdf', 'Tachycardia - Narrow Complex - Expanded Scope.pdf',
      'Adult Cardiac Arrest - Additional Treatments to Consider.pdf', 'Difficulty Breathing - Asthma and COPD with expanded scope.pdf',
      'Termination of Resuscitation - Non-traumatic Cardiac Arrest.pdf', 'Adult Cardiac Arrest - Post Resuscitative Care - Expanded Scope.pdf',
      'Rabies World_Health_Organization_post_exposure_rabies_management.pdf'
    ];

    rootProtocols = allAssets.map((asset) => {
      'title': asset.replaceAll('.pdf', ''),
      'asset': asset,
    }).toList();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      favorites = Set.from(prefs.getStringList('favorites') ?? []);
      final uploadsList = prefs.getStringList('user_uploads') ?? [];
      userUploads = uploadsList
          .where((e) => e.contains('|'))
          .map((e) {
            final separatorIndex = e.indexOf('|');
            return {
              'title': e.substring(0, separatorIndex),
              'path': e.substring(separatorIndex + 1),
            };
          })
          .toList();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', favorites.toList());
  }

  Future<void> _saveUploads() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('user_uploads', userUploads.map((e) => '${e['title']}|${e['path']}').toList());
  }

  void _toggleFavorite(String assetPath) {
    setState(() {
      if (favorites.contains(assetPath)) {
        favorites.remove(assetPath);
      } else {
        favorites.add(assetPath);
      }
    });
    _saveFavorites();
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final dir = await getApplicationDocumentsDirectory();
      final uploadDir = Directory('${dir.path}/user_uploads');
      if (!await uploadDir.exists()) await uploadDir.create();

      final targetPath = '${uploadDir.path}/$fileName';
      final targetFile = File(targetPath);

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await file.copy(targetPath);

      setState(() {
        userUploads.removeWhere((element) => element['title'] == fileName);
        userUploads.add({'title': fileName, 'path': targetPath});
      });
      _saveUploads();
    }
  }

  Future<void> _deleteUpload(int index) async {
    final file = File(userUploads[index]['path']!);
    if (await file.exists()) await file.delete();
    setState(() {
      final assetPath = userUploads[index]['path']!;
      favorites.remove(assetPath);
      userUploads.removeAt(index);
    });
    _saveUploads();
    _saveFavorites();
  }

  Future<void> _openPdf(String title, String asset, {bool isAsset = true}) async {
    String finalPath;
    if (isAsset) {
      final dir = await getApplicationDocumentsDirectory();
      finalPath = '${dir.path}/$asset';
      final file = File(finalPath);
      if (!await file.exists()) {
        final byteData = await rootBundle.load('assets/protocols/$asset');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }
    } else {
      finalPath = asset;
    }

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(
        title: title,
        filePath: finalPath,
        assetPath: asset,
        isFavorite: favorites.contains(asset),
        onToggleFavorite: () => _toggleFavorite(asset),
      )));
    }
  }

  List<Map<String, dynamic>> get allCategories {
    final airwayItems = <Map<String, dynamic>>[];
    final breathingItems = <Map<String, dynamic>>[];
    final circulationItems = <Map<String, dynamic>>[];
    final traumaItems = <Map<String, dynamic>>[];
    final otherItems = <Map<String, dynamic>>[];

    final airwayMeds = <Map<String, dynamic>>[];
    final breathingMeds = <Map<String, dynamic>>[];
    final circulationMeds = <Map<String, dynamic>>[];

    final circulationKeywords = ['circulation', 'cardiac', 'heart', 'pulse', 'shock', 'arrest', 'vascular', 'blood', 'vessel'];

    final List<Map<String, dynamic>> pool = [];
    pool.addAll(rootProtocols);
    for (var cat in staticCategories) {
      if (cat['title'] != 'Medications' && cat['title'] != 'Appendix Material') {
        pool.addAll((cat['items'] as List).cast<Map<String, dynamic>>());
      }
    }

    for (var item in pool) {
      final title = item['title'].toString().toLowerCase();
      if (title.contains('trauma')) {
        traumaItems.add(item);
      } else if (title.contains('airway')) {
        airwayItems.add(item);
      } else if (title.contains('breathing')) {
        breathingItems.add(item);
      } else if (circulationKeywords.any((kw) => title.contains(kw))) {
        circulationItems.add(item);
      } else {
        otherItems.add(item);
      }
    }

    final mainMedFolderItems = <Map<String, dynamic>>[];
    final Map<String, List<Map<String, dynamic>>> groupedMeds = {};

    medicationData.forEach((name, data) {
      final item = {'title': name, 'asset': '$name.pdf'};
      final types = (data['types'] as List).cast<String>();
      final abc = (data['abc'] as List).cast<String>();

      if (abc.contains('airway')) airwayMeds.add(item);
      if (abc.contains('breathing')) breathingMeds.add(item);
      if (abc.contains('circulation')) circulationMeds.add(item);

      for (var type in types) {
        groupedMeds.putIfAbsent(type, () => []).add(item);
      }
    });

    groupedMeds.forEach((type, items) {
      mainMedFolderItems.add({
        'title': type,
        'isFolder': true,
        'items': items,
      });
    });

    return [
      if (favorites.isNotEmpty)
        {
          'title': 'Favorites ⭐',
          'isFolder': true,
          'items': _getFavoriteItems(),
          'isFavoriteSection': true,
        },
      if (userUploads.isNotEmpty)
        {
          'title': 'User Uploads',
          'isFolder': true,
          'items': userUploads.map((e) => {'title': e['title'], 'path': e['path'], 'isUserUpload': true}).toList(),
        },
      {
        'title': 'Airway',
        'isFolder': true,
        'items': [
          ...airwayItems,
          if (airwayMeds.isNotEmpty) {'title': 'Medications', 'isFolder': true, 'items': airwayMeds},
        ]
      },
      {
        'title': 'Breathing',
        'isFolder': true,
        'items': [
          ...breathingItems,
          if (breathingMeds.isNotEmpty) {'title': 'Medications', 'isFolder': true, 'items': breathingMeds},
        ]
      },
      {
        'title': 'Circulation',
        'isFolder': true,
        'items': [
          ...circulationItems,
          if (circulationMeds.isNotEmpty) {'title': 'Medications', 'isFolder': true, 'items': circulationMeds},
        ]
      },
      {
        'title': 'Trauma',
        'isFolder': true,
        'items': traumaItems,
      },
      {
        'title': 'Medications',
        'isFolder': true,
        'items': mainMedFolderItems,
      },
      {
        'title': 'Other Protocols',
        'isFolder': true,
        'items': [
          ...otherItems,
          ...staticCategories.where((c) => c['title'] == 'Appendix Material').expand((c) => c['items'] as List),
        ],
      },
    ];
  }

  List<Map<String, dynamic>> _getFavoriteItems() {
    final List<Map<String, dynamic>> items = [];
    for (var upload in userUploads) {
      if (favorites.contains(upload['path'])) {
        items.add({'title': upload['title'], 'path': upload['path'], 'isUserUpload': true});
      }
    }
    for (var item in rootProtocols) {
      if (favorites.contains(item['asset'])) {
        items.add({'title': item['title'], 'asset': item['asset']});
      }
    }
    for (final name in medicationData.keys) {
      final asset = '$name.pdf';
      if (favorites.contains(asset)) {
        items.add({'title': name, 'asset': asset});
      }
    }
    for (var cat in staticCategories) {
      for (var item in cat['items']) {
        if (favorites.contains(item['asset'])) {
          items.add({'title': item['title'], 'asset': item['asset']});
        }
      }
    }
    return items;
  }

  List<Map<String, dynamic>> get filteredItems {
    if (searchQuery.isEmpty) return [];
    final query = searchQuery.toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (var item in rootProtocols) {
      if (item['title']!.toLowerCase().contains(query)) results.add(item);
    }
    for (var name in medicationData.keys) {
      if (name.toLowerCase().contains(query)) results.add({'title': name, 'asset': '$name.pdf'});
    }
    for (var cat in staticCategories) {
      for (var item in cat['items']) {
        if (item['title']!.toLowerCase().contains(query)) results.add(item);
      }
    }
    for (var upload in userUploads) {
      if (upload['title']!.toLowerCase().contains(query)) {
        results.add({'title': upload['title'], 'path': upload['path'], 'isUserUpload': true});
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = searchQuery.isNotEmpty;
    final categoriesToShow = allCategories;

    return Scaffold(
      // ── Drawer now holds the protocol list ───────────────────────────────
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.menu_book, color: Colors.white, size: 32),
                  const SizedBox(height: 8),
                  const Text('Protocols', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('v$kCurrentVersion', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search protocols…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.light
                      ? Colors.grey[100]
                      : Colors.grey[800],
                ),
                onChanged: (value) => setState(() => searchQuery = value),
              ),
            ),
            Expanded(
              child: isSearching
                  ? ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final isUser = item['isUserUpload'] == true;
                        final assetPath = isUser ? (item['path'] ?? '') : (item['asset'] ?? '');
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
                          title: Text(item['title'] ?? 'Unknown', style: const TextStyle(fontSize: 14)),
                          onTap: () {
                            Navigator.pop(context);
                            _openPdf(item['title'] ?? 'Unknown', assetPath, isAsset: !isUser);
                          },
                        );
                      },
                    )
                  : ListView.builder(
                      itemCount: categoriesToShow.length,
                      itemBuilder: (context, index) =>
                          _buildCategoryTile(categoriesToShow[index]),
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                _isAdmin ? Icons.admin_panel_settings : Icons.lock_outline,
                color: _isAdmin ? Colors.orange : null,
              ),
              title: Text(_isAdmin ? 'Admin Mode: ON' : 'Admin Mode'),
              subtitle: _isAdmin ? const Text('Tap to deactivate') : null,
              onTap: () { Navigator.pop(context); _toggleAdminMode(); },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Import PDF'),
              onTap: () { Navigator.pop(context); _uploadFile(); },
            ),
          ],
        ),
      ),

      // ── AppBar ───────────────────────────────────────────────────────────
      appBar: AppBar(
        title: const Text('AustereMed'),
        actions: [
          IconButton(icon: const Icon(Icons.brightness_medium), onPressed: widget.onThemeToggle),
        ],
      ),

      // ── Body: feature launcher ───────────────────────────────────────────
      body: _buildHomeLauncher(context),
    );
  }

  Widget _buildHomeLauncher(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _launcherSection('Clinical Tools'),
        _launcherGrid(context, const [
          _FeatureTile(Icons.account_tree, 'Decision Trees', Colors.indigo, DecisionTreeScreen()),
          _FeatureTile(Icons.medication, 'Drug Reference', Colors.teal, DrugReferenceScreen()),
          _FeatureTile(Icons.checklist, 'Procedure\nChecklists', Colors.green, ProcedureListScreen()),
          _FeatureTile(Icons.biotech, 'Differential\nDiagnosis', Colors.purple, DifferentialDxScreen()),
          _FeatureTile(Icons.calculate, 'Dosing\nCalculator', Colors.orange, DosingCalculatorScreen()),
          _FeatureTile(Icons.assignment_outlined, 'Patient\nReports', Colors.red, PatientReportListScreen()),
          _FeatureTile(Icons.workspace_premium, 'Cert\nVault', Colors.deepPurple, CertVaultScreen()),
        ]),
        _launcherSection('Field & Navigation'),
        _launcherGrid(context, const [
          _FeatureTile(Icons.map_outlined, 'Offline Maps', Colors.brown, OfflineMapsScreen()),
          _FeatureTile(Icons.gps_fixed, 'GPS Tools', Colors.blue, GpsToolsScreen()),
          _FeatureTile(Icons.flight_land, 'LZ Assessment', Colors.cyan, LzAssessmentScreen()),
          _FeatureTile(Icons.wb_sunny_outlined, 'Sun & Weather', Colors.amber, SunWeatherScreen()),
        ]),
        _launcherSection('Team Coordination'),
        _launcherGrid(context, const [
          _FeatureTile(Icons.account_tree_outlined, 'Team\nCommand', Colors.indigo, TeamCommandScreen()),
          _FeatureTile(Icons.emergency, 'MCI\nTriage', Colors.red, MciTriageScreen()),
          _FeatureTile(Icons.radar, 'Tac\nMap', Colors.teal, TacMapScreen()),
          _FeatureTile(Icons.description_outlined, 'Team\nProtocols', Colors.deepOrange, TeamProtocolsScreen()),
        ]),
        _launcherSection('Reference'),
        _launcherGrid(context, [
          const _FeatureTile(Icons.info_outline, 'Protocol\nVersion', Colors.blueGrey, ProtocolVersionScreen()),
          if (_isAdmin)
            const _FeatureTile(Icons.admin_panel_settings, 'Admin\nPanel', Colors.red, AdminPanelScreen()),
        ]),
      ],
    );
  }

  Widget _launcherSection(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _launcherGrid(BuildContext context, List<_FeatureTile> tiles) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) {
        final t = tiles[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => t.screen)),
          child: Container(
            decoration: BoxDecoration(
              color: t.color.withValues(alpha: 0.12),
              border: Border.all(color: t.color.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(t.icon, color: t.color, size: 32),
                const SizedBox(height: 6),
                Text(t.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.color, height: 1.2)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> category, {double depth = 0}) {
    if (category['isFolder'] == true) {
      return ExpansionTile(
        initiallyExpanded: category['isFavoriteSection'] == true,
        title: Text(
          category['title'],
          style: TextStyle(
            fontWeight: depth == 0 ? FontWeight.bold : FontWeight.normal,
            fontSize: depth == 0 ? 18 : 16,
          ),
        ),
        children: (category['items'] as List).map<Widget>((item) {
          if (item['isFolder'] == true) {
            return Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildCategoryTile(item, depth: depth + 1),
            );
          } else {
            return _buildFileTile(item);
          }
        }).toList(),
      );
    } else {
      return _buildFileTile(category);
    }
  }

  Widget _buildFileTile(Map<String, dynamic> item) {
    final isUser = item['isUserUpload'] == true;
    final assetPath = isUser ? (item['path'] ?? '') : (item['asset'] ?? '');
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
      title: Text(item['title'] ?? 'Unknown'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUser)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.grey),
              onPressed: () {
                final idx = userUploads.indexWhere((u) => u['path'] == item['path']);
                if (idx != -1) _deleteUpload(idx);
              },
            ),
          IconButton(
            icon: Icon(favorites.contains(assetPath) ? Icons.star : Icons.star_border, color: Colors.amber),
            onPressed: () => _toggleFavorite(assetPath),
          ),
        ],
      ),
      onTap: () => _openPdf(item['title'] ?? 'Unknown', assetPath, isAsset: !isUser),
    );
  }
}

class _FeatureTile {
  final IconData icon;
  final String label;
  final Color color;
  final Widget screen;
  const _FeatureTile(this.icon, this.label, this.color, this.screen);
}

class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String filePath;
  final String assetPath;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.filePath,
    required this.assetPath,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.star : Icons.star_border, color: Colors.amber),
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });
              widget.onToggleFavorite();
            },
          ),
        ],
      ),
      body: PdfViewer.file(
        widget.filePath,
      ),
    );
  }
}

// ── Deployment orders startup dialog ──────────────────────────────────────────

class _DeploymentOrdersDialog extends StatefulWidget {
  final List<DeploymentOrder> orders;
  const _DeploymentOrdersDialog({required this.orders});

  @override
  State<_DeploymentOrdersDialog> createState() => _DeploymentOrdersDialogState();
}

class _DeploymentOrdersDialogState extends State<_DeploymentOrdersDialog> {
  bool _acknowledging = false;

  Future<void> _ackAll() async {
    setState(() => _acknowledging = true);
    for (final o in widget.orders) {
      await ProtocolSyncService.instance.markDeploymentOrderViewed(o.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.orders.length;
    return AlertDialog(
      icon: const Icon(Icons.assignment_outlined, color: Colors.orange, size: 32),
      title: Text('$n Deployment Order${n > 1 ? 's' : ''} Received'),
      content: SizedBox(
        width: double.maxFinite,
        height: 260,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'The following order${n > 1 ? 's have' : ' has'} been issued. '
            'Tap to review each one.',
            style: TextStyle(fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: n,
              itemBuilder: (_, i) {
                final o = widget.orders[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.assignment_outlined,
                        color: Colors.orange, size: 24),
                    title: Text(o.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                      'From: ${o.uploadedBy.isEmpty ? 'Admin' : o.uploadedBy}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: _acknowledging ? null : _ackAll,
          icon: _acknowledging
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Acknowledge'),
        ),
      ],
    );
  }
}
