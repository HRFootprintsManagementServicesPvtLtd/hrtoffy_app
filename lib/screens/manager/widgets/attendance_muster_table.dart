import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/manager_attendance_repository.dart';

/// One muster cell: what to print and in which colour. `code` is one of
/// P, LT, HD, A, ES, L, H, OFF, NR (past day with no record) or `-` (day not over yet).
class MusterCell {
  const MusterCell(this.code, this.color);
  final String code;
  final Color color;
}

/// One person's month: a cell per day plus the totals printed after the grid.
class MusterRow {
  MusterRow(this.cells);
  final List<MusterCell> cells;
  int get present => cells
      .where((c) => c.code == 'P' || c.code == 'LT' || c.code == 'HD')
      .length;
  int get leave => cells.where((c) => c.code == 'L').length;
  int get holidays => cells.where((c) => c.code == 'H').length;
  int get absent => cells.where((c) => c.code == 'A' || c.code == 'ES').length;
  int get noRecord => cells.where((c) => c.code == 'NR').length;
}

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// The cell for [day] of one person. A server record always wins; without one the day is a holiday, a weekly off
/// (only when the organization's working days are known), a leave still to come, "-" when the day is not over, and
/// otherwise `NR`: no record, which is not the same as absent and is never counted as absence.
MusterCell musterCellFor({
  required DateTime day,
  required DateTime today,
  Map<String, dynamic>? record,
  required Map<String, String> holidays,
  Set<String>? workingDays,
  List<UpcomingLeave> upcomingLeaves = const [],
}) {
  final ymd = ManagerAttendanceRepository.ymd(day);
  if (record != null) {
    switch ((record['status'] ?? '').toString().toLowerCase()) {
      case 'present':
        return MusterCell('P', Colors.green);
      case 'late':
        return MusterCell('LT', Colors.orange);
      case 'half day':
      case 'half_day':
        return MusterCell('HD', Colors.orangeAccent);
      case 'absent':
        return MusterCell('A', Colors.red);
      case 'esi absence':
      case 'esi_absence':
        return MusterCell('ES', Colors.red.shade300);
      case 'on leave':
      case 'on_leave':
        return MusterCell('L', Colors.blue.shade300);
      case 'holiday':
        return MusterCell('H', Colors.purple.shade300);
      case 'weekly off':
      case 'weekly_off':
        return MusterCell('OFF', Colors.grey.shade400);
    }
  }
  if (holidays.containsKey(ymd)) {
    return MusterCell('H', Colors.purple.shade300);
  }
  if (workingDays != null &&
      !workingDays.contains(_weekdays[day.weekday - 1])) {
    return MusterCell('OFF', Colors.grey.shade400);
  }
  if (upcomingLeaves.any((l) => l.covers(ymd))) {
    return MusterCell('L', Colors.blue.shade300);
  }
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  if (!d.isBefore(t)) return const MusterCell('-', Colors.grey);
  return MusterCell('NR', Colors.blueGrey.shade300);
}

/// The month grid (team x days) with P / PL / H / A / NR totals, as in the original muster.
class AttendanceMusterTable extends StatelessWidget {
  const AttendanceMusterTable({
    super.key,
    required this.members,
    required this.month,
    required this.today,
    required this.recordsByKey,
    required this.holidays,
    required this.workingDays,
    required this.upcomingLeaves,
    required this.onLocation,
  });

  final List<Map<String, dynamic>> members;
  final DateTime month;
  final DateTime today;

  /// `<employeeId>|<yyyy-MM-dd>` -> the server's attendance row.
  final Map<String, Map<String, dynamic>> recordsByKey;
  final Map<String, String> holidays;
  final Set<String>? workingDays;
  final Map<String, List<UpcomingLeave>>? upcomingLeaves;
  final void Function(Map<String, dynamic> member) onLocation;

  static String recordKey(String employeeId, String ymd) => '$employeeId|$ymd';

  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    TextStyle head(double s) =>
        TextStyle(fontSize: s, fontWeight: FontWeight.bold);
    final rows = <DataRow>[];
    for (final m in members) {
      final id = m['id'].toString();
      final name = (m['full_name'] ?? 'Unknown').toString();
      final row = MusterRow([
        for (var i = 1; i <= days; i++)
          musterCellFor(
            day: DateTime(month.year, month.month, i),
            today: today,
            record:
                recordsByKey[recordKey(
                  id,
                  ManagerAttendanceRepository.ymd(
                    DateTime(month.year, month.month, i),
                  ),
                )],
            holidays: holidays,
            workingDays: workingDays,
            upcomingLeaves: upcomingLeaves?[id] ?? const [],
          ),
      ]);
      Widget cell(String t, Color c) => Container(
        width: 25,
        alignment: Alignment.center,
        child: Text(
          t,
          style: GoogleFonts.montserrat(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: c,
          ),
        ),
      );
      rows.add(
        DataRow(
          cells: [
            DataCell(
              SizedBox(
                width: 110,
                child: Row(
                  children: [
                    InkWell(
                      key: ValueKey('muster-location-$id'),
                      onTap: () => onLocation(m),
                      child: const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final c in row.cells) DataCell(cell(c.code, c.color)),
            DataCell(cell('${row.present}', Colors.black)),
            DataCell(cell('${row.leave}', Colors.black)),
            DataCell(cell('${row.holidays}', Colors.black)),
            DataCell(cell('${row.absent}', Colors.black)),
            DataCell(cell('${row.noRecord}', Colors.black)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 10,
        horizontalMargin: 10,
        headingRowHeight: 40,
        columns: [
          DataColumn(
            label: SizedBox(
              width: 110,
              child: Text('Employee', style: head(10)),
            ),
          ),
          for (var i = 1; i <= days; i++)
            DataColumn(
              label: Container(
                width: 25,
                alignment: Alignment.center,
                child: Text('$i', style: const TextStyle(fontSize: 9)),
              ),
            ),
          DataColumn(label: Text('P', style: head(9))),
          DataColumn(label: Text('PL', style: head(9))),
          DataColumn(label: Text('H', style: head(9))),
          DataColumn(label: Text('A', style: head(9))),
          DataColumn(label: Text('NR', style: head(9))),
        ],
        rows: rows,
      ),
    );
  }
}
