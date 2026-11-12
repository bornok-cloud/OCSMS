import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/payment_config.dart';
import '../../services/gcash_parser.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/receipt_widgets.dart';
import '../../models/models.dart';

/// Employee-facing view of incoming kiosk orders. Accepting an order (once
/// stock is confirmed sufficient and payment verified) opens an editable Receipt modal
/// built from that order; pressing Done there saves the receipt on the order,
/// moves it to Preparing and opens the Order Status Workflow modal,
/// which steps the order through Preparing -> Orders Ready -> Orders
/// Complete. Stock is deducted the moment the order enters Preparing;
/// Orders Complete only finalizes the sale so it shows as completed for
/// the customer — it does not touch stock again.
///
/// A pending order is first reviewed through the "Preview Order" modal,
/// which shows the full order details, available add-ons, and a "Mode of
/// Payment" step (Cash / GCash / Multi Payment). Once a payment method is
/// recorded, the modal reveals "Decline Order" and "Accept Order" — Accept
/// hands the order off to the existing accept flow, Decline opens the
/// existing decline-reason modal.
/// What the employee confirmed in the payment-verification step for one
/// order — the figures the Receipt is generated from.
class _PaymentOutcome {
  const _PaymentOutcome({
    required this.total,
    required this.amountPaid,
    this.cashTendered,
    this.gcashAmount,
    this.change = 0,
  });
  final double total;
  final double amountPaid;
  final double? cashTendered;
  final double? gcashAmount;
  final double change;
}

/// Cash + GCash figures typed into the Split Payment dialog.
class _SplitInput {
  const _SplitInput(this.gcash, this.cashTendered, this.cashDue, this.change);
  final double gcash;
  final double cashTendered;
  final double cashDue;
  final double change;
}

class KioskManagementScreen extends StatelessWidget {
  final bool onlyPending;
  const KioskManagementScreen({super.key, this.onlyPending = false});

  static void _viewProof(BuildContext context, OrderRecord o) {
    final bytes = o.proofOfPaymentBase64;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Proof of Payment — Order #${o.displayOrderNumber}'),
        content: bytes == null
            ? const Text('No proof of payment was attached to this order.')
            : SizedBox(
                width: 360,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(base64Decode(bytes), fit: BoxFit.contain),
                ),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Display-only label for an order's `source`. The stored value stays
  /// 'Kiosk' (it drives ordering logic); only the text shown changes.
  static String _sourceLabel(String source) => source == 'Kiosk' ? 'Kitchen' : source;

  List<double> _getSmartCashSuggestions(double total) {
    if (total <= 0) return [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0];

    final set = <double>{};

    // Standard Philippine bills (up to 1000, no 2000 bill exists in PH)
    for (final bill in [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]) {
      if (bill >= total) {
        set.add(bill);
      }
    }

    // Exact amount
    set.add(double.parse(total.toStringAsFixed(2)));

    // Smart rounded multiples (e.g., 69 -> 70, 75, 80, 100)
    double m5 = (total / 5.0).ceil() * 5.0;
    if (m5 >= total && m5 - total <= 25) set.add(m5);

    double m10 = (total / 10.0).ceil() * 10.0;
    if (m10 >= total && m10 - total <= 35) set.add(m10);

    double m20 = (total / 20.0).ceil() * 20.0;
    if (m20 >= total && m20 - total <= 45) set.add(m20);

    double m50 = (total / 50.0).ceil() * 50.0;
    if (m50 >= total && m50 - total <= 100) set.add(m50);

    double m100 = (total / 100.0).ceil() * 100.0;
    if (m100 >= total && m100 - total <= 200) set.add(m100);

    final list = set.toList()..sort();
    return list;
  }

  static Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(label,
                    style: const TextStyle(color: AppColors.textMuted))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Future<void> _decline(BuildContext context, OrderRecord o) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Decline Order #${o.displayOrderNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason. This will be shown to the customer.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. Payment amount does not match the order total',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: const Text('Confirm Decline'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    if (!context.mounted) return;
    await AppData.instance.declineKioskOrder(o.id, reason: reason);
    if (!context.mounted) return;
    showAppSnack(context, 'Order #${o.displayOrderNumber} declined.', success: false);
  }

  /// Products on the order whose live stock can no longer cover the
  /// quantity ordered (includes items that have since gone Out of Stock).
  /// Does not modify stock in any way — read-only check.
  List<Product> _insufficientStockItems(AppData data, OrderRecord o) {
    final problems = <Product>[];
    for (final item in o.items) {
      Product live = item.product;
      try {
        live = data.products.firstWhere((p) => p.id == item.product.id);
      } catch (_) {
        // Fall back to the snapshot captured on the order itself.
      }
      if (live.stockQuantity < item.quantity) {
        problems.add(live);
      }
    }
    return problems;
  }

  Future<_PaymentOutcome?> _verifyPaymentBeforeAccept(BuildContext context, OrderRecord o) async {
    if (o.paymentMethod == 'Cash' || o.paymentMethod == 'Pay at Counter') {
      final controller = TextEditingController(text: o.total.toStringAsFixed(2));
      final cashGiven = await showDialog<double>(
        context: context,
        builder: (ctx) {
          String? errorMsg;
          return StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: Text('Cash Payment — Order #${o.displayOrderNumber}'),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Amount: ${peso(o.total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      const Text('Enter cash amount given by customer:'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixText: '₱ ',
                          labelText: 'Cash Tendered',
                        ),
                        onChanged: (_) => setDialogState(() => errorMsg = null),
                      ),
                      const SizedBox(height: 12),
                      const Text('Quick Select Amount:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _getSmartCashSuggestions(o.total).map((amt) {
                          final label = amt == amt.roundToDouble() ? '₱${amt.toStringAsFixed(0)}' : '₱${amt.toStringAsFixed(2)}';
                          return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              controller.text = amt.toStringAsFixed(2);
                              setDialogState(() => errorMsg = null);
                            },
                            child: Text(label),
                          );
                        }).toList(),
                      ),
                      if (errorMsg != null) ...[
                        const SizedBox(height: 8),
                        Text(errorMsg!, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    final val = double.tryParse(controller.text.trim()) ?? -1;
                    if (val < o.total) {
                      setDialogState(() => errorMsg = 'Insufficient cash! Cash tendered must be at least ${peso(o.total)}.');
                      return;
                    }
                    Navigator.pop(ctx, val);
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          );
        },
      );

      if (cashGiven == null || cashGiven < o.total) return null;

      final change = (cashGiven - o.total).clamp(0.0, double.infinity);

      if (!context.mounted) return null;

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change Calculation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Total Amount', peso(o.total)),
              _infoRow('Cash Tendered', peso(cashGiven)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Change:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    change == 0 ? '₱0.00' : peso(change),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.success),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Accept'),
            ),
          ],
        ),
      );
      return _PaymentOutcome(
        total: o.total,
        amountPaid: cashGiven,
        cashTendered: cashGiven,
        change: change,
      );
    } else if (o.paymentMethod == 'Split Payment' || o.paymentMethod == 'Multi Payment') {
      final defaultGcash = o.extractedAmount ?? 0.0;
      final gcashController = TextEditingController(
        text: defaultGcash > 0 ? defaultGcash.toStringAsFixed(2) : '',
      );
      final cashTenderedController = TextEditingController();
      final input = await showDialog<_SplitInput>(
        context: context,
        builder: (ctx) {
          String? errorMsg;
          return StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: Text('Split Payment — Order #${o.displayOrderNumber}'),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Order Amount: ${peso(o.total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 10),
                      const Text('1. Preview GCash Receipt:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () => KioskManagementScreen._viewProof(ctx, o),
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('View GCash Receipt'),
                      ),
                      const SizedBox(height: 14),
                      const Text('2. Input GCash Amount Sent:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: gcashController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixText: '₱ ',
                          labelText: 'GCash Amount',
                        ),
                        onChanged: (_) => setDialogState(() => errorMsg = null),
                      ),
                      const SizedBox(height: 12),
                      const Text('3. Input Cash Tendered by Customer:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: cashTenderedController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixText: '₱ ',
                          labelText: 'Cash Tendered',
                        ),
                        onChanged: (_) => setDialogState(() => errorMsg = null),
                      ),
                      const SizedBox(height: 12),
                      const Text('Quick Select Amount:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _getSmartCashSuggestions((o.total - (double.tryParse(gcashController.text.trim()) ?? 0.0)).clamp(0.0, double.infinity)).map((amt) {
                          final label = amt == amt.roundToDouble() ? '₱${amt.toStringAsFixed(0)}' : '₱${amt.toStringAsFixed(2)}';
                          return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              cashTenderedController.text = amt.toStringAsFixed(2);
                              setDialogState(() => errorMsg = null);
                            },
                            child: Text(label),
                          );
                        }).toList(),
                      ),
                      if (errorMsg != null) ...[
                        const SizedBox(height: 10),
                        Text(errorMsg!, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    final gcashAmt = double.tryParse(gcashController.text.trim()) ?? 0.0;
                    final cashTendered = double.tryParse(cashTenderedController.text.trim()) ?? 0.0;
                    
                    if ((gcashAmt + cashTendered) < o.total) {
                      setDialogState(() => errorMsg = 'Insufficient payment! Total paid (GCash + Cash) must be at least ${peso(o.total)}.');
                      return;
                    }

                    final cashDue = (o.total - gcashAmt).clamp(0.0, double.infinity);
                    if (cashTendered < cashDue) {
                      setDialogState(() => errorMsg = 'Insufficient cash tendered for remaining balance of ${peso(cashDue)}.');
                      return;
                    }

                    final change = (cashTendered - cashDue).clamp(0.0, double.infinity);

                    Navigator.pop(ctx, _SplitInput(gcashAmt, cashTendered, cashDue, change));
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          );
        },
      );
      if (input == null) return null;
      if (!context.mounted) return null;

      // Change Due modal — wait for the cashier's Accept before moving on.
      await showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Split Payment — Change Due'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Total Amount', peso(o.total)),
              _infoRow('GCash Paid', peso(input.gcash)),
              _infoRow('Cash Balance Due', peso(input.cashDue)),
              _infoRow('Cash Tendered', peso(input.cashTendered)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Change:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    input.change == 0 ? '₱0.00' : peso(input.change),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.success),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Accept'),
            ),
          ],
        ),
      );
      return _PaymentOutcome(
        total: o.total,
        amountPaid: input.gcash + input.cashTendered,
        cashTendered: input.cashTendered,
        gcashAmount: input.gcash,
        change: input.change,
      );
    } else if (o.paymentMethod == 'GCash' || o.paymentMethod.contains('Partial')) {
      final isPartial = o.paymentMethod.contains('Partial') || o.isPartialPayment;
      final defaultAmount = o.partialAmountPaid ?? (isPartial ? o.total * 0.5 : o.total);

      final refController = TextEditingController(text: o.extractedReferenceId ?? '');
      final amountController = TextEditingController(
        text: (o.extractedAmount ?? defaultAmount).toStringAsFixed(2),
      );
      final dateController = TextEditingController(text: o.extractedDateTime ?? '');

      final gcashSent = await showDialog<double>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: AppColors.cardWhite,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (ctx, setModalState) {
                bool isEditable = false;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.qr_code_2_outlined,
                            color: AppColors.accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPartial ? 'Verify Partial GCash Deposit' : 'Verify GCash Payment',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.darkBrown,
                                ),
                              ),
                              Text(
                                'Order #${o.displayOrderNumber}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.beige,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.beigeDark),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Total Order Amount:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.darkBrown)),
                                      Text(peso(o.total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                                    ],
                                  ),
                                  if (isPartial) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Deposit Amount (GCash):', style: TextStyle(fontSize: 11.5, color: AppColors.accent, fontWeight: FontWeight.bold)),
                                        Text(peso(defaultAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Remaining Balance (due at counter):', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                        Text(peso(o.total - defaultAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.warning)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '1. Review Customer GCash Screenshot:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.darkBrown),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.darkBrown,
                                  side: const BorderSide(color: AppColors.darkBrown),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => KioskManagementScreen._viewProof(ctx, o),
                                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                                label: const Text('Preview GCash Receipt Screenshot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              '2. Verify & Confirm GCash Payment Details:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.darkBrown),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.beige.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.beigeDark),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
                                          const SizedBox(width: 6),
                                          const Text('Extracted Receipt Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.darkBrown)),
                                        ],
                                      ),
                                      IconButton(
                                        icon: Icon(isEditable ? Icons.lock_open_rounded : Icons.edit_outlined, size: 18, color: AppColors.darkBrown),
                                        tooltip: isEditable ? 'Lock details' : 'Edit details',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => setModalState(() => isEditable = !isEditable),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: refController,
                                    enabled: isEditable,
                                    decoration: const InputDecoration(
                                      labelText: 'Reference Number (Ref No.)',
                                      prefixIcon: Icon(Icons.tag_rounded, size: 18),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: amountController,
                                    enabled: isEditable,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Verified GCash Amount (₱)',
                                      prefixIcon: Icon(Icons.payments_outlined, size: 18),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  if (dateController.text.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: dateController,
                                      enabled: isEditable,
                                      decoration: const InputDecoration(
                                        labelText: 'Receipt Date & Time',
                                        prefixIcon: Icon(Icons.access_time_rounded, size: 18),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.darkBrown,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          onPressed: () async {
                            final amount = double.tryParse(amountController.text.trim()) ?? defaultAmount;
                            final refNo = refController.text.trim();
                            final updateData = <String, dynamic>{
                              if (refNo.isNotEmpty) 'extractedReferenceId': refNo,
                              if (dateController.text.trim().isNotEmpty) 'extractedDateTime': dateController.text.trim(),
                            };
                            if (isPartial) {
                              updateData['partialAmountPaid'] = amount;
                              updateData['verifiedTotal'] = null;
                            } else {
                              updateData['verifiedTotal'] = amount;
                            }
                            await FirebaseFirestore.instance.collection('kioskOrders').doc(o.id).update(updateData);
                            if (ctx.mounted) Navigator.pop(ctx, amount);
                          },
                          child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      if (gcashSent == null) return null;
      return _PaymentOutcome(total: o.total, amountPaid: gcashSent, gcashAmount: gcashSent);
    }
    return _PaymentOutcome(total: o.total, amountPaid: o.total);
  }

  Future<void> _handleAcceptOrder(BuildContext context, AppData data, OrderRecord o) async {
    final insufficient = _insufficientStockItems(data, o);
    if (insufficient.isNotEmpty) {
      await _showOutOfStockDialog(context, o, insufficient);
      return;
    }
    final payment = await _verifyPaymentBeforeAccept(context, o);
    if (payment == null) return;
    if (!context.mounted) return;

    // For partial payment orders, do NOT generate a receipt yet. Proceed straight to Preparing status.
    if (o.paymentMethod.contains('Partial') || o.isPartialPayment) {
      await data.updateKioskOrderStage(o.id, 'Preparing');
      if (!context.mounted) return;
      showAppSnack(context, 'Partial payment accepted. Order #${o.displayOrderNumber} set to Preparing.');
      return;
    }

    // Payment confirmed -> generate the receipt from THIS order's own data.
    final cashier = data.currentUser?.fullName ?? 'Staff';
    final generated = ReceiptRecord.fromOrder(
      o,
      total: payment.total,
      amountPaid: payment.amountPaid,
      cashTendered: payment.cashTendered,
      gcashAmount: payment.gcashAmount,
      change: payment.change,
      cashier: cashier,
    );

    // Receipt modal: staff can edit it, print it, then press Done. Cancel
    // (null) leaves the order Pending with nothing saved.
    final finalReceipt = await showReceiptDialog(context, generated, orderTotal: payment.total);
    if (finalReceipt == null) return;
    if (!context.mounted) return;

    // Done -> save the receipt on this order's document only (verified
    // against the stored order/customer ID), then finalize.
    try {
      await data.saveKioskOrderReceipt(o.id, finalReceipt);
    } catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, 'Could not save the receipt for order #${o.displayOrderNumber}: $e', success: false);
      return;
    }
    if (!context.mounted) return;

    // Set ONLY this order to 'Preparing' (deducting stock once, as before),
    // so its "Preview Order" button becomes "Status".
    await data.updateKioskOrderStage(o.id, 'Preparing');
    if (!context.mounted) return;
    showAppSnack(context, 'Order #${o.displayOrderNumber} accepted and set to Preparing.');
  }

  Future<void> _previewOrder(BuildContext context, AppData data, OrderRecord o) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _OrderPreviewModal(order: o),
    );
    if (!context.mounted) return;
    if (result == 'accept') {
      await _handleAcceptOrder(context, data, o);
    } else if (result == 'decline') {
      await _decline(context, o);
    }
  }

  /// Opens the read-only Preview Order modal. Once the employee completes
  /// the Mode of Payment step inside it (which records the chosen payment
  /// method), the modal reveals "Decline Order" / "Accept Order" — the
  /// result tells us which one was pressed so we can route into the
  /// matching existing flow: Accept hands off to the existing accept flow
  /// (stock check -> Order Status Workflow modal); Decline opens the
  /// existing decline-reason modal, which already reflects the reason only
  /// on the correct customer's account via `declineKioskOrder`.


  /// Display label + icon for each in-progress Order Status Workflow step,
  /// used both on the order card's status control and inside the modal.
  (String, IconData) _stageDisplay(String status) {
    switch (status) {
      case 'Preparing':
        return ('Preparing', Icons.restaurant_outlined);
      case 'Ready':
        return ('Orders Ready', Icons.notifications_active_outlined);
      default:
        return (status, Icons.info_outline);
    }
  }

  /// The Order Status Workflow modal: lets the employee move an accepted
  /// order through Preparing -> Orders Ready -> Orders Complete, one step
  /// at a time. Only the next step in the sequence is ever selectable —
  /// earlier steps show as done, later ones stay locked until their turn.
  /// Selecting "Preparing" is what deducts stock (exactly once, right
  /// then); "Orders Ready" just updates the in-progress status; "Orders
  /// Complete" finalizes the sale — creating the transaction the
  /// customer's Complete Orders list is built from — without touching
  /// stock again. Reopening this modal (via the status control on an
  /// in-progress order) picks up exactly where it left off, since it
  /// always reflects the order's live status.
  Future<void> _showOrderStatusModal(BuildContext context, AppData data, String orderId) async {
    await showDialog(
      context: context,
      builder: (dialogCtx) => AnimatedBuilder(
        animation: data,
        builder: (animatedCtx, _) {
          OrderRecord? order;
          for (final candidate in data.kioskOrders) {
            if (candidate.id == orderId) {
              order = candidate;
              break;
            }
          }
          if (order == null) {
            // The order was finalized (or otherwise removed) while this
            // modal was open — nothing left to manage, so close it.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(dialogCtx).canPop()) Navigator.of(dialogCtx).pop();
            });
            return const SizedBox.shrink();
          }
          final o = order;
          // -1 = not started (still 'Pending'), 0 = Preparing done, 1 = Ready done.
          const stages = ['Preparing', 'Ready'];
          final currentIndex = stages.indexOf(o.status);

          return AlertDialog(
            title: Text('Order #${o.displayOrderNumber} — Status'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Move the order forward one step at a time.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 14),
                  if (o.isPartialPayment && !o.isFullyPaid) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.beige,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.beigeDark),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Remaining Balance:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.darkBrown)),
                              Text(peso(o.remainingBalance), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.warning)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.darkBrown,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _showCompletePaymentModal(dialogCtx, data, o),
                            icon: const Icon(Icons.payment_outlined, size: 16),
                            label: const Text('Complete Payment'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  _stageRow(
                    label: 'Preparing',
                    icon: Icons.restaurant_outlined,
                    done: currentIndex >= 0,
                    enabled: currentIndex == -1,
                    onSelect: () => data.updateKioskOrderStage(o.id, 'Preparing'),
                  ),
                  const SizedBox(height: 10),
                  _stageRow(
                    label: 'Orders Ready',
                    icon: Icons.notifications_active_outlined,
                    done: currentIndex >= 1,
                    enabled: currentIndex == 0,
                    onSelect: () => data.updateKioskOrderStage(o.id, 'Ready'),
                  ),
                  const SizedBox(height: 10),
                  _stageRow(
                    label: 'Orders Complete',
                    icon: Icons.check_circle_outline,
                    done: false,
                    enabled: currentIndex == 1 && (!o.isPartialPayment || o.isFullyPaid),
                    onSelect: () async {
                      if (o.isPartialPayment && !o.isFullyPaid) {
                        showAppSnack(
                          dialogCtx,
                          'Please complete remaining payment (${peso(o.remainingBalance)}) using "Complete Payment" first.',
                          success: false,
                        );
                        return;
                      }

                      if (o.receipt == null) {
                        final cashier = data.currentUser?.fullName ?? 'Staff';
                        final generated = ReceiptRecord.fromOrder(
                          o,
                          total: o.total,
                          amountPaid: o.total,
                          cashTendered: o.total,
                          gcashAmount: o.partialAmountPaid,
                          change: 0,
                          cashier: cashier,
                        );

                        final finalReceipt = await showReceiptDialog(
                          dialogCtx,
                          generated,
                          orderTotal: o.total,
                        );
                        if (finalReceipt == null) return;
                        await data.saveKioskOrderReceipt(o.id, finalReceipt);
                      }

                      await data.completeKioskOrder(
                        o.id,
                        cashier: data.currentUser?.fullName ?? 'Staff',
                      );
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      if (dialogCtx.mounted) {
                        showAppSnack(
                          dialogCtx,
                          'Order #${o.displayOrderNumber} completed successfully.',
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCompletePaymentModal(BuildContext context, AppData data, OrderRecord o) async {
    final remaining = o.remainingBalance;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Complete Payment — Order #${o.displayOrderNumber}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Total Order Amount: ${peso(o.total)}'),
              Text('Amount Paid So Far: ${peso(o.totalVerifiedPayments)}', style: const TextStyle(color: AppColors.success)),
              const SizedBox(height: 4),
              Text('Remaining Balance Due: ${peso(remaining)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.warning)),
              const SizedBox(height: 16),
              const Text('Select Payment Method for Remaining Balance:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.qr_code_2_outlined, color: AppColors.accent),
                title: const Text('GCash'),
                subtitle: const Text('Pay remaining balance via GCash'),
                onTap: () => Navigator.pop(ctx, 'GCash'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.money, color: AppColors.brown),
                title: const Text('Cash'),
                subtitle: const Text('Collect remaining balance in cash at counter'),
                onTap: () => Navigator.pop(ctx, 'Cash'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.call_split_outlined, color: AppColors.brown),
                title: const Text('Split Payment (GCash + Cash)'),
                subtitle: const Text('Divide remaining balance between GCash and cash'),
                onTap: () => Navigator.pop(ctx, 'Split'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (choice == null || !context.mounted) return;

    bool paymentConfirmed = false;
    if (choice == 'GCash') {
      final verifiedAmount = await _verifyRemainingGCash(
        context,
        o,
        remaining,
      );
      if (verifiedAmount != null && verifiedAmount > 0) {
        await data.recordAdditionalPayment(o.id, verifiedAmount);
        paymentConfirmed = true;
      }
    } else if (choice == 'Cash') {
      final cashOk = await _verifyRemainingCash(context, o, remaining);
      if (cashOk != null && cashOk > 0) {
        await data.recordAdditionalPayment(o.id, cashOk);
        paymentConfirmed = true;
      }
    } else if (choice == 'Split') {
      final splitOk = await _showSplitRemainingModal(context, o, remaining);
      if (splitOk == true) {
        await data.recordAdditionalPayment(o.id, remaining);
        paymentConfirmed = true;
      }
    }

    if (paymentConfirmed && context.mounted) {
      // Payment confirmed -> Generate official receipt now
      final cashier = data.currentUser?.fullName ?? 'Staff';
      final generated = ReceiptRecord.fromOrder(
        o,
        total: o.total,
        amountPaid: o.total,
        cashTendered: o.total,
        gcashAmount: o.partialAmountPaid,
        change: 0,
        cashier: cashier,
      );

      final finalReceipt = await showReceiptDialog(
        context,
        generated,
        orderTotal: o.total,
      );
      if (finalReceipt != null) {
        await data.saveKioskOrderReceipt(o.id, finalReceipt);
      }

      if (context.mounted) {
        showAppSnack(
          context,
          'Payment confirmed for Order #${o.displayOrderNumber} and receipt generated.',
        );
      }
    }
  }

  Future<double?> _verifyRemainingGCash(
    BuildContext context,
    OrderRecord o,
    double remaining,
  ) async {
    Uint8List? proofBytes;
    String? proofFileName;
    bool submitting = false;
    final amountController = TextEditingController(
      text: remaining.toStringAsFixed(2),
    );
    final refController = TextEditingController();

    return await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> captureProof() async {
            final picker = ImagePicker();
            final image = await picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 75,
              maxWidth: 800,
              maxHeight: 800,
            );
            if (image == null) return;
            final rawBytes = await image.readAsBytes();
            final bytes = compressImage(rawBytes, maxDimension: 800, quality: 75);

            setModalState(() {
              proofBytes = bytes;
              proofFileName = 'remaining_gcash_capture.jpg';
            });

            // Run OCR to auto-fill fields
            final details = await GcashReceiptParser.extractDetails(bytes);
            setModalState(() {
              if (details.amount != null) {
                amountController.text = details.amount!.toStringAsFixed(2);
              }
              if (details.referenceId != null) {
                refController.text = details.referenceId!;
              }
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: AppColors.cardWhite,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.qr_code_2_outlined,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GCash Remaining Balance — Order #${o.displayOrderNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.darkBrown,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Remaining Balance Due: ${peso(remaining)}',
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Scan GCash QR Code to Pay:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkBrown,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.beige,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (PaymentConfig.gcashQrBase64 != null &&
                                    PaymentConfig.gcashQrBase64!.isNotEmpty) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      base64Decode(
                                        PaymentConfig.gcashQrBase64!,
                                      ),
                                      width: double.infinity,
                                      height: 200,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Take photo with Camera (GCash Receipt):',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkBrown,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: captureProof,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.textMuted.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: proofBytes == null
                                  ? const Column(
                                      children: [
                                        Icon(
                                          Icons.camera_alt_outlined,
                                          color: AppColors.brown,
                                          size: 32,
                                        ),
                                        SizedBox(height: 6),
                                        Text(
                                          'Tap to open Camera & Capture Receipt',
                                          style: TextStyle(
                                            color: AppColors.brown,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.memory(
                                            proofBytes!,
                                            height: 140,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          proofFileName ?? 'Captured Photo',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.success,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: amountController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            decoration: const InputDecoration(
                              labelText: 'Verified GCash Amount (₱)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: refController,
                            decoration: const InputDecoration(
                              labelText: 'Reference ID / Ref No.',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.darkBrown,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: proofBytes == null
                            ? null
                            : () {
                                final amt =
                                    double.tryParse(
                                      amountController.text.trim(),
                                    ) ??
                                    remaining;
                                Navigator.pop(ctx, amt);
                              },
                        child: const Text('Verify & Confirm Payment'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<double?> _verifyRemainingCash(
    BuildContext context,
    OrderRecord o,
    double remaining,
  ) async {
    final controller = TextEditingController(text: remaining.toStringAsFixed(2));
    final cashGiven = await showDialog<double>(
      context: context,
      builder: (ctx) {
        String? errorMsg;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(
              'Cash Payment for Remaining Balance — Order #${o.displayOrderNumber}',
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remaining Balance Due: ${peso(remaining)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Enter cash amount given by customer:'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixText: '₱ ',
                        labelText: 'Cash Tendered',
                      ),
                      onChanged: (_) => setDialogState(() => errorMsg = null),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Quick Select Amount:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _getSmartCashSuggestions(remaining).map((amt) {
                        final label = amt == amt.roundToDouble() ? '₱${amt.toStringAsFixed(0)}' : '₱${amt.toStringAsFixed(2)}';
                        return OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            controller.text = amt.toStringAsFixed(2);
                            setDialogState(() => errorMsg = null);
                          },
                          child: Text(label),
                        );
                      }).toList(),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMsg!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkBrown,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final val = double.tryParse(controller.text.trim()) ?? -1;
                  if (val < remaining) {
                    setDialogState(
                      () => errorMsg =
                          'Insufficient cash! Cash tendered must be at least ${peso(remaining)}.',
                    );
                    return;
                  }
                  Navigator.pop(ctx, val);
                },
                child: const Text('Accept'),
              ),
            ],
          ),
        );
      },
    );

    if (cashGiven == null || cashGiven < remaining) return null;

    final change = (cashGiven - remaining).clamp(0.0, double.infinity);

    if (!context.mounted) return null;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Calculation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Remaining Balance Due', peso(remaining)),
            _infoRow('Cash Tendered', peso(cashGiven)),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Change', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
                Text(change == 0 ? '₱0.00' : peso(change), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.success)),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkBrown,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    return remaining;
  }

  Future<bool?> _showSplitRemainingModal(BuildContext context, OrderRecord o, double remaining) async {
    Uint8List? proofBytes;
    String? proofFileName;
    final gcashController = TextEditingController();
    final cashController = TextEditingController();
    String? errorMsg;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> captureProof() async {
            final picker = ImagePicker();
            final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 800, maxHeight: 800);
            if (image == null) return;
            final rawBytes = await image.readAsBytes();
            final bytes = compressImage(rawBytes, maxDimension: 800, quality: 75);

            setDialogState(() {
              proofBytes = bytes;
              proofFileName = 'split_remaining_camera.jpg';
            });

            // Run OCR to auto-fill fields
            final details = await GcashReceiptParser.extractDetails(bytes);
            setDialogState(() {
              if (details.amount != null) {
                gcashController.text = details.amount!.toStringAsFixed(2);
                final remCash = (remaining - details.amount!).clamp(0.0, double.infinity);
                cashController.text = remCash.toStringAsFixed(2);
              }
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: AppColors.cardWhite,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.call_split_outlined, color: AppColors.darkBrown),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Split Remaining Balance — Order #${o.displayOrderNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkBrown),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Remaining Balance Due: ${peso(remaining)}',
                              style: const TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (errorMsg != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(errorMsg!, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          const Text('1. Camera Upload for GCash Portion:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: captureProof,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: proofBytes == null
                                  ? const Column(
                                      children: [
                                        Icon(Icons.camera_alt_outlined, color: AppColors.brown, size: 28),
                                        SizedBox(height: 4),
                                        Text('Tap to open Camera & Capture GCash Receipt', style: TextStyle(color: AppColors.brown, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.memory(proofBytes!, height: 120, fit: BoxFit.cover),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(proofFileName ?? 'Captured Photo', style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text('2. Split Amounts (GCash + Cash):', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: gcashController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'GCash Portion (₱)',
                              border: OutlineInputBorder(),
                              prefixText: '₱ ',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: cashController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Cash Portion (₱)',
                              border: OutlineInputBorder(),
                              prefixText: '₱ ',
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkBrown, foregroundColor: Colors.white),
                        onPressed: () {
                          if (proofBytes == null) {
                            setDialogState(() => errorMsg = 'Please capture a camera photo of the GCash receipt.');
                            return;
                          }
                          final gcash = double.tryParse(gcashController.text.trim()) ?? 0;
                          final cash = double.tryParse(cashController.text.trim()) ?? 0;
                          final sum = gcash + cash;
                          if ((sum - remaining).abs() > 0.01) {
                            setDialogState(() => errorMsg = 'Sum (${peso(sum)}) must exactly equal remaining balance (${peso(remaining)}).');
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Confirm Split Payment'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// One row of the Order Status Workflow modal — a step that's either
  /// already done, currently selectable ("Select" enabled), or still
  /// locked behind an earlier step.
  Widget _stageRow({
    required String label,
    required IconData icon,
    required bool done,
    required bool enabled,
    required VoidCallback onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: done ? AppColors.success.withValues(alpha: 0.08) : AppColors.beige,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : icon,
            color: done
                ? AppColors.success
                : (enabled ? AppColors.brown : AppColors.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: done ? AppColors.success : (enabled ? null : AppColors.textMuted),
              ),
            ),
          ),
          if (done)
            const Text('Done', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold))
          else
            ElevatedButton(
              onPressed: enabled ? onSelect : null,
              child: const Text('Select'),
            ),
        ],
      ),
    );
  }

  /// Blocks accepting the order and offers to send the customer a polite,
  /// out-of-stock notice instead. Sending it declines the order (via the
  /// existing decline/declineReason flow) with the composed message as the
  /// reason, so it surfaces only on that customer's own "My Orders" screen
  /// (already filtered there by customerId) — never to any other customer.
  Future<void> _showOutOfStockDialog(BuildContext context, OrderRecord o, List<Product> insufficient) async {
    final names = insufficient.map((p) => p.name).join(', ');
    final plural = insufficient.length > 1;
    final controller = TextEditingController(
      text: 'Hi! We\'re sorry — $names ${plural ? 'are' : 'is'} currently out of stock, '
          'so we\'re unable to prepare your order #${o.displayOrderNumber} at this time. '
          'We sincerely apologize for the inconvenience and hope to serve you again soon.',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot Accept Order — Insufficient Stock'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Out of stock: $names',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              const Text('This order cannot be accepted as-is. Notify the customer:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Message to customer',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final message = controller.text.trim();
              if (message.isEmpty) return;
              Navigator.pop(ctx);
              await AppData.instance.declineKioskOrder(o.id, reason: message);
              if (!context.mounted) return;
              showAppSnack(context, 'Customer notified — order #${o.displayOrderNumber} declined due to insufficient stock.', success: false);
            },
            child: const Text('Send Notification & Decline'),
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
        // Declined orders stay in the collection until the customer
        // dismisses them, so only orders still moving through the workflow
        // ('Pending' plus the in-progress 'Preparing'/'Ready' steps) need
        // employee attention here.
        final orders = data.kioskOrders
            .where((o) => onlyPending
                ? (o.status == 'Pending')
                : (o.status == 'Preparing' || o.status == 'Ready'))
            .toList();
        return SectionPage(
          children: [
            if (orders.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    onlyPending ? 'No pending orders right now.' : 'No orders currently in the kitchen.',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ),
            PaginatedList<OrderRecord>(
              items: orders,
              pageSize: 5,
              itemBuilder: (context, o) {
                final isPending = o.status == 'Pending';
                final isLoyalCustomer = AppData.instance.isCustomerLoyalById(o.customerId) ||
                    AppData.instance.isCustomerLoyalByName(o.customerName);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.beigeDark, width: 1),
                    boxShadow: AppShadows.soft,
                  ),
                  child: LayoutBuilder(
                    builder: (context, cardConstraints) {
                      final isPhone = cardConstraints.maxWidth < 450;
                      return Padding(
                        padding: EdgeInsets.all(isPhone ? 12 : 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Header Row
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isPending
                                        ? AppColors.accent.withValues(alpha: 0.15)
                                        : AppColors.darkBrown.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPending
                                        ? Icons.notifications_active_outlined
                                        : _stageDisplay(o.status).$2,
                                    color: isPending ? AppColors.accent : AppColors.darkBrown,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 2,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'Order #${o.displayOrderNumber}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14.5,
                                              color: AppColors.darkBrown,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.beige,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _sourceLabel(o.source).toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.darkBrown,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (o.customerName != null) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.person_outline, size: 12, color: AppColors.textMuted),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                o.customerName!,
                                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isLoyalCustomer) ...[
                                              const SizedBox(width: 4),
                                              const LoyalBadge(),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (!isPending) ...[
                                  StatusBadge(status: _stageDisplay(o.status).$1),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Badges Row
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.beige,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.dining_outlined, size: 12, color: AppColors.darkBrown),
                                      const SizedBox(width: 4),
                                      Text(o.orderType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.beige,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        (o.proofOfPaymentBase64 != null || o.paymentMethod.contains('GCash') || o.paymentMethod.contains('Split') || o.paymentMethod.contains('Partial'))
                                            ? Icons.qr_code_2_outlined
                                            : Icons.payments_outlined,
                                        size: 12,
                                        color: AppColors.darkBrown,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(o.paymentMethod, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
                                    ],
                                  ),
                                ),
                                if (o.extractedReferenceId != null && o.extractedReferenceId!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.tag_rounded, size: 12, color: AppColors.accent),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Ref No: ${o.extractedReferenceId}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentDark),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),

                            // Partial Payment Status Banner if applicable
                            if (o.isPartialPayment || o.paymentMethod.contains('Partial')) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: o.isFullyPaid
                                      ? AppColors.success.withValues(alpha: 0.1)
                                      : AppColors.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: o.isFullyPaid
                                        ? AppColors.success.withValues(alpha: 0.3)
                                        : AppColors.warning.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          o.isFullyPaid ? 'Fully Paid' : 'Partially Paid (GCash Deposit)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                            color: o.isFullyPaid ? AppColors.success : AppColors.darkBrown,
                                          ),
                                        ),
                                        Text(
                                          'Deposit Paid: ${peso(o.totalVerifiedPayments)}',
                                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                    if (!o.isFullyPaid)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Due: ${peso(o.remainingBalance)}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      )
                                    else
                                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),
                            const Divider(height: 1, color: AppColors.beigeDark),
                            const SizedBox(height: 8),

                            // Ordered Items
                            const Text(
                              'Ordered Items:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.darkBrown),
                            ),
                            const SizedBox(height: 4),
                            ...o.items.map((i) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${i.quantity} × ${i.product.name}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.darkBrown),
                                        ),
                                      ),
                                      Text(
                                        peso(i.subtotal),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.darkBrown),
                                      ),
                                    ],
                                  ),
                                  if (i.selectedAddOns.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 14, top: 2),
                                      child: Text(
                                        i.selectedAddOns.map((a) => a.quantity > 1 ? '${a.quantity} × ${a.name}' : '+ ${a.name}').join(', '),
                                        style: const TextStyle(fontSize: 10.5, color: AppColors.accentDark),
                                      ),
                                    ),
                                ],
                              ),
                            )),

                            const SizedBox(height: 10),
                            const Divider(height: 1, color: AppColors.beigeDark),
                            const SizedBox(height: 10),

                            // Total & Action Footer
                            if (isPhone)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total',
                                        style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        peso(o.total),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          color: AppColors.darkBrown,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isPending)
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.darkBrown,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _previewOrder(context, data, o),
                                      icon: const Icon(Icons.visibility_outlined, size: 13),
                                      label: const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    )
                                  else
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.darkBrown,
                                        side: const BorderSide(color: AppColors.darkBrown),
                                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _showOrderStatusModal(context, data, o.id),
                                      icon: Icon(_stageDisplay(o.status).$2, size: 13),
                                      label: const Text('Manage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                ],
                              )
                            else
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total Order Amount',
                                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        peso(o.total),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color: AppColors.darkBrown,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isPending)
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.darkBrown,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _previewOrder(context, data, o),
                                      icon: const Icon(Icons.visibility_outlined, size: 16),
                                      label: const Text('Preview Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                    )
                                  else
                                    OutlinedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        foregroundColor: AppColors.darkBrown,
                                        side: const BorderSide(color: AppColors.darkBrown),
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _showOrderStatusModal(context, data, o.id),
                                      icon: Icon(_stageDisplay(o.status).$2, size: 16),
                                      label: const Text('Manage Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
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

/// Read-only Preview Order modal. Shows the customer's complete order
/// details (Order ID, ordered items, quantities, add-ons and total amount)
/// and, at the bottom, a "Mode of Payment" button that opens the
/// payment-method chooser. Once a payment method has been recorded, the
/// bottom actions swap to "Decline Order" / "Accept Order" — [Navigator.pop]
/// returns `'accept'`, `'decline'`, or `null` (dismissed with no decision)
/// so the caller can route into the matching existing flow.
class PendingOrdersPage extends StatelessWidget {
  const PendingOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Orders'),
        backgroundColor: AppColors.cardWhite,
        foregroundColor: AppColors.darkBrown,
        elevation: 0.5,
      ),
      body: const KioskManagementScreen(onlyPending: true),
    );
  }
}

class PendingOrdersModal extends StatelessWidget {
  const PendingOrdersModal({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final isDesktop = media.width > 700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isDesktop ? 680 : media.width * 0.92,
        height: media.height * 0.82,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, color: AppColors.darkBrown),
                const SizedBox(width: 8),
                const Text(
                  'Pending Orders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkBrown,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const Expanded(
              child: KioskManagementScreen(onlyPending: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderPreviewModal extends StatelessWidget {
  const _OrderPreviewModal({required this.order});

  final OrderRecord order;

  Widget _detailRow(String label, String value, {Widget? badge}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkBrown,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                badge,
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final isLoyalCustomer =
        AppData.instance.isCustomerLoyalById(o.customerId) ||
        AppData.instance.isCustomerLoyalByName(o.customerName);

    final isGcash = o.paymentMethod.contains('GCash') ||
        o.paymentMethod.contains('Split') ||
        o.paymentMethod.contains('Multi') ||
        o.paymentMethod.contains('Partial') ||
        o.proofOfPaymentBase64 != null;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: AppColors.cardWhite,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.darkBrown.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.darkBrown,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview Order #${o.displayOrderNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.darkBrown,
                        ),
                      ),
                      const Text(
                        'Review order details before accepting or declining',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, null),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order Metadata Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.beige,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.beigeDark),
                      ),
                      child: Column(
                        children: [
                          if (o.customerName != null)
                            _detailRow(
                              'Customer',
                              o.customerName!,
                              badge: isLoyalCustomer ? const LoyalBadge() : null,
                            ),
                          _detailRow('Order Type', o.orderType),
                          _detailRow('Payment Method', o.paymentMethod),
                          _detailRow(
                            'Source',
                            KioskManagementScreen._sourceLabel(o.source),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Payment Special Notices
                    if (o.paymentMethod.contains('Partial') ||
                        o.isPartialPayment) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🔄 Partial Payment (GCash Deposit)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.darkBrown,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Deposit Paid: ${peso(o.totalVerifiedPayments)} · Remaining Balance Due at Counter: ${peso(o.remainingBalance)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.darkBrown,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    const Divider(height: 1, color: AppColors.beigeDark),
                    const SizedBox(height: 10),

                    // Items List
                    const Text(
                      'Ordered Items:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: AppColors.darkBrown,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...o.items.map((i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${i.quantity} × ${i.product.name}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                        color: AppColors.darkBrown,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    peso(i.subtotal),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.darkBrown,
                                    ),
                                  ),
                                ],
                              ),
                              if (i.selectedAddOns.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 14,
                                    top: 2,
                                  ),
                                  child: Text(
                                    i.selectedAddOns
                                        .map((a) => a.quantity > 1
                                            ? '${a.quantity} × ${a.name}'
                                            : '+ ${a.name}')
                                        .join(', '),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.accentDark,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )),

                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.beigeDark),
                    const SizedBox(height: 12),

                    // Total Amount
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Order Amount',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.darkBrown,
                          ),
                        ),
                        Text(
                          peso(o.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: AppColors.darkBrown,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Actions Row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, 'decline'),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text(
                      'Decline Order',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkBrown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, 'accept'),
                    icon: Icon(isGcash ? Icons.verified_outlined : Icons.payments_outlined, size: 16),
                    label: Text(
                      isGcash ? 'Verify Payment' : 'Payment',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
