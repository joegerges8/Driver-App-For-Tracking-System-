// Tapping a pin on the map brings that order's card to the front.
//
// The home screen shows the same run twice — pins above, cards below — and the
// two halves used to be strangers. A driver could see a pin somewhere awkward
// and have no way to learn which order it was except swiping the cards and
// reading addresses off them. These tests lock down the link: the pin the
// driver taps and the card they then act on are the same order.

import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/provider/order_focus_controller.dart';
import 'package:delivery_boy_app/utils/order_pins.dart';
import 'package:delivery_boy_app/widgets/swipeable_order_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'support/fake_network_images.dart';

const LatLng _jounieh = LatLng(33.9808, 35.6178);

OrderModel _order(String id, {LatLng? city = _jounieh}) => OrderModel(
      id: id,
      customerName: 'Customer $id',
      customerPhone: '70218542',
      item: 'Order #$id',
      orderNumber: id,
      storeName: 'SonicBeat',
      price: 22,
      pickupLocation: const LatLng(0, 0),
      deliveryLocation: const LatLng(0, 0),
      cityLocation: city,
      pickupAddress: 'Current location',
      deliveryAddress: 'Address for $id',
    );

class _StubDeliveryProvider extends DeliveryProvider {
  _StubDeliveryProvider(this._orders);
  final List<OrderModel> _orders;

  @override
  List<OrderModel> get orders => _orders;
}

Future<void> _pumpCards(
  WidgetTester tester, {
  required List<OrderModel> orders,
  required OrderFocusController focus,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<DeliveryProvider>(
      create: (_) => _StubDeliveryProvider(orders),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [SwipeableOrderCards(focus: focus)],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Which order's card is in front of the driver, read off the screen the way
// they read it.
String _visibleOrderNumber(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.startsWith('Order #'));
  return texts.first;
}

void main() {
  useFakeNetworkImages();

  group('OrderFocusController', () {
    test('carries the order that was asked for', () {
      final focus = OrderFocusController();
      addTearDown(focus.dispose);

      expect(focus.orderId, isNull);
      focus.focus('2719');
      expect(focus.orderId, '2719');
    });

    test('notifies again when the same order is asked for twice', () {
      // The driver taps a pin, swipes away to read another card, then taps the
      // first pin again. A controller that only spoke up on a change of value
      // would sit silent the second time and the card would never come back.
      final focus = OrderFocusController();
      addTearDown(focus.dispose);

      var notifications = 0;
      focus.addListener(() => notifications++);

      focus.focus('2719');
      focus.focus('2719');

      expect(notifications, 2);
    });
  });

  group('pins', () {
    test('hand the tapped order back to whoever is listening', () {
      final tapped = <String>[];
      final markers = buildOrderMarkers(
        pending: [_order('1'), _order('2')],
        delivered: const [],
        onTap: tapped.add,
      );

      for (final marker in markers) {
        marker.onTap!();
      }

      expect(tapped, containsAll(['1', '2']));
    });

    test('carry no tap handler when nobody is listening', () {
      final markers = buildOrderMarkers(
        pending: [_order('1')],
        delivered: const [],
      );

      expect(markers.single.onTap, isNull);
    });
  });

  group('tapping a pin', () {
    testWidgets('brings that order to the front of the cards', (tester) async {
      final focus = OrderFocusController();
      addTearDown(focus.dispose);

      await _pumpCards(
        tester,
        orders: [_order('2718'), _order('2719'), _order('2720')],
        focus: focus,
      );
      expect(_visibleOrderNumber(tester), 'Order #2718');

      focus.focus('2720');
      await tester.pumpAndSettle();

      expect(_visibleOrderNumber(tester), 'Order #2720');
    });

    testWidgets('brings it back after the driver has swiped away',
        (tester) async {
      final focus = OrderFocusController();
      addTearDown(focus.dispose);

      await _pumpCards(
        tester,
        orders: [_order('2718'), _order('2719')],
        focus: focus,
      );

      focus.focus('2719');
      await tester.pumpAndSettle();
      expect(_visibleOrderNumber(tester), 'Order #2719');

      await tester.drag(find.byType(PageView), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(_visibleOrderNumber(tester), 'Order #2718');

      // The same pin again — the repeat is the case that matters.
      focus.focus('2719');
      await tester.pumpAndSettle();
      expect(_visibleOrderNumber(tester), 'Order #2719');
    });

    testWidgets('does nothing for an order with no card', (tester) async {
      // A delivered order keeps its green pin after it has left the assigned
      // list, so a tap can name an order the cards do not have.
      final focus = OrderFocusController();
      addTearDown(focus.dispose);

      await _pumpCards(
        tester,
        orders: [_order('2718'), _order('2719')],
        focus: focus,
      );

      focus.focus('9999');
      await tester.pumpAndSettle();

      expect(_visibleOrderNumber(tester), 'Order #2718');
    });
  });

  group('swiping', () {
    testWidgets('settles on the next card quickly after a flick',
        (tester) async {
      // The complaint this answers: a swipe kept gliding long after the finger
      // had left. PageView's default spring took 800ms to hand over the card;
      // the stiffer one in SnappyPageScrollPhysics takes about 330ms. The
      // threshold sits between the two, so putting the old spring back fails
      // here rather than quietly feeling slow again.
      await _pumpCards(
        tester,
        orders: [_order('2718'), _order('2719')],
        focus: OrderFocusController(),
      );

      await tester.fling(find.byType(PageView), const Offset(-120, 0), 800);
      await tester.pump();

      var settledAfter = Duration.zero;
      const step = Duration(milliseconds: 10);
      while (settledAfter < const Duration(seconds: 2)) {
        await tester.pump(step);
        settledAfter += step;
        if (_visibleOrderNumber(tester) == 'Order #2719') break;
      }
      await tester.pumpAndSettle();

      expect(_visibleOrderNumber(tester), 'Order #2719');
      expect(settledAfter, lessThan(const Duration(milliseconds: 500)));
    });

    testWidgets('does not make the driver fight a vertical scroll',
        (tester) async {
      // Each card sits in a scroll view, which is what lets it be measured. It
      // only needs to scroll when the card does not fit, and when it does fit
      // its scrolling is off — otherwise every horizontal swipe has to be told
      // apart from a vertical drag before it can start.
      await _pumpCards(
        tester,
        orders: [_order('2718'), _order('2719')],
        focus: OrderFocusController(),
      );

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );

      expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
    });
  });
}
