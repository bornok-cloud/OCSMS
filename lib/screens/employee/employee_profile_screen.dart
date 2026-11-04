import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/profile_view.dart';
import '../../widgets/profile_crop_dialog.dart';
import '../../models/models.dart';
import '../auth/password_reset_screen.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  bool _loading = false;

  Future<void> _changeProfilePicture(AppUser user) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => ProfileCropDialog(
          imageBytes: file.bytes!,
          userId: user.id,
        ),
      );

      if (confirmed == true && mounted) {
        showAppSnack(context, 'Profile picture updated successfully.');
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Failed to update profile picture: $e');
    }
  }

  void _showEditProfileDialog(AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => EditProfileModal(
        user: user,
        onSave: ({
          required String firstName,
          required String lastName,
          required String suffix,
          required String email,
          required String phone,
        }) async {
          final emailChanged = email.toLowerCase() != user.email.trim().toLowerCase();

          if (emailChanged) {
            final existingUser = await AppData.instance.findUserByEmail(email);
            if (existingUser != null && existingUser.id != user.id) {
              if (!mounted) return;
              showAppSnack(context, 'This email address is already in use.', success: false);
              return;
            }

            if (!mounted) return;
            final confirmChange = await showDialog<bool>(
              context: context,
              builder: (ctxConfirm) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('Confirm Email Change', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Are you sure you want to change your email address to:'),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.beige,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.beigeDark),
                      ),
                      child: Text(
                        email,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A One-Time Password (OTP) verification code will be sent to your new email address to confirm ownership before updating your profile.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctxConfirm, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkBrown,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(ctxConfirm, true),
                    child: const Text('Confirm & Send OTP'),
                  ),
                ],
              ),
            );

            if (confirmChange != true) return;

            try {
              await AppData.instance.sendEmailChangeOtp(user, email);
            } catch (e) {
              if (!mounted) return;
              showAppSnack(context, 'Failed to send OTP verification code: $e', success: false);
              return;
            }

            if (!mounted) return;
            final verified = await showEmailOtpDialog(
              context: context,
              user: user,
              newEmail: email,
            );

            if (verified != true) return;
          }

          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          await AppData.instance.updateProfile(
            userId: user.id,
            firstName: firstName,
            lastName: lastName,
            suffix: suffix,
            email: email,
            phone: phone,
          );
          if (!mounted) return;
          showAppSnack(context, 'Profile updated successfully.');
        },
      ),
    );
  }

  Future<void> _startPasswordChange(AppUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Text('A verification OTP code will be sent to your email (${user.email}) to confirm changing your password.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send OTP')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await AppData.instance.sendChangePasswordOtp(user);
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PasswordResetFlowScreen(user: user)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppSnack(context, 'Failed to send verification code: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final user = AppData.instance.currentUser;
        if (user == null) {
          return const SizedBox.shrink();
        }

        Uint8List? avatarBytes;
        if (user.profileImage != null && user.profileImage!.isNotEmpty) {
          try {
            avatarBytes = base64Decode(user.profileImage!);
          } catch (_) {}
        }

        return SectionPage(children: [
          ProfileView(
            name: user.fullName,
            roleText: user.position ?? 'Employee',
            email: user.email,
            phone: user.phone,
            fallbackInitial: user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'E',
            avatarBytes: avatarBytes,
            loading: _loading,
            editLabel: 'Edit Info',
            onChangePicture: () => _changeProfilePicture(user),
            onEdit: () => _showEditProfileDialog(user),
            onChangePassword: () => _startPasswordChange(user),
          ),
        ]);
      },
    );
  }
}
