import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CelebrationsSection extends StatelessWidget {
  final List<dynamic> birthdays;

  const CelebrationsSection({
    super.key,
    required this.birthdays,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Colors.pinkAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                "Celebrations Today",
                style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (birthdays.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(
                  children: [
                    Icon(Icons.celebration_outlined, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(
                      "No birthdays today.\nCheck back tomorrow!",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              itemCount: birthdays.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final item = birthdays[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.pink.shade50,
                    child: Text(item['full_name']?[0] ?? '?', style: TextStyle(color: Colors.pink.shade700, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(item['full_name'] ?? '', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(item['designation'] ?? '', style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
                  trailing: const Icon(Icons.cake_outlined, color: Colors.pinkAccent, size: 20),
                );
              },
            ),
        ],
      ),
    );
  }
}
