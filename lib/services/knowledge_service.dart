import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/service_info.dart';

class KnowledgeService {
  static final KnowledgeService instance = KnowledgeService._();
  KnowledgeService._();
  List<ServiceInfo> _services = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/knowledge_base.json');
    final list = jsonDecode(raw) as List;
    _services = list.map((e) => ServiceInfo.fromJson(e as Map<String, dynamic>)).toList();
    _loaded = true;
  }

  ServiceInfo? byId(String id) {
    try {
      return _services.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  ServiceInfo? matchByKeywords(String text) {
    final lower = text.toLowerCase();
    for (final s in _services) {
      if (lower.contains(s.id.replaceAll('_', ' ')) ||
          lower.contains(s.name.toLowerCase()) ||
          (s.id == 'pm_awas_yojana' && (lower.contains('awas') || lower.contains('pmay'))) ||
          (s.id == 'aadhaar_update' && lower.contains('aadhaar')) ||
          (s.id == 'pan_card' && lower.contains('pan')) ||
          (s.id == 'digilocker' && lower.contains('digilocker')) ||
          (s.id == 'scholarship_nsp' && (lower.contains('scholarship') || lower.contains('nsp')))) {
        return s;
      }
    }
    return null;
  }
}
