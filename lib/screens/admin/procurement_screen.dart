import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class ProcurementScreen extends StatefulWidget {
  const ProcurementScreen({super.key});
  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  String _selectedTab = 'Inventory Item'; // 'Inventory Item' or 'Kitchen Item'
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final needsRestock = data.inventory
            .where((i) => (i.status == 'Low Stock' || i.status == 'Out of Stock') && i.itemType == _selectedTab)
            .toList();
        var procurementList = data.procurement
            .where((p) => p.itemType == _selectedTab && p.productName.toLowerCase().contains(_search.toLowerCase()))
            .toList();
        procurementList.sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));

        return SectionPage(
          children: [
            Text('Products Needing Restock', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (needsRestock.isEmpty) const Text('Nothing needs restocking right now.', style: TextStyle(color: AppColors.textMuted)),
            ...needsRestock.map((i) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                    title: Text(i.productName),
                    subtitle: Text('Current: ${i.quantity} ${i.unit} · Minimum: ${i.minimumStock} ${i.unit}'),
                    trailing: ElevatedButton(
                      onPressed: () => _restockDialog(context, i.productName, _selectedTab),
                      child: const Text('Restock'),
                    ),
                  ),
                )),
            const SizedBox(height: 24),
            Builder(
              builder: (context) {
                final searchField = TextField(
                  decoration: InputDecoration(
                    hintText: 'Search ${_selectedTab.toLowerCase()} procurement...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
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

                final addItemButton = OutlinedButton.icon(
                  onPressed: () => _restockDialog(context, null, _selectedTab),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 750;
                    if (wide) {
                      return Row(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: searchField,
                          ),
                          const Spacer(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              inventoryChip,
                              const SizedBox(width: 8),
                              kitchenChip,
                            ],
                          ),
                          const Spacer(),
                          addItemButton,
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 2nd row: Search bar and Add Item button
                          Row(
                            children: [
                              Expanded(child: searchField),
                              const SizedBox(width: 8),
                              addItemButton,
                            ],
                          ),
                          const SizedBox(height: 10),
                          // 3rd row: Inventory Items button and Kitchen Items button
                          Row(
                            children: [
                              Expanded(child: Center(child: inventoryChip)),
                              const SizedBox(width: 8),
                              Expanded(child: Center(child: kitchenChip)),
                            ],
                          ),
                        ],
                      );
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            Text('${_selectedTab == 'Kitchen Item' ? 'Kitchen' : 'Inventory'} Procurement History', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ResponsiveTable(
              columns: const [
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Supplier')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Cost')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: procurementList.map((p) => DataRow(cells: [
                    DataCell(Text(p.productName)),
                    DataCell(Text(p.supplier)),
                    DataCell(Text('${p.quantity}')),
                    DataCell(Text(peso(p.cost))),
                    DataCell(Text('${p.date.month}/${p.date.day}/${p.date.year}')),
                    DataCell(StatusBadge(status: p.status)),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.brown),
                            tooltip: 'Edit Record',
                            onPressed: () => _editProcurementDialog(context, p),
                          ),
                          if (data.currentUser?.role == UserRole.admin) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.danger),
                              tooltip: 'Archive Record',
                              onPressed: () => _confirmArchive(context, p),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ])).toList(),
            ),
          ],
        );
      },
    );
  }

  void _confirmArchive(BuildContext context, ProcurementRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Procurement Record?'),
        content: Text('Are you sure you want to archive the record for "${record.productName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              AppData.instance.archiveProcurement(record.id);
              Navigator.pop(ctx);
              showAppSnack(context, 'Procurement record moved to Archive.');
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _editProcurementDialog(BuildContext context, ProcurementRecord record) {
    final nameCtrl = TextEditingController(text: record.productName);
    final supplierCtrl = TextEditingController(text: record.supplier);
    final qtyCtrl = TextEditingController(text: '${record.quantity}');
    final costCtrl = TextEditingController(text: '${record.cost}');
    String itemType = record.itemType;
    DateTime? selectedExpiration = record.expiration;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Procurement — ${record.productName}'),
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
                            if (itemType != 'Kitchen Item') selectedExpiration = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Product Name'),
                      inputFormatters: [TitleCaseFormatter()],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: supplierCtrl,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      inputFormatters: [TitleCaseFormatter()],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtyCtrl,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: costCtrl,
                      decoration: const InputDecoration(labelText: 'Total Cost (₱)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    ),
                    if (itemType == 'Kitchen Item') ...[
                      const SizedBox(height: 16),
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
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      showAppSnack(context, 'Product name cannot be empty.');
                      return;
                    }
                    if (itemType == 'Kitchen Item' && selectedExpiration == null) {
                      showAppSnack(context, 'Expiration date is required for Kitchen Items.');
                      return;
                    }
                    AppData.instance.updateProcurement(
                      record.id,
                      name,
                      supplierCtrl.text.trim().isEmpty ? record.supplier : supplierCtrl.text.trim(),
                      int.tryParse(qtyCtrl.text) ?? record.quantity,
                      double.tryParse(costCtrl.text) ?? record.cost,
                      itemType: itemType,
                      expiration: itemType == 'Kitchen Item' ? selectedExpiration : null,
                    );
                    Navigator.pop(ctx);
                    showAppSnack(context, 'Procurement record updated.');
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _restockDialog(BuildContext context, String? productName, String defaultType) {
    final nameCtrl = TextEditingController(text: productName ?? '');
    String existingSupplier = '';
    double existingCost = 0.0;
    if (productName != null && productName.isNotEmpty) {
      final match = AppData.instance.procurement.where((p) => p.productName.trim().toLowerCase() == productName.trim().toLowerCase()).toList();
      if (match.isNotEmpty) {
        existingSupplier = match.last.supplier;
        existingCost = match.last.cost;
      }
    }
    final supplierCtrl = TextEditingController(text: existingSupplier);
    final qtyCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: existingCost > 0 ? (existingCost == existingCost.roundToDouble() ? existingCost.toStringAsFixed(0) : existingCost.toStringAsFixed(2)) : '');
    String itemType = defaultType;
    DateTime? selectedExpiration;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Procurement Record'),
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
                            if (itemType != 'Kitchen Item') selectedExpiration = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Product Name'),
                      inputFormatters: [TitleCaseFormatter()],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: supplierCtrl,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      inputFormatters: [TitleCaseFormatter()],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtyCtrl,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: costCtrl,
                      decoration: const InputDecoration(labelText: 'Total Cost (₱)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    ),
                    if (itemType == 'Kitchen Item') ...[
                      const SizedBox(height: 16),
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
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      showAppSnack(context, 'Product name cannot be empty.');
                      return;
                    }
                    if (itemType == 'Kitchen Item' && selectedExpiration == null) {
                      showAppSnack(context, 'Expiration date is required for Kitchen Items.');
                      return;
                    }
                    AppData.instance.addProcurement(
                      name,
                      supplierCtrl.text.trim(),
                      int.tryParse(qtyCtrl.text) ?? 0,
                      double.tryParse(costCtrl.text) ?? 0,
                      itemType: itemType,
                      expiration: itemType == 'Kitchen Item' ? selectedExpiration : null,
                    );
                    Navigator.pop(ctx);
                    showAppSnack(context, 'Procurement recorded & $itemType restocked.');
                  },
                  child: const Text('Save & Restock'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickExpirationDate(BuildContext context, DateTime? current, void Function(DateTime?) onSelected) async {
    final picked = await showCustomExpirationDatePicker(context, initialDate: current);
    if (picked != null) {
      onSelected(picked);
    }
  }
}
