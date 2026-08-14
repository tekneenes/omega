import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'models/call_session.dart';
import 'providers/app_state_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/call_screen.dart';
import 'screens/incoming_call_screen.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initializeDateFormatting('tr_TR', null);
    await initializeDateFormatting('tr', null);
  } catch (e) {
    debugPrint('Date formatting initialization notice: $e');
  }

  FlutterError.onError = (details) {
    final errStr = details.exception.toString();
    if (kIsWeb &&
        (errStr.contains('LegacyJavaScriptObject') ||
            errStr.contains('disposed EngineFlutterView') ||
            errStr.contains('!isDisposed'))) {
      return;
    }
    FlutterError.presentError(details);
  };

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase initialized notice: $e');
  }
  runApp(const OmegaCallApp());
}

class OmegaCallApp extends StatelessWidget {
  const OmegaCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppStateProvider(),
      child: MaterialApp(
        title: 'Omega',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        builder: (context, child) {
          return GlobalCallOverlay(child: child ?? const SizedBox());
        },
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
        },
      ),
    );
  }
}

class GlobalCallOverlay extends StatelessWidget {
  final Widget child;
  const GlobalCallOverlay({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<AppStateProvider>(
          builder: (context, appState, _) {
            final activeCall = appState.activeCall;
            if (activeCall == null) {
              return const SizedBox.shrink();
            }

            Widget callOverlay;
            if (activeCall.status == CallStatus.ringing) {
              callOverlay = const IncomingCallScreen();
            } else if (activeCall.status == CallStatus.calling ||
                       activeCall.status == CallStatus.connected ||
                       activeCall.status == CallStatus.ended ||
                       activeCall.status == CallStatus.rejected ||
                       activeCall.status == CallStatus.busy) {
              callOverlay = const CallScreen();
            } else {
              return const SizedBox.shrink();
            }

            return Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: callOverlay,
              ),
            );
          },
        ),
      ],
    );
  }
}
