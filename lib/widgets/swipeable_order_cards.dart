import 'dart:math' as math;

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/widgets/order_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SwipeableOrderCards extends StatefulWidget {
  const SwipeableOrderCards({super.key});

  @override
  State<SwipeableOrderCards> createState() => _SwipeableOrderCardsState();
}

class _SwipeableOrderCardsState extends State<SwipeableOrderCards> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // The order the driver is currently looking at, remembered by id rather than
  // by page number. The list is not fixed: orders under way are lifted to the
  // front of it (see sortActiveFirst), so the order sitting at page 3 before a
  // delivery is started is not the one sitting there after. Following the id
  // keeps the card in front of the driver showing the same order it did a
  // moment ago instead of quietly swapping in someone else's address.
  String? _currentOrderId;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Keeps the visible page pointing at the order the driver was reading, after
  // the list has been reordered or an order has left it.
  void _syncPage(List<OrderModel> orders) {
    if (orders.isEmpty) return;

    final id = _currentOrderId;
    final moved = id == null ? -1 : orders.indexWhere((o) => o.id == id);

    // An order that is gone — delivered, returned, or taken back by the
    // dispatcher — leaves the page number to fall back on, clamped into range.
    final target = moved >= 0
        ? moved
        : _currentPage.clamp(0, orders.length - 1);

    if (target == _currentPage) {
      // Nothing to move; just remember what is on screen, which is all the
      // memo is. Assigning during build is safe because nothing renders it.
      _currentOrderId = orders[target].id;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The controller only drives a PageView that is actually on screen; the
      // list can be reordered by the background poll while the driver is on
      // another tab, and jumping a controller with no view attached throws.
      if (_pageController.hasClients) _pageController.jumpToPage(target);
      setState(() {
        _currentPage = target;
        _currentOrderId = orders[target].id;
      });
    });
  }

  // Height of one order page. 330 is the English layout plus the headroom
  // Arabic needs; it scales with the accessibility font setting and is capped
  // at 55% of the screen so the map above never collapses on short devices.
  double _cardHeight(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final screenHeight = MediaQuery.sizeOf(context).height;
    return math.min(330 * textScale, screenHeight * 0.55);
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<DeliveryProvider>().orders;
    if (orders.isEmpty) return const SizedBox.shrink();

    _syncPage(orders);

    final dotPage = _currentPage.clamp(0, orders.length - 1);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Swipeable order pages.
          //
          // PageView needs a bounded height, and the old fixed 310 was tuned
          // against English text: Arabic glyphs sit on a taller line box, which
          // pushed the card a few pixels past the edge and produced the striped
          // overflow banner. Two changes make that impossible to hit again:
          // the box now grows with the driver's system font scale (capped so
          // the map keeps at least half the screen), and each card scrolls
          // inside its own page as a last resort, so a long translation or a
          // long address can never overflow the layout.
          SizedBox(
            height: _cardHeight(context),
            child: PageView.builder(
              controller: _pageController,
              itemCount: orders.length,
              onPageChanged: (i) => setState(() {
                _currentPage = i;
                _currentOrderId = orders[i].id;
              }),
              itemBuilder: (context, index) => SingleChildScrollView(
                child: OrderCard(order: orders[index]),
              ),
            ),
          ),
          // Page indicator dots — only shown when there are multiple orders
          if (orders.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(orders.length, (i) {
                  final active = i == dotPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: active ? Colors.red : Colors.grey[300],
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
