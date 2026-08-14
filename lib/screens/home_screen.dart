import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user_profile.dart';
import '../models/call_session.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

// Modular Page Tabs Imports
import 'tabs/contacts_tab.dart';
import 'tabs/chats_tab.dart';
import 'tabs/calls_tab.dart';
import 'tabs/settings_tab.dart';
import '../widgets/profile_avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (mounted) {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final double t = (_scrollOffset / 130.0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF5B6578),
      body: Stack(
        children: [
          // Dynamic Liquid Glass Background Gradient & Bubbles
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
            bottom: 100,
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

          // Main Tabs Views Body
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: [
                ContactsTab(
                  scrollController: _scrollController,
                  scrollProgress: t,
                  onShowAddDeviceModal: () => _showAddDeviceModal(context, appState),
                ),
                ChatsTab(
                  onShowAddDeviceModal: () => _showAddDeviceModal(context, appState),
                ),
                const CallsTab(),
                const SettingsTab(),
              ],
            ),
          ),

          // --- Animated Sticky Liquid Glass Top Header (Appears smoothly on scroll) ---
          if (_currentIndex == 0 && t > 0.05)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Opacity(
                  opacity: t,
                  child: _buildStickyLiquidTopHeader(context, appState),
                ),
              ),
            ),

          // --- Ultra Premium Floating Liquid Glass Bottom Navigation Bar ---
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                child: _buildFloatingLiquidGlassNavBar(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Sticky Liquid Top Header on Scroll ---
  Widget _buildStickyLiquidTopHeader(BuildContext context, AppStateProvider appState) {
    final myProfile = appState.myProfile;
    final activeDevice = appState.pairedProfile;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                ProfileAvatar(
                  profile: myProfile,
                  radius: 18,
                  borderWidth: 1.5,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        myProfile?.deviceName ?? 'Ev Tableti (Ömer)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Kod: ${myProfile?.pairCode ?? ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSmallHeaderActionButton(
                      icon: Icons.chat_bubble_rounded,
                      onTap: () {
                        if (activeDevice != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ChatScreen()),
                          );
                        } else {
                          _showAddDeviceModal(context, appState);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildSmallHeaderActionButton(
                      icon: Icons.call_rounded,
                      onTap: () {
                        if (activeDevice != null) {
                          appState.startCall(CallType.audio);
                        } else {
                          _showAddDeviceModal(context, appState);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildSmallHeaderActionButton(
                      icon: Icons.videocam_rounded,
                      onTap: () {
                        if (activeDevice != null) {
                          appState.startCall(CallType.video);
                        } else {
                          _showAddDeviceModal(context, appState);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildSmallHeaderActionButton(
                      icon: Icons.notifications_active_rounded,
                      onTap: () {
                        if (activeDevice != null) {
                          appState.sendMessage('🔔 YÜKSEK İKAZ: Lütfen cihaza bakın!');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔔 Cihaza yüksek sesli bildirim gönderildi!'),
                              backgroundColor: AppTheme.primary,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallHeaderActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  // --- Floating Liquid Glass Navigation Bar ---
  Widget _buildFloatingLiquidGlassNavBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Consumer<AppStateProvider>(
            builder: (context, appState, _) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.people_alt_rounded),
                _buildNavItem(1, Icons.chat_bubble_rounded, badgeCount: appState.totalUnreadCount),
                _buildNavItem(2, Icons.phone_rounded),
                _buildNavItem(3, Icons.settings_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, {int badgeCount = 0}) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.35)
              : Colors.transparent,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white70,
              size: 24,
            ),
            if (badgeCount > 0)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E676),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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

  void _openQRScannerModal(
    BuildContext context,
    TextEditingController targetInputCtrl,
    Function(String) performLookup,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'QR Scanner',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curve),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.65,
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
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00E676), size: 24),
                            SizedBox(width: 10),
                            Text(
                              '📷 QR Kod Okutun',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white60),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Diğer cihazın ekranındaki QR kodu kameranızla okutarak anında eşleşin:',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
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
                                    extractedPin = parsed['pairCode'] ?? parsed['pin'] ?? scannedVal;
                                    extractedName = parsed['deviceName'] ?? '';
                                  }
                                } catch (_) {}

                                targetInputCtrl.text = extractedPin;
                                performLookup(extractedPin);

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '✅ QR Kod Algılandı! ${extractedName.isNotEmpty ? "Cihaz: $extractedName" : "Kod: $extractedPin"}',
                                      ),
                                      backgroundColor: const Color(0xFF00E676),
                                    ),
                                  );
                                }
                                break;
                              }
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddDeviceModal(BuildContext context, AppStateProvider appState) {
    final targetInputCtrl = TextEditingController();
    PairingMethod selectedMethod = PairingMethod.pinCode;

    Map<String, dynamic>? lookupDeviceInfo;
    bool isLookingUp = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          void performLookup(String val) async {
            final cleanVal = val.trim().replaceAll(' ', '');

            bool shouldQuery = false;
            if (selectedMethod == PairingMethod.pinCode) {
              shouldQuery = cleanVal.length == 6;
            } else if (selectedMethod == PairingMethod.phoneNumber) {
              shouldQuery = cleanVal.length >= 10;
            } else if (selectedMethod == PairingMethod.email) {
              final emailRegex = RegExp(r'^[^@]+@[^@]+\.[a-zA-Z]{2,}$');
              shouldQuery = emailRegex.hasMatch(cleanVal);
            }

            if (shouldQuery) {
              setModalState(() {
                isLookingUp = true;
              });
              final res = await appState.lookupTargetDevice(cleanVal);
              setModalState(() {
                isLookingUp = false;
                lookupDeviceInfo = res;
              });
            } else {
              setModalState(() {
                isLookingUp = false;
                lookupDeviceInfo = null;
              });
            }
          }

          final myCode = appState.myProfile?.pairCode ?? '';
          final myPhone = appState.myProfile?.phoneNumber ?? '';

          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_add_rounded, color: Color(0xFF00E676), size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Yeni Aile Bireyi / Cihaz Ekle',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white60),
                        onPressed: () {
                          Navigator.pop(modalCtx);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Bağlanmak istediğiniz cihazın Sabit PIN Kodunu, Telefon Numarasını veya E-Posta Adresini girerek eşleşme isteği gönderebilirsiniz:',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 14),

                  // My Own Device Code Banner Info
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF00E676), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bu Cihazın Sabit Kodu: $myCode${myPhone.isNotEmpty ? " • Tel: $myPhone" : ""}',
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
                  const SizedBox(height: 16),

                  // --- 3-Method Selection Segmented Control ---
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setModalState(() {
                              selectedMethod = PairingMethod.pinCode;
                              targetInputCtrl.clear();
                              lookupDeviceInfo = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedMethod == PairingMethod.pinCode
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedMethod == PairingMethod.pinCode
                                    ? const Color(0xFF00E676)
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.pin_outlined,
                                  size: 16,
                                  color: selectedMethod == PairingMethod.pinCode ? Colors.black : Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'PIN Kodu',
                                  style: TextStyle(
                                    color: selectedMethod == PairingMethod.pinCode ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setModalState(() {
                              selectedMethod = PairingMethod.phoneNumber;
                              targetInputCtrl.clear();
                              lookupDeviceInfo = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedMethod == PairingMethod.phoneNumber
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedMethod == PairingMethod.phoneNumber
                                    ? const Color(0xFF00E676)
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.phone_iphone_rounded,
                                  size: 16,
                                  color: selectedMethod == PairingMethod.phoneNumber ? Colors.black : Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Tel No',
                                  style: TextStyle(
                                    color: selectedMethod == PairingMethod.phoneNumber ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setModalState(() {
                              selectedMethod = PairingMethod.email;
                              targetInputCtrl.clear();
                              lookupDeviceInfo = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedMethod == PairingMethod.email
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedMethod == PairingMethod.email
                                    ? const Color(0xFF00E676)
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.email_outlined,
                                  size: 16,
                                  color: selectedMethod == PairingMethod.email ? Colors.black : Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'E-Posta',
                                  style: TextStyle(
                                    color: selectedMethod == PairingMethod.email ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: targetInputCtrl,
                    keyboardType: selectedMethod == PairingMethod.phoneNumber
                        ? TextInputType.phone
                        : (selectedMethod == PairingMethod.email
                            ? TextInputType.emailAddress
                            : TextInputType.number),
                    maxLength: selectedMethod == PairingMethod.pinCode ? 6 : null,
                    style: TextStyle(
                      fontSize: selectedMethod == PairingMethod.pinCode ? 22 : 16,
                      letterSpacing: selectedMethod == PairingMethod.pinCode ? 4 : 0,
                      fontWeight: FontWeight.bold,
                      color: selectedMethod == PairingMethod.pinCode ? const Color(0xFF00E676) : Colors.white,
                    ),
                    onChanged: performLookup,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      labelText: selectedMethod == PairingMethod.pinCode
                          ? 'Karşı Cihazın Sabit 6 Haneli Kodu'
                          : (selectedMethod == PairingMethod.phoneNumber
                              ? 'Telefon Numarası'
                              : 'E-Posta Adresi'),
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: selectedMethod == PairingMethod.pinCode
                          ? 'Örn: 101673'
                          : (selectedMethod == PairingMethod.phoneNumber
                              ? 'Örn: 05551234567'
                              : 'Örn: anne@gmail.com'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: Icon(
                        selectedMethod == PairingMethod.pinCode
                            ? Icons.lock_rounded
                            : (selectedMethod == PairingMethod.phoneNumber
                                ? Icons.phone_rounded
                                : Icons.email_rounded),
                        color: const Color(0xFF00E676),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00E676)),
                        tooltip: 'QR Kod Tarat',
                        onPressed: () => _openQRScannerModal(context, targetInputCtrl, performLookup),
                      ),
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF00E676), width: 2),
                      ),
                    ),
                  ),

                  // Live OMEGA User Lookup Status Badge
                  if (isLookingUp) ...[
                    const SizedBox(height: 8),
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
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ] else if (lookupDeviceInfo != null && lookupDeviceInfo!['found'] == true) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                              'Bu ${selectedMethod == PairingMethod.phoneNumber ? "Telefon No" : (selectedMethod == PairingMethod.email ? "E-Posta" : "Sabit Kod")} OMEGA Kullanıyor! (${lookupDeviceInfo!["deviceName"]})',
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
                  const SizedBox(height: 18),



                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text(
                      'BAĞLANTI İSTEĞİ GÖNDER',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: () async {
                      final inputVal = targetInputCtrl.text.trim();
                      if (inputVal.isNotEmpty) {
                        final myId = appState.myProfile?.id ?? 'omega_device';
                        final myName = appState.myProfile?.deviceName ?? 'Omega Cihazı';
                        final res = await appState.sendPairRequest(inputVal, myId, myName);
                        if (context.mounted) {
                          if (res == PairRequestResult.success) {
                            Navigator.pop(modalCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🟢 Eşleşme isteği başarıyla gönderildi!'),
                                backgroundColor: Color(0xFF00E676),
                              ),
                            );
                          } else if (res == PairRequestResult.alreadyPaired) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('⚠️ Bu cihaz zaten bağlı cihaz listenizde ekli!'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          } else if (res == PairRequestResult.alreadyPending) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('⏳ Bu cihaza halihazırda bekleyen bir eşleşme isteğiniz var!'),
                                backgroundColor: Colors.blueAccent,
                              ),
                            );
                          } else if (res == PairRequestResult.selfPair) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ℹ️ Kendi cihazınıza istek gönderemezsiniz.'),
                                backgroundColor: Colors.purple,
                              ),
                            );
                          } else if (res == PairRequestResult.blocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🚫 Bu cihaz engellenenler listenizde bulunuyor.'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('⚠️ İleti gönderilemedi. Lütfen tekrar deneyin.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
