import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  List<DateTime> _months = [];
  int _selectedMonthIdx = 0;
  int _touchedPieIdx = -1;

  static const Map<String, Color> _catColors = {
    'Salary': Color(0xFF8BC34A),
    'Rent': Color(0xFFE65100),
    'University': Color(0xFF1A237E),
    'People': Color(0xFF00695C),
    'Groceries': Color(0xFF4CAF50),
    'Restaurants': Color(0xFFFF9800),
    'Transport': Color(0xFF2196F3),
    'Health': Color(0xFFE91E63),
    'Entertainment': Color(0xFF9C27B0),
    'Travel': Color(0xFF00BCD4),
    'Subscriptions': Color(0xFF607D8B),
    'Clothing': Color(0xFFFF5722),
    'Transfers': Color(0xFF795548),
    'Others': Color(0xFF9E9E9E),
  };

  Color _catColor(String cat) => _catColors[cat] ?? const Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    const pageSize = 1000;
    final txList = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final batch = await _supabase
          .from('transactions')
          .select()
          .order('date', ascending: true)
          .range(from, from + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(batch);
      txList.addAll(rows);
      if (rows.length < pageSize) break;
      from += pageSize;
    }

    final monthKeys = <String>{};
    for (final t in txList) {
      final d = DateTime.parse(t['date'] as String);
      monthKeys.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    final sortedKeys = monthKeys.toList()..sort();
    final months = sortedKeys.map((s) {
      final parts = s.split('-');
      return DateTime(int.parse(parts[0]), int.parse(parts[1]));
    }).toList();

    setState(() {
      _transactions = txList;
      _months = months;
      _selectedMonthIdx = months.isNotEmpty ? months.length - 1 : 0;
      _loading = false;
    });
  }

  DateTime? get _currentMonth =>
      _months.isNotEmpty ? _months[_selectedMonthIdx] : null;

  List<Map<String, dynamic>> _txForMonth(DateTime m) => _transactions
      .where((t) {
        final d = DateTime.parse(t['date'] as String);
        return d.year == m.year && d.month == m.month;
      })
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _months.isEmpty
              ? const Center(
                  child: Text('No data yet. Import some transactions first.'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final m = _currentMonth!;
    final monthTxs = _txForMonth(m);
    final fmt = NumberFormat.currency(symbol: '€', decimalDigits: 2);
    final fmtK = NumberFormat.currency(symbol: '€', decimalDigits: 0);

    double income = 0, expenses = 0, transferred = 0;
    for (final t in monthTxs) {
      final a = (t['amount'] as num).toDouble();
      final cat = t['category'] as String? ?? 'Others';
      if (a > 0) {
        income += a;
      } else if (cat == 'Transfers') {
        // Internal savings movements: track separately, don't count as expense
        transferred += a.abs();
      } else {
        expenses += a;
      }
    }
    final savings = income + expenses; // expenses is negative
    final margin = income > 0 ? (savings / income * 100) : 0.0;

    // Pie chart: only real expenses (excludes savings transfers)
    final catExpenses = <String, double>{};
    for (final t in monthTxs) {
      final a = (t['amount'] as num).toDouble();
      final cat = t['category'] as String? ?? 'Others';
      if (a < 0 && cat != 'Transfers') {
        catExpenses[cat] = (catExpenses[cat] ?? 0) + a.abs();
      }
    }
    final sortedCats = catExpenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalExp = catExpenses.values.fold(0.0, (s, v) => s + v);

    // Show all available months in the bar chart (horizontal scroll handles overflow)
    final barMonths = _months;
    final barData = barMonths.map((bm) {
      double inc = 0, exp = 0;
      for (final t in _txForMonth(bm)) {
        final a = (t['amount'] as num).toDouble();
        final cat = t['category'] as String? ?? 'Others';
        if (a > 0) {
          inc += a;
        } else if (cat != 'Transfers') {
          exp += a.abs();
        }
      }
      return (month: bm, income: inc, expenses: exp);
    }).toList();

    final maxBar = barData.fold(
      0.0,
      (mx, d) => [mx, d.income, d.expenses].reduce((a, b) => a > b ? a : b),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMonthNav(m),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _statCard('Income', fmt.format(income),
                      Colors.green.shade700)),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard('Expenses', fmt.format(expenses.abs()),
                      Colors.red.shade600)),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(
                    'Savings',
                    fmt.format(savings),
                    savings >= 0 ? Colors.green.shade700 : Colors.red.shade600,
                    subtitle: income > 0
                        ? '${margin.toStringAsFixed(1)}% margin'
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (transferred > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined, size: 14,
                      color: Color(0xFF795548)),
                  const SizedBox(width: 6),
                  Text(
                    'Savings transfer: ${fmt.format(transferred)} '
                    '(excluded from expenses)',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF795548)),
                  ),
                ],
              ),
            ),
          if (sortedCats.isNotEmpty) ...[
            _sectionTitle(context, 'Expenses by category'),
            _buildPieSection(sortedCats, totalExp, fmt),
          ] else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No expenses this month',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            ),
          _sectionTitle(context, 'Monthly comparison'),
          _buildBarChart(barData, maxBar, fmtK),
          _buildBarLegend(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMonthNav(DateTime m) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _selectedMonthIdx > 0
                ? () => setState(() {
                      _selectedMonthIdx--;
                      _touchedPieIdx = -1;
                    })
                : null,
          ),
          Expanded(
            child: Text(
              DateFormat('MMMM yyyy').format(m),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _selectedMonthIdx < _months.length - 1
                ? () => setState(() {
                      _selectedMonthIdx++;
                      _touchedPieIdx = -1;
                    })
                : null,
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color,
      {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle,
                style: TextStyle(fontSize: 10, color: color.withAlpha(180))),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPieSection(List<MapEntry<String, double>> cats,
      double totalExp, NumberFormat fmt) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(
            height: 220,
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, response) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              response == null ||
                              response.touchedSection == null) {
                            _touchedPieIdx = -1;
                            return;
                          }
                          _touchedPieIdx =
                              response.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    sections: cats.asMap().entries.map((e) {
                      final isTouched = e.key == _touchedPieIdx;
                      final pct = totalExp > 0
                          ? (e.value.value / totalExp * 100)
                          : 0.0;
                      return PieChartSectionData(
                        color: _catColor(e.value.key),
                        value: e.value.value,
                        title: isTouched ? '${pct.toStringAsFixed(1)}%' : '',
                        radius: isTouched ? 82 : 74,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                    centerSpaceRadius: 16,
                    sectionsSpace: 2,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Legend — scrollable so it never pushes content below
              Expanded(
                child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: cats.map((e) {
                    final pct = totalExp > 0 ? (e.value / totalExp * 100) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: _catColor(e.key),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(e.key,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${pct.toStringAsFixed(0)}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 70,
                            child: Text(
                              fmt.format(e.value),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(
    List<({DateTime month, double income, double expenses})> barData,
    double maxVal,
    NumberFormat fmt,
  ) {
    if (barData.isEmpty) return const SizedBox.shrink();
    final safeMax = maxVal <= 0 ? 100.0 : maxVal * 1.2;

    // Each bar group needs ~68px; grow to fill screen if fewer months
    final groupWidth = 68.0;
    final minChartWidth = barData.length * groupWidth;

    return SizedBox(
      height: 220,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartWidth = minChartWidth > constraints.maxWidth
              ? minChartWidth
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: safeMax,
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 52,
                          getTitlesWidget: (val, meta) {
                            if (val == 0 || val == meta.max) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              fmt.format(val),
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.grey),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          getTitlesWidget: (val, meta) {
                            final idx = val.toInt();
                            if (idx < 0 || idx >= barData.length) {
                              return const SizedBox.shrink();
                            }
                            final d = barData[idx];
                            final isSelected =
                                d.month.year == _currentMonth!.year &&
                                    d.month.month == _currentMonth!.month;
                            // Show year only when it changes
                            final showYear = idx == 0 ||
                                barData[idx - 1].month.year != d.month.year;
                            final label = showYear
                                ? DateFormat("MMM\nyyyy").format(d.month)
                                : DateFormat('MMM').format(d.month);
                            return Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                height: 1.2,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (val) => FlLine(
                        color: Colors.grey.withAlpha(40),
                        strokeWidth: 0.8,
                      ),
                    ),
                    barGroups: barData.asMap().entries.map((e) {
                      final d = e.value;
                      final isSelected =
                          d.month.year == _currentMonth!.year &&
                              d.month.month == _currentMonth!.month;
                      return BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: d.income,
                            color: const Color(0xFF388E3C)
                                .withAlpha(isSelected ? 255 : 170),
                            width: 12,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                          BarChartRodData(
                            toY: d.expenses,
                            color: Colors.red.shade400
                                .withAlpha(isSelected ? 255 : 170),
                            width: 12,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ],
                        barsSpace: 3,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBarLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendDot(const Color(0xFF388E3C)),
          const SizedBox(width: 4),
          const Text('Income', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 16),
          _legendDot(Color(0xFFEF5350)),
          const SizedBox(width: 4),
          const Text('Expenses', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
