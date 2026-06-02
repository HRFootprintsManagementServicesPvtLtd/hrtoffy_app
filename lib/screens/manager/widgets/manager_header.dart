import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class ManagerHeader extends StatelessWidget {
  final String employeeName;

  const ManagerHeader({
    super.key,
    required this.employeeName,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = employeeName.split(' ')[0];
    final dateStr = DateFormat("EEEE, d MMMM yyyy").format(DateTime.now());
    final timeStr = DateFormat("hh:mm a").format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.montserrat(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            children: [
              const TextSpan(text: "Welcome back, "),
              TextSpan(
                text: "$firstName 🖐️",
                style: const TextStyle(color: Color(0xFF1E90FF)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Here's what's happening today",
          style: GoogleFonts.montserrat(
            fontSize: 15,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "$dateStr at $timeStr",
          style: GoogleFonts.montserrat(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
}
