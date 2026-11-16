import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';
import '../auth/register_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  String _search = '';
  String _roleFilter = 'All';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        var users = AppData.instance.users
            .where(
                (u) => u.fullName.toLowerCase().contains(_search.toLowerCase()))
            .toList();
        if (_roleFilter != 'All') {
          users = users.where((u) => u.roleLabel == _roleFilter).toList();
        }

        final activeAdminsCount = AppData.instance.users
            .where((u) => u.role == UserRole.admin && u.status == 'Active')
            .length;

        return SectionPage(children: [
          Builder(
            builder: (context) {
              final wideControls = MediaQuery.of(context).size.width >= 650;
              final searchField = TextField(
                decoration: const InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true),
                onChanged: (v) => setState(() => _search = v),
              );

              final roleDropdown = DropdownButtonFormField<String>(
                initialValue: _roleFilter,
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: const ['All', 'Admin', 'Employee', 'Customer']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() => _roleFilter = v ?? 'All'),
              );

              if (wideControls) {
                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    SizedBox(width: 140, child: roleDropdown),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                        onPressed: () => _addUserDialog(context),
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Add User')),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: roleDropdown),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                            onPressed: () => _addUserDialog(context),
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Add')),
                      ],
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Registered')),
              DataColumn(label: Text('Actions')),
            ],
            rows: users
                .map((u) => DataRow(cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(u.fullName),
                            if (AppData.instance.isCustomerLoyal(u)) const LoyalBadge(),
                          ],
                        ),
                      ),
                      DataCell(Text(u.email)),
                      DataCell(Text(u.roleLabel)),
                      DataCell(StatusBadge(status: u.status)),
                      DataCell(Text(
                          '${u.dateRegistered.month}/${u.dateRegistered.day}/${u.dateRegistered.year}')),
                      DataCell(Row(children: [
                        if (u.role == UserRole.admin && u.status == 'Active' && activeAdminsCount <= 1) ...[
                          const Tooltip(
                            message: 'Protected: Only remaining active admin account',
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
                            ),
                          ),
                        ] else ...[
                          IconButton(
                            icon: Icon(
                              u.status == 'Active' ? Icons.block : Icons.check_circle_outline,
                              size: 18,
                              color: u.status == 'Active' ? AppColors.warning : AppColors.success,
                            ),
                            tooltip: u.status == 'Active' ? 'Deactivate (Make Inactive)' : 'Activate',
                            onPressed: () => _confirmToggleStatus(context, u),
                          ),
                          IconButton(
                            icon: const Icon(Icons.archive_outlined,
                                size: 18, color: AppColors.danger),
                            tooltip: 'Archive',
                            onPressed: () => _confirmArchive(context, u),
                          ),
                        ],
                      ])),
                    ]))
                .toList(),
          ),
        ]);
      },
    );
  }

  void _confirmToggleStatus(BuildContext context, AppUser user) {
    final activating = user.status != 'Active';
    if (!activating && user.role == UserRole.admin) {
      final activeAdminsCount = AppData.instance.users.where((u) => u.role == UserRole.admin && u.status == 'Active').length;
      if (activeAdminsCount <= 1) {
        showAppSnack(context, 'Cannot disable the only remaining admin account!', success: false);
        return;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activating ? 'Activate Account?' : 'Deactivate Account?'),
        content: Text(
          activating
              ? 'Are you sure you want to activate ${user.fullName}\'s account? They will be able to log in.'
              : 'Are you sure you want to deactivate ${user.fullName}\'s account? They will no longer be able to log in until reactivated.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: activating ? AppColors.success : AppColors.warning,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newStatus = activating ? 'Active' : 'Disabled';
              AppData.instance.updateUserStatus(user.id, newStatus);
              Navigator.pop(ctx);
            },
            child: Text(activating ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
  }

  void _confirmArchive(BuildContext context, AppUser user) {
    if (user.role == UserRole.admin) {
      final activeAdminsCount = AppData.instance.users.where((u) => u.role == UserRole.admin && u.status == 'Active').length;
      if (activeAdminsCount <= 1) {
        showAppSnack(context, 'Cannot archive the only remaining admin account!', success: false);
        return;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive User?'),
        content: const Text(
            'Instead of permanently deleting this user, the account will be moved to the Archive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              AppData.instance.archiveUser(user.id);
              Navigator.pop(ctx);
              showAppSnack(context, 'User successfully moved to Archive.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _addUserDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen(isAdminCreation: true)),
    );
  }
}
