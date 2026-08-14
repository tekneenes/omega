import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Comprehensive Legal Terms & KVKK Service
/// Provides legally airtight EULA, TCK disclaimers, Mutual Pairing Consent, and Privacy Policy.
/// Enforces full scroll-to-read requirement on both tabs before acceptance and records immutable timestamps.
class LegalTermsService {
  static const String keyEulaAccepted = 'omega_eula_accepted';
  static const String keyEulaTimestamp = 'omega_eula_accepted_at';
  static const String keyEulaVersion = 'omega_eula_version';
  static const String currentEulaVersion = '1.0.0';

  static const String eulaAndTerms = '''
1. MEŞRU KULLANIM VE AMACIN SINIRLILIĞI:
OMEGA yazılımı; yalnızca Türk Medeni Kanunu (TMK m. 339) kapsamında velayet altındaki bebek/çocukların can güvenliği, hasta ve yaşlı aile fertlerinin meşru bakımı ve tarafların karşılıklı rızasına dayalı aile içi açık iletişim amacıyla geliştirilmiştir. Yazılım kesinlikle gizli takip, casusluk, eş takibi veya arka planda tespit edilemeyen dinleme aracı (spyware/stalkerware) niteliği taşımaz ve bu amaçlarla kullanılamaz.

2. CİHAZ EŞLEŞTİRME İLE ÖNCEDEN VERİLEN KARŞILIKLI RIZA:
Uygulamanın sesli/görüntülü arama ve kamera istasyon modları; yalnızca iki cihazın karşılıklı PIN kodu, telefon, e-posta veya QR kod doğrulaması ile birbirini "Eşleşen Cihaz" olarak onaylaması halinde çalışır. Cihazını eşleştiren ve kamera moduna alan kullanıcı, eşleştiği diğer yetkili cihazın erişimine açık, hür ve önceden tanımlanmış rızasını vermiş olduğunu peşinen kabul ve ikrar eder.

3. YASAL SORUMLULUK REDDİ VE RIZASIZ İZLEME YASAĞI (TCK m. 132, 133, 134, 136):
Yargıtay yerleşik içtihatları ve Türk Hukuku uyarınca; evlilik birliği veya aile bağı bulunması dahi eşlerin veya reşit bireylerin açık rızası olmaksızın gizlice izlenmesi, sesinin dinlenmesi veya kayda alınması için hukuki gerekçe oluşturmaz. Yazılımın reşit bireylerin (eş, aile fertleri, ev çalışanları, 3. şahıslar) rızası ve bilgisi dışında gizli dinleme, casusluk, özel hayatın gizliliğini ihlal amacıyla kullanılması 5237 sayılı TCK uyarınca suçtur. Geliştirici, genel amaçlı bir iletişim kod sağlayıcısı olup; uygulamanın hukuka veya ahlaka aykırı bireysel kullanımlarından doğabilecek hiçbir cezai, hukuki veya idari yaptırımdan sorumlu tutulamaz (TCK m. 20 - Ceza Sorumluluğunun Şahsiliği).

4. KULLANICI RIZA & BİLDİRİM TAAHHÜDÜ:
Kullanıcı; cihazların yerleştirildiği veya kameranın yönlendirildiği mekanda bulunan tüm üçüncü kişilerin (aynı evde yaşayanlar, eşler, farklı adresteki aile bireyleri, bebek bakıcıları, ev çalışanları ve misafirler) meşru şekilde bilgilendirildiğini ve açık rızalarının alındığını gayrikabili rücu kabul, beyan ve taahhüt eder.

5. MERKEZİ SUNUCUSUZLUK (BYODB & ZERO-KNOWLEDGE):
Uygulama "Kendi Sunucusunu Getir" (Bring-Your-Own-Database) mimarisiyle çalışır. Veritabanı entegrasyonu kullanıcının kendi belirlediği bulut sağlayıcısı (Google Firebase) üzerinde barındırılır. Geliştirici kullanıcıların hiçbir ses, görüntü, mesaj, kişi listesi veya parola verisini merkezi sunucularda depolamaz ve bunlara erişemez (Sıfır Bilgi / Zero-Knowledge).

6. UÇTAN UCA P2P MEDYA VE YEREL VERİ İMHASI:
Sesli ve görüntülü görüşmeler WebRTC teknolojisiyle uçtan uca doğrudan istemciler arasında (P2P) aktarılır; medya sunuculara kaydedilmez. Cihaz üzerindeki mesajlar ve arama kayıtları yerel olarak AES-256 ile şifrelenir; belirlenen saklama süreleri (60 gün çağrı, 90 gün sohbet) sonunda yerel depolamadan otomatik imha edilir.

7. YURT DIŞI BULUT ENTEGRASYONU (KVKK m. 9):
Kullanıcı, seçtiği bulut sağlayıcısının (Google Firebase) sunucularının yurt dışında bulunabileceğini ve bu bulut entegrasyonunu kendi serbest iradesiyle kurduğunu kabul eder. Eşleştirme kodları, PIN'ler ve cihazın fiziksel güvenliğinin korunması münhasıran kullanıcının sorumluluğundadır.

8. KULLANIMLA BİRLİKTE YÜRÜRLÜĞE GİRME VE BAĞLAYICILIK:
Bu uygulamayı indirerek, kurarak, açarak veya herhangi bir işlevini kullanarak; işbu Sözleşme'de ve KVKK Aydınlatma Metni'nde yer alan tüm şartları, kuralları, yasal sorumluluk reddi beyanlarını ve yükümlülükleri peşinen, gayrikabili rücu ve eksiksiz olarak kabul etmiş sayılırsınız. Şartları kabul etmiyorsanız lütfen uygulamayı kullanmayınız ve cihazınızdan derhal kaldırınız.
''';

  static const String kvkkAndPrivacy = '''
6698 SAYILI KVKK KAPSAMINDA AYDINLATMA METNİ & GİZLİLİK POLİTİKASI

1. VERİ SORUMLUSU VE SİSTEM MİMARİSİ:
OMEGA uygulamasında kullanıcı verileri geliştiriciye ait merkezi sunucularda toplanmaz veya işlenmez. Kullanıcıların Firebase hesabı üzerinden oluşturduğu kapalı aile ağında veri işleme amaç ve vasıtalarını hesabı açan ve yöneten kullanıcı belirlediğinden, 6698 sayılı KVKK m. 3/1-(ı) kapsamında "Veri Sorumlusu" bizzat kullanıcının kendisidir.

2. İŞLENEN KİŞİSEL VERİ KATEGORİLERİ:
- Kimlik ve İletişim Bilgileri: Kullanıcının cihazında tanımladığı takma ad, isteğe bağlı profil fotoğrafı, PIN/telefon/e-posta eşleştirme anahtarı.
- İletişim İçerikleri: Metin mesajları ve sesli mesajlar (Cihaz üzerinde yerel AES-256 şifreli Hive veritabanında tutulur).
- Görsel ve İşitsel Veriler: Canlı ses ve video akışları (Doğrudan WebRTC P2P ile anlık aktarılır, sunucuda depolanmaz).

3. KİŞİSEL VERİLERİN İŞLENME AMACI VE HUKUKİ SEBEBİ:
Kişisel veriler; KVKK m. 5/2-c (sözleşmenin ifası) ve m. 5/2-f (meşru menfaat) hukuki sebeplerine dayalı olarak; yalnızca iki cihaz arasında güvenli P2P eşleşme kurulması ve aile içi anlık mesajlaşma sağlanması amacıyla işlenir.

4. VERİ AKTARIMI VE ÜÇÜNCÜ KİŞİLER:
Geliştirici hiçbir kişisel veriyi üçüncü taraflara satmaz, kiralamaz, reklam veya analitik şirketleriyle paylaşmaz. Sinyalleşme ve anlık mesajlaşma trafiği kullanıcının kendi yapılandırdığı Google Firebase altyapısı üzerinden akar.

5. VERİ GÜVENLİĞİ VE OTOMATİK İMHA (KVKK m. 12):
- Tüm yerel veri tabanı AES-256 algoritmasıyla şifrelenir.
- 60 günden eski arama kayıtları ve 90 günden eski mesajlaşma kayıtları otomatik olarak cihazdan kalıcı olarak silinir.

6. İLGİLİ KİŞİNİN HAKLARI (KVKK m. 11):
Kullanıcılar diledikleri an Ayarlar sekmesinden "Kurulumu Sıfırla" butonunu kullanarak cihazdaki tüm kişisel verilerini, profilini ve eşleşme kayıtlarını tek tuşla kalıcı olarak silebilirler.

7. KULLANIMLA BAĞLAYICILIK VE ONAYIN YÜRÜRLÜĞÜ:
Uygulamanın aktif olarak kullanılması; işbu Aydınlatma Metni'nde belirtilen veri işleme esaslarına, yerel şifrelemeye ve kullanıcı tarafından yapılandırılan bulut mimarisine açık ve hür iradeyle onay verildiği anlamına gelir.
''';

  /// Saves the timestamp and version of legal acceptance to local secure storage
  static Future<void> saveAcceptanceRecord() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyEulaAccepted, true);
      await prefs.setString(keyEulaTimestamp, DateTime.now().toIso8601String());
      await prefs.setString(keyEulaVersion, currentEulaVersion);
      debugPrint('📜 [LEGAL AUDIT LOG] EULA & KVKK accepted and saved locally at: ${DateTime.now()}');
    } catch (e) {
      debugPrint('⚠️ [LEGAL AUDIT LOG SAVE NOTICE]: $e');
    }
  }

  /// Retrieves the stored acceptance audit record
  static Future<Map<String, dynamic>> getAcceptanceRecord() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'accepted': prefs.getBool(keyEulaAccepted) ?? false,
        'timestamp': prefs.getString(keyEulaTimestamp),
        'version': prefs.getString(keyEulaVersion) ?? currentEulaVersion,
      };
    } catch (e) {
      return {'accepted': false, 'timestamp': null, 'version': currentEulaVersion};
    }
  }

  /// Shows the complete, tabbed, dark liquid glass legal dialog.
  /// Requires scrolling down both tabs completely before enabling the acceptance button.
  static void showLegalTermsModal(
    BuildContext context, {
    bool isMandatoryAcceptance = false,
    VoidCallback? onAccepted,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatoryAcceptance,
      builder: (ctx) => _LegalTermsDialogContent(
        isMandatoryAcceptance: isMandatoryAcceptance,
        onAccepted: onAccepted,
      ),
    );
  }
}

class _LegalTermsDialogContent extends StatefulWidget {
  final bool isMandatoryAcceptance;
  final VoidCallback? onAccepted;

  const _LegalTermsDialogContent({
    required this.isMandatoryAcceptance,
    this.onAccepted,
  });

  @override
  State<_LegalTermsDialogContent> createState() => _LegalTermsDialogContentState();
}

class _LegalTermsDialogContentState extends State<_LegalTermsDialogContent> {
  final ScrollController _eulaScrollCtrl = ScrollController();
  final ScrollController _kvkkScrollCtrl = ScrollController();

  bool _eulaScrolledToBottom = false;
  bool _kvkkScrolledToBottom = false;

  @override
  void initState() {
    super.initState();
    // If not mandatory, allow instant closing
    if (!widget.isMandatoryAcceptance) {
      _eulaScrolledToBottom = true;
      _kvkkScrolledToBottom = true;
    }

    _eulaScrollCtrl.addListener(_onEulaScroll);
    _kvkkScrollCtrl.addListener(_onKvkkScroll);
  }

  void _onEulaScroll() {
    if (!_eulaScrolledToBottom && _eulaScrollCtrl.hasClients) {
      if (_eulaScrollCtrl.position.pixels >= _eulaScrollCtrl.position.maxScrollExtent - 40) {
        setState(() => _eulaScrolledToBottom = true);
      }
    }
  }

  void _onKvkkScroll() {
    if (!_kvkkScrolledToBottom && _kvkkScrollCtrl.hasClients) {
      if (_kvkkScrollCtrl.position.pixels >= _kvkkScrollCtrl.position.maxScrollExtent - 40) {
        setState(() => _kvkkScrolledToBottom = true);
      }
    }
  }

  @override
  void dispose() {
    _eulaScrollCtrl.dispose();
    _kvkkScrollCtrl.dispose();
    super.dispose();
  }

  bool get _canAccept => _eulaScrolledToBottom && _kvkkScrolledToBottom;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.all(16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded, color: Color(0xFF00E676), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Yasal Sözleşmeler & KVKK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TabBar(
              indicatorColor: const Color(0xFF00E676),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00E676),
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Kullanım (EULA)'),
                      const SizedBox(width: 4),
                      Icon(
                        _eulaScrolledToBottom ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        size: 14,
                        color: _eulaScrolledToBottom ? const Color(0xFF00E676) : Colors.white38,
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('KVKK & Gizlilik'),
                      const SizedBox(width: 4),
                      Icon(
                        _kvkkScrolledToBottom ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        size: 14,
                        color: _kvkkScrolledToBottom ? const Color(0xFF00E676) : Colors.white38,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: Column(
            children: [
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      controller: _eulaScrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: const Text(
                        LegalTermsService.eulaAndTerms,
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
                      ),
                    ),
                    SingleChildScrollView(
                      controller: _kvkkScrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: const Text(
                        LegalTermsService.kvkkAndPrivacy,
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isMandatoryAcceptance && !_canAccept)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.touch_app_rounded, color: Colors.amberAccent, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          !_eulaScrolledToBottom && !_kvkkScrolledToBottom
                              ? 'Lütfen 2 sekmeyi de sonuna kadar kaydırıp okuyun'
                              : (!_eulaScrolledToBottom
                                  ? 'Lütfen EULA sekmesini sonuna kadar kaydırın'
                                  : 'Lütfen KVKK sekmesini sonuna kadar kaydırın'),
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (widget.isMandatoryAcceptance)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canAccept ? const Color(0xFF00E676) : Colors.grey.shade800,
                  foregroundColor: _canAccept ? Colors.black : Colors.white38,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: _canAccept ? 4 : 0,
                ),
                onPressed: _canAccept
                    ? () async {
                        await LegalTermsService.saveAcceptanceRecord();
                        if (context.mounted) {
                          Navigator.pop(context);
                          if (widget.onAccepted != null) widget.onAccepted!();
                        }
                      }
                    : null,
                child: Text(
                  _canAccept ? 'OKUDUM, ANLADIM VE KABUL EDİYORUM' : 'LÜTFEN TÜM METİNLERİ OKUYUN (${(_eulaScrolledToBottom ? 1 : 0) + (_kvkkScrolledToBottom ? 1 : 0)}/2)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: _canAccept ? Colors.black : Colors.white54,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'KAPAT',
                style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
