import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/message.dart';
import '../models/service_info.dart';
import '../services/ai_service.dart';
import '../services/knowledge_service.dart';
import '../services/storage_service.dart';
import '../services/agent_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import 'summary_screen.dart';

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
  String? _agentSessionId;
  String? _agentNeedsInput;

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
        'Namaste! Main Sahayak hoon. Aadhaar, PM Awas, PAN, Scholarship — bas bol do. Data phone pe hi rehta hai.',
        quickReplies: ['PM Awas Yojana', 'Aadhaar Update', 'PAN Card', 'DigiLocker', 'Scholarship'],
      );
    }
  }

  void _addAssistant(String text, {List<String>? quickReplies, bool isGuide = false}) {
    final msg = ChatMessage(id: _uuid.v4(), role: MessageRole.assistant, text: text, quickReplies: quickReplies, isGuideStep: isGuide);
    setState(() => _messages.add(msg));
    StorageService.instance.saveMessage(msg);
    _history.add({'role': 'assistant', 'content': text});
    _scrollToBottom();
  }

  void _addUser(String text, {String? imagePath}) {
    final msg = ChatMessage(id: _uuid.v4(), role: MessageRole.user, text: text, imagePath: imagePath);
    setState(() => _messages.add(msg));
    StorageService.instance.saveMessage(msg);
    _history.add({'role': 'user', 'content': text});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
        if (service != null) _currentService = service;
      } else {
        final matched = KnowledgeService.instance.matchByKeywords(text);
        if (matched != null) _currentService = matched;
      }
      if (_currentService != null && (text.toLowerCase().contains('apply') || text.toLowerCase().contains('karna') || text.toLowerCase().contains('chahiye') || _messages.where((m) => m.role == MessageRole.user).length <= 2)) {
        final docs = _currentService!.docsRequired.map((d) => '• ${d.labelHi}').join('\n');
        _addAssistant('Theek hai! ${_currentService!.name} ke liye:\n$docs\n\nPhoto bhejo.', quickReplies: ['Camera se photo lo', 'Gallery se choose karo', 'Pehle steps batao']);
      } else if (text.toLowerCase().contains('steps') || text.toLowerCase().contains('guide') || text.toLowerCase().contains('batao')) {
        if (_currentService != null) {
          final steps = _currentService!.guideSteps.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
          _addAssistant('${_currentService!.name}:\n$steps\n\nPortal: ${_currentService!.url}', isGuide: true);
        } else {
          _addAssistant(await AiService.instance.chat(userMessage: text, history: _history));
        }
      } else {
        _addAssistant(await AiService.instance.chat(userMessage: text, history: _history));
      }
    } catch (e) {
      _addAssistant('Technical issue. Dobara try karo ya offline guide maango.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final status = source == ImageSource.camera ? await Permission.camera.request() : await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      _addAssistant('Camera/Gallery permission chahiye.');
      return;
    }
    final file = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    _addUser('Document photo', imagePath: file.path);
    setState(() => _isLoading = true);
    try {
      final bytes = await File(file.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final docType = _currentService?.docsRequired.isNotEmpty == true ? _currentService!.docsRequired.first.type : 'document';
      final extracted = await AiService.instance.extractDocument(docType: docType, imageBase64: b64);
      _lastExtracted = extracted;
      final fields = extracted['fields'] as Map<String, dynamic>? ?? {};
      final conf = extracted['confidence'] as Map<String, dynamic>? ?? {};
      final buffer = StringBuffer('Maine ye padha:\n\n');
      fields.forEach((k, v) {
        final c = (conf[k] as num?)?.toDouble() ?? 0.0;
        buffer.writeln('${k.toUpperCase()}: $v${c < 0.8 ? ' (confirm)' : ''}');
      });
      buffer.writeln('\nSab sahi hai kya?');
      await StorageService.instance.saveExtractedDoc(id: _uuid.v4(), docType: docType, fields: fields, confidence: conf);
      _addAssistant(buffer.toString(), quickReplies: ['Haan, sahi hai', 'Kuch galat hai']);
    } catch (e) {
      _addAssistant('Photo clearly nahi padhi. Phir se try karo ya type karke batao.');
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
    final available = await _speech.initialize(onStatus: (s) {
      if (s == 'done' || s == 'notListening') setState(() => _isListening = false);
    }, onError: (_) => setState(() => _isListening = false));
    if (!available) {
      _addAssistant('Speech available nahi hai.');
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(onResult: (result) {
      if (result.finalResult) {
        _controller.text = result.recognizedWords;
        setState(() => _isListening = false);
      }
    }, listenOptions: stt.SpeechListenOptions(localeId: 'hi_IN'));
  }

  void _onQuickReply(String text) {
    if (text.contains('Camera')) {
      _pickImage(ImageSource.camera);
    } else if (text.contains('Gallery')) {
      _pickImage(ImageSource.gallery);
    } else if (text.contains('steps') || text.contains('batao')) {
      _sendText('steps batao');
    } else if (text.toLowerCase().contains('haan') || text.toLowerCase().contains('sahi hai')) {
      if (_lastExtracted != null && _currentService != null) {
        final fields = Map<String, dynamic>.from((_lastExtracted!['fields'] as Map?) ?? {});
        if (fields.isNotEmpty && !fields.containsKey('error')) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => SummaryScreen(service: _currentService!, fields: fields)));
          _addAssistant('Summary khol diya. Copy-paste + PDF available.', quickReplies: ['Full Agent se bharo', 'Steps batao', 'Naya kaam']);
          return;
        }
      }
      _sendText(text);
    } else if (text.toLowerCase().contains('full agent') || text.toLowerCase().contains('agent se')) {
      _startFullAgent();
    } else if (_agentNeedsInput != null && (text.toUpperCase() == 'HAAN' || RegExp(r'^\d{4,8}$').hasMatch(text.trim()))) {
      _sendAgentInput(text.trim());
    } else {
      _sendText(text);
    }
  }

  Future<void> _startFullAgent() async {
    if (_currentService == null) {
      _addAssistant('Pehle service choose karo.');
      return;
    }
    final fields = Map<String, dynamic>.from((_lastExtracted?['fields'] as Map?) ?? {});
    if (fields.isEmpty || fields.containsKey('error')) {
      _addAssistant('Pehle document extract + confirm karo.');
      return;
    }
    setState(() => _isLoading = true);
    _addAssistant('Portal check...');
    final health = await AgentService.instance.portalCheck(_currentService!.url);
    if (health['live'] != true) {
      setState(() => _isLoading = false);
      _addAssistant('Portal down / backend offline. Guided mode use karo.', quickReplies: ['Steps batao']);
      return;
    }
    final session = await AgentService.instance.startSession(serviceId: _currentService!.id, fields: fields, portalUrl: _currentService!.url);
    if (session == null) {
      setState(() => _isLoading = false);
      _addAssistant('Agent backend nahi mila. Guided mode use karo.');
      return;
    }
    _agentSessionId = session['session_id'] as String?;
    final fill = await AgentService.instance.startFill(_agentSessionId!);
    setState(() => _isLoading = false);
    if (fill == null) {
      _addAssistant('Fill fail. Guided mode try karo.');
      return;
    }
    _agentNeedsInput = fill['needs_input'] as String?;
    final msg = fill['message'] as String? ?? 'Agent update';
    final replies = <String>[];
    if (_agentNeedsInput == 'confirm') replies.addAll(['HAAN', 'NAHI']);
    if (_agentNeedsInput == 'otp') replies.add('OTP type karo');
    _addAssistant('$msg\nSubmit sirf HAAN pe hoga.', quickReplies: replies.isEmpty ? null : replies);
  }

  Future<void> _sendAgentInput(String value) async {
    if (_agentSessionId == null || _agentNeedsInput == null) {
      _sendText(value);
      return;
    }
    setState(() => _isLoading = true);
    var type = _agentNeedsInput!;
    if (value.toUpperCase().contains('HAAN')) type = 'confirm';
    else if (RegExp(r'^\d{4,8}$').hasMatch(value)) type = 'otp';
    final res = await AgentService.instance.sendInput(sessionId: _agentSessionId!, inputType: type, value: value);
    setState(() => _isLoading = false);
    if (res == null) {
      _addAssistant('Agent input fail.');
      return;
    }
    _agentNeedsInput = res['needs_input'] as String?;
    final status = res['status'] as String? ?? '';
    final msg = res['message'] as String? ?? '';
    if (status == 'submitted') {
      _addAssistant('Done. $msg', quickReplies: ['Naya kaam']);
      _agentSessionId = null;
      _agentNeedsInput = null;
    } else {
      _addAssistant(msg, quickReplies: _agentNeedsInput == 'confirm' ? ['HAAN', 'NAHI'] : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('GovtSahayak', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('Data phone pe hi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
        ]),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: Colors.amber.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: const Text('App sirf guide karta hai. Final submit aapki zimmedari.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _messages.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (_isLoading && index == _messages.length) return const TypingIndicator();
              return MessageBubble(message: _messages[index], onQuickReply: _onQuickReply);
            },
          ),
        ),
        _buildInputBar(),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      color: Colors.white,
      child: Row(children: [
        IconButton(icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF1565C0)), onPressed: () => _pickImage(ImageSource.camera)),
        IconButton(icon: const Icon(Icons.photo_library_outlined, color: Color(0xFF1565C0)), onPressed: () => _pickImage(ImageSource.gallery)),
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(hintText: 'Hinglish...', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            onSubmitted: _sendText,
            maxLines: 3,
            minLines: 1,
          ),
        ),
        IconButton(icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.red : const Color(0xFF1565C0)), onPressed: _toggleListen),
        IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFF1565C0)), onPressed: () => _sendText(_controller.text)),
      ]),
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
