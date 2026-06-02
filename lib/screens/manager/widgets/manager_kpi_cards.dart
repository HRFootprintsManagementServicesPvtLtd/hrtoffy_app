import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ManagerKpiCards extends StatelessWidget {
  final int directReports;
  final int indirectReports;
  final int reviewCount;
  final int onLeaveCount;

  const ManagerKpiCards({
    super.key,
    required this.directReports,
    required this.indirectReports,
    required this.reviewCount,
    required this.onLeaveCount,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildKpiCard(
          icon: Icons.people_outline_rounded,
          count: directReports,
          label: "Direct Reports",
          color: const Color(0xFFE8EAF6),
          iconColor: Colors.blueAccent,
        ),
        _buildKpiCard(
          icon: Icons.groups_3_outlined,
          count: indirectReports,
          label: "Indirect Reports",
          color: const Color(0xFFE8F5E9),
          iconColor: Colors.green,
        ),
        _buildKpiCard(
          icon: Icons.remove_red_eye_outlined,
          count: reviewCount,
          label: "Under My Review",
          color: const Color(0xFFFFF3E0),
          iconColor: Colors.orange,
        ),
        _buildKpiCard(
          icon: Icons.calendar_today_outlined,
          count: onLeaveCount,
          label: "On Leave",
          color: const Color(0xFFE3F2FD),
          iconColor: Colors.lightBlue,
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required int count,
    required String label,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const Spacer(),
          Text(
            count.toString(),
            style: GoogleFonts.montserrat(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
