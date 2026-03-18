import 'package:intl/intl.dart';

final NumberFormat _currencyFormat = NumberFormat.currency(
  symbol: 'GHS ',
  decimalDigits: 2,
);

String formatMoney(num amount) => _currencyFormat.format(amount);

String formatEventWindow(DateTime start, DateTime? end) {
  final startLabel = DateFormat('EEE, MMM d • h:mm a').format(start);
  if (end == null) return startLabel;
  return '$startLabel - ${DateFormat('h:mm a').format(end)}';
}

String formatShortDate(DateTime value) =>
    DateFormat('MMM d, yyyy').format(value);

String formatDate(DateTime value) => DateFormat('MMM d, yyyy').format(value);

String formatPromoTime(DateTime? value) {
  if (value == null) return 'Start anytime';
  return DateFormat('MMM d • h:mm a').format(value);
}
