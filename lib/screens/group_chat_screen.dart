import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../providers/app_state_provider.dart';
import '../services/firebase_config_service.dart';
import '../theme/app_theme.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  AudioRecorder? _audioRecorder;
  AudioPlayer? _audioPlayer;
  StreamSubscription? _playerCompleteSubscription;

  bool _isRecording = false;
  String? _playingMessageId;
  bool _showScrollToBottomButton = false;
  bool _hasTextInput = false;

  // Editing state
  String? _editingMessageId;

  final Map<String, Uint8List> _base64ImageCache = {};

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      appState.setGroupChatActive(true);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final currentScroll = _scrollController.offset;
    final isScrolledUp = currentScroll > 150;
    if (isScrolledUp != _showScrollToBottomButton) {
      if (mounted) {
        setState(() {
          _showScrollToBottomButton = isScrolledUp;
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
    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      appState.setGroupChatActive(false);
    } catch (_) {}
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;

    final appState = Provider.of<AppStateProvider>(context, listen: false);

    if (_editingMessageId != null) {
      // Editing existing message
      await appState.editGroupChatMessage(_editingMessageId!, text);
      setState(() {
        _editingMessageId = null;
        _hasTextInput = false;
      });
      _messageController.clear();
      return;
    }

    _messageController.clear();
    setState(() {
      _hasTextInput = false;
    });

    await appState.sendGroupChatMessage(text);
    _scrollToBottom();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _hasTextInput = false;
      _messageController.clear();
    });
  }


  Future<void> _pickAndSendPhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 1024,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64String = base64Encode(bytes);
        if (mounted) {
          final appState = Provider.of<AppStateProvider>(context, listen: false);
          await appState.sendGroupMediaMessage(
            '📷 Fotoğraf',
            MessageType.photo,
            mediaUrl: base64String,
          );
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Error picking photo: $e');
    }
  }

  Future<void> _startRecording() async {
    try {
      _audioRecorder = AudioRecorder();
      if (await _audioRecorder!.hasPermission()) {
        final tempDir = Directory.systemTemp;
        final path = '${tempDir.path}/group_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder!.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    try {
      if (_audioRecorder != null && _isRecording) {
        final path = await _audioRecorder!.stop();
        setState(() {
          _isRecording = false;
        });

        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final base64Audio = base64Encode(bytes);
            if (mounted) {
              final appState = Provider.of<AppStateProvider>(context, listen: false);
              await appState.sendGroupMediaMessage(
                '🎤 Ses Mesajı',
                MessageType.voice,
                mediaUrl: base64Audio,
              );
              _scrollToBottom();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    } finally {
      _audioRecorder?.dispose();
      _audioRecorder = null;
    }
  }

  Future<void> _togglePlayVoiceMessage(ChatMessage msg) async {
    if (_audioPlayer == null) return;
    if (_playingMessageId == msg.id) {
      await _audioPlayer?.stop();
      if (mounted) setState(() => _playingMessageId = null);
    } else {
      await _audioPlayer?.stop();
      if (mounted) setState(() => _playingMessageId = msg.id);

      if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
        try {
          final bytes = base64Decode(msg.mediaUrl!);
          await _audioPlayer?.play(BytesSource(bytes));
        } catch (e) {
          debugPrint('Error playing voice: $e');
          if (mounted) setState(() => _playingMessageId = null);
        }
      }
    }
  }

  // --- DOWNLOAD PHOTO / MEDIA ---
  Future<void> _downloadImage(String base64Str) async {
    try {
      final bytes = base64Decode(base64Str);
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
                Expanded(child: Text('Fotoğraf başarıyla indirildi:\n$filePath')),
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
              child: _buildImageWidget(base64Str),
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
                      await appState.deleteGroupChatMessage(msg.id);
                    },
                  ),

                // Delete For Me (Available for any message)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.orangeAccent),
                  title: const Text('Benden Sil', style: TextStyle(color: Colors.orangeAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await appState.deleteGroupMessageForMe(msg.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final messages = appState.groupChatHistory.reversed.toList();
    final familyCount = appState.pairedDevicesList.length + 1;

    return Scaffold(
      backgroundColor: const Color(0xFF5B6578),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF475569), Color(0xFF1E293B)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Glassmorphic Group Header
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD97706), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.3),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Center(
                          child: Text(
                            '👨‍👩‍👧‍👦',
                            style: TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Aile Odası',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '$familyCount Aile Bireyi Bağlı',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
                        color: const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onSelected: (value) async {
                          if (value == 'reset') {
                            final isAdmin = await FirebaseConfigService.isNetworkAdmin();
                            if (!context.mounted) return;

                            if (!isAdmin) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E293B),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Row(
                                    children: [
                                      Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 24),
                                      SizedBox(width: 10),
                                      Text('Yönetici Yetkisi Gerekli', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  content: const Text(
                                    'Aile Odası mesajlarını yalnızca ağı ilk kuran Yönetici Cihaz tüm cihazlar için sıfırlayabilir.',
                                    style: TextStyle(color: Colors.white70, fontSize: 14),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Tamam', style: TextStyle(color: Color(0xFF00E676))),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF1E293B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 28),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Aile Sohbetini Sıfırla',
                                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                content: const Text(
                                  '👑 Yönetici İşlemi:\nTüm bağlı cihazlardaki ve sunucudaki Aile Odası mesajları kalıcı olarak temizlenecektir. Devam etmek istiyor musunuz?',
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Vazgeç', style: TextStyle(color: Colors.white60)),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                                    label: const Text('Tüm Cihazlarda Sıfırla', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () => Navigator.pop(ctx, true),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true && context.mounted) {
                              await appState.resetFamilyGroupChatForAllDevices();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('👑 Aile Odası tüm cihazlar için başarıyla sıfırlandı.'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'reset',
                            child: Row(
                              children: [
                                Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                                SizedBox(width: 10),
                                Text('Sohbeti Sıfırla (Yönetici)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Chat Messages List
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 48)),
                                SizedBox(height: 12),
                                Text(
                                  'Aile Odasına Hoş Geldiniz!',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Tüm aile bireyleri bu odada mesajlaşabilir. İlk mesajı siz atın!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isMe = appState.myProfile != null &&
                                (msg.senderId == appState.myProfile!.id ||
                                    msg.senderId.endsWith(appState.myProfile!.id.split('_').last));

                            return _buildGroupMessageBubble(msg, isMe);
                          },
                        ),
                ),

                // Editing Indicator Bar
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

                // Bottom Input Area
                _buildInputArea(appState),
              ],
            ),
          ),

          // Scroll to Bottom Floating Button
          if (_showScrollToBottomButton)
            Positioned(
              bottom: 90,
              right: 20,
              child: FloatingActionButton.small(
                backgroundColor: AppTheme.primary,
                onPressed: _scrollToBottom,
                child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupMessageBubble(ChatMessage msg, bool isMe) {
    final isAlarm = msg.text.contains('🔔 YÜKSEK İKAZ');
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);
    final authorName = isMe ? 'Siz' : (msg.senderName ?? 'Aile Üyesi');

    return GestureDetector(
      onLongPress: () => _showMessageOptions(msg, isMe),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: msg.isDeleted
                ? Colors.grey.shade800.withValues(alpha: 0.7)
                : (isAlarm
                    ? Colors.redAccent.withValues(alpha: 0.9)
                    : (isMe
                        ? const Color(0xFF0284C7).withValues(alpha: 0.9)
                        : const Color(0xFF334155).withValues(alpha: 0.85))),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            border: Border.all(
              color: isMe ? const Color(0xFF7DD3FC).withValues(alpha: 0.4) : Colors.white24,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Author Name Header for Group Messages
              if (!isMe) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        authorName,
                        style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              // Content based on type and status
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
                    child: _buildImageWidget(msg.mediaUrl!),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _playingMessageId == msg.id
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () => _togglePlayVoiceMessage(msg),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Ses Mesajı',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  msg.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.3,
                  ),
                ),
              ],

              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                  if (msg.isEdited) ...[
                    const SizedBox(width: 4),
                    const Text(
                      ' • düzenlendi',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageWidget(String base64Str) {
    if (_base64ImageCache.containsKey(base64Str)) {
      return Image.memory(_base64ImageCache[base64Str]!, fit: BoxFit.cover);
    }
    try {
      final bytes = base64Decode(base64Str);
      _base64ImageCache[base64Str] = bytes;
      return Image.memory(bytes, fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 40);
    }
  }

  Widget _buildInputArea(AppStateProvider appState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // Photo Picker
          IconButton(
            icon: const Icon(Icons.photo_library_rounded, color: Colors.amber, size: 24),
            onPressed: _pickAndSendPhoto,
          ),

          // Message Text Input (Auto-expanding up to 3 lines)
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              onChanged: (val) {
                final hasText = val.trim().isNotEmpty;
                if (hasText != _hasTextInput) {
                  setState(() {
                    _hasTextInput = hasText;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: _editingMessageId != null ? 'Mesajı düzenleyin...' : 'Aile odasına mesaj yazın...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),

          // Voice Record Button (hidden when typing or editing)
          if (!_hasTextInput && _editingMessageId == null)
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecordingAndSend(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),

          const SizedBox(width: 4),

          // Send / Update Button
          IconButton(
            icon: Icon(
              _editingMessageId != null ? Icons.check_circle_rounded : Icons.send_rounded,
              color: const Color(0xFF00E676),
              size: 24,
            ),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}
