import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in person's own task assignments.
class TasksRepository extends BaseRepository {
  TasksRepository({super.auth});

  /// `GET /organizations/:orgId/tasks?assignedTo=<own employee id>` -> `{items, total}`; each item is an assignment
  /// (`status`, `due_date`, `employee_id`) with its task under `task` (`task_title`, `task_type`, `task_description`,
  /// `priority`, `checklist_items`).
  ///
  /// For a manager the server would also return the assignments of everyone in their reporting tree. The screen is the
  /// manager's OWN task list (the original filtered on their own employee id), so the request names the caller and the
  /// answer is filtered again to the caller's own assignments: nobody else's task is ever requested or shown.
  Future<List<Map<String, dynamic>>> myTasks() async {
    final me = employeeId;
    final data = await api.get(orgPath('/tasks'), query: {'assignedTo': me});
    return asMapList(
      data,
    ).where((a) => a['employee_id']?.toString() == me).toList();
  }
}
