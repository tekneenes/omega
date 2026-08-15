import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../models/call_session.dart';
import '../models/chat_message.dart';
import '../providers/app_state_provider.dart';
import '../utils/web_audio_recorder.dart';
import '../widgets/profile_avatar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  AudioPlayer? _audioPlayer;
  String? _playingMessageId;
  StreamSubscription? _playerCompleteSubscription;
  bool _showScrollToBottomButton = false;
  int _displayLimit = 15;
  final Set<String> _historyMessageIds = {};
  final Set<String> _animatedMessageIds = {};
  bool _hasInitialized = false;

  Timer? _typingDebounceTimer;
  Timer? _typingHeartbeatTimer;
  bool _isCurrentlyTyping = false;
  bool _hasTextInput = false;
  String? _editingMessageId;

  final Map<String, Uint8List> _base64ImageCache = {};

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      if (appState.pairedProfile != null) {
        appState.setActiveChatPartner(appState.pairedProfile!.id);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final currentScroll = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Show button when scrolled up (>150px from bottom)
    final isScrolledUp = currentScroll > 150;
    if (isScrolledUp != _showScrollToBottomButton) {
      if (mounted) {
        setState(() {
          _showScrollToBottomButton = isScrolledUp;
        });
      }
    }

    // Load 15 more older messages when scrolling near top of history
    if (currentScroll > maxScroll - 150) {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      final pairedId = appState.pairedProfile?.id ?? '';
      final pairedPin = appState.pairedProfile?.pairCode ?? '';
      final allMessages = appState.getMessagesForContact(pairedId, pairedPin);
      if (_displayLimit < allMessages.length) {
        // Mark newly paginated messages as history so they animate left/right
        final oldVisibleCount = _displayLimit.clamp(0, allMessages.length);
        final newDisplayLimit = (_displayLimit + 15).clamp(0, allMessages.length);
        final oldStartIndex = allMessages.length - oldVisibleCount;
        final newStartIndex = allMessages.length - newDisplayLimit;
        for (int i = newStartIndex; i < oldStartIndex; i++) {
          _historyMessageIds.add(allMessages[i].id);
        }
        setState(() {
          _displayLimit += 15;
        });
      }
    }
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _playerCompleteSubscription = _audioPlayer?.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingMessageId = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _playerCompleteSubscription?.cancel();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _stopTyping();
    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      appState.setActiveChatPartner(null);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _togglePlayVoiceMessage(ChatMessage msg) async {
    if (_audioPlayer == null) return;

    if (_playingMessageId == msg.id) {
      await _audioPlayer?.stop();
      if (mounted) {
        setState(() {
          _playingMessageId = null;
        });
      }
    } else {
      await _audioPlayer?.stop();
      if (mounted) {
        setState(() {
          _playingMessageId = msg.id;
        });
      }
      try {
        if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
          if (msg.mediaUrl!.startsWith('data:audio')) {
            // Extract the mime type from the data URI (e.g. "audio/webm" or "audio/aac")
            final mimeMatch = RegExp(r'data:(audio/[^;]+);').firstMatch(msg.mediaUrl!);
            final mimeType = mimeMatch?.group(1) ?? 'audio/webm';
            final base64Audio = msg.mediaUrl!.split(',').last;
            final bytes = base64Decode(base64Audio);
            
            if (kIsWeb) {
              await _audioPlayer?.play(BytesSource(bytes, mimeType: mimeType));
            } else {
              // Determine correct file extension from actual mime type
              final ext = mimeType.contains('webm') ? '.webm'
                        : mimeType.contains('ogg')  ? '.ogg'
                        : mimeType.contains('wav')  ? '.wav'
                        : mimeType.contains('mp3')  ? '.mp3'
                        : '.m4a';
              final tempDir = await getTemporaryDirectory();
              final safeId = msg.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
              final tempFile = File('${tempDir.path}/play_$safeId$ext');
              await tempFile.writeAsBytes(bytes);
              
              if (ext == '.webm' || ext == '.ogg') {
                // macOS AVPlayer does NOT support WebM/OGG.
                // Use BytesSource as fallback — audioplayers will use its own decoder.
                await _audioPlayer?.play(BytesSource(bytes, mimeType: mimeType));
              } else {
                await _audioPlayer?.play(DeviceFileSource(tempFile.path));
              }
            }
          } else if (msg.mediaUrl!.startsWith('http://') || msg.mediaUrl!.startsWith('https://')) {
            await _audioPlayer?.play(UrlSource(msg.mediaUrl!));
          } else if (!kIsWeb && File(msg.mediaUrl!).existsSync()) {
            await _audioPlayer?.play(DeviceFileSource(msg.mediaUrl!));
          } else {
            _showVoiceErrorSnackBar();
          }
        } else {
          _showVoiceErrorSnackBar();
        }
      } catch (e) {
        debugPrint('⚠️ [AUDIO PLAY WARN]: $e');
        _showVoiceErrorSnackBar();
      }
    }
  }

  void _showVoiceErrorSnackBar() {
    if (mounted) {
      setState(() {
        _playingMessageId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Bu mesajda geçerli bir ses kaydı verisi bulunmuyor.'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _stopTyping() {
    _typingDebounceTimer?.cancel();
    _typingHeartbeatTimer?.cancel();
    if (_isCurrentlyTyping) {
      _isCurrentlyTyping = false;
      try {
        final appState = Provider.of<AppStateProvider>(context, listen: false);
        appState.sendTypingStatus(false);
      } catch (_) {}
    }
  }

  void _onTextChanged(String val) {
    final text = val.trim();
    final hasText = text.isNotEmpty;
    if (hasText != _hasTextInput) {
      setState(() {
        _hasTextInput = hasText;
      });
    }

    final appState = Provider.of<AppStateProvider>(context, listen: false);
    if (text.isNotEmpty) {
      if (!_isCurrentlyTyping) {
        _isCurrentlyTyping = true;
        appState.sendTypingStatus(true);

        _typingHeartbeatTimer?.cancel();
        _typingHeartbeatTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
          if (_isCurrentlyTyping && mounted) {
            appState.sendTypingStatus(true);
          }
        });
      }

      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
        _stopTyping();
      });
    } else {
      _stopTyping();
    }
  }

  void _sendMessage({String? customText}) async {
    final text = (customText ?? _messageController.text).trim();
    if (text.isEmpty) return;

    final appState = Provider.of<AppStateProvider>(context, listen: false);

    if (_editingMessageId != null) {
      await appState.editChatMessage(_editingMessageId!, text);
      setState(() {
        _editingMessageId = null;
        _hasTextInput = false;
      });
      _messageController.clear();
      _stopTyping();
      return;
    }

    appState.sendMessage(text);
    if (customText == null) {
      _messageController.clear();
      setState(() {
        _hasTextInput = false;
      });
    }
    _stopTyping();
    _scrollToBottom();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _hasTextInput = false;
      _messageController.clear();
    });
  }

  // --- DOWNLOAD PHOTO / MEDIA ---
  Future<void> _downloadImage(String base64Str) async {
    try {
      final cleanBase64 = base64Str.contains(',') ? base64Str.split(',').last : base64Str;
      final bytes = base64Decode(cleanBase64);
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/omega_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                const SizedBox(width: 10),
                Expanded(child: Text('Fotoğraf indirildi:\n$filePath')),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İndirme hatası: $e')),
        );
      }
    }
  }

  // --- FULLSCREEN IMAGE VIEWER ---
  void _showFullScreenImage(String base64Str) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.5),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
            actions: [
              IconButton(
                tooltip: 'Fotoğrafı İndir',
                icon: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
                onPressed: () {
                  _downloadImage(base64Str);
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: _buildImageWidget(context, base64Str),
            ),
          ),
        );
      },
    );
  }

  // --- LONG PRESS MESSAGE OPTIONS (EDIT / DELETE / COPY / DOWNLOAD) ---
  void _showMessageOptions(ChatMessage msg, bool isMe) {
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Copy Text
                if (!msg.isDeleted && msg.text.isNotEmpty && msg.type == MessageType.text)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: Colors.white),
                    title: const Text('Metni Kopyala', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mesaj kopyalandı')),
                      );
                    },
                  ),

                // Download Photo
                if (msg.type == MessageType.photo && msg.mediaUrl != null)
                  ListTile(
                    leading: const Icon(Icons.download_rounded, color: Colors.amber),
                    title: const Text('Fotoğrafı İndir', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _downloadImage(msg.mediaUrl!);
                    },
                  ),

                // Edit Message (Only own messages)
                if (isMe && !msg.isDeleted && msg.type == MessageType.text)
                  ListTile(
                    leading: const Icon(Icons.edit_rounded, color: Color(0xFF38BDF8)),
                    title: const Text('Mesajı Düzenle', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _editingMessageId = msg.id;
                        _messageController.text = msg.text;
                        _hasTextInput = true;
                      });
                    },
                  ),

                // Delete For Everyone (Only own messages)
                if (isMe && !msg.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                    title: const Text('Herkesten Sil', style: TextStyle(color: Colors.redAccent)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await appState.deleteChatMessage(msg.id);
                    },
                  ),

                // Delete For Me (Available for any message)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.orangeAccent),
                  title: const Text('Benden Sil', style: TextStyle(color: Colors.orangeAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await appState.deleteChatMessageForMe(msg.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _sendMedia(String text, MessageType type, {String? mediaUrl}) {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    appState.sendMediaMessage(text, type, mediaUrl: mediaUrl);
    _scrollToBottom();
  }

  void _scrollToBottom({bool animated = true}) {
    if (_scrollController.hasClients) {
      if (animated) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  void _showPhotoPicker(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _sendMedia('📷 Fotoğraf Gönderildi', MessageType.photo, mediaUrl: base64Image);
      }
    } catch (e) {
      debugPrint('⚠️ [PHOTO PICKER ERROR]: $e');
    }
  }

  void _showCameraPicker(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _sendMedia('📷 Fotoğraf Gönderildi', MessageType.photo, mediaUrl: base64Image);
      }
    } catch (e) {
      debugPrint('⚠️ [CAMERA PICKER ERROR]: $e');
    }
  }

  void _showVoiceNoteDialog(BuildContext context) async {
    bool isRecordingStarted = false;
    WebAudioRecorder? webRecorder;
    AudioRecorder? nativeRecorder;
    String? nativeRecordPath;

    try {
      if (kIsWeb) {
        // Web: use our custom WebAudioRecorder (WAV output)
        webRecorder = WebAudioRecorder();
        isRecordingStarted = await webRecorder.start();
      } else {
        // Native (iOS/Android/macOS): use record package (AAC output)
        nativeRecorder = AudioRecorder();
        if (await nativeRecorder.hasPermission()) {
          final tempDir = await getTemporaryDirectory();
          nativeRecordPath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await nativeRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc),
            path: nativeRecordPath,
          );
          isRecordingStarted = true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [RECORD START ERROR]: $e');
    }

    if (!context.mounted) return;

    int elapsedSeconds = 0;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (dialogCtx.mounted) {
              setDialogState(() {
                elapsedSeconds++;
              });
            }
          });

          final minutes = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
          final seconds = (elapsedSeconds % 60).toString().padLeft(2, '0');
          final durationStr = '$minutes:$seconds';

          return AlertDialog(
            backgroundColor: const Color(0xFF384353),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.mic_rounded, color: Color(0xFF00E676), size: 28),
                SizedBox(width: 10),
                Text('Sesli Mesaj Kaydı', style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                  ),
                  child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF00E676), size: 40),
                ),
                const SizedBox(height: 16),
                Text(
                  '🎙️ Sesiniz kaydediliyor: $durationStr',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  isRecordingStarted
                      ? 'Konuşmanız bittiğinde GÖNDER butonuna basın.'
                      : 'Mikrofon izni kontrol ediliyor...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  timer?.cancel();
                  if (isRecordingStarted) {
                    try {
                      if (kIsWeb) {
                        await webRecorder?.stop();
                      } else {
                        await nativeRecorder?.stop();
                        nativeRecorder?.dispose();
                      }
                    } catch (_) {}
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('İPTAL ET', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('GÖNDER', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  timer?.cancel();
                  String? audioBase64;
                  if (isRecordingStarted) {
                    try {
                      if (kIsWeb) {
                        // Web: get WAV bytes from WebAudioRecorder
                        final rawBytes = await webRecorder?.stop();
                        if (rawBytes != null && rawBytes.isNotEmpty) {
                          audioBase64 = 'data:audio/wav;base64,${base64Encode(rawBytes)}';
                          debugPrint('🎙️ [WEB VOICE] WAV Base64 length: ${audioBase64.length}');
                        }
                      } else {
                        // Native: get AAC file from record package
                        final path = await nativeRecorder?.stop();
                        nativeRecorder?.dispose();
                        if (path != null && path.isNotEmpty) {
                          final file = File(path);
                          if (await file.exists()) {
                            final rawBytes = await file.readAsBytes();
                            if (rawBytes.isNotEmpty) {
                              audioBase64 = 'data:audio/aac;base64,${base64Encode(rawBytes)}';
                              debugPrint('🎙️ [NATIVE VOICE] AAC Base64 length: ${audioBase64.length}');
                            }
                          }
                        }
                      }
                    } catch (e) {
                      debugPrint('⚠️ [RECORD STOP ERROR]: $e');
                    }
                  }

                  if (ctx.mounted) Navigator.pop(ctx);

                  final finalDurationStr = elapsedSeconds > 0 ? durationStr : '00:03';
                  _sendMedia(
                    '🎙️ Sesli Mesaj ($finalDurationStr)',
                    MessageType.voice,
                    mediaUrl: audioBase64,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAttachmentMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF384353),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📎 Medya / Dosya Gönder',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF00E676)),
              title: const Text('Galeriden Fotoğraf Seç', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showPhotoPicker(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF00E676)),
              title: const Text('Kamera İle Çek & Gönder', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showCameraPicker(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic_rounded, color: Color(0xFF00E676)),
              title: const Text('Sesli Mesaj Kaydet & Gönder', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showVoiceNoteDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final paired = appState.pairedProfile;
    final pairedName = paired?.deviceName ?? 'İletişim';
    final pairCode = paired?.pairCode ?? '';
    final myId = appState.myProfile?.id ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF5B6578),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8BA0B5), Color(0xFF4A5568)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildGlassHeader(context, appState, pairedName, pairCode),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final allMessages = appState.getMessagesForContact(
                        appState.pairedProfile?.id ?? '',
                        appState.pairedProfile?.pairCode ?? '',
                      );
                      if (allMessages.isEmpty && !appState.isPeerTyping) {
                        return _buildEmptyChatState();
                      }

                      final visibleCount = _displayLimit.clamp(0, allMessages.length);
                      final startIndex = allMessages.length - visibleCount;
                      final visibleMessages = allMessages.sublist(startIndex);

                      // On FIRST build, capture all existing messages as "history"
                      // so they animate left/right, not from bottom
                      if (!_hasInitialized) {
                        _hasInitialized = true;
                        for (final m in allMessages) {
                          _historyMessageIds.add(m.id);
                        }
                      }

                      final showTypingIndicator = appState.isPeerTyping;
                      final itemCount = visibleMessages.length + (showTypingIndicator ? 1 : 0);

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          if (showTypingIndicator && index == 0) {
                            return _TypingIndicatorBubble();
                          }

                          final msgIndex = showTypingIndicator ? index - 1 : index;
                          final msg = visibleMessages[visibleMessages.length - 1 - msgIndex];
                          final isMe = msg.senderId == myId;
                          final timeStr = DateFormat('HH:mm').format(msg.timestamp);

                          // Determine animation type:
                          // 1. Already animated before → none (skip animation on rebuild)
                          // 2. History message (initial load / pagination) → side
                          // 3. New live message → bottom
                          BubbleAnimationType animType;
                          if (_animatedMessageIds.contains(msg.id)) {
                            animType = BubbleAnimationType.none;
                          } else {
                            final isHistoryMsg = _historyMessageIds.contains(msg.id);
                            animType = isHistoryMsg ? BubbleAnimationType.side : BubbleAnimationType.bottom;
                            _animatedMessageIds.add(msg.id);
                          }

                          if (!_historyMessageIds.contains(msg.id)) {
                            _historyMessageIds.add(msg.id);
                          }

                          final isFirstOfDay = (msgIndex == visibleMessages.length - 1) ||
                              !_isSameDay(msg.timestamp, visibleMessages[visibleMessages.length - 1 - (msgIndex + 1)].timestamp);

                          final bubble = _AnimatedMessageBubble(
                            key: ValueKey(msg.id),
                            isMe: isMe,
                            animationType: animType,
                            child: _buildMessageBubble(
                              context,
                              msg,
                              timeStr,
                              isMe,
                            ),
                          );

                          if (isFirstOfDay) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildDateSeparatorPill(msg.timestamp),
                                bubble,
                              ],
                            );
                          }

                          return bubble;
                        },
                      );
                    },
                  ),
                ),
                if (_editingMessageId != null)
                  Container(
                    color: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_rounded, color: Color(0xFF38BDF8), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Mesaj Düzenleniyor...',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                          onPressed: _cancelEditing,
                        ),
                      ],
                    ),
                  ),
                _buildInputBar(appState),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: 80,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showScrollToBottomButton ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showScrollToBottomButton,
                child: FloatingActionButton.small(
                  heroTag: 'scrollToBottomBtn',
                  backgroundColor: const Color(0xFF384353),
                  foregroundColor: const Color(0xFF00E676),
                  elevation: 6,
                  onPressed: () => _scrollToBottom(animated: true),
                  child: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);

    if (msgDate == today) {
      return 'BUGÜN';
    } else if (msgDate == yesterday) {
      return 'DÜN';
    } else if (now.difference(msgDate).inDays < 7 && msgDate.weekday < now.weekday) {
      return DateFormat('EEEE', 'tr_TR').format(date).toUpperCase();
    } else if (date.year == now.year) {
      return DateFormat('d MMMM', 'tr_TR').format(date).toUpperCase();
    } else {
      return DateFormat('d MMMM yyyy', 'tr_TR').format(date).toUpperCase();
    }
  }

  Widget _buildDateSeparatorPill(DateTime date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          _formatDateHeader(date),
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _buildGlassHeader(
    BuildContext context,
    AppStateProvider appState,
    String pairedName,
    String pairCode,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          ProfileAvatar(
            profile: appState.pairedProfile,
            radius: 20,
            borderWidth: 1.5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pairedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  appState.isPeerTyping ? 'yazıyor...' : 'Çevrimiçi • Kod: $pairCode',
                  style: TextStyle(
                    fontSize: 12,
                    color: appState.isPeerTyping ? const Color(0xFF69F0AE) : const Color(0xFF00E676),
                    fontWeight: appState.isPeerTyping ? FontWeight.bold : FontWeight.w600,
                    fontStyle: appState.isPeerTyping ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Colors.white, size: 22),
            onPressed: () {
              appState.startCall(CallType.audio);
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
            onPressed: () {
              appState.startCall(CallType.video);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) async {
              if (value == 'clear') {
                final targetId = appState.pairedProfile?.id ?? '';
                final targetName = appState.pairedProfile?.deviceName ?? 'Bu kişi';
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Sohbeti Temizle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    content: Text('$targetName ile olan tüm mesajlar silinecektir. Onaylıyor musunuz?',
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç', style: TextStyle(color: Colors.white60))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Temizle'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && targetId.isNotEmpty) {
                  await appState.deleteEntireChatWithDevice(targetId);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                    SizedBox(width: 10),
                    Text('Sohbeti Temizle', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChatState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Henüz Mesaj Bulunmuyor',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aşağıdaki mesaj alanından ilk mesajınızı veya sesli notunuzu gönderebilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessage msg,
    String timeStr,
    bool isMe,
  ) {
    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    return GestureDetector(
      onLongPress: () => _showMessageOptions(msg, isMe),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: msg.isDeleted
                ? Colors.grey.shade800.withValues(alpha: 0.7)
                : (isMe
                    ? Colors.white.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.18)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.isDeleted) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.block_rounded, color: Colors.white54, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '🚫 Bu mesaj silindi',
                      style: TextStyle(
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ] else if (msg.type == MessageType.photo && msg.mediaUrl != null) ...[
                GestureDetector(
                  onTap: () => _showFullScreenImage(msg.mediaUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildImageWidget(context, msg.mediaUrl!),
                  ),
                ),
                if (msg.text.isNotEmpty && msg.text != '📷 Fotoğraf') ...[
                  const SizedBox(height: 6),
                  Text(
                    msg.text,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5),
                  ),
                ],
              ] else if (msg.type == MessageType.voice) ...[
                GestureDetector(
                  onTap: () => _togglePlayVoiceMessage(msg),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF00E676),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _playingMessageId == msg.id
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _playingMessageId == msg.id
                                  ? '🔊 Oynatılıyor...'
                                  : 'Dinlemek için dokunun',
                              style: TextStyle(
                                color: _playingMessageId == msg.id
                                    ? const Color(0xFF00E676)
                                    : Colors.white70,
                                fontSize: 11,
                                fontWeight: _playingMessageId == msg.id
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ] else ...[
                Text(
                  msg.text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  if (msg.isEdited) ...[
                    const SizedBox(width: 4),
                    const Text(
                      ' • düzenlendi',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildMessageStatusIcon(msg),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageStatusIcon(ChatMessage msg) {
    if (msg.isRead) {
      return const Icon(
        Icons.done_all_rounded,
        size: 16,
        color: Color(0xFF34B7F1), // WhatsApp Blue
      );
    } else if (msg.isDelivered) {
      return const Icon(
        Icons.done_all_rounded,
        size: 16,
        color: Colors.white70, // Double grey ticks
      );
    } else {
      return const Icon(
        Icons.check_rounded,
        size: 15,
        color: Colors.white60, // Single grey tick
      );
    }
  }

  Widget _buildImageWidget(BuildContext context, String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return _buildImagePlaceholder();
    }

    Widget imgWidget;
    try {
      if (mediaUrl.startsWith('data:image')) {
        Uint8List? bytes = _base64ImageCache[mediaUrl];
        if (bytes == null) {
          final base64Str = mediaUrl.split(',').last;
          bytes = base64Decode(base64Str);
          _base64ImageCache[mediaUrl] = bytes;
        }
        imgWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200,
          errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
        );
      } else if (mediaUrl.startsWith('http://') ||
          mediaUrl.startsWith('https://') ||
          mediaUrl.startsWith('blob:')) {
        imgWidget = Image.network(
          mediaUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200,
          errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
        );
      } else if (!kIsWeb && File(mediaUrl.replaceAll('file://', '')).existsSync()) {
        imgWidget = Image.file(
          File(mediaUrl.replaceAll('file://', '')),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200,
          errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
        );
      } else {
        imgWidget = _buildImagePlaceholder();
      }
    } catch (e) {
      imgWidget = _buildImagePlaceholder();
    }

    return GestureDetector(
      onTap: () => _showFullImageDialog(context, mediaUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            imgWidget,
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_rounded, color: Colors.white70, size: 36),
          SizedBox(height: 6),
          Text(
            'Görüntü Yüklenemedi',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showFullImageDialog(BuildContext context, String mediaUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: _buildFullImageWidget(mediaUrl),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Fotoğrafı İndir',
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
                    onPressed: () => _downloadImage(mediaUrl),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullImageWidget(String mediaUrl) {
    try {
      if (mediaUrl.startsWith('data:image')) {
        Uint8List? bytes = _base64ImageCache[mediaUrl];
        if (bytes == null) {
          final base64Str = mediaUrl.split(',').last;
          bytes = base64Decode(base64Str);
          _base64ImageCache[mediaUrl] = bytes;
        }
        return Image.memory(bytes, fit: BoxFit.contain);
      } else if (mediaUrl.startsWith('http://') ||
          mediaUrl.startsWith('https://') ||
          mediaUrl.startsWith('blob:')) {
        return Image.network(mediaUrl, fit: BoxFit.contain);
      } else if (!kIsWeb && File(mediaUrl.replaceAll('file://', '')).existsSync()) {
        return Image.file(File(mediaUrl.replaceAll('file://', '')), fit: BoxFit.contain);
      }
    } catch (_) {}
    return const Icon(Icons.image_rounded, color: Colors.white, size: 64);
  }

  Widget _buildInputBar(AppStateProvider appState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () => _showAttachmentMenu(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: const Icon(
                Icons.attach_file_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _messageController,
                onChanged: _onTextChanged,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: !_hasTextInput
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: !_hasTextInput ? 1.0 : 0.0,
                      child: GestureDetector(
                        onTap: () => _showVoiceNoteDialog(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendMessage(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum BubbleAnimationType { side, bottom, none }

class _AnimatedMessageBubble extends StatefulWidget {
  final bool isMe;
  final BubbleAnimationType animationType;
  final Widget child;

  const _AnimatedMessageBubble({
    required this.isMe,
    this.animationType = BubbleAnimationType.bottom,
    required this.child,
    super.key,
  });

  @override
  State<_AnimatedMessageBubble> createState() => _AnimatedMessageBubbleState();
}

class _AnimatedMessageBubbleState extends State<_AnimatedMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    if (widget.animationType == BubbleAnimationType.none) {
      // Already shown message — no animation, jump to end state immediately
      _slideAnimation = AlwaysStoppedAnimation(Offset.zero);
      _fadeAnimation = const AlwaysStoppedAnimation(1.0);
      _controller.value = 1.0;
    } else {
      // Live NEW message -> Slide up from BOTTOM (0.0, 0.45)
      // First-time history messages -> Slide in from RIGHT/LEFT
      final Offset startOffset = widget.animationType == BubbleAnimationType.bottom
          ? const Offset(0.0, 0.45)
          : (widget.isMe ? const Offset(0.25, 0.0) : const Offset(-0.25, 0.0));

      _slideAnimation = Tween<Offset>(
        begin: startOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ));

      _fadeAnimation = CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      );

      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.animationType == BubbleAnimationType.none) {
      return widget.child;
    }
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatefulWidget {
  const _TypingIndicatorBubble();

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with TickerProviderStateMixin {
  late AnimationController _dotsController;
  late AnimationController _entryController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // Dots bounce animation
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Smooth entry animation (fade + subtle slide up)
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    ));
    _entryController.forward();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8, left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _dotsController,
              builder: (context, child) {
                final value = _dotsController.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final delay = index * 0.25;
                    final animValue = (value - delay) % 1.0;
                    final opacity = (animValue < 0.5 ? animValue * 2 : (1.0 - animValue) * 2).clamp(0.25, 1.0);
                    final translateY = -3.5 * (animValue < 0.5 ? animValue * 2 : (1.0 - animValue) * 2);

                    return Transform.translate(
                      offset: Offset(0, translateY),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFF384353).withValues(alpha: opacity),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
