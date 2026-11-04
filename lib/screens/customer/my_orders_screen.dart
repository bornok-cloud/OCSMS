import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/app_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/customer_order_widgets.dart';
import '../../widgets/receipt_widgets.dart';
import '../../widgets/shared_widgets.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final myId = data.currentUser?.id;
        final myOrders = data.kioskOrders
            .where(
              (order) =>
                  myId != null &&
                  order.customerId == myId &&
                  (order.status == 'Pending' ||
                      order.status == 'Preparing' ||
                      order.status == 'Ready'),
            )
            .toList();

        return SectionPage(
          children: [
            Text(
              'Active orders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Follow each order as it moves from the counter to your table.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (myOrders.isEmpty)
              const _OrderEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No active orders',
                message: 'Your new orders will appear here.',
              ),
            PaginatedList<OrderRecord>(
              items: myOrders,
              pageSize: 5,
              itemBuilder: (context, order) {
                final statusMessage = switch (order.status) {
                  'Ready' => (
                      Icons.storefront_outlined,
                      'Ready for collection',
                      'Your order is ready. Please collect it at the counter.',
                      AppColors.success,
                    ),
                  'Preparing' => (
                      Icons.restaurant_outlined,
                      'Being prepared',
                      'The café team is preparing your order.',
                      AppColors.info,
                    ),
                  _ => (
                      Icons.hourglass_bottom_rounded,
                      'Awaiting confirmation',
                      'Show your Order ID to the counter staff to confirm and pay.',
                      AppColors.warning,
                    ),
                };

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
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${order.displayOrderNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppColors.darkBrown,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatDateTime(order.createdAt),
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(status: order.status),
                          if (order.linkedReceipt != null) ...[
                            const SizedBox(width: 6),
                            OrderCardReceipt(receipt: order.linkedReceipt),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          CustomerOrderInfoChip(
                            icon: order.orderType == 'Pickup'
                                ? Icons.shopping_bag_outlined
                                : order.orderType == 'Take Out'
                                    ? Icons.takeout_dining_outlined
                                    : Icons.restaurant_outlined,
                            label: order.orderType,
                          ),
                          CustomerOrderInfoChip(
                            icon: order.paymentMethod == 'Cash' ||
                                    order.paymentMethod == 'Pay at Counter'
                                ? Icons.payments_outlined
                                : order.paymentMethod == 'Split Payment'
                                    ? Icons.call_split_rounded
                                    : Icons.qr_code_2_outlined,
                            label: order.paymentMethod,
                          ),
                          if (order.extractedReferenceId != null && order.extractedReferenceId!.isNotEmpty)
                            CustomerOrderInfoChip(
                              icon: Icons.tag_rounded,
                              label: 'Ref: ${order.extractedReferenceId}',
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: AppColors.beige),
                      const SizedBox(height: 8),
                      CustomerOrderItems(items: order.items),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.beige,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.beigeDark, width: 0.6),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              statusMessage.$1,
                              size: 16,
                              color: AppColors.darkBrown,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    statusMessage.$2,
                                    style: const TextStyle(
                                      color: AppColors.darkBrown,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  Text(
                                    statusMessage.$3,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10.5,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: AppColors.beige),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Order Total',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Text(
                            peso(order.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              color: AppColors.darkBrown,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      if (order.isPartialPayment) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Amount Paid (Deposit via GCash)',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Text(
                              peso(order.partialAmountPaid!),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppColors.darkBrown,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Remaining Balance (Due at Counter)',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Text(
                              peso(order.remainingBalance),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (order.status == 'Pending') ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.darkBrown,
                              side: const BorderSide(color: AppColors.darkBrown),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: const Size(48, 36),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 15),
                            label: const Text('Cancel Order', style: TextStyle(fontSize: 11.5)),
                            onPressed: () async {
                              final reason = await showDialog<String>(
                                context: context,
                                builder: (ctx) => CancelOrderDialog(order: order),
                              );
                              if (reason != null && context.mounted) {
                                await AppData.instance.cancelKioskOrder(
                                  order.id,
                                  reason: reason,
                                );
                                if (context.mounted) {
                                  showAppSnack(
                                    context,
                                    'Order #${order.displayOrderNumber} has been cancelled.',
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
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

class _OrderEmptyState extends StatelessWidget {
  const _OrderEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.beige,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, color: AppColors.brown, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            message,
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
