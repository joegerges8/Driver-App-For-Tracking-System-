import 'package:delivery_boy_app/utils/earnings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('driverPayFor', () {
    test('pays nothing before the first delivery', () {
      expect(driverPayFor(0), 0);
    });

    test('pays the flat fee for one delivery', () {
      expect(driverPayFor(1), driverFeePerDelivery);
    });

    // The whole point of the figure: the store owner reads it to know what to
    // hand over, so it has to be the fee times the deliveries and nothing else
    // — no rounding, no relation to the order values the driver collected.
    test('scales with the number of deliveries', () {
      expect(driverPayFor(7), 7 * driverFeePerDelivery);
    });
  });
}
