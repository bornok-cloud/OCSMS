import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/receipt_widgets.dart';
import '../../models/models.dart';

class CustomerReceiptsScreen extends StatefulWidget {
  const CustomerReceiptsScreen({super.key});

  @override
  State<CustomerReceiptsScreen> createState() => _CustomerReceiptsScreenState();
}

class _CustomerReceiptsScreenState extends State<CustomerReceiptsScreen> {
  DateTimeRange? _selectedDateRange;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => CustomDateRangePickerDialog(
        initialRange: _selectedDateRange ?? DateTimeRange(start: now, end: now),
      ),
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final myId = data.currentUser?.id;

        var receiptsList = <Map<String, dynamic>>[];
        if (myId != null) {
          for (final t in data.transactions.where(
            (t) => t.customerId == myId && t.linkedReceipt != null,
          )) {
            receiptsList.add({
              'id': t.id,
              'orderNumber': t.displayOrderNumber,
              'date': t.timestamp,
              'total': t.total,
              'items': t.items,
              'receipt': t.linkedReceipt!,
            });
          }
        }

        // Filter by Date Range if selected
        if (_selectedDateRange != null) {
          final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
          receiptsList = receiptsList.where((item) {
            final DateTime date = item['date'];
            return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
                date.isBefore(end.add(const Duration(seconds: 1)));
          }).toList();
        }

        receiptsList.sort((a, b) {
          final DateTime dateA = a['date'];
          final DateTime dateB = b['date'];
          return dateB.compareTo(dateA); // Newest first
        });

        final dateFilterButton = OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.brown),
          label: Text(
            _selectedDateRange == null
                ? 'Filter Date: All'
                : (_selectedDateRange!.start.year == _selectedDateRange!.end.year &&
                   _selectedDateRange!.start.month == _selectedDateRange!.end.month &&
                   _selectedDateRange!.start.day == _selectedDateRange!.end.day
                    ? 'Date: ${_selectedDateRange!.start.month}/${_selectedDateRange!.start.day}/${_selectedDateRange!.start.year}'
                    : 'Date: ${_selectedDateRange!.start.month}/${_selectedDateRange!.start.day} - ${_selectedDateRange!.end.month}/${_selectedDateRange!.end.day}'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.brown),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            side: BorderSide(color: _selectedDateRange != null ? AppColors.accent : AppColors.border),
          ),
        );

        return SectionPage(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  'All receipts (${receiptsList.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                );

                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: dateFilterButton),
                          if (_selectedDateRange != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.clear, color: AppColors.danger),
                              tooltip: 'Clear Date Filter',
                              onPressed: () => setState(() => _selectedDateRange = null),
                            ),
                          ],
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: title),
                    dateFilterButton,
                    if (_selectedDateRange != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.danger),
                        tooltip: 'Clear Date Filter',
                        onPressed: () => setState(() => _selectedDateRange = null),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (receiptsList.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No receipts found on file.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ),
            PaginatedList<Map<String, dynamic>>(
              items: receiptsList,
              pageSize: 6,
              itemBuilder: (context, item) {
                final ReceiptRecord r = item['receipt'];
                final DateTime date = item['date'];
                final double total = item['total'];
                final String orderNo = item['orderNumber'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Order No: $orderNo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Text(
                              peso(total),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${date.month}/${date.day}/${date.year}  ·  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const Divider(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                insetPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 24,
                                ),
                                title: Row(
                                  children: [
                                    const Icon(
                                      Icons.receipt_long_outlined,
                                      color: AppColors.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Receipt — Order #$orderNo',
                                      ),
                                    ),
                                  ],
                                ),
                                content: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 420),
                                  child: SingleChildScrollView(
                                    child: ReceiptView(receipt: r),
                                  ),
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                            icon: const Icon(
                              Icons.receipt_long_outlined,
                              size: 16,
                            ),
                            label: const Text('View Receipt'),
                          ),
                        ),
                      ],
                    ),
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
