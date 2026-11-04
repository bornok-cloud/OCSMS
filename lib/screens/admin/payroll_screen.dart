import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final filtered = data.payrollHistory
            .where((p) => _isWithinRange(p.date, _dateRange))
            .toList();

        final totalFilteredPayroll = filtered.fold(0.0, (sum, p) => sum + p.netSalary);

        final isSingleDay = _dateRange != null &&
            _dateRange!.start.year == _dateRange!.end.year &&
            _dateRange!.start.month == _dateRange!.end.month &&
            _dateRange!.start.day == _dateRange!.end.day;

        final dateLabel = _dateRange == null
            ? 'Filter Date: All'
            : (isSingleDay
                ? 'Date: ${_dateRange!.start.month}/${_dateRange!.start.day}/${_dateRange!.start.year}'
                : 'Date: ${_dateRange!.start.month}/${_dateRange!.start.day}/${_dateRange!.start.year} - ${_dateRange!.end.month}/${_dateRange!.end.day}/${_dateRange!.end.year}');

        return SectionPage(
          children: [
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
              StatCard(
                label: _dateRange == null ? 'Total Payroll Payouts' : 'Filtered Payroll Payouts',
                value: peso(totalFilteredPayroll),
                icon: Icons.payments_outlined,
                color: AppColors.brown,
              ),
              StatCard(
                label: 'Employees',
                value: '${data.employeeUsers.length}',
                icon: Icons.people_outline,
                color: AppColors.brown,
              ),
              StatCard(
                label: 'Payout Records',
                value: '${filtered.length}',
                icon: Icons.history_edu,
                color: AppColors.brown,
              ),
            ]),
            const SizedBox(height: 16),
            Text(_dateRange == null ? 'All Payroll Payouts' : 'Filtered Payroll Payouts',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ResponsiveTable(
              columns: const [
                DataColumn(label: Text('Employee')),
                DataColumn(label: Text('Position')),
                DataColumn(label: Text('Net Salary')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Date & Time')),
                DataColumn(label: Text('Action')),
              ],
              rows: filtered.map((p) {
                return DataRow(cells: [
                  DataCell(Text(p.employeeName, style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(p.position)),
                  DataCell(Text(peso(p.netSalary), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success))),
                  DataCell(StatusBadge(status: p.status)),
                  DataCell(Text(formatDateTime(p.date))),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.textMuted),
                      tooltip: 'Archive payroll record',
                      onPressed: () => _confirmArchive(context, p),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  void _confirmArchive(BuildContext context, PayrollRecord p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Payroll Record?'),
        content: Text('Are you sure you want to archive payroll for "${p.employeeName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              AppData.instance.archivePayroll(p.id);
              Navigator.pop(ctx);
              showAppSnack(context, 'Payroll record archived.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}
