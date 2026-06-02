import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SnapshotSection extends StatelessWidget {
  final Map<String, dynamic>? employee;

  const SnapshotSection({
    super.key,
    required this.employee,
  });

  @override
  Widget build(BuildContext context) {
    if (employee == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3F2FD)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title and Designation - Fixed with Expanded to prevent overflow
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.info_outline_rounded, color: Color(0xFF1E90FF), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Your Details Snapshot",
                      style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      employee?['organization_name'] ?? 'HR TOFFY',
                      style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (employee?['designation'] != null)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    employee!['designation'].toString().toUpperCase(),
                    style: GoogleFonts.montserrat(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Info Grid using Wrap to prevent horizontal overflow
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              _infoItem(Icons.person_outline, "Name", employee?['full_name'] ?? '-'),
              _infoItem(Icons.badge_outlined, "ID", employee?['employee_id'] ?? employee?['id']?.toString().substring(0, 8) ?? '-'),
              _infoItem(Icons.work_outline, "Department", employee?['department'] ?? '-'),
              _infoItem(Icons.email_outlined, "Email", employee?['email'] ?? '-'),
              _infoItem(Icons.location_on_outlined, "Location", employee?['location'] ?? 'Not Set'),
              _infoItem(Icons.business_outlined, "Assigned worksite", employee?['assigned_worksite'] ?? 'Main Office'),
            ],
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(height: 1, thickness: 0.5),
          ),
          
          // Approvers section using Wrap to prevent overflow
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_tree_outlined, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text("Reporting Structure:", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
              _approverTag("Manager", employee?['manager_name']),
              _approverTag("Reviewer", employee?['reviewer_name']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return SizedBox(
      width: 145, // Constraint for Wrap items
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _approverTag(String label, dynamic name) {
    if (name == null || name.toString().isEmpty) return const SizedBox();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$label: ", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey)),
        Text(
          name.toString(),
          style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
      ],
    );
  }
}
