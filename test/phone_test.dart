// The two shapes a customer phone number is needed in: one to compare, one to
// read off an order card.
//
// What these lock down is that neither shape ever loses a number. The driver
// dials the raw column, so trimming the country code off the card is purely
// how it reads — and anything the rules do not recognise is shown as it
// arrived rather than blanked out.

import 'package:delivery_boy_app/utils/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  group('displayPhone', () {
    test('takes the country code off, however it was written', () {
      expect(displayPhone('+96170218542'), '70218542');
      expect(displayPhone('+961 70 218 542'), '70218542');
      expect(displayPhone('0096170218542'), '70218542');
      expect(displayPhone('96170218542'), '70218542');
    });

    // A seven-digit national number is an 03 mobile or an 01 landline, and
    // that is not how anyone reads it out.
    test('puts the trunk zero back on a seven-digit number', () {
      expect(displayPhone('+9613719871'), '03719871');
      expect(displayPhone('+9611234567'), '01234567');
    });

    // Already short: the store's own spacing is left alone rather than tidied.
    test('passes through a number that carries no country code', () {
      expect(displayPhone('70218542'), '70218542');
      expect(displayPhone('03 719 871'), '03 719 871');
      expect(displayPhone('  71107802  '), '71107802');
    });

    // Blanking a number the rules do not understand would leave the driver
    // with no way to reach the customer from the card at all.
    test('shows anything it cannot shorten exactly as it arrived', () {
      expect(displayPhone('+961'), '+961');
      expect(displayPhone('call the shop'), 'call the shop');
    });

    test('is empty only for an empty column', () {
      expect(displayPhone(''), '');
      expect(displayPhone('   '), '');
    });
  });
}
