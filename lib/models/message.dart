enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String text;
  final DateTime timestamp;
  final String? imagePath;
  final Map<String, dynamic>? extractedData;
  final bool isGuideStep;
  final List<String>? quickReplies;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.imagePath,
    this.extractedData,
    this.isGuideStep = false,
    this.quickReplies,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'imagePath': imagePath,
        'extractedData': extractedData,
        'isGuideStep': isGuideStep,
        'quickReplies': quickReplies,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        role: MessageRole.values.byName(json['role']),
        text: json['text'],
        timestamp: DateTime.parse(json['timestamp']),
        imagePath: json['imagePath'],
        extractedData: json['extractedData'] != null
            ? Map<String, dynamic>.from(json['extractedData'])
            : null,
        isGuideStep: json['isGuideStep'] ?? false,
        quickReplies: json['quickReplies'] != null
            ? List<String>.from(json['quickReplies'])
            : null,
      );
}
