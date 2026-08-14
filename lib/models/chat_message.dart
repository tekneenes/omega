enum MessageType { text, photo, voice, file }

class ChatMessage {
  final String id;
  final String senderId;
  final String? senderName;
  final String receiverId;
  final String text;
  final MessageType type;
  final String? mediaUrl;
  final DateTime timestamp;
  final bool isDelivered;
  final bool isRead;
  final bool isEdited;
  final bool isDeleted;

  ChatMessage({
    required this.id,
    required this.senderId,
    this.senderName,
    required this.receiverId,
    required this.text,
    this.type = MessageType.text,
    this.mediaUrl,
    required this.timestamp,
    this.isDelivered = false,
    this.isRead = false,
    this.isEdited = false,
    this.isDeleted = false,
  });

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? receiverId,
    String? text,
    MessageType? type,
    String? mediaUrl,
    DateTime? timestamp,
    bool? isDelivered,
    bool? isRead,
    bool? isEdited,
    bool? isDeleted,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      timestamp: timestamp ?? this.timestamp,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'type': type.name,
      'mediaUrl': mediaUrl,
      'timestamp': timestamp.toIso8601String(),
      'isDelivered': isDelivered,
      'isRead': isRead,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'],
      receiverId: json['receiverId'] ?? '',
      text: json['text'] ?? '',
      type: MessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => MessageType.text,
      ),
      mediaUrl: json['mediaUrl'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      isDelivered: json['isDelivered'] ?? false,
      isRead: json['isRead'] ?? false,
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
    );
  }
}
