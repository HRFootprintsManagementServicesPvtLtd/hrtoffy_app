import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'dashboard_screen.dart';

class GifSplashScreen extends StatefulWidget {
  const GifSplashScreen({Key? key}) : super(key: key);

  @override
  State<GifSplashScreen> createState() => _GifSplashScreenState();
}

class _GifSplashScreenState extends State<GifSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    // Smooth animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo),
    );

    _controller.forward();

    // After 3 seconds → route based on session
    Future.delayed(const Duration(seconds: 1), _routeNext);
  }

  Future<void> _routeNext() async {
    final supabase = Supabase.instance.client;

    // Give Supabase a moment to restore session
    await Future.delayed(const Duration(milliseconds: 300));

    final session = supabase.auth.currentSession;

    if (!mounted) return;

    if (session != null) {
      final email = session.user.email ?? "";
      await FirebaseNotificationService.setupFCM(userEmail: email);

      // Fetch employee UUID safely
      final empRes = await supabase
          .from("employee_records")
          .select("id")
          .eq("email", email)
          .maybeSingle();

      final employeeId = empRes?['id'] ?? session.user.id;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            email: email,
            employeeId: employeeId,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Image.asset(
              "assets/grok-video-5ee1fb5d-6d43-46a9-a750-f8faff7b1a87.gif",
              width: size.width * 0.55,
              height: size.width * 0.55,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
