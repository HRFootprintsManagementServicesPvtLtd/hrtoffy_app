import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../manager_engage_screen.dart';

class EngagementSection extends StatelessWidget {
  final int announcements;
  final int events;
  final int surveys;
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const EngagementSection({
    super.key,
    required this.announcements,
    required this.events,
    required this.surveys,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ManagerEngageScreen(
              userEmail: userEmail,
              userData: userData,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Engagement",
              style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              "Active communications & activities",
              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildEngageItem(Icons.campaign_outlined, announcements, "Announcements", Colors.blueGrey),
                _buildEngageItem(Icons.event_available_outlined, events, "Events", Colors.blueAccent),
                _buildEngageItem(Icons.poll_outlined, surveys, "Surveys", Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngageItem(IconData icon, int count, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          count.toString(),
          style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
