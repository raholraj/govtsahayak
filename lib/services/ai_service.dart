import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Fallback chain: OpenRouter → Groq → Mistral → offline
/// Keys via --dart-define / GitHub Secrets (never hardcode).
class AiService {
  static final AiService instance = AiService._();
  AiService._();

  static const String _openRouterKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );
  static const String _groqKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
  static const String _mistralKey = String.fromEnvironment(
    'MISTRAL_API_KEY',
    defaultValue: '',
  );

  static const String _openRouterModel = 'openai/gpt-oss-20b:free';
  static const String _openRouterVisionModel = 'google/gemma-4-26b-a4b-it:free';

  static const String _systemPrompt = '''
Tu "Sahayak" hai — ek dost jaisa AI jo sarkari kaam mein madad karta hai.

RULES:
1. Hamesha Hinglish mein baat kar, jab tak user pure Hindi/English na maange.
2. Kabhi bhi jaldi mat kar — pehle poochh, phir kaam kar.
3. User ka koi bhi data (Aadhaar, bank, mobile) kabhi bhi apne aap assume ya guess mat kar — hamesha confirm kar.
4. Har step pe user ko batao ki "ab main kya kar raha hoon".
5. Submit se pehle HAMESHA poora preview dikha aur explicit "HAAN" suno.
6. Agar kuch samajh na aaye ya confidence kam ho, guess mat kar — seedha poochh le user se.
7. Tu kabhi bhi "main ye kar dunga" nahi bolega bina user ko dikhaye ki kya karne wala hai.
8. Tone: dosti wali, lekin professional.
9. Guided / Semi-auto mode mein ho — form khud mat submit karo.
10. Short, clear replies rakho.
''';

  Future<String> chat({
    required String userMessage,
    List<Map<String, String>> history = const [],
    bool needsVision = false,
    String? imageBase64,
  }) async {
    final prompt = '''
$_systemPrompt

Conversation so far:
${history.map((m) => '${m['role']}: ${m['content']}').join('\n')}

User: $userMessage

Sahayak:
''';

    if (needsVision && imageBase64 != null) {
      return _callWithVision(prompt, imageBase64);
    }

    try {
      return await _callOpenRouter(prompt);
    } catch (e) {
      debugPrint('OpenRouter failed: $e');
      try {
        return await _callGroq(prompt);
      } catch (e2) {
        debugPrint('Groq failed: $e2');
        try {
          return await _callMistral(prompt);
        } catch (e3) {
          debugPrint('Mistral failed: $e3');
          return _offlineFallback(userMessage);
        }
      }
    }
  }

  Future<Map<String, dynamic>> classifyIntent(String userInput) async {
    final prompt = '''
User ne kaha: "$userInput"

Sirf JSON return karo, kuch aur nahi:
{
  "service": "<service_id from: pm_awas_yojana, aadhaar_update, pan_card, digilocker, scholarship_nsp, unknown>",
  "action": "apply_new | check_status | correction | general_help",
  "confidence": 0.0-1.0,
  "clarification_needed": true/false
}
''';
    try {
      final raw = await _callOpenRouter(prompt, jsonMode: true);
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      try {
        final raw = await _callGroq(prompt);
        final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
        return jsonDecode(cleaned) as Map<String, dynamic>;
      } catch (_) {
        return {
          'service': 'unknown',
          'action': 'general_help',
          'confidence': 0.3,
          'clarification_needed': true,
        };
      }
    }
  }

  Future<Map<String, dynamic>> extractDocument({
    required String docType,
    required String imageBase64,
  }) async {
    final prompt = '''
Ye $docType ka image hai. Extract karo aur SIRF JSON do:
{
  "fields": {
    "name": "...",
    "dob": "...",
    "aadhaar_number": "...",
    "address": "...",
    "other_relevant": "..."
  },
  "confidence": {
    "name": 0.0-1.0,
    "dob": 0.0-1.0,
    "aadhaar_number": 0.0-1.0,
    "address": 0.0-1.0
  }
}
Agar field clearly visible nahi hai to "UNCLEAR" likho — kabhi guess mat karo.
Sirf JSON return karo.
''';
    try {
      final raw = await _callWithVision(prompt, imageBase64);
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Extract failed: $e');
      return {
        'fields': {'error': 'Could not read document clearly. Fields type karke bata do.'},
        'confidence': {},
      };
    }
  }

  Future<String> _callOpenRouter(String prompt, {bool jsonMode = false}) async {
    if (_openRouterKey.isEmpty) throw Exception('OPENROUTER_API_KEY not set');
    final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
    final body = {
      'model': _openRouterModel,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.4,
      'max_tokens': 1024,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };
    final res = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_openRouterKey',
            'HTTP-Referer': 'https://github.com/raholraj/govtsahayak',
            'X-Title': 'GovtSahayak',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) {
      throw Exception('OpenRouter ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body);
    return data['choices'][0]['message']['content'] as String;
  }

  Future<String> _callWithVision(String prompt, String imageBase64) async {
    if (_openRouterKey.isNotEmpty) {
      try {
        final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
        final body = {
          'model': _openRouterVisionModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$imageBase64',
                  },
                },
              ],
            },
          ],
          'temperature': 0.2,
          'max_tokens': 1024,
        };
        final res = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_openRouterKey',
                'HTTP-Referer': 'https://github.com/raholraj/govtsahayak',
                'X-Title': 'GovtSahayak',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 50));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return data['choices'][0]['message']['content'] as String;
        }
        debugPrint('OpenRouter vision ${res.statusCode}');
      } catch (e) {
        debugPrint('OpenRouter vision failed: $e');
      }
    }
    throw Exception('Vision extraction unavailable');
  }

  Future<String> _callGroq(String prompt) async {
    if (_groqKey.isEmpty) throw Exception('GROQ_API_KEY not set');
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final body = {
      'model': 'llama-3.3-70b-versatile',
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.4,
      'max_tokens': 1024,
    };
    final res = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_groqKey',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Groq ${res.statusCode}');
    final data = jsonDecode(res.body);
    return data['choices'][0]['message']['content'] as String;
  }

  Future<String> _callMistral(String prompt) async {
    if (_mistralKey.isEmpty) throw Exception('MISTRAL_API_KEY not set');
    final url = Uri.parse('https://api.mistral.ai/v1/chat/completions');
    final body = {
      'model': 'mistral-small-latest',
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.4,
      'max_tokens': 1024,
    };
    final res = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_mistralKey',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Mistral ${res.statusCode}');
    final data = jsonDecode(res.body);
    return data['choices'][0]['message']['content'] as String;
  }

  String _offlineFallback(String userMessage) {
    final lower = userMessage.toLowerCase();
    if (lower.contains('awas') || lower.contains('housing') || lower.contains('pmay')) {
      return 'Theek hai! PM Awas Yojana ke liye apply karna hai. '
          '3 documents chahiye: Aadhaar, Income Certificate, aur Bank Passbook. '
          'Photo bhejo ek ek karke, main guide karta hoon.';
    }
    if (lower.contains('aadhaar') || lower.contains('\u0906\u0927\u093e\u0930')) {
      return 'Aadhaar update/correction ke liye myAadhaar portal use hota hai. '
          'Kaunsi detail change karni hai? (naam, address, DOB, mobile?)';
    }
    if (lower.contains('pan')) {
      return 'PAN card ke liye NSDL/UTIITSL portal hai. Naya PAN chahiye ya correction?';
    }
    return 'Samajh gaya. Thoda aur detail batao — kaunsa sarkari kaam hai? '
        'Jaise Awas Yojana, Aadhaar, PAN, Scholarship, DigiLocker...';
  }
}
