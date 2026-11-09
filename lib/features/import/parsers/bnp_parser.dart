import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../classifier.dart';
import 'parsed_transaction.dart';

class BnpParser {
  static const _months = {
    'janvier': 1, 'fevrier': 2, 'février': 2, 'mars': 3,
    'avril': 4, 'mai': 5, 'juin': 6, 'juillet': 7,
    'aout': 8, 'août': 8, 'septembre': 9, 'octobre': 10,
    'novembre': 11, 'decembre': 12, 'décembre': 12,
  };

  // Fix UTF-8 characters mangled by the PDF extractor (Latin-1 misread as UTF-8)
  static String _fixEncoding(String s) => s
      .replaceAll('Ã©', 'é').replaceAll('Ã¨', 'è').replaceAll('Ãª', 'ê')
      .replaceAll('Ã ', 'à').replaceAll('Ã¢', 'â')
      .replaceAll('Ã®', 'î').replaceAll('Ã¯', 'ï')
      .replaceAll('Ã´', 'ô').replaceAll('Ã»', 'û').replaceAll('Ã¹', 'ù')
      .replaceAll('Ã§', 'ç').replaceAll('Ã‰', 'É').replaceAll('Ãˆ', 'È')
      .replaceAll('ÃŠ', 'Ê').replaceAll('Ã€', 'À').replaceAll('Ã‚', 'Â')
      .replaceAll('Ã\u008e', 'Î').replaceAll('Ã\u008e', 'Î')
      .replaceAll('Ã®', 'î').replaceAll('ÃÎle', 'Île');

  // Normalize accents + non-breaking space for keyword matching
  static String _norm(String s) => s
      .replaceAll('é', 'e').replaceAll('è', 'e').replaceAll('ê', 'e')
      .replaceAll('à', 'a').replaceAll('â', 'a')
      .replaceAll('î', 'i').replaceAll('ï', 'i')
      .replaceAll('ô', 'o').replaceAll('û', 'u').replaceAll('ù', 'u')
      .replaceAll('ç', 'c').replaceAll('É', 'E').replaceAll('È', 'E')
      .replaceAll('Ê', 'E').replaceAll('À', 'A').replaceAll('Â', 'A')
      .replaceAll('Î', 'I').replaceAll('Ô', 'O').replaceAll('Û', 'U')
      .replaceAll('Ù', 'U').replaceAll('Ç', 'C')
      .replaceAll(' ', ' ');

  /// Uses extractTextLines() which groups text by Y-position and
  /// orders within each line by X-position, giving proper line breaks
  /// and word spacing even for PDFs that don't use space characters.
  static String _extractLines(Uint8List pdfBytes) {
    final document = PdfDocument(inputBytes: pdfBytes);
    final extractor = PdfTextExtractor(document);
    final buf = StringBuffer();
    for (var i = 0; i < document.pages.count; i++) {
      final lines = extractor.extractTextLines(
        startPageIndex: i,
        endPageIndex: i,
      );
      for (final line in lines) {
        final t = _fixEncoding(line.text.trim());
        if (t.isNotEmpty) buf.writeln(t);
      }
    }
    document.dispose();
    return buf.toString();
  }

  static String extractRawText(Uint8List pdfBytes) {
    final document = PdfDocument(inputBytes: pdfBytes);
    final extractor = PdfTextExtractor(document);
    final buf = StringBuffer();
    for (var i = 0; i < document.pages.count; i++) {
      buf.writeln('=== PAGE ${i + 1} ===');
      final lines = extractor.extractTextLines(
        startPageIndex: i,
        endPageIndex: i,
      );
      for (final line in lines) {
        final t = line.text.trim();
        if (t.isNotEmpty) buf.writeln(t);
      }
    }
    document.dispose();
    return buf.toString();
  }

  static List<ParsedTransaction> parse(Uint8List pdfBytes) {
    final raw = _extractLines(pdfBytes);
    final preview = raw.length > 2000 ? raw.substring(0, 2000) : raw;
    dev.log('BNP textLines (first 2000):\n$preview', name: 'BnpParser');
    return _parseText(raw);
  }

  static List<ParsedTransaction> _parseText(String text) {
    final year = _extractYear(text);
    final startMonth = _extractStartMonth(text);

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    var bodyStart = 0;
    var bodyEnd = lines.length;
    var foundFirstSolde = false;

    for (var i = 0; i < lines.length; i++) {
      final n = _norm(lines[i]).toUpperCase();
      if (!foundFirstSolde && n.contains('SOLDE CREDITEUR AU')) {
        bodyStart = i + 1;
        foundFirstSolde = true;
      }
      if (n.contains('TOTAL DES OPERATIONS') || n.contains('TOTAL DES MOUVEMENTS')) {
        bodyEnd = i;
        break;
      }
    }

    dev.log('BNP body: lines $bodyStart–$bodyEnd / ${lines.length} (year=$year month=$startMonth)', name: 'BnpParser');

    // DD.MM not followed by another dot or digit (avoids matching DD.MM.YYYY)
    final txDateRe = RegExp(r'^\d{2}\.\d{2}(?![.\d])');
    final amountRe = RegExp(r'(?<![.\d])\d{1,3}(?:[  ]\d{3})*,\d{2}');

    final results = <ParsedTransaction>[];
    var block = <String>[];

    void flush() {
      if (block.isEmpty) return;
      final tx = _parseBlock(block, year, startMonth);
      if (tx != null) results.add(tx);
      block = [];
    }

    for (var i = bodyStart; i < bodyEnd; i++) {
      final line = lines[i];
      // Skip pure valeur date lines like "07.10"
      if (RegExp(r'^\d{2}\.\d{2}$').hasMatch(line)) continue;
      // Skip foreign-currency suffix lines like "NLD 31,34EUR"
      if (RegExp(r'^[A-Z]{3}\s+[\d,]+EUR$').hasMatch(line)) continue;
      // Skip amount-only lines before first block
      if (amountRe.hasMatch(line) && !txDateRe.hasMatch(line) && block.isEmpty) continue;

      if (txDateRe.hasMatch(line)) {
        flush();
        block.add(line);
      } else {
        block.add(line);
      }
    }
    flush();

    dev.log('BNP parsed ${results.length} transactions', name: 'BnpParser');
    return results;
  }

  static ParsedTransaction? _parseBlock(
      List<String> block, int year, int startMonth) {
    if (block.isEmpty) return null;

    final firstLine = block.first;
    final dateMatch = RegExp(r'^(\d{2})\.(\d{2})').firstMatch(firstLine);
    if (dateMatch == null) return null;

    final day = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    var txYear = year;
    if (startMonth == 12 && month == 1) txYear = year + 1;
    final date = DateTime(txYear, month, day);

    final combined = block.join(' ');
    final upper = _norm(combined).toUpperCase();

    String type;
    bool positive;

    if (upper.contains('REMBOURST CB') || upper.contains('REMBOURSEMENT CB') ||
        (upper.contains('REMBOURSEMENT') && upper.contains('CARTE'))) {
      type = 'card refund'; positive = true;
    } else if (upper.contains('RETROCESSION')) {
      // Any RETROCESSION is a credit (reversal/refund from BNP)
      type = 'card refund'; positive = true;
    } else if (upper.contains('FACTURE') && upper.contains('CARTE')) {
      type = 'card payment'; positive = false;
    } else if ((upper.contains('VIR') || upper.contains('VIREMENT')) &&
        (upper.contains('RECU') || upper.contains('RECUE'))) {
      type = 'deposit'; positive = true;
    } else if ((upper.contains('VIR') || upper.contains('VIREMENT')) &&
        (upper.contains('EMIS') || upper.contains('EMISE'))) {
      type = 'transfer'; positive = false;
    } else if (upper.contains('VIR PERMANENT') || upper.contains('VIREMENT PERMANENT')) {
      type = 'transfer'; positive = false;
    } else if (upper.contains('PRLV') || upper.contains('PRELEVEMENT')) {
      type = 'direct debit'; positive = false;
    } else if (upper.contains('RETRAIT')) {
      type = 'direct debit'; positive = false;
    } else if (RegExp(r'DU\s+\d{6}').hasMatch(upper)) {
      // Standalone card payment: "DU DDMMYY MERCHANT" without FACTURE(S) CARTE header
      type = 'card payment'; positive = false;
    } else if (upper.contains('*COMMISSIONS') || upper.contains('COTISATION') ||
        upper.contains('FRAIS DE TENUE')) {
      type = 'direct debit'; positive = false;
    } else if (upper.contains('REMISE CHEQUE') || upper.contains('REMISE DE CHEQUE')) {
      type = 'deposit'; positive = true;
    } else {
      dev.log('BNP unrecognized: ${block.take(3).join(' | ')}', name: 'BnpParser');
      return null;
    }

    // Strict French number format with negative lookbehind to avoid matching
    // digits embedded in dates: "21.12 200,00" must not match as "12 200,00".
    // (?<![.\d]) ensures we don't start in the middle of "21.12" or "200,00".
    final amountRe = RegExp(r'(?<![.\d])(\d{1,3}(?:[  ]\d{3})*,\d{2})');
    final allAmounts = amountRe.allMatches(combined).toList();
    if (allAmounts.isEmpty) return null;

    final rawAmount = allAmounts.last.group(1)!
        .replaceAll(' ', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    var amount = double.tryParse(rawAmount);
    if (amount == null || amount == 0) return null;
    if (!positive) amount = -amount;

    final description = _buildDescription(combined, type);
    final category = Classifier.classify(description, type);

    return ParsedTransaction(
      date: date,
      description: description,
      amount: amount,
      currency: 'EUR',
      type: type,
      category: category,
    );
  }

  static String _buildDescription(String raw, String type) {
    // extractTextLines() puts "DD.MM [DD.MM] [amount]" on its own line before the
    // description text, so the combined block starts with that prefix.
    // Strip it so description-extraction regexes work on clean text.
    final cleaned = raw.replaceFirst(
      RegExp(
        r'^\d{2}\.\d{2}'               // transaction date
        r'(?:\s+\d{2}\.\d{2})?'        // optional valeur date
        r'(?:\s+\d{1,3}(?:[  ]\d{3})*,\d{2})?'  // optional amount
        r'\s+',
      ),
      '',
    ).trim();

    if (type == 'card payment') {
      final m = RegExp(
        r'DU \d{6}\s+(.+?)(?:\s+(?:\d{2}[.\-]\d{2}|[\d ]+,\d{2})|\s*$)',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (m != null) return _cleanEnd(m.group(1)!);
      // Fallback: strip FACTURE(S) CARTE XXXX prefix
      return _cleanEnd(cleaned.replaceFirst(
          RegExp(r'^FACTURES?\(S\)?\s+CARTE\s+[\dX]+\s+', caseSensitive: false), ''));
    }

    if (type == 'card refund') {
      if (cleaned.toUpperCase().contains('DU ')) {
        final m = RegExp(
          r'DU \d{6}\s+(.+?)(?:\s+(?:\d{2}\.\d{2}|[\d ]+,\d{2})|\s*$)',
          caseSensitive: false,
        ).firstMatch(cleaned);
        if (m != null) return '${_cleanEnd(m.group(1)!)} (refund)';
      }
      return _cleanEnd(cleaned);
    }

    if (type == 'deposit') {
      final nameM = RegExp(
        r'/DE\s+(.+?)(?:\s+/REF|\s+/MOTIF|\s+/DATE|\s+\d{2}[./]\d{2}|$)',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (nameM != null) {
        final name = _cleanEnd(nameM.group(1)!);
        final motifM = RegExp(
          r'/MOTIF\s+(.+?)(?:\s+/REF|\s+\d{2}\.\d{2}|\s*$)',
          caseSensitive: false,
        ).firstMatch(cleaned);
        final motif = motifM != null ? _cleanEnd(motifM.group(1)!) : null;
        // Prefix with "From " so the classifier can detect person transfers
        return motif != null && motif.isNotEmpty
            ? 'From $name - $motif'
            : 'From $name';
      }
    }

    if (type == 'transfer') {
      // /BEN is case-insensitive; name ends at /REF, /MOTIF, a date, or end of string
      final benM = RegExp(
        r'/BEN\s+(.+?)(?:\s+/REF|\s+/MOTIF|\s+/DATE|\s+\d{2}[./]\d{2}|\s*$)',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (benM != null) return 'To ${_cleanEnd(benM.group(1)!)}';
    }

    if (type == 'direct debit') {
      if (cleaned.toUpperCase().contains('RETRAIT')) return 'ATM withdrawal';
      final m = RegExp(
        r'PRLV SEPA (.+?)(?:\s+ECH|\s+ID|\s+\d{2}\.\d{2}|$)',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (m != null) return _cleanEnd(m.group(1)!);
      if (cleaned.toUpperCase().contains('*COMMISSIONS') ||
          cleaned.toUpperCase().contains('COTISATION') ||
          cleaned.toUpperCase().contains('FRAIS DE TENUE')) {
        return 'BNP bank fee';
      }
    }

    return _cleanEnd(
      cleaned.replaceAll(RegExp(r'\s+\d{2}\.\d{2}\s+[\d ,]+,\d{2}\s*$'), ''),
    );
  }

  static String _cleanEnd(String s) =>
      s.trim().replaceAll(RegExp(r'\s{2,}'), ' ');

  static int _extractYear(String text) {
    // Normalize first so accented month names (décembre, février…) match \w+
    final norm = _norm(text);
    final m1 = RegExp(r'du\s+\d+\s+\w+\s+(\d{4})', caseSensitive: false)
        .firstMatch(norm);
    if (m1 != null) return int.tryParse(m1.group(1)!) ?? DateTime.now().year;
    final m2 = RegExp(r'du\s+\d{2}\.\d{2}\.(\d{4})', caseSensitive: false)
        .firstMatch(norm);
    if (m2 != null) return int.tryParse(m2.group(1)!) ?? DateTime.now().year;
    return DateTime.now().year;
  }

  static int _extractStartMonth(String text) {
    final lower = _norm(text.toLowerCase());
    final m1 = RegExp(r'du\s+\d+\s+(\w+)\s+\d{4}', caseSensitive: false)
        .firstMatch(lower);
    if (m1 != null) return _months[m1.group(1)] ?? 1;
    final m2 = RegExp(r'du\s+\d{2}\.(\d{2})\.\d{4}', caseSensitive: false)
        .firstMatch(lower);
    if (m2 != null) return int.tryParse(m2.group(1)!) ?? 1;
    return 1;
  }
}
