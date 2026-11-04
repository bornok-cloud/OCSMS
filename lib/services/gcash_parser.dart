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
  /// Scans the uploaded or photographed payment receipt (GCash, GoTyme, Maya, or any e-bank)
  /// and extracts exact Amount, Reference ID, and Date/Time using OCR.
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

        // 2. Extract Exact Amount FIRST so we can exclude it from reference number
        final amountRegex = RegExp(
          r'(?:Total\s*Amount\s*Sent|Total\s*Amount|Amount\s*Sent|Amount|Total|Paid|PHP|₱)\s*[:#]?\s*(?:PHP|₱)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})',
          caseSensitive: false,
        );
        final amountMatches = amountRegex.allMatches(fullText);
        for (final match in amountMatches) {
          final cleanStr = (match.group(1) ?? '').replaceAll(',', '');
          final val = double.tryParse(cleanStr);
          if (val != null && val > 0) {
            extractedAmount = val;
            break;
          }
        }

        if (extractedAmount == null) {
          final moneyRegex = RegExp(r'\b([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})\b');
          final moneyMatches = moneyRegex.allMatches(fullText);
          double maxVal = 0.0;
          for (final m in moneyMatches) {
            final cleanStr = (m.group(1) ?? '').replaceAll(',', '');
            final v = double.tryParse(cleanStr) ?? 0.0;
            if (v > maxVal) {
              maxVal = v;
            }
          }
          if (maxVal > 0) {
            extractedAmount = maxVal;
          }
        }

        // --- ULTRA-ROBUST REFERENCE NUMBER EXTRACTION ---
        // Step 1: Scan line by line for explicit labels ("ref", "reference", "trace", "trans", "receipt")
        final lines = fullText.split('\n');
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lowerLine = line.toLowerCase();
          if (lowerLine.contains('ref') ||
              lowerLine.contains('reference') ||
              lowerLine.contains('trace') ||
              lowerLine.contains('transaction') ||
              lowerLine.contains('trans') ||
              lowerLine.contains('receipt')) {
            // Extract digit sequences (allowing spaces or hyphens between digits)
            final digitMatches = RegExp(r'([0-9][0-9\s\-]{8,20}[0-9])').allMatches(line);
            for (final m in digitMatches) {
              final cleaned = m.group(1)!.replaceAll(RegExp(r'[\s\-]+'), '');
              if (cleaned.length >= 10 && cleaned.length <= 15 && !cleaned.startsWith('09') && !cleaned.startsWith('639')) {
                extractedRef = cleaned;
                break;
              }
            }
            if (extractedRef != null) break;

            // If label is on line i but value is on line i+1
            if (i + 1 < lines.length) {
              final nextLine = lines[i + 1];
              final nextDigitMatches = RegExp(r'([0-9][0-9\s\-]{8,20}[0-9])').allMatches(nextLine);
              for (final m in nextDigitMatches) {
                final cleaned = m.group(1)!.replaceAll(RegExp(r'[\s\-]+'), '');
                if (cleaned.length >= 10 && cleaned.length <= 15 && !cleaned.startsWith('09') && !cleaned.startsWith('639')) {
                  extractedRef = cleaned;
                  break;
                }
              }
              if (extractedRef != null) break;
            }
          }
        }

        // Step 2: Search fullText with aggressive label regex
        if (extractedRef == null || extractedRef.isEmpty) {
          final aggressiveRefRegex = RegExp(
            r'(?:ref\.?\s*no\.?|reference\s*no\.?|reference|ref|trace|transaction|trans|receipt)\D*([0-9][0-9\s\-]{8,20}[0-9])',
            caseSensitive: false,
          );
          final aggressiveMatch = aggressiveRefRegex.firstMatch(fullText);
          if (aggressiveMatch != null) {
            final cand = aggressiveMatch.group(1)!.replaceAll(RegExp(r'[\s\-]+'), '');
            if (cand.length >= 10 && cand.length <= 15 && !cand.startsWith('09') && !cand.startsWith('639')) {
              extractedRef = cand;
            }
          }
        }

        // Step 3: Search cleanText (all whitespace/hyphens removed) for any 10-15 digit sequence
        if (extractedRef == null || extractedRef.isEmpty) {
          final cleanText = fullText.replaceAll(RegExp(r'[\s\-]+'), '');
          final allNumbers = RegExp(r'\b([0-9]{10,15})\b').allMatches(cleanText);
          for (final m in allNumbers) {
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
        final dateRegex = RegExp(
          r'([0-9]{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+[0-9]{4}(?:\s+(?:at|@|-)\s+[0-9]{1,2}:[0-9]{2}\s*[AP]M)?)',
          caseSensitive: false,
        );
        final dateMatch = dateRegex.firstMatch(fullText);
        if (dateMatch != null) {
          extractedDateTime = dateMatch.group(1);
        } else {
          final altDateRegex = RegExp(
            r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+[0-9]{1,2},?\s+[0-9]{4}(?:\s+[0-9]{1,2}:[0-9]{2}\s*[AP]M)?)',
            caseSensitive: false,
          );
          final altDateMatch = altDateRegex.firstMatch(fullText);
          if (altDateMatch != null) {
            extractedDateTime = altDateMatch.group(1);
          } else {
            final numDateRegex = RegExp(r'([0-9]{1,4}[-/][0-9]{1,2}[-/][0-9]{1,4}(?:\s+[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)?)');
            final numDateMatch = numDateRegex.firstMatch(fullText);
            if (numDateMatch != null) {
              extractedDateTime = numDateMatch.group(1);
            }
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
