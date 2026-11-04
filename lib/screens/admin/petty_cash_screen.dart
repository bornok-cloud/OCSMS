import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class PettyCashScreen extends StatefulWidget {
  const PettyCashScreen({super.key});
  @override
  State<PettyCashScreen> createState() => _PettyCashScreenState();
}

class _PettyCashScreenState extends State<PettyCashScreen> {
  DateTimeRange? _dateRange = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
  );

  bool get _isToday {
    if (_dateRange == null) return false;
    final now = DateTime.now();
    return _dateRange!.start.year == now.year &&
           _dateRange!.start.month == now.month &&
           _dateRange!.start.day == now.day &&
           _dateRange!.end.year == now.year &&
           _dateRange!.end.month == now.month &&
           _dateRange!.end.day == now.day;
  }

  static const _amountPresets = <double>[100, 200, 500, 1000, 2000, 5000];

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => CustomDateRangePickerDialog(
        initialRange: _dateRange ?? DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        ),
      ),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  bool _isWithinRange(DateTime date, DateTimeRange? range) {
    if (range == null) return true;
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
        date.isBefore(end.add(const Duration(seconds: 1)));
  }

  Widget _amountPresetsFor(TextEditingController controller) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _amountPresets.map((amount) {
        final label = amount >= 1000
            ? '₱${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k'
            : '₱${amount.toStringAsFixed(0)}';
        return OutlinedButton(
          onPressed: () => controller.text = amount.toStringAsFixed(0),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
          child: Text(label),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final filteredEntries = data.pettyCash
            .where((e) => _isWithinRange(e.date, _dateRange))
            .toList();

        double expenses = 0.0;
        double added = 0.0;
        for (final e in filteredEntries) {
          if (e.amount < 0) expenses += e.amount.abs();
          if (e.amount > 0) added += e.amount;
        }
        final balance = data.pettyCashStart + added - expenses;

        final isSingleDay = _dateRange != null &&
            _dateRange!.start.year == _dateRange!.end.year &&
            _dateRange!.start.month == _dateRange!.end.month &&
            _dateRange!.start.day == _dateRange!.end.day;

        final dateLabel = _dateRange == null
            ? 'Filter Date: All'
            : (isSingleDay
                ? 'Date: ${_dateRange!.start.month}/${_dateRange!.start.day}/${_dateRange!.start.year}'
                : 'Date: ${_dateRange!.start.month}/${_dateRange!.start.day}/${_dateRange!.start.year} - ${_dateRange!.end.month}/${_dateRange!.end.day}/${_dateRange!.end.year}');

        return SectionPage(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.soft,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black87),
                  label: Text(
                    dateLabel,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    side: const BorderSide(color: Colors.black87, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    backgroundColor: Colors.white,
                  ),
                ),
                if (!_isToday) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black, size: 20),
                    tooltip: 'Reset to Today',
                    onPressed: () => setState(() {
                      final now = DateTime.now();
                      _dateRange = DateTimeRange(
                        start: DateTime(now.year, now.month, now.day),
                        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
          StatGrid(cards: [
            InkWell(
              onTap: () => _editStartingBalanceDialog(context, data.pettyCashStart),
              borderRadius: BorderRadius.circular(16),
              child: StatCard(
                  label: 'Starting Balance (Tap to Edit)',
                  value: peso(data.pettyCashStart),
                  icon: Icons.account_balance_outlined,
                  color: AppColors.brown),
            ),
            StatCard(
                label: _dateRange == null ? 'Total Cash Added' : 'Filtered Cash Added',
                value: peso(added),
                icon: Icons.add_circle_outline,
                color: AppColors.brown),
            StatCard(
                label: _dateRange == null ? 'Total Expenses' : 'Filtered Expenses',
                value: peso(expenses),
                icon: Icons.trending_down,
                color: AppColors.brown),
            StatCard(
                label: 'Petty Cash Balance',
                value: peso(balance),
                icon: Icons.account_balance_wallet_outlined,
                color: AppColors.accent),
          ]),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 750;
              final addButton = ElevatedButton.icon(
                onPressed: () => _showAddExpenseDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Petty Cash / Expense', overflow: TextOverflow.ellipsis),
              );

              if (isWide) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_dateRange == null ? 'All Petty Cash History' : 'Filtered Petty Cash History',
                        style: Theme.of(context).textTheme.titleMedium),
                    addButton,
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_dateRange == null ? 'All Petty Cash History' : 'Filtered Petty Cash History',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    addButton,
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 10),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Date & Time')),
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Amount')),
              DataColumn(label: Text('Action')),
            ],
            rows: filteredEntries.map((e) {
              final isExpense = e.amount < 0;
              return DataRow(cells: [
                DataCell(Text(formatDateTime(e.date))),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.beige,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(e.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                DataCell(Text(e.description)),
                DataCell(Text(
                  peso(e.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isExpense ? AppColors.danger : AppColors.success,
                  ),
                )),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.textMuted),
                    tooltip: 'Archive entry',
                    onPressed: () => _confirmArchive(context, e),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ]);
      },
    );
  }

  void _editStartingBalanceDialog(BuildContext context, double currentStart) {
    final ctrl = TextEditingController(text: currentStart.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Starting Balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Set the starting petty cash balance for this shift/period:'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Starting Balance', prefixText: '₱ '),
            ),
            const SizedBox(height: 10),
            _amountPresetsFor(ctrl),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.trim());
              if (val != null) {
                AppData.instance.updatePettyCashStart(val);
                Navigator.pop(ctx);
                showAppSnack(context, 'Starting balance updated.');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context) {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String category = 'Supplies';
    bool isExpense = true;

    final categories = ['Supplies', 'Utilities', 'Maintenance', 'Emergency', 'Cash In / Refill', 'Others'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Petty Cash Entry'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Expense (Out)')),
                      ButtonSegment(value: false, label: Text('Cash In / Refill')),
                    ],
                    selected: {isExpense},
                    onSelectionChanged: (set) => setDialogState(() => isExpense = set.first),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Category', isDense: true, border: OutlineInputBorder()),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setDialogState(() => category = v ?? category),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description', isDense: true, border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount', prefixText: '₱ ', isDense: true, border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  _amountPresetsFor(amountCtrl),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final desc = descCtrl.text.trim();
                if (amount <= 0 || desc.isEmpty) {
                  showAppSnack(context, 'Please enter a valid description and amount.');
                  return;
                }
                final finalAmount = isExpense ? -amount : amount;
                AppData.instance.addPettyCash(desc, category, finalAmount);
                Navigator.pop(ctx);
                showAppSnack(context, 'Petty cash entry added successfully.');
              },
              child: const Text('Add Entry'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmArchive(BuildContext context, PettyCashEntry e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Petty Cash Entry?'),
        content: Text('Are you sure you want to archive "${e.description}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              AppData.instance.archivePettyCash(e.id);
              Navigator.pop(ctx);
              showAppSnack(context, 'Petty cash entry archived.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}
