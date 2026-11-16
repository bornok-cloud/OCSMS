import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_data.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

/// Presentation-only widgets for the Customer side (Menu / cart).
///
/// IMPORTANT: nothing in this file owns state or business logic. Every action
/// (add to cart, change quantity, edit add-ons, place order) is passed in as a
/// callback from the screen that already implements it, and every number shown
/// (prices, totals) is passed in by that screen, never calculated here.

/// Small accent palette used ONLY for badges/status dots. The app-wide
/// [AppColors] palette is left untouched.
class CustomerUiColors {
  static const amber = Color(0xFFF5B301);
  static const amberSoft = Color(0xFFFFF4D6);
  static const amberText = Color(0xFF7A4F00);
  static const live = Color(0xFF22A06B);
  static const liveSoft = Color(0xFFE6F6EE);
  static const pageGray = Color(0xFFF7F7F7);
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// Rounded pill with a status dot, e.g. "Ordering Open".
class CustomerStatusChip extends StatelessWidget {
  const CustomerStatusChip({super.key, required this.label, this.active = true});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final dot = active ? CustomerUiColors.live : AppColors.textMuted;
    final bg = active ? CustomerUiColors.liveSoft : AppColors.beige;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: active ? const Color(0xFF14663F) : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// [CustomerStatusChip] wired to the existing ordering-window check
/// (read-only: it only calls [AppData.isWithinOrderingWindow]).
class CustomerOrderingStatusChip extends StatelessWidget {
  const CustomerOrderingStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final open = AppData.instance.isWithinOrderingWindow();
        return CustomerStatusChip(
          label: open ? 'Ordering Open' : 'Ordering Closed',
          active: open,
        );
      },
    );
  }
}

/// Status card pinned to the bottom of the dark sidebar.
class CustomerSidebarStatusCard extends StatelessWidget {
  const CustomerSidebarStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final open = AppData.instance.isWithinOrderingWindow();
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: open
                          ? CustomerUiColors.live
                          : Colors.white.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      open ? 'Store Active' : 'Ordering Closed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                open
                    ? 'Dine In, Take Out & Pickup ready.'
                    : 'Operating hours: 7:00 PM – 2:00 AM.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Red-tinted strip used for the "ordering is closed" message.
class CustomerNoticeStrip extends StatelessWidget {
  const CustomerNoticeStrip({
    super.key,
    required this.message,
    this.compact = false,
  });

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 6 : 10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.danger,
          fontSize: compact ? 11 : 11.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search + categories
// ---------------------------------------------------------------------------

class CustomerSearchField extends StatelessWidget {
  const CustomerSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: 'Search menu items...',
        hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true,
        fillColor: AppColors.cardWhite,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        enabledBorder: border(AppColors.border),
        border: border(AppColors.border),
        focusedBorder: border(AppColors.darkBrown, 1.4),
      ),
    );
  }
}

/// Category pill. Selected = solid black pill (optionally with a count).
class CustomerCategoryChip extends StatelessWidget {
  const CustomerCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.darkBrown;
    return Material(
      color: selected ? AppColors.darkBrown : AppColors.cardWhite,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.darkBrown : AppColors.border,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (selected && count != null) ...[
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product card
// ---------------------------------------------------------------------------

class _CardBadge extends StatelessWidget {
  const _CardBadge({
    required this.text,
    required this.background,
    required this.foreground,
    required this.border,
    this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final Color border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact product card: image, name, 1-line description, price and a black
/// round "+" button. Tapping anywhere on the card calls [onTap] (which is the
/// screen's existing add-to-cart handler).
class CustomerProductCard extends StatelessWidget {
  const CustomerProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.popular = false,
    this.compact = false,
  });

  final Product product;
  final VoidCallback onTap;
  final bool popular;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final description = p.description.trim().isNotEmpty
        ? p.description.trim()
        : (p.addOns.isNotEmpty ? 'Customize with add-ons' : p.category);

    return InteractiveProductCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ProductImage(
                  imageBase64: p.imageBase64,
                  height: compact ? 84 : 92,
                ),
                if (popular || p.isLowStock)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (popular)
                          const _CardBadge(
                            text: 'Popular',
                            icon: Icons.local_fire_department_rounded,
                            background: Colors.white,
                            foreground: AppColors.darkBrown,
                            border: AppColors.border,
                          ),
                        if (popular && p.isLowStock) const SizedBox(height: 4),
                        if (p.isLowStock)
                          _CardBadge(
                            text: 'Only ${p.stockQuantity} left',
                            background: CustomerUiColors.amberSoft,
                            foreground: CustomerUiColors.amberText,
                            border: CustomerUiColors.amber,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              peso(p.price),
              maxLines: 1,
              style: const TextStyle(
                color: AppColors.darkBrown,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cart
// ---------------------------------------------------------------------------

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null
                ? AppColors.textMuted.withValues(alpha: 0.45)
                : AppColors.darkBrown,
          ),
        ),
      ),
    );
  }
}

/// One cart line. All behavior is injected:
///  * [onDecrement]  – existing "quantity--, remove at 0" handler
///  * [onIncrement]  – existing "quantity++" handler, or null when at max stock
///  * [onEditAddOns] – existing add-on picker handler, or null if the product
///                     has no add-ons
class CustomerCartItemTile extends StatelessWidget {
  const CustomerCartItemTile({
    super.key,
    required this.item,
    required this.onDecrement,
    required this.onIncrement,
    required this.onEditAddOns,
  });

  final CartItem item;
  final VoidCallback onDecrement;
  final VoidCallback? onIncrement;
  final VoidCallback? onEditAddOns;

  @override
  Widget build(BuildContext context) {
    final c = item;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.beigeDark),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: ProductImage(imageBase64: c.product.imageBase64, height: 52),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (c.selectedAddOns.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    c.selectedAddOns
                        .map(
                          (a) => a.quantity > 1
                              ? '${a.quantity} × ${a.name} (+${peso(a.price * a.quantity)})'
                              : '+ ${a.name} (+${peso(a.price)})',
                        )
                        .join(', '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (onEditAddOns != null)
                  InkWell(
                    onTap: onEditAddOns,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Text(
                        'Edit add-ons',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.brown,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.beige,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.beigeDark),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StepperButton(
                            icon: Icons.remove_rounded,
                            onTap: onDecrement,
                            semanticLabel: 'Decrease quantity',
                          ),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${c.quantity}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          _StepperButton(
                            icon: Icons.add_rounded,
                            onTap: onIncrement,
                            semanticLabel: 'Increase quantity',
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      peso(c.subtotal),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBrown,
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
  }
}

/// Empty-cart placeholder (same message as before).
class CustomerEmptyCart extends StatelessWidget {
  const CustomerEmptyCart({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.beige,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: AppColors.textMuted,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Item-count pill shown beside the "Your Order" title.
class CustomerCountBadge extends StatelessWidget {
  const CustomerCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.darkBrown,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count ${count == 1 ? 'item' : 'items'}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Summary block + big black "Place Order" button.
///
/// [total] is the value the screen already computes (`_total`); nothing is
/// recalculated here. [onPlaceOrder] is the screen's existing `_placeOrder`.
/// Pass `showPlaceOrder: false` to render the summary only (used in the
/// mobile cart sheet, which never had a Place Order button).
class CustomerOrderSummary extends StatelessWidget {
  const CustomerOrderSummary({
    super.key,
    required this.total,
    required this.itemCount,
    this.onPlaceOrder,
    this.showPlaceOrder = true,
  });

  final double total;
  final int itemCount;
  final VoidCallback? onPlaceOrder;
  final bool showPlaceOrder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CustomerUiColors.pageGray,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.beigeDark),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Items',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$itemCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: AppColors.beigeDark),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    peso(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      letterSpacing: -0.5,
                      color: AppColors.darkBrown,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showPlaceOrder) ...[
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onPlaceOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkBrown,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.beigeDark,
              disabledForegroundColor: AppColors.textMuted,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Place Order',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    peso(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Order type and payment method are chosen at checkout.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}
