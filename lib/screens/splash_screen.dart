import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import 'onboarding_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAndNavigate();
    });
  }

  Future<void> _initAndNavigate() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    await appState.initializeApp();

    if (!mounted) return;

    if (appState.myProfile == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient Glow Orb 1 (Top Left)
            Positioned(
              top: -80,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00E676).withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Ambient Glow Orb 2 (Bottom Right)
            Positioned(
              bottom: -100,
              right: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF3B82F6).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Center Content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glassmorphic Logo Container
                Container(
                  width: 110,
                  height: 110,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.35),
                        blurRadius: 32,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/app_logo.png',
                      width: 104,
                      height: 104,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // App Title
                const Text(
                  'OMEGA',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Color(0xFF00E676),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 54),

                // Sleek Pulsing Loading Indicator
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF00E676)),
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
