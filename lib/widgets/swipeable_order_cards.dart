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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Keep the page index in bounds after an order is dismissed.
  void _clampPage(int orderCount) {
    if (orderCount == 0 || _currentPage < orderCount) return;
    final target = orderCount - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pageController.jumpToPage(target);
      setState(() => _currentPage = target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<DeliveryProvider>().orders;
    if (orders.isEmpty) return const SizedBox.shrink();

    _clampPage(orders.length);

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
          // Swipeable order pages
          SizedBox(
            height: 310,
            child: PageView.builder(
              controller: _pageController,
              itemCount: orders.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) =>
                  OrderCard(order: orders[index]),
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
