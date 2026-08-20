import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Phase 3 — FastAPI + Playwright backend client.
class AgentService {
  static final AgentService instance = AgentService._();
  AgentService._();

  static const String _base = String.fromEnvironment(
    'AGENT_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  Uri _u(String path) => Uri.parse('$_base$path');

  Future<Map<String, dynamic>> portalCheck(String url) async {
    try {
      final res = await http
          .post(
            _u('/api/portal-check'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        return {'live': false, 'message': 'Health check fail (${res.statusCode})'};
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('portalCheck: $e');
      return {
        'live': false,
        'message': 'Backend unreachable. Guided mode use karo.',
      };
    }
  }

  Future<Map<String, dynamic>?> startSession({
    required String serviceId,
    required Map<String, dynamic> fields,
    String? portalUrl,
  }) async {
    try {
      final res = await http
          .post(
            _u('/api/session/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'service_id': serviceId,
              'fields': fields,
              if (portalUrl != null) 'portal_url': portalUrl,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('startSession: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> startFill(String sessionId) async {
    try {
      final res = await http
          .post(
            _u('/api/agent/fill/$sessionId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('startFill: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> sendInput({
    required String sessionId,
    required String inputType,
    required String value,
  }) async {
    try {
      final res = await http
          .post(
            _u('/api/agent/input'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'input_type': inputType,
              'value': value,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('sendInput: $e');
      return null;
    }
  }

  Future<void> endSession(String sessionId) async {
    try {
      await http.delete(_u('/api/session/$sessionId'));
    } catch (_) {}
  }
}
