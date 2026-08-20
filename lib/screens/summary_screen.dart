import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pdf_service.dart';
import '../models/service_info.dart';

/// Phase 2 — Semi-Automatic: form data summary + copy-paste guidance + PDF.
class SummaryScreen extends StatefulWidget {
  final ServiceInfo service;
  final Map<String, dynamic> fields;
  final List<String>? portalFieldHints;

  const SummaryScreen({
    super.key,
    required this.service,
    required this.fields,
    this.portalFieldHints,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _generatingPdf = false;
  File? _pdfFile;

  Future<void> _copyField(String key, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"$key" copy ho gaya — portal pe paste kar lo'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _generatePdf() async {
    setState(() => _generatingPdf = true);
    final file = await PdfService.instance.generateSummaryPdf(
      serviceName: widget.service.name,
      fields: widget.fields,
      guideSteps: widget.service.guideSteps,
      referenceNote:
          'Portal: ${widget.service.url}\nYe summary local device pe bani hai.',
    );
    setState(() {
      _generatingPdf = false;
      _pdfFile = file;
    });
    if (file != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF ready — share / download kar sakte ho')),
      );
    }
  }

  Future<void> _sharePdf() async {
    if (_pdfFile == null) return;
    await PdfService.instance.sharePdf(_pdfFile!);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.fields.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF banao',
            onPressed: _generatingPdf ? null : _generatePdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.service.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Portal: ${widget.service.url}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Har field pe "Copy" dabao → portal mein paste karo. '
                  'Submit se pehle sab check kar lena.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = entries[index];
                final label = e.key.replaceAll('_', ' ').toUpperCase();
                final value = '${e.value}';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(
                    value,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy',
                    onPressed: () => _copyField(label, value),
                  ),
                  onTap: () => _copyField(label, value),
                );
              },
            ),
          ),
          if (widget.service.guideSteps.isNotEmpty)
            ExpansionTile(
              title: const Text('Portal steps (guide)', style: TextStyle(fontSize: 14)),
              children: widget.service.guideSteps
                  .asMap()
                  .entries
                  .map(
                    (e) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11)),
                      ),
                      title: Text(e.value, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                  .toList(),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _generatingPdf ? null : _generatePdf,
                      icon: _generatingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf),
                      label: Text(_pdfFile == null ? 'PDF banao' : 'PDF phir se banao'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_pdfFile != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _sharePdf,
                        icon: const Icon(Icons.share),
                        label: const Text('Share PDF'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
