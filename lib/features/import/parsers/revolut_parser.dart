import 'package:csv/csv.dart';
import '../classifier.dart';
import 'parsed_transaction.dart';

class RevolutParser {
  static List<ParsedTransaction> parse(String csvContent) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvContent);
    if (rows.isEmpty) return [];

    final header = rows.first.map((e) => e.toString().trim()).toList();

    // Support both English and Spanish Revolut exports
    final typeIdx      = _col(header, ['Type',         'Tipo']);
    final productIdx   = _col(header, ['Product',      'Cuenta Revolut']);
    final completedIdx = _col(header, ['Completed Date','Fecha de finalización']);
    final startedIdx   = _col(header, ['Started Date', 'Fecha de inicio']);
    final descIdx      = _col(header, ['Description',  'Descripción']);
    final amountIdx    = _col(header, ['Amount',       'Monto']);
    final currencyIdx  = _col(header, ['Currency',     'Moneda']);
    final stateIdx     = _col(header, ['State',        'Estado']);

    if ([typeIdx, productIdx, descIdx, amountIdx, currencyIdx, stateIdx]
        .contains(-1)) {
      throw Exception('Unrecognized CSV format');
    }

    final results = <ParsedTransaction>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final maxIdx = [typeIdx, productIdx, descIdx, amountIdx, currencyIdx,
          stateIdx, completedIdx, startedIdx].reduce((a, b) => a > b ? a : b);
      if (row.length <= maxIdx) continue;

      final product = row[productIdx].toString().trim();
      // "Current" (EN) or "Actual" (ES)
      if (product != 'Current' && product != 'Actual') continue;

      final state = row[stateIdx].toString().trim();
      // "COMPLETED" (EN) or "Completado" (ES)
      if (state != 'COMPLETED' && state != 'Completado') continue;

      // Use completed date; fall back to started date
      String dateStr = '';
      if (completedIdx != -1 && completedIdx < row.length) {
        dateStr = row[completedIdx].toString().trim();
      }
      if (dateStr.isEmpty && startedIdx != -1 && startedIdx < row.length) {
        dateStr = row[startedIdx].toString().trim();
      }
      if (dateStr.isEmpty) continue;

      final date = _parseDate(dateStr);
      if (date == null) continue;

      final rawType = row[typeIdx].toString().trim();
      final type    = _normalizeType(rawType);
      final rawDesc = _decodeHtml(row[descIdx].toString().trim());
      final desc    = _normalizeDesc(rawDesc);
      final amountStr  = row[amountIdx].toString().trim();
      final currency   = row[currencyIdx].toString().trim();

      final amount = double.tryParse(amountStr) ?? 0.0;
      final category = Classifier.classify(desc, type);

      results.add(ParsedTransaction(
        date: date,
        description: desc,
        amount: amount,
        currency: currency,
        type: type,
        category: category,
      ));
    }

    return results;
  }

  // Find column index accepting multiple possible header names
  static int _col(List<String> header, List<String> names) {
    for (final name in names) {
      final idx = header.indexOf(name);
      if (idx != -1) return idx;
    }
    return -1;
  }

  // Map Spanish type values to English equivalents
  static String _normalizeType(String raw) {
    switch (raw) {
      case 'Depósito':          return 'TOPUP';
      case 'Pago con tarjeta':  return 'CARD_PAYMENT';
      case 'Transferencia':     return 'TRANSFER';
      case 'Cambio':            return 'EXCHANGE';
      case 'Reembolso':         return 'REFUND';
      case 'Cobro':             return 'FEE';
      default:                  return raw;
    }
  }

  // Normalize Spanish description prefixes so the classifier works
  // "Pago de X"         → "Payment from X"
  // "Transferencia de X"→ "Transfer from X"
  // "Transferencia a X" → "Transfer to X"
  static String _normalizeDesc(String desc) {
    final lower = desc.toLowerCase();
    if (lower.startsWith('pago de ')) {
      return 'Payment from ${desc.substring(8).trim()}';
    }
    if (lower.startsWith('transferencia de ')) {
      return 'Transfer from ${desc.substring(17).trim()}';
    }
    if (lower.startsWith('transferencia a ')) {
      return 'Transfer to ${desc.substring(16).trim()}';
    }
    return desc;
  }

  static DateTime? _parseDate(String raw) {
    try {
      return DateTime.parse(raw.replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }

  static String _decodeHtml(String text) => text
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
