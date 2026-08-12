// Searching the orders list by the customer's phone number, or by the order
// number.
//
// The rule these lock down is the one a driver assumes without being told: what
// they type is the number they were read over the phone, and everything around
// it — the '#', a stray space, the '+961' one store saved and another did not,
// the case of a store prefix — is decoration the app deals with rather than
// something the driver has to get right.

import 'package:delivery_boy_app/utils/order_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeOrderQuery', () {
    test('drops the # the driver should not have to type', () {
      expect(normalizeOrderQuery('#2693'), '2693');
    });

    test('drops spaces around and inside the number', () {
      expect(normalizeOrderQuery(' 26 93 '), '2693');
    });

    test('lowercases a store prefix so case never decides a match', () {
      expect(normalizeOrderQuery('EN2693'), 'en2693');
    });

    // The screen reads an empty result as "no search is running" and shows the
    // full list, so a field holding only punctuation must not narrow anything.
    test('is empty for text with nothing to match on', () {
      expect(normalizeOrderQuery(''), '');
      expect(normalizeOrderQuery('#'), '');
      expect(normalizeOrderQuery('   '), '');
    });
  });

  group('normalizePhone', () {
    // The point of the whole exercise: the same line saved four ways by four
    // stores has to come out as one string.
    test('reduces every way a number is written to the same digits', () {
      expect(normalizePhone('+96170218542'), '70218542');
      expect(normalizePhone('+961 70 218 542'), '70218542');
      expect(normalizePhone('0096170218542'), '70218542');
      expect(normalizePhone('96170218542'), '70218542');
      expect(normalizePhone('70218542'), '70218542');
    });

    test('drops the trunk zero the local form carries', () {
      expect(normalizePhone('03123456'), '3123456');
      expect(normalizePhone('+96103123456'), '3123456');
      expect(normalizePhone('03 123 456'), '3123456');
    });

    test('drops dashes, brackets and other formatting', () {
      expect(normalizePhone('(+961) 70-218-542'), '70218542');
    });

    // A driver part-way through '+961...' has not typed a search yet, and the
    // screen must not empty the list under them.
    test('is empty for a country code on its own', () {
      expect(normalizePhone('+961'), '');
      expect(normalizePhone('00961'), '');
      expect(normalizePhone('+'), '');
      expect(normalizePhone(''), '');
    });
  });

  group('phoneMatches', () {
    // The behaviour the driver was promised: type the number, no +961.
    test('finds a stored +961 number typed without the country code', () {
      expect(phoneMatches('+96170218542', '70218542'), isTrue);
      expect(phoneMatches('+961 70 218 542', '70218542'), isTrue);
    });

    test('finds a bare stored number typed with the country code', () {
      expect(phoneMatches('70218542', '+96170218542'), isTrue);
      expect(phoneMatches('71107802', '0096171107802'), isTrue);
    });

    test('finds a number stored either way, typed either way', () {
      expect(phoneMatches('+96103123456', '03123456'), isTrue);
      expect(phoneMatches('03123456', '+96103123456'), isTrue);
      expect(phoneMatches('71107802', '71107802'), isTrue);
    });

    test('narrows as the driver types', () {
      expect(phoneMatches('+96170218542', '7'), isTrue);
      expect(phoneMatches('+96170218542', '702'), isTrue);
      expect(phoneMatches('+96170218542', '7021854'), isTrue);
    });

    // Half-remembered numbers are the reason for matching on any part rather
    // than only the start: "the one ending in 542" is a real thing to say.
    test('matches the tail of a number, not only its start', () {
      expect(phoneMatches('+96170218542', '542'), isTrue);
    });

    test('does not match a different customer', () {
      expect(phoneMatches('+96170218542', '71107802'), isFalse);
      expect(phoneMatches('71107802', '70218542'), isFalse);
    });

    // Both of these mean "show the whole list", and the screen relies on the
    // list not being filtered down to nothing behind that.
    test('matches nothing for a query with no digits to match on', () {
      expect(phoneMatches('+96170218542', ''), isFalse);
      expect(phoneMatches('+96170218542', '+961'), isFalse);
      expect(phoneMatches('+96170218542', '+'), isFalse);
    });

    // An order the backend sent without a phone cannot be meant by anything
    // the driver typed, so it must not surface as a false hit.
    test('never matches an order that has no phone', () {
      expect(phoneMatches('', '70218542'), isFalse);
      expect(phoneMatches('', ''), isFalse);
    });
  });

  group('orderNumberMatches', () {
    test('finds the order by its bare number', () {
      expect(orderNumberMatches('2693', '2693'), isTrue);
    });

    test('finds it whether or not either side carries a #', () {
      expect(orderNumberMatches('2693', '#2693'), isTrue);
      expect(orderNumberMatches('#2693', '2693'), isTrue);
      expect(orderNumberMatches('#2693', '#2693'), isTrue);
    });

    test('narrows as the driver types', () {
      expect(orderNumberMatches('2693', '2'), isTrue);
      expect(orderNumberMatches('2693', '26'), isTrue);
      expect(orderNumberMatches('2693', '269'), isTrue);
    });

    test('matches the tail of a number, not only its start', () {
      expect(orderNumberMatches('2693', '93'), isTrue);
    });

    test('finds a prefixed order number by its digits alone', () {
      expect(orderNumberMatches('EN2693', '2693'), isTrue);
      expect(orderNumberMatches('EN2693', 'en2693'), isTrue);
      expect(orderNumberMatches('EN2693', 'EN2693'), isTrue);
    });

    test('does not match a different order', () {
      expect(orderNumberMatches('2693', '2694'), isFalse);
      expect(orderNumberMatches('2693', '12693'), isFalse);
    });

    test('matches nothing for a query with nothing in it', () {
      expect(orderNumberMatches('2693', ''), isFalse);
      expect(orderNumberMatches('2693', '#'), isFalse);
    });

    test('never matches an order that has no number', () {
      expect(orderNumberMatches('', '2693'), isFalse);
      expect(orderNumberMatches('', ''), isFalse);
    });
  });

  group('orderMatchesSearch', () {
    test('finds the order by the customer phone', () {
      expect(
        orderMatchesSearch(
          phone: '+96170218542',
          orderNumber: '2689',
          query: '70218542',
        ),
        isTrue,
      );
    });

    // The label in the driver's hand still carries an order number, and one
    // field has to answer both.
    test('still finds the order by its number', () {
      expect(
        orderMatchesSearch(
          phone: '+96170218542',
          orderNumber: '2689',
          query: '#2689',
        ),
        isTrue,
      );
    });

    test('does not match an order that answers to neither', () {
      expect(
        orderMatchesSearch(
          phone: '+96170218542',
          orderNumber: '2689',
          query: '71107802',
        ),
        isFalse,
      );
    });
  });

  group('isSearchActive', () {
    test('is on as soon as there is a digit worth matching', () {
      expect(isSearchActive('7'), isTrue);
      expect(isSearchActive('70218542'), isTrue);
      expect(isSearchActive('#2689'), isTrue);
    });

    // Everything here is a field the driver is still in the middle of, and the
    // list stays whole rather than emptying out under them.
    test('is off for text carrying nothing to match on yet', () {
      expect(isSearchActive(''), isFalse);
      expect(isSearchActive('   '), isFalse);
      expect(isSearchActive('#'), isFalse);
      expect(isSearchActive('+'), isFalse);
      expect(isSearchActive('+961'), isFalse);
    });
  });
}
