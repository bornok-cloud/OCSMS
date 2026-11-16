import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import '../../widgets/shared_widgets.dart';

class RfidSettingsScreen extends StatefulWidget {
  const RfidSettingsScreen({super.key});

  @override
  State<RfidSettingsScreen> createState() => _RfidSettingsScreenState();
}

class _RfidSettingsScreenState extends State<RfidSettingsScreen> {
  String _searchQuery = '';
  final _testTagCtrl = TextEditingController();

  @override
  void dispose() {
    _testTagCtrl.dispose();
    super.dispose();
  }

  void _openRegisterDialog(AppUser user) {
    final tagCtrl = TextEditingController(text: user.rfidCardId ?? '');
    final focusNode = FocusNode();
    StreamSubscription? rfidSub;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          rfidSub ??= FirebaseFirestore.instance.collection('rfidScans').snapshots().listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final data = change.doc.data();
                final tag = (data?['rfidTag'] as String? ?? data?['cardId'] as String? ?? '').trim();
                if (tag.isNotEmpty) {
                  setDialogState(() {
                    tagCtrl.text = tag;
                  });
                }
              }
            }
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: AppColors.cardWhite,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: AppColors.darkBrown,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.nfc_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TAP RFID CARD TO REGISTER',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.fullName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Target Account Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.beigeDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.email_outlined, size: 14, color: AppColors.darkBrown),
                            SizedBox(width: 6),
                            Text('TARGET ACCOUNT EMAIL:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1.0)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          user.email.isNotEmpty ? user.email : 'No email attached (${user.fullName})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          'Employee System UID: ${user.id}',
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tap Card Sensor Graphic Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(color: AppColors.accent, width: 2),
                          ),
                          child: const Icon(Icons.sensors_rounded, size: 32, color: AppColors.accent),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'PLEASE TAP RFID CARD ON SCANNER NOW',
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Card UID will automatically capture and merge with this account email.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tag Input Field
                  TextField(
                    controller: tagCtrl,
                    focusNode: focusNode,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Scanned Card Tag UID',
                      hintText: 'e.g. CARD-882910 or A1B2C3D4',
                      prefixIcon: const Icon(Icons.credit_card_rounded, color: AppColors.darkBrown),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  rfidSub?.cancel();
                  Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.darkBrown),
                child: const Text('Cancel'),
              ),
              if (user.rfidCardId != null && user.rfidCardId!.isNotEmpty)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: () async {
                    rfidSub?.cancel();
                    Navigator.pop(ctx);
                    await AppData.instance.updateEmployeeRfidCard(user.id, '');
                    if (mounted) {
                      showAppSnack(context, 'Unlinked RFID Card from ${user.email}.');
                    }
                  },
                  child: const Text('Unlink Card'),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkBrown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final newTag = tagCtrl.text.trim();
                  if (newTag.isEmpty) {
                    showAppSnack(context, 'Please tap an RFID card or enter a valid Tag UID.', success: false);
                    return;
                  }

                  // Validation: Prevent duplicate RFID card assignment to another employee
                  AppUser? existingOwner;
                  for (final u in AppData.instance.users) {
                    if (u.id != user.id &&
                        u.rfidCardId != null &&
                        u.rfidCardId!.trim().toLowerCase() == newTag.toLowerCase()) {
                      existingOwner = u;
                      break;
                    }
                  }

                  if (existingOwner != null) {
                    showAppSnack(
                      context,
                      'RFID Card "$newTag" is already assigned to ${existingOwner.fullName} (${existingOwner.email.isNotEmpty ? existingOwner.email : 'User'})!',
                      success: false,
                    );
                    return;
                  }

                  rfidSub?.cancel();
                  Navigator.pop(ctx);
                  await AppData.instance.updateEmployeeRfidCard(user.id, newTag);
                  if (mounted) {
                    showAppSnack(context, 'RFID Card "$newTag" successfully merged & linked to ${user.email} (${user.fullName})!');
                  }
                },
                child: const Text('Merge & Link to Account'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openTestSimulationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sensors_rounded, color: AppColors.accent),
            SizedBox(width: 10),
            Text('Test RFID Card Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Simulate an RFID card tap to test real-time Time In / Time Out attendance processing:',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _testTagCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Enter Scanned Tag ID / Employee Name',
                hintText: 'e.g. RFID-882910 or Mikha Lim',
                prefixIcon: const Icon(Icons.fingerprint),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkBrown,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final tag = _testTagCtrl.text.trim();
              if (tag.isEmpty) {
                showAppSnack(context, 'Please enter a Tag ID or Employee Name.', success: false);
                return;
              }
              Navigator.pop(ctx);

              // Find matching user
              AppUser? match;
              for (final u in AppData.instance.users) {
                if ((u.rfidCardId != null && u.rfidCardId!.toLowerCase() == tag.toLowerCase()) ||
                    u.fullName.toLowerCase() == tag.toLowerCase() ||
                    u.id.toLowerCase() == tag.toLowerCase()) {
                  match = u;
                  break;
                }
              }

              if (match == null) {
                showAppSnack(context, 'No employee registered with RFID Tag "$tag".', success: false);
                return;
              }

              final record = await AppData.instance.recordAttendance(match.fullName, method: 'RFID');
              _testTagCtrl.clear();
              if (mounted) {
                final statusMsg = record.timeOut != null
                    ? 'TIMED OUT at ${record.timeOut}'
                    : 'TIMED IN at ${record.timeIn}';
                showAppSnack(context, '${match.fullName}: $statusMsg');
              }
            },
            child: const Text('Simulate Scan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppData.instance,
      builder: (context, _) {
        final staffList = AppData.instance.users
            .where((u) => u.role != UserRole.customer && u.status == 'Active')
            .where((u) => u.fullName.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

        return SectionPage(
          children: [
            // Banner Top Box
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.nfc_outlined, size: 28, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMPLOYEE RFID ATTENDANCE SETTINGS',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.white70,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Register & Manage RFID Cards',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Assign RFID card UIDs to employees for automated time-in & time-out tracking.',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _openTestSimulationDialog,
                    icon: const Icon(Icons.sensors_rounded, size: 18),
                    label: const Text('Test Scan', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search employee name...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Staff List
            if (staffList.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('No active employees or staff members found.', style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: staffList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final user = staffList[index];
                  final hasRfid = user.rfidCardId != null && user.rfidCardId!.isNotEmpty;

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 1.2),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.darkBrown,
                          child: Text(
                            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'E',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    user.fullName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkBrown),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.beige,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.beigeDark),
                                    ),
                                    child: Text(
                                      user.roleLabel,
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.badge_outlined,
                                    size: 13,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  SelectableText(
                                    'UID: ${user.id}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (user.employeeId != null && user.employeeId!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '•  ID: ${user.employeeId}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(
                                    hasRfid ? Icons.nfc_rounded : Icons.credit_card_off_rounded,
                                    size: 15,
                                    color: hasRfid ? AppColors.success : AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    hasRfid ? 'RFID Tag: ${user.rfidCardId}' : 'No RFID Card Registered',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: hasRfid ? FontWeight.bold : FontWeight.normal,
                                      color: hasRfid ? AppColors.darkBrown : AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkBrown,
                            side: const BorderSide(color: AppColors.darkBrown, width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _openRegisterDialog(user),
                          icon: Icon(hasRfid ? Icons.edit_rounded : Icons.add_card_rounded, size: 16),
                          label: Text(hasRfid ? 'Edit RFID' : 'Register RFID', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
