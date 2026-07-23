import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EmployeeUi {
  static const Color pageBg = Color(0xFFF7F8FC);
  static const Color primary = Color(0xFF1E90FF);
  static const Color text = Color(0xFF161A23);
  static const Color muted = Color(0xFF687082);
  static const Color border = Color(0xFFE8ECF3);

  // New Design Tokens
  static const Color blueBg = Color(0xFFD7E8FF);
  static const Color tealBg = Color(0xFFD4F3F7);
  static const Color peachBg = Color(0xFFFFECE6);
  static const Color lavenderBg = Color(0xFFEBDFF6);

  static TextStyle title(double size) => GoogleFonts.montserrat(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: text,
  );

  static TextStyle header(double size) => GoogleFonts.playfairDisplay(
    fontSize: size,
    fontWeight: FontWeight.bold,
    color: text,
  );

  static TextStyle body({
    double size = 14,
    Color color = text,
    FontWeight weight = FontWeight.w500,
  }) =>
      GoogleFonts.montserrat(fontSize: size, fontWeight: weight, color: color);

  static BoxDecoration cardDecoration({
    Color color = Colors.white,
    double radius = 20,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: borderColor != null ? Border.all(color: borderColor) : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
  static AppBar appBar({
    required String title,
    String? subtitle,
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
  }) {
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.black87),
      titleSpacing: leading == null ? 20 : 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: title == ''
                ? const TextStyle(fontSize: 0)
                : EmployeeUi.title(18),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(subtitle, style: EmployeeUi.body(size: 12, color: muted)),
        ],
      ),
      actions: actions,
    );
  }
}
class EmployeeSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const EmployeeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: EmployeeUi.title(20)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: EmployeeUi.body(size: 13, color: EmployeeUi.muted),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
class EmployeeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  const EmployeeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color = Colors.white,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: EmployeeUi.cardDecoration(color: color),
      child: child,
    );
  }
}
