import 'package:flutter/material.dart';

/// Shared empty-state shown by console screens that need an active incident
/// selected before they have anything meaningful to display.
class NoIncidentPlaceholder extends StatelessWidget {
  final String feature;
  const NoIncidentPlaceholder({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text('Select or create an incident to use $feature'),
      ]),
    );
  }
}
