import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import '../../config/payment_config.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../services/gcash_parser.dart';
import '../../models/models.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/addon_picker.dart';
import '../../widgets/customer_ui_widgets.dart';

class CustomerKioskScreen extends StatefulWidget {
  const CustomerKioskScreen({super.key, this.onOrderPlaced});

  /// Called right after an order is successfully placed. The shell uses this
  /// to start the Order ID + 20-minute countdown session (so the reminder
  /// survives navigation between customer tabs). When not provided the order
  /// is still placed normally.
  final void Function(OrderRecord order)? onOrderPlaced;

  @override
  State<CustomerKioskScreen> createState() => _CustomerKioskScreenState();
}

class _CustomerKioskScreenState extends State<CustomerKioskScreen> {
  static const _bestSellersTab = 'Best Sellers';
  String _category = 'All';
  String _search = '';
  final List<CartItem> _cart = [];

  @override
  void initState() {
    super.initState();
    AppData.instance.addListener(_onAppDataChanged);
  }

  void _onAppDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppData.instance.removeListener(_onAppDataChanged);
    super.dispose();
  }

  Future<void> _onProductSelected(Product p) async {
    if (p.isOutOfStock) return;
    List<MenuAddOn> chosenAddOns = const [];
    if (p.addOns.isNotEmpty) {
      final result = await _showAddOnsPickerDialog(p);
      if (result == null) return; // User cancelled
      chosenAddOns = result;
    }
    _addToCart(p, chosenAddOns);
  }

  void _addToCart(Product p, List<MenuAddOn> addOns) {
    setState(() {
      final existing = _cart.where((c) => c.sameSelectionAs(p, addOns));
      if (existing.isNotEmpty) {
        if (existing.first.quantity < p.stockQuantity) {
          existing.first.quantity++;
        }
      } else {
        _cart.add(CartItem(product: p, selectedAddOns: List.of(addOns)));
      }
    });
  }

  Future<List<MenuAddOn>?> _showAddOnsPickerDialog(
    Product p, {
    List<MenuAddOn>? initial,
  }) =>
      showAddOnPickerDialog(
        context: context,
        product: p,
        helperText: 'Select any add-ons you want for this item:',
        initial: initial,
      );

  double get _total => _cart.fold(0, (s, c) => s + c.subtotal);

  String formatTitleCase(String text) {
    if (text.isEmpty) return '';
    final words = text.split(RegExp(r'\s+'));
    return words.map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : '');
    }).join(' ');
  }

  bool hasConsecutiveDuplicates(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    for (int i = 0; i < clean.length - 1; i++) {
      if (clean[i] == clean[i + 1]) {
        return true;
      }
    }
    return false;
  }

  String? validateWalkInName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Customer name is required.';
    }
    final trimmed = value.trim();
    if (RegExp(r'\s{2,}').hasMatch(trimmed)) {
      return 'Only a single space between words is allowed.';
    }
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmed)) {
      return 'Only letters and spaces are allowed.';
    }
    if (hasConsecutiveDuplicates(trimmed)) {
      return 'Repeated consecutive letters (e.g., "cc" or "oo") are not allowed.';
    }
    return null;
  }

  /// Places the order with order type selection (Dine In, Take Out, Pickup)
  /// and payment method selection (Cash, GCash, Split Payment).
  /// Pickup forces GCash payment (anti-fake booking).
  Future<void> _placeOrder() async {
    if (_cart.isEmpty) return;

    final data = AppData.instance;
    final myId = data.currentUser?.id;
    final myName = data.currentUser?.fullName;
    final activeCount = data.kioskOrders.where((o) {
      final isMine = (myId != null && o.customerId == myId) ||
          (myId == null && myName != null && o.customerName == myName);
      final isActive = o.status == 'Pending' ||
          o.status == 'Preparing' ||
          o.status == 'Ready';
      return isMine && isActive;
    }).length;

    if (activeCount >= 3) {
      showAppSnack(
        context,
        'Maximum limit reached: You currently have $activeCount active orders in progress. Please wait for your current orders to complete.',
        success: false,
      );
      return;
    }

    String? guestName = data.currentUser?.fullName;
    if (data.currentUser == null) {
      final ctrl = TextEditingController();
      String? errorMsg;
      final nameEntered = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Enter Your Name', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please enter your name for this walk-in / guest order:'),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Customer Name *',
                    hintText: 'e.g., Juan Dela Cruz',
                    errorText: errorMsg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  autofocus: true,
                  onChanged: (val) {
                    if (errorMsg != null) {
                      setDialogState(() => errorMsg = null);
                    }
                    final formatted = formatTitleCase(val);
                    if (formatted != ctrl.text) {
                      ctrl.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  },
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkBrown,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final name = ctrl.text.trim();
                  final err = validateWalkInName(name);
                  if (err != null) {
                    setDialogState(() => errorMsg = err);
                    return;
                  }
                  Navigator.pop(ctx, name);
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      );
      if (nameEntered == null || nameEntered.trim().isEmpty || !mounted) return;
      guestName = nameEntered.trim();
    }

    while (mounted) {
      final user = AppData.instance.currentUser;
      final isLoyal = user != null && AppData.instance.isCustomerLoyal(user);

      // 1. Ask Order Type: Dine In, Take Out, Pickup
      final orderType = await showDialog<String>(
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
            child: SingleChildScrollView(
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
                        child: const Icon(
                          Icons.dining_outlined,
                          color: AppColors.darkBrown,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Order Type',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.darkBrown,
                              ),
                            ),
                            Text(
                              'How would you like to receive your order?',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close checkout',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Card 1: Dine In
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
                            decoration: BoxDecoration(
                              color: AppColors.darkBrown.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.restaurant_outlined,
                              color: AppColors.darkBrown,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dine In',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.darkBrown,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Enjoy your meal freshly served inside Overnight Cafe.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Card 2: Take Out
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
                            decoration: BoxDecoration(
                              color: AppColors.darkBrown.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.takeout_dining_outlined,
                              color: AppColors.darkBrown,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Take Out',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.darkBrown,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Packaged securely for you to enjoy on the go.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Card 3: Pickup
                  InkWell(
                    onTap: () => Navigator.pop(ctx, 'Pickup'),
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
                            decoration: BoxDecoration(
                              color: AppColors.darkBrown.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.storefront_outlined,
                              color: AppColors.darkBrown,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Pickup',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.darkBrown,
                                      ),
                                    ),
                                    if (isLoyal) ...[
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'PARTIAL OPTION AVAILABLE',
                                          style: TextStyle(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Order ahead and collect at our store counter.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (orderType == null || !mounted) return;

      if (orderType == 'Pickup' && isLoyal) {
        final pickupChoice = await showDialog<String>(
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
              child: SingleChildScrollView(
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
                          child: const Icon(
                            Icons.star_rounded,
                            color: AppColors.accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pickup Payment Options',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.darkBrown,
                                ),
                              ),
                              Text(
                                'Exclusive benefit for Loyal Customers',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, 'back'),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select how you would like to pay for this pickup order:',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.darkBrown,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Card 1: Full Payment
                    InkWell(
                      onTap: () => Navigator.pop(ctx, 'Full'),
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
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_outlined,
                                color: AppColors.accent,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Full Payment',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppColors.darkBrown,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          peso(_total),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Pay full order amount upfront via GCash for fast counter release.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Card 2: Partial Payment
                    InkWell(
                      onTap: () => Navigator.pop(ctx, 'Partial'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.beige.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.darkBrown.withValues(alpha: 0.3),
                          ),
                          boxShadow: AppShadows.soft,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.darkBrown.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.pie_chart_outline_rounded,
                                color: AppColors.darkBrown,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Partial Payment (50%)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppColors.darkBrown,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.darkBrown,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'LOYAL PERK',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pay ${peso(_total * 0.5)} deposit via GCash now, settle ${peso(_total * 0.5)} at counter.',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.darkBrown,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.darkBrown,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'back'),
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Back to Order Type'),
                      ),
                    ),
                  ],
                ),
            ),
          ),
        ),
      );

        if (pickupChoice == 'back') continue;
        if (pickupChoice == null || !mounted) return;

        if (pickupChoice == 'Full') {
          final gcashResult = await _openGCashModal(
            orderType: 'Pickup',
            paymentMethod: 'GCash (Full)',
            isPickup: true,
          );
          if (gcashResult == 'back') continue;
          return;
        } else if (pickupChoice == 'Partial') {
          final partialAmount = _total * 0.5;

          final gcashResult = await _openGCashModal(
            orderType: 'Pickup',
            paymentMethod: 'Partial Payment (GCash Deposit)',
            isPickup: true,
            partialAmountPaid: partialAmount,
          );
          if (gcashResult == 'back') continue;
          return;
        }
      }

      if (orderType == 'Pickup' && !isLoyal) {
        // Pickup requires GCash payment only for non-loyal customers to prevent fake bookings
        final gcashResult = await _openGCashModal(
          orderType: 'Pickup',
          paymentMethod: 'GCash',
          isPickup: true,
        );
        if (gcashResult == 'back')
          continue; // Loop back to Order Type selection
        return;
      }

      // 2. For Dine In or Take Out, choose payment method: Cash, GCash, or Split Payment
      final paymentMethod = await showDialog<String>(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.darkBrown,
                      ),
                      tooltip: 'Back to Order Type',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      onPressed: () => Navigator.pop(ctx, 'back'),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Mode of Payment',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.darkBrown,
                            ),
                          ),
                          Text(
                            'Order Type: $orderType',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close checkout',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choose your preferred payment method:',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.darkBrown,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                // Card 1: Cash
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
                          decoration: BoxDecoration(
                            color: AppColors.darkBrown.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.payments_outlined,
                            color: AppColors.darkBrown,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cash',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.darkBrown,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Pay cash at the counter upon staff confirmation.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Card 2: GCash
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
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.qr_code_2_outlined,
                            color: AppColors.accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GCash',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.darkBrown,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Pay via GCash QR code and upload receipt screenshot.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Card 3: Split Payment
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
                          decoration: BoxDecoration(
                            color: AppColors.darkBrown.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.call_split_outlined,
                            color: AppColors.darkBrown,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Split Payment (Cash + GCash)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.darkBrown,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Pay part via GCash QR and part in cash at counter.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (paymentMethod == 'back')
        continue; // Loop back to Order Type selection
      if (paymentMethod == null || !mounted) return;

      if (paymentMethod == 'Cash') {
        OrderRecord order;
        try {
          order = await AppData.instance.placeKioskOrder(
            List.of(_cart),
            customerName: guestName,
            paymentMethod: 'Cash',
            orderType: orderType,
            isGuest: data.currentUser == null,
          );
        } catch (e) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Order Submission Failed', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
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
          continue;
        }
        if (!mounted) return;
        setState(() => _cart.clear());
        widget.onOrderPlaced?.call(order);
        return;
      } else {
        final gcashResult = await _openGCashModal(
          orderType: orderType,
          paymentMethod: paymentMethod,
          isPickup: false,
          guestName: guestName,
        );
        if (gcashResult == 'back')
          continue; // Loop back to Mode of Payment selection
        return;
      }
    }
  }

  Future<String?> _openGCashModal({
    required String orderType,
    required String paymentMethod,
    required bool isPickup,
    double? partialAmountPaid,
    String? guestName,
  }) async {
    Uint8List? proofBytes;
    bool submitting = false;
    double? extractedAmount;
    String? extractedRef;
    String? extractedDate;

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickProof() async {
            final picker = ImagePicker();
            final image = await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 75,
              maxWidth: 800,
              maxHeight: 800,
            );
            if (image == null) return;
            final rawBytes = await image.readAsBytes();
            final bytes = compressImage(rawBytes, maxDimension: 800, quality: 75);

            // Set image immediately so it is ALWAYS accepted and previewed
            setModalState(() {
              proofBytes = bytes;
            });

            // Run OCR to auto-fill fields in background for verification
            final details = await GcashReceiptParser.extractDetails(bytes);
            setModalState(() {
              extractedAmount = details.amount;
              extractedRef = details.referenceId;
              extractedDate = details.dateTime;
            });
          }

          Future<void> submit() async {
            if (proofBytes == null || submitting) return;
            setModalState(() => submitting = true);
            final base64Image = base64Encode(proofBytes!);
            Navigator.pop(ctx, 'submitted');

            try {
              final order = await AppData.instance.placeKioskOrder(
                List.of(_cart),
                customerName: guestName ?? AppData.instance.currentUser?.fullName,
                paymentMethod: paymentMethod,
                proofOfPaymentBase64: base64Image,
                orderType: orderType,
                extractedAmount: extractedAmount,
                extractedReferenceId: extractedRef,
                extractedDateTime: extractedDate,
                partialAmountPaid: partialAmountPaid,
                isGuest: AppData.instance.currentUser == null,
              );
              if (!mounted) return;
              setState(() => _cart.clear());
              widget.onOrderPlaced?.call(order);
            } catch (e) {
              if (!mounted) return;
              await showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('Order Submission Failed', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
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
            }
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
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.darkBrown),
                        tooltip: 'Back',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        onPressed: () => Navigator.pop(ctx, 'back'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isPickup
                              ? 'Pickup — GCash Payment'
                              : (paymentMethod == 'Split Payment'
                                  ? 'Split Payment — GCash'
                                  : 'Pay with GCash'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkBrown),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel checkout',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (partialAmountPaid != null) ...[
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
                                      const Text('Deposit Amount Due Now:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.darkBrown)),
                                      Text(peso(partialAmountPaid!), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.accent)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Remaining Balance (at counter):', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                      Text(peso(_total - partialAmountPaid!), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.warning)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else if (isPickup) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Full Order Amount: ${peso(_total)} — Please send payment via GCash QR code below.',
                                style: const TextStyle(
                                  color: AppColors.darkBrown,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          const Text(
                            'Scan GCash QR Code to Pay:',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.darkBrown),
                          ),
                          const SizedBox(height: 8),
                          if (PaymentConfig.gcashQrBase64 != null &&
                              PaymentConfig.gcashQrBase64!.isNotEmpty) ...[
                            InkWell(
                              onTap: () => showEnlargedQrDialog(ctx, PaymentConfig.gcashQrBase64!),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.cardWhite,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.beigeDark),
                                  boxShadow: AppShadows.soft,
                                ),
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(6),
                                        color: Colors.white,
                                        child: Image.memory(
                                          base64Decode(PaymentConfig.gcashQrBase64!),
                                          width: double.infinity,
                                          height: 200,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.zoom_in, size: 16, color: AppColors.darkBrown),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Tap to Enlarge or Download QR Code',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.darkBrown,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.darkBrown,
                                  side: const BorderSide(color: AppColors.darkBrown),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => showEnlargedQrDialog(ctx, PaymentConfig.gcashQrBase64!),
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: const Text('Save / Download QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          const Text(
                            'Upload GCash Receipt Screenshot:',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.darkBrown),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: submitting ? null : pickProof,
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
                                        Icon(
                                          Icons.cloud_upload_outlined,
                                          color: AppColors.darkBrown,
                                          size: 32,
                                        ),
                                        SizedBox(height: 6),
                                        Text(
                                          'Tap to upload receipt screenshot',
                                          style: TextStyle(
                                            color: AppColors.darkBrown,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Supports PNG, JPG',
                                          style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.memory(
                                            proofBytes!,
                                            height: 150,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.check_circle, size: 14, color: AppColors.success),
                                            SizedBox(width: 4),
                                            Text(
                                              'Receipt screenshot attached (Tap to change)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.success,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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
                        onPressed: () => Navigator.pop(ctx, 'cancel'),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (proofBytes == null || submitting) ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.darkBrown,
                          foregroundColor: Colors.white,
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Submit Order'),
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

  // ---------------------------------------------------------------------
  // UI layer only (below). Everything above this line is untouched logic.
  // The helpers below call the SAME state mutations the old inline code did.
  // ---------------------------------------------------------------------

  /// Cart lines for both the desktop panel and the mobile sheet.
  /// [refreshSheet] is only passed from the bottom sheet so it can rebuild
  /// itself after the same `setState` mutations as before.
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
            });
            refreshSheet?.call();
          },
          onIncrement: c.quantity >= c.product.stockQuantity
              ? null
              : () {
                  setState(() => c.quantity++);
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
                    setState(() => c.selectedAddOns = result);
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
                      'Your Cart',
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
    // Out-of-stock items are hidden from the customer kiosk entirely so
    // they can never be ordered here.
    final products = AppData.instance.orderableProducts;
    final bestSellers = AppData.instance.bestSellingProducts;
    final popularIds = {for (final p in bestSellers) p.id};
    final categories = [
      'All',
      _bestSellersTab,
      ...{for (var p in products) p.category},
    ];
    var filtered = (_category == _bestSellersTab ? bestSellers : products)
        .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    if (_category != 'All' && _category != _bestSellersTab) {
      filtered = filtered.where((p) => p.category == _category).toList();
    }

    final orderingOpen = AppData.instance.isWithinOrderingWindow();
    final totalItems = _cart.fold(0, (s, c) => s + c.quantity);

    // LayoutBuilder: size everything from the space this screen really gets
    // (i.e. after the sidebar), not from the whole window width.
    return LayoutBuilder(
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
              padding:
                  EdgeInsets.fromLTRB(horizontalInset, 14, horizontalInset, 10),
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
              padding:
                  EdgeInsets.fromLTRB(horizontalInset, 16, horizontalInset, 0),
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
                        style: TextStyle(color: AppColors.textMuted),
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
                          onTap: () => _onProductSelected(p),
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
                      'Your Order',
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
                      (!orderingOpen || _cart.isEmpty) ? null : _placeOrder,
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
            Positioned.fill(bottom: 110, child: menu),
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
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
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
                          (!orderingOpen || _cart.isEmpty) ? null : _placeOrder,
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
    );
  }
}
