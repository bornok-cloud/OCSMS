import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tutorial_step.dart';

class TutorialService {
  TutorialService._privateConstructor();
  static final TutorialService instance = TutorialService._privateConstructor();

  static const String _keyPrefix = 'tutorial_completed_';

  Future<bool> hasCompletedTutorial(String userId, String role) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_keyPrefix${userId}_$role') ?? false;
  }

  Future<void> setTutorialCompleted(String userId, String role, bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_keyPrefix${userId}_$role', completed);
  }

  List<TutorialStep> getStepsForRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return const [
          TutorialStep(
            id: 'admin_dashboard',
            role: 'admin',
            title: 'Admin Dashboard',
            description: 'Monitor overall café performance, daily revenue, active orders, and quick stats at a glance.',
            icon: Icons.dashboard_outlined,
          ),
          TutorialStep(
            id: 'admin_pos',
            role: 'admin',
            title: 'Point of Sale (POS)',
            description: 'Process walk-in or phone orders, select menu items, apply discounts, and record payments efficiently.',
            icon: Icons.point_of_sale_outlined,
          ),
          TutorialStep(
            id: 'admin_kitchen',
            role: 'admin',
            title: 'Kitchen & Kiosk Management',
            description: 'Manage incoming customer kiosk orders, accept or decline orders, and update preparation statuses live.',
            icon: Icons.storefront_outlined,
          ),
          TutorialStep(
            id: 'admin_inventory',
            role: 'admin',
            title: 'Inventory & Menu Management',
            description: 'Track stock levels, manage ingredients, update menu items, prices, and categories in real time.',
            icon: Icons.inventory_2_outlined,
          ),
          TutorialStep(
            id: 'admin_reports',
            role: 'admin',
            title: 'Reports & Analytics',
            description: 'Generate financial reports, sales analytics, payroll, petty cash, and attendance records.',
            icon: Icons.bar_chart_outlined,
          ),
          TutorialStep(
            id: 'admin_settings',
            role: 'admin',
            title: 'Settings & User Management',
            description: 'Configure GCash credentials, printer settings, user accounts, and archived records.',
            icon: Icons.settings_outlined,
          ),
        ];

      case 'employee':
      case 'staff':
        return const [
          TutorialStep(
            id: 'employee_dashboard',
            role: 'employee',
            title: 'Staff Dashboard',
            description: 'View your shift summary, active tasks, attendance status, and quick shortcuts.',
            icon: Icons.dashboard_outlined,
          ),
          TutorialStep(
            id: 'employee_kiosk',
            role: 'employee',
            title: 'Kiosk & Order Management',
            description: 'View pending customer kiosk orders, accept orders for preparation, and update status when ready.',
            icon: Icons.storefront_outlined,
          ),
          TutorialStep(
            id: 'employee_attendance',
            role: 'employee',
            title: 'Attendance Tracker',
            description: 'Clock in and clock out for your shifts securely with biometric or PIN tracking.',
            icon: Icons.fingerprint,
          ),
          TutorialStep(
            id: 'employee_payroll',
            role: 'employee',
            title: 'Payroll & Profile',
            description: 'Review your payroll statements, earnings history, and update personal account profile details.',
            icon: Icons.payments_outlined,
          ),
        ];

      case 'customer':
      case 'guest':
        return const [
          TutorialStep(
            id: 'customer_menu',
            role: 'customer',
            title: 'Browse Menu & Kiosk',
            description: 'Explore our delicious café menu, select items, customize add-ons, and place orders directly.',
            icon: Icons.storefront_outlined,
          ),
          TutorialStep(
            id: 'customer_active_order',
            role: 'customer',
            title: 'Active Order & Countdown',
            description: 'When you place an order, get a unique Order ID with a live 20-minute countdown to show at the counter.',
            icon: Icons.receipt_long_rounded,
          ),
          TutorialStep(
            id: 'customer_my_orders',
            role: 'customer',
            title: 'My Orders & History',
            description: 'Track the real-time status of your active orders and review your past order history.',
            icon: Icons.history_outlined,
          ),
          TutorialStep(
            id: 'customer_profile',
            role: 'customer',
            title: 'Customer Profile & Rewards',
            description: 'View your profile details, loyalty points, feedback options, and account settings.',
            icon: Icons.person_outline_rounded,
          ),
        ];

      default:
        return const [
          TutorialStep(
            id: 'general_welcome',
            role: 'all',
            title: 'Welcome to Overnight Cafe',
            description: 'Explore system features, navigate easily between tabs, and enjoy a seamless café experience.',
            icon: Icons.star_border,
          ),
        ];
    }
  }
}
