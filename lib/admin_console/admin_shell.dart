import 'package:flutter/material.dart';
import '../incident_service.dart';
import 'incident_screen.dart';
import 'roster_screen.dart';
import 'assets_screen.dart';
import 'live_map_screen.dart';
import 'deployment_orders_console_screen.dart';
import 'transmitted_forms_console_screen.dart';
import 'reports_console_screen.dart';
import 'access_requests_screen.dart';
import 'protocols_console_screen.dart';
import 'org_management_screen.dart';
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
  // The signed-in admin's own role/org, resolved once at sign-in (see
  // main_admin.dart) -- 'super_admin' sees every organization and gets the
  // Org Management tab; 'org_admin' is scoped to just their own org.
  final String role;
  final String? orgId;
  final String orgName;
  const AdminShellScreen({
    super.key,
    required this.onSignOut,
    required this.role,
    required this.orgId,
    required this.orgName,
  });

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;
  final _activeIncident = ActiveIncidentController();

  bool get _isSuperAdmin => widget.role == 'super_admin';
  bool get _canManageOrg => widget.role == 'super_admin' || widget.role == 'org_admin';

  @override
  void dispose() {
    _activeIncident.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: Text('Incidents')),
      const NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: Text('Live Map')),
      const NavigationRailDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: Text('Roster')),
      const NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: Text('Assets')),
      const NavigationRailDestination(icon: Icon(Icons.upload_file_outlined), selectedIcon: Icon(Icons.upload_file), label: Text('Deployment Orders')),
      const NavigationRailDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: Text('Forms')),
      const NavigationRailDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: Text('Reports')),
      const NavigationRailDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: Text('Access Requests')),
      const NavigationRailDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: Text('Protocols')),
      if (_canManageOrg)
        NavigationRailDestination(
          icon: const Icon(Icons.corporate_fare_outlined),
          selectedIcon: const Icon(Icons.corporate_fare),
          label: Text(_isSuperAdmin ? 'Organizations' : 'My Org'),
        ),
      const NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Settings')),
    ];

    final screens = <Widget>[
      IncidentScreen(controller: _activeIncident),
      LiveMapScreen(incident: _activeIncident.incident),
      RosterScreen(incident: _activeIncident.incident, role: widget.role, orgId: widget.orgId, orgName: widget.orgName),
      const AssetsScreen(),
      DeploymentOrdersConsoleScreen(incident: _activeIncident.incident),
      const TransmittedFormsConsoleScreen(),
      ReportsConsoleScreen(incident: _activeIncident.incident),
      const AccessRequestsScreen(),
      ProtocolsConsoleScreen(role: widget.role, orgId: widget.orgId, orgName: widget.orgName),
      if (_canManageOrg) OrgManagementScreen(role: widget.role, orgId: widget.orgId),
      SettingsScreen(onSignOut: widget.onSignOut),
    ];

    if (_index >= screens.length) _index = 0;

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
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActiveIncidentBar(controller: _activeIncident, orgName: widget.orgName),
                const Divider(height: 1),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _activeIncident,
                    builder: (context, _) => IndexedStack(
                      index: _index,
                      children: screens,
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
  final String orgName;
  const _ActiveIncidentBar({required this.controller, required this.orgName});

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
          child: Row(children: [
            if (orgName.isNotEmpty) ...[
              Icon(Icons.corporate_fare, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(orgName, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              const Text('•'),
              const SizedBox(width: 16),
            ],
            Expanded(
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
            ),
          ]),
        );
      },
    );
  }
}
