import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// A compact, aligned item list for customer order cards and receipts.
/// Quantities, product names, add-ons and line totals keep a stable hierarchy
/// even on narrow phone screens.
class CustomerOrderItems extends StatelessWidget {
  const CustomerOrderItems({
    super.key,
    required this.items,
    this.showAddOns = true,
  });

  final List<CartItem> items;
  final bool showAddOns;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _CustomerOrderItem(item: items[index], showAddOns: showAddOns),
          if (index < items.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Divider(height: 1, color: AppColors.beige),
            ),
        ],
      ],
    );
  }
}

class _CustomerOrderItem extends StatelessWidget {
  const _CustomerOrderItem({required this.item, required this.showAddOns});

  final CartItem item;
  final bool showAddOns;

  @override
  Widget build(BuildContext context) {
    final addOns = item.selectedAddOns
        .map(
          (addOn) => addOn.quantity > 1
              ? '${addOn.quantity} × ${addOn.name}'
              : addOn.name,
        )
        .join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.beige,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '${item.quantity}×',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.darkBrown,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.2,
                  color: AppColors.darkBrown,
                ),
              ),
              if (showAddOns && item.selectedAddOns.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  addOns,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            peso(item.subtotal),
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppColors.darkBrown,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small, touch-friendly descriptor used for order type and payment method.
class CustomerOrderInfoChip extends StatelessWidget {
  const CustomerOrderInfoChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.beige,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.beigeDark, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.darkBrown),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.darkBrown,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
