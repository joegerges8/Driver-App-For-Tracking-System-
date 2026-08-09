// ─── WhatsApp helpers ────────────────────────────────────────────────────────
// Everything needed to turn an order into a WhatsApp chat the driver can send
// with one tap: a phone number wa.me will actually accept, and the message body
// that lands pre-typed in the input box.
//
// Both functions here are deliberately pure — no BuildContext, no provider, no
// Flutter import — so the wording and the number rules can be unit-tested
// without pumping a widget. See test/whatsapp_test.dart.
// ─────────────────────────────────────────────────────────────────────────────

// Numbers that reach us without a country code are assumed Lebanese, matching
// the dispatcher dashboard (dispatcher-dashboard-frontend/js/orders.js).
const String _defaultCountryCode = '961';

// Turns whatever the customer typed into their Shopify checkout into the bare
// international digits wa.me expects ('96171123456' — no '+', no spaces).
//
// The phone column is free-form text, so this has to cope with every shape a
// customer might use. In particular a Lebanese number is normally given in
// local form, '03 719 871', where the leading 0 is a domestic trunk prefix that
// must be swapped for the country code rather than kept: sending wa.me
// '03719871' opens a chat with nobody.
//
// Returns null when there is nothing usable to dial, so callers can tell the
// driver instead of launching a dead link.
String? toWhatsAppNumber(String? rawPhone) {
  if (rawPhone == null) return null;

  final trimmed = rawPhone.trim();
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  // An explicit '+' or '00' means the country code is already there.
  if (trimmed.startsWith('+')) return digits;
  if (digits.startsWith('00')) return digits.substring(2);

  // Domestic trunk prefix: '03 719 871' -> '961 3 719 871'.
  if (digits.startsWith('0')) return '$_defaultCountryCode${digits.substring(1)}';

  if (digits.startsWith(_defaultCountryCode)) return digits;

  return '$_defaultCountryCode$digits';
}

// LEFT-TO-RIGHT MARK. Arabic runs right-to-left, so a bare '$45' or '#2672'
// sitting inside an Arabic sentence gets reordered by the bidi algorithm and
// renders as '45$', with the '#' liable to jump to the far end of the number.
// Fencing each Latin-script run — prices, order numbers, and the driver and
// store names, which are not transliterated — pins it the right way round.
const String _lrm = '‎';

String _ltr(String value) => '$_lrm$value$_lrm';

// Builds the message the driver sends the customer when starting a delivery.
//
// It always carries BOTH languages, whatever the app is currently set to: the
// driver has no idea whether this particular customer reads Arabic or English,
// and guessing wrong is worse than a slightly longer message. That is also why
// this lives here rather than in AppLocalizations, whose whole job is to return
// exactly one language for the active locale.
//
// Every field degrades on its own. An order with no store name still produces a
// sensible message, which is what happens against a backend that predates
// store_name reaching the driver endpoints.
String buildOrderWhatsAppMessage({
  String storeName = '',
  String customerName = '',
  String driverName = '',
  String orderNumber = '',
  int price = 0,
  bool isPrepaid = false,
}) {
  final store = storeName.trim();
  final customer = customerName.trim();
  final driver = driverName.trim();
  final number = orderNumber.trim();

  return '${_englishBlock(store, customer, driver, number, price, isPrepaid)}'
      '\n\n'
      '${_arabicBlock(store, customer, driver, number, price, isPrepaid)}';
}

String _englishBlock(
  String store,
  String customer,
  String driver,
  String number,
  int price,
  bool isPrepaid,
) {
  final lines = <String>[
    customer.isEmpty ? 'Hi! 👋' : 'Hi $customer! 👋',
    _englishIntro(store, driver),
  ];

  final orderLine = _englishOrderLine(number, price, isPrepaid);
  if (orderLine.isNotEmpty) lines.add(orderLine);

  lines.add('Please send me your location 📍');

  return lines.join('\n');
}

String _englishIntro(String store, String driver) {
  final from = store.isEmpty ? 'your order' : 'your order from $store';
  return driver.isEmpty
      ? 'Your driver here, delivering $from.'
      : 'This is $driver, delivering $from.';
}

// The money line. A zero price means the backend had no total for this order,
// and quoting '$0' to a customer is worse than saying nothing — so the amount
// and the payment wording drop out together, leaving just the order number. If
// neither is known there is no line at all.
String _englishOrderLine(String number, int price, bool isPrepaid) {
  final label = number.isEmpty ? '' : 'Order #$number';

  if (price <= 0) return label;

  final amount = isPrepaid ? '\$$price, already paid ✅' : '\$$price (cash on delivery)';

  return label.isEmpty ? amount : '$label — $amount';
}

String _arabicBlock(
  String store,
  String customer,
  String driver,
  String number,
  int price,
  bool isPrepaid,
) {
  final lines = <String>[
    customer.isEmpty ? 'مرحبا! 👋' : 'مرحبا ${_ltr(customer)}! 👋',
    _arabicIntro(store, driver),
  ];

  final orderLine = _arabicOrderLine(number, price, isPrepaid);
  if (orderLine.isNotEmpty) lines.add(orderLine);

  lines.add('الرجاء إرسال موقعك 📍');

  return lines.join('\n');
}

String _arabicIntro(String store, String driver) {
  final from = store.isEmpty ? 'أوصل لك طلبك' : 'أوصل لك طلبك من ${_ltr(store)}';
  return driver.isEmpty
      ? 'معك سائق التوصيل، $from.'
      : 'أنا ${_ltr(driver)}، $from.';
}

String _arabicOrderLine(String number, int price, bool isPrepaid) {
  final label = number.isEmpty ? '' : 'الطلب ${_ltr('#$number')}';

  if (price <= 0) return label;

  final amount = isPrepaid
      ? '${_ltr('\$$price')}، مدفوع مسبقاً ✅'
      : '${_ltr('\$$price')} (نقداً عند الاستلام)';

  return label.isEmpty ? amount : '$label — $amount';
}
