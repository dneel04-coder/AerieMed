import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../transmitted_form_service.dart';

const Map<String, IconData> _kFormIcons = {
  'shift_ticket': Icons.receipt_long_outlined,
  'crew_swap': Icons.swap_horiz,
  'sf261': Icons.groups_outlined,
  'ics214': Icons.history_edu_outlined,
  'ics205': Icons.radio_outlined,
  'ics213': Icons.mail_outline,
  'ics206wf': Icons.medical_services_outlined,
};

const Map<String, Color> _kFormColors = {
  'shift_ticket': Colors.brown,
  'crew_swap': Colors.deepPurple,
  'sf261': Colors.orange,
  'ics214': Colors.teal,
  'ics205': Colors.indigo,
  'ics213': Colors.blueGrey,
  'ics206wf': Colors.red,
};

/// Read-only archive of every transmitted form (Shift Ticket, Crew Swap,
/// SF-261, ICS 214/205/213) -- these are recorded automatically the moment
/// a field user's send actually goes out (immediately, or later via
/// FormOutboxService's queued retry), not pushed/uploaded from here.
class TransmittedFormsConsoleScreen extends StatefulWidget {
  const TransmittedFormsConsoleScreen({super.key});

  @override
  State<TransmittedFormsConsoleScreen> createState() => _TransmittedFormsConsoleScreenState();
}

class _TransmittedFormsConsoleScreenState extends State<TransmittedFormsConsoleScreen> {
  List<TransmittedFormRecord> _forms = [];
  bool _loading = true;
  final Set<String> _downloading = {};
  String? _typeFilter; // null = all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final forms = await allTransmittedForms();
    if (mounted) {
      setState(() {
        _forms = forms;
        _loading = false;
      });
    }
  }

  List<TransmittedFormRecord> get _filtered =>
      _typeFilter == null ? _forms : _forms.where((f) => f.formType == _typeFilter).toList();

  Future<void> _download(TransmittedFormRecord r) async {
    setState(() => _downloading.add(r.id));
    try {
      final bytes = await fetchTransmittedFormBytes(r);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not find this file in storage.'), backgroundColor: Colors.red));
        }
        return;
      }
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${r.formTitle} PDF',
        fileName: r.fileName.isEmpty ? '${r.formTitle}-${r.id}.pdf' : r.fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savePath == null) return;
      final path = savePath.toLowerCase().endsWith('.pdf') ? savePath : '$savePath.pdf';
      await File(path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save PDF: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(r.id));
    }
  }

  Future<void> _confirmDelete(TransmittedFormRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete form record?'),
        content: Text('This removes "${r.fileName}" from the archive. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteTransmittedFormRecord(r);
    _load();
  }

  String _formatSentAt(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final types = _forms.map((f) => f.formType).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transmitted Forms'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        if (types.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _typeFilter == null,
                      onSelected: (_) => setState(() => _typeFilter = null),
                    ),
                  ),
                  for (final t in types)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_forms.firstWhere((f) => f.formType == t).formTitle),
                        selected: _typeFilter == t,
                        onSelected: (_) => setState(() => _typeFilter = t),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Text('No forms sent yet.', style: TextStyle(color: Colors.grey[600])),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final r = _filtered[i];
                        final busy = _downloading.contains(r.id);
                        final icon = _kFormIcons[r.formType] ?? Icons.description_outlined;
                        final color = _kFormColors[r.formType] ?? Colors.grey;
                        return Card(
                          child: ListTile(
                            leading: Icon(icon, color: color),
                            title: Text(r.summary.isEmpty ? r.formTitle : r.summary),
                            subtitle: Text(
                              '${r.formTitle} • To: ${r.recipientEmail} • ${_formatSentAt(r.sentAt)}'
                              '${r.sentBy.isEmpty ? '' : ' • ${r.sentBy}'}',
                            ),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (busy)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.download_outlined),
                                  tooltip: 'Download PDF',
                                  onPressed: () => _download(r),
                                ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                                tooltip: 'Delete record',
                                onPressed: () => _confirmDelete(r),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
