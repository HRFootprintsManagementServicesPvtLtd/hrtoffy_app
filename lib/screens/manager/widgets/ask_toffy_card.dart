import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AskToffyCard extends StatelessWidget {
  const AskToffyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFE3F2FD).withOpacity(0.6), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E90FF).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E90FF).withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E90FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                "ASK TOFFY",
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E90FF),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Ask anything about my team...",
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              const Icon(Icons.send_rounded, color: Colors.blueAccent, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildActionChip("Who in my team is on leave today?"),
                _buildActionChip("Show pending approvals"),
                _buildActionChip("My team's attendance this week"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E90FF).withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: GoogleFonts.montserrat(
          fontSize: 12,
          color: const Color(0xFF1E90FF),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
