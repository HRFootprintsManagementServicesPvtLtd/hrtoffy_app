import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TeamTabs extends StatelessWidget {
  final String selected;
  final Function(String) onChanged;
  final int allCount;
  final int directCount;
  final int indirectCount;
  final int reviewCount;

  const TeamTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.allCount,
    required this.directCount,
    required this.indirectCount,
    required this.reviewCount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTab("all", "All ($allCount)", Icons.person_search_outlined),
          _buildTab("direct", "Direct ($directCount)", Icons.person_outline),
          _buildTab("indirect", "Indirect ($indirectCount)", Icons.people_outline),
          _buildTab("reviewer", "Review ($reviewCount)", Icons.remove_red_eye_outlined),
        ],
      ),
    );
  }

  Widget _buildTab(String key, String label, IconData icon) {
    final bool isSelected = selected == key;

    return GestureDetector(
      onTap: () => onChanged(key),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E90FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? null : Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
