import 'dart:math' as math;

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/provider/order_focus_controller.dart';
import 'package:delivery_boy_app/widgets/order_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A first guess at what one order card needs, in logical pixels, used for the
/// single frame before the real card has been laid out and measured.
///
/// Fitted to cards rendered at font scales from 1.0 to 1.5: a fixed part that
/// does not scale (the thumbnail, the paddings, the button's own padding) and a
/// part that grows with the text. It only has to be close — [_cardHeight]
/// replaces it with the height the card actually came out to on this device,
/// which is the number that matters and which no formula can know, since the
/// font a phone renders Arabic or English in is not the font a test binding
/// measures.
double estimatedOrderCardHeight(double textScale) => 161 + 106 * textScale;

/// The most of the screen the cards may take, leaving the rest to the map.
///
/// The cards are the driver's controls and the map is what they are reading, so
/// on a short phone at a large font scale the cards give way first: the card
/// scrolls inside its own page rather than pushing the map off the screen.
const double kMaxCardScreenFraction = 0.55;

/// The height of one page of the swipeable order cards.
///
/// [measuredHeight] is what the card laid out to, once it has; null before the
/// first frame, where the estimate stands in.
double orderCardPageHeight({
  required double textScale,
  required double screenHeight,
  double? measuredHeight,
}) =>
    math.min(
      measuredHeight ?? estimatedOrderCardHeight(textScale),
      screenHeight * kMaxCardScreenFraction,
    );

/// How the cards settle after a swipe.
///
/// PageView's default spring is tuned for full-screen pages and takes a
/// noticeable moment to settle a short one like these, which is most of what
/// made swiping between orders feel slow: the finger had long since finished
/// and the card was still gliding into place. This one is stiffer and critically
/// damped — it arrives quickly and does not wobble when it gets there — and it
/// takes less of a flick to count as a fling, so a small flick moves a card
/// instead of sagging back.
class SnappyPageScrollPhysics extends ScrollPhysics {
  const SnappyPageScrollPhysics({super.parent});

  @override
  SnappyPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      SnappyPageScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.3,
        stiffness: 240,
        ratio: 1.0,
      );

  @override
  double get minFlingVelocity => 30;
}

class SwipeableOrderCards extends StatefulWidget {
  const SwipeableOrderCards({super.key, this.focus});

  /// Pin taps from the map above. Null wherever the cards are shown without a
  /// map beside them.
  final OrderFocusController? focus;

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

  // What the card on screen actually laid out to, and the font scale it was
  // measured at.
  //
  // The page has to be given a height before its card exists — that is what
  // PageView requires — so the height used to be a constant with enough
  // headroom that no card could ever clip. The headroom was the problem: it
  // was about seventy pixels the card did not use, and a fixed box does not
  // shrink to its contents, so it showed up as a band of white below the
  // button and came out of the map above it.
  //
  // So the first frame uses the estimate, the card is measured once it has
  // been laid out, and the box is set to what it found. Every card has the
  // same structure and every line in it is capped at one line, so one
  // measurement describes all of them; it is retaken when the driver changes
  // their font scale, which is the only thing that changes the answer.
  double? _measuredCardHeight;
  double? _measuredAtTextScale;

  final GlobalKey _cardKey = GlobalKey();

  // The orders as of the last build, so a pin tap arriving between builds can
  // be turned into a page number without waiting for one.
  List<OrderModel> _orders = const [];

  @override
  void initState() {
    super.initState();
    widget.focus?.addListener(_onFocusRequested);
  }

  @override
  void didUpdateWidget(SwipeableOrderCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus) {
      oldWidget.focus?.removeListener(_onFocusRequested);
      widget.focus?.addListener(_onFocusRequested);
    }
  }

  @override
  void dispose() {
    widget.focus?.removeListener(_onFocusRequested);
    _pageController.dispose();
    super.dispose();
  }

  // A pin was tapped on the map: bring that order's card to the front.
  //
  // Animated rather than jumped so the driver can see which way the cards
  // moved and how far — a card that simply appeared would leave them unsure
  // whether they are looking at the order they tapped or the one they were on.
  //
  // Silently does nothing for an order with no card: a delivered order still
  // has a green pin on the map after it has left the assigned list.
  void _onFocusRequested() {
    final orderId = widget.focus?.orderId;
    if (orderId == null) return;

    final target = _orders.indexWhere((o) => o.id == orderId);
    if (target < 0 || target == _currentPage) return;
    if (!_pageController.hasClients) return;

    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  // Reads the laid-out card and, if it disagrees with the height the box is
  // using, adopts it.
  //
  // Runs after the frame because it is reading a size that layout has only just
  // produced, and setState during layout is not allowed. The half-pixel
  // threshold is what stops it from trading rounding error back and forth with
  // the layout forever.
  void _measureCard(double textScale) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;

      final height = box.size.height;
      if (height <= 0) return;
      if (_measuredAtTextScale == textScale &&
          _measuredCardHeight != null &&
          (_measuredCardHeight! - height).abs() < 0.5) {
        return;
      }

      setState(() {
        _measuredCardHeight = height;
        _measuredAtTextScale = textScale;
      });
    });
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

  // Height of one order page: what the card measured, or the estimate until it
  // has. Still capped at [kMaxCardScreenFraction] of the screen, and each card
  // still scrolls inside its own page, so a card too tall for the room costs a
  // scroll rather than an overflow banner.
  double _cardHeight(BuildContext context, double textScale) =>
      orderCardPageHeight(
        textScale: textScale,
        screenHeight: MediaQuery.sizeOf(context).height,
        measuredHeight: _measuredAtTextScale == textScale
            ? _measuredCardHeight
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<DeliveryProvider>().orders;
    if (orders.isEmpty) {
      _orders = orders;
      return const SizedBox.shrink();
    }

    _orders = orders;
    _syncPage(orders);

    final dotPage = _currentPage.clamp(0, orders.length - 1);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    _measureCard(textScale);

    final boxHeight = _cardHeight(context, textScale);
    // Whether the card fits the room it has been given. Unknown until the first
    // measurement, and assumed true until then: guessing wrong for one frame
    // costs a card that cannot be scrolled for that frame, and guessing the
    // other way would turn scrolling on for every card that never needs it.
    final cardFits =
        _measuredCardHeight == null || _measuredCardHeight! <= boxHeight + 0.5;

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
          // PageView needs a bounded height, so the box cannot simply shrink to
          // its card — it has to be told a number before the card exists. That
          // number was a constant with enough headroom for Arabic, whose glyphs
          // sit on a taller line box than English; the headroom is what showed
          // up as white space under the button. It is now the height the card
          // measured on this device (see _measureCard), which owes nothing to
          // an assumption about fonts.
          //
          // The two guards on it are unchanged: capped so the map keeps its
          // share of a short screen, and each card scrolls inside its own page,
          // so a card that wants more room than the cap allows is scrollable
          // rather than overflowing.
          SizedBox(
            height: boxHeight,
            // The cards repaint as they slide; the map behind them does not
            // need to. Without the boundary every swipe dirties the whole
            // screen underneath.
            child: RepaintBoundary(
              child: PageView.builder(
                controller: _pageController,
                // See SnappyPageScrollPhysics: the default spring is what made
                // a swipe feel like it was still finishing long after the
                // finger had left.
                physics: const SnappyPageScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                itemCount: orders.length,
                onPageChanged: (i) => setState(() {
                  _currentPage = i;
                  _currentOrderId = orders[i].id;
                }),
                itemBuilder: (context, index) => SingleChildScrollView(
                  // The scroll view is here to give the card an unbounded
                  // height to lay out into, which is what makes it measurable;
                  // scrolling is only a fallback for a card too tall for the
                  // room. When it fits — which is the normal case — its
                  // scrolling is turned off, so a swipe no longer has to be
                  // told apart from a vertical drag before it can start. That
                  // disambiguation was the other half of the sluggishness.
                  physics: cardFits
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  // The key rides the first page only: every card has the same
                  // structure and every line in it is capped at one line, so one
                  // measurement describes all of them, and a key that moved
                  // between pages as the driver swiped would remeasure the same
                  // height on every swipe.
                  child: OrderCard(
                    key: index == 0 ? _cardKey : null,
                    order: orders[index],
                  ),
                ),
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
