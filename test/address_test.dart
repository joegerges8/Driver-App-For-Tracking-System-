// The address line as it is printed on a card.
//
// The cases pinned here are real orders that read badly before the rule
// existed — the town written into the address and then again into Shopify's
// city field, arriving as 'Fraikeh, Friekeh valley residence, house nb 4,
// Fraikeh'. Each shape of that repetition is kept below, alongside the
// addresses that must keep their town because they never name it.

import 'package:delivery_boy_app/utils/address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildDeliveryAddress', () {
    test('appends the town to an address that does not name it', () {
      expect(
        buildDeliveryAddress('Hobeika street', 'Hazmieh'),
        'Hobeika street, Hazmieh',
      );
    });

    test('drops a town the address opens with', () {
      // Order #2686: address1 'Ashkout', address2 'House No. 280 Street No.7,,'
      expect(
        buildDeliveryAddress('Ashkout, House No. 280 Street No.7,,', 'Ashkout'),
        'Ashkout, House No. 280 Street No.7,,',
      );
    });

    test('drops a town repeated at the end of the address', () {
      expect(
        buildDeliveryAddress(
          'Fraikeh, Friekeh valley residence, house nb 4',
          'Fraikeh',
        ),
        'Fraikeh, Friekeh valley residence, house nb 4',
      );
    });

    test('drops a town written as one slash-separated part', () {
      // Order #2719, where the town is the first of four parts rather than a
      // field of its own.
      expect(
        buildDeliveryAddress(
          'Beirut/ Ras Nab3/ Muhammad Hout Street/ Olive Garden Building',
          'Beirut',
        ),
        'Beirut/ Ras Nab3/ Muhammad Hout Street/ Olive Garden Building',
      );
    });

    test('matches a town however it was capitalised or punctuated', () {
      expect(
        buildDeliveryAddress('ashkout , House No. 280', 'Ashkout'),
        'ashkout , House No. 280',
      );
    });

    test('keeps a town the address only mentions inside a longer part', () {
      // 'Beirut street' is a street, not the town of Beirut: the segment has
      // to match the town whole, or an address in Jounieh loses the only word
      // saying which town the driver is going to.
      expect(
        buildDeliveryAddress('Beirut street, building 4', 'Jounieh'),
        'Beirut street, building 4, Jounieh',
      );
    });

    test('keeps a town whose name merely starts the same way', () {
      expect(
        buildDeliveryAddress('Hazmieh el Kadime, near the church', 'Hazmieh'),
        'Hazmieh el Kadime, near the church, Hazmieh',
      );
    });

    test('is the address alone when the backend sent no town', () {
      expect(
        buildDeliveryAddress('Hobeika street', ''),
        'Hobeika street',
      );
    });

    test('is the town alone when the backend sent no address', () {
      expect(buildDeliveryAddress('', 'Hazmieh'), 'Hazmieh');
    });

    test('is empty when the backend sent neither', () {
      expect(buildDeliveryAddress('', ''), '');
    });

    test('ignores a town that is punctuation only', () {
      expect(buildDeliveryAddress('Hobeika street', '-'), 'Hobeika street');
    });

    test('trims the parts it is given', () {
      expect(
        buildDeliveryAddress('  Hobeika street  ', '  Hazmieh  '),
        'Hobeika street, Hazmieh',
      );
    });
  });
}
