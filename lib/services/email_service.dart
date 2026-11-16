import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../config/email_config.dart';

/// Handles generating and actually sending OTP codes by email.
///
/// Sends via EmailJS's plain HTTP API instead of raw SMTP sockets, so this
/// works the same way on Android, iOS, desktop, AND Flutter Web (browsers
/// cannot open raw sockets, which is why an SMTP-based `mailer` approach
/// fails on web with "Unsupported operation: Socket constructor").
class EmailService {
  EmailService._();
  static final EmailService instance = EmailService._();

  static final Uri _endpoint = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

  final Random _rng = Random.secure();

  /// Generates a random 6-digit numeric OTP as a string, e.g. "042917".
  String generateOtp() {
    final code = _rng.nextInt(900000) + 100000; // 100000 - 999999
    return code.toString();
  }

  /// Sends the OTP to [toEmail]. Throws an [EmailSendException] on failure
  /// (bad config, no internet, EmailJS rejecting the request, etc.) so the
  /// caller can show the user a proper error instead of silently pretending
  /// the email went out.
  Future<void> sendOtpEmail({
    required String toEmail,
    required String toName,
    required String otp,
  }) async {
    if (EmailConfig.serviceId == 'your_service_id' ||
        EmailConfig.templateId == 'your_template_id' ||
        EmailConfig.publicKey == 'your_public_key') {
      throw EmailSendException(
        'Email sender is not configured yet. Fill in lib/config/email_config.dart '
        'with your EmailJS Service ID, Template ID, and Public Key.',
      );
    }

    try {
      final response = await http.post(
        _endpoint,
        headers: {'Content-Type': 'application/json', 'origin': 'http://localhost'},
        body: jsonEncode({
          'service_id': EmailConfig.serviceId,
          'template_id': EmailConfig.templateId,
          'user_id': EmailConfig.publicKey,
          'template_params': {
            'to_email': toEmail,
            'to_name': toName,
            'otp_code': otp,
            'from_name': EmailConfig.senderName,
            'reply_to': EmailConfig.noReplyEmail,
            'from_email': EmailConfig.noReplyEmail,
          },
        }),
      );

      if (response.statusCode != 200) {
        throw EmailSendException(
          'EmailJS rejected the request (${response.statusCode}): ${response.body}',
        );
      }
    } on EmailSendException {
      rethrow;
    } catch (e) {
      throw EmailSendException('Failed to send OTP email: $e');
    }
  }
}

class EmailSendException implements Exception {
  final String message;
  EmailSendException(this.message);
  @override
  String toString() => message;
}
