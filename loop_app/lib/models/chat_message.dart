/// Poruka između dva korisnika (npr. kupac pita prodavatelja o predmetu).
/// Razgovor čine sve poruke istog para korisnika ([conversationId]).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
    this.deviceId,
    this.read = false,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String text;

  /// Predmet o kojem je poruka (prikazuje se kao kartica u razgovoru).
  final String? deviceId;
  final bool read;
  final DateTime createdAt;

  static const maxLength = 500;

  /// Isti ID za oba smjera: "a|b" (sortirano).
  static String conversationOf(String a, String b) =>
      a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  String get conversationId => conversationOf(senderId, receiverId);

  /// Drugi sudionik iz perspektive [userId].
  String otherThan(String userId) => senderId == userId ? receiverId : senderId;

  ChatMessage markRead() => ChatMessage(
    id: id,
    senderId: senderId,
    receiverId: receiverId,
    text: text,
    createdAt: createdAt,
    deviceId: deviceId,
    read: true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'senderId': senderId,
    'receiverId': receiverId,
    'text': text,
    'deviceId': deviceId,
    'read': read,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ChatMessage.fromMap(Map<dynamic, dynamic> m) => ChatMessage(
    id: m['id'] as String,
    senderId: m['senderId'] as String,
    receiverId: m['receiverId'] as String,
    text: m['text'] as String? ?? '',
    deviceId: m['deviceId'] as String?,
    read: m['read'] as bool? ?? false,
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}
