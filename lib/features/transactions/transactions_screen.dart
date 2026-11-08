import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../accounts/accounts_screen.dart';
import '../import/import_screen.dart';
import '../analytics/analytics_screen.dart';

sealed class _Item {}

class _MonthHeader extends _Item {
  final String label;
  final double income;
  final double expense;
  _MonthHeader(this.label, this.income, this.expense);
}

class _TxRow extends _Item {
  final Map<String, dynamic> data;
  _TxRow(this.data);
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  bool _searchVisible = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedCategories = {};

  static const Map<String, Color> _categoryColors = {
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

  Color _catColor(String? cat) =>
      _categoryColors[cat] ?? const Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _searchController.addListener(
        () => setState(() => _searchQuery = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    final all = await _fetchAllTransactions();
    setState(() {
      _transactions = all;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _fetchAllTransactions() async {
    const pageSize = 1000;
    final all = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final batch = await _supabase
          .from('transactions')
          .select()
          .order('date', ascending: false)
          .range(from, from + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(batch);
      all.addAll(rows);
      if (rows.length < pageSize) break;
      from += pageSize;
    }
    return all;
  }

  double get _totalBalance =>
      _transactions.fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

  Set<String> get _allCategories =>
      _transactions.map((t) => t['category'] as String? ?? 'Others').toSet();

  List<Map<String, dynamic>> get _filtered {
    var list = _transactions;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((t) =>
              (t['description'] as String).toLowerCase().contains(q))
          .toList();
    }
    if (_selectedCategories.isNotEmpty) {
      list = list
          .where((t) => _selectedCategories.contains(t['category']))
          .toList();
    }
    return list;
  }

  List<_Item> _buildItems() {
    final filtered = _filtered;

    // Precompute month totals in one pass
    final monthIncome = <String, double>{};
    final monthExpense = <String, double>{};
    for (final t in filtered) {
      final d = DateTime.parse(t['date'] as String);
      final key = DateFormat('yyyy-MM').format(d);
      final amount = (t['amount'] as num).toDouble();
      if (amount > 0) {
        monthIncome[key] = (monthIncome[key] ?? 0) + amount;
      } else {
        monthExpense[key] = (monthExpense[key] ?? 0) + amount;
      }
    }

    final items = <_Item>[];
    String? currentKey;
    for (final t in filtered) {
      final d = DateTime.parse(t['date'] as String);
      final key = DateFormat('yyyy-MM').format(d);
      if (key != currentKey) {
        items.add(_MonthHeader(
          DateFormat('MMMM yyyy').format(d),
          monthIncome[key] ?? 0,
          monthExpense[key] ?? 0,
        ));
        currentKey = key;
      }
      items.add(_TxRow(t));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '€', decimalDigits: 2);
    final dateFmt = DateFormat('dd MMM');
    final cs = Theme.of(context).colorScheme;
    final items = _buildItems();
    final sortedCats = _allCategories.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search transactions...',
                  border: InputBorder.none,
                ),
              )
            : const Text('BettyBalance'),
        actions: [
          IconButton(
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            tooltip: _searchVisible ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searchVisible = !_searchVisible;
              if (!_searchVisible) _searchController.clear();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Analytics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance),
            tooltip: 'Accounts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _supabase.auth.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Balance summary
                Container(
                  color: cs.primaryContainer,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Balance',
                              style:
                                  Theme.of(context).textTheme.labelMedium),
                          Text(
                            fmt.format(_totalBalance),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _totalBalance >= 0
                                      ? Colors.green.shade700
                                      : Colors.red,
                                ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text('${_transactions.length} transactions',
                          style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                ),
                // Category filter chips
                if (_transactions.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: FilterChip(
                            label: const Text('All'),
                            selected: _selectedCategories.isEmpty,
                            onSelected: (_) => setState(
                                () => _selectedCategories.clear()),
                          ),
                        ),
                        ...sortedCats.map((cat) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: FilterChip(
                                label: Text(cat),
                                selected:
                                    _selectedCategories.contains(cat),
                                selectedColor:
                                    _catColor(cat).withAlpha(50),
                                checkmarkColor: _catColor(cat),
                                onSelected: (sel) => setState(() {
                                  sel
                                      ? _selectedCategories.add(cat)
                                      : _selectedCategories.remove(cat);
                                }),
                              ),
                            )),
                      ],
                    ),
                  ),
                // Column headers
                if (_transactions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      border: Border(
                          bottom:
                              BorderSide(color: cs.outlineVariant)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                            width: 52,
                            child: Text('Date',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey))),
                        SizedBox(width: 6),
                        SizedBox(
                            width: 96,
                            child: Text('Category',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey))),
                        SizedBox(width: 6),
                        Expanded(
                            child: Text('Description',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey))),
                        SizedBox(width: 6),
                        SizedBox(
                            width: 82,
                            child: Text('Income',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green))),
                        SizedBox(width: 4),
                        SizedBox(
                            width: 82,
                            child: Text('Expense',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red))),
                      ],
                    ),
                  ),
                // List
                Expanded(
                  child: _transactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inbox,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 8),
                              const Text('No transactions yet.'),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _openImport,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Import CSV'),
                              ),
                            ],
                          ),
                        )
                      : items.isEmpty
                          ? const Center(child: Text('No results'))
                          : RefreshIndicator(
                              onRefresh: _loadTransactions,
                              child: ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, i) {
                                  final item = items[i];
                                  if (item is _MonthHeader) {
                                    return _buildMonthHeader(
                                        context, item, fmt);
                                  } else if (item is _TxRow) {
                                    return _buildTxRow(context,
                                        item.data, fmt, dateFmt);
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                ),
              ],
            ),
      floatingActionButton: _transactions.isNotEmpty
          ? FloatingActionButton(
              onPressed: _openImport,
              tooltip: 'Import CSV',
              child: const Icon(Icons.upload_file),
            )
          : null,
    );
  }

  Widget _buildMonthHeader(
      BuildContext context, _MonthHeader h, NumberFormat fmt) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHigh,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          Text(
            h.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
          const Spacer(),
          if (h.income > 0)
            Text(
              '+${fmt.format(h.income)}',
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF388E3C),
                  fontWeight: FontWeight.w600),
            ),
          if (h.income > 0 && h.expense < 0)
            const SizedBox(width: 10),
          if (h.expense < 0)
            Text(
              fmt.format(h.expense),
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                  fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildTxRow(BuildContext context, Map<String, dynamic> t,
      NumberFormat fmt, DateFormat dateFmt) {
    final amount = (t['amount'] as num).toDouble();
    final category = t['category'] as String? ?? 'Others';
    final date = DateTime.parse(t['date'] as String);
    final catColor = _catColor(category);
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: cs.outlineVariant.withAlpha(60)),
        ),
      ),
      child: Row(
        children: [
          // Date
          SizedBox(
            width: 52,
            child: Text(
              dateFmt.format(date),
              style:
                  const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 6),
          // Category chip
          SizedBox(
            width: 96,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: catColor.withAlpha(38),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                category,
                style: TextStyle(
                  fontSize: 10,
                  color: catColor,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Description
          Expanded(
            child: Text(
              t['description'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          // Income column
          SizedBox(
            width: 82,
            child: amount > 0
                ? Text(
                    fmt.format(amount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF388E3C)),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 4),
          // Expense column
          SizedBox(
            width: 82,
            child: amount < 0
                ? Text(
                    fmt.format(amount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _openImport() async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
    if (imported == true) _loadTransactions();
  }
}
