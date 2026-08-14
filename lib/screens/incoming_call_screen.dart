import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call_session.dart';
import '../providers/app_state_provider.dart';
import '../widgets/profile_avatar.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final session = appState.activeCall;
    final callerName = session?.callerName ?? 'Evdeki Cihaz';
    final isVideo = session?.type == CallType.video;

    return Scaffold(
      backgroundColor: const Color(0xFF384353),
      body: SafeArea(
        child: Stack(
          children: [
            // --- Matching Gradient Background (Identical to CallScreen) ---
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF5B6578), Color(0xFF384353)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Profile Avatar matching CallScreen
                    ProfileAvatar(
                      profile: appState.pairedProfile,
                      radius: 60,
                      borderWidth: 3,
                      borderColor: Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      callerName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isVideo ? 'Gelen Görüntülü Arama...' : 'Gelen Sesli Arama...',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 100), // Spacing for floating bottom bar
                  ],
                ),
              ),
            ),

            // --- Floating Liquid Glass Action Control Bar (Identical to CallScreen style) ---
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Decline Button (Red Circle)
                          GestureDetector(
                            onTap: () async {
                              await appState.rejectCall();
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 66,
                                  height: 66,
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red,
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.call_end_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Reddet',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 52),

                          // Accept Button (Green Circle)
                          GestureDetector(
                            onTap: () async {
                              await appState.acceptCall();
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 66,
                                  height: 66,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00E676),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF00E676),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.call_rounded,
                                    color: Colors.black,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Cevapla',
                                  style: TextStyle(
                                    color: Color(0xFF00E676),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
