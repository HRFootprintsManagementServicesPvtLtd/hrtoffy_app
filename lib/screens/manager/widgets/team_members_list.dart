import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TeamMembersList extends StatelessWidget {
  final List<dynamic> members;

  const TeamMembersList({
    super.key,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 60, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text("No team members found", style: GoogleFonts.montserrat(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: members.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final item = members[index];
        final String name = item['full_name'] ?? 'Unknown';
        final String empId = item['employee_id'] ?? '-';
        final String designation = item['designation'] ?? '-';
        final String status = item['employment_status'] ?? 'active';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1E90FF).withOpacity(0.1),
              child: Text(name[0].toUpperCase(), style: const TextStyle(color: Color(0xFF1E90FF), fontWeight: FontWeight.bold)),
            ),
            title: Text(
              name,
              style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              designation,
              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54),
            ),
            trailing: _buildStatusPill(status),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildDetailRow("Employee ID", empId),
                    _buildDetailRow("Department", item['department'] ?? '-'),
                    _buildDetailRow("Email", item['email'] ?? '-'),
                    _buildDetailRow("Reports To", item['manager_name'] ?? 'Self'),
                    _buildDetailRow("Relation", item['relation_type'] ?? 'Direct'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusPill(String status) {
    final bool isActive = status.toLowerCase() == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: isActive ? Colors.green.shade700 : Colors.red.shade700,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
          Text(value, style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
