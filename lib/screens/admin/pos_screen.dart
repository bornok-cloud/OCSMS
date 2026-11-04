import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/payment_config.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../services/gcash_parser.dart';
import '../../models/models.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/addon_picker.dart';
import '../../widgets/customer_ui_widgets.dart';
import '../../widgets/receipt_widgets.dart';

/// Employee/Admin Point of Sale — used to take walk-in / counter orders.
///
/// Mirrors [CustomerKioskScreen]'s ordering logic exactly: staff pick from
/// the same [AppData.orderableProducts] list (out-of-stock items are
/// hidden, not just disabled), quantities are capped at live stock, and
/// submitting calls the very same [AppData.placeKioskOrder] the customer
/// kiosk uses — just tagged with `source: 'POS'` instead of `'Kiosk'`.
/// That means POS orders go through the identical order-creation and
/// stock-deduction flow: they land as 'Pending' in the shared order
/// queue (Kiosk Management), and stock is only deducted once an employee
/// accepts the order into "Preparing" — never at the point of sale here.
class _GcashResult {
  final Uint8List proofBytes;
  final double? amount;
  final String referenceId;
  final String dateTime;

  const _GcashResult({
    required this.proofBytes,
    this.amount,
    required this.referenceId,
    required this.dateTime,
  });
}

class PosScreen extends StatefulWidget {
  final String cashier;
  const PosScreen({super.key, required this.cashier});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  static const _bestSellersTab = 'Best Sellers';
  String _category = 'All';
  String _search = '';
  final List<CartItem> _cart = [];
  final TextEditingController _customerNameController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _cart.addAll(AppData.instance.posCart);
    _customerNameController.text = AppData.instance.posCustomerName;
    _customerNameController.addListener(() {
      AppData.instance.updatePosCustomerName(_customerNameController.text);
    });
  }

  void _syncCart() {
    AppData.instance.updatePosCart(_cart);
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    super.dispose();
  }

  /// Same add-to-cart rule as the Customer Kiosk: out-of-stock products
  /// can't be added, and quantity can never exceed live stock. If the
  /// product has add-ons configured in Menu Management, the cashier picks
  /// them first; otherwise it's added straight away like before.
  Future<void> _add(Product p) async {
    if (p.isOutOfStock) return; // safety net -- button already hidden/disabled
    List<MenuAddOn> chosenAddOns = const [];
    if (p.addOns.isNotEmpty) {
      final result = await _showAddOnsPickerDialog(p);
      if (result == null) return; // cashier cancelled
      chosenAddOns = result;
    }
    _addToCart(p, chosenAddOns);
  }

  void _addToCart(Product p, List<MenuAddOn> addOns) {
    setState(() {
      // Only bump quantity on an existing line if it's the same product
      // AND the same add-ons — a different add-on combo is a separate
      // line since it's priced differently.
      final existing = _cart.where((c) => c.sameSelectionAs(p, addOns));
      if (existing.isNotEmpty) {
        if (existing.first.quantity < p.stockQuantity) existing.first.quantity++;
      } else {
        _cart.add(CartItem(product: p, selectedAddOns: List.of(addOns)));
      }
      _syncCart();
    });
  }

  /// Lets the cashier tick which add-ons the customer wants for [p], with
  /// each add-on's extra price shown alongside it. Returns the picked
  /// list, or null if the cashier cancelled.
  Future<List<MenuAddOn>?> _showAddOnsPickerDialog(Product p, {List<MenuAddOn>? initial}) =>
      showAddOnPickerDialog(
        context: context,
        product: p,
        helperText: 'Select any add-ons the customer wants for this item.',
        initial: initial,
      );

  double get _total => _cart.fold(0, (s, c) => s + c.subtotal);

  /// Same order type and payment method flow as the Customer Kiosk.
  Future<void> _placeOrder() async {
    if (_cart.isEmpty) return;

    final customerName = _customerNameController.text.trim();
    if (customerName.isEmpty) {
      showAppSnack(context, 'Customer Name is required before placing an order.', success: false);
      return;
    }

    final data = AppData.instance;
    final activeCount = data.kioskOrders.where((o) {
      final isCustomer = o.customerName != null && o.customerName == customerName;
      final isActive = o.status == 'Pending' || o.status == 'Preparing' || o.status == 'Ready';
      return isCustomer && isActive;
    }).length;

    if (activeCount >= 3) {
      showAppSnack(
        context,
        'Maximum limit reached: $customerName currently has $activeCount active orders in progress. Please wait for current orders to complete.',
        success: false,
      );
      return;
    }

    // 1. Preview Order First
    // 1. Preview Order First
    final previewConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppColors.cardWhite,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.darkBrown.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded, color: AppColors.darkBrown, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preview Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.darkBrown)),
                  Text('Customer: $customerName', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.beige.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.beigeDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Order Items Summary:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.darkBrown)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _cart.length,
                        itemBuilder: (context, i) {
                          final item = _cart[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item.quantity} × ${item.product.name}',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.darkBrown),
                                      ),
                                      if (item.selectedAddOns.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 12, top: 2),
                                          child: Text(
                                            item.selectedAddOns.map((a) => a.quantity > 1 ? '${a.quantity} × ${a.name}' : '+ ${a.name}').join(', '),
                                            style: const TextStyle(fontSize: 11, color: AppColors.accentDark),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  peso(item.subtotal),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.beige,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.beigeDark),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                    Text(
                      peso(_total),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkBrown,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Proceed', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (previewConfirmed != true || !mounted) return;

    while (mounted) {
      // 2. Choose Order Type: Dine In or Take Out (no Pickup in POS)
      final orderType = await _showOrderTypeDialog();
      if (orderType == null || !mounted) return;

      // 3. Choose payment method: Cash, GCash, or Split Payment with customer-style cards
      final paymentMethod = await _showPaymentMethodDialog(orderType);
      if (paymentMethod == 'back') continue; // Loop back to Order Type selection
      if (paymentMethod == null || !mounted) return;

      if (paymentMethod == 'Cash') {
        final cashGiven = await _showPosCashPaymentDialog(context, _total);
        if (cashGiven == null) continue;
        await Future.delayed(const Duration(milliseconds: 150));
        await _submitOrder(paymentMethod: 'Cash', orderType: orderType, cashGiven: cashGiven);
        return;
      } else {
        final gcashResult = await _openGCashModal(orderType: orderType, paymentMethod: paymentMethod, isPickup: false);
        if (gcashResult == 'back' || gcashResult == null) continue;
        if (gcashResult is _GcashResult) {
          await Future.delayed(const Duration(milliseconds: 150));
          final base64Image = base64Encode(gcashResult.proofBytes);
          await _submitOrder(
            paymentMethod: paymentMethod,
            proofOfPaymentBase64: base64Image,
            orderType: orderType,
            extractedAmount: gcashResult.amount,
            extractedReferenceId: gcashResult.referenceId,
            extractedDateTime: gcashResult.dateTime,
          );
          return;
        }
      }
    }
  }

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

  Future<double?> _showPosCashPaymentDialog(BuildContext context, double total) async {
    final controller = TextEditingController(text: total.toStringAsFixed(2));
    return showDialog<double>(
      context: context,
      builder: (ctx) {
        String? errorMsg;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final tendered = double.tryParse(controller.text.trim()) ?? 0.0;
            final change = (tendered - total).clamp(0.0, double.infinity);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: AppColors.cardWhite,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.darkBrown.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.payments_outlined, color: AppColors.darkBrown, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cash Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.darkBrown)),
                        Text('POS Cash Settlement', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.beige,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.beigeDark),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount Due:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                            Text(peso(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Cash Tendered by Customer:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.darkBrown)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixText: '₱ ',
                          labelText: 'Amount Tendered',
                          isDense: true,
                        ),
                        onChanged: (_) => setDialogState(() => errorMsg = null),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Change:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                            Text(
                              peso(change),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.success),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Quick Select Amount:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _getSmartCashSuggestions(total).map((amt) {
                          final label = amt == amt.roundToDouble() ? '₱${amt.toStringAsFixed(0)}' : '₱${amt.toStringAsFixed(2)}';
                          return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppColors.cardWhite,
                              foregroundColor: AppColors.darkBrown,
                              side: const BorderSide(color: AppColors.beigeDark),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: const Size(0, 36),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              controller.text = amt.toStringAsFixed(2);
                              setDialogState(() => errorMsg = null);
                            },
                            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                      ),
                      if (errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Text(errorMsg!, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkBrown,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final val = double.tryParse(controller.text.trim()) ?? -1;
                    if (val < total) {
                      setDialogState(() => errorMsg = 'Insufficient cash! Cash tendered must be at least ${peso(total)}.');
                      return;
                    }
                    Navigator.pop(ctx, val);
                  },
                  child: const Text('Accept & Continue', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showOrderTypeDialog() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.darkBrown.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.dining_outlined, color: AppColors.darkBrown, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Select Order Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkBrown)),
                        Text('Choose how the customer will receive the order', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Dine In Card
              InkWell(
                onTap: () => Navigator.pop(ctx, 'Dine In'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.beigeDark),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.darkBrown.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.restaurant_outlined, color: AppColors.darkBrown, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dine In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                            SizedBox(height: 2),
                            Text('Enjoy your order inside the café.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Take Out Card
              InkWell(
                onTap: () => Navigator.pop(ctx, 'Take Out'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.beigeDark),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.darkBrown.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.takeout_dining_outlined, color: AppColors.darkBrown, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Take Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                            SizedBox(height: 2),
                            Text('Packaged for takeaway.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showPaymentMethodDialog(String orderType) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
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
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.darkBrown),
                    onPressed: () => Navigator.pop(ctx, 'back'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select Mode of Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkBrown)),
                        Text('Order Type: $orderType', style: const TextStyle(fontSize: 11.5, color: AppColors.accent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Choose your preferred payment method:', style: TextStyle(fontSize: 12.5, color: AppColors.darkBrown, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              // Cash Card
              InkWell(
                onTap: () => Navigator.pop(ctx, 'Cash'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.beigeDark),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.darkBrown.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.payments_outlined, color: AppColors.darkBrown, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                            SizedBox(height: 2),
                            Text('Pay cash at the counter upon staff confirmation.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // GCash Card
              InkWell(
                onTap: () => Navigator.pop(ctx, 'GCash'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.beigeDark),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.qr_code_2_outlined, color: AppColors.accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GCash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                            SizedBox(height: 2),
                            Text('Pay via GCash QR code and upload receipt screenshot.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Split Payment Card
              InkWell(
                onTap: () => Navigator.pop(ctx, 'Split Payment'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.beige.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.beigeDark),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.darkBrown.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.call_split_outlined, color: AppColors.darkBrown, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Split Payment (Cash + GCash)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkBrown)),
                            SizedBox(height: 2),
                            Text('Pay part via GCash QR and part in cash at counter.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Submits the order through the exact same [AppData.placeKioskOrder]
  /// call the Customer Kiosk uses, so order creation and (later) stock
  /// deduction follow identical rules. Only the `source` differs.
  Future<void> _submitOrder({
    required String paymentMethod,
    String? proofOfPaymentBase64,
    required String orderType,
    double? extractedAmount,
    String? extractedReferenceId,
    String? extractedDateTime,
    double? cashGiven,
  }) async {
    final typedName = _customerNameController.text.trim();
    final currentTotal = _total;

    OrderRecord order;
    try {
      order = await AppData.instance.placeKioskOrder(
        List.of(_cart),
        customerName: typedName.isEmpty ? null : typedName,
        paymentMethod: paymentMethod == 'Cash' ? 'Cash' : (paymentMethod == 'Split Payment' ? 'Multi Payment' : paymentMethod),
        proofOfPaymentBase64: proofOfPaymentBase64,
        source: 'POS',
        orderType: orderType,
        extractedAmount: extractedAmount,
        extractedReferenceId: extractedReferenceId,
        extractedDateTime: extractedDateTime,
        initialStatus: 'Preparing',
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Order Submission Failed', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          content: Text(formatUserFriendlyError(e)),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkBrown, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;

    AppData.instance.clearPosCart();
    setState(() {
      _cart.clear();
      _customerNameController.clear();
    });

    // 1. Show Order Submitted Successfully dialog FIRST
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppColors.cardWhite,
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 14),
            const Text(
              'Order Submitted Successfully',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Order has been sent straight to Kitchen.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.beige.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.brown.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Number:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    Text(
                      '#${order.displayOrderNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.brown),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Type:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    Text(
                      orderType,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payment:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    Text(
                      paymentMethod,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkBrown,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('View Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // 2. AFTER closing Order Submitted dialog, show the Receipt Dialog!
    final cashier = AppData.instance.currentUser?.fullName ?? 'Cashier';
    final amountPaid = cashGiven ?? extractedAmount ?? currentTotal;
    final change = cashGiven != null ? (cashGiven - currentTotal).clamp(0.0, double.infinity) : 0.0;

    final generatedReceipt = ReceiptRecord.fromOrder(
      order,
      total: currentTotal,
      amountPaid: amountPaid,
      cashTendered: cashGiven,
      gcashAmount: paymentMethod.contains('GCash') || paymentMethod == 'Split Payment' || paymentMethod == 'Multi Payment' ? (extractedAmount ?? currentTotal) : null,
      change: change,
      cashier: cashier,
    );

    final finalReceipt = await showReceiptDialog(context, generatedReceipt, orderTotal: currentTotal);
    if (finalReceipt != null) {
      try {
        await AppData.instance.saveKioskOrderReceipt(order.id, finalReceipt);
      } catch (e) {
        debugPrint('Error saving receipt: $e');
      }
    }
  }

  /// Same GCash proof-of-payment capture the Customer Kiosk uses, for
  /// cases where the customer pays via GCash at the counter instead of
  /// handing over cash.
  Future<Object?> _openGCashModal({
    required String orderType,
    required String paymentMethod,
    required bool isPickup,
  }) async {
    Uint8List? proofBytes;
    String? proofFileName;
    bool submitting = false;
    bool isEditable = false;
    final amountController = TextEditingController();
    final refController = TextEditingController();
    final dateController = TextEditingController();

    return await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> captureProof() async {
            final picker = ImagePicker();
            final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 800, maxHeight: 800);
            if (image == null) return;
            final rawBytes = await image.readAsBytes();
            final bytes = compressImage(rawBytes, maxDimension: 800, quality: 75);

            // Set image immediately so it is ALWAYS accepted and previewed
            setModalState(() {
              proofBytes = bytes;
              proofFileName = 'gcash_camera_capture.jpg';
            });

            // Run OCR to auto-fill fields
            final details = await GcashReceiptParser.extractDetails(bytes);
            setModalState(() {
              if (details.amount != null) amountController.text = details.amount!.toStringAsFixed(2);
              if (details.referenceId != null) refController.text = details.referenceId!;
              if (details.dateTime != null) dateController.text = details.dateTime!;
            });
          }

          void submit() {
            if (proofBytes == null) return;
            Navigator.pop(
              ctx,
              _GcashResult(
                proofBytes: proofBytes!,
                amount: double.tryParse(amountController.text),
                referenceId: refController.text.trim(),
                dateTime: dateController.text.trim(),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: AppColors.cardWhite,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.darkBrown),
                  tooltip: 'Back',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  onPressed: () => Navigator.pop(ctx, 'back'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPickup
                            ? 'Pickup — GCash Payment'
                            : (paymentMethod == 'Split Payment'
                                ? 'Split Payment (Attach GCash)'
                                : 'Pay with GCash'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkBrown),
                      ),
                      Text('Order Type: $orderType', style: const TextStyle(fontSize: 11.5, color: AppColors.accent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPickup) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          '⚠️ Pickup orders require GCash payment and employee/admin approval before acceptance to prevent fake bookings.',
                          style: TextStyle(color: AppColors.darkBrown, fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    const Text('Scan GCash QR Code to Pay:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.darkBrown)),
                    const SizedBox(height: 8),
                    if (PaymentConfig.gcashQrBase64 != null && PaymentConfig.gcashQrBase64!.isNotEmpty) ...[
                      InkWell(
                        onTap: () => showEnlargedQrDialog(ctx, PaymentConfig.gcashQrBase64!),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.beige,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.beigeDark),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  base64Decode(PaymentConfig.gcashQrBase64!),
                                  width: double.infinity,
                                  height: 180,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.zoom_in, size: 16, color: AppColors.darkBrown),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tap to View / Enlarge QR Code',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text('Upload GCash Receipt Screenshot:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.darkBrown)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: submitting ? null : captureProof,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: proofBytes == null ? AppColors.beige.withValues(alpha: 0.3) : AppColors.cardWhite,
                          border: Border.all(
                            color: proofBytes == null ? AppColors.textMuted.withValues(alpha: 0.4) : AppColors.success,
                            width: proofBytes == null ? 1 : 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: proofBytes == null
                            ? const Column(
                                children: [
                                  Icon(Icons.camera_alt_outlined, color: AppColors.darkBrown, size: 32),
                                  SizedBox(height: 6),
                                  Text('Tap to open Camera & Capture Receipt', style: TextStyle(color: AppColors.darkBrown, fontWeight: FontWeight.bold, fontSize: 12.5)),
                                  SizedBox(height: 2),
                                  Text('Supports PNG, JPG', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                                ],
                              )
                            : Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(proofBytes!, height: 140, fit: BoxFit.cover),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle, size: 14, color: AppColors.success),
                                      const SizedBox(width: 4),
                                      Text(
                                        proofFileName ?? 'Captured Photo',
                                        style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Extracted Details Container with Edit Button at the corner
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
                            controller: amountController,
                            enabled: isEditable,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Extracted Amount (₱)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: refController,
                            enabled: isEditable,
                            decoration: const InputDecoration(
                              labelText: 'Reference ID / Ref No.',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: dateController,
                            enabled: isEditable,
                            decoration: const InputDecoration(
                              labelText: 'Transaction Date & Time',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, 'back'),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkBrown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: proofBytes == null || submitting ? null : submit,
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cartLines({VoidCallback? refreshSheet}) {
    return ListView.builder(
      itemCount: _cart.length,
      itemBuilder: (ctx, i) {
        final c = _cart[i];
        return CustomerCartItemTile(
          item: c,
          onDecrement: () {
            setState(() {
              c.quantity--;
              if (c.quantity <= 0) _cart.removeAt(i);
              _syncCart();
            });
            refreshSheet?.call();
          },
          onIncrement: c.quantity >= c.product.stockQuantity
              ? null
              : () {
                  setState(() {
                    c.quantity++;
                    _syncCart();
                  });
                  refreshSheet?.call();
                },
          onEditAddOns: c.product.addOns.isEmpty
              ? null
              : () async {
                  final result = await _showAddOnsPickerDialog(
                    c.product,
                    initial: c.selectedAddOns,
                  );
                  if (result != null && mounted) {
                    setState(() {
                      c.selectedAddOns = result;
                      _syncCart();
                    });
                    refreshSheet?.call();
                  }
                },
        );
      },
    );
  }

  void _openMobileCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final itemCount = _cart.fold(0, (s, c) => s + c.quantity);
          return Container(
            height: MediaQuery.sizeOf(ctx).height * 0.72,
            decoration: const BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.beigeDark,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'Current Order',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CustomerCountBadge(count: itemCount),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: _cart.isEmpty
                      ? const CustomerEmptyCart(message: 'Your cart is empty.')
                      : _cartLines(refreshSheet: () => setSheetState(() {})),
                ),
                const SizedBox(height: 8),
                CustomerOrderSummary(
                  total: _total,
                  itemCount: itemCount,
                  showPlaceOrder: false,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Out-of-stock items are hidden entirely, exactly like the Customer
    // Kiosk, so they can never be added to a POS order either.
    final products = AppData.instance.orderableProducts;
    final bestSellers = AppData.instance.bestSellingProducts;
    final popularIds = {for (final p in bestSellers) p.id};
    final categories = [
      'All',
      _bestSellersTab,
      ...{for (var p in products) p.category}
    ];
    var filtered = (_category == _bestSellersTab ? bestSellers : products)
        .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    if (_category != 'All' && _category != _bestSellersTab) {
      filtered = filtered.where((p) => p.category == _category).toList();
    }

    final orderingOpen = AppData.instance.isWithinOrderingWindow();
    final totalItems = _cart.fold(0, (s, c) => s + c.quantity);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final wide = width >= 700;
          final horizontalInset = width < 380 ? 12.0 : 18.0;
        final cartWidth = wide ? (width >= 1100 ? 380.0 : 340.0) : width;
        final productPanelWidth = wide ? (width - cartWidth) : width;
        final cols = (productPanelWidth / 178).floor().clamp(2, 4).toInt();
        final compactCards = productPanelWidth / cols < 190;

    final menu = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalInset, 14, horizontalInset, 10),
          child: CustomerSearchField(
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: horizontalInset),
            children: categories
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CustomerCategoryChip(
                      label: c,
                      icon: c == _bestSellersTab
                          ? Icons.local_fire_department_outlined
                          : null,
                      selected: _category == c,
                      count: _category == c ? filtered.length : null,
                      onTap: () => setState(() => _category = c),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalInset, 16, horizontalInset, 0),
          child: Row(
            children: [
              const Text(
                'FEATURED SELECTION',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Showing ${filtered.length} ${filtered.length == 1 ? 'item' : 'items'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _category == _bestSellersTab
                        ? 'No completed sales yet.'
                        : 'No available products match.',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    horizontalInset,
                    12,
                    horizontalInset,
                    22,
                  ),
                  itemCount: filtered.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisExtent: compactCards ? 190 : 200,
                    crossAxisSpacing: width < 380 ? 10 : 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    return CustomerProductCard(
                      product: p,
                      popular: popularIds.contains(p.id),
                      compact: compactCards,
                      onTap: () => _add(p),
                    );
                  },
                ),
        ),
      ],
    );

    if (wide) {
      final cartPanel = Container(
        margin: const EdgeInsets.fromLTRB(0, 14, 16, 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Current Order',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(width: 8),
                CustomerCountBadge(count: totalItems),
              ],
            ),
            const SizedBox(height: 12),
            if (!orderingOpen)
              const CustomerNoticeStrip(
                message:
                    'Café ordering is closed. Operating hours: 7:00 PM – 2:00 AM.',
              ),
            TextField(
              controller: _customerNameController,
              maxLength: 20,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                LengthLimitingTextInputFormatter(20),
                NameTextInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                hintText: 'Enter customer name',
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _cart.isEmpty
                  ? const CustomerEmptyCart(
                      message: 'Your cart is empty. Add something delicious!',
                    )
                  : _cartLines(),
            ),
            const SizedBox(height: 8),
            CustomerOrderSummary(
              total: _total,
              itemCount: totalItems,
              onPlaceOrder:
                  _cart.isEmpty ? null : _placeOrder,
            ),
          ],
        ),
      );

      return Row(
        children: [
          Expanded(child: menu),
          SizedBox(width: cartWidth, child: cartPanel),
        ],
      );
    }

    // Phone / narrow layout: menu + floating cart bar (cart opens as a
    // bottom sheet).
    return Stack(
      children: [
        Positioned.fill(bottom: 140, child: menu),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.lifted,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!orderingOpen)
                  const CustomerNoticeStrip(
                    message: 'Café ordering is closed (7:00 PM – 2:00 AM).',
                    compact: true,
                  ),
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _customerNameController,
                    maxLength: 20,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(20),
                      NameTextInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Customer Name *',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.darkBrown,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _openMobileCartSheet,
                      icon: const Icon(
                        Icons.shopping_bag_outlined,
                        size: 18,
                      ),
                      label: Text(
                        'Cart ($totalItems items)',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      peso(_total),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: AppColors.darkBrown,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkBrown,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.beigeDark,
                    disabledForegroundColor: AppColors.textMuted,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed:
                      _cart.isEmpty ? null : _placeOrder,
                  child: const Text(
                    'Place Order',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
      },
    ),
  );
  }
}
