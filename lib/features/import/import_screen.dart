import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'parsers/revolut_parser.dart';
import 'parsers/bnp_parser.dart';
import 'parsers/parsed_transaction.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _accounts = [];
  String? _selectedAccountId;
  String? _selectedFileName;
  List<ParsedTransaction> _transactions = [];
  bool _loadingAccounts = true;
  bool _saving = false;
  String? _error;
  String? _rawDebugText;
  bool _showDebug = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final data = await _supabase.from('accounts').select().order('name');
    setState(() {
      _accounts = List<Map<String, dynamic>>.from(data);
      _loadingAccounts = false;
    });
  }

  String? get _selectedBank => _accounts
      .where((a) => a['id'] == _selectedAccountId)
      .map((a) => a['bank'] as String?)
      .firstOrNull;

  Future<void> _pickFile() async {
    setState(() => _error = null);

    final isRevolutCsv = _selectedBank == 'revolut';
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: isRevolutCsv ? ['csv'] : ['pdf'],
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();

    try {
      List<ParsedTransaction> parsed;
      String? rawDebug;
      if (isRevolutCsv) {
        final content = String.fromCharCodes(bytes);
        parsed = RevolutParser.parse(content);
      } else {
        parsed = BnpParser.parse(bytes);
        rawDebug = BnpParser.extractRawText(bytes);
      }

      setState(() {
        _selectedFileName = file.name;
        _transactions = parsed;
        _rawDebugText = rawDebug;
        _showDebug = false;
        _error = parsed.isEmpty ? 'No transactions found.' : null;
      });
    } catch (e) {
      setState(() => _error = 'Error parsing file: $e');
    }
  }

  Future<void> _save() async {
    if (_selectedAccountId == null || _transactions.isEmpty) return;
    setState(() => _saving = true);

    try {
      final userId = _supabase.auth.currentUser!.id;
      final rows = _transactions.map((t) => {
        'user_id': userId,
        'account_id': _selectedAccountId,
        'date': t.date.toIso8601String().split('T').first,
        'description': t.description,
        'amount': t.amount,
        'currency': t.currency,
        'category': t.category,
        'source_file': _selectedFileName,
      }).toList();

      for (var i = 0; i < rows.length; i += 100) {
        final batch = rows.sublist(i, (i + 100).clamp(0, rows.length));
        await _supabase.from('transactions').insert(batch);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_transactions.length} transactions imported.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

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

  Color _catColor(String cat) =>
      _categoryColors[cat] ?? const Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '€', decimalDigits: 2);
    final dateFmt = DateFormat('dd MMM yyyy');
    final bank = _selectedBank;
    final fileLabel = bank == 'revolut' ? 'Select CSV' : 'Select PDF';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import transactions'),
        actions: [
          if (_transactions.isNotEmpty && _selectedAccountId != null)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Save ${_transactions.length}'),
            ),
        ],
      ),
      body: _loadingAccounts
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedAccountId,
                        decoration: const InputDecoration(
                          labelText: 'Account',
                          border: OutlineInputBorder(),
                        ),
                        items: _accounts.map((a) {
                          final bankTag = (a['bank'] as String)
                              .toUpperCase();
                          return DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text('${a['name']} · $bankTag'),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() {
                          _selectedAccountId = v;
                          _transactions = [];
                          _selectedFileName = null;
                          _error = null;
                        }),
                        hint: _accounts.isEmpty
                            ? const Text('No accounts found')
                            : const Text('Select account'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            _selectedAccountId == null ? null : _pickFile,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_selectedFileName ?? fileLabel),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_transactions.isNotEmpty || _rawDebugText != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text('${_transactions.length} transactions',
                            style: Theme.of(context).textTheme.labelLarge),
                        const Spacer(),
                        if (_transactions.isNotEmpty)
                          Text(
                            fmt.format(_transactions.fold(
                                0.0, (s, t) => s + t.amount)),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _transactions.fold(
                                          0.0, (s, t) => s + t.amount) >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        if (_rawDebugText != null) ...[
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _showDebug = !_showDebug),
                            icon: Icon(_showDebug
                                ? Icons.bug_report
                                : Icons.bug_report_outlined,
                                size: 16),
                            label: Text(_showDebug ? 'Hide raw' : 'Show raw'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_showDebug && _rawDebugText != null)
                    Container(
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(
                          _rawDebugText!,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  if (_transactions.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        itemCount: _transactions.length,
                        itemBuilder: (context, i) {
                          final t = _transactions[i];
                          final catColor = _catColor(t.category);
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: catColor.withAlpha(38),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                t.category,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: catColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(t.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(dateFmt.format(t.date)),
                            trailing: Text(
                              fmt.format(t.amount),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: t.amount >= 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
