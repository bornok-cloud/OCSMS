import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  String _search = '';
  String _selectedEmployee = 'All';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final employees = data.activeEmployees.map((e) => e.name).toList()..sort();
        
        var records = data.attendance.where((a) {
          final isEmployeeActive = data.activeEmployees.any((e) => e.name.toLowerCase() == a.employeeName.toLowerCase());
          if (!isEmployeeActive) return false;

          if (_selectedEmployee != 'All' && a.employeeName != _selectedEmployee) {
            return false;
          }
          if (_search.isNotEmpty &&
              !a.employeeName.toLowerCase().contains(_search.toLowerCase()) &&
              !a.timeIn.toLowerCase().contains(_search.toLowerCase())) {
            return false;
          }
          return true;
        }).toList();

        // Sort newest first
        records.sort((a, b) => b.date.compareTo(a.date));

        return SectionPage(children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search employee...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.brown.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedEmployee,
                  underline: const SizedBox.shrink(),
                  items: ['All', ...employees]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedEmployee = v ?? 'All'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Attendance Logs (${records.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Employee')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Time In')),
              DataColumn(label: Text('Time Out')),
              DataColumn(label: Text('Method')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: records.map((a) {
              final dateStr = '${a.date.month}/${a.date.day}/${a.date.year}';
              return DataRow(cells: [
                DataCell(Text(a.employeeName, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(dateStr)),
                DataCell(Text(a.timeIn)),
                DataCell(Text(a.timeOut ?? 'Active / Not Timed Out',
                    style: TextStyle(color: a.timeOut == null ? AppColors.accent : null))),
                DataCell(Text(a.method)),
                DataCell(StatusBadge(status: a.status)),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.restart_alt_rounded, color: AppColors.danger),
                    tooltip: 'Reset / Delete Attendance',
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Reset Attendance?'),
                          content: Text(
                              'Are you sure you want to delete attendance for ${a.employeeName} on $dateStr? This will also update their days worked.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await data.deleteAttendanceRecord(a.id);
                        if (context.mounted) {
                          showAppSnack(context, 'Attendance for ${a.employeeName} on $dateStr was reset.');
                        }
                      }
                    },
                  ),
                ),
              ]);
            }).toList(),
          ),
        ]);
      },
    );
  }
}
