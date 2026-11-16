import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../utils/file_download.dart';
import '../guest/guest_ordering_shell.dart';

class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  void _launchGuestInterface() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GuestOrderingShell(),
      ),
    );
  }

  Future<Uint8List> _generateBrandedQrImageBytes(QrImage qrImage) async {
    const width = 600.0;
    const height = 750.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // 1. Background
    final bgPaint = Paint()..color = const Color(0xFFFBF9F5); // AppColors.cream
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // 2. Card Container
    final cardRect = Rect.fromLTWH(40, 40, width - 80, height - 80);
    final cardPaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = const Color(0xFFD6CFC7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final rrect = RRect.fromRectAndRadius(cardRect, const Radius.circular(20));
    canvas.drawRRect(rrect, cardPaint);
    canvas.drawRRect(rrect, borderPaint);

    // 3. Header Text: OVERNIGHT CAFE
    final titleBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 22, fontWeight: FontWeight.w900),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFF2C221E)))
      ..addText('OVERNIGHT CAFE');
    final titleParagraph = titleBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width - 80));
    canvas.drawParagraph(titleParagraph, const Offset(40, 75));

    // 4. Badge: WALK-IN ORDERING
    const badgeWidth = 210.0;
    const badgeHeight = 32.0;
    final badgeRect = Rect.fromLTWH((width - badgeWidth) / 2, 115, badgeWidth, badgeHeight);
    final badgePaint = Paint()..color = Colors.black;
    canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(16)), badgePaint);

    final badgeBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 11.5, fontWeight: FontWeight.bold),
    )
      ..pushStyle(ui.TextStyle(color: Colors.white))
      ..addText('WALK-IN ORDERING');
    final badgeParagraph = badgeBuilder.build()
      ..layout(ui.ParagraphConstraints(width: badgeWidth));
    canvas.drawParagraph(badgeParagraph, Offset((width - badgeWidth) / 2, 123));

    // 5. QR Code Box Container
    const qrBoxSize = 360.0;
    final qrBoxLeft = (width - qrBoxSize) / 2;
    const qrBoxTop = 170.0;
    final qrBoxRect = Rect.fromLTWH(qrBoxLeft, qrBoxTop, qrBoxSize, qrBoxSize);

    final qrBgPaint = Paint()..color = Colors.white;
    final qrBorderPaint = Paint()
      ..color = const Color(0xFFD6CFC7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(RRect.fromRectAndRadius(qrBoxRect, const Radius.circular(14)), qrBgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(qrBoxRect, const Radius.circular(14)), qrBorderPaint);

    // Paint QR Modules inside QR Box (with 24px padding)
    const qrPadding = 24.0;
    final actualQrSize = qrBoxSize - (qrPadding * 2);
    canvas.save();
    canvas.translate(qrBoxLeft + qrPadding, qrBoxTop + qrPadding);

    final darkPaint = Paint()..color = Colors.black;
    final lightPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, actualQrSize, actualQrSize), lightPaint);

    final qrSize = qrImage.moduleCount;
    final cellWidth = actualQrSize / qrSize;
    final cellHeight = actualQrSize / qrSize;

    for (int x = 0; x < qrSize; x++) {
      for (int y = 0; y < qrSize; y++) {
        if (qrImage.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth + 0.5, cellHeight + 0.5),
            darkPaint,
          );
        }
      }
    }
    canvas.restore();

    // 6. Footer Instruction Text
    final footerBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 13, fontWeight: FontWeight.w700),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFF7A6E65)))
      ..addText('Scan to browse menu & order directly from phone');
    final footerParagraph = footerBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width - 120));
    canvas.drawParagraph(footerParagraph, Offset(60, qrBoxTop + qrBoxSize + 25));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static const String walkInQrUrl = 'https://overnightcafe-app.web.app/#/walk-in-order';

  Future<void> _downloadQrCode() async {
    try {
      final qrCode = QrCode(4, QrErrorCorrectLevel.L)..addData(walkInQrUrl);
      final qrImage = QrImage(qrCode);

      final bytes = await _generateBrandedQrImageBytes(qrImage);
      final downloaded = await saveOrDownloadBytes(bytes, 'walk_in_counter_qr.png');

      if (mounted && downloaded) {
        showAppSnack(context, 'Walk-In QR Code PNG downloaded successfully!');
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Failed to download QR code: $e', success: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrCode = QrCode(4, QrErrorCorrectLevel.L)..addData(walkInQrUrl);
    final qrImage = QrImage(qrCode);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppShadows.soft,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.qr_code_2_rounded, size: 24, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WALK-IN QR CODE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Universal Counter QR Code',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // QR Code Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1.2),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'OVERNIGHT CAFE',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'WALK-IN ORDERING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border, width: 1.5),
                        boxShadow: AppShadows.soft,
                      ),
                      child: SizedBox(
                        width: 140,
                        height: 140,
                        child: CustomPaint(
                          painter: _QrCodePainter(qrImage),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan to browse menu & order directly from phone',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _downloadQrCode,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download / Save QR Code', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkBrown,
                            side: const BorderSide(color: AppColors.darkBrown, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Clipboard.setData(const ClipboardData(text: walkInQrUrl));
                            showAppSnack(context, 'Walk-in ordering link copied to clipboard!');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: const Text('Copy Link', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkBrown,
                            side: const BorderSide(color: AppColors.darkBrown, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _launchGuestInterface,
                          icon: const Icon(Icons.launch_rounded, size: 15),
                          label: const Text('Simulate Scan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  final QrImage qrImage;
  _QrCodePainter(this.qrImage);

  @override
  void paint(Canvas canvas, Size size) {
    final darkPaint = Paint()..color = Colors.black;
    final lightPaint = Paint()..color = Colors.white;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), lightPaint);

    final qrSize = qrImage.moduleCount;
    final cellWidth = size.width / qrSize;
    final cellHeight = size.height / qrSize;

    for (int x = 0; x < qrSize; x++) {
      for (int y = 0; y < qrSize; y++) {
        if (qrImage.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth + 0.5, cellHeight + 0.5),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
