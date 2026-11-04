import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/app_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class CustomerArchiveScreen extends StatelessWidget {
  const CustomerArchiveScreen({super.key});

  void _confirmDeleteAll(BuildContext context, List<ArchivedRecord> records) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete All Archived Orders?'),
        content: Text('Are you sure you want to permanently delete all ${records.length} archived order(s)? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await AppData.instance.permanentlyDeleteAll(records);
              if (context.mounted) {
                showAppSnack(context, 'All archived orders permanently deleted.');
              }
            },
            child: const Text('Delete All Forever'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final myId = data.currentUser?.id;
        final records = data.archive.where((record) {
          if (record.category != 'Customer Orders') return false;
          if (myId != null && record.originalCustomerId == myId) return true;
          if (record.archivedBy == data.currentUser?.fullName ||
              record.archivedBy == data.currentUser?.email) {
            return true;
          }
          return false;
        }).toList();

        return SectionPage(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Restore an order to bring it back to your history.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
                if (records.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _confirmDeleteAll(context, records),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('Delete All'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (records.isEmpty) const _ArchiveEmptyState(),
            LayoutBuilder(
              builder: (context, constraints) {
                if (records.isEmpty) return const SizedBox.shrink();
                if (constraints.maxWidth < 680) {
                  return Column(
                    children: records
                        .map((record) => _archiveCard(context, record))
                        .toList(),
                  );
                }
                return ResponsiveTable(
                  columns: const [
                    DataColumn(label: Text('Order')),
                    DataColumn(label: Text('Details')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Date archived')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: records
                      .map(
                        (record) => DataRow(
                          cells: [
                            DataCell(Text(record.name)),
                            DataCell(Text(record.email)),
                            DataCell(StatusBadge(status: record.role)),
                            DataCell(
                              Text(formatDateTime(record.dateArchived)),
                            ),
                            DataCell(_archiveActions(context, record)),
                          ],
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _archiveCard(BuildContext context, ArchivedRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.beige,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.archive_outlined,
                    color: AppColors.brown,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatDateTime(record.dateArchived),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status: record.role),
              ],
            ),
            if (record.email.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                record.email,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmRestore(context, record),
                  icon: const Icon(
                    Icons.settings_backup_restore_outlined,
                    size: 18,
                  ),
                  label: const Text('Restore'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _confirmPermanentDelete(context, record),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete forever'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _archiveActions(BuildContext context, ArchivedRecord record) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(
            Icons.settings_backup_restore_outlined,
            size: 20,
            color: AppColors.success,
          ),
          tooltip: 'Restore order',
          onPressed: () => _confirmRestore(context, record),
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_forever_outlined,
            size: 20,
            color: AppColors.danger,
          ),
          tooltip: 'Permanently delete',
          onPressed: () => _confirmPermanentDelete(context, record),
        ),
      ],
    );
  }

  void _confirmRestore(BuildContext context, ArchivedRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        icon: const Icon(
          Icons.settings_backup_restore_outlined,
          color: AppColors.success,
        ),
        title: const Text('Restore order?'),
        content: Text(
          'Are you sure you want to restore “${record.name}” back to your active orders?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await AppData.instance.restoreRecord(record);
              if (context.mounted) {
                showAppSnack(
                  context,
                  '“${record.name}” restored successfully.',
                );
              }
            },
            icon: const Icon(Icons.settings_backup_restore_outlined, size: 18),
            label: const Text('Restore order'),
          ),
        ],
      ),
    );
  }

  void _confirmPermanentDelete(BuildContext context, ArchivedRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        icon: const Icon(
          Icons.delete_forever_outlined,
          color: AppColors.danger,
        ),
        title: const Text('Permanently delete?'),
        content: Text(
          'Are you sure you want to permanently delete “${record.name}”? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await AppData.instance.permanentlyDelete(record.id);
              if (context.mounted) {
                showAppSnack(context, '“${record.name}” permanently deleted.');
              }
            },
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Delete forever'),
          ),
        ],
      ),
    );
  }
}

class _ArchiveEmptyState extends StatelessWidget {
  const _ArchiveEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.archive_outlined, size: 30, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'No archived orders',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          SizedBox(height: 4),
          Text(
            'Orders you archive will be available here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
