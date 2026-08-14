import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user_profile.dart';
import '../providers/app_state_provider.dart';
import 'home_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isScanning = false;
  bool _isLoading = false;
  String? _errorMessage;

  void _onSelectTabletRole(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    appState.setupDeviceRole(
      role: DeviceRole.tablet,
      name: 'Ev Tableti (Ömer)',
    );
  }

  void _onSelectParentRole(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    appState.setupDeviceRole(
      role: DeviceRole.parent,
      name: 'Ebeveyn Telefonu',
    );
  }

  void _completePairing(String pinOrQr) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final success = await appState.pairWithDevice(pinOrQr);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _errorMessage =
            '❌ Geçersiz veya Bulunamayan Kod! Lütfen tablet ekranındaki 6 haneli kodu kontrol edin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);

    // Auto-navigate when paired remotely via Firebase listener
    if (appState.pairedProfile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      });
    }

    final myRole = appState.myProfile?.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Eşleştirme (OMEGA)'),
        actions: [
          if (appState.myProfile != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Sıfırla / Mod Değiştir',
              onPressed: () async {
                await appState.unpairAndReset();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: myRole == null
              ? _buildRoleSelection(context)
              : myRole == DeviceRole.tablet
                  ? _buildTabletPairingUI(appState.myProfile!)
                  : _buildParentPairingUI(),
        ),
      ),
    );
  }

  Widget _buildRoleSelection(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.devices_rounded, size: 70, color: Color(0xFF00E5FF)),
        const SizedBox(height: 20),
        const Text(
          'Bu Cihazı Nasıl Kullanacaksınız?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Evde duracak SIM kartsız tablet mi yoksa arama yapacak ebeveyn telefonu mu?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 40),
        ElevatedButton.icon(
          icon: const Icon(Icons.tablet_android_rounded, size: 28),
          label: const Text('EV TABLETİ OLARAK KUR'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(20),
            backgroundColor: const Color(0xFF161B22),
            foregroundColor: const Color(0xFF00E5FF),
            side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
          ),
          onPressed: () => _onSelectTabletRole(context),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.phone_iphone_rounded, size: 28),
          label: const Text('EBEVEYN TELEFONU OLARAK BAĞLAN'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(20),
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
          ),
          onPressed: () => _onSelectParentRole(context),
        ),
      ],
    );
  }

  Widget _buildTabletPairingUI(UserProfile profile) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Text(
            'Ev Tableti Hazır!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ebeveyn telefonundan bu QR kodu taratın veya 6 haneli kodu yazın:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: QrImageView(
              data: profile.pairCode,
              version: QrVersions.auto,
              size: 190.0,
            ),
          ),
          const SizedBox(height: 24),
          const Text('EŞLEŞTİRME KODU', style: TextStyle(letterSpacing: 2)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00E5FF)),
            ),
            child: Text(
              profile.pairCode,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: Color(0xFF00E5FF),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // --- Live Listening Indicator ---
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ebeveyn telefona ${profile.pairCode} yazınca tablet otomatik açılacaktır...',
                    style:
                        const TextStyle(color: Color(0xFF00E5FF), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentPairingUI() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Text(
            'Tableti Bağla',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ev tabletinin ekranındaki 6 haneli kodu girin:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 32,
              letterSpacing: 6,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
            decoration: InputDecoration(
              hintText: '638813',
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF00E5FF)),
              ),
            ),
            onChanged: (val) {
              if (val.length == 6) {
                _completePairing(val);
              }
            },
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ElevatedButton.icon(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: Text(_isLoading ? 'KONTROL EDİLİYOR...' : 'KOD İLE BAĞLAN'),
            onPressed: () {
              if (_pinController.text.length == 6) {
                _completePairing(_pinController.text);
              }
            },
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Expanded(child: Divider(color: Colors.grey)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('VEYA', style: TextStyle(color: Colors.grey)),
              ),
              Expanded(child: Divider(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 24),
          _isScanning
              ? SizedBox(
                  height: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: MobileScanner(
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        for (final barcode in barcodes) {
                          if (barcode.rawValue != null) {
                            setState(() => _isScanning = false);
                            _completePairing(barcode.rawValue!);
                            break;
                          }
                        }
                      },
                    ),
                  ),
                )
              : OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('TABLET QR KODUNU TARAT'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: () => setState(() => _isScanning = true),
                ),
        ],
      ),
    );
  }
}
