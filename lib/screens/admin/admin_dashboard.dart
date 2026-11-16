import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final todaySales = data.todaySales;
        final totalSales = data.totalSales;

        final wideLayout = MediaQuery.of(context).size.width >= 1100;

        Widget buildWelcomeBanner(BuildContext ctx) {
          final isOrderingOpen = data.isWithinOrderingWindow();
          final compact = MediaQuery.of(ctx).size.width < 600;
          final currentUser = data.currentUser;
          final adminName = (currentUser != null && currentUser.fullName.trim().isNotEmpty)
              ? currentUser.fullName.trim()
              : 'Admin';

          final toggleWidget = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOrderingOpen ? Colors.white : Colors.white38,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Store Ordering', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(
                      isOrderingOpen ? 'OPEN' : 'CLOSED',
                      style: TextStyle(
                        color: isOrderingOpen ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Switch(
                  value: isOrderingOpen,
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.white38,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white12,
                  onChanged: (val) {
                    data.setOrderingOverride(val);
                  },
                ),
              ],
            ),
          );

          return Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brown, AppColors.brownDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppShadows.soft,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Welcome back, $adminName!',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
                                const SizedBox(height: 2),
                                const Text('Here is your café performance overview for today.',
                                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Align(alignment: Alignment.centerRight, child: toggleWidget),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Welcome back, $adminName!',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
                            const SizedBox(height: 2),
                            const Text('Here is your café performance overview for today.',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      toggleWidget,
                    ],
                  ),
          );
        }

        final statCardsList = [
          StatCard(
              label: "Today's Sales",
              value: peso(todaySales),
              icon: Icons.trending_up,
              color: AppColors.brown),
          StatCard(
              label: 'Total Sales',
              value: peso(totalSales),
              icon: Icons.attach_money,
              color: AppColors.brown),
        ];

        final activeTransactions = data.transactions.where((t) => !t.archivedByAdmin).toList();

        if (wideLayout) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buildWelcomeBanner(context),
                      const SizedBox(height: 20),
                      StatGrid(cards: statCardsList),
                      const SizedBox(height: 24),
                      _LineChartSketch(transactions: activeTransactions),
                      const SizedBox(height: 16),
                      _MiniChartCard(
                          title: 'Best-Selling Products',
                          child: _BestSellers(transactions: activeTransactions)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: Container(
                  width: 340,
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppShadows.soft,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MiniChartCard(
                            title: 'Inventory Status',
                            child: _InventoryDonutSketch(inventory: data.inventory)),
                        const SizedBox(height: 16),
                        _DashboardInventoryItemsCard(inventory: data.inventory),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return SectionPage(
          children: [
            buildWelcomeBanner(context),
            const SizedBox(height: 20),
            StatGrid(cards: statCardsList),
            const SizedBox(height: 20),
            _LineChartSketch(transactions: activeTransactions),
            const SizedBox(height: 16),
            _MiniChartCard(
                title: 'Best-Selling Products',
                child: _BestSellers(transactions: activeTransactions)),
          ],
        );
      },
    );
  }
}



class _DashboardInventoryItemsCard extends StatelessWidget {
  final List inventory;
  const _DashboardInventoryItemsCard({required this.inventory});

  @override
  Widget build(BuildContext context) {
    final items = inventory.take(6).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Inventory Items',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                Text('${inventory.length} total',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('No inventory items found.', style: TextStyle(color: AppColors.textMuted))
            else
              ...items.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.beige,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.darkBrown),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${item.quantity} ${item.unit}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      StatusBadge(status: item.status),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MiniChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _MiniChartCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

/// Live Mon–Sun sales trend for the current week, computed from
/// [transactions] so it updates in real time as new sales come in (the
/// Firestore 'transactions' listener in [AppData] keeps that list fresh
/// and calls notifyListeners(), and this widget sits under the dashboard's
/// AnimatedBuilder so it rebuilds automatically).
class _LineChartPainter extends CustomPainter {
  final List<double> totals;
  final double maxTotal;
  final int busiestIndex;

  _LineChartPainter({required this.totals, required this.maxTotal, required this.busiestIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.length != 7) return;

    final paintGrid = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final paintLine = Paint()
      ..color = AppColors.darkBrown
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final paintFill = Paint()
      ..shader = LinearGradient(
        colors: [AppColors.brown.withValues(alpha: 0.2), AppColors.brown.withValues(alpha: 0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final paintDot = Paint()
      ..color = AppColors.darkBrown
      ..style = PaintingStyle.fill;

    final paintDotInner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const paddingBottom = 10.0;
    const paddingTop = 15.0;
    final chartHeight = size.height - paddingBottom - paddingTop;
    final stepX = totals.length > 1 ? size.width / (totals.length - 1) : size.width;

    // Draw horizontal grid lines (4 levels: 0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final y = paddingTop + (chartHeight * (1.0 - (i / 4.0)));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    final points = <Offset>[];
    for (int i = 0; i < totals.length; i++) {
      final x = totals.length > 1 ? i * stepX : size.width / 2;
      final ratio = maxTotal > 0 ? (totals[i] / maxTotal) : 0.0;
      final y = paddingTop + chartHeight - (chartHeight * ratio.clamp(0.0, 1.0));
      points.add(Offset(x, y));
    }

    // Draw fill path
    if (points.isNotEmpty) {
      final pathFill = Path()..moveTo(points.first.dx, size.height - paddingBottom);
      for (final p in points) {
        pathFill.lineTo(p.dx, p.dy);
      }
      pathFill.lineTo(points.last.dx, size.height - paddingBottom);
      pathFill.close();
      canvas.drawPath(pathFill, paintFill);
    }

    // Draw connecting line
    final pathLine = Path();
    if (points.isNotEmpty) {
      pathLine.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        pathLine.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(pathLine, paintLine);
    }

    // Draw dots
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isBusiest = i == busiestIndex;

      canvas.drawCircle(p, isBusiest ? 6.0 : 4.0, paintDot);
      canvas.drawCircle(p, isBusiest ? 3.0 : 1.5, paintDotInner);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.totals != totals || oldDelegate.maxTotal != maxTotal;
  }
}

class _LineChartSketch extends StatefulWidget {
  final List<TransactionRecord> transactions;
  const _LineChartSketch({required this.transactions});

  @override
  State<_LineChartSketch> createState() => _LineChartSketchState();
}

class _LineChartSketchState extends State<_LineChartSketch> {
  int? _selectedDayIndex;

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    final totals = List<double>.filled(7, 0.0);
    for (final t in widget.transactions) {
      final ts = t.timestamp;
      if (!ts.isBefore(startOfWeek) && ts.isBefore(endOfWeek)) {
        totals[ts.weekday - 1] += t.total;
      }
    }

    final maxTotal = totals.fold<double>(0, (m, v) => v > m ? v : m);
    final effectiveMax = maxTotal > 0 ? maxTotal : 1000.0;
    final busiestIndex = maxTotal <= 0 ? -1 : totals.indexOf(maxTotal);

    final selectedText = _selectedDayIndex != null 
        ? ' — ${days[_selectedDayIndex!]}: ${peso(totals[_selectedDayIndex!])}'
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Weekly Sales Trend',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                      ),
                      if (_selectedDayIndex != null)
                        Flexible(
                          child: Text(
                            selectedText,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.accent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_selectedDayIndex != null)
                  TextButton(
                    onPressed: () => setState(() => _selectedDayIndex = null),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 24)),
                    child: const Text('Reset', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 176,
              child: Row(
                children: [
                  // Y-Axis amounts on the left
                  SizedBox(
                    width: 52,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_shortPeso(effectiveMax), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        Text(_shortPeso(effectiveMax * 0.75), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        Text(_shortPeso(effectiveMax * 0.5), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        Text(_shortPeso(effectiveMax * 0.25), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        const Text('₱0', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Chart area
                  Expanded(
                    child: GestureDetector(
                      onTapDown: (details) {
                        final renderBox = context.findRenderObject() as RenderBox?;
                        if (renderBox != null) {
                          final chartWidth = renderBox.size.width - 60;
                          if (chartWidth > 0) {
                            final localX = details.localPosition.dx - 60;
                            if (localX >= 0 && localX <= chartWidth) {
                              final step = chartWidth / 6;
                              final index = (localX / step).round().clamp(0, 6);
                              setState(() => _selectedDayIndex = index);
                            }
                          }
                        }
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _LineChartPainter(
                          totals: totals,
                          maxTotal: effectiveMax,
                          busiestIndex: busiestIndex,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // X-Axis days at the bottom
            Padding(
              padding: const EdgeInsets.only(left: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(days.length, (i) {
                  final isSelected = _selectedDayIndex == i;
                  final isBusiest = i == busiestIndex;
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedDayIndex = i);
                      },
                      child: Tooltip(
                        message: '${days[i]}: ${peso(totals[i])}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            days[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected || isBusiest ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? AppColors.accent : (isBusiest ? AppColors.darkBrown : AppColors.textMuted),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortPeso(double amount) {
  if (amount >= 1000000) {
    return '₱${(amount / 1000000).toStringAsFixed(1)}M';
  } else if (amount >= 1000) {
    return '₱${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k';
  } else {
    return '₱${amount.toStringAsFixed(0)}';
  }
}

/// Live overall top-5 best sellers, ranked by total units sold across every
/// completed transaction. Updates in real time the same way [_BarSketch]
/// does — driven by [AppData]'s live 'transactions' listener.
class _BestSellers extends StatelessWidget {
  final List<TransactionRecord> transactions;
  const _BestSellers({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final Map<String, int> unitsSold = {};
    for (final t in transactions) {
      for (final item in t.items) {
        unitsSold.update(item.product.name, (v) => v + item.quantity,
            ifAbsent: () => item.quantity);
      }
    }

    final ranked = unitsSold.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(5).toList();

    if (top.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No sales recorded yet.',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
      );
    }
    final maxUnits = top.first.value;
    return Column(
      children: List.generate(top.length, (i) {
        final entry = top[i];
        final ratio = maxUnits > 0 ? entry.value / maxUnits : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == 0 ? AppColors.darkBrown : AppColors.beige,
                  shape: BoxShape.circle,
                ),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: i == 0 ? Colors.white : AppColors.darkBrown)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(entry.key,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Text('${entry.value} sold',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.darkBrown,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio.toDouble(),
                        minHeight: 5,
                        backgroundColor: AppColors.beige,
                        color: i == 0 ? AppColors.darkBrown : const Color(0xFF6C757D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _InventoryDonutSketch extends StatelessWidget {
  final List inventory;
  const _InventoryDonutSketch({required this.inventory});
  @override
  Widget build(BuildContext context) {
    final total = inventory.length;
    final low = inventory.where((i) => i.status == 'Low Stock').length;
    final out = inventory.where((i) => i.status == 'Out of Stock').length;
    final near = inventory.where((i) => i.status == 'Near Expiration').length;
    final okRaw = total - low - out - near;
    final ok = okRaw < 0 ? 0 : okRaw;

    // Greyscale ramp — every segment is also labelled below, so the chart
    // never relies on color alone.
    const cOk = AppColors.darkBrown;
    const cLow = Color(0xFF6C757D);
    const cOut = Color(0xFFADB5BD);
    const cNear = Color(0xFFDEE2E6);

    Widget row(String label, int count, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
            Text('$count',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
        );

    final counts = [ok, low, out, near];
    final colors = [cOk, cLow, cOut, cNear];
    final segments = <Widget>[];
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] <= 0) continue;
      if (segments.isNotEmpty) segments.add(const SizedBox(width: 2));
      segments.add(Expanded(flex: counts[i], child: Container(color: colors[i])));
    }

    return Column(children: [
      if (segments.isNotEmpty)
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(height: 12, child: Row(children: segments)),
        )
      else
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('No inventory items found.', style: TextStyle(color: AppColors.textMuted)),
        ),
      const SizedBox(height: 14),
      row('In Stock', ok, cOk),
      row('Low Stock', low, cLow),
      row('Out of Stock', out, cOut),
      row('Near Expiration', near, cNear),
    ]);
  }
}


