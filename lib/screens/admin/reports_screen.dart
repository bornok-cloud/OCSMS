import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  Future<void> _showFilterModal(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;

    return Column(
      children: [
        Material(
          color: AppColors.cream,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: TabBar(
                  controller: _tab,
                  isScrollable: false,
                  tabAlignment: TabAlignment.fill,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                  labelColor: AppColors.darkBrown,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12.5),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.accent.withValues(alpha: 0.16),
                    border: Border.all(color: AppColors.accent, width: 1.2),
                  ),
                  tabs: const [
                    Tab(text: 'Sales'),
                    Tab(text: 'Inventory'),
                    Tab(text: 'Payroll'),
                    Tab(text: 'Expenses'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Builder(
                  builder: (context) {
                    final isSingleDay = _dateRange != null &&
                        _dateRange!.start.year == _dateRange!.end.year &&
                        _dateRange!.start.month == _dateRange!.end.month &&
                        _dateRange!.start.day == _dateRange!.end.day;

                    final dateLabel = _dateRange == null
                        ? 'Filter Date: All'
                        : (isSingleDay
                            ? 'Date: ${_dateRange!.start.month}/${_dateRange!.start.day}/${_dateRange!.start.year}'
                            : 'Date: ${_dateRange!.start.month}/${_dateRange!.start.day}/${_dateRange!.start.year} - ${_dateRange!.end.month}/${_dateRange!.end.day}/${_dateRange!.end.year}');

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            onPressed: () => _showFilterModal(context),
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _SalesReport(data: data, dateRange: _dateRange),
              _InventoryReport(data: data),
              _PayrollReport(data: data),
              _ExpenseReport(data: data, dateRange: _dateRange),
            ],
          ),
        ),
      ],
    );
  }
}

bool _isWithinRange(DateTime date, DateTimeRange? range) {
  if (range == null) return true;
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
  return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
      date.isBefore(end.add(const Duration(seconds: 1)));
}

class _SalesReport extends StatelessWidget {
  final AppData data;
  final DateTimeRange? dateRange;
  const _SalesReport({required this.data, this.dateRange});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final filteredTx = data.transactions
            .where((t) => !t.archivedByAdmin)
            .where((t) => _isWithinRange(t.timestamp, dateRange))
            .toList();

        final totalSales = filteredTx.fold(0.0, (s, t) => s + t.total);
        final totalItems = filteredTx.fold(0, (s, t) => s + t.items.fold(0, (isum, item) => isum + item.quantity));

        return SectionPage(children: [
          StatGrid(cards: [
            StatCard(
                label: dateRange == null ? 'Total Sales' : 'Filtered Sales',
                value: peso(totalSales),
                icon: Icons.storefront_outlined,
                color: AppColors.brown),
            StatCard(
                label: 'Transactions Count',
                value: '${filteredTx.length}',
                icon: Icons.receipt_long_outlined,
                color: AppColors.brown),
            StatCard(
                label: 'Items Sold',
                value: '$totalItems',
                icon: Icons.local_cafe_outlined,
                color: AppColors.brown),
          ]),
          const SizedBox(height: 16),
          Text(dateRange == null ? 'All Transactions' : 'Filtered Transactions',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Date & Time')),
              DataColumn(label: Text('Items')),
              DataColumn(label: Text('Subtotal')),
              DataColumn(label: Text('Discount')),
              DataColumn(label: Text('Total')),
              DataColumn(label: Text('Cashier')),
              DataColumn(label: Text('Action')),
            ],
            rows: filteredTx.reversed.map((t) => DataRow(cells: [
                  DataCell(Text('${t.timestamp.month}/${t.timestamp.day}/${t.timestamp.year}')),
                  DataCell(Text('${t.items.length} item(s)')),
                  DataCell(Text(peso(t.subtotal))),
                  DataCell(Text(peso(t.discount))),
                  DataCell(Text(peso(t.total))),
                  DataCell(Text(t.cashier)),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.danger),
                      tooltip: 'Archive Sale',
                      onPressed: () => _confirmArchiveSale(context, t),
                    ),
                  ),
                ])).toList(),
          ),
        ]);
      },
    );
  }

  void _confirmArchiveSale(BuildContext context, TransactionRecord tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Sale Record?'),
        content: Text(
            'Are you sure you want to archive the sale from ${tx.timestamp.month}/${tx.timestamp.day}/${tx.timestamp.year} (${peso(tx.total)})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              AppData.instance.archiveTransaction(tx.id);
              Navigator.pop(ctx);
              showAppSnack(context, 'Sale record moved to Archive.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}

class _InventoryReport extends StatefulWidget {
  final AppData data;
  const _InventoryReport({required this.data});
  @override
  State<_InventoryReport> createState() => _InventoryReportState();
}

class _InventoryReportState extends State<_InventoryReport> {
  String _selectedTab = 'Inventory Item'; // 'Inventory Item' or 'Kitchen Item'

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final items = data.inventory.where((i) => i.itemType == _selectedTab).toList();
        final low = items.where((i) => i.status == 'Low Stock').length;
        final out = items.where((i) => i.status == 'Out of Stock').length;
        final near = items.where((i) => i.status == 'Near Expiration').length;
        final current = items.length - low - out - near;
        return SectionPage(children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('Inventory Items'),
                selected: _selectedTab == 'Inventory Item',
                onSelected: (sel) => setState(() => _selectedTab = 'Inventory Item'),
              ),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('Kitchen Items'),
                selected: _selectedTab == 'Kitchen Item',
                onSelected: (sel) => setState(() => _selectedTab = 'Kitchen Item'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StatGrid(cards: [
            StatCard(label: 'Current Stock Items', value: '$current', icon: Icons.inventory_2_outlined, color: AppColors.brown),
            StatCard(label: 'Low Stock', value: '$low', icon: Icons.warning_amber_outlined, color: AppColors.brown),
            StatCard(label: 'Out of Stock', value: '$out', icon: Icons.remove_shopping_cart_outlined, color: AppColors.brown),
            StatCard(label: 'Near Expiration', value: '$near', icon: Icons.timer_outlined, color: AppColors.brown),
          ]),
          const SizedBox(height: 16),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Qty')),
              DataColumn(label: Text('Status')),
            ],
            rows: items.map((i) => DataRow(cells: [
                  DataCell(Text(i.productName)),
                  DataCell(Text('${i.quantity} ${i.unit}')),
                  DataCell(StatusBadge(status: i.status)),
                ])).toList(),
          ),
        ]);
      },
    );
  }
}

class _PayrollReport extends StatelessWidget {
  final AppData data;
  const _PayrollReport({required this.data});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) => SectionPage(children: [
        StatGrid(cards: [
          StatCard(
            label: 'Total Payroll',
            value: peso(data.totalPayrollExpense),
            icon: Icons.payments_outlined,
            color: AppColors.brown,
          ),
          StatCard(label: 'Employees', value: '${data.activeEmployees.length}', icon: Icons.badge_outlined, color: AppColors.brown),
        ]),
        const SizedBox(height: 16),
        Text('Payroll Details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ResponsiveTable(
          columns: const [
            DataColumn(label: Text('Employee')),
            DataColumn(label: Text('Position')),
            DataColumn(label: Text('Net Salary')),
            DataColumn(label: Text('Status')),
          ],
          rows: data.activeEmployees.map((e) => DataRow(cells: [
                DataCell(Text(e.name)),
                DataCell(Text(e.position)),
                DataCell(Text(peso(e.netSalary))),
                DataCell(StatusBadge(status: e.status)),
              ])).toList(),
        ),
      ]),
    );
  }
}

class _ExpenseReport extends StatelessWidget {
  final AppData data;
  final DateTimeRange? dateRange;
  const _ExpenseReport({required this.data, this.dateRange});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final filteredPettyCash = data.pettyCash
            .where((e) => _isWithinRange(e.date, dateRange))
            .toList();

        double totalExpenses = 0.0;
        double totalAdded = 0.0;
        for (final e in filteredPettyCash) {
          if (e.amount < 0) totalExpenses += e.amount.abs();
          if (e.amount > 0) totalAdded += e.amount;
        }

        return SectionPage(children: [
          StatGrid(cards: [
            StatCard(
              label: 'Petty Cash Balance',
              value: peso(data.pettyCashBalance),
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.brown,
            ),
            StatCard(
              label: dateRange == null ? 'Total Expenses' : 'Filtered Expenses',
              value: peso(totalExpenses),
              icon: Icons.money_off_outlined,
              color: AppColors.brown,
            ),
            StatCard(
              label: dateRange == null ? 'Cash Added' : 'Filtered Cash Added',
              value: peso(totalAdded),
              icon: Icons.savings_outlined,
              color: AppColors.brown,
            ),
          ]),
          const SizedBox(height: 16),
          Text(dateRange == null ? 'All Expense Records' : 'Filtered Expense Records',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Amount')),
              DataColumn(label: Text('Action')),
            ],
            rows: filteredPettyCash.map((e) => DataRow(cells: [
                  DataCell(Text(e.description)),
                  DataCell(Text(e.category)),
                  DataCell(Text('${e.date.month}/${e.date.day}/${e.date.year}')),
                  DataCell(Text(
                    '${e.amount < 0 ? '-' : '+'}${peso(e.amount.abs())}',
                    style: TextStyle(
                        color: e.amount < 0
                            ? AppColors.danger
                            : AppColors.success,
                        fontWeight: FontWeight.bold),
                  )),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.danger),
                      tooltip: 'Archive Expense',
                      onPressed: () => _confirmArchiveExpense(context, e),
                    ),
                  ),
                ])).toList(),
          ),
        ]);
      },
    );
  }

  void _confirmArchiveExpense(BuildContext context, PettyCashEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Expense Record?'),
        content: Text('Are you sure you want to archive "${entry.description}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              AppData.instance.archivePettyCash(entry.id);
              Navigator.pop(ctx);
              showAppSnack(context, 'Expense record moved to Archive.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}
