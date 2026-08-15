import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../models/call_session.dart';
import '../providers/app_state_provider.dart';
import '../services/security_service.dart';
import '../services/legal_terms_service.dart';
import '../services/firebase_config_service.dart';
import '../firebase_options.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_glass_card.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;

  final TextEditingController _firebaseUrlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _targetPinController = TextEditingController();
  final TextEditingController _targetPhoneController = TextEditingController();
  final TextEditingController _targetEmailController = TextEditingController();

  final DeviceRole _selectedRole = DeviceRole.tablet;
  String _selectedAvatar = 'tablet';
  String? _customPhotoPath;
  Uint8List? _customPhotoBytes;
  PairingMethod _selectedMethod = PairingMethod.pinCode;
  String _generatedPin = '';

  bool _micGranted = false;
  bool _camGranted = false;
  bool _notifGranted = false;
  bool _isLoading = false;
  bool _eulaAccepted = false;

  // BYODB Firebase State
  String _networkMode = 'create'; // 'create' or 'join'
  bool _isTestingConnection = false;
  Map<String, dynamic>? _connectionTestResult;
  bool _isDeployingRules = false;
  Map<String, dynamic>? _rulesDeployResult;
  bool _manualRulesConfirmed = false;
  bool _adminOnlySharing = true;
  bool _showStep5NetworkQr = false;

  bool get _isConnectionVerified =>
      _connectionTestResult != null && _connectionTestResult!['success'] == true;

  bool get _isRulesConfigured =>
      (_rulesDeployResult != null && _rulesDeployResult!['success'] == true) ||
      _manualRulesConfirmed;

  void _showEulaDialog() {
    LegalTermsService.showLegalTermsModal(
      context,
      isMandatoryAcceptance: true,
      onAccepted: () {
        setState(() => _eulaAccepted = true);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _generatedPin = SecurityService.generatePairPin();
    _initFirebaseUrl();
    _checkPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkEulaAndClipboard();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    _firebaseUrlController.clear();
    _connectionTestResult = null;
    _rulesDeployResult = null;
    _manualRulesConfirmed = false;
  }

  Future<void> _initFirebaseUrl() async {
    await FirebaseConfigService.clearSavedRtdbUrl();
    if (mounted) {
      setState(() {
        _firebaseUrlController.clear();
        _connectionTestResult = null;
        _rulesDeployResult = null;
        _manualRulesConfirmed = false;
      });
    }
  }

  Future<void> _checkEulaAndClipboard() async {
    final audit = await LegalTermsService.getAcceptanceRecord();
    if (audit['accepted'] != true) {
      _showEulaDialog();
    }
  }

  Future<void> _pasteFirebaseUrlFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      final text = data.text!.trim();
      if (text.contains('firebaseio.com') || text.contains('firebasedatabase.app')) {
        setState(() {
          _firebaseUrlController.text = FirebaseConfigService.cleanRtdbUrl(text);
          _connectionTestResult = null;
          _rulesDeployResult = null;
        });
        _testFirebaseConnection();
      } else {
        setState(() {
          _firebaseUrlController.text = text;
        });
      }
    }
  }

  Future<void> _testFirebaseConnection() async {
    final rawUrl = _firebaseUrlController.text.trim();
    if (rawUrl.isEmpty) return;

    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
    });

    final result = await FirebaseConfigService.testConnection(rawUrl);
    if (result['success'] == true) {
      await FirebaseConfigService.saveActiveRtdbUrl(rawUrl);
    }

    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _connectionTestResult = result;
      });
    }
  }

  Future<void> _deployFirebaseRules() async {
    final rawUrl = _firebaseUrlController.text.trim();
    if (rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Lütfen önce bir veritabanı URL\'si giriniz.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Always copy rules to clipboard first
    await Clipboard.setData(ClipboardData(text: FirebaseConfigService.formattedRulesJson));

    setState(() {
      _isDeployingRules = true;
      _rulesDeployResult = null;
    });

    final result = await FirebaseConfigService.deployRules(rawUrl);
    if (mounted) {
      setState(() {
        _isDeployingRules = false;
        _rulesDeployResult = result;
      });

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Güvenlik kuralları başarıyla yüklendi!'),
            backgroundColor: Color(0xFF00E676),
          ),
        );
      } else {
        // Automatically open the helper modal for 1-click copy and manual confirmation
        _showRulesDeployModal();
      }
    }
  }

  Future<void> _checkPermissions() async {
    final mic = await Permission.microphone.status;
    final cam = await Permission.camera.status;
    final notif = await Permission.notification.status;

    setState(() {
      _micGranted = mic.isGranted;
      _camGranted = cam.isGranted;
      _notifGranted = notif.isGranted;
    });
  }

  Future<void> _requestAllPermissions() async {
    if (kIsWeb) {
      // Web browser permission request via WebRTC getUserMedia
      try {
        final appState = Provider.of<AppStateProvider>(context, listen: false);
        await appState.webRTCService.openUserMedia(CallType.video);
        setState(() {
          _micGranted = true;
          _camGranted = true;
          _notifGranted = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Tarayıcı Kamera ve Mikrofon İzinleri Doğrulandı!'),
              backgroundColor: Color(0xFF00E676),
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ Web permission error: $e');
      }
    } else {
      // Android, iOS, macOS native permission request
      final mic = await Permission.microphone.request();
      final cam = await Permission.camera.request();
      final notif = await Permission.notification.request();

      bool micG = mic.isGranted;
      bool camG = cam.isGranted;

      // On iOS, trigger native WebRTC hardware prompt if permission_handler was pending
      if (defaultTargetPlatform == TargetPlatform.iOS && (!micG || !camG)) {
        try {
          final stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
          micG = true;
          camG = true;
          for (final t in stream.getTracks()) {
            t.stop();
          }
          await stream.dispose();
        } catch (_) {}
      }

      setState(() {
        _micGranted = micG;
        _camGranted = camG;
        _notifGranted = notif.isGranted;
      });

      if (!_micGranted || !_camGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️ Bazı izinler reddedildi. "Sistem İzin Ayarlarını Aç" butonunu kullanarak izin verebilirsiniz.',
              ),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'AYARLAR',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
    }
  }

  // --- Step 3: System Permissions Check (macOS, Web, iOS, Android Platform-Aware) ---
  Widget _buildStep3PermissionCheck() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sistem İzinleri & Doğrulama',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Görüşmelerin sorunsuz çalışması için sistem izinlerini doğrulayın:',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 24),

        // Interactive Permission Check List
        LiquidGlassCard(
          child: Column(
            children: [
              _buildPermissionTile(
                icon: Icons.phone_in_talk_rounded,
                title: 'Mikrofon İzni',
                subtitle: 'Sesli telefon aramaları ve karşılıklı sesli mesajlaşma için gereklidir.',
                isGranted: _micGranted,
                onTap: () async {
                  if (kIsWeb) {
                    _requestAllPermissions();
                  } else {
                    var status = await Permission.microphone.request();
                    if (!status.isGranted && defaultTargetPlatform == TargetPlatform.iOS) {
                      try {
                        final stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
                        for (final t in stream.getTracks()) {
                          t.stop();
                        }
                        await stream.dispose();
                        status = PermissionStatus.granted;
                      } catch (_) {}
                    }
                    setState(() => _micGranted = status.isGranted);
                  }
                },
              ),
              const Divider(color: Colors.white24),
              _buildPermissionTile(
                icon: Icons.videocam_rounded,
                title: 'Kamera İzni',
                subtitle: 'Görüntülü telefon aramaları ve karşılıklı kamera bağlantısı için gereklidir.',
                isGranted: _camGranted,
                onTap: () async {
                  if (kIsWeb) {
                    _requestAllPermissions();
                  } else {
                    var status = await Permission.camera.request();
                    if (!status.isGranted && defaultTargetPlatform == TargetPlatform.iOS) {
                      try {
                        final stream = await navigator.mediaDevices.getUserMedia({'audio': false, 'video': true});
                        for (final t in stream.getTracks()) {
                          t.stop();
                        }
                        await stream.dispose();
                        status = PermissionStatus.granted;
                      } catch (_) {}
                    }
                    setState(() => _camGranted = status.isGranted);
                  }
                },
              ),
              const Divider(color: Colors.white24),
              _buildPermissionTile(
                icon: Icons.notifications_active_rounded,
                title: 'Bildirim İzni',
                subtitle: 'Gelen telefon aramalarını, alarmları ve anlık mesajları almak için gereklidir.',
                isGranted: _notifGranted,
                onTap: () async {
                  if (!kIsWeb) {
                    final status = await Permission.notification.request();
                    setState(() => _notifGranted = status.isGranted);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action Buttons: Grant All & Open System Settings
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _requestAllPermissions,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_user_rounded, size: 20),
                    SizedBox(width: 6),
                    Text('İZİN İSTE VE ONAYLA',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
                onPressed: () => openAppSettings(),
                child: const Row(
                  children: [
                    Icon(Icons.settings_rounded, size: 20, color: Colors.white),
                    SizedBox(width: 6),
                    Text('AYARLAR',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Statutory & Technical Privacy Shield for Hardware Permissions
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.security_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'DONANIM İZİNLERİ & GİZLİLİK GÜVENCESİ',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildStep0LegalRow(
                badgeText: 'Mikrofon',
                badgeColor: const Color(0xFF00E676),
                title: 'Sesli Arama & Mesajlaşma (TCK m. 132-133):',
                description:
                    'Mikrofon yalnızca canlı sesli telefon aramalarında ve bas-konuş sesli mesaj gönderirken kullanılır. Arka planda gizli ortam dinlemesi veya rızasız ses kaydı kesinlikle yapılmaz.',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'Kamera',
                badgeColor: Colors.amber,
                title: 'Görüntülü Arama & P2P Şifreleme (TCK m. 134):',
                description:
                    'Kamera yalnızca görüntülü aramalarda ve karşılıklı onaylanan kamera istasyon modunda açılır. Canlı yayın doğrudan cihazlar arasında P2P şifreli akar; sunucularda depolanmaz.',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'Bildirim',
                badgeColor: Colors.orangeAccent,
                title: 'Gelen Arama & Mesaj İletimi (KVKK m. 10):',
                description:
                    'Ekran kilitliyken veya uygulama kapalıyken gelen telefon aramalarını, çağrı sesini ve anlık mesajları iletmek için kullanılır. Reklam veya pazarlama bildirimi gönderilmez.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => setState(() => _currentStep = 1),
                child: const Text('Geri'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => setState(() => _currentStep = 3),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('DEVAM ET',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openNetworkQRScannerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF384353),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '📷 Aile Ağı QR Kodunu Taratın',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '1. Cihazın ekranındaki Aile Ağı QR kodunu kameranızla okutun:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MobileScanner(
                  onDetect: (capture) async {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                        final raw = barcode.rawValue!;
                        final parsedUrl = FirebaseConfigService.parseNetworkQrPayload(raw);
                        if (parsedUrl != null) {
                          Navigator.pop(ctx);
                          _showJoinNetworkTrustDialog(parsedUrl);
                          break;
                        }
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinNetworkTrustDialog(String targetUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.amber, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aile Ağına Katılma Onayı',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_done_rounded, color: Color(0xFF00E676), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        targetUrl,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '⚠️ DİKKAT VE GÜVEN UYARISI (KVKK m. 8 & TCK m. 132-134):',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const Text(
                'Bu QR kod 3. bir şahsın Firebase veritabanına bağlanmanızı sağlar. Cihaz sinyalizasyon bilgileriniz bu veritabanına aktarılacaktır.\n\n• Yalnızca kesin olarak güvendiğiniz aile üyelerinin QR kodunu onaylayın.\n• Eşler dahil yetişkin bireylerin rızasız gizli izlenmesi TCK m. 132-134 uyarınca suçtur.\n• Tüm görüşmeler doğrudan (P2P) şifreli olarak iki cihaz arasında gerçekleşir.',
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              _firebaseUrlController.text = targetUrl;
              setState(() => _isTestingConnection = true);
              final testRes = await FirebaseConfigService.testConnection(targetUrl);
              await FirebaseConfigService.saveActiveRtdbUrl(targetUrl);
              await FirebaseConfigService.setIsNetworkAdmin(false);
              if (mounted) {
                setState(() {
                  _isTestingConnection = false;
                  _connectionTestResult = testRes;
                  _currentStep = 1;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🎉 Aile Veritabanına Başarıyla Katıldınız!'),
                    backgroundColor: Color(0xFF00E676),
                  ),
                );
              }
            },
            child: const Text('GÜVENİYORUM & KATIL', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRulesDeployModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFF00E676), size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Güvenlik Kuralları (Rules) Yayınlama',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Google güvenlik mimarisi gereği, kuralları değiştirmek için Firebase Console yetkisi gerekir (403). Kurallar panonuza kopyalandı.',
                      style: TextStyle(color: Colors.white, fontSize: 11, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nasıl Yayınlanır? (3 Kolay Adım):',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _buildGuideStepCard(
              stepNum: '1',
              title: 'Firebase Console\'a Gidin',
              description: 'console.firebase.google.com açın > Realtime Database > Kurallar (Rules) sekmesine girin.',
            ),
            const SizedBox(height: 6),
            _buildGuideStepCard(
              stepNum: '2',
              title: 'Panodaki Kuralları Yapıştırın',
              description: 'Mevcut kuralları silip aşağıdaki kopyalanan JSON kurallarını yapıştırın.',
            ),
            const SizedBox(height: 6),
            _buildGuideStepCard(
              stepNum: '3',
              title: 'Yayınla (Publish) Butonuna Basın',
              description: 'Sağ üstteki "Yayınla" butonuna tıklayıp kuralları aktif edin.',
            ),
            const SizedBox(height: 12),

            // Code Preview Box with Copy Button
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📋 Omega Rules JSON',
                          style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: FirebaseConfigService.formattedRulesJson));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('📋 Kurallar panoya kopyalandı!'),
                                backgroundColor: Color(0xFF00E676),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.copy_rounded, size: 12, color: Color(0xFF00E676)),
                                SizedBox(width: 4),
                                Text('Kopyala', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          FirebaseConfigService.formattedRulesJson,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Big Confirmation Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 20),
                label: const Text(
                  'YAYINLADIM, KURALLARI ONAYLA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _manualRulesConfirmed = true;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🎉 Güvenlik kuralları başarıyla onaylandı!'),
                      backgroundColor: Color(0xFF00E676),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRulesRequiredDialog() {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.amber, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Colors.amber, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Güvenlik Kuralları Zorunludur',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Veritabanınızı yetkisiz erişimlere ve veri sızıntılarına karşı korumak için Omega Güvenlik Kurallarını (Rules) yüklemeden veya onaylamadan devam edemezsiniz.\n\n"RULES YÜKLE" butonuna basabilir veya kuralları kopyalayarak Firebase Console\'daki "Kurallar" sekmesine yapıştırabilirsiniz.',
          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              Clipboard.setData(ClipboardData(text: FirebaseConfigService.formattedRulesJson));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📋 Kurallar panoya kopyalandı!'),
                  backgroundColor: Color(0xFF00E676),
                ),
              );
            },
            child: const Text('Kuralları Kopyala', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(dlgCtx);
              _deployFirebaseRules();
            },
            child: const Text('RULES YÜKLE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showFirebaseGuideModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.menu_book_rounded, color: Color(0xFF00E676), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Firebase Veritabanı Açma Rehberi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGuideStepCard(
                      stepNum: '1',
                      title: 'Firebase Console\'a Girin',
                      description:
                          'console.firebase.google.com adresini açın (Google hesabınızla ücretsiz giriş yapın) ve "Proje Ekle" butonuna basarak projenize bir isim verin (Örn: Ailemiz Omega).',
                    ),
                    const SizedBox(height: 12),
                    _buildGuideStepCard(
                      stepNum: '2',
                      title: 'Realtime Database Oluşturun',
                      description:
                          'Sol menüden "Build (Oluştur) -> Realtime Database" bölümüne tıklayın. "Veritabanı Oluştur" deyin ve konum olarak "europe-west1 (Belçika/Frankfurt)" seçin.',
                    ),
                    const SizedBox(height: 12),
                    _buildGuideStepCard(
                      stepNum: '3',
                      title: 'Linki Kopyalayın & Kuralları Yükleyin',
                      description:
                          'Oluşturulan Realtime Database\'in üstündeki linki (https://...firebasedatabase.app) kopyalayıp Omega\'ya yapıştırın. Omega güvenlik kurallarını tek tıkla otomatik yapılandıracaktır!',
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.shield_rounded, color: Color(0xFF00E676), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Manuel Güvenlik Kuralları (Opsiyonel)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Dilerseniz kuralları kopyalayıp Firebase Console\'daki "Kurallar (Rules)" sekmesine kendiniz de yapıştırabilirsiniz:',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Kuralları JSON Olarak Kopyala', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: FirebaseConfigService.formattedRulesJson));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('📋 Kurallar panoya kopyalandı!'),
                                  backgroundColor: Color(0xFF00E676),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ⚖️ HUKUKİ, KANUNİ VE KVKK UYARILARI KARTI
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.gavel_rounded, color: Colors.amber, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '⚖️ HUKUKİ, KANUNİ & KVKK UYARILARI',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 1. Veri Sorumlusu & Şahsi Barındırma
                          _buildLegalWarningBullet(
                            title: 'Veri Sorumluluğu (KVKK m. 3 & m. 10):',
                            content:
                                'Bağladığınız Firebase veritabanı münhasıran sizin şahsi Google hesabınızda açılır. Omega geliştiricisi veritabanınıza, şifrelerinize veya içeriklerinize asla erişemez. Veri Sorumlusu veritabanı sahibi olan kullanıcıdır.',
                          ),
                          const SizedBox(height: 10),

                          // 2. Yasal Amaç Sınırı & TMK m. 339
                          _buildLegalWarningBullet(
                            title: 'Meşru Gözetim Kapsamı (TMK m. 339):',
                            content:
                                'Bu altyapı yalnızca velayet altındaki bebek/çocukların can güvenliği ve bakıma muhtaç kişilerin meşru gözetimi içindir.',
                          ),
                          const SizedBox(height: 10),

                          // 3. TCK Ceza Kanunu Uyarısı (Eşler ve Aile Dahil)
                          _buildLegalWarningBullet(
                            title: 'Rızasız İzleme ve Dinleme Yasağı (TCK m. 132-134):',
                            content:
                                'Eşler veya yetişkin aile fertleri dahil olmak üzere, kişilerin açık rızası ve bilgisi olmaksızın gizlice izlenmesi veya dinlenmesi Türk Ceza Kanunu uyarınca suçtur. Aile içi veya 3. şahıslara yönelik tüm yetkisiz kullanımların cezai sorumluluğu münhasıran kullanıcıya aittir.',
                          ),
                          const SizedBox(height: 10),

                          // 4. Veritabanı Güvenliği
                          _buildLegalWarningBullet(
                            title: 'Veritabanı Güvenlik Tedbiri (KVKK m. 12):',
                            content:
                                'Yetkisiz 3. şahısların veritabanınıza erişmesini önlemek amacıyla Omega\'nın sağladığı Güvenlik Kurallarını (Rules) mutlaka uygulayınız; veritabanınızı herkese açık bırakmayınız.',
                          ),

                          const SizedBox(height: 14),

                          // View EULA & KVKK button
                          Center(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.amber, width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.description_rounded, size: 16, color: Colors.amber),
                              label: const Text(
                                'Kullanım Şartları & KVKK Metnini İncele',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showEulaDialog();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ANLADIM, TEŞEKKÜRLER', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStepCard({
    required String stepNum,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFF00E676),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                stepNum,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalWarningBullet({
    required String title,
    required String content,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '• ',
          style: TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              children: [
                TextSpan(
                  text: '$title ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep0LegalRow({
    required String badgeText,
    required Color badgeColor,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              children: [
                TextSpan(
                  text: '$title ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 0: Family Network & Firebase RTDB BYODB Selection ---
  Widget _buildStep0DatabaseNetwork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aile Ağı & Veritabanı',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Omega, merkezi sunuculardan bağımsız (BYODB) çalışır. Aile ağınızı kurun veya mevcut aileye katılın:',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Mode Selector: Create new family vs Join with QR
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _networkMode = 'create'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _networkMode == 'create'
                          ? const Color(0xFF00E676)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_queue_rounded,
                          size: 16,
                          color: _networkMode == 'create'
                              ? Colors.black
                              : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Yeni Ağ Kur',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _networkMode == 'create'
                                ? Colors.black
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _networkMode = 'join'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _networkMode == 'join'
                          ? const Color(0xFF00E676)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 16,
                          color: _networkMode == 'join'
                              ? Colors.black
                              : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'QR ile Katıl',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _networkMode == 'join'
                                ? Colors.black
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (_networkMode == 'create') ...[
          LiquidGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.link_rounded, color: Color(0xFF00E676), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Firebase Veritabanı URL',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.paste_rounded, size: 14, color: Color(0xFF00E676)),
                      label: const Text(
                        'Panodan Yapıştır',
                        style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _pasteFirebaseUrlFromClipboard,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: _firebaseUrlController,
                  onChanged: (_) {
                    setState(() {
                      _connectionTestResult = null;
                      _rulesDeployResult = null;
                      _manualRulesConfirmed = false;
                    });
                  },
                  style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'https://projeniz-default-rtdb.europe-west1.firebasedatabase.app',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 12, fontWeight: FontWeight.normal),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.95),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _firebaseUrlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.black54),
                            onPressed: () {
                              _firebaseUrlController.clear();
                              FirebaseConfigService.clearSavedRtdbUrl();
                              setState(() {
                                _connectionTestResult = null;
                                _rulesDeployResult = null;
                                _manualRulesConfirmed = false;
                              });
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),

                // Test & Deploy buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isTestingConnection
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.black)),
                              )
                            : const Icon(Icons.bolt_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('TEST ET & KAYDET', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        onPressed: _isTestingConnection ? null : _testFirebaseConnection,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isDeployingRules
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                              )
                            : const Icon(Icons.shield_rounded, size: 18, color: Color(0xFF00E676)),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('RULES YÜKLE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        onPressed: _isDeployingRules ? null : _deployFirebaseRules,
                      ),
                    ),
                  ],
                ),

                // Verification Checklist Card (Bağlantı ve Rules Doğrulama Durumu)
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (_isConnectionVerified && _isRulesConfigured)
                          ? const Color(0xFF00E676).withValues(alpha: 0.6)
                          : Colors.white12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Kurulum Doğrulama Durumu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (_isConnectionVerified && _isRulesConfigured)
                                  ? const Color(0xFF00E676).withValues(alpha: 0.2)
                                  : Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              (_isConnectionVerified && _isRulesConfigured) ? 'HAZIR ✅' : 'ONAY BEKLİYOR ⚠️',
                              style: TextStyle(
                                color: (_isConnectionVerified && _isRulesConfigured) ? const Color(0xFF00E676) : Colors.orangeAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _isConnectionVerified
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: _isConnectionVerified
                                ? const Color(0xFF00E676)
                                : Colors.white38,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isConnectionVerified
                                  ? '1. Veritabanı Bağlantısı: Doğrulandı'
                                  : '1. Veritabanı Bağlantısı: "TEST ET" yapılmalı',
                              style: TextStyle(
                                color: _isConnectionVerified
                                    ? const Color(0xFF00E676)
                                    : Colors.white70,
                                fontSize: 11,
                                fontWeight: _isConnectionVerified
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            _isRulesConfigured
                                ? Icons.check_circle_rounded
                                : Icons.shield_outlined,
                            color: _isRulesConfigured
                                ? const Color(0xFF00E676)
                                : Colors.amber,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isRulesConfigured
                                  ? '2. Güvenlik Kuralları (Rules): Aktif ve Onaylandı'
                                  : '2. Güvenlik Kuralları: "RULES YÜKLE" yapılmalı (Zorunlu)',
                              style: TextStyle(
                                color: _isRulesConfigured
                                    ? const Color(0xFF00E676)
                                    : Colors.amber,
                                fontSize: 11,
                                fontWeight: _isRulesConfigured
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (!_isRulesConfigured)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _manualRulesConfirmed = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Güvenlik kuralları manuel olarak onaylandı!'),
                            backgroundColor: Color(0xFF00E676),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded, size: 14, color: Color(0xFF00E676)),
                          SizedBox(width: 4),
                          Text(
                            'Kuralları Firebase Console\'a yapıştırdım, onayla',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Status messages
                if (_connectionTestResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _connectionTestResult!['success'] == true
                          ? const Color(0xFF00E676).withValues(alpha: 0.18)
                          : Colors.redAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _connectionTestResult!['success'] == true
                            ? const Color(0xFF00E676)
                            : Colors.redAccent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _connectionTestResult!['success'] == true
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          color: _connectionTestResult!['success'] == true
                              ? const Color(0xFF00E676)
                              : Colors.redAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _connectionTestResult!['message'] ?? '',
                            style: TextStyle(
                              color: _connectionTestResult!['success'] == true
                                  ? const Color(0xFF00E676)
                                  : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_rulesDeployResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _rulesDeployResult!['success'] == true
                          ? const Color(0xFF00E676).withValues(alpha: 0.18)
                          : Colors.orange.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _rulesDeployResult!['success'] == true
                            ? const Color(0xFF00E676)
                            : Colors.orange,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _rulesDeployResult!['success'] == true
                              ? Icons.verified_rounded
                              : Icons.info_outline_rounded,
                          color: _rulesDeployResult!['success'] == true
                              ? const Color(0xFF00E676)
                              : Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _rulesDeployResult!['message'] ?? '',
                            style: TextStyle(
                              color: _rulesDeployResult!['success'] == true
                                  ? const Color(0xFF00E676)
                                  : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Network Sharing Policy Selector Card
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.admin_panel_settings_rounded, color: Colors.amber, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Aile Ağı Davet & QR Yetkisi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => setState(() => _adminOnlySharing = true),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Radio<bool>(
                                value: true,
                                groupValue: _adminOnlySharing,
                                activeColor: const Color(0xFF00E676),
                                onChanged: (v) => setState(() => _adminOnlySharing = v ?? true),
                              ),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '👑 Yalnızca Yönetici Cihaz (Ben) Ekleyebilsin',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Diğer cihazlarda Aile QR kodu kilitlenir; yalnızca siz yeni cihaz bağlayabilirsiniz.',
                                      style: TextStyle(color: Colors.white60, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 10),
                      InkWell(
                        onTap: () => setState(() => _adminOnlySharing = false),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Radio<bool>(
                                value: false,
                                groupValue: _adminOnlySharing,
                                activeColor: const Color(0xFF00E676),
                                onChanged: (v) => setState(() => _adminOnlySharing = v ?? false),
                              ),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '👨‍👩‍👧‍👦 Tüm Aile Üyeleri Yeni Cihaz Davet Edebilsin',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Ağa katılan her cihaz dilediğinde QR gösterip evin diğer cihazlarını bağlayabilir.',
                                      style: TextStyle(color: Colors.white60, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Help button
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.help_outline_rounded, size: 16, color: Colors.white70),
              label: const Text(
                'Firebase Hesabı Nasıl Açılır? (3 Adımlı Rehber)',
                style: TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.underline),
              ),
              onPressed: _showFirebaseGuideModal,
            ),
          ),
        ] else ...[
          // Option B: Join family via QR Code
          LiquidGlassCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00E676), size: 40),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Mevcut Aile Ağına Katılın',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Evdeki diğer cihazın ekranındaki Aile Ağı QR kodunu kameranızla tarayın. Tüm veritabanı ayarları 1 saniyede otomatik yüklenecektir.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded, size: 20),
                  label: const Text(
                    'AİLE QR KODUNU TARA',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _openNetworkQRScannerModal,
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 18),

        // 🛡️ DİNAMİK YURTDIŞI VERİ AKTARIMI, 3. ŞAHIS AĞI GÜVEN & KVKK BİLGİLENDİRME KARTI (VURGULU & BELİRGİN)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _networkMode == 'create' ? Colors.amber.withValues(alpha: 0.6) : Colors.orangeAccent.withValues(alpha: 0.7),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (_networkMode == 'create' ? Colors.amber : Colors.orangeAccent).withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: (_networkMode == 'create' ? Colors.amber : Colors.orangeAccent).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _networkMode == 'create' ? Icons.shield_rounded : Icons.warning_amber_rounded,
                      color: _networkMode == 'create' ? Colors.amber : Colors.orangeAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _networkMode == 'create'
                              ? 'YURTDIŞI VERİ AKTARIMI & KANUNİ BİLDİRİM'
                              : '3. ŞAHIS AĞINA KATILIM & GÜVEN UYARISI',
                          style: TextStyle(
                            color: _networkMode == 'create' ? Colors.amber : Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          _networkMode == 'create'
                              ? '6698 Sayılı KVKK m. 9 & TCK m. 132-134 Kapsamında Bilgilendirme'
                              : '6698 Sayılı KVKK m. 8-10 & TCK m. 134 Kapsamında Hayati Bildirim',
                          style: const TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (_networkMode == 'create') ...[
                // Mode 1: Create own network
                _buildStep0LegalRow(
                  badgeText: 'KVKK m. 9',
                  badgeColor: Colors.amber,
                  title: 'Yurtdışı Veri Aktarımı:',
                  description:
                      'Girilen veritabanı doğrudan sizin şahsi Google Firebase hesabınızda barındırılır. Sunucu konumu (Avrupa/Belçika veya ABD) kullanıcının kendi seçimidir. Omega geliştiricisi verilerinize asla erişemez ve merkezi sunucuda veri tutmaz.',
                ),
                const SizedBox(height: 10),
                _buildStep0LegalRow(
                  badgeText: 'P2P Şifreli',
                  badgeColor: const Color(0xFF00E676),
                  title: 'Uçtan Uca Doğrudan İletişim:',
                  description:
                      'Sesli ve görüntülü aramalar iki cihaz arasında doğrudan (WebRTC Peer-to-Peer) şifreli olarak gerçekleşir; aracı sunucularda ses/görüntü depolanmaz.',
                ),
                const SizedBox(height: 10),
                _buildStep0LegalRow(
                  badgeText: 'TCK Uyarısı',
                  badgeColor: Colors.orangeAccent,
                  title: 'Rızasız İzleme Yasağı (TCK m. 132-134):',
                  description:
                      'Uygulama yalnızca velayet altındaki bebek/çocuk ve bakım gözetimi içindir. Eşler ve yetişkin aile fertleri dahil kişilerin rızasız gizli izlenmesi/dinlenmesi TCK uyarınca suçtur.',
                ),
              ] else ...[
                // Mode 2: Join 3rd party / family QR network
                _buildStep0LegalRow(
                  badgeText: '3. Şahıs Ağı',
                  badgeColor: Colors.redAccent,
                  title: 'Güven & Veri Aktarımı Uyarısı (KVKK m. 8):',
                  description:
                      'Okutacağınız QR kod, bu ağı kuran kişinin şahsi Firebase veritabanına bağlanmanızı sağlar. Yalnızca kesin olarak güvendiğiniz aile üyelerinin QR kodunu okutunuz. Cihaz sinyalizasyon bilgileriniz o kişinin veritabanına aktarılacaktır.',
                ),
                const SizedBox(height: 10),
                _buildStep0LegalRow(
                  badgeText: 'Veri Sorumlusu',
                  badgeColor: Colors.amber,
                  title: 'Ağ Sahibinin Sorumluluğu (KVKK m. 10):',
                  description:
                      'Bu ağa katıldığınızda, veri sorumlusu QR kodun ait olduğu veritabanı sahibidir. Omega geliştiricisi, 3. şahısların veritabanlarının güvenliğini veya ağ sahibinin eylemlerini denetleyemez.',
                ),
                const SizedBox(height: 10),
                _buildStep0LegalRow(
                  badgeText: 'TCK m. 132-134',
                  badgeColor: Colors.orangeAccent,
                  title: 'Rızasız / Gizli İzleme Yasağı:',
                  description:
                      'Eşler, aile fertleri veya 3. şahısların açık rızası olmaksızın gizli izleme/dinleme amacıyla ağlara katılmak TCK m. 132-134 uyarınca suçtur. Tüm hukuki ve cezai sorumluluk kullanıcıya aittir.',
                ),
                const SizedBox(height: 10),
                _buildStep0LegalRow(
                  badgeText: 'P2P Şifreli',
                  badgeColor: const Color(0xFF00E676),
                  title: 'Uçtan Uca Ses/Görüntü Güvencesi:',
                  description:
                      'Ağ yöneticisi sadece cihaz bağlantı durumlarını görür; canlı ses ve görüntülü görüşmeler iki cihaz arasında doğrudan (P2P) şifreli akar.',
                ),
              ],

              const SizedBox(height: 12),

              // Direct link to EULA & KVKK
              InkWell(
                onTap: _showEulaDialog,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.description_rounded, size: 15, color: Color(0xFF00E676)),
                      const SizedBox(width: 6),
                      const Text(
                        'Kullanım Şartları & KVKK Aydınlatma Metnini İncele',
                        style: TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Navigation forward button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onPressed: () async {
              if (_networkMode == 'create') {
                final raw = _firebaseUrlController.text.trim();
                if (raw.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Lütfen bir Firebase Realtime Database URL giriniz.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                if (!_isConnectionVerified) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Lütfen önce "TEST ET & KAYDET" butonuna basarak bağlantıyı doğrulayın.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                if (!_isRulesConfigured) {
                  _showRulesRequiredDialog();
                  return;
                }
                await FirebaseConfigService.saveActiveRtdbUrl(raw);
                await FirebaseConfigService.setIsNetworkAdmin(true);
                await FirebaseConfigService.setAdminOnlySharing(_adminOnlySharing);
                setState(() => _currentStep = 1);
              } else {
                final raw = _firebaseUrlController.text.trim();
                if (raw.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Lütfen önce "AİLE QR KODUNU TARA" butonu ile ağa katılın.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                await FirebaseConfigService.saveActiveRtdbUrl(raw);
                await FirebaseConfigService.setIsNetworkAdmin(false);
                setState(() => _currentStep = 1);
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'DEVAM ET (PROFİL ADIMI)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image != null) {
        Uint8List? bytes;
        try {
          bytes = await image.readAsBytes();
        } catch (_) {}
        setState(() {
          _customPhotoPath = image.path;
          _customPhotoBytes = bytes;
          _selectedAvatar = 'custom_photo';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Profil Fotoğrafı Seçildi!'),
              backgroundColor: Color(0xFF00E676),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Photo pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Yeni fotoğraf eklentisinin aktifleşmesi için terminalde "R" basarak uygulamayı tam baştan başlatın.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _openQRScannerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF384353),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '📷 Cihaz QR Kodunu Taratın',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Diğer cihazın ekranındaki QR kodu kameranızla okutarak anında eşleşin:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null &&
                          barcode.rawValue!.isNotEmpty) {
                        final scannedVal = barcode.rawValue!;
                        Navigator.pop(ctx);

                        String extractedPin = scannedVal;
                        String extractedName = '';

                        try {
                          final parsed = jsonDecode(scannedVal);
                          if (parsed is Map) {
                            extractedPin = parsed['pairCode'] ?? scannedVal;
                            extractedName = parsed['deviceName'] ?? '';
                          }
                        } catch (_) {}

                        setState(() {
                          if (_selectedMethod == PairingMethod.phoneNumber) {
                            _phoneController.text = extractedPin;
                          } else if (_selectedMethod == PairingMethod.email) {
                            _emailController.text = extractedPin;
                          } else {
                            _targetPinController.text = extractedPin;
                          }
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ QR Kod Algılandı! ${extractedName.isNotEmpty ? "Cihaz: $extractedName" : "PIN: $extractedPin"}',
                            ),
                            backgroundColor: const Color(0xFF00E676),
                          ),
                        );
                        break;
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF384353),
      body: Stack(
        children: [
          // Background Gradient & Liquid Circles
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8BA0B5), Color(0xFF4A5568)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryLight.withValues(alpha: 0.25),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.2),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Liquid AppBar Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'OMEGA',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 5-Step Animated Wizard Bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Row(
                    children: [
                      _buildWizardStepBadge(0, '1. Ağ'),
                      _buildWizardStepLine(0),
                      _buildWizardStepBadge(1, '2. Profil'),
                      _buildWizardStepLine(1),
                      _buildWizardStepBadge(2, '3. İzinler'),
                      _buildWizardStepLine(2),
                      _buildWizardStepBadge(3, '4. Yöntem'),
                      _buildWizardStepLine(3),
                      _buildWizardStepBadge(4, '5. Kod/QR'),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildCurrentWizardStep(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWizardStepBadge(int index, String title) {
    final isActive = _currentStep == index;
    final isDone = _currentStep > index;
    final stepNum = index + 1;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDone
                ? const Color(0xFF00E676)
                : (isActive ? Colors.white : Colors.white.withValues(alpha: 0.2)),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDone
                  ? const Color(0xFF00E676)
                  : (isActive ? Colors.white : Colors.white.withValues(alpha: 0.4)),
              width: 2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
                    '$stepNum',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: isActive ? Colors.black : Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.white : Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildWizardStepLine(int index) {
    final isDone = _currentStep > index;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 14),
        color: isDone ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildCurrentWizardStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep0DatabaseNetwork();
      case 1:
        return _buildStep1ProfileAndName();
      case 2:
        return _buildStep3PermissionCheck();
      case 3:
        return _buildStep4PairingMethodSelection();
      case 4:
        return _buildStep5IdentityAndQRGeneration();
      default:
        return _buildStep0DatabaseNetwork();
    }
  }

  // --- Step 1: Device Name & Profile Avatar / Photo Selection ---
  Widget _buildStep1ProfileAndName() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Profilinizi Oluşturun',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Profil fotoğrafınızı yükleyin ve cihaz adınızı girin:',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        const SizedBox(height: 24),

        // 1. TOP ROUND PROFILE PHOTO CIRCLE (EN ÜSTTE YUVARLAK BÜYÜK FOTOĞRAF ALANI)
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _customPhotoBytes != null
                        ? ClipOval(
                            child: Image.memory(
                              _customPhotoBytes!,
                              fit: BoxFit.cover,
                              width: 100,
                              height: 100,
                            ),
                          )
                        : (_customPhotoPath != null &&
                                !kIsWeb &&
                                File(_customPhotoPath!).existsSync()
                            ? ClipOval(
                                child: Image.file(
                                  File(_customPhotoPath!),
                                  fit: BoxFit.cover,
                                  width: 100,
                                  height: 100,
                                ),
                              )
                            : const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 52,
                              )),
                  ),

                  // Camera Badge Icon at bottom right
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E676),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.black,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _customPhotoPath != null ? '📷 Fotoğrafı Değiştir' : '📷 Profil Fotoğrafı Yükle',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 2. DEVICE NAME INPUT CARD (FOTOĞRAFIN HEMEN ALTINDA)
        LiquidGlassCard(
          isHighlight: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Cihaz / Kullanıcı Adı',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Örn: Ev Tableti (Ömer) veya Anne Telefonu',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.95),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. PROFILE DATA PRIVACY & STATUTORY SHIELD
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.privacy_tip_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'KİŞİSEL VERİ VE PROFİL GÜVENLİĞİ',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildStep0LegalRow(
                badgeText: 'KVKK m. 4',
                badgeColor: Colors.amber,
                title: 'Cihaz & Profil Kimliği:',
                description:
                    'Belirlediğiniz cihaz adı (örn: Bebek Odası) yalnızca kendi Firebase ağınızdaki yetkili aile üyelerine görünür. Merkezi sunucuya veya 3. şahıslara aktarılmaz.',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'Yerel Depolama',
                badgeColor: const Color(0xFF00E676),
                title: 'Fotoğraf Güvenliği:',
                description:
                    'Profil fotoğrafınız yerel cihazınızda ve şahsi veritabanınızda tutulur; hiçbir biyometrik analiz veya harici işleme tabi tutulmaz.',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'TCK Uyarısı',
                badgeColor: Colors.orangeAccent,
                title: 'Yasal Kimlik Sorumluluğu:',
                description:
                    'Cihaz ismi karşı tarafın arayanı tanıması içindir. Başkalarını yanıltıcı veya rızasız izleme amaçlı kimlik tanımlamalarının yasal sorumluluğu kullanıcıya aittir.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. EULA & KVKK LEGAL CONSENT CARD (OKUMADAN İŞARETLENEMEZ)
        LiquidGlassCard(
          isHighlight: _eulaAccepted,
          child: InkWell(
            onTap: () {
              if (!_eulaAccepted) {
                _showEulaDialog();
              } else {
                setState(() => _eulaAccepted = false);
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                Checkbox(
                  value: _eulaAccepted,
                  activeColor: const Color(0xFF00E676),
                  checkColor: Colors.black,
                  side: const BorderSide(color: Colors.white70, width: 2),
                  onChanged: (val) {
                    if (_eulaAccepted) {
                      setState(() => _eulaAccepted = false);
                    } else {
                      _showEulaDialog();
                    }
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
                          children: [
                            TextSpan(text: 'Ebeveyn Denetimi '),
                            TextSpan(
                              text: 'Kullanım Şartları & KVKK Aydınlatma Metnini',
                              style: TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            TextSpan(text: ' okudum, yasal kullanımı kabul ediyorum.'),
                          ],
                        ),
                      ),
                      if (!_eulaAccepted)
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Text(
                            '(Okumak ve onaylamak için dokunun 📄)',
                            style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Text(
                            '✅ Sözleşmeler İncelendi ve Onaylandı',
                            style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => setState(() => _currentStep = 0),
                child: const Text('Geri'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () {
                  if (_nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ Lütfen cihaz için bir isim giriniz.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  } else if (!_eulaAccepted) {
                    _showEulaDialog();
                  } else {
                    setState(() => _currentStep = 2);
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('DEVAM ET',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }



  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isGranted
                    ? const Color(0xFF00E676).withValues(alpha: 0.2)
                    : Colors.white12,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isGranted ? const Color(0xFF00E676) : Colors.white70,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isGranted
                    ? const Color(0xFF00E676).withValues(alpha: 0.2)
                    : Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isGranted ? const Color(0xFF00E676) : Colors.orangeAccent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isGranted ? Icons.check_circle_rounded : Icons.lock_open_rounded,
                    color: isGranted ? const Color(0xFF00E676) : Colors.orangeAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isGranted ? 'Onaylandı' : 'İzin İste',
                    style: TextStyle(
                      color: isGranted ? const Color(0xFF00E676) : Colors.orangeAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 4: Pairing Method Selection ---
  Widget _buildStep4PairingMethodSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Eşleştirme Yöntemi Seçin',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cihazlar arasında hangi kimlik yöntemini kullanmak istersiniz?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 24),

        // Method 1: 6-Digit PIN Code
        LiquidGlassCard(
          isHighlight: _selectedMethod == PairingMethod.pinCode,
          onTap: () => setState(() => _selectedMethod = PairingMethod.pinCode),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pin_rounded,
                    size: 30, color: Colors.white),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔑 6 Haneli Otomatik PIN Kodu',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Sistem tarafından üretilen 6 haneli özel PIN kodunu ve QR kodu kullanın.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_selectedMethod == PairingMethod.pinCode)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF00E676), size: 26),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Method 2: Phone Number (SIM Card)
        LiquidGlassCard(
          isHighlight: _selectedMethod == PairingMethod.phoneNumber,
          onTap: () =>
              setState(() => _selectedMethod = PairingMethod.phoneNumber),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_rounded,
                    size: 30, color: Colors.white),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📞 SIM Kart Telefon Numarası',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Cihazın kendi cep telefon numarasını girerek kolayca eşleşin.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_selectedMethod == PairingMethod.phoneNumber)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF00E676), size: 26),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Method 3: Email Address
        LiquidGlassCard(
          isHighlight: _selectedMethod == PairingMethod.email,
          onTap: () => setState(() => _selectedMethod = PairingMethod.email),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.email_rounded,
                    size: 30, color: Colors.white),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📧 E-Posta Adresi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'E-posta adresiniz ile cihazlar arası güvenli eşleşin.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_selectedMethod == PairingMethod.email)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF00E676), size: 26),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Cross-Method Compatibility & Privacy Shield Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.hub_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'ÇAPRAZ EŞLEŞME VE KOD GİZLİLİĞİ',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildStep0LegalRow(
                badgeText: 'Çapraz Uyumlu',
                badgeColor: const Color(0xFF00E676),
                title: 'Farklı Yöntemler Birlikte Çalışır:',
                description:
                    'İki cihazın aynı yöntemi seçmesi şart değildir. Örneğin; Tablet "6 Haneli PIN" seçerken, Anne "Telefon Numarası" seçebilir. İki cihaz birbirini bu kimliklerle sorunsuz arayabilir.',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'Gizlilik Uyarısı',
                badgeColor: Colors.redAccent,
                title: 'Kodları Yalnızca Ailenizle Paylaşın:',
                description:
                    'Üretilen PIN kodunu veya eşleştirme numaranızı yalnızca güvendiğiniz aile üyelerine veriniz. 3. şahıslarla asla paylaşmayınız; kodunuzu bilenler ağ üzerinden arama başlatabilir (TCK m. 132).',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'Yenileme',
                badgeColor: Colors.amber,
                title: 'Dilediğiniz Zaman Değiştirme:',
                description:
                    'Oluşturulan PIN kodunu veya eşleştirme metodunu dilediğiniz an Ayarlar menüsünden tek tuşla sıfırlayabilir ve yenileyebilirsiniz.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => setState(() => _currentStep = 2),
                child: const Text('Geri'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => setState(() => _currentStep = 4),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('DEVAM ET',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isLookingUpTarget = false;
  Map<String, dynamic>? _targetDeviceInfo;

  void _performTargetLookup(String val) async {
    final clean = val.trim();
    if (clean.length < 3) {
      setState(() {
        _targetDeviceInfo = null;
        _isLookingUpTarget = false;
      });
      return;
    }

    setState(() => _isLookingUpTarget = true);
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final res = await appState.lookupTargetDevice(clean);
    if (mounted) {
      setState(() {
        _targetDeviceInfo = res;
        _isLookingUpTarget = false;
      });
    }
  }

  PairingMethod _targetInputMethod = PairingMethod.pinCode;

  // --- Step 5: Identity Code, Dynamic QR Code & Camera Scanner Button ---
  Widget _buildStep5IdentityAndQRGeneration() {
    final String activeName = _nameController.text.trim().isEmpty
        ? 'Omega Cihazı'
        : _nameController.text.trim();
    String activePin = _generatedPin;
    if (_selectedMethod == PairingMethod.phoneNumber &&
        _phoneController.text.trim().isNotEmpty) {
      activePin = _phoneController.text.trim();
    } else if (_selectedMethod == PairingMethod.email &&
        _emailController.text.trim().isNotEmpty) {
      activePin = _emailController.text.trim();
    }

    String methodLabel = '6 HANELİ ÖZEL PIN KODU';
    if (_selectedMethod == PairingMethod.phoneNumber) {
      methodLabel = 'SIM KART TELEFON NUMARASI';
    } else if (_selectedMethod == PairingMethod.email) {
      methodLabel = 'E-POSTA ADRESİ';
    }

    final payload = {
      'deviceName': activeName,
      'pairCode': activePin,
      'role': _selectedRole.name,
      'avatar': _selectedAvatar,
    };
    String qrData = jsonEncode(payload);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kimlik Kodu & QR Oluşturma',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cihazınızın kimlik bilgisi oluşturuldu. Karşı cihaza bağlanmak için yöntemi seçin:',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 20),

        // 1. SİZİN CİHAZINIZIN KİMLİK KARTI
        LiquidGlassCard(
          isHighlight: true,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.key_rounded,
                      color: Color(0xFF00E676), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'BENZERSİZ $methodLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_selectedMethod == PairingMethod.pinCode) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _generatedPin,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8.0,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Diğer cihaz sahibi bu 6 haneli kodu kendi ekranına yazarak sizinle eşleşebilir.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                // Phone / Email QR Code display
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 150.0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedMethod == PairingMethod.phoneNumber
                      ? (_phoneController.text.trim().isEmpty
                          ? 'Telefon No Tanımlanmadı'
                          : _phoneController.text.trim())
                      : (_emailController.text.trim().isEmpty
                          ? 'E-Posta Tanımlanmadı'
                          : _emailController.text.trim()),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2. KARŞI CİHAZA BAĞLANMA / İSTEK GÖNDERME KARTI (ESNEK YÖNTEM SEÇİCİ)
        LiquidGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.phonelink_setup_rounded,
                      color: Color(0xFF00E676), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'KARŞI CİHAZA BAĞLAN & İSTEK GÖNDER',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 3-Tab Target Method Selector with Icons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _targetInputMethod = PairingMethod.pinCode;
                          _targetDeviceInfo = null;
                        });
                        _performTargetLookup(_targetPinController.text);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _targetInputMethod == PairingMethod.pinCode
                              ? const Color(0xFF00E676)
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.key_rounded,
                                size: 14,
                                color:
                                    _targetInputMethod == PairingMethod.pinCode
                                        ? Colors.black
                                        : Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'PIN Kodu',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color:
                                    _targetInputMethod == PairingMethod.pinCode
                                        ? Colors.black
                                        : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _targetInputMethod = PairingMethod.phoneNumber;
                          _targetDeviceInfo = null;
                        });
                        _performTargetLookup(_phoneController.text);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _targetInputMethod == PairingMethod.phoneNumber
                              ? const Color(0xFF00E676)
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_android_rounded,
                                size: 14,
                                color: _targetInputMethod ==
                                        PairingMethod.phoneNumber
                                    ? Colors.black
                                    : Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'Tel No',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _targetInputMethod ==
                                        PairingMethod.phoneNumber
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _targetInputMethod = PairingMethod.email;
                          _targetDeviceInfo = null;
                        });
                        _performTargetLookup(_emailController.text);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _targetInputMethod == PairingMethod.email
                              ? const Color(0xFF00E676)
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.email_rounded,
                                size: 14,
                                color:
                                    _targetInputMethod == PairingMethod.email
                                        ? Colors.black
                                        : Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'E-Posta',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color:
                                    _targetInputMethod == PairingMethod.email
                                        ? Colors.black
                                        : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Target Input Field & Camera Scan Button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetInputMethod == PairingMethod.pinCode
                          ? _targetPinController
                          : (_targetInputMethod == PairingMethod.phoneNumber
                              ? _targetPhoneController
                              : _targetEmailController),
                      keyboardType:
                          _targetInputMethod == PairingMethod.phoneNumber
                              ? TextInputType.phone
                              : (_targetInputMethod == PairingMethod.email
                                  ? TextInputType.emailAddress
                                  : TextInputType.number),
                      maxLength: _targetInputMethod == PairingMethod.pinCode
                          ? 6
                          : null,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      onChanged: _performTargetLookup,
                      decoration: InputDecoration(
                        hintText: _targetInputMethod == PairingMethod.pinCode
                            ? '6 Haneli PIN Girin'
                            : (_targetInputMethod == PairingMethod.phoneNumber
                                ? 'Örn: 05551234567'
                                : 'Örn: anne@gmail.com'),
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.95),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _openQRScannerModal,
                    child: const Row(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 20),
                        SizedBox(width: 4),
                        Text('TARA',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),

              // WhatsApp-Style Live Device Check Status Badge
              if (_isLookingUpTarget) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF00E676)),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'OMEGA Veritabanı Kontrol Ediliyor...',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ] else if (_targetDeviceInfo != null &&
                  _targetDeviceInfo!['found'] == true) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00E676)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF00E676), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '✓ Bu ${_targetInputMethod == PairingMethod.phoneNumber ? "Telefon No" : (_targetInputMethod == PairingMethod.email ? "E-Posta" : "PIN Kodu")} OMEGA Kullanıyor! (${_targetDeviceInfo!["deviceName"]})',
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 3. AİLE AĞI KURULUM QR KODU (Yalnızca ilk adımda "Tüm Aile Ekleyebilsin" seçildiyse gösterilir)
        if (_networkMode == 'create' && !_adminOnlySharing) ...[
          LiquidGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _showStep5NetworkQr = !_showStep5NetworkQr),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.hub_rounded, color: Color(0xFF00E676), size: 18),
                            SizedBox(width: 8),
                            Text(
                              '📲 AİLE AĞI QR KODU (2. CİHAZ İÇİN)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _showStep5NetworkQr ? 'Gizle' : 'Göster',
                                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                _showStep5NetworkQr
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showStep5NetworkQr) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Evdeki bebek tableti veya diğer ebeveyn telefonu açıldığında "QR ile Katıl" diyerek bu kodu okuttuğunda 1 saniyede aynı veritabanına bağlanır:',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: QrImageView(
                        data: FirebaseConfigService.generateNetworkQrPayload(
                          _firebaseUrlController.text.trim().isNotEmpty
                              ? _firebaseUrlController.text.trim()
                              : DefaultFirebaseOptions.rtdbUrl,
                        ),
                        version: QrVersions.auto,
                        size: 140.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Statutory & Technical Privacy Commitment Shield for Final Setup
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.gavel_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'YASAL TAAHHÜT VE NİHAİ KULLANIM ONAYI',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '"KURULUMU TAMAMLA" butonuna basarak aşağıdaki tüm yasal koşulları, KVKK aydınlatma metnini ve EULA sözleşmesini eksiksiz kabul etmiş sayılırsınız:',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 10),
              _buildStep0LegalRow(
                badgeText: 'KVKK & EULA',
                badgeColor: const Color(0xFF00E676),
                title: 'Sözleşme & Mevzuat Uyumu:',
                description:
                    'Uygulamayı EULA Kullanıcı Sözleşmesi, KVKK Aydınlatma Metni ve Gizlilik İlkelerine tam uyumlu şekilde çalıştıracağınızı onaylarsınız.',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'TCK m. 132-134',
                badgeColor: Colors.redAccent,
                title: 'Rıza Dışı İzleme ve Dinleme Yasağı:',
                description:
                    'Uygulamayı yetişkin bireyler ve eşler üzerinde açık rızaları olmaksızın gizli takip/dinleme amacıyla kullanmayacağınızı; TMK m. 339 uyarınca yalnızca velayet/bakım altındaki küçükler ve telefon görüşmeleri için kullanacağınızı taahhüt edersiniz.',
              ),
              const SizedBox(height: 8),
              _buildStep0LegalRow(
                badgeText: 'BYODB Sorumluluk',
                badgeColor: Colors.amber,
                title: 'Ağ & Kod Güvenliği Sorumluluğu:',
                description:
                    'Firebase veritabanı URL\'nizi ve PIN kodunuzu 3. şahıslarla paylaşmayacağınızı; kendi veritabanınız üzerindeki erişim ve veri güvenliğinden doğrudan sorumlu olduğunuzu kabul edersiniz.',
              ),
              const SizedBox(height: 10),
              Center(
                child: InkWell(
                  onTap: () => LegalTermsService.showLegalTermsModal(context),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_rounded, size: 14, color: Color(0xFF00E676)),
                      SizedBox(width: 4),
                      Text(
                        'Sözleşmeleri Tekrar İncele (EULA & KVKK)',
                        style: TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => setState(() => _currentStep = 3),
                child: const Text('Geri'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        final appState = Provider.of<AppStateProvider>(
                            context,
                            listen: false);

                        String finalPin = _generatedPin;
                        if (_selectedMethod == PairingMethod.phoneNumber &&
                            _phoneController.text.trim().isNotEmpty) {
                          finalPin = _phoneController.text
                              .trim()
                              .replaceAll(RegExp(r'\D'), '');
                        } else if (_selectedMethod == PairingMethod.email &&
                            _emailController.text.trim().isNotEmpty) {
                          finalPin = _emailController.text.trim();
                        }

                        final avatarVal = _selectedAvatar == 'custom_photo' && _customPhotoPath != null
                            ? _customPhotoPath!
                            : _selectedAvatar;

                        await appState.setupDeviceRole(
                          role: _selectedRole,
                          name: _nameController.text.trim().isEmpty
                              ? 'Omega Cihazı'
                              : _nameController.text.trim(),
                          avatarIcon: avatarVal,
                          photoBase64: _customPhotoBytes != null
                              ? base64Encode(_customPhotoBytes!)
                              : null,
                          customPin: finalPin,
                          email: _emailController.text.trim().isEmpty
                              ? null
                              : _emailController.text.trim(),
                          phoneNumber: _phoneController.text.trim().isEmpty
                              ? null
                              : _phoneController.text.trim(),
                        );

                        // Upload profile photo to Firebase if custom photo was picked
                        if (_selectedAvatar == 'custom_photo' && (_customPhotoBytes != null || _customPhotoPath != null)) {
                          await appState.uploadMyProfilePhoto(_customPhotoPath ?? '', bytes: _customPhotoBytes);
                        }

                        String targetVal = '';
                        if (_targetInputMethod == PairingMethod.pinCode) {
                          targetVal = _targetPinController.text.trim();
                        } else if (_targetInputMethod == PairingMethod.phoneNumber) {
                          targetVal = _targetPhoneController.text.trim();
                        } else if (_targetInputMethod == PairingMethod.email) {
                          targetVal = _targetEmailController.text.trim();
                        }

                        if (targetVal.isNotEmpty) {
                          final myId = appState.myProfile?.id ?? 'omega_device';
                          final myName = _nameController.text.trim().isEmpty
                              ? 'Omega Cihazı'
                              : _nameController.text.trim();
                          await appState.sendPairRequest(targetVal, myId, myName);
                        }

                        if (!mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const HomeScreen()),
                        );
                      },
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Colors.black),
                        ),
                      )
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'KURULUMU TAMAMLA',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
