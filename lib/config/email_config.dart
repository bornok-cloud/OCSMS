// ============================================================================
// EMAIL CONFIGURATION (EmailJS)
// ============================================================================
// The OTP email is sent through EmailJS (https://www.emailjs.com), which
// works over a plain HTTP request — so, unlike raw SMTP, it works on
// Android AND on Flutter Web (browsers can't open raw sockets, which is
// why the old Gmail-SMTP/`mailer` approach failed with
// "Unsupported operation: Socket constructor").
//
// SETUP (free tier is enough for a school project):
//   1. Create an account at https://www.emailjs.com
//   2. Email Services -> Add New Service -> connect your Gmail (or any
//      provider). Copy the "Service ID" it gives you.
//   3. Email Templates -> Create New Template. Use these variable names
//      in the template body so they match what this app sends:
//        {{to_email}}   - recipient's email address
//        {{to_name}}    - recipient's name
//        {{otp_code}}   - the 6-digit code
//      Example template body:
//        "Hi {{to_name}}, your Overnight Cafe verification code is
//         {{otp_code}}. It expires in 5 minutes."
//      Copy the "Template ID".
//   4. Account -> General -> copy your "Public Key".
//   5. Paste all three values below.
//
// NOTE: The public key is meant to be used client-side (that's how EmailJS
// is designed), but for a real production app you'd still want server-side
// rate limiting so the endpoint can't be spammed. Fine for a school project.
// ============================================================================

class EmailConfig {
  /// EmailJS "Service ID" (Email Services tab).
  static const String serviceId = 'service_ktswy7t';

  /// EmailJS "Template ID" (Email Templates tab).
  static const String templateId = 'template_oz8uejy';

  /// EmailJS "Public Key" (Account -> General).
  static const String publicKey = 'MLEDz-_s8hmMdrL7O';

  /// No-Reply sender display name and address configuration.
  static const String senderName = 'Overnight Cafe – No Reply';
  static const String noReplyEmail = 'no-reply@overnightcafe.com';
}
