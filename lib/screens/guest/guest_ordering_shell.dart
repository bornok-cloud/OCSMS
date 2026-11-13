import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import '../../utils/web_back_guard.dart';
import 'guest_track_order_screen.dart';
import '../customer/customer_kiosk_screen.dart';
import '../auth/login_screen.dart';

class GuestOrderingShell extends StatefulWidget {
  const GuestOrderingShell({super.key, this.initialTableNumber});

  final String? initialTableNumber;

  @override
  State<GuestOrderingShell> createState() => _GuestOrderingShellState();
}

class _GuestOrderingShellState extends State<GuestOrderingShell> {
  late String _tableNumber;
  OrderRecord? _activeOrder;
  final ValueNotifier<Duration> _remaining = ValueNotifier<Duration>(const Duration(minutes: 20));
  Timer? _countdown;
  bool _modalOpen = false;
  StreamSubscription? _webBackGuardSub;

  @override
  void initState() {
    super.initState();
    _tableNumber = widget.initialTableNumber ?? 'Table 1';
    AppData.instance.addListener(_checkActiveOrderStatus);
    _webBackGuardSub = setupWebBackGuard(_handleExitPrompt);
  }

  static const Duration _orderValidity = Duration(minutes: 20);

  void _checkActiveOrderStatus() {
    if (_activeOrder == null) return;
    try {
      final updatedOrder = AppData.instance.kioskOrders.firstWhere(
        (o) => o.id == _activeOrder!.id,
      );
      if (updatedOrder.status == 'Preparing' || updatedOrder.status == 'Ready') {
        _dismissActiveOrderTimer(msg: 'Your order is now being prepared!');
      } else if (updatedOrder.status == 'Declined') {
        _dismissActiveOrderTimer(msg: 'Your order was declined: ${updatedOrder.declineReason ?? 'Please contact counter.'}');
      } else if (updatedOrder.status == 'Cancelled' || updatedOrder.status == 'Expired') {
        _dismissActiveOrderTimer(msg: 'Your order was cancelled or expired.');
      }
    } catch (_) {
      _dismissActiveOrderTimer(msg: 'Your order has been processed.');
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

  Future<void> _showOrderModal() async {
    if (_activeOrder == null || _modalOpen) return;
    _modalOpen = true;
    if (mounted) setState(() {});
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GuestOrderIdModal(
        order: _activeOrder!,
        remaining: _remaining,
        tableNumber: _tableNumber,
        onMinimize: () => Navigator.of(context).pop(),
      ),
    );
    if (!mounted) return;
    _modalOpen = false;
    setState(() {});
  }

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
      unawaited(AppData.instance.expireKioskOrder(orderId));
    }
    showAppSnack(context, 'Your Order ID has expired. Please place your order again.', success: false);
  }

  Future<bool> _handleExitPrompt() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.cardWhite,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.exit_to_app_rounded,
                color: AppColors.danger,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Exit Walk-In Ordering',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.darkBrown,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to exit walk-in ordering?',
          style: TextStyle(
            fontSize: 13.5,
            color: AppColors.darkBrown,
            fontWeight: FontWeight.w500,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkBrown,
              side: const BorderSide(color: AppColors.beigeDark, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Exit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _webBackGuardSub?.cancel();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (r) => false,
      );
    }
    return confirm == true;
  }

  @override
  void dispose() {
    _webBackGuardSub?.cancel();
    AppData.instance.removeListener(_checkActiveOrderStatus);
    _countdown?.cancel();
    _remaining.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final showCard = wide && _activeOrder != null && !_modalOpen;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleExitPrompt();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: AppShell(
              title: 'Overnight Cafe (Guest - $_tableNumber)',
              logoAsset: 'assets/images/OC_NAVBAR_LOGO.png',
              profileScreen: null,
              hideDrawer: true,
              mobileBottomNavigation: true,
              onBack: _handleExitPrompt,
              leading: IconButton(
                tooltip: 'Exit Walk-In Ordering',
                onPressed: _handleExitPrompt,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
              ),
              trailing: _activeOrder != null
                  ? IconButton(
                      tooltip: 'View active order and countdown',
                      onPressed: _showOrderModal,
                      icon: const Badge(child: Icon(Icons.receipt_long_rounded, color: Colors.black)),
                    )
                  : null,
              onLogout: _handleExitPrompt,
            items: [
              NavItem(
                icon: Icons.storefront_outlined,
                label: 'Menu',
                builder: () => CustomerKioskScreen(
                  onOrderPlaced: (order) {
                    // Inject guest & table metadata
                    _startOrderSession(order);
                  },
                ),
              ),
              NavItem(
                icon: Icons.search_rounded,
                label: 'Track Order',
                builder: () => GuestTrackOrderScreen(
                  initialOrderNumber: _activeOrder?.displayOrderNumber,
                ),
              ),
            ],
          ),
        ),
        if (showCard)
          Positioned(
            right: 16,
            bottom: 24,
            child: _MinimizedGuestOrderCard(
              order: _activeOrder!,
              remaining: _remaining,
              tableNumber: _tableNumber,
              onTap: _showOrderModal,
            ),
          ),
      ],
    ),
    );
  }
}

class _GuestOrderIdModal extends StatelessWidget {
  const _GuestOrderIdModal({
    required this.order,
    required this.remaining,
    required this.tableNumber,
    required this.onMinimize,
  });

  final OrderRecord order;
  final ValueNotifier<Duration> remaining;
  final String tableNumber;
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Guest Order Placed!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBrown,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Seated at $tableNumber',
                        style: const TextStyle(
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
                            'YOUR ORDER REFERENCE',
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
                        const total = 1200; // 20 mins in seconds
                        final progress = (d.inSeconds / total).clamp(0.0, 1.0).toDouble();
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
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          expired ? AppColors.danger : AppColors.darkBrown,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          expired ? Icons.timer_off_outlined : Icons.timer_outlined,
                                          size: 18,
                                          color: expired ? AppColors.danger : AppColors.darkBrown,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _fmt(d),
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: expired ? AppColors.danger : AppColors.darkBrown,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkBrown,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onMinimize,
              child: const Text('Minimize & Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinimizedGuestOrderCard extends StatelessWidget {
  const _MinimizedGuestOrderCard({
    required this.order,
    required this.remaining,
    required this.tableNumber,
    required this.onTap,
  });

  final OrderRecord order;
  final ValueNotifier<Duration> remaining;
  final String tableNumber;
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
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.brown, size: 20),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'GUEST ORDER ($tableNumber)',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${order.displayOrderNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.brown),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
