import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

/// Employees can ONLY view their own payroll — no editing.
class EmployeePayrollScreen extends StatelessWidget {
  const EmployeePayrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final user = data.currentUser;

        if (user == null) {
          return const Center(child: Text('Please log in to view payroll'));
        }

        Employee? employee;

        // 1. Match by ID or employeeId
        final match = data.employees.where(
            (e) => e.id == user.id || (user.employeeId != null && e.id == user.employeeId));
        if (match.isNotEmpty) {
          employee = match.first;
        } else {
          // 2. Match by full name
          final nameMatch = data.employees
              .where((e) => e.name.toLowerCase() == user.fullName.toLowerCase());
          if (nameMatch.isNotEmpty) {
            employee = nameMatch.first;
          }
        }

        // 3. Fallback card for newly registered employee
        employee ??= Employee(
          id: user.id,
          name: user.fullName,
          position: user.position ?? 'Staff',
          dailyRate: 500.0,
          daysWorked: 0.0,
          bonus: 0.0,
          deductions: 0.0,
          status: 'Pending',
        );

        return _buildPayrollContent(employee);
      },
    );
  }

  Widget _buildPayrollContent(Employee employee) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.payments_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EMPLOYEE PAYROLL',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            employee.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            employee.position,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(status: employee.status),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Main Breakdown Card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border, width: 1.2),
                  boxShadow: AppShadows.soft,
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'PAYROLL CYCLE',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.beige,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Current Cycle',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkBrown,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _row(Icons.attach_money_rounded, 'Daily Rate', peso(employee.dailyRate)),
                    _row(Icons.calendar_today_rounded, 'Days Worked', '${employee.daysWorked.toStringAsFixed(0)} days'),
                    _row(Icons.work_outline_rounded, 'Basic Salary', peso(employee.basicSalary)),
                    _row(Icons.card_giftcard_rounded, 'Bonus & Allowances', peso(employee.bonus)),
                    _row(Icons.remove_circle_outline_rounded, 'Deductions', '-${peso(employee.deductions)}', isNegative: true),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: AppColors.border),
                    ),
                    // Net Salary Highlight Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.darkBrown,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppShadows.soft,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NET SALARY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: Colors.white70,
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'Total Payable Earnings',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            peso(employee.netSalary),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Info Footer Note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.beige,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.beigeDark, width: 0.8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppColors.darkBrown,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Payroll calculations are computed based on attendance logs and daily rate records. For discrepancies, please contact administration.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: Colors.black87),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: isNegative ? Colors.black54 : AppColors.darkBrown,
            ),
          ),
        ],
      ),
    );
  }
}
