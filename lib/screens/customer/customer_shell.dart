import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/customer_ui_widgets.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import '../auth/login_screen.dart';
import 'customer_kiosk_screen.dart';
import 'my_orders_screen.dart';
import 'order_history_screen.dart';
import 'customer_profile_screen.dart';

/// Customer-facing shell. Besides hosting the bottom/rail navigation it also
/// owns the "active order" session: after a customer places an order, the
/// generated Order ID and its 20-minute countdown live here (not in the kiosk
/// screen) so they survive navigation between customer tabs — the kiosk screen
/// itself is rebuilt/disposed whenever the user switches tabs.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  @override
  void initState() {
    super.initState();
    AppData.instance.addListener(_checkActiveOrderStatus);
    _restoreActiveOrderIfNeeded();
  }

  /// How long an Order ID stays valid before its reminder disappears.
  static const Duration _orderValidity = Duration(minutes: 20);

  OrderRecord? _activeOrder;
  final ValueNotifier<Duration> _remaining = ValueNotifier<Duration>(
    _orderValidity,
  );
  Timer? _countdown;
  bool _modalOpen = false;

  void _restoreActiveOrderIfNeeded() {
    if (_activeOrder != null) return;
    final myId = AppData.instance.currentUser?.id;
    if (myId == null) return;

    try {
      final pendingOrders = AppData.instance.kioskOrders
          .where(
            (o) =>
                o.customerId == myId &&
                o.status == 'Pending' &&
                o.source == 'Kiosk' &&
                o.expiresAt != null,
          )
          .toList();

      if (pendingOrders.isNotEmpty) {
        pendingOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final latestOrder = pendingOrders.first;

        final remainingTime = latestOrder.expiresAt!.difference(DateTime.now());
        if (remainingTime > Duration.zero) {
          _activeOrder = latestOrder;
          _remaining.value = remainingTime;
          _countdown?.cancel();
          _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
            final next = _remaining.value - const Duration(seconds: 1);
            if (next <= Duration.zero) {
              _remaining.value = Duration.zero;
              _endOrderSession();
            } else {
              _remaining.value = next;
            }
          });
          if (mounted) setState(() {});
        } else {
          unawaited(AppData.instance.expireKioskOrder(latestOrder.id));
        }
      }
    } catch (e) {
      debugPrint('Error restoring active order: $e');
    }
  }

  void _checkActiveOrderStatus() {
    if (_activeOrder == null) {
      _restoreActiveOrderIfNeeded();
      return;
    }
    try {
      final updatedOrder = AppData.instance.kioskOrders.firstWhere(
        (o) => o.id == _activeOrder!.id,
      );
      if (updatedOrder.status == 'Preparing' ||
          updatedOrder.status == 'Ready') {
        _dismissActiveOrderTimer(
          msg: 'Your order is now being prepared! Order timer removed.',
        );
      } else if (updatedOrder.status == 'Declined') {
        _dismissActiveOrderTimer(
          msg:
              'Your order was declined: ${updatedOrder.declineReason ?? 'Please contact counter.'}',
        );
      } else if (updatedOrder.status == 'Cancelled' ||
          updatedOrder.status == 'Expired') {
        _dismissActiveOrderTimer(msg: 'Your order was cancelled.');
      } else if (updatedOrder.status != 'Pending') {
        _dismissActiveOrderTimer(msg: 'Your order status has been updated.');
      }
    } catch (_) {
      _dismissActiveOrderTimer(
        msg: 'Your order has been processed or removed.',
      );
    }
  }

  void _dismissActiveOrderTimer({required String msg}) {
    _countdown?.cancel();
    _countdown = null;
    if (_modalOpen) {
      Navigator.of(context).pop();
      _modalOpen = false;
    }
    if (!mounted) return;
    if (_activeOrder != null) {
      setState(() => _activeOrder = null);
      showAppSnack(context, msg, success: false);
    }
  }

  /// Starts a fresh 20-minute session for [order] and opens the full modal.
  /// Only one reminder is shown at a time — a new order replaces any previous
  /// one (the earlier order still lives on the Employee side's Pending Orders).
  void _startOrderSession(OrderRecord order) {
    _countdown?.cancel();
    _activeOrder = order;
    _remaining.value = _orderValidity;
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _remaining.value - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _remaining.value = Duration.zero;
        _endOrderSession();
      } else {
        _remaining.value = next;
      }
    });
    if (mounted) setState(() {});
    _showOrderModal();
  }

  /// Shows the full Order ID modal (also used to restore it from the
  /// minimized floating card).
  Future<void> _showOrderModal() async {
    if (_activeOrder == null || _modalOpen) return;
    _modalOpen = true;
    if (mounted) setState(() {});
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OrderIdModal(
        order: _activeOrder!,
        remaining: _remaining,
        onMinimize: () => Navigator.of(context).pop(),
      ),
    );
    if (!mounted) return;
    _modalOpen = false;
    setState(() {});
  }

  /// Ends the session: cancels the timer, closes the modal/floating card and
  /// clears the active order. The order is also expired on the backend so it
  /// drops out of the employee's Pending Orders at the same moment this card
  /// disappears — an order already accepted by staff is left untouched.
  void _endOrderSession() {
    _countdown?.cancel();
    _countdown = null;
    final orderId = _activeOrder?.id;
    if (_modalOpen) {
      Navigator.of(context).pop();
      _modalOpen = false;
    }
    if (!mounted) return;
    setState(() => _activeOrder = null);
    if (orderId != null) {
      // Fire-and-forget: the employee side updates live via its Firestore
      // listener, so the order vanishes in sync with this card.
      unawaited(AppData.instance.expireKioskOrder(orderId));
    }
    showAppSnack(
      context,
      'Your Order ID has expired. Please place your order again.',
      success: false,
    );
  }

  @override
  void dispose() {
    AppData.instance.removeListener(_checkActiveOrderStatus);
    _countdown?.cancel();
    _remaining.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final showCard = wide && _activeOrder != null && !_modalOpen;

    return Stack(
      children: [
        Positioned.fill(
          child: AppShell(
            title: 'Overnight Cafe',
            logoAsset: 'assets/images/OC_NAVBAR_LOGO.png',
            profileScreen: wide ? const CustomerProfileScreen() : null,
            trailing: wide
                ? const CustomerOrderingStatusChip()
                : (_activeOrder != null
                    ? IconButton(
                        tooltip: 'View active order and countdown',
                        onPressed: _showOrderModal,
                        icon: const Badge(
                          child: Icon(Icons.receipt_long_rounded),
                        ),
                      )
                    : null),
            sidebarFooter: const CustomerSidebarStatusCard(),
            liveItemLabel: 'Menu',
            hideDrawer: true,
            mobileBottomNavigation: true,
            onLogout: () {
              AppData.instance.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (r) => false,
              );
            },
            items: [
              NavItem(
                icon: Icons.storefront_outlined,
                label: 'Menu',
                builder: () =>
                    CustomerKioskScreen(onOrderPlaced: _startOrderSession),
              ),
              NavItem(
                icon: Icons.receipt_long_outlined,
                label: 'My Orders',
                builder: () => const MyOrdersScreen(),
              ),
              NavItem(
                icon: Icons.history_outlined,
                label: 'Order History',
                builder: () => const OrderHistoryScreen(),
              ),
              if (!wide)
                NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  builder: () => const CustomerProfileScreen(),
                ),
            ],
          ),
        ),
        if (showCard)
          Positioned(
            right: 16,
            bottom: 24,
            child: _MinimizedOrderCard(
              order: _activeOrder!,
              remaining: _remaining,
              onTap: _showOrderModal,
            ),
          ),
      ],
    );
  }
}

/// The full, minimizable Order ID modal. Shows the generated Order ID and a
/// live 20-minute countdown; "Minimize" collapses it to the floating card.
class _OrderIdModal extends StatelessWidget {
  const _OrderIdModal({
    required this.order,
    required this.remaining,
    required this.onMinimize,
  });

  final OrderRecord order;
  final ValueNotifier<Duration> remaining;
  final VoidCallback onMinimize;

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final orderId = order.displayOrderNumber;
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
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Placed!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBrown,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Successfully queued for counter',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Minimize',
                  onPressed: onMinimize,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.darkBrown,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppShadows.soft,
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'YOUR ORDER ID',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            orderId,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<Duration>(
                      valueListenable: remaining,
                      builder: (context, d, _) {
                        final total = _CustomerShellState
                            ._orderValidity
                            .inSeconds;
                        final progress = (d.inSeconds / total)
                            .clamp(0.0, 1.0)
                            .toDouble();
                        final expired = d <= Duration.zero;
                        return Center(
                          child: Column(
                            children: [
                              SizedBox(
                                width: 90,
                                height: 90,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 90,
                                      height: 90,
                                      child: CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: 6,
                                        backgroundColor: AppColors.beige,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          expired
                                              ? AppColors.danger
                                              : AppColors.darkBrown,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          expired
                                              ? Icons.timer_off_outlined
                                              : Icons.timer_outlined,
                                          size: 18,
                                          color: expired
                                              ? AppColors.danger
                                              : AppColors.darkBrown,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _fmt(d),
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: expired
                                                ? AppColors.danger
                                                : AppColors.darkBrown,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: expired
                                      ? AppColors.danger.withValues(
                                          alpha: 0.1,
                                        )
                                      : AppColors.beige,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  expired
                                      ? 'This Order ID has expired.'
                                      : 'Time left to show this at the counter',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: expired
                                        ? AppColors.danger
                                        : AppColors.darkBrown,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.beige,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.beigeDark,
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppColors.darkBrown,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Present this Order ID at the counter to confirm and pay. You can track this in "My Orders".',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      final reason = await showDialog<String>(
                        context: context,
                        builder: (ctx) => CancelOrderDialog(order: order),
                      );
                      if (reason != null && context.mounted) {
                        Navigator.pop(context);
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
                    icon: const Icon(Icons.cancel_outlined, size: 15),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkBrown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onMinimize,
                    icon: const Icon(Icons.minimize_rounded, size: 15),
                    label: const Text(
                      'Minimize',
                      style: TextStyle(fontSize: 12),
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

/// The collapsed reminder shown while the full modal is minimized. Tapping it
/// reopens the full modal with the same live countdown.
class _MinimizedOrderCard extends StatelessWidget {
  const _MinimizedOrderCard({
    required this.order,
    required this.remaining,
    required this.onTap,
  });

  final OrderRecord order;
  final ValueNotifier<Duration> remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: AppColors.cardWhite,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.3),
              width: 1.2,
            ),
            gradient: LinearGradient(
              colors: [Colors.white, AppColors.beige.withValues(alpha: 0.3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brown.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppColors.brown,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ACTIVE ORDER ID',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${order.displayOrderNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: AppColors.brown,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ValueListenableBuilder<Duration>(
                    valueListenable: remaining,
                    builder: (context, d, _) {
                      final expired = d <= Duration.zero;
                      return Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: expired
                                ? AppColors.danger
                                : AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            expired ? 'Expired' : _OrderIdModal._fmt(d),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: expired
                                  ? AppColors.danger
                                  : AppColors.accentDark,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(width: 14),
              const Icon(
                Icons.open_in_full_rounded,
                size: 16,
                color: AppColors.brown,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
