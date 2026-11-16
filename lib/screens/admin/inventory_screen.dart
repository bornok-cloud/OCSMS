import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class InventoryScreen extends StatefulWidget {
  final bool readOnly;
  const InventoryScreen({super.key, this.readOnly = false});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _search = '';
  String _filter = 'All';
  String _selectedTab = 'Inventory Item'; // 'Inventory Item' or 'Kitchen Item'

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        var items = data.inventory
            .where((i) =>
                i.productName.toLowerCase().contains(_search.toLowerCase()) &&
                i.itemType == _selectedTab)
            .toList();
        if (_filter != 'All') {
          items = items.where((i) => i.status == _filter).toList();
        }
        items.sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
        final lowStockAlerts = data.inventory
            .where((i) => (i.status == 'Low Stock' || i.status == 'Out of Stock') && i.itemType == _selectedTab)
            .toList();
        final nearExpiry =
            data.inventory.where((i) => i.status == 'Near Expiration' && i.itemType == _selectedTab).toList();

        return SectionPage(children: [
          Builder(
            builder: (context) {
              final searchField = SizedBox(
                height: 44,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search ${_selectedTab.toLowerCase()}s...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              );

              final filterDropdown = SizedBox(
                height: 44,
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    'All',
                    'In Stock',
                    'Low Stock',
                    'Out of Stock',
                    'Near Expiration',
                    'Expired'
                  ].map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(
                          f,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      )).toList(),
                  onChanged: (v) => setState(() => _filter = v ?? 'All'),
                ),
              );

              final inventoryChip = ChoiceChip(
                label: const Text('Inventory Items'),
                selected: _selectedTab == 'Inventory Item',
                onSelected: (sel) => setState(() => _selectedTab = 'Inventory Item'),
              );

              final kitchenChip = ChoiceChip(
                label: const Text('Kitchen Items'),
                selected: _selectedTab == 'Kitchen Item',
                onSelected: (sel) => setState(() => _selectedTab = 'Kitchen Item'),
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
                        const SizedBox(width: 12),
                        inventoryChip,
                        const SizedBox(width: 8),
                        kitchenChip,
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 170,
                          child: filterDropdown,
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1st row: Search bar and Sort bar
                        Row(
                          children: [
                            Expanded(child: searchField),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 150,
                              child: filterDropdown,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 2nd row: Inventory Items chip and Kitchen Items chip side-by-side
                        Row(
                          children: [
                            Expanded(
                              child: Center(child: inventoryChip),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Center(child: kitchenChip),
                            ),
                          ],
                        ),
                      ],
                    );
                  }
                },
              );
            },
          ),
          const SizedBox(height: 16),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Quantity')),
              DataColumn(label: Text('Unit')),
              DataColumn(label: Text('Min. Stock')),
              DataColumn(label: Text('Expiration')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: items.map((i) {
              return DataRow(cells: [
                DataCell(Text(i.productName)),
                DataCell(Text('${i.quantity}')),
                DataCell(Text(i.unit)),
                DataCell(Text('${i.minimumStock}')),
                DataCell(Text(i.expiration != null
                    ? '${i.expiration!.month}/${i.expiration!.day}/${i.expiration!.year}'
                    : '—')),
                DataCell(StatusBadge(status: i.status)),
                DataCell(
                  widget.readOnly || data.currentUser?.role != UserRole.admin
                      ? IconButton(
                          icon: const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.darkBrown),
                          tooltip: 'Notify Admin',
                          onPressed: () async {
                            final user = data.currentUser?.fullName ?? 'Employee';
                            await data.pushNotification(
                              'INVENTORY NOTICE',
                              '${i.productName} (${i.quantity} ${i.unit}) reported by $user.',
                              'Inventory',
                            );
                            if (context.mounted) {
                              showAppSnack(context, 'Admin notified about ${i.productName}.');
                            }
                          },
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                              tooltip: 'Decrease stock',
                              onPressed: i.quantity <= 0
                                  ? null
                                  : () => AppData.instance.updateInventoryQuantity(i.id, i.quantity - 1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 18),
                              tooltip: 'Restock +1',
                              onPressed: () => AppData.instance.updateInventoryQuantity(i.id, i.quantity + 1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.brown),
                              tooltip: 'Edit item info',
                              onPressed: () => _showEditInventoryItemDialog(context, i),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.danger),
                              tooltip: 'Archive item',
                              onPressed: () => _confirmArchive(context, i),
                            ),
                          ],
                        ),
                ),
              ]);
            }).toList(),
          ),
        ]);
      },
    );
  }

  void _showEditInventoryItemDialog(BuildContext context, InventoryItem item) {
    final nameCtrl = TextEditingController(text: item.productName);
    final qtyCtrl = TextEditingController(text: '${item.quantity}');
    final unitCtrl = TextEditingController(text: item.unit);
    final minStockCtrl = TextEditingController(text: '${item.minimumStock}');
    String itemType = item.itemType;
    DateTime? selectedExpiration = item.expiration;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Inventory Item — ${item.productName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: itemType,
                  decoration: const InputDecoration(labelText: 'Item Category / Type'),
                  items: const [
                    DropdownMenuItem(value: 'Inventory Item', child: Text('Inventory Item')),
                    DropdownMenuItem(value: 'Kitchen Item', child: Text('Kitchen Item')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() {
                        itemType = v;
                        if (itemType != 'Kitchen Item') {
                          selectedExpiration = null;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  inputFormatters: [TitleCaseFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(labelText: 'Unit (e.g. pcs, kg, packs)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minStockCtrl,
                  decoration: const InputDecoration(labelText: 'Minimum Stock Threshold'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                ),
                if (itemType == 'Kitchen Item') ...[
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Expiration Date *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedExpiration != null
                              ? '${selectedExpiration!.month}/${selectedExpiration!.day}/${selectedExpiration!.year}'
                              : 'Select expiration date *',
                          style: TextStyle(
                            color: selectedExpiration != null ? AppColors.darkBrown : AppColors.danger,
                            fontSize: 13,
                            fontWeight: selectedExpiration != null ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _pickExpirationDate(context, selectedExpiration, (d) => setDialogState(() => selectedExpiration = d)),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(selectedExpiration != null ? 'Change' : 'Pick Date'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brown, foregroundColor: Colors.white),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? item.quantity;
                final unit = unitCtrl.text.trim().isEmpty ? 'pcs' : unitCtrl.text.trim();
                final minStock = int.tryParse(minStockCtrl.text.trim()) ?? item.minimumStock;
                if (name.isEmpty) {
                  showAppSnack(context, 'Product name cannot be empty.');
                  return;
                }
                if (itemType == 'Kitchen Item' && selectedExpiration == null) {
                  showAppSnack(context, 'Expiration date is required for Kitchen Items.');
                  return;
                }
                AppData.instance.updateInventoryItem(
                  item.id,
                  productName: name,
                  quantity: qty,
                  unit: unit,
                  minimumStock: minStock,
                  itemType: itemType,
                  expiration: itemType == 'Kitchen Item' ? selectedExpiration : null,
                );
                Navigator.pop(ctx);
                showAppSnack(context, 'Inventory item updated successfully.');
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExpirationDate(BuildContext context, DateTime? current, void Function(DateTime?) onSelected) async {
    final picked = await showCustomExpirationDatePicker(context, initialDate: current);
    if (picked != null) {
      onSelected(picked);
    }
  }

  void _confirmArchive(BuildContext context, InventoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Inventory Item?'),
        content: Text('Are you sure you want to archive "${item.productName}"? This will move it to the Archive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              final user = AppData.instance.currentUser?.fullName ?? 'Admin/Staff';
              AppData.instance.archiveInventory(item.id, archivedBy: user);
              Navigator.pop(ctx);
              showAppSnack(context, '"${item.productName}" moved to Archive.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _promoDialog(BuildContext context, String productName) {
    String promoType = 'Buy 1 Take 1';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Create Promotion — $productName'),
          content: DropdownButtonFormField<String>(
            initialValue: promoType,
            items: const [
              'Buy 1 Take 1',
              '10% Discount',
              '20% Discount',
              '30% Discount'
            ].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) => setDialogState(() => promoType = v ?? promoType),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                AppData.instance.addPromotion(productName, promoType);
                Navigator.pop(ctx);
                showAppSnack(context, 'Promotion created for $productName.');
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
