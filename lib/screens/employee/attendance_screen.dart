import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _scanning = false;
  final String _method = 'RFID';
  AttendanceRecord? _lastRecord;
  bool _lastActionWasTimeOut = false;

  void _scan(bool willBeTimeOut) {
    setState(() {
      _scanning = true;
      _lastRecord = null;
    });
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final user = AppData.instance.currentUser;
      if (user == null) {
        setState(() => _scanning = false);
        return;
      }
      try {
        final record =
            await AppData.instance.recordAttendance(user.fullName, method: _method);
        setState(() {
          _scanning = false;
          _lastRecord = record;
          _lastActionWasTimeOut = willBeTimeOut;
        });
      } catch (e) {
        setState(() => _scanning = false);
        if (!mounted) return;
        showAppSnack(
            context, e.toString().replaceFirst('Exception: ', ''),
            success: false);
      }
    });
  }

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
        final myHistory =
            data.attendance.where((a) => a.employeeName == user.fullName).toList();

        // The cafe runs one overnight shift, 6:30 PM to 2:30 AM. An open
        // (not-yet-timed-out) record always means "scan to time out",
        // regardless of what the calendar date says. Outside that window
        // there's nothing to scan for — either it's too early to time in,
        // or tonight's shift is already done.
        final openRecord = data.openAttendanceFor(user.fullName);
        final withinWindow = data.isWithinAttendanceWindow();
        final shiftRecord = openRecord ??
            (withinWindow ? data.attendanceForCurrentShift(user.fullName) : null);

        bool canTimeoutNow = false;
        if (openRecord != null) {
          final shiftDate = DateTime(openRecord.date.year, openRecord.date.month, openRecord.date.day);
          final shiftTimes = data.getShiftTimes(shiftDate);
          final timeoutStart = shiftTimes.end.subtract(const Duration(minutes: 30)); // 2:00 AM
          final timeoutEnd = shiftTimes.end; // 2:30 AM
          final now = DateTime.now();
          canTimeoutNow = !now.isBefore(timeoutStart) && now.isBefore(timeoutEnd);
        }

        // null = nothing to scan right now (button disabled).
        final bool? nextIsTimeOut = openRecord != null
            ? (canTimeoutNow ? true : null)
            : (!withinWindow || (shiftRecord?.hasTimedOut ?? false))
                ? null
                : false;

        String headerText;
        if (openRecord != null && !canTimeoutNow) {
          headerText = 'TIME OUT OPENS AT 2:00 AM';
        } else if (nextIsTimeOut == true) {
          headerText = 'SCAN RFID TO TIME OUT';
        } else if (!withinWindow) {
          headerText = 'TIME IN OPENS AT 6:30 PM';
        } else if (shiftRecord?.hasTimedOut ?? false) {
          headerText = 'ATTENDANCE COMPLETE FOR TONIGHT';
        } else {
          headerText = 'SCAN RFID TO TIME IN';
        }

        return SectionPage(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(headerText,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.darkBrown)),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: (!_scanning && nextIsTimeOut != null)
                        ? () => _scan(nextIsTimeOut)
                        : null,
                    child: Opacity(
                      opacity: nextIsTimeOut == null ? 0.4 : 1,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: AppColors.beige,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.brown.withValues(alpha: 0.4),
                              width: 2,
                              style: BorderStyle.solid),
                        ),
                        alignment: Alignment.center,
                        child: _scanning
                            ? const CircularProgressIndicator(
                                color: AppColors.brown)
                            : const Icon(
                                Icons.credit_card,
                                size: 64,
                                color: AppColors.brown),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                      _scanning
                          ? 'Waiting for scan...'
                          : (nextIsTimeOut == null
                              ? (openRecord != null && !canTimeoutNow
                                  ? 'You have already timed in. Time out will be available from 2:00 AM to 2:30 AM.'
                                  : (!withinWindow
                                      ? ''
                                      : 'You have already timed in and out for tonight\'s shift.'))
                              : 'Tap the scan area to simulate a scan'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted)),
                  if (_lastRecord != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _lastActionWasTimeOut
                                    ? 'Time Out recorded successfully.'
                                    : 'Time In recorded successfully.',
                                style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Employee: ${_lastRecord!.employeeName}'),
                          Text('Time In: ${_lastRecord!.timeIn}'),
                          if (_lastRecord!.hasTimedOut)
                            Text('Time Out: ${_lastRecord!.timeOut}'),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Status: '),
                                StatusBadge(status: _lastRecord!.status)
                              ]),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Attendance History',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ResponsiveTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Time In')),
              DataColumn(label: Text('Time Out')),
              DataColumn(label: Text('Method')),
              DataColumn(label: Text('Status')),
            ],
            rows: myHistory
                .map((a) => DataRow(cells: [
                      DataCell(
                          Text('${a.date.month}/${a.date.day}/${a.date.year}')),
                      DataCell(Text(a.timeIn)),
                      DataCell(Text(a.timeOut ?? '—')),
                      DataCell(Text(a.method)),
                      DataCell(StatusBadge(status: a.status)),
                    ]))
                .toList(),
          ),
        ]);
      },
    );
  }
}
