import 'package:flutter/material.dart';
import '../incident_service.dart';
import 'incident_screen.dart';
import 'roster_screen.dart';
import 'assets_screen.dart';
import 'live_map_screen.dart';
import 'deployment_orders_console_screen.dart';
import 'reports_console_screen.dart';
import 'access_requests_screen.dart';
import 'settings_screen.dart';

/// Carries the admin's currently-selected incident to every console screen.
class ActiveIncidentController extends ChangeNotifier {
  TacIncident? _incident;
  TacIncident? get incident => _incident;

  void select(TacIncident? incident) {
    _incident = incident;
    notifyListeners();
  }
}

class AdminShellScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  const AdminShellScreen({super.key, required this.onSignOut});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;
  final _activeIncident = ActiveIncidentController();

  @override
  void dispose() {
    _activeIncident.dispose();
    super.dispose();
  }

  static const _destinations = [
    NavigationRailDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: Text('Incidents')),
    NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: Text('Live Map')),
    NavigationRailDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: Text('Roster')),
    NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: Text('Assets')),
    NavigationRailDestination(icon: Icon(Icons.upload_file_outlined), selectedIcon: Icon(Icons.upload_file), label: Text('Deployment Orders')),
    NavigationRailDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: Text('Reports')),
    NavigationRailDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: Text('Access Requests')),
    NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Settings')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.shield_outlined, size: 32),
            ),
            destinations: _destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActiveIncidentBar(controller: _activeIncident),
                const Divider(height: 1),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _activeIncident,
                    builder: (context, _) => IndexedStack(
                      index: _index,
                      children: [
                        IncidentScreen(controller: _activeIncident),
                        LiveMapScreen(incident: _activeIncident.incident),
                        RosterScreen(incident: _activeIncident.incident),
                        const AssetsScreen(),
                        DeploymentOrdersConsoleScreen(incident: _activeIncident.incident),
                        ReportsConsoleScreen(incident: _activeIncident.incident),
                        const AccessRequestsScreen(),
                        SettingsScreen(onSignOut: widget.onSignOut),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveIncidentBar extends StatelessWidget {
  final ActiveIncidentController controller;
  const _ActiveIncidentBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final incident = controller.incident;
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: incident == null
              ? Text('No active incident — select one from Incidents',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Row(children: [
                  Icon(Icons.local_fire_department,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(incident.name.isEmpty ? incident.missionCode : incident.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('(${incident.missionCode})',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  if (!incident.isOpen)
                    const Chip(label: Text('Closed'), visualDensity: VisualDensity.compact),
                ]),
        );
      },
    );
  }
}
