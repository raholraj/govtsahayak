import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Local PDF receipt / form summary generator (Phase 2).
/// No server — file phone pe hi banta hai.
class PdfService {
  static final PdfService instance = PdfService._();
  PdfService._();

  Future<File?> generateSummaryPdf({
    required String serviceName,
    required Map<String, dynamic> fields,
    String? referenceNote,
    List<String>? guideSteps,
  }) async {
    try {
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'GovtSahayak — Application Summary',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Service: $serviceName',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Generated: ${DateTime.now().toString().substring(0, 19)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Extracted / Prepared Fields',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Field', 'Value'],
              data: fields.entries
                  .map((e) => [e.key.replaceAll('_', ' ').toUpperCase(), '${e.value}'])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(color: PdfColors.grey400),
            ),
            if (guideSteps != null && guideSteps.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text(
                'Step-by-step Guide',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              ...guideSteps.asMap().entries.map(
                    (e) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('${e.key + 1}. ${e.value}', style: const pw.TextStyle(fontSize: 10)),
                    ),
                  ),
            ],
            if (referenceNote != null) ...[
              pw.SizedBox(height: 16),
              pw.Text(referenceNote, style: const pw.TextStyle(fontSize: 10)),
            ],
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.orange),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'Disclaimer: Ye app sirf guide/assist karta hai. Final submit aapki zimmedari hai. '
                'Data is phone pe generate hua hai — kisi server pe nahi bheja gaya.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
            ),
          ],
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'govtsahayak_${serviceName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await doc.save());
      debugPrint('PDF saved: ${file.path}');
      return file;
    } catch (e) {
      debugPrint('PDF generate error: $e');
      return null;
    }
  }

  Future<void> sharePdf(File file) async {
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: file.path.split('/').last,
    );
  }
}
