import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class TeamAttendanceSection extends StatelessWidget {
  final List<dynamic> attendance;

  const TeamAttendanceSection({
    super.key,
    required this.attendance,
  });

  @override
  Widget build(BuildContext context) {
    if (attendance.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.access_time, size: 60, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text("No attendance records", style: GoogleFonts.montserrat(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header Row
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                Expanded(flex: 3, child: _headerCell("Employee")),
                Expanded(flex: 2, child: _headerCell("Date")),
                Expanded(flex: 2, child: _headerCell("Status")),
              ],
            ),
          ),
          // Data Rows
          ...attendance.map((item) {
            final String employee = item['employee_records']?['full_name'] ?? 'Unknown';
            final String date = item['date'] ?? '-';
            final String status = item['status'] ?? 'absent';
            
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      employee,
                      style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      date,
                      style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _buildStatusPill(status),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey),
    );
  }

  Widget _buildStatusPill(String status) {
    Color color = Colors.red;
    if (status.toLowerCase() == 'present') color = Colors.green;
    if (status.toLowerCase() == 'half day') color = Colors.orange;

    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.toUpperCase(),
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
