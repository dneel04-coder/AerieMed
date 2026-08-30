import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../shift_ticket_record_service.dart';

/// Read-only archive of transmitted Shift Tickets -- these are recorded
/// automatically when a field user sends one (see ShiftTicketFormScreen's
/// _email(), which calls recordAndUploadShiftTicket on a successful send),
/// not pushed/uploaded from here the way Deployment Orders are.
class ShiftTicketsConsoleScreen extends StatefulWidget {
  const ShiftTicketsConsoleScreen({super.key});

  @override
  State<ShiftTicketsConsoleScreen> createState() => _ShiftTicketsConsoleScreenState();
}

class _ShiftTicketsConsoleScreenState extends State<ShiftTicketsConsoleScreen> {
  List<ShiftTicketRecord> _tickets = [];
  bool _loading = true;
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tickets = await allShiftTicketRecords();
    if (mounted) setState(() {
      _tickets = tickets;
      _loading = false;
    });
  }

  Future<void> _download(ShiftTicketRecord r) async {
    setState(() => _downloading.add(r.id));
    try {
      final bytes = await fetchShiftTicketRecordBytes(r);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not find this file in storage.'), backgroundColor: Colors.red));
        }
        return;
      }
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Shift Ticket PDF',
        fileName: r.fileName.isEmpty ? 'ShiftTicket-${r.id}.pdf' : r.fileName,
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

  Future<void> _confirmDelete(ShiftTicketRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Shift Ticket record?'),
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
    await deleteShiftTicketRecord(r);
    _load();
  }

  String _formatSentAt(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Tickets'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tickets.isEmpty
              ? Center(
                  child: Text('No Shift Tickets sent yet.', style: TextStyle(color: Colors.grey[600])),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _tickets.length,
                  itemBuilder: (_, i) {
                    final r = _tickets[i];
                    final busy = _downloading.contains(r.id);
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined, color: Colors.brown),
                        title: Text(r.incidentName.isEmpty ? '(no incident name)' : r.incidentName),
                        subtitle: Text(
                          '${r.equipmentMakeModel.isEmpty ? 'Unknown equipment' : r.equipmentMakeModel} • '
                          'To: ${r.recipientEmail} • ${_formatSentAt(r.sentAt)}'
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
    );
  }
}
