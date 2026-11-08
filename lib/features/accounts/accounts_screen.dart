import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final data = await _supabase.from('accounts').select().order('name');
    setState(() {
      _accounts = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  Future<void> _deleteAccount(String id) async {
    await _supabase.from('accounts').delete().eq('id', id);
    _loadAccounts();
  }

  void _showAddAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddAccountDialog(
        onSaved: _loadAccounts,
      ),
    );
  }

  String _bankIcon(String bank) {
    switch (bank.toLowerCase()) {
      case 'revolut':
        return '💳';
      case 'bnp':
        return '🏦';
      case 'bbva':
        return '🏧';
      default:
        return '🏦';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? const Center(child: Text('No accounts yet. Add one below.'))
              : ListView.builder(
                  itemCount: _accounts.length,
                  itemBuilder: (context, index) {
                    final account = _accounts[index];
                    return ListTile(
                      leading: Text(
                        _bankIcon(account['bank']),
                        style: const TextStyle(fontSize: 28),
                      ),
                      title: Text(account['name']),
                      subtitle: Text('${account['bank'].toString().toUpperCase()} · ${account['currency']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteAccount(account['id']),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAccountDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  final VoidCallback onSaved;
  const _AddAccountDialog({required this.onSaved});

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _nameController = TextEditingController();
  String _bank = 'revolut';
  String _currency = 'EUR';
  bool _loading = false;

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('accounts').insert({
        'user_id': userId,
        'name': _nameController.text.trim(),
        'bank': _bank,
        'currency': _currency,
      });
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Revolut EUR'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _bank,
            decoration: const InputDecoration(labelText: 'Bank'),
            items: const [
              DropdownMenuItem(value: 'revolut', child: Text('Revolut')),
              DropdownMenuItem(value: 'bnp', child: Text('BNP')),
              DropdownMenuItem(value: 'bbva', child: Text('BBVA Colombia')),
            ],
            onChanged: (v) => setState(() => _bank = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: const [
              DropdownMenuItem(value: 'EUR', child: Text('EUR €')),
              DropdownMenuItem(value: 'COP', child: Text('COP \$')),
            ],
            onChanged: (v) => setState(() => _currency = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
