class ParsedTransaction {
  final DateTime date;
  final String description;
  final double amount;
  final String currency;
  final String type;
  String category;

  ParsedTransaction({
    required this.date,
    required this.description,
    required this.amount,
    required this.currency,
    required this.type,
    required this.category,
  });
}
