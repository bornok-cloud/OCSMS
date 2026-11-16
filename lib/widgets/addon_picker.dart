import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Shared add-on selection surface for the customer and both POS experiences.
/// Supports Categories ('Extras', 'Flavors'). Flavors are 1 selection only (single choice).
Future<List<MenuAddOn>?> showAddOnPickerDialog({
  required BuildContext context,
  required Product product,
  required String helperText,
  List<MenuAddOn>? initial,
}) {
  final quantities = <String, int>{
    for (final a in initial ?? const <MenuAddOn>[]) a.name: a.quantity,
  };
  String? selectedFlavor = initial
      ?.where((a) => a.category == 'Flavors' && a.quantity > 0)
      .map((a) => a.name)
      .firstOrNull;

  final flavors = product.addOns.where((a) => a.category == 'Flavors').toList();
  final extras = product.addOns.where((a) => a.category != 'Flavors').toList();

  return showDialog<List<MenuAddOn>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final selectedExtrasCount =
            extras.where((e) => (quantities[e.name] ?? 0) > 0).length;
        final hasFlavorSelected = selectedFlavor != null;
        final totalSelectedCount =
            selectedExtrasCount + (hasFlavorSelected ? 1 : 0);

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              minHeight: MediaQuery.sizeOf(ctx).height * 0.72,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.darkBrown,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customize your ${product.name}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              helperText,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.beige.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            totalSelectedCount == 0
                                ? 'No customization selected'
                                : '$totalSelectedCount customization${totalSelectedCount == 1 ? '' : 's'} selected',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brown,
                            ),
                          ),
                        ),
                        Text(
                          '${product.addOns.length} available',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      children: [
                        if (flavors.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Flavors (Choose 1)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.darkBrown,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...flavors.map((flavor) {
                            final isSelected = selectedFlavor == flavor.name;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: isSelected
                                    ? AppColors.darkBrown.withValues(
                                        alpha: 0.045,
                                      )
                                    : AppColors.cardWhite,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => setDialogState(() {
                                    if (selectedFlavor == flavor.name) {
                                      selectedFlavor = null;
                                    } else {
                                      selectedFlavor = flavor.name;
                                    }
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      10,
                                      12,
                                      10,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.darkBrown.withValues(
                                                alpha: 0.55,
                                              )
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Radio<String?>(
                                          value: flavor.name,
                                          groupValue: selectedFlavor,
                                          activeColor: AppColors.brown,
                                          onChanged: (val) =>
                                              setDialogState(() {
                                            selectedFlavor = val;
                                          }),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                flavor.name,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '+${peso(flavor.price)}',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                        ],
                        if (extras.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Extras',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.darkBrown,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...extras.map((extra) {
                            final canQty = extra.allowQuantity;
                            final rawQuantity = quantities[extra.name] ?? 0;
                            final quantity = canQty
                                ? rawQuantity
                                : (rawQuantity > 0 ? 1 : 0);
                            final selected = quantity > 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: selected
                                    ? AppColors.darkBrown.withValues(
                                        alpha: 0.045,
                                      )
                                    : AppColors.cardWhite,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => setDialogState(() {
                                    quantities[extra.name] = selected ? 0 : 1;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      10,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.darkBrown.withValues(
                                                alpha: 0.55,
                                              )
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: selected,
                                          activeColor: AppColors.brown,
                                          onChanged: (checked) =>
                                              setDialogState(() {
                                            quantities[extra.name] =
                                                checked == true ? 1 : 0;
                                          }),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                extra.name,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                canQty
                                                    ? '+${peso(extra.price)} each · choose quantity'
                                                    : '+${peso(extra.price)}',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (canQty)
                                          Container(
                                            decoration: BoxDecoration(
                                              color: AppColors.cardWhite,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: AppColors.border,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip:
                                                      'Decrease ${extra.name}',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  icon: const Icon(
                                                    Icons.remove_rounded,
                                                    size: 17,
                                                  ),
                                                  onPressed: quantity <= 0
                                                      ? null
                                                      : () => setDialogState(
                                                            () => quantities[
                                                                    extra
                                                                        .name] =
                                                                quantity - 1,
                                                          ),
                                                ),
                                                SizedBox(
                                                  width: 22,
                                                  child: Text(
                                                    '$quantity',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip:
                                                      'Increase ${extra.name}',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  icon: const Icon(
                                                    Icons.add_rounded,
                                                    size: 17,
                                                  ),
                                                  onPressed: quantity >= 99
                                                      ? null
                                                      : () => setDialogState(
                                                            () => quantities[
                                                                    extra
                                                                        .name] =
                                                                quantity + 1,
                                                          ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(
                                              Icons
                                                  .check_circle_outline_rounded,
                                              size: 18,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            final picked = <MenuAddOn>[];
                            if (selectedFlavor != null) {
                              final f = flavors.firstWhere(
                                (fl) => fl.name == selectedFlavor,
                              );
                              picked.add(
                                MenuAddOn(
                                  name: f.name,
                                  price: f.price,
                                  quantity: 1,
                                  category: 'Flavors',
                                  allowQuantity: false,
                                  procurementItems: List.from(
                                    f.procurementItems,
                                  ),
                                ),
                              );
                            }
                            for (final e in extras) {
                              final q = quantities[e.name] ?? 0;
                              if (q > 0) {
                                picked.add(
                                  MenuAddOn(
                                    name: e.name,
                                    price: e.price,
                                    quantity: e.allowQuantity ? q : 1,
                                    category: 'Extras',
                                    allowQuantity: e.allowQuantity,
                                    procurementItems: List.from(
                                      e.procurementItems,
                                    ),
                                  ),
                                );
                              }
                            }
                            Navigator.pop(ctx, picked);
                          },
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            totalSelectedCount == 0
                                ? 'Add'
                                : MediaQuery.sizeOf(ctx).width < 380
                                    ? 'Apply'
                                    : 'Apply customization',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
