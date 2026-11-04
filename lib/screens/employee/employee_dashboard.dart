import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import '../../widgets/shared_widgets.dart';

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final user = data.currentUser;
        if (user == null) {
          return const SizedBox.shrink();
        }
        final myAttendance = data.attendance.where((a) => a.employeeName == user.fullName).toList();
        final pendingOrders = data.kioskOrders
            .where((o) => o.status == 'Pending' || o.status == 'Preparing' || o.status == 'Ready')
            .length;
        final lowStock = data.inventory.where((i) => i.status == 'Low Stock' || i.status == 'Out of Stock').length;

        return SectionPage(
          children: [
            // Welcome Header
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.darkBrown,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.waving_hand_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, ${user.fullName}!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Here is your café station update for today.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Stat Cards
            StatGrid(cards: [
              StatCard(
                label: 'Pending Orders',
                value: '$pendingOrders',
                icon: Icons.receipt_long_outlined,
                color: AppColors.brown,
              ),
              StatCard(
                label: 'Low Stock Items',
                value: '$lowStock',
                icon: Icons.warning_amber_outlined,
                color: AppColors.accent,
              ),
              StatCard(
                label: 'Attendance Logs',
                value: '${myAttendance.length}',
                icon: Icons.fingerprint,
                color: AppColors.brown,
              ),
              StatCard(
                label: 'Notifications',
                value: '${data.unreadNotifications}',
                icon: Icons.notifications_outlined,
                color: AppColors.accent,
              ),
            ]),
            const SizedBox(height: 20),

            // Side-by-side section: Minimized Notifications & Stocks Overview
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;

                final notificationsCard = _MinimizedNotificationsCard(
                  notifications: data.notifications,
                );

                final stocksCard = _StocksOverviewCard(
                  inventory: data.inventory,
                  products: data.products,
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: notificationsCard),
                      const SizedBox(width: 16),
                      Expanded(child: stocksCard),
                    ],
                  );
                }

                return Column(
                  children: [
                    notificationsCard,
                    const SizedBox(height: 16),
                    stocksCard,
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _MinimizedNotificationsCard extends StatelessWidget {
  final List notifications;
  const _MinimizedNotificationsCard({required this.notifications});

  @override
  Widget build(BuildContext context) {
    final recent = notifications.take(4).toList();

    return Container(
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_outlined, size: 20, color: AppColors.darkBrown),
              const SizedBox(width: 8),
              const Text(
                'Recent Notifications',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.darkBrown,
                ),
              ),
              const Spacer(),
              if (recent.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.beige,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${recent.length} recent',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkBrown,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 20, color: AppColors.beigeDark),
          Expanded(
            child: recent.isEmpty
                ? const Center(
                    child: Text(
                      'No recent notifications.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: recent.length,
                    separatorBuilder: (_, __) => const Divider(height: 12, color: AppColors.beige),
                    itemBuilder: (context, index) {
                      final n = recent[index];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.darkBrown,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: AppColors.darkBrown,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  n.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StocksOverviewCard extends StatefulWidget {
  final List<InventoryItem> inventory;
  final List<Product> products;

  const _StocksOverviewCard({
    required this.inventory,
    required this.products,
  });

  @override
  State<_StocksOverviewCard> createState() => _StocksOverviewCardState();
}

class _StocksOverviewCardState extends State<_StocksOverviewCard> {
  int _selectedTab = 0; // 0 = Inventory, 1 = Menu Stocks

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.darkBrown),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Stocks Overview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                    color: AppColors.darkBrown,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.beige,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tabButton(0, 'Inventory'),
                    _tabButton(1, 'Menu'),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.beigeDark),
          Expanded(
            child: _selectedTab == 0 ? _buildInventoryList() : _buildProductsList(),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label) {
    final selected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.darkBrown : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryList() {
    if (widget.inventory.isEmpty) {
      return const Center(
        child: Text(
          'No inventory items found.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: widget.inventory.length,
      separatorBuilder: (_, __) => const Divider(height: 10, color: AppColors.beige),
      itemBuilder: (context, index) {
        final item = widget.inventory[index];
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: AppColors.darkBrown,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.quantity} ${item.unit} (Min: ${item.minimumStock})',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            StatusBadge(status: item.status),
          ],
        );
      },
    );
  }

  Widget _buildProductsList() {
    if (widget.products.isEmpty) {
      return const Center(
        child: Text(
          'No menu products found.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: widget.products.length,
      separatorBuilder: (_, __) => const Divider(height: 10, color: AppColors.beige),
      itemBuilder: (context, index) {
        final product = widget.products[index];
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: AppColors.darkBrown,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${product.category} · Stock: ${product.stockQuantity}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            StatusBadge(status: product.stockStatus),
          ],
        );
      },
    );
  }
}
