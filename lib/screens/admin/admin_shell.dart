import 'package:flutter/material.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/app_data.dart';
import '../auth/login_screen.dart';
import 'admin_dashboard.dart';
import 'reports_screen.dart';
import 'inventory_screen.dart';
import 'payroll_screen.dart';
import 'pos_screen.dart';
import 'feedback_screen.dart';
import 'procurement_screen.dart';
import 'petty_cash_screen.dart';
import 'user_management_screen.dart';
import 'archive_screen.dart';
import 'admin_profile_screen.dart';
import 'menu_management_screen.dart';
import 'admin_attendance_screen.dart';
import 'admin_order_history_screen.dart';
import 'gcash_settings_screen.dart';
import 'printer_settings_screen.dart';
import 'qr_generator_screen.dart';
import '../employee/kiosk_management_screen.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Admin Panel',
      trailing: const HeaderActions(),
      profileScreen: const AdminProfileScreen(),
      onLogout: () {
        AppData.instance.logout();
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
      },
      logoAsset: 'assets/images/OC_NAVBAR_LOGO.png',
      homeItem: null, // Logo is non-clickable
      // Divider lines: after Customer Feedback (4) and after Menu Management (7).
      dividerAfter: const {4, 7},
      // Shown in the navbar Settings menu, between Profile and Logout.
      settingsItems: [
        NavItem(icon: Icons.qr_code_2_outlined, label: 'GCash Settings', builder: () => const GcashSettingsScreen()),
        NavItem(icon: Icons.print_outlined, label: 'Printer Settings', builder: () => const PrinterSettingsScreen()),
        NavItem(icon: Icons.qr_code_scanner_outlined, label: 'Walk-In QR Code', builder: () => const QrGeneratorScreen()),
        NavItem(icon: Icons.people_outline, label: 'User Management', builder: () => const UserManagementScreen()),
        NavItem(icon: Icons.archive_outlined, label: 'Archive', builder: () => const ArchiveScreen()),
      ],
      items: [
        NavItem(icon: Icons.dashboard_outlined, label: 'Dashboard', builder: () => const AdminDashboard()),
        NavItem(icon: Icons.point_of_sale_outlined, label: 'POS', builder: () => PosScreen(cashier: AppData.instance.currentUser?.fullName ?? 'Admin')),
        NavItem(icon: Icons.storefront_outlined, label: 'Kitchen', builder: () => const KioskManagementScreen()),
        NavItem(icon: Icons.history, label: 'Order History', builder: () => const AdminOrderHistoryScreen()),
        NavItem(icon: Icons.star_border, label: 'Customer Feedback', builder: () => const FeedbackScreen(canReply: true)),
        NavItem(icon: Icons.local_shipping_outlined, label: 'Procurement', builder: () => const ProcurementScreen()),
        NavItem(icon: Icons.inventory_2_outlined, label: 'Inventory Management', builder: () => const InventoryScreen(readOnly: false)),
        NavItem(icon: Icons.restaurant_menu_outlined, label: 'Menu Management', builder: () => const MenuManagementScreen()),
        NavItem(icon: Icons.bar_chart_outlined, label: 'Report & Analytics', builder: () => const ReportsScreen()),
        NavItem(icon: Icons.payments_outlined, label: 'Payroll Management', builder: () => const PayrollScreen()),
        NavItem(icon: Icons.account_balance_wallet_outlined, label: 'Petty Cash Management', builder: () => const PettyCashScreen()),
        NavItem(icon: Icons.fingerprint, label: 'Attendance Tracker', builder: () => const AdminAttendanceScreen()),
      ],
    );
  }
}
