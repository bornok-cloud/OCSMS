import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import 'shared_widgets.dart';

/// Presentation-only profile layout shared by the Admin, Employee and Customer
/// profile screens (black & white theme). All behaviour (picking a picture,
/// editing, password change) stays in each screen and is passed in as callbacks.
///
///  * Wide (>= 760px): identity card on the left, details + actions on the right.
///  * Narrow: everything stacked in one column.
class ProfileView extends StatelessWidget {
  final String name;
  final String roleText;
  final String email;
  final String phone;
  final String fallbackInitial;
  final Uint8List? avatarBytes;
  final String editLabel;
  final bool loading;
  final VoidCallback onChangePicture;
  final VoidCallback onEdit;
  final VoidCallback onChangePassword;

  const ProfileView({
    super.key,
    required this.name,
    required this.roleText,
    required this.email,
    required this.phone,
    required this.fallbackInitial,
    required this.avatarBytes,
    required this.onChangePicture,
    required this.onEdit,
    required this.onChangePassword,
    this.editLabel = 'Edit Profile',
    this.loading = false,
  });

  static const double _wideBreakpoint = 760;

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      );

  // ---------------------------------------------------------------- identity
  Widget _avatar() {
    final isLoyal = roleText.contains('Loyal');
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 104,
            height: 104,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isLoyal ? AppColors.accent : Colors.transparent,
                width: isLoyal ? 3.5 : 0,
              ),
              boxShadow: isLoyal
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : AppShadows.lifted,
            ),
            child: CircleAvatar(
              backgroundColor: AppColors.brown,
              backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes!) : null,
              child: avatarBytes == null
                  ? Text(
                      fallbackInitial,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 2,
            child: Tooltip(
              message: 'Change profile picture',
              child: Semantics(
                button: true,
                label: 'Change profile picture',
                child: Material(
                  color: AppColors.darkBrown,
                  shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2.5)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onChangePicture,
                    child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityCard() {
    const coverHeight = 112.0;
    const avatarSize = 104.0;
    return Container(
      decoration: _cardDecoration,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                child: Container(
                  height: coverHeight,
                  width: double.infinity,
                  color: AppColors.darkBrown,
                  child: const CustomPaint(painter: _CoverPainter()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: coverHeight - avatarSize / 2),
                child: _avatar(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
            child: Column(
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: AppColors.darkBrown,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.darkBrown,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    roleText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- details
  Widget _cardTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.beigeDark),
            ),
            child: Icon(icon, size: 20, color: AppColors.darkBrown),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.trim().isEmpty ? 'Not set' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: value.trim().isEmpty ? AppColors.textMuted : AppColors.darkBrown,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Contact information'),
          const SizedBox(height: 4),
          _infoTile(Icons.email_outlined, 'Email', email),
          const Divider(height: 1),
          _infoTile(Icons.phone_outlined, 'Phone', phone),
        ],
      ),
    );
  }

  Widget _actionsCard() {
    final edit = OutlinedButton.icon(
      onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: Text(editLabel),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.darkBrown, width: 1.3),
      ),
    );
    final password = ElevatedButton.icon(
      onPressed: loading ? null : onChangePassword,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.lock_outline, size: 18),
      label: const Text('Change Password'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        disabledBackgroundColor: loading ? AppColors.darkBrown : null,
        disabledForegroundColor: loading ? Colors.white : null,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Account'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 380) {
                return Column(children: [edit, const SizedBox(height: 10), password]);
              }
              return Row(
                children: [
                  Expanded(child: edit),
                  const SizedBox(width: 12),
                  Expanded(child: password),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Changing your password sends a verification code to your email.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: LayoutBuilder(
          builder: (context, c) {
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _contactCard(),
                const SizedBox(height: 16),
                _actionsCard(),
              ],
            );
            if (c.maxWidth >= _wideBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 320, child: _identityCard()),
                  const SizedBox(width: 20),
                  Expanded(child: details),
                ],
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _identityCard(),
                    const SizedBox(height: 16),
                    details,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Faint concentric rings on the black cover, matching the login/register panel.
class _CoverPainter extends CustomPainter {
  const _CoverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.08);
    final center = Offset(size.width * 0.9, size.height * 0.1);
    for (var i = 1; i <= 6; i++) {
      canvas.drawCircle(center, i * 34.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class EditProfileModal extends StatefulWidget {
  final AppUser user;
  final Future<void> Function({
    required String firstName,
    required String lastName,
    required String suffix,
    required String email,
    required String phone,
  }) onSave;

  const EditProfileModal({
    super.key,
    required this.user,
    required this.onSave,
  });

  @override
  State<EditProfileModal> createState() => _EditProfileModalState();
}

class _EditProfileModalState extends State<EditProfileModal> {
  static const List<String> _suffixes = [
    'N/A',
    'Jr.',
    'Sr.',
    'II',
    'III',
    'IV',
    'V',
    'VI',
  ];

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late String _selectedSuffix;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    String initialFirst = widget.user.firstName ?? '';
    String initialLast = widget.user.lastName ?? '';
    if (initialFirst.isEmpty && widget.user.fullName.isNotEmpty) {
      final parts = widget.user.fullName.trim().split(' ');
      initialFirst = parts.isNotEmpty ? parts.first : '';
      initialLast = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    _firstNameCtrl = TextEditingController(text: initialFirst);
    _lastNameCtrl = TextEditingController(text: initialLast);

    String userSuffix = (widget.user.suffix ?? '').trim();
    if (userSuffix.isEmpty || !_suffixes.contains(userSuffix)) {
      _selectedSuffix = 'N/A';
    } else {
      _selectedSuffix = userSuffix;
    }

    _emailCtrl = TextEditingController(text: widget.user.email);
    _phoneCtrl = TextEditingController(text: widget.user.phone);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        suffix: _selectedSuffix == 'N/A' ? '' : _selectedSuffix,
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.cardWhite,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.manage_accounts_outlined,
                    color: AppColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.darkBrown,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Update your personal information below',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined, size: 15, color: AppColors.accent),
                          const SizedBox(width: 6),
                          const Text(
                            'PERSONAL NAME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          final isPhone = constraints.maxWidth < 440;
                          final firstNameField = TextFormField(
                            controller: _firstNameCtrl,
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: [NameTextInputFormatter()],
                            decoration: InputDecoration(
                              labelText: 'First Name *',
                              hintText: 'e.g. Juan',
                              prefixIcon: const Icon(Icons.person_outline, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                            validator: validateFirstName,
                          );

                          final lastNameField = TextFormField(
                            controller: _lastNameCtrl,
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: [NameTextInputFormatter()],
                            decoration: InputDecoration(
                              labelText: 'Last Name *',
                              hintText: 'e.g. Dela Cruz',
                              prefixIcon: const Icon(Icons.person_outline, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                            validator: validateLastName,
                          );

                          final suffixField = DropdownButtonFormField<String>(
                            initialValue: _selectedSuffix,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Suffix',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                            items: _suffixes
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s, style: const TextStyle(fontSize: 13.5)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              setState(() {
                                _selectedSuffix = v ?? 'N/A';
                              });
                            },
                          );

                          if (!isPhone) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: firstNameField),
                                const SizedBox(width: 8),
                                Expanded(flex: 2, child: lastNameField),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: suffixField),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                firstNameField,
                                const SizedBox(height: 10),
                                lastNameField,
                                const SizedBox(height: 10),
                                suffixField,
                              ],
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Icon(Icons.contact_mail_outlined, size: 15, color: AppColors.accent),
                          const SizedBox(width: 6),
                          const Text(
                            'CONTACT INFORMATION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email Address *',
                          hintText: 'name@example.com',
                          prefixIcon: const Icon(Icons.email_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Email is required';
                          final email = v.trim();
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone Number *',
                          hintText: '09123456789',
                          prefixIcon: const Icon(Icons.phone_android_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Phone number is required';
                          final trimmed = v.trim();
                          if (!trimmed.startsWith('09') || trimmed.length != 11 || !RegExp(r'^[0-9]+$').hasMatch(trimmed)) {
                            return 'Must be 11 digits and start with 09';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.darkBrown,
                    side: const BorderSide(color: AppColors.beigeDark),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkBrown,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(_saving ? 'Saving...' : 'Save Changes', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
