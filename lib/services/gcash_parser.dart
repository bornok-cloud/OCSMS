import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

class GcashReceiptDetails {
  final double? amount;
  final String? referenceId;
  final String? dateTime;
  final bool isValid;

  const GcashReceiptDetails({
    this.amount,
    this.referenceId,
    this.dateTime,
    this.isValid = true,
  });
}

class GcashReceiptParser {
  /// Scans the uploaded receipt image and extracts the exact Amount, Reference Number, and Date/Time from the receipt using OCR.
  static Future<GcashReceiptDetails> extractDetails(Uint8List imageBytes) async {
    double? extractedAmount;
    String? extractedRef;
    String? extractedDateTime;

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(imageBytes);

        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final inputImage = InputImage.fromFilePath(tempFile.path);
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
        await textRecognizer.close();

        final fullText = recognizedText.text;
        debugPrint("--- RECEIPT OCR TEXT START ---\n$fullText\n--- RECEIPT OCR TEXT END ---");

        final lines = fullText.split('\n');

        // 1. Extract Amount
        final amountRegex = RegExp(
          r'(?:Total\s*Amount\s*Sent|Total\s*Amount|Amount\s*Sent|Amount|Total|Paid|PHP|₱)\s*[:#]?\s*(?:PHP|₱)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})',
          caseSensitive: false,
        );
        for (final match in amountRegex.allMatches(fullText)) {
          final cleanStr = (match.group(1) ?? '').replaceAll(',', '');
          final val = double.tryParse(cleanStr);
          if (val != null && val > 0) {
            extractedAmount = val;
            break;
          }
        }
        if (extractedAmount == null) {
          final moneyRegex = RegExp(r'\b([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})\b');
          double maxVal = 0.0;
          for (final m in moneyRegex.allMatches(fullText)) {
            final v = double.tryParse((m.group(1) ?? '').replaceAll(',', '')) ?? 0.0;
            if (v > maxVal) maxVal = v;
          }
          if (maxVal > 0) extractedAmount = maxVal;
        }

        // 2. Extract Reference Number (10 to 15 digits, excluding phone numbers)
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lower = line.toLowerCase();
          if (lower.contains('ref') || lower.contains('reference') || lower.contains('trace') || lower.contains('trans') || lower.contains('no.')) {
            for (int checkIdx = i; checkIdx <= i + 1 && checkIdx < lines.length; checkIdx++) {
              final checkLine = lines[checkIdx];
              final matches = RegExp(r'([0-9][0-9\s\-]{8,15}[0-9])').allMatches(checkLine);
              for (final m in matches) {
                final cleaned = m.group(1)!.replaceAll(RegExp(r'[\s\-]+'), '');
                if (cleaned.length >= 10 && cleaned.length <= 15 && !cleaned.startsWith('09') && !cleaned.startsWith('639')) {
                  extractedRef = cleaned;
                  break;
                }
              }
              if (extractedRef != null) break;
            }
          }
          if (extractedRef != null) break;
        }

        if (extractedRef == null || extractedRef.isEmpty) {
          final cleanText = fullText.replaceAll(RegExp(r'[\s\-]+'), '');
          final allNumMatches = RegExp(r'\b([0-9]{10,15})\b').allMatches(cleanText);
          for (final m in allNumMatches) {
            final cand = m.group(1)!;
            if (cand.startsWith('09') || cand.startsWith('639')) continue;
            if (extractedAmount != null) {
              final amtInt = (extractedAmount * 100).toInt().toString();
              if (cand == amtInt || cand.contains(amtInt)) continue;
            }
            extractedRef = cand;
            break;
          }
        }

        // 3. Extract Date and Time
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lower = line.toLowerCase();
          if (lower.contains('jan') || lower.contains('feb') || lower.contains('mar') || 
              lower.contains('apr') || lower.contains('may') || lower.contains('jun') || 
              lower.contains('jul') || lower.contains('aug') || lower.contains('sep') || 
              lower.contains('oct') || lower.contains('nov') || lower.contains('dec') ||
              RegExp(r'[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{2,4}').hasMatch(line)) {
            extractedDateTime = line.trim();
            if (i + 1 < lines.length && (lines[i+1].contains(':') || lines[i+1].toLowerCase().contains('am') || lines[i+1].toLowerCase().contains('pm'))) {
              extractedDateTime = '${line.trim()} ${lines[i+1].trim()}';
            }
            break;
          }
        }

        if (extractedDateTime == null || extractedDateTime.isEmpty) {
          final dateRegex = RegExp(
            r'([0-9]{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+[0-9]{4}(?:\s+(?:at|@|-)?\s*[0-9]{1,2}:[0-9]{2}\s*[AP]M)?)',
            caseSensitive: false,
          );
          final match = dateRegex.firstMatch(fullText);
          if (match != null) {
            extractedDateTime = match.group(1);
          }
        }
      }
    } catch (e) {
      debugPrint("Error extracting receipt via OCR: $e");
    }

    return GcashReceiptDetails(
      amount: extractedAmount,
      referenceId: extractedRef,
      dateTime: extractedDateTime,
      isValid: true,
    );
  }
}
