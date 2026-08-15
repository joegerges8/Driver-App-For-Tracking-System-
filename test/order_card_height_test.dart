// How tall the home screen gives one order card.
//
// The card sits in a fixed-height box because that is what PageView needs, so
// the number is a promise made in advance about content that has not been laid
// out yet, and it can be wrong in two directions:
//
//   * Too small and the card clips, or — since each page scrolls — the driver
//     has to scroll a card to reach the button on it.
//   * Too large and the surplus is a band of white below the button, taken off
//     the map above it. That is what 330 was doing: about seventy pixels of
//     nothing, on every card, at every font scale.
//
// The fix is to stop guessing: the widget lays the card out, measures it, and
// sizes the box to what it found. These tests render the real thing at each
// font scale a driver can set, in both languages, and check that the box the
// driver ends up looking at is the height of the card inside it — no clipping,
// and no band of white underneath.

import 'dart:async';
import 'dart:io';

import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/widgets/order_card.dart';
import 'package:delivery_boy_app/widgets/swipeable_order_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

// The card shows the product thumbnail with a NetworkImage. Test bindings fail
// every HTTP request with a 400, which surfaces as a test failure that has
// nothing to do with the layout being measured, so requests are served a 1x1
// transparent PNG instead.
class _FakeImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

const List<int> _transparentPixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();

  // Everything else the image loader touches — autoUncompress, timeouts — is
  // configuration this fake has no use for.
  @override
  noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();

  @override
  noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPixelPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_transparentPixelPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  noSuchMethod(Invocation invocation) => null;
}

// An order shaped like the ones a driver actually gets, with the longest text
// each slot realistically carries.
OrderModel _order({
  String id = '2719',
  String address = 'Beirut/ Ras Nab3/ Muhammad al Hout street, building 4',
}) =>
    OrderModel(
      id: id,
      customerName: 'Dana Mounla',
      customerPhone: '76424299',
      item: 'Order #$id',
      orderNumber: id,
      storeName: 'SonicBeat',
      price: 36,
      pickupLocation: const LatLng(0, 0),
      deliveryLocation: const LatLng(0, 0),
      pickupAddress: 'Current location',
      deliveryAddress: address,
    );

// A DeliveryProvider already holding orders, without going near the network:
// the widget reads its list and nothing else here.
class _StubDeliveryProvider extends DeliveryProvider {
  _StubDeliveryProvider(this._orders);
  final List<OrderModel> _orders;

  @override
  List<OrderModel> get orders => _orders;
}

// Pumps the real widget — cards, PageView, measurement and all — and settles
// the post-frame measurement so the box under test is the one the driver ends
// up looking at rather than the first-frame estimate.
Future<void> _pumpCards(
  WidgetTester tester, {
  required Locale locale,
  required double textScale,
  List<OrderModel>? orders,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<DeliveryProvider>(
      create: (_) => _StubDeliveryProvider(orders ?? [_order()]),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // copyWith rather than a fresh MediaQueryData: the widget reads the
        // screen height from here too, and a bare MediaQueryData would hand it
        // a zero-sized screen and collapse the box being measured.
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: const Scaffold(
              // Bottom-aligned, the way the home screen stacks them under the
              // map.
              body: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [SwipeableOrderCards()],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => HttpOverrides.global = _FakeImageHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  group('the card box', () {
    for (final locale in [const Locale('en'), const Locale('ar')]) {
      for (final textScale in [1.0, 1.15, 1.3, 1.5]) {
        testWidgets(
          'fits its ${locale.languageCode} card at font scale $textScale',
          (tester) async {
            await _pumpCards(tester, locale: locale, textScale: textScale);

            final box = tester.getSize(find.byType(PageView)).height;
            final card = tester.getSize(find.byType(OrderCard).first).height;

            expect(
              box,
              greaterThanOrEqualTo(card),
              reason: 'the card would clip, or have to be scrolled to reach '
                  'the button on it',
            );
            expect(
              box - card,
              lessThan(1),
              reason: 'dead space under the card, taken off the map',
            );
          },
        );
      }
    }

    testWidgets('leaves the map more than half the screen', (tester) async {
      await _pumpCards(tester, locale: const Locale('en'), textScale: 1.0);

      final screen = tester.getSize(find.byType(MaterialApp)).height;
      final cards = tester.getSize(find.byType(SwipeableOrderCards)).height;

      expect(cards, lessThan(screen * kMaxCardScreenFraction));
    });

    testWidgets('re-measures when the driver changes their font scale',
        (tester) async {
      await _pumpCards(tester, locale: const Locale('en'), textScale: 1.0);
      final small = tester.getSize(find.byType(PageView)).height;

      await _pumpCards(tester, locale: const Locale('en'), textScale: 1.5);
      final large = tester.getSize(find.byType(PageView)).height;

      expect(large, greaterThan(small));
      expect(
        large - tester.getSize(find.byType(OrderCard).first).height,
        lessThan(1),
        reason: 'a stale measurement would leave the old height behind',
      );
    });

    testWidgets('gives every card the same box, whichever is on screen',
        (tester) async {
      // The box is measured from the first page. Swiping to another order must
      // not leave that card clipped or floating in a box built for a different
      // one — which holds because every line on the card is capped at one line.
      await _pumpCards(
        tester,
        locale: const Locale('en'),
        textScale: 1.0,
        orders: [_order(), _order(id: '2720', address: 'Jounieh, Haret Sakher')],
      );

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      final box = tester.getSize(find.byType(PageView)).height;
      final card = tester.getSize(find.byType(OrderCard).first).height;

      expect(box - card, lessThan(1));
    });
  });

  group('orderCardPageHeight', () {
    test('never takes more than its share of a short screen', () {
      // A small device at a large font scale: the card wants more than the
      // screen can spare, and the cap is what stops the map being squeezed to
      // nothing. The card scrolls inside its page instead.
      final height = orderCardPageHeight(
        textScale: 2.0,
        screenHeight: 600,
        measuredHeight: 420,
      );

      expect(height, 600 * kMaxCardScreenFraction);
    });

    test('uses the estimate only until a real measurement arrives', () {
      const screenHeight = 900.0;
      final estimated = orderCardPageHeight(
        textScale: 1.0,
        screenHeight: screenHeight,
      );
      final measured = orderCardPageHeight(
        textScale: 1.0,
        screenHeight: screenHeight,
        measuredHeight: 250,
      );

      expect(estimated, estimatedOrderCardHeight(1.0));
      expect(measured, 250);
    });

    test('estimates a taller card at a larger font scale', () {
      expect(
        estimatedOrderCardHeight(1.4),
        greaterThan(estimatedOrderCardHeight(1.0)),
      );
    });
  });
}
