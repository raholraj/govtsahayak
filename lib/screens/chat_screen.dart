import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/message.dart';
import '../models/service_info.dart';
import '../services/ai_service.dart';
import '../services/knowledge_service.dart';
import '../services/storage_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Uuid _uuid = const Uuid();
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isLoading = false;
  bool _isListening = false;
  ServiceInfo? _currentService;
  final List<Map<String, String>> _history = [];
  Map<String, dynamic>? _lastExtracted;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await KnowledgeService.instance.load();
    final saved = await StorageService.instance.loadMessages();
    if (saved.isNotEmpty) {
      setState(() => _messages.addAll(saved));
      _scrollToBottom();
    } else {
      _addAssistant(
        'Namaste! 🙏 Main Sahayak hoon. Aadhaar sudhaarna hai, ration card, '
        'PM Awas Yojana, ya kuch aur sarkari kaam? Bas bol do, main madad '
        'karta hoon — aur haan, tera data tere phone se bahar kahin nahi '
        'jaata, ye promise hai.',
        quickReplies: [
          'PM Awas Yojana',
          'Aadhaar Update',
          'PAN Card',
          'DigiLocker',
          'Scholarship',
        ],
      );
    }
  }

  void _addAssistant(String text, {List<String>? quickReplies, bool isGuide = false}) {
    final msg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      text: text,
      quickReplies: quickReplies,
      isGuideStep: isGuide,
    );
    setState(() => _messages.add(msg));
    StorageService.instance.saveMessage(msg);
    _history.add({'role': 'assistant', 'content': text});
    _scrollToBottom();
  }

  void _addUser(String text, {String? imagePath}) {
    final msg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      text: text,
      imagePath: imagePath,
    );
    setState(() => _messages.add(msg));
    StorageService.instance.saveMessage(msg);
    _history.add({'role': 'user', 'content': text});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();
    _addUser(text);
    setState(() => _isLoading = true);

    try {
      final intent = await AiService.instance.classifyIntent(text);
      final serviceId = intent['service'] as String? ?? 'unknown';
      final confidence = (intent['confidence'] as num?)?.toDouble() ?? 0.0;

      if (serviceId != 'unknown' && confidence > 0.5) {
        final service = KnowledgeService.instance.byId(serviceId);
        if (service != null) {
          _currentService = service;
        }
      } else {
        final matched = KnowledgeService.instance.matchByKeywords(text);
        if (matched != null) _currentService = matched;
      }

      if (_currentService != null &&
          (text.toLowerCase().contains('apply') ||
              text.toLowerCase().contains('karna') ||
              text.toLowerCase().contains('chahiye') ||
              _messages.where((m) => m.role == MessageRole.user).length <= 2)) {
        final docs = _currentService!.docsRequired
            .map((d) => '• ${d.labelHi} (${d.label})')
            .join('\n');
        _addAssistant(
          'Theek hai! ${_currentService!.name} ke liye ye documents chahiye:\n\n'
          '$docs\n\n'
          'Photo bhejo ek ek karke (camera se le sakte ho). '
          'Main padh ke confirm karunga.',
          quickReplies: ['Camera se photo lo', 'Gallery se choose karo', 'Pehle steps batao'],
        );
      } else if (text.toLowerCase().contains('steps') ||
          text.toLowerCase().contains('guide') ||
          text.toLowerCase().contains('batao') ||
          text.toLowerCase().contains('kaise')) {
        if (_currentService != null) {
          final steps = _currentService!.guideSteps
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value}')
              .join('\n');
          _addAssistant(
            '${_currentService!.name} — step-by-step guide:\n\n$steps\n\n'
            'Portal: ${_currentService!.url}\n\n'
            'Ab documents ki photo bhejoge to main data extract karke guide karunga.',
            isGuide: true,
          );
        } else {
          final reply = await AiService.instance.chat(
            userMessage: text,
            history: _history,
          );
          _addAssistant(reply);
        }
      } else {
        final reply = await AiService.instance.chat(
          userMessage: text,
          history: _history,
        );
        _addAssistant(reply);
      }
    } catch (e) {
      _addAssistant(
        'Thoda technical issue aa gaya. Dobara try karo, ya seedha batao '
        'kaunsa kaam hai — main offline guide bhi de sakta hoon.',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final status = source == ImageSource.camera
        ? await Permission.camera.request()
        : await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      _addAssistant('Camera / Gallery permission chahiye. Settings se allow kar do.');
      return;
    }

    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;

    _addUser('📄 Document photo bheja', imagePath: file.path);
    setState(() => _isLoading = true);

    try {
      final bytes = await File(file.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final docType = _currentService?.docsRequired.isNotEmpty == true
          ? _currentService!.docsRequired.first.type
          : 'document';

      final extracted = await AiService.instance.extractDocument(
        docType: docType,
        imageBase64: b64,
      );
      _lastExtracted = extracted;

      final fields = extracted['fields'] as Map<String, dynamic>? ?? {};
      final conf = extracted['confidence'] as Map<String, dynamic>? ?? {};

      final buffer = StringBuffer('Maine ye padha:\n\n');
      fields.forEach((k, v) {
        final c = (conf[k] as num?)?.toDouble() ?? 0.0;
        final flag = c < 0.8 ? ' ⚠️ (confirm karo)' : '';
        buffer.writeln('📋 ${k.replaceAll('_', ' ').toUpperCase()}: $v$flag');
      });
      buffer.writeln('\nSab sahi hai kya?');

      await StorageService.instance.saveExtractedDoc(
        id: _uuid.v4(),
        docType: docType,
        fields: fields,
        confidence: conf,
      );

      _addAssistant(
        buffer.toString(),
        quickReplies: ['Haan, sahi hai', 'Kuch galat hai', 'Address type karke batao'],
      );
    } catch (e) {
      _addAssistant(
        'Photo clearly nahi padh paaya. Thoda better light mein phir se photo lo, '
        'ya important fields type karke bata do.',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleListen() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (_) => setState(() => _isListening = false),
    );
    if (!available) {
      _addAssistant('Speech recognition is device pe available nahi hai.');
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _controller.text = result.recognizedWords;
          setState(() => _isListening = false);
        }
      },
      localeId: 'hi_IN',
    );
  }

  void _onQuickReply(String text) {
    if (text.contains('Camera')) {
      _pickImage(ImageSource.camera);
    } else if (text.contains('Gallery')) {
      _pickImage(ImageSource.gallery);
    } else if (text.contains('steps') || text.contains('Steps') || text.contains('batao')) {
      _sendText('steps batao');
    } else {
      _sendText(text);
    }
  }

  Future<void> _showMoreOptions() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Chat history clear karo'),
              onTap: () async {
                Navigator.pop(ctx);
                await StorageService.instance.clearChatHistory();
                setState(() {
                  _messages.clear();
                  _history.clear();
                  _currentService = null;
                });
                _addAssistant(
                  'Chat clear ho gaya. Naya kaam batao!',
                  quickReplies: [
                    'PM Awas Yojana',
                    'Aadhaar Update',
                    'PAN Card',
                    'DigiLocker',
                    'Scholarship',
                  ],
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Saara data wipe karo (secure)'),
              onTap: () async {
                Navigator.pop(ctx);
                await StorageService.instance.wipeAllData();
                setState(() {
                  _messages.clear();
                  _history.clear();
                  _currentService = null;
                  _lastExtracted = null;
                });
                _addAssistant('Sab local data delete ho gaya. Privacy safe hai.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Privacy note'),
              subtitle: const Text(
                'Ye app sirf guide/assist karta hai. Final submit user ki responsibility hai. '
                'Data sirf is phone pe rehta hai.',
              ),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GovtSahayak', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Sahayak • Tera data phone pe hi rehta hai',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text(
              '⚠️ Ye app sirf guide karta hai. Final submit aapki zimmedari hai.',
              style: TextStyle(fontSize: 11, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return const TypingIndicator();
                }
                final msg = _messages[index];
                return MessageBubble(
                  message: msg,
                  onQuickReply: _onQuickReply,
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF1565C0)),
            onPressed: () => _pickImage(ImageSource.camera),
            tooltip: 'Camera',
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, color: Color(0xFF1565C0)),
            onPressed: () => _pickImage(ImageSource.gallery),
            tooltip: 'Gallery',
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Hinglish mein likho ya bolo...',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: _sendText,
              maxLines: 4,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: _isListening ? Colors.red : const Color(0xFF1565C0),
            ),
            onPressed: _toggleListen,
            tooltip: 'Voice',
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: Color(0xFF1565C0)),
            onPressed: () => _sendText(_controller.text),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }
}
