import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/utils/whatsapp.dart';
import 'package:flutter_test/flutter_test.dart';

// U+200E, the left-to-right mark the Arabic block fences Latin runs with.
const String lrm = '‎';

void main() {
  group('toWhatsAppNumber', () {
    test('keeps an explicitly international number', () {
      expect(toWhatsAppNumber('+961 3 719 871'), '9613719871');
    });

    test('strips the 00 international prefix', () {
      expect(toWhatsAppNumber('00961 3 719 871'), '9613719871');
    });

    // The common case, and the one the old strip-everything-but-digits code got
    // wrong: the domestic trunk 0 has to become the country code, not survive.
    test('swaps a local trunk zero for the country code', () {
      expect(toWhatsAppNumber('03 719 871'), '9613719871');
    });

    test('leaves a bare country-code number alone', () {
      expect(toWhatsAppNumber('961 3 719 871'), '9613719871');
    });

    test('prefixes the country code onto a number that has none', () {
      expect(toWhatsAppNumber('3 719 871'), '9613719871');
    });

    test('tolerates punctuation around the digits', () {
      expect(toWhatsAppNumber(' (03) 719-871 '), '9613719871');
    });

    test('returns null when there is nothing dialable', () {
      expect(toWhatsAppNumber(''), isNull);
      expect(toWhatsAppNumber('   '), isNull);
      expect(toWhatsAppNumber('abc'), isNull);
      expect(toWhatsAppNumber(null), isNull);
    });
  });

  group('buildOrderWhatsAppMessage', () {
    String cod() => buildOrderWhatsAppMessage(
          storeName: 'Fresh India Organics',
          customerName: 'Rami',
          driverName: 'Joe',
          orderNumber: '2672',
          price: 45,
        );

    test('carries both languages in one message', () {
      final message = cod();

      expect(message, contains('Please send me your location'));
      expect(message, contains('الرجاء إرسال موقعك'));
    });

    test('names the store, driver, customer, order and price in both blocks', () {
      final message = cod();

      expect('Fresh India Organics'.allMatches(message).length, 2);
      expect('Joe'.allMatches(message).length, 2);
      expect('2672'.allMatches(message).length, 2);
      expect('45'.allMatches(message).length, 2);
      expect(message, contains('Hi Rami!'));
      expect(message, contains('مرحبا ${lrm}Rami$lrm!'));
    });

    test('asks a cash order for cash', () {
      final message = cod();

      expect(message, contains('\$45 (cash on delivery)'));
      expect(message, contains('(نقداً عند الاستلام)'));
    });

    // A prepaid customer has already paid online; asking them for cash at the
    // door would be collecting the same money twice.
    test('tells a prepaid order it is already paid', () {
      final message = buildOrderWhatsAppMessage(
        storeName: 'Fresh India Organics',
        customerName: 'Rami',
        driverName: 'Joe',
        orderNumber: '2672',
        price: 45,
        isPrepaid: true,
      );

      expect(message, contains('already paid'));
      expect(message, contains('مدفوع مسبقاً'));
      expect(message, isNot(contains('cash on delivery')));
      expect(message, isNot(contains('نقداً عند الاستلام')));
    });

    test('fences Latin runs inside the Arabic block against bidi reordering', () {
      final message = cod();

      expect(message, contains('${lrm}#2672$lrm'));
      expect(message, contains('$lrm\$45$lrm'));
      expect(message, contains('${lrm}Joe$lrm'));
      expect(message, contains('${lrm}Fresh India Organics$lrm'));
    });

    group('fallbacks', () {
      // What an app running against a backend that predates the store join
      // produces: still a usable message, just without the shop.
      test('drops the shop when the store name is unknown', () {
        final message = buildOrderWhatsAppMessage(
          customerName: 'Rami',
          driverName: 'Joe',
          orderNumber: '2672',
          price: 45,
        );

        expect(message, contains('This is Joe, delivering your order.'));
        expect(message, contains('أنا ${lrm}Joe$lrm، أوصل لك طلبك.'));
        expect(message, isNot(contains('from')));
      });

      test('drops the driver name when the profile has not loaded', () {
        final message = buildOrderWhatsAppMessage(
          storeName: 'Fresh India Organics',
          customerName: 'Rami',
          orderNumber: '2672',
          price: 45,
        );

        expect(message, contains('Your driver here, delivering your order from'));
        expect(message, contains('معك سائق التوصيل، أوصل لك طلبك من'));
      });

      test('greets without a name when the order carries none', () {
        final message = buildOrderWhatsAppMessage(
          storeName: 'Fresh India Organics',
          driverName: 'Joe',
          orderNumber: '2672',
          price: 45,
        );

        expect(message, contains('Hi! 👋'));
        expect(message, contains('مرحبا! 👋'));
      });

      test('omits the order number when there is none', () {
        final message = buildOrderWhatsAppMessage(
          storeName: 'Fresh India Organics',
          customerName: 'Rami',
          driverName: 'Joe',
          price: 45,
        );

        expect(message, isNot(contains('#')));
        expect(message, contains('\$45 (cash on delivery)'));
      });

      // Quoting '$0' to a customer is worse than saying nothing about money.
      test('omits price and payment wording when the total is zero', () {
        final message = buildOrderWhatsAppMessage(
          storeName: 'Fresh India Organics',
          customerName: 'Rami',
          driverName: 'Joe',
          orderNumber: '2672',
        );

        expect(message, isNot(contains('\$')));
        expect(message, isNot(contains('cash on delivery')));
        expect(message, contains('Order #2672'));
        expect(message, contains('الطلب ${lrm}#2672$lrm'));
      });

      test('drops the whole order line when neither number nor price is known', () {
        final message = buildOrderWhatsAppMessage(
          storeName: 'Fresh India Organics',
          customerName: 'Rami',
          driverName: 'Joe',
        );

        expect(message, isNot(contains('Order')));
        expect(message, isNot(contains('الطلب')));
        expect(message, contains('Please send me your location'));
      });
    });
  });

  group('OrderModel.storeName', () {
    OrderModel parse(Map<String, dynamic> extra) =>
        OrderModel.fromBackend({'id': 1, 'total_price': '45', ...extra});

    test('prefers the store name the merchant set in Shopify', () {
      expect(
        parse({
          'store_name': 'Fresh India Organics',
          'shop_domain': 'fresh-india.myshopify.com',
        }).storeName,
        'Fresh India Organics',
      );
    });

    test('falls back to the shop domain without the myshopify suffix', () {
      expect(
        parse({'shop_domain': 'fresh-india.myshopify.com'}).storeName,
        'fresh-india',
      );
    });

    test('keeps a custom domain intact', () {
      expect(parse({'shop_domain': 'freshindia.com'}).storeName, 'freshindia.com');
    });

    // A backend that does not send the store join at all.
    test('is empty when the backend sends neither field', () {
      expect(parse({}).storeName, '');
    });
  });

  group('OrderModel.orderNumber', () {
    test('keeps the bare number alongside the display label', () {
      final order = OrderModel.fromBackend({
        'id': 1,
        'order_number': '#2672',
        'total_price': '45',
      });

      expect(order.orderNumber, '2672');
      expect(order.item, 'Order #2672');
    });

    test('is empty when the order has no number at all', () {
      expect(OrderModel.fromBackend({'id': 1}).orderNumber, '');
    });
  });
}
