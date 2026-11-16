import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

Uint8List compressImage(Uint8List originalBytes, {int maxDimension = 600, int quality = 80}) {
  try {
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) return originalBytes;

    img.Image resized = originalImage;
    if (originalImage.width > maxDimension || originalImage.height > maxDimension) {
      resized = img.copyResize(
        originalImage,
        width: originalImage.width > originalImage.height ? maxDimension : null,
        height: originalImage.height >= originalImage.width ? maxDimension : null,
      );
    }

    final compressedBytes = img.encodeJpg(resized, quality: quality);
    return Uint8List.fromList(compressedBytes);
  } catch (e) {
    debugPrint('Error compressing image: $e');
    return originalBytes;
  }
}

class _AddOnEntry {
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  String category; // 'Extras' or 'Flavors'
  bool allowQuantity;
  List<String> procurementItems;

  _AddOnEntry({
    String name = '',
    double price = 0.0,
    this.category = 'Extras',
    this.allowQuantity = false,
    List<String>? procurementItems,
  })  : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price > 0 ? _trimZero(price) : ''),
        procurementItems = procurementItems ?? [];

  static String _trimZero(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _MenuItemEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController(text: '50');
  String category = 'Coffee';
  String? imageBase64;
  Uint8List? imageBytes;
  final List<_AddOnEntry> addOns = [];

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    stockCtrl.dispose();
    for (final e in addOns) {
      e.dispose();
    }
  }
}

class MenuManagementScreen extends StatefulWidget {
  /// Employees get a view-only version: they can see stock levels and
  /// status/alerts (since stock updates automatically from the Kiosk/POS),
  /// but only Admin can add, edit, archive, or manually adjust stock.
  final bool readOnly;
  const MenuManagementScreen({super.key, this.readOnly = false});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  String _search = '';
  String _categoryFilter = 'All';

  final List<String> _menuCategories = [
    'Coffee',
    'Non-Coffee',
    'Matcha Series',
    'Refreshers',
    'Rice Meals',
    'Snacks',
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        var filtered = data.products
            .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
            .toList();

        if (_categoryFilter != 'All') {
          filtered = filtered.where((p) => p.category == _categoryFilter).toList();
        }

        final categories = ['All', ..._menuCategories];
        final outOfStock = data.outOfStockProducts;
        final lowStock = data.lowStockProducts;

        return SectionPage(
          children: [
            if (outOfStock.isNotEmpty)
              Card(
                color: AppColors.danger.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.remove_shopping_cart_outlined, color: AppColors.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'OUT OF STOCK — ${outOfStock.map((p) => p.name).join(", ")}. Hidden from the Kitchen and disabled on POS.',
                        style: const TextStyle(color: AppColors.darkBrown),
                      ),
                    ),
                  ]),
                ),
              ),
            if (lowStock.isNotEmpty) ...[
              const SizedBox(height: 10),
              Card(
                color: AppColors.warning.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'LOW STOCK ALERT — ${lowStock.map((p) => '${p.name} (${p.stockQuantity})').join(", ")} at or below ${Product.lowStockThreshold} items.',
                        style: const TextStyle(color: AppColors.darkBrown),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            if (outOfStock.isNotEmpty || lowStock.isNotEmpty) const SizedBox(height: 14),
            Builder(
              builder: (context) {
                final searchField = SizedBox(
                  height: 44,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search menu items...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                );

                final categoryDropdown = SizedBox(
                  height: 44,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _categoryFilter == 'All' || categories.contains(_categoryFilter) ? _categoryFilter : 'All',
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setState(() => _categoryFilter = v ?? 'All'),
                  ),
                );

                final bestSellerButton = SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => _showBestSellerManagementDialog(context),
                    icon: const Icon(Icons.local_fire_department_outlined, size: 16),
                    label: const Text('Best Sellers', overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                );

                final addOnsButton = SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => _showGlobalAddOnsSettingsDialog(context),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Add-ons', overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                );

                final addItemButton = SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => _showProductDialog(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Item', overflow: TextOverflow.ellipsis),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 950;
                    if (isWide) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: searchField,
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 170,
                            child: categoryDropdown,
                          ),
                          if (!widget.readOnly) ...[
                            const SizedBox(width: 8),
                            bestSellerButton,
                            const SizedBox(width: 6),
                            addOnsButton,
                            const SizedBox(width: 6),
                            addItemButton,
                          ],
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1st row: Search bar
                          searchField,
                          if (!widget.readOnly) ...[
                            const SizedBox(height: 8),
                            // 2nd row: Sort bar and Best Seller bar
                            Row(
                              children: [
                                Expanded(child: categoryDropdown),
                                const SizedBox(width: 8),
                                Expanded(child: bestSellerButton),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // 3rd row: Add-ons bar and Add Item bar
                            Row(
                              children: [
                                Expanded(child: addOnsButton),
                                const SizedBox(width: 8),
                                Expanded(child: addItemButton),
                              ],
                            ),
                          ],
                        ],
                      );
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            ResponsiveTable(
              columns: [
                const DataColumn(label: Text('Image')),
                const DataColumn(label: Text('Name')),
                const DataColumn(label: Text('Category')),
                const DataColumn(label: Text('Price')),
                const DataColumn(label: Text('Stock')),
                const DataColumn(label: Text('Add-ons')),
                const DataColumn(label: Text('Procurement')),
                const DataColumn(label: Text('Status')),
                const DataColumn(label: Text('Actions')),
              ],
              rows: filtered.map((p) {
                Uint8List? imageBytes;
                if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) {
                  try {
                    imageBytes = base64Decode(p.imageBase64!);
                  } catch (_) {}
                }

                return DataRow(cells: [
                  DataCell(
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.beige.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: imageBytes != null
                          ? Image.memory(
                              imageBytes,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            )
                          : const Icon(Icons.local_cafe_outlined, color: AppColors.brown, size: 20),
                    ),
                  ),
                  DataCell(Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(p.category)),
                  DataCell(Text(peso(p.price))),
                  DataCell(Text('${p.stockQuantity} / ${Product.maxStockQuantity}')),
                  DataCell(
                    InkWell(
                      onTap: widget.readOnly ? null : () => _showAddOnsDialog(context, p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.addOns.isNotEmpty ? AppColors.accent.withValues(alpha: 0.15) : AppColors.beige.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: p.addOns.isNotEmpty ? AppColors.accent : AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_outlined, size: 13, color: p.addOns.isNotEmpty ? AppColors.darkBrown : AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              p.addOns.isNotEmpty ? '${p.addOns.length} add-on(s)' : 'Add-ons',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: p.addOns.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                color: p.addOns.isNotEmpty ? AppColors.darkBrown : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    InkWell(
                      onTap: widget.readOnly ? null : () => _showProcurementOptionsDialog(context, p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.procurementItems.isNotEmpty ? AppColors.brown.withValues(alpha: 0.15) : AppColors.beige.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: p.procurementItems.isNotEmpty ? AppColors.brown : AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 13, color: p.procurementItems.isNotEmpty ? AppColors.darkBrown : AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              p.procurementItems.isNotEmpty ? '${p.procurementItems.length} procurement(s)' : 'Procurement',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: p.procurementItems.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                color: p.procurementItems.isNotEmpty ? AppColors.darkBrown : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DataCell(StatusBadge(status: p.stockStatus)),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!widget.readOnly) ...[
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 18),
                          tooltip: 'Decrease stock',
                          onPressed: p.stockQuantity <= 0
                              ? null
                              : () => AppData.instance.updateProductStock(p.id, p.stockQuantity - 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          tooltip: 'Restock +1',
                          onPressed: p.stockQuantity >= Product.maxStockQuantity
                              ? null
                              : () => AppData.instance.updateProductStock(p.id, p.stockQuantity + 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.brown),
                          onPressed: () => _showProductDialog(context, product: p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.danger),
                          onPressed: () => _confirmArchive(context, p),
                        ),
                      ] else ...[
                        IconButton(
                          icon: const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.warning),
                          tooltip: 'Notify Admin',
                          onPressed: () => _showNotifyAdminDialog(context, p),
                        ),
                      ],
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  void _showProductDialog(BuildContext context, {Product? product}) {
    if (product != null) {
      final nameCtrl = TextEditingController(text: product.name);
      String selectedCategory = product.category;
      if (!_menuCategories.contains(selectedCategory)) {
        selectedCategory = 'Coffee';
      }
      final priceCtrl = TextEditingController(text: product.price > 0 ? product.price.toStringAsFixed(0) : '');
      final stockCtrl = TextEditingController(text: '${product.stockQuantity}');
      String? imageBase64 = product.imageBase64;
      Uint8List? imageBytes;
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        try {
          imageBytes = base64Decode(imageBase64);
        } catch (_) {
          imageBytes = null;
        }
      }
      final List<_AddOnEntry> productAddOns = product.addOns.map((a) => _AddOnEntry(
        name: a.name,
        price: a.price,
        category: a.category,
        allowQuantity: a.allowQuantity,
        procurementItems: List.from(a.procurementItems),
      )).toList();

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final dialogWidth = (MediaQuery.of(ctx).size.width - 48).clamp(280.0, 500.0);
            return AlertDialog(
              title: Text('Edit Menu Item — ${product.name}'),
              content: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Product Name')),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: _menuCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setDialogState(() => selectedCategory = v ?? selectedCategory),
                      ),
                      const SizedBox(height: 10),
                      TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price (₱)'), keyboardType: TextInputType.number),
                      const SizedBox(height: 10),
                      TextField(
                        controller: stockCtrl,
                        decoration: const InputDecoration(labelText: 'Stock Quantity', helperText: '0 - 200'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Product picture', style: Theme.of(context).textTheme.labelLarge),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 130,
                          width: double.infinity,
                          color: AppColors.beige.withValues(alpha: 0.55),
                          child: imageBytes == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.photo_outlined, size: 30, color: AppColors.textMuted),
                                    SizedBox(height: 4),
                                    Text('No picture selected', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                  ],
                                )
                              : Image.memory(imageBytes!, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                                if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
                                final rawBytes = result.files.first.bytes!;
                                setDialogState(() {
                                  imageBytes = rawBytes;
                                  imageBase64 = base64Encode(rawBytes);
                                });
                                try {
                                  final compressedBytes = await compute(compressImage, rawBytes);
                                  imageBase64 = base64Encode(compressedBytes);
                                } catch (_) {}
                              },
                              icon: const Icon(Icons.upload_outlined, size: 16),
                              label: const Text('Upload picture'),
                            ),
                          ),
                          if (imageBytes != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Remove picture',
                              onPressed: () => setDialogState(() {
                                imageBytes = null;
                                imageBase64 = null;
                              }),
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            productAddOns.isEmpty ? 'Add-ons: None' : 'Add-ons (${productAddOns.length})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setDialogState(() => productAddOns.add(_AddOnEntry())),
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Add Add-on', style: TextStyle(fontSize: 11.5)),
                          ),
                        ],
                      ),
                      ...productAddOns.asMap().entries.map((aeEntry) {
                        final ai = aeEntry.key;
                        final ae = aeEntry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.cardWhite,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: ae.nameCtrl,
                                      decoration: const InputDecoration(labelText: 'Add-on Name', isDense: true),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: ae.priceCtrl,
                                      decoration: const InputDecoration(labelText: 'Price (₱)', isDense: true),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => setDialogState(() {
                                      ae.dispose();
                                      productAddOns.removeAt(ai);
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: ae.category,
                                      decoration: const InputDecoration(labelText: 'Category', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                      items: const [
                                        DropdownMenuItem(value: 'Extras', child: Text('Extras')),
                                        DropdownMenuItem(value: 'Flavors', child: Text('Flavors')),
                                      ],
                                      onChanged: (v) => setDialogState(() => ae.category = v ?? 'Extras'),
                                    ),
                                  ),
                                  if (ae.category == 'Extras') ...[
                                    const SizedBox(width: 8),
                                    const Text('Qty', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                    Switch.adaptive(
                                      value: ae.allowQuantity,
                                      onChanged: (v) => setDialogState(() => ae.allowQuantity = v),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final price = double.tryParse(priceCtrl.text) ?? 0.0;
                    final rawStock = int.tryParse(stockCtrl.text.trim()) ?? product.stockQuantity;

                    if (name.isEmpty || price <= 0) {
                      showAppSnack(context, 'Please enter valid product name and price.');
                      return;
                    }

                    final addOnsList = productAddOns.where((ae) => ae.nameCtrl.text.trim().isNotEmpty && (double.tryParse(ae.priceCtrl.text.trim()) ?? -1) >= 0).map((ae) => MenuAddOn(
                      name: ae.nameCtrl.text.trim(),
                      price: double.tryParse(ae.priceCtrl.text.trim()) ?? 0.0,
                      category: ae.category,
                      allowQuantity: ae.category == 'Extras' ? ae.allowQuantity : false,
                      procurementItems: ae.procurementItems,
                    )).toList();

                    AppData.instance.updateProduct(
                      product.id,
                      name,
                      selectedCategory,
                      price,
                      product.description,
                      stockQuantity: rawStock,
                      imageBase64: imageBase64,
                    );
                    Navigator.pop(ctx);
                    showAppSnack(context, 'Product updated successfully.');
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        ),
      );
    } else {
      List<_MenuItemEntry> entries = [_MenuItemEntry()];
      final ScrollController scrollController = ScrollController();

      void scrollToBottom() {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final dialogWidth = (MediaQuery.of(ctx).size.width - 48).clamp(280.0, 640.0);

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.playlist_add_rounded, color: AppColors.brown),
                  SizedBox(width: 8),
                  Text('Add Menu Item(s)'),
                ],
              ),
              content: SizedBox(
                width: dialogWidth,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add one or multiple items with name, category, price, stock, picture, and add-ons:',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...entries.asMap().entries.map((entry) {
                              final i = entry.key;
                              final e = entry.value;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.beige.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Text('Item #${i + 1}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                                color: AppColors.darkBrown)),
                                        const Spacer(),
                                        if (entries.length > 1)
                                          IconButton(
                                            icon: const Icon(Icons.close_rounded,
                                                size: 18, color: AppColors.danger),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              setDialogState(() {
                                                e.dispose();
                                                entries.removeAt(i);
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: e.nameCtrl,
                                      decoration: const InputDecoration(labelText: 'Product Name', isDense: true),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            isExpanded: true,
                                            initialValue: e.category,
                                            decoration: const InputDecoration(labelText: 'Category', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                                            items: _menuCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                                            onChanged: (v) => setDialogState(() => e.category = v ?? e.category),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: e.priceCtrl,
                                            decoration: const InputDecoration(labelText: 'Price (₱)', isDense: true),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: e.stockCtrl,
                                            decoration: const InputDecoration(labelText: 'Stock', isDense: true),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            height: 50,
                                            width: 50,
                                            color: AppColors.beige,
                                            child: e.imageBytes == null
                                                ? const Icon(Icons.photo_outlined, size: 20, color: AppColors.textMuted)
                                                : Image.memory(e.imageBytes!, fit: BoxFit.cover),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                                              if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
                                              final rawBytes = result.files.first.bytes!;
                                              setDialogState(() {
                                                e.imageBytes = rawBytes;
                                                e.imageBase64 = base64Encode(rawBytes);
                                              });
                                              try {
                                                final compressed = await compute(compressImage, rawBytes);
                                                e.imageBase64 = base64Encode(compressed);
                                              } catch (_) {}
                                            },
                                            icon: const Icon(Icons.upload_outlined, size: 14),
                                            label: Text(e.imageBytes == null ? 'Upload picture' : 'Change picture', style: const TextStyle(fontSize: 11.5)),
                                          ),
                                        ),
                                        if (e.imageBytes != null)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                                            onPressed: () => setDialogState(() {
                                              e.imageBytes = null;
                                              e.imageBase64 = null;
                                            }),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Text(
                                          e.addOns.isEmpty ? 'Add-ons: None' : 'Add-ons (${e.addOns.length})',
                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.darkBrown),
                                        ),
                                        const Spacer(),
                                        TextButton.icon(
                                          onPressed: () => setDialogState(() => e.addOns.add(_AddOnEntry())),
                                          icon: const Icon(Icons.add, size: 14),
                                          label: const Text('Add Add-on', style: TextStyle(fontSize: 11.5)),
                                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 24)),
                                        ),
                                      ],
                                    ),
                                    if (e.addOns.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      ...e.addOns.asMap().entries.map((addOnEntry) {
                                        final ai = addOnEntry.key;
                                        final ae = addOnEntry.value;
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.cardWhite,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: AppColors.border),
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    flex: 3,
                                                    child: TextField(
                                                      controller: ae.nameCtrl,
                                                      decoration: const InputDecoration(labelText: 'Add-on Name', isDense: true),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    flex: 2,
                                                    child: TextField(
                                                      controller: ae.priceCtrl,
                                                      decoration: const InputDecoration(labelText: 'Price (₱)', isDense: true),
                                                      keyboardType: TextInputType.number,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onPressed: () => setDialogState(() {
                                                      ae.dispose();
                                                      e.addOns.removeAt(ai);
                                                    }),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: DropdownButtonFormField<String>(
                                                      value: ae.category,
                                                      decoration: const InputDecoration(labelText: 'Category', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                                      items: const [
                                                        DropdownMenuItem(value: 'Extras', child: Text('Extras')),
                                                        DropdownMenuItem(value: 'Flavors', child: Text('Flavors')),
                                                      ],
                                                      onChanged: (v) => setDialogState(() => ae.category = v ?? 'Extras'),
                                                    ),
                                                  ),
                                                  if (ae.category == 'Extras') ...[
                                                    const SizedBox(width: 8),
                                                    const Text('Qty', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                                    Switch.adaptive(
                                                      value: ae.allowQuantity,
                                                      onChanged: (v) => setDialogState(() => ae.allowQuantity = v),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Sticky / Non-scrolling "Add Another Item Row" button
                    OutlinedButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          entries.add(_MenuItemEntry());
                        });
                        scrollToBottom();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Another Item Row'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    for (final e in entries) {
                      e.dispose();
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.brown, foregroundColor: Colors.white),
                  onPressed: () async {
                    final validItems = <Map<String, dynamic>>[];
                    for (final e in entries) {
                      final name = e.nameCtrl.text.trim();
                      final price = double.tryParse(e.priceCtrl.text.trim()) ?? 0.0;
                      final stock = int.tryParse(e.stockCtrl.text.trim()) ?? 50;
                      if (name.isNotEmpty && price > 0) {
                        final addOnsList = <MenuAddOn>[];
                        for (final ae in e.addOns) {
                          final aname = ae.nameCtrl.text.trim();
                          final aprice = double.tryParse(ae.priceCtrl.text.trim()) ?? 0.0;
                          if (aname.isNotEmpty && aprice >= 0) {
                            addOnsList.add(MenuAddOn(
                              name: aname,
                              price: aprice,
                              category: ae.category,
                              allowQuantity: ae.category == 'Extras' ? ae.allowQuantity : false,
                              procurementItems: ae.procurementItems,
                            ));
                          }
                        }
                        validItems.add({
                          'name': name,
                          'category': e.category,
                          'price': price,
                          'stock': stock,
                          'imageBase64': e.imageBase64 ?? '',
                          'addOns': addOnsList,
                        });
                      }
                    }

                    if (validItems.isEmpty) {
                      showAppSnack(context, 'Please enter at least one valid product name and price.');
                      return;
                    }

                    await AppData.instance.addBatchProducts(validItems);

                    for (final e in entries) {
                      e.dispose();
                    }

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      showAppSnack(context, 'Successfully added ${validItems.length} menu item(s)!');
                    }
                  },
                  child: const Text('Save Item(s)'),
                ),
              ],
            );
          },
        ),
      );
    }
  }

  /// Employee-only: lets an employee flag a menu item to Admin without
  /// touching stock levels themselves. Purely a notification — does not
  /// call [AppData.updateProductStock] or alter any stock management logic.
  void _showNotifyAdminDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notify Admin — ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current stock: ${product.stockQuantity} / ${Product.maxStockQuantity}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text('Choose what to notify Admin about:'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined, color: AppColors.brown),
              title: const Text('Restock Needed'),
              subtitle: const Text('Ask Admin to reorder/restock this item.'),
              onTap: () => _sendAdminNotification(context, ctx, product, restockNeeded: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              title: const Text('Low Stock Alert'),
              subtitle: const Text('Flag this item as running low.'),
              onTap: () => _sendAdminNotification(context, ctx, product, restockNeeded: false),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _sendAdminNotification(BuildContext context, BuildContext dialogCtx, Product product,
      {required bool restockNeeded}) async {
    Navigator.pop(dialogCtx);
    await AppData.instance.notifyAdminAboutProduct(product, restockNeeded: restockNeeded);
    if (!context.mounted) return;
    showAppSnack(
      context,
      restockNeeded
          ? 'Admin notified: "${product.name}" needs restocking.'
          : 'Admin notified: "${product.name}" is low on stock.',
    );
  }

  void _confirmArchive(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Menu Item?'),
        content: Text('Are you sure you want to archive "${product.name}"? This removes it from the customer kitchen and employee POS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              AppData.instance.archiveProduct(product.id);
              Navigator.pop(ctx);
              showAppSnack(context, '"${product.name}" archived successfully.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _showBestSellerManagementDialog(BuildContext context) {
    String search = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final data = AppData.instance;
          final allProducts = data.products
              .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
              .toList();
          final checkedCount = data.products.where((p) => p.isBestSeller).length;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_fire_department_outlined, color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Best Seller Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('$checkedCount item(s) selected as Best Seller',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              height: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search menu items to toggle as Best Seller...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onChanged: (v) => setDialogState(() => search = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: allProducts.isEmpty
                        ? const Center(child: Text('No products found.', style: TextStyle(color: AppColors.textMuted)))
                        : ListView.builder(
                            itemCount: allProducts.length,
                            itemBuilder: (ctx, i) {
                              final p = allProducts[i];
                              Uint8List? imgBytes;
                              if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) {
                                try {
                                  imgBytes = base64Decode(p.imageBase64!);
                                } catch (_) {}
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: CheckboxListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  secondary: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.beige,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    alignment: Alignment.center,
                                    child: imgBytes != null
                                        ? Image.memory(
                                            imgBytes,
                                            width: 36,
                                            height: 36,
                                            fit: BoxFit.cover,
                                          )
                                        : const Icon(Icons.local_cafe_outlined, color: AppColors.brown, size: 18),
                                  ),
                                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  subtitle: Text('${p.category} · ${peso(p.price)}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  value: p.isBestSeller,
                                  onChanged: (val) async {
                                    await data.updateProductBestSeller(p.id, val ?? false);
                                    setDialogState(() {});
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGlobalAddOnsSettingsDialog(BuildContext context) {
    final entries = AppData.instance.globalAddOns
        .map((a) => _AddOnEntry(
              name: a.name,
              price: a.price,
              category: a.category,
              allowQuantity: a.allowQuantity,
              procurementItems: List.from(a.procurementItems),
            ))
        .toList();
    final scrollController = ScrollController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.darkBrown,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.tune_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 13),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Global Add-ons & Flavors', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
                              SizedBox(height: 5),
                              Text('Manage master list of extras and flavors available for menu items.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            for (final e in entries) e.dispose();
                            Navigator.pop(ctx);
                          },
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: entries.isEmpty
                          ? Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.beige.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Text('No global add-ons yet', style: TextStyle(fontWeight: FontWeight.w800)),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: entries.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final e = entries[i];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardWhite,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: e.nameCtrl,
                                              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Oat milk / Caramel', isDense: true),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 100,
                                            child: TextField(
                                              controller: e.priceCtrl,
                                              decoration: const InputDecoration(labelText: 'Price (₱)', isDense: true),
                                              keyboardType: TextInputType.number,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => setDialogState(() {
                                              e.dispose();
                                              entries.removeAt(i);
                                            }),
                                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              value: e.category,
                                              decoration: const InputDecoration(labelText: 'Category', isDense: true),
                                              items: const [
                                                DropdownMenuItem(value: 'Extras', child: Text('Extras')),
                                                DropdownMenuItem(value: 'Flavors', child: Text('Flavors')),
                                              ],
                                              onChanged: (v) => setDialogState(() => e.category = v ?? 'Extras'),
                                            ),
                                          ),
                                          if (e.category == 'Extras') ...[
                                            const SizedBox(width: 12),
                                            const Text('Quantity', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                                            const SizedBox(width: 6),
                                            Switch.adaptive(
                                              value: e.allowQuantity,
                                              onChanged: (v) => setDialogState(() => e.allowQuantity = v),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              icon: const Icon(Icons.inventory_2_outlined, size: 16),
                                              label: Text(e.procurementItems.isEmpty ? 'Link Procurement' : 'Procurement (${e.procurementItems.length})'),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                minimumSize: const Size(0, 32),
                                              ),
                                              onPressed: () => _showAddOnProcurementDialog(context, e, setDialogState),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          entries.add(_AddOnEntry());
                        });
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (scrollController.hasClients) {
                            scrollController.animateTo(
                              scrollController.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add another add-on / flavor'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            for (final e in entries) e.dispose();
                            Navigator.pop(ctx);
                          },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            final newAddOns = <MenuAddOn>[];
                            for (final e in entries) {
                              final name = e.nameCtrl.text.trim();
                              final price = double.tryParse(e.priceCtrl.text.trim()) ?? 0.0;
                              if (name.isNotEmpty && price >= 0) {
                                newAddOns.add(MenuAddOn(
                                  name: name,
                                  price: price,
                                  category: e.category,
                                  allowQuantity: e.category == 'Extras' ? e.allowQuantity : false,
                                  procurementItems: e.procurementItems,
                                ));
                              }
                            }
                            await AppData.instance.saveGlobalAddOns(newAddOns);
                            for (final e in entries) e.dispose();
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              showAppSnack(context, 'Global add-ons updated successfully.');
                            }
                          },
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Save changes'),
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

  void _showProcurementOptionsDialog(BuildContext context, Product product) {
    final allProcurementItems = {
      for (final proc in AppData.instance.procurement) proc.productName
    }.toList();

    final selectedMap = <String, bool>{
      for (var name in allProcurementItems) name: product.procurementItems.any((pi) => pi.toLowerCase() == name.toLowerCase())
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: AppColors.brown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Procurement Options — ${product.name}', overflow: TextOverflow.ellipsis),
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
                    const Text(
                      'Select items from procurement linked to this menu product:',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    if (allProcurementItems.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.beige.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'No procurement items found. Add items in Procurement first.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                        ),
                      ),
                    ...allProcurementItems.map((itemName) {
                      final isChecked = selectedMap[itemName] ?? false;
                      return CheckboxListTile(
                        title: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        value: isChecked,
                        activeColor: AppColors.brown,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setDialogState(() {
                            selectedMap[itemName] = val ?? false;
                          });
                        },
                      );
                    }),
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
                  backgroundColor: AppColors.brown,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final updatedItems = <String>[];
                  for (final name in allProcurementItems) {
                    if (selectedMap[name] == true) {
                      updatedItems.add(name);
                    }
                  }

                  await AppData.instance.updateProductProcurementItems(product.id, updatedItems);

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    showAppSnack(context, 'Procurement items updated for "${product.name}".');
                  }
                },
                child: const Text('Save Procurement'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddOnProcurementDialog(BuildContext context, _AddOnEntry entry, StateSetter parentSetState) {
    final allProcurementItems = {
      for (final proc in AppData.instance.procurement) proc.productName
    }.toList();

    final selectedMap = <String, bool>{
      for (var name in allProcurementItems) name: entry.procurementItems.contains(name)
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Link Procurement — ${entry.nameCtrl.text.isEmpty ? 'New Add-on' : entry.nameCtrl.text}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Select raw inventory items consumed by this add-on/flavor:', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  if (allProcurementItems.isEmpty)
                    const Text('No procurement items found.', style: TextStyle(color: AppColors.textMuted)),
                  ...allProcurementItems.map((itemName) {
                    final isChecked = selectedMap[itemName] ?? false;
                    return CheckboxListTile(
                      title: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      value: isChecked,
                      activeColor: AppColors.brown,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedMap[itemName] = val ?? false;
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brown, foregroundColor: Colors.white),
              onPressed: () {
                parentSetState(() {
                  entry.procurementItems = allProcurementItems.where((name) => selectedMap[name] == true).toList();
                });
                Navigator.pop(ctx);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOnsDialog(BuildContext context, Product product) {
    final globalAddOns = AppData.instance.globalAddOns;
    final Map<String, bool> selectedMap = {
      for (var ga in globalAddOns) ga.name: product.addOns.any((pA) => pA.name.toLowerCase() == ga.name.toLowerCase())
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final flavors = globalAddOns.where((a) => a.category == 'Flavors').toList();
          final extras = globalAddOns.where((a) => a.category != 'Flavors').toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.tune_outlined, color: AppColors.brown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Add-ons Checklist — ${product.name}', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              height: 500,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Check the global add-ons & flavors allowed for this menu item:',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    if (globalAddOns.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.beige.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'No global add-ons configured. Click "Add-ons" at the top of Menu Management to create global add-ons first.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                        ),
                      ),
                    if (flavors.isNotEmpty) ...[
                      const Text('Flavors', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.darkBrown)),
                      const SizedBox(height: 6),
                      ...flavors.map((ga) {
                        final isChecked = selectedMap[ga.name] ?? false;
                        return CheckboxListTile(
                          title: Text(ga.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(peso(ga.price), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          value: isChecked,
                          activeColor: AppColors.brown,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            setDialogState(() {
                              selectedMap[ga.name] = val ?? false;
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                    if (extras.isNotEmpty) ...[
                      const Text('Extras', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.darkBrown)),
                      const SizedBox(height: 6),
                      ...extras.map((ga) {
                        final isChecked = selectedMap[ga.name] ?? false;
                        return CheckboxListTile(
                          title: Text(ga.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text('${peso(ga.price)}${ga.allowQuantity ? ' · repeatable qty' : ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          value: isChecked,
                          activeColor: AppColors.brown,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            setDialogState(() {
                              selectedMap[ga.name] = val ?? false;
                            });
                          },
                        );
                      }),
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
                  backgroundColor: AppColors.brown,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final updatedAddOns = <MenuAddOn>[];
                  for (final ga in globalAddOns) {
                    if (selectedMap[ga.name] == true) {
                      updatedAddOns.add(ga);
                    }
                  }

                  await AppData.instance.updateProductAddOns(product.id, updatedAddOns);

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    showAppSnack(context, 'Add-ons checklist updated for "${product.name}".');
                  }
                },
                child: const Text('Save Add-ons'),
              ),
            ],
          );
        },
      ),
    );
  }
}





