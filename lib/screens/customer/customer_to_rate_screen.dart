import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/receipt_widgets.dart';
import '../../widgets/customer_order_widgets.dart';
import '../../models/models.dart';

class CustomerToRateScreen extends StatefulWidget {
  const CustomerToRateScreen({super.key});

  @override
  State<CustomerToRateScreen> createState() => _CustomerToRateScreenState();
}

class _CustomerToRateScreenState extends State<CustomerToRateScreen> {
  String _selectedTab = 'To Rate'; // 'To Rate' or 'My Reviews'

  void _showOrderListModal(BuildContext context, String orderNumber, List<CartItem> items, double total) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Order #$orderNumber — Items'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomerOrderItems(items: items),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Items:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 13)),
                    Text('${items.fold(0, (s, i) => s + i.quantity)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Total:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown, fontSize: 14)),
                    Text(peso(total), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.darkBrown, fontSize: 16)),
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

  void _showFeedbackDialog(BuildContext context, TransactionRecord t) {
    int rating = 0;
    String category = 'Service';
    final commentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            title: Text('Feedback for Order #${t.displayOrderNumber}'),
            content: SizedBox(
              width: MediaQuery.sizeOf(ctx).width * 0.84,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: StarRating(
                      rating: rating,
                      size: 30,
                      onChanged: (r) => setDialogState(() => rating = r),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items:
                        const [
                              'Service',
                              'Food Quality',
                              'Cleanliness',
                              'Ambiance',
                              'Other',
                            ]
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                    onChanged: (v) =>
                        setDialogState(() => category = v ?? category),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Write your feedback...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (rating == 0) {
                    showAppSnack(
                      context,
                      'Please select a star rating.',
                      success: false,
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await AppData.instance.submitFeedback(
                      customerName:
                          AppData.instance.currentUser?.fullName ?? 'Customer',
                      rating: rating,
                      comment: commentCtrl.text.trim(),
                      category: category,
                      customerId: AppData.instance.currentUser?.id,
                      orderId: t.id,
                    );
                    if (context.mounted) {
                      showAppSnack(context, 'Feedback submitted successfully.');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showAppSnack(
                        context,
                        'Failed to submit feedback: $e',
                        success: false,
                      );
                    }
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          );
        },
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
        final myTransactions = data.transactions
            .where(
              (t) => myId != null && t.items.isNotEmpty && t.customerId == myId,
            )
            .toList();
        final unreviewedTransactions = myTransactions
            .where((t) => data.feedbackForOrder(t.id) == null)
            .toList();
        final reviewedTransactions = myTransactions
            .where((t) => data.feedbackForOrder(t.id) != null)
            .toList();

        return SectionPage(
          children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'To Rate (${unreviewedTransactions.length})',
                          ),
                        ),
                        selected: _selectedTab == 'To Rate',
                        onSelected: (_) =>
                            setState(() => _selectedTab = 'To Rate'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ChoiceChip(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'My Reviews (${reviewedTransactions.length})',
                          ),
                        ),
                        selected: _selectedTab == 'My Reviews',
                        onSelected: (_) =>
                            setState(() => _selectedTab = 'My Reviews'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_selectedTab == 'To Rate') ...[
                if (unreviewedTransactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No completed orders pending review.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                PaginatedList<TransactionRecord>(
                  items: unreviewedTransactions.reversed.toList(),
                  pageSize: 6,
                  itemBuilder: (context, t) {
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
                                  Icons.check_circle_outline,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Order #${t.displayOrderNumber}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (t.linkedReceipt != null)
                                        OrderCardReceipt(receipt: t.linkedReceipt),
                                    ],
                                  ),
                                ),
                                Text(
                                  peso(t.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Completed on ${t.timestamp.month}/${t.timestamp.day}/${t.timestamp.year} at ${t.timestamp.hour.toString().padLeft(2, '0')}:${t.timestamp.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const Divider(),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showOrderListModal(context, t.displayOrderNumber, t.items, t.total),
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
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _showFeedbackDialog(context, t),
                                  icon: const Icon(
                                    Icons.rate_review_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Send Feedback'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ] else ...[
                if (reviewedTransactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No reviewed orders yet.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                PaginatedList<TransactionRecord>(
                  items: reviewedTransactions.reversed.toList(),
                  pageSize: 6,
                  itemBuilder: (context, t) {
                    final feedback = data.feedbackForOrder(t.id);
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
                                  Icons.check_circle_outline,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Order #${t.displayOrderNumber}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (t.linkedReceipt != null)
                                        OrderCardReceipt(receipt: t.linkedReceipt),
                                    ],
                                  ),
                                ),
                                Text(
                                  peso(t.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Completed on ${t.timestamp.month}/${t.timestamp.day}/${t.timestamp.year}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const Divider(),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showOrderListModal(context, t.displayOrderNumber, t.items, t.total),
                                  icon: const Icon(Icons.list_alt_rounded, size: 16),
                                  label: Text('Order List (${t.items.fold(0, (s, i) => s + i.quantity)} items)'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.darkBrown,
                                    side: const BorderSide(color: AppColors.beigeDark),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                            if (feedback != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.beige,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Your Review',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Spacer(),
                                        StarRating(
                                          rating: feedback.rating,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatDateTime(feedback.date),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    if (feedback.comment.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        feedback.comment,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                    if (feedback.reply != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Café reply: ${feedback.reply}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          );
      },
    );
  }
}
