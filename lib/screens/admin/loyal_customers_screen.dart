import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';

class LoyalCustomersScreen extends StatefulWidget {
  const LoyalCustomersScreen({super.key});

  @override
  State<LoyalCustomersScreen> createState() => _LoyalCustomersScreenState();
}

class _LoyalCustomersScreenState extends State<LoyalCustomersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final loyalList = AppData.instance.loyalCustomers
            .where((u) => u.fullName.toLowerCase().contains(_search.toLowerCase()) ||
                          u.email.toLowerCase().contains(_search.toLowerCase()))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search loyal customers...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: loyalList.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.beige.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.loyalty_outlined, size: 48, color: AppColors.brown),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No Loyal Customers Yet',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkBrown,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Customers automatically qualify and appear here\nonce they reach 5 or more completed orders.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: loyalList.length,
                      itemBuilder: (context, i) {
                        final customer = loyalList[i];
                        final orderCount = AppData.instance.getCompletedOrdersCount(customer.id);
                        final isOn = customer.loyalToggle;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 1.5,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.beige,
                                  radius: 18,
                                  child: Text(
                                    customer.fullName.isNotEmpty ? customer.fullName[0].toUpperCase() : 'C',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              customer.fullName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isOn) ...[
                                            const SizedBox(width: 4),
                                            const LoyalBadge(),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        customer.email,
                                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.success.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '$orderCount Orders',
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success),
                                            ),
                                          ),
                                          StatusBadge(status: isOn ? 'Active' : 'Disabled'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isOn ? 'Active' : 'Inactive',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isOn ? AppColors.darkBrown : AppColors.textMuted,
                                      ),
                                    ),
                                    SizedBox(
                                      height: 30,
                                      child: Transform.scale(
                                        scale: 0.75,
                                        child: Switch(
                                          value: isOn,
                                          activeColor: AppColors.darkBrown,
                                          onChanged: (val) async {
                                            if (!val) {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Deactivate Loyal Status?'),
                                                  content: Text(
                                                      'Are you sure you want to deactivate loyal status for ${customer.fullName}?'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx, false),
                                                      child: const Text('Cancel'),
                                                    ),
                                                    ElevatedButton(
                                                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      child: const Text('Deactivate'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm != true) return;
                                            }
                                            await AppData.instance.updateCustomerLoyalToggle(customer.id, val);
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class LoyalCustomersModal extends StatelessWidget {
  const LoyalCustomersModal({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final isDesktop = media.width > 700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,
      child: Container(
        width: isDesktop ? 640 : media.width * 0.94,
        height: media.height * 0.82,
        padding: EdgeInsets.all(isDesktop ? 22 : 14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brown.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.loyalty_outlined, color: AppColors.darkBrown, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Loyal Customers',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBrown,
                        ),
                      ),
                      Text(
                        'Manage customer loyalty tiers & active status',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 10),
            const Expanded(
              child: LoyalCustomersScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

class LoyalCustomersButton extends StatelessWidget {
  const LoyalCustomersButton({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => const LoyalCustomersModal(),
        );
      },
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Tooltip(
          message: 'Loyal Customers',
          child: Icon(Icons.loyalty_outlined, color: AppColors.darkBrown),
        ),
      ),
    );
  }
}
