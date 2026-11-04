import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/app_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/customer_order_widgets.dart';
import '../../widgets/receipt_widgets.dart';
import '../../widgets/shared_widgets.dart';

/// A single row in the customer's consolidated Order History — built from
/// either a Kiosk order (Pending/Declined/Expired/Cancelled) or a completed
/// transaction (Completed).
class _OrderHistoryEntry {
  final String id;
  final String displayId;
  final List<CartItem> items;
  final double total;
  final String status;
  final DateTime date;
  final String? declineReason;
  final ReceiptRecord? receipt;

  _OrderHistoryEntry({
    required this.id,
    required this.displayId,
    required this.items,
    required this.total,
    required this.status,
    required this.date,
    this.declineReason,
    this.receipt,
  });
}

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Completed', 'Cancelled'];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final myId = data.currentUser?.id;

        final entries = <_OrderHistoryEntry>[
          if (myId != null) ...[
            ...data.kioskOrders
                .where(
                  (order) =>
                      order.customerId == myId &&
                      (order.status == 'Pending' ||
                          order.status == 'Declined' ||
                          order.status == 'Expired' ||
                          order.status == 'Cancelled'),
                )
                .map(
                  (order) => _OrderHistoryEntry(
                    id: order.id,
                    displayId: order.displayOrderNumber,
                    items: order.items,
                    total: order.total,
                    status: order.status,
                    date: order.createdAt,
                    declineReason: order.declineReason,
                  ),
                ),
            ...data.transactions
                .where(
                  (transaction) =>
                      transaction.customerId == myId &&
                      transaction.items.isNotEmpty,
                )
                .map(
                  (transaction) => _OrderHistoryEntry(
                    id: transaction.id,
                    displayId: transaction.displayOrderNumber,
                    items: transaction.items,
                    total: transaction.total,
                    status: 'Completed',
                    date: transaction.timestamp,
                    receipt: transaction.linkedReceipt,
                  ),
                ),
          ],
        ]..sort((a, b) => b.date.compareTo(a.date));

        final filteredEntries = entries.where((entry) {
          if (_selectedCategory == 'Completed') {
            return entry.status == 'Completed';
          }
          if (_selectedCategory == 'Cancelled') {
            return entry.status == 'Cancelled' ||
                entry.status == 'Declined' ||
                entry.status == 'Expired';
          }
          return true;
        }).toList();

        return SectionPage(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _categories
                    .map(
                      (category) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = category),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
            if (filteredEntries.isEmpty)
              _HistoryEmptyState(hasAnyOrders: entries.isNotEmpty),
            PaginatedList<_OrderHistoryEntry>(
              items: filteredEntries,
              pageSize: 8,
              itemBuilder: (context, entry) => Container(
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
                    // Header Row: Order Number, Date, Status Badge, Archive Button
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${entry.displayId}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: AppColors.darkBrown,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatDateTime(entry.date),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(status: entry.status),
                        if (entry.receipt != null) ...[
                          const SizedBox(width: 6),
                          OrderCardReceipt(receipt: entry.receipt, showWhenMissing: false),
                        ],
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _confirmArchive(
                            context,
                            entry: entry,
                            currentUser: data.currentUser,
                            customerId: myId,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.archive_outlined,
                              size: 16,
                              color: AppColors.darkBrown,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: AppColors.beige),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showOrderListModal(context, entry),
                          icon: const Icon(Icons.list_alt_rounded, size: 16),
                          label: Text('Order List (${entry.items.fold(0, (s, i) => s + i.quantity)} items)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkBrown,
                            side: const BorderSide(color: AppColors.beigeDark),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Order Total',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                peso(entry.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: AppColors.darkBrown,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (entry.declineReason != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.beige,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.beigeDark, width: 0.8),
                        ),
                        child: Text(
                          'Reason: ${entry.declineReason}',
                          style: const TextStyle(
                            color: AppColors.darkBrown,
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showOrderListModal(BuildContext context, _OrderHistoryEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Order #${entry.displayId} — Items'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomerOrderItems(items: entry.items),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Items:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 13)),
                    Text('${entry.items.fold(0, (s, i) => s + i.quantity)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Total:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown, fontSize: 14)),
                    Text(peso(entry.total), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.darkBrown, fontSize: 16)),
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

  Future<void> _confirmArchive(
    BuildContext context, {
    required _OrderHistoryEntry entry,
    required AppUser? currentUser,
    required String? customerId,
  }) async {
    final archive = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.archive_outlined, color: AppColors.info),
        ),
        title: const Text('Archive this order?'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 380,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Text(
              'Order #${entry.displayId} will move to your Archive and no longer appear in Order History.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep in history'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.archive_outlined, size: 17),
            label: const Text('Archive order'),
          ),
        ],
      ),
    );
    if (archive != true) return;

    await AppData.instance.archiveCustomerOrder(
      entry.id,
      entry.displayId,
      '${entry.items.length} items - Total: ${peso(entry.total)}',
      entry.status,
      archivedBy: currentUser?.fullName ?? 'Customer',
      originalCustomerId: customerId,
    );
    if (context.mounted) {
      showAppSnack(context, 'Order #${entry.displayId} archived successfully.');
    }
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({required this.hasAnyOrders});

  final bool hasAnyOrders;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.history_rounded,
            size: 30,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 10),
          Text(
            hasAnyOrders ? 'No orders in this filter' : 'Your history is empty',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            hasAnyOrders
                ? 'Choose another status to see your past orders.'
                : 'Completed orders and receipts will show up here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
