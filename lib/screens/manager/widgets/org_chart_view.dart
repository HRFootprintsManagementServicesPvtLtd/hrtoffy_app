import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/employee_repository.dart';
import '../../../repositories/manager_repository.dart';
import 'manager_state_views.dart';

const String kOrgChartCaption = 'Your reporting structure';
const String kOrgChartEmptyMessage = 'You have no direct reports yet';

/// One person on the chart. Only what the server's team view gives; nothing is invented.
class OrgNode {
  OrgNode({
    required this.id,
    required this.name,
    required this.designation,
    required this.department,
  });

  final String id;
  final String name;
  final String designation;
  final String department;
  final List<OrgNode> children = [];
}

String _s(Object? v) => v?.toString().trim() ?? '';

bool _isActive(Map<String, dynamic> m) =>
    _s(m['status'] ?? m['employment_status']).toLowerCase() == 'active';

/// Builds the reporting tree below [meId] from the manager's team rows (by `manager_id`).
///
/// Only active people appear. When someone's manager is inactive (so left out), the person is attached to the nearest
/// active manager above, so no active report is lost; a person whose line cannot be followed goes under [meId].
/// Returns the top-level nodes (the manager's direct line), sorted by name; cycles in the data cannot loop.
List<OrgNode> buildOrgTree(List<Map<String, dynamic>> rows, String meId) {
  final byId = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final id = _s(r['id']);
    if (id.isNotEmpty && id != meId) byId[id] = r;
  }
  final nodes = <String, OrgNode>{
    for (final e in byId.entries)
      if (_isActive(e.value))
        e.key: OrgNode(
          id: e.key,
          name: _s(e.value['full_name']),
          designation: _s(e.value['designation']),
          department: _s(e.value['department']),
        ),
  };
  final top = <OrgNode>[];
  for (final e in nodes.entries) {
    final seen = <String>{e.key};
    var parent = _s(byId[e.key]!['manager_id']);
    String? attachTo;
    while (true) {
      if (parent.isEmpty || parent == meId || !byId.containsKey(parent)) {
        attachTo = null; // the manager (or an unknown line)
        break;
      }
      if (!seen.add(parent)) {
        attachTo = null; // a cycle in the data
        break;
      }
      if (nodes.containsKey(parent)) {
        attachTo = parent;
        break;
      }
      parent = _s(byId[parent]!['manager_id']); // inactive: look one level up
    }
    if (attachTo == null) {
      top.add(e.value);
    } else {
      nodes[attachTo]!.children.add(e.value);
    }
  }
  int byName(OrgNode a, OrgNode b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  void sortAll(List<OrgNode> l) {
    l.sort(byName);
    for (final n in l) {
      sortAll(n.children);
    }
  }

  sortAll(top);
  return top;
}

class _OrgData {
  _OrgData(this.me, this.roots);
  final Map<String, dynamic> me;
  final List<OrgNode> roots;
}

/// The manager's own reporting structure (NOT the whole company): the manager, their manager when the profile has one,
/// the direct reports and each report's reports. Read-only: `GET /employees/me` and the team list.
class OrgChartView extends StatefulWidget {
  const OrgChartView({
    super.key,
    required this.manager,
    required this.employees,
  });

  final ManagerRepository manager;
  final EmployeeRepository employees;

  @override
  State<OrgChartView> createState() => _OrgChartViewState();
}

class _OrgChartViewState extends State<OrgChartView> {
  final Set<String> _expanded = {};

  Future<_OrgData> _load() async {
    final r = await Future.wait([
      widget.employees.getMe(),
      widget.manager.team(),
    ]);
    final me = r[0] as Map<String, dynamic>;
    final team = r[1] as ManagerTeam;
    return _OrgData(me, buildOrgTree(team.tree, widget.manager.employeeId));
  }

  @override
  Widget build(BuildContext context) {
    return ManagerLoader<_OrgData>(
      load: _load,
      isEmpty: (d) => d.roots.isEmpty,
      emptyText: kOrgChartEmptyMessage,
      builder: (context, d) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              kOrgChartCaption,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ),
          if (_s(d.me['manager_name']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _card(
                name: _s(d.me['manager_name']),
                subtitle: 'Your manager',
                avatarColor: Colors.grey.shade200,
              ),
            ),
          _card(
            key: const ValueKey('org-me'),
            name: _s(d.me['full_name']),
            subtitle: [
              _s(d.me['designation']),
              _s(d.me['department']),
            ].where((s) => s.isNotEmpty).join(' • '),
            badge: 'You',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(children: [for (final n in d.roots) _node(n, 0)]),
          ),
        ],
      ),
    );
  }

  Widget _node(OrgNode n, int depth) {
    final open = _expanded.contains(n.id);
    final has = n.children.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _card(
            key: ValueKey('org-node-${n.id}'),
            name: n.name,
            subtitle: [
              n.designation,
              n.department,
            ].where((s) => s.isNotEmpty).join(' • '),
            trailing: has
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${n.children.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey,
                      ),
                    ],
                  )
                : null,
            onTap: has
                ? () => setState(() {
                    if (!_expanded.remove(n.id)) _expanded.add(n.id);
                  })
                : null,
          ),
        ),
        if (has && open)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: [for (final c in n.children) _node(c, depth + 1)],
            ),
          ),
      ],
    );
  }

  Widget _card({
    Key? key,
    required String name,
    required String subtitle,
    String? badge,
    Widget? trailing,
    VoidCallback? onTap,
    Color? avatarColor,
  }) {
    return Material(
      key: key,
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: avatarColor ?? Colors.blue.shade50,
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
