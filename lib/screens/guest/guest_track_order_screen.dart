import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';

class GuestTrackOrderScreen extends StatefulWidget {
  const GuestTrackOrderScreen({super.key, this.initialOrderNumber});

  final String? initialOrderNumber;

  @override
  State<GuestTrackOrderScreen> createState() => _GuestTrackOrderScreenState();
}

class _GuestTrackOrderScreenState extends State<GuestTrackOrderScreen> {
  late final TextEditingController _ctrl;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialOrderNumber ?? '');
    if (_ctrl.text.trim().isNotEmpty) {
      _submitted = true;
    }
  }

  @override
  void didUpdateWidget(covariant GuestTrackOrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialOrderNumber != null && widget.initialOrderNumber != oldWidget.initialOrderNumber) {
      _ctrl.text = widget.initialOrderNumber!;
      _submitted = true;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'preparing':
        return Colors.orange.shade800;
      case 'ready':
      case 'completed':
        return AppColors.success;
      case 'declined':
      case 'cancelled':
      case 'expired':
        return AppColors.danger;
      default:
        return AppColors.darkBrown;
    }
  }

  Widget _buildStatusStepper(String status) {
    final s = status.toLowerCase();
    int currentStep = 0;
    if (s == 'preparing') currentStep = 1;
    if (s == 'ready') currentStep = 2;
    if (s == 'completed') currentStep = 3;
    if (s == 'declined' || s == 'cancelled' || s == 'expired') currentStep = -1;

    if (currentStep == -1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
            const SizedBox(width: 6),
            Text(
              'Status: ${status.toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: AppColors.danger),
            ),
          ],
        ),
      );
    }

    const steps = ['Pending', 'Preparing', 'Ready', 'Complete'];
    return Row(
      children: List.generate(steps.length, (i) {
        final active = i <= currentStep;
        final isCurrent = i == currentStep;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: active ? Colors.black : AppColors.beige,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCurrent ? Colors.black : Colors.transparent,
                          width: 1.8,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        i < currentStep ? Icons.check_rounded : (i == currentStep ? Icons.radio_button_checked_rounded : Icons.circle),
                        size: i == currentStep ? 11 : 6,
                        color: active ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                        color: active ? Colors.black : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < currentStep ? Colors.black : AppColors.beigeDark,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildOrderDetails(OrderRecord order) {
    final itemCount = order.items.fold(0, (s, i) => s + i.quantity);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ORDER REFERENCE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${order.displayOrderNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.darkBrown),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(order.status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  order.status.toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5, color: _statusColor(order.status), letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildStatusStepper(order.status),
          const Divider(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Customer Name', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text(order.customerName ?? 'Walk-in Guest', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Order Type', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text(order.orderType, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Payment Method', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text(order.paymentMethod, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
          const Divider(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items ($itemCount total)', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1.0)),
              Text(peso(order.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.darkBrown)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 75,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: order.items.length,
                itemBuilder: (ctx, idx) {
                  final item = order.items[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.quantity}x ${item.product.name}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          peso(item.subtotal),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  OrderRecord _transactionToRecord(TransactionRecord tx) {
    final ref = tx.orderNumber ?? (tx.id.length > 4 ? tx.id.substring(tx.id.length - 4) : tx.id);
    return OrderRecord(
      id: tx.id,
      items: tx.items,
      source: 'Kiosk',
      status: 'Completed',
      createdAt: tx.timestamp,
      customerName: tx.customerName,
      paymentMethod: tx.paymentMethod ?? 'Cash',
      orderNumber: ref,
      orderType: tx.orderType ?? 'Dine In',
      discount: tx.discount,
      receipt: tx.receipt,
      isGuest: tx.isGuest,
      tableNumber: tx.tableNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 1.2),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'Enter Reference ID (e.g. #1042)',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onSubmitted: (_) => setState(() => _submitted = true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => setState(() => _submitted = true),
                          child: const Text('Track', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: AppData.instance,
                      builder: (context, _) {
                        final rawQuery = _ctrl.text.trim().toUpperCase();
                        final query = rawQuery.startsWith('#') ? rawQuery.substring(1) : rawQuery;
                        OrderRecord? match;
                        if (query.isNotEmpty) {
                          try {
                            match = AppData.instance.kioskOrders.firstWhere(
                              (o) =>
                                  o.displayOrderNumber.toUpperCase() == query ||
                                  o.id.toUpperCase() == query ||
                                  (o.orderNumber != null && o.orderNumber!.toUpperCase() == query),
                            );
                          } catch (_) {
                            try {
                              final tx = AppData.instance.transactions.firstWhere(
                                (t) =>
                                    t.id.toUpperCase() == query ||
                                    (t.orderNumber != null && t.orderNumber!.toUpperCase() == query),
                              );
                              match = _transactionToRecord(tx);
                            } catch (_) {
                              match = null;
                            }
                          }
                        }

                        if (!_submitted && query.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_rounded, size: 40, color: AppColors.textMuted),
                                const SizedBox(height: 8),
                                const Text(
                                  'Enter your Order Reference ID above',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }

                        if (match == null) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off_rounded, size: 40, color: AppColors.textMuted),
                                const SizedBox(height: 8),
                                const Text(
                                  'Order Not Found',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkBrown),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'No active or completed order matches "${_ctrl.text.trim()}".',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          );
                        }

                        return _buildOrderDetails(match);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
