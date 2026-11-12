import 'dart:convert';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/receipt_widgets.dart';
import '../../models/models.dart';

class _OrderHistoryItem {
  final TransactionRecord transaction;
  final String displayId;
  final String customerName;
  final String source; // POS or Customer Menu
  final DateTime date;
  final double total;

  _OrderHistoryItem({
    required this.transaction,
    required this.displayId,
    required this.customerName,
    required this.source,
    required this.date,
    required this.total,
  });
}

class AdminOrderHistoryScreen extends StatefulWidget {
  const AdminOrderHistoryScreen({super.key});

  @override
  State<AdminOrderHistoryScreen> createState() => _AdminOrderHistoryScreenState();
}

class _AdminOrderHistoryScreenState extends State<AdminOrderHistoryScreen> {
  String _search = '';
  String _sourceFilter = 'All'; // 'All', 'POS', 'Customer Menu'
  String _sortBy = 'Date (Newest)'; // 'Date (Newest)', 'Date (Oldest)'
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

  void _showOrderListModal(BuildContext context, TransactionRecord t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Order #${t.displayOrderNumber} — Items'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...t.items.map((i) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.beige.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.beigeDark),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${i.quantity} × ${i.product.name}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.darkBrown),
                                ),
                              ),
                              Text(peso(i.subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.darkBrown)),
                            ],
                          ),
                          if (i.selectedAddOns.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              i.selectedAddOns.map((a) => a.quantity > 1 ? '${a.quantity} × ${a.name}' : '+ ${a.name}').join(', '),
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ],
                      ),
                    )),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Items:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 13)),
                    Text('${t.items.fold(0, (s, i) => s + i.quantity)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Total:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown, fontSize: 14)),
                    Text(peso(t.total), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.darkBrown, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkBrown,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmArchive(BuildContext context, _OrderHistoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this order?'),
        content: Text('Order #${item.displayId} will move to your Archive and no longer appear in Order History.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brown, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await AppData.instance.archiveTransaction(item.transaction.id);
              if (ctx.mounted) {
                showAppSnack(ctx, 'Order #${item.displayId} archived successfully.');
              }
            },
            child: const Text('Archive order'),
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

        // Build normalized list of completed transactions (excluding admin-archived)
        var items = data.transactions.where((t) => !t.archivedByAdmin).map((t) {
          final rSource = t.receipt?.source;
          final sourceLabel = (rSource != null && rSource.isNotEmpty)
              ? (rSource == 'Kiosk' ? 'Customer Menu' : rSource)
              : (t.customerId != null ? 'Customer Menu' : 'POS');

          return _OrderHistoryItem(
            transaction: t,
            displayId: t.displayOrderNumber,
            customerName: (t.customerName != null && t.customerName!.isNotEmpty)
                ? t.customerName!
                : 'Walk-in Customer',
            source: sourceLabel,
            date: t.timestamp,
            total: t.total,
          );
        }).toList();

        // 1. Filter by Search Query (Order Number or Customer Name)
        if (_search.isNotEmpty) {
          final query = _search.toLowerCase();
          items = items.where((i) =>
              i.displayId.toLowerCase().contains(query) ||
              i.customerName.toLowerCase().contains(query)
          ).toList();
        }

        // 2. Filter by Source
        if (_sourceFilter != 'All') {
          items = items.where((i) => i.source == _sourceFilter).toList();
        }

        // 3. Filter by Selected Date Range
        if (_selectedDateRange != null) {
          final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
          items = items.where((i) =>
              i.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
              i.date.isBefore(end.add(const Duration(seconds: 1)))
          ).toList();
        }

        // 4. Sort by chosen criteria
        items.sort((a, b) {
          switch (_sortBy) {
            case 'Date (Oldest)':
              return a.date.compareTo(b.date);
            case 'Date (Newest)':
            default:
              return b.date.compareTo(a.date);
          }
        });

        final searchField = TextField(
          decoration: const InputDecoration(
            hintText: 'Search order # or customer...',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        );

        final sourceDropdown = DropdownButtonFormField<String>(
          initialValue: _sourceFilter,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Source',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: const ['All', 'POS', 'Customer Menu']
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _sourceFilter = v ?? 'All'),
        );

        final sortDropdown = DropdownButtonFormField<String>(
          initialValue: _sortBy,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sort By',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: const [
            'Date (Newest)',
            'Date (Oldest)',
          ].map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              )).toList(),
          onChanged: (v) => setState(() => _sortBy = v ?? 'Date (Newest)'),
        );

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            side: BorderSide(color: _selectedDateRange != null ? AppColors.accent : AppColors.border),
          ),
        );

        return SectionPage(children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 860) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: searchField),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: sourceDropdown),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: sortDropdown),
                    const SizedBox(width: 10),
                    dateFilterButton,
                    if (_selectedDateRange != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.danger),
                        tooltip: 'Clear Date Filter',
                        onPressed: () => setState(() => _selectedDateRange = null),
                      ),
                    ],
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
                        Expanded(child: sourceDropdown),
                        const SizedBox(width: 10),
                        Expanded(child: sortDropdown),
                      ],
                    ),
                    const SizedBox(height: 10),
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
            },
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No completed orders match the current filter/search.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                ),
              ),
            )
          else
            PaginatedList<_OrderHistoryItem>(
              items: items,
              pageSize: 6,
              itemBuilder: (context, item) {
                final t = item.transaction;
                final isAdmin = data.currentUser?.role == UserRole.admin;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isPhone = constraints.maxWidth < 650;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.cardWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppShadows.soft,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isPhone) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        '#${item.displayId}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: AppColors.darkBrown,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.beige,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.beigeDark, width: 0.6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              item.source == 'POS'
                                                  ? Icons.point_of_sale_outlined
                                                  : Icons.storefront_outlined,
                                              size: 12,
                                              color: AppColors.darkBrown,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              item.source,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.darkBrown,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const StatusBadge(status: 'Completed'),
                                if (t.linkedReceipt != null) ...[
                                  const SizedBox(width: 6),
                                  OrderCardReceipt(receipt: t.linkedReceipt, showWhenMissing: false),
                                ],
                                if (t.proofOfPaymentBase64 != null) ...[
                                  const SizedBox(width: 6),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.darkBrown,
                                      side: const BorderSide(color: AppColors.beigeDark, width: 1.1),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text('GCash Receipt — #${t.displayOrderNumber}'),
                                          content: SizedBox(
                                            width: 360,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: Image.memory(base64Decode(t.proofOfPaymentBase64!), fit: BoxFit.contain),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                                          ],
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.receipt_long_outlined, size: 14),
                                    label: const Text('View GCash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '#${item.displayId}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: AppColors.darkBrown,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.beige,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.beigeDark, width: 0.6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              item.source == 'POS'
                                                  ? Icons.point_of_sale_outlined
                                                  : Icons.storefront_outlined,
                                              size: 11,
                                              color: AppColors.darkBrown,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              item.source,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.darkBrown,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const StatusBadge(status: 'Completed'),
                                    if (t.linkedReceipt != null) ...[
                                      const SizedBox(width: 4),
                                      OrderCardReceipt(receipt: t.linkedReceipt, showWhenMissing: false),
                                    ],
                                    if (t.proofOfPaymentBase64 != null) ...[
                                      const SizedBox(width: 4),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.darkBrown,
                                          side: const BorderSide(color: AppColors.beigeDark, width: 1.1),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: Text('GCash Receipt — #${t.displayOrderNumber}'),
                                              content: SizedBox(
                                                width: 360,
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Image.memory(base64Decode(t.proofOfPaymentBase64!), fit: BoxFit.contain),
                                                ),
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                                              ],
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.receipt_long_outlined, size: 14),
                                        label: const Text('View GCash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        item.customerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                          color: AppColors.darkBrown,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (AppData.instance.isCustomerLoyalById(t.customerId) ||
                                        AppData.instance.isCustomerLoyalByName(item.customerName)) ...[
                                      const SizedBox(width: 4),
                                      const LoyalBadge(),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatDateTime(t.timestamp),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1, color: AppColors.beige),
                          const SizedBox(height: 8),
                          if (!isPhone) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showOrderListModal(context, t),
                                  icon: const Icon(Icons.list_alt_rounded, size: 16),
                                  label: Text('Order List (${t.items.fold(0, (s, i) => s + i.quantity)} items)'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.darkBrown,
                                    side: const BorderSide(color: AppColors.beigeDark),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Payment: ${t.paymentMethod ?? 'Pay at Counter'} · Cashier: ${t.cashier}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.end,
                                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            peso(t.total),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15.5,
                                              color: AppColors.darkBrown,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isAdmin) ...[
                                        const SizedBox(width: 10),
                                        IconButton(
                                          icon: const Icon(Icons.archive_outlined, size: 20, color: AppColors.info),
                                          tooltip: 'Archive order',
                                          onPressed: () => _confirmArchive(context, item),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showOrderListModal(context, t),
                                  icon: const Icon(Icons.list_alt_rounded, size: 15),
                                  label: Text('Items (${t.items.fold(0, (s, i) => s + i.quantity)})'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.darkBrown,
                                    side: const BorderSide(color: AppColors.beigeDark),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      peso(t.total),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: AppColors.darkBrown,
                                      ),
                                    ),
                                    if (isAdmin) ...[
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.info),
                                        tooltip: 'Archive order',
                                        onPressed: () => _confirmArchive(context, item),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Payment: ${t.paymentMethod ?? 'Pay at Counter'} · Cashier: ${t.cashier}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ]);
      },
    );
  }
}
