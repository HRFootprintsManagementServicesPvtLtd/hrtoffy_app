import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';
import '../../../repositories/manager_repository.dart';
import '../../../repositories/tasks_repository.dart';
import 'manager_state_views.dart';

const String kTeamTasksEmptyMessage = 'No tasks assigned to your team';
const String kTeamTasksNoMatchMessage = 'No tasks match this filter';

enum TeamTaskFilter { all, open, completed }

/// One assignee and their tasks.
class TeamTaskGroup {
  TeamTaskGroup(this.name, this.designation, this.tasks);
  final String name;
  final String designation;
  final List<Map<String, dynamic>> tasks;
}

bool isTaskDone(Map<String, dynamic> a) =>
    (a['status']?.toString() ?? '').toLowerCase() == 'completed';

/// Groups assignments by the team member they belong to (named from [team] rows; an assignment whose assignee is not on
/// the team is dropped, never shown under an invented name). Groups are sorted by name, tasks by due date.
List<TeamTaskGroup> groupTeamTasks(
  List<Map<String, dynamic>> assignments,
  List<Map<String, dynamic>> team,
) {
  final people = {for (final m in team) m['id'].toString(): m};
  final by = <String, List<Map<String, dynamic>>>{};
  for (final a in assignments) {
    final id = a['employee_id']?.toString();
    if (id == null || !people.containsKey(id)) continue;
    by.putIfAbsent(id, () => []).add(a);
  }
  final groups = [
    for (final e in by.entries)
      TeamTaskGroup(
        people[e.key]!['full_name']?.toString().trim() ?? '',
        people[e.key]!['designation']?.toString().trim() ?? '',
        e.value..sort((a, b) {
          final da = a['due_date']?.toString() ?? '9999';
          final db = b['due_date']?.toString() ?? '9999';
          return da.compareTo(db);
        }),
      ),
  ];
  groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}

class _TeamTasksData {
  _TeamTasksData(this.groups);
  final List<TeamTaskGroup> groups;
  int get done =>
      groups.fold(0, (n, g) => n + g.tasks.where(isTaskDone).length);
  int get total => groups.fold(0, (n, g) => n + g.tasks.length);
  int get open => total - done;
}

/// Read-only list of the tasks assigned to the manager's team, by person. No creating or changing of tasks.
class TeamTasksView extends StatefulWidget {
  const TeamTasksView({super.key, required this.tasks, required this.manager});

  final TasksRepository tasks;
  final ManagerRepository manager;

  @override
  State<TeamTasksView> createState() => _TeamTasksViewState();
}

class _TeamTasksViewState extends State<TeamTasksView> {
  TeamTaskFilter filter = TeamTaskFilter.all;

  Future<_TeamTasksData> _load() async {
    final r = await Future.wait([
      widget.tasks.teamTasks(),
      widget.manager.team(),
    ]);
    return _TeamTasksData(
      groupTeamTasks(
        r[0] as List<Map<String, dynamic>>,
        (r[1] as ManagerTeam).tree,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagerLoader<_TeamTasksData>(
      load: _load,
      isEmpty: (d) => d.total == 0,
      emptyText: kTeamTasksEmptyMessage,
      builder: (context, d) {
        bool keep(Map<String, dynamic> a) => switch (filter) {
          TeamTaskFilter.all => true,
          TeamTaskFilter.open => !isTaskDone(a),
          TeamTaskFilter.completed => isTaskDone(a),
        };
        final shown = [
          for (final g in d.groups)
            if (g.tasks.any(keep))
              TeamTaskGroup(
                g.name,
                g.designation,
                g.tasks.where(keep).toList(),
              ),
        ];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${d.open} open / ${d.done} done',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final f in TeamTaskFilter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      TeamTaskFilter.all => 'All',
                      TeamTaskFilter.open => 'Open',
                      TeamTaskFilter.completed => 'Completed',
                    }),
                    selected: filter == f,
                    onSelected: (_) => setState(() => filter = f),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text(kTeamTasksNoMatchMessage)),
              ),
            for (final g in shown) _group(g),
          ],
        );
      },
    );
  }

  Widget _group(TeamTaskGroup g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              g.name,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (g.designation.isNotEmpty)
              Text(
                g.designation,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            const SizedBox(height: 8),
            for (final a in g.tasks) _row(a),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> a) {
    final task = a['task'] is Map
        ? Map<String, dynamic>.from(a['task'] as Map)
        : <String, dynamic>{};
    final done = isTaskDone(a);
    final status = (a['status']?.toString() ?? '').replaceAll('_', ' ');
    final due = asDate(a['due_date']);
    final color = done
        ? Colors.green
        : (status == 'in progress' ? Colors.blue : Colors.orange);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['task_title']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (due != null)
                  Text(
                    'Due ${DateFormat('dd MMM yyyy').format(due)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          if (status.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
