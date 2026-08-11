// Searching the orders list by order number.
//
// The rule these lock down is the one a driver assumes without being told: what
// they type is the number they were read over the phone, and everything around
// it — the '#', a stray space, the case of a store prefix — is decoration the
// app deals with rather than something the driver has to get right.

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

    // Half-remembered numbers are the reason for matching on any part rather
    // than only the start: "the one ending in 93" is a real thing a dispatcher
    // says.
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

    // Both of these mean "show the whole list", and the screen relies on the
    // list not being filtered down to nothing behind that.
    test('matches nothing for a query with nothing in it', () {
      expect(orderNumberMatches('2693', ''), isFalse);
      expect(orderNumberMatches('2693', '#'), isFalse);
    });

    // An order the backend sent without a number cannot be meant by anything
    // the driver typed, so it must not surface as a false hit.
    test('never matches an order that has no number', () {
      expect(orderNumberMatches('', '2693'), isFalse);
      expect(orderNumberMatches('', ''), isFalse);
    });
  });
}
