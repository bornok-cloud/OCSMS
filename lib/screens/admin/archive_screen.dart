import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});
  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  String _category = 'Inventory Items';

  final List<String> _categories = [
    'Inventory Items',
    'Kitchen Items',
    'Products',
    'Users',
    'Expenses',
    'Payroll',
    'Sales',
    'Feedback',
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final records = AppData.instance.archive.where((r) {
          if (_category == 'Inventory Items') {
            return r.category == 'Inventory Items' || r.category == 'Inventory';
          }
          if (_category == 'Kitchen Items') {
            return r.category == 'Kitchen Items';
          }
          if (_category == 'Users') {
            return r.category == 'Users' || r.category == 'Employees';
          }
          if (_category == 'Expenses') {
            return r.category == 'Expenses' || r.category == 'Petty Cash';
          }
          if (_category == 'Payroll') {
            return r.category == 'Payroll' || r.category == 'Payroll History';
          }
          if (_category == 'Feedback') {
            return r.category == 'Customer Feedback' || r.category == 'Feedback';
          }
          return r.category == _category;
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _categories
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(c),
                              selected: _category == c,
                              onSelected: (_) => setState(() => _category = c),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Archived $_category (${records.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkBrown),
                  ),
                  if (records.isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => _confirmDeleteAll(context, _category, records),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                      label: const Text('Delete All'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ResponsiveTable(
                columns: const [
                  DataColumn(label: Text('Name / Title')),
                  DataColumn(label: Text('Details')),
                  DataColumn(label: Text('Category / Info')),
                  DataColumn(label: Text('Date Archived')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: records.map((r) => DataRow(cells: [
                      DataCell(Text(r.name)),
                      DataCell(Text(r.email)),
                      DataCell(Text(r.role)),
                      DataCell(Text('${r.dateArchived.month}/${r.dateArchived.day}/${r.dateArchived.year}')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.settings_backup_restore_outlined, size: 20, color: AppColors.success),
                              tooltip: 'Restore Record',
                              onPressed: () => _confirmRestore(context, r),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_forever_outlined, size: 20, color: AppColors.danger),
                              tooltip: 'Permanently Delete',
                              onPressed: () => _confirmPermanentDelete(context, r),
                            ),
                          ],
                        ),
                      ),
                    ])).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteAll(BuildContext context, String categoryName, List<ArchivedRecord> records) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete All $categoryName?'),
        content: Text('Are you sure you want to permanently delete all ${records.length} archived record(s) under "$categoryName"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await AppData.instance.permanentlyDeleteAll(records);
              if (ctx.mounted) {
                showAppSnack(ctx, 'All records under "$categoryName" have been permanently deleted.');
              }
            },
            child: const Text('Delete All Forever'),
          ),
        ],
      ),
    );
  }

  void _confirmRestore(BuildContext context, ArchivedRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Record?'),
        content: Text('Are you sure you want to restore "${record.name}" back to ${record.category}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              AppData.instance.restoreRecord(record);
              Navigator.pop(ctx);
              showAppSnack(context, '"${record.name}" restored successfully.');
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _confirmPermanentDelete(BuildContext context, ArchivedRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently Delete?'),
        content: Text('Are you sure you want to permanently delete "${record.name}"? This action cannot be undone and will permanently remove only this archived record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              AppData.instance.permanentlyDelete(record.id);
              Navigator.pop(ctx);
              showAppSnack(context, '"${record.name}" permanently deleted.');
            },
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
  }
}
