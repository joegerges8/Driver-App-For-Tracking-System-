// orders_screen.dart
//
// This screen is the "Orders" tab in the driver app's bottom navigation bar.
// It was redesigned from a plain list to a tabbed, card-based interface with
// the following improvements:
//
//  1. Tab bar       — four filter tabs: All, Pending, Active, Done.
//  2. Earnings strip— a red banner that shows total earnings and completed
//                     order count, calculated from the Done tab's data.
//  3. Card layout   — each order is shown as an elevated card instead of a
//                     plain ListTile, with pickup/delivery addresses and a
//                     colour-coded status badge (orange = Pending, green = Active).
//  4. Swipe-to-dismiss — the driver can swipe a pending order left to remove it.
//  5. Skeleton loading — pulsing grey placeholder cards are shown while data
//                     loads, instead of a plain spinner.
//  6. Empty states  — each tab shows a context-aware icon and message when empty.
//  7. Done tab      — read-only green cards for completed deliveries, loaded
//                     lazily when the driver first opens that tab.

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/order_detail_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

// SingleTickerProviderStateMixin is required by TabController so that
// the tab animation has a valid vsync (animation tick source).
class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  // Tracks which token was last used to fetch orders, so we only call the
  // API once per session rather than on every widget rebuild.
  String? _lastFetchToken;

  // Controls the four tabs: All, Pending, Active, Done.
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Listen for tab changes so we can lazily load completed orders only
    // when the driver actually opens the Done tab.
    _tabController.addListener(_onTabChanged);

    // Schedule the first data fetch after the first frame so that the
    // BuildContext (needed to read providers) is fully available.
    Future.microtask(_maybeFetch);
  }

  @override
  void dispose() {
    // Always remove listeners and dispose controllers to prevent memory leaks.
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // Called every time the selected tab changes.
  // We only fetch completed orders when the Done tab (index 3) is opened,
  // and only when the tab has finished animating (indexIsChanging == false).
  // This is called "lazy loading" — we avoid an unnecessary API call until
  // the data is actually needed.
  void _onTabChanged() {
    if (_tabController.index == 3 && !_tabController.indexIsChanging) {
      final token = context.read<AuthProvider>().token;
      if (token != null && token.isNotEmpty) {
        context.read<DeliveryProvider>().refreshCompletedOrders(token: token);
      }
    }
  }

  // Fetches the list of assigned (pending) orders from the backend.
  // The guard on _lastFetchToken ensures we only call the API once per
  // login session, not on every hot-reload or widget rebuild.
  void _maybeFetch() {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;
    if (_lastFetchToken == token) return;
    _lastFetchToken = token;
    context.read<DeliveryProvider>().refreshMyOrders(token: token);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Called when an inherited widget (like AuthProvider) changes — handles
    // the case where the token is restored from storage after initState runs.
    Future.microtask(_maybeFetch);
  }

  @override
  Widget build(BuildContext context) {
    // context.watch rebuilds this widget automatically whenever DeliveryProvider
    // calls notifyListeners() (e.g. after a fetch completes).
    final delivery = context.watch<DeliveryProvider>();

    // Determine whether there is currently an order being actively delivered.
    // An "active" delivery is one that has been accepted but not yet finished.
    final isActive = delivery.currentOrder != null &&
        delivery.status != DeliveryStatus.waitingForAcceptance &&
        delivery.status != DeliveryStatus.delivered &&
        delivery.status != DeliveryStatus.rejected;

    // Pending tab: all orders except the one currently being delivered.
    final pendingOrders = delivery.orders
        .where((o) => !(isActive && o.id == delivery.currentOrder!.id))
        .toList();

    // Active tab: at most one order — the one currently being delivered.
    final activeOrders = isActive ? [delivery.currentOrder!] : <OrderModel>[];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'My Orders',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        // TabBar is placed inside the AppBar's bottom slot so it sits
        // directly below the title, which is standard Material design.
        // isScrollable: true allows each tab to use its natural text width,
        // preventing labels from being clipped when there are four tabs.
        bottom: TabBar(
          controller: _tabController,
          labelColor: buttonMainColor,
          unselectedLabelColor: Colors.black45,
          indicatorColor: buttonMainColor,
          indicatorWeight: 3,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'All (${delivery.orders.length})'),
            Tab(text: 'Pending (${pendingOrders.length})'),
            Tab(text: 'Active (${activeOrders.length})'),
            Tab(text: 'Completed (${delivery.completedOrders.length})'),
          ],
        ),
      ),
      // RefreshIndicator wraps the body so the driver can pull down to
      // manually re-fetch orders at any time.
      body: RefreshIndicator(
        onRefresh: () async {
          final token = context.read<AuthProvider>().token;
          if (token != null && token.isNotEmpty) {
            await context
                .read<DeliveryProvider>()
                .refreshMyOrders(token: token);
          }
        },
        child: _buildBody(delivery, pendingOrders, activeOrders, isActive),
      ),
    );
  }

  // Decides what to show in the body based on the current loading/error state.
  Widget _buildBody(
    DeliveryProvider delivery,
    List<OrderModel> pendingOrders,
    List<OrderModel> activeOrders,
    bool isActive,
  ) {
    // Show skeleton cards while the initial fetch is in progress.
    if (delivery.isLoadingOrders) {
      return const _SkeletonList();
    }

    // Show the error message if the API call failed.
    final err = delivery.ordersError;
    if (err != null && err.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              err.replaceFirst('Exception: ', ''),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      );
    }

    // Main layout: earnings strip on top, then the four tab views below.
    return Column(
      children: [
        // Earnings strip reads from completedOrders so the figures only
        // reflect deliveries that have actually been completed.
        _EarningsSummaryStrip(
          completedOrders: delivery.completedOrders,
          isActive: isActive,
        ),
        Expanded(
          // TabBarView renders the content for whichever tab is selected.
          // It is linked to _tabController so swiping and tapping stay in sync.
          child: TabBarView(
            controller: _tabController,
            children: [
              // All tab — every assigned order.
              _OrderList(
                orders: delivery.orders,
                emptyMessage: 'No orders assigned yet',
              ),
              // Pending tab — orders not yet accepted.
              _OrderList(
                orders: pendingOrders,
                emptyMessage: 'No pending orders',
              ),
              // Active tab — the single order currently being delivered.
              _OrderList(
                orders: activeOrders,
                emptyMessage: 'No active delivery right now',
                isActiveTab: true,
              ),
              // Done tab — read-only cards for completed deliveries.
              _CompletedOrderList(delivery: delivery),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────── Earnings Summary Strip ───────────────────────────
//
// A red banner pinned above the tab views that shows:
//   - Total Earned: the sum of all completed orders' prices.
//   - Completed:    how many orders have been marked as delivered.
//   - "In Progress" pill: shown only when a delivery is currently active.
//
// The values are derived from completedOrders (fetched from the Done tab
// endpoint), so the strip accurately reflects real delivered orders rather
// than just assigned ones.

class _EarningsSummaryStrip extends StatelessWidget {
  final List<OrderModel> completedOrders;
  final bool isActive;

  const _EarningsSummaryStrip({required this.completedOrders, required this.isActive});

  @override
  Widget build(BuildContext context) {
    // Sum the price field across all completed orders.
    final total = completedOrders.fold<int>(0, (sum, o) => sum + o.price);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: buttonMainColor,
        boxShadow: [
          BoxShadow(
            color: buttonMainColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatColumn(label: 'Total Earned', value: '\$$total'),
          const Spacer(),
          _StatColumn(label: 'Completed', value: '${completedOrders.length}'),
          // The "In Progress" pill is conditionally shown only when the driver
          // has accepted an order and is currently on the way.
          if (isActive) ...[
            const SizedBox(width: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.local_shipping, color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text(
                    'In Progress',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// A small column showing a label above a large value, used inside the
// earnings strip for "Total Earned" and "Completed".
class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────── Order List (All / Pending / Active tabs) ─────────
//
// A scrollable list of pending/active orders. Each item is wrapped in a
// Dismissible widget so the driver can swipe left to remove an order.
// Tapping an order opens the OrderDetailScreen where it can be accepted.

class _OrderList extends StatelessWidget {
  final List<OrderModel> orders;
  final String emptyMessage;
  final bool isActiveTab;

  const _OrderList({
    required this.orders,
    required this.emptyMessage,
    this.isActiveTab = false,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _EmptyState(message: emptyMessage, isActiveTab: isActiveTab);
    }

    return ListView.builder(
      // AlwaysScrollableScrollPhysics ensures the RefreshIndicator can be
      // triggered even when the list has fewer items than the screen height.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];

        // context.read (not watch) is safe here because this is inside a
        // callback/builder, not the main build method — no rebuild needed.
        final delivery = context.read<DeliveryProvider>();

        // Determine if this order is the one currently being actively delivered.
        final isCurrentActive = delivery.currentOrder?.id == order.id &&
            delivery.status != DeliveryStatus.waitingForAcceptance;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          // Dismissible allows the driver to swipe the card left to dismiss it.
          // A confirmation dialog is shown before the order is actually removed.
          child: Dismissible(
            key: Key(order.id), // Unique key required by Dismissible.
            direction: DismissDirection.endToStart, // Swipe left only.
            // Red background with a bin icon revealed during the swipe.
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.white,
                size: 28,
              ),
            ),
            // Ask the driver to confirm before removing the order.
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Dismiss Order'),
                      content:
                          const Text('Remove this order from your list?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Dismiss',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            // Calls dismissOrder on the provider, which removes the order from
            // the in-memory list and triggers a UI rebuild via notifyListeners().
            onDismissed: (_) =>
                context.read<DeliveryProvider>().dismissOrder(order),
            child: _OrderListCard(
              order: order,
              isCurrentActive: isCurrentActive,
              onTap: () {
                // Set this order as the current one in the provider, then
                // navigate to the detail screen where it can be accepted.
                context.read<DeliveryProvider>().setCurrentOrder(order);
                NavigationHelper.push(context, const OrderDetailScreen());
              },
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────── Order Card ──────────────────────────────────────
//
// Visual card for a single pending or active order. Consists of:
//   - Header: order number + colour-coded status badge.
//   - Body:   pickup address → delivery address with a connecting line.
//   - Footer: customer name on the left, price + chevron on the right.

class _OrderListCard extends StatelessWidget {
  final OrderModel order;
  final bool isCurrentActive; // true if this order is being delivered now.
  final VoidCallback onTap;

  const _OrderListCard({
    required this.order,
    required this.isCurrentActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          // Subtle shadow to give the card a lifted appearance.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Card Header ──────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.item, // e.g. "Order #1664"
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge: orange "Pending" or green "Active".
                  _StatusBadge(isActive: isCurrentActive),
                ],
              ),
            ),
            // ── Card Body ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                children: [
                  // Pickup row — circle icon + vertical line connecting to
                  // the delivery row below, visually representing a route.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          const Icon(
                            Icons.radio_button_checked,
                            color: Colors.black38,
                            size: 18,
                          ),
                          // The thin vertical line between the two location icons.
                          Container(
                              width: 1, height: 18, color: Colors.black12),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pickup',
                              style: TextStyle(
                                  color: Colors.black38, fontSize: 11),
                            ),
                            Text(
                              order.pickupAddress,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Delivery row — red pin icon marking the destination.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: buttonMainColor,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Delivery',
                              style: TextStyle(
                                  color: Colors.black38, fontSize: 11),
                            ),
                            Text(
                              order.deliveryAddress,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── Footer: customer name + price + arrow ────────────
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 15, color: Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        order.customerName,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        '\$${order.price}',
                        style: TextStyle(
                          color: buttonMainColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Chevron hints that the card is tappable.
                      const Icon(Icons.chevron_right,
                          color: Colors.black26, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A small pill-shaped badge that shows either "Active" (green) or "Pending"
// (orange) depending on whether this order is currently being delivered.
class _StatusBadge extends StatelessWidget {
  final bool isActive;

  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Text(
        isActive ? 'Active' : 'Pending',
        style: TextStyle(
          color: isActive ? Colors.green.shade700 : Colors.orange.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ──────────────────────── Completed Order List (Done tab) ─────────────────
//
// Shows orders whose status is "DELIVERED" in the database. These are fetched
// from a separate backend endpoint (GET /api/drivers/me/orders/completed) and
// loaded lazily — only when the driver first opens the Done tab.
// Completed orders are read-only (no swipe-to-dismiss).

class _CompletedOrderList extends StatelessWidget {
  final DeliveryProvider delivery;

  const _CompletedOrderList({required this.delivery});

  @override
  Widget build(BuildContext context) {
    // Show skeleton cards while the completed orders fetch is in progress.
    if (delivery.isLoadingCompleted) {
      return const _SkeletonList();
    }

    // Show the API error if the fetch failed.
    final err = delivery.completedError;
    if (err != null && err.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              err.replaceFirst('Exception: ', ''),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      );
    }

    // Show the empty state if there are no completed orders yet.
    if (delivery.completedOrders.isEmpty) {
      return const _EmptyState(
        message: 'No deliveries completed today',
        isCompletedTab: true,
      );
    }

    // Render a green card for each completed order.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: delivery.completedOrders.length,
      itemBuilder: (context, index) {
        final order = delivery.completedOrders[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _CompletedOrderCard(order: order),
        );
      },
    );
  }
}

// Card used exclusively in the Done tab. Has a green header and a "Delivered"
// badge instead of the orange "Pending" badge on regular order cards.
class _CompletedOrderCard extends StatelessWidget {
  final OrderModel order;

  const _CompletedOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Green header — visually distinguishes completed orders from pending ones.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: Colors.green.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.item,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // "Delivered" badge in green.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Text(
                    'Delivered',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Compact body row: delivery address, customer name, price.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 15, color: Colors.black45),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.deliveryAddress,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.person_outline,
                    size: 15, color: Colors.black45),
                const SizedBox(width: 4),
                Text(
                  order.customerName,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(width: 12),
                Text(
                  '\$${order.price}',
                  style: TextStyle(
                    color: buttonMainColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────── Empty State ─────────────────────────────────────
//
// Shown when a tab has no orders. Displays a large icon and two lines of
// text that are tailored to the specific tab (All, Active, or Done).
// Using a ListView instead of a plain Column ensures the RefreshIndicator
// can still be triggered even when the screen is empty.

class _EmptyState extends StatelessWidget {
  final String message;
  final bool isActiveTab;
  final bool isCompletedTab;

  const _EmptyState({
    required this.message,
    this.isActiveTab = false,
    this.isCompletedTab = false,
  });

  @override
  Widget build(BuildContext context) {
    // Choose an icon that makes sense for each tab context.
    final icon = isCompletedTab
        ? Icons.check_circle_outline
        : isActiveTab
            ? Icons.local_shipping_outlined
            : Icons.inbox_outlined;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 72, color: Colors.black12),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black38,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        // Secondary hint line, also tailored per tab.
        Text(
          isCompletedTab
              ? 'Completed deliveries will appear here'
              : isActiveTab
                  ? 'Accept an order to start delivering'
                  : 'Pull down to refresh',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black26, fontSize: 13),
        ),
      ],
    );
  }
}

// ──────────────────────── Skeleton Loading ────────────────────────────────
//
// Shown while data is being fetched from the backend.
// Instead of a plain spinner, four placeholder cards are displayed with a
// pulsing opacity animation — a technique called "skeleton loading" or
// "shimmer loading" — which gives the user a preview of the layout
// before the real data arrives, improving perceived performance.

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: 4,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _SkeletonCard(),
      ),
    );
  }
}

// A single animated placeholder card. Uses an AnimationController to
// repeatedly fade the card between 40% and 85% opacity, creating the
// pulsing effect. Each card manages its own controller so they all pulse
// independently (they are not synchronised on purpose — it looks more natural).
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true); // Animate forward then backward, looping forever.
    _opacity = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // Must dispose to stop the animation and free memory.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // Placeholder header area.
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F5F5),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    _box(18, 18, radius: 9),
                    const SizedBox(width: 8),
                    _box(120, 14),
                    const Spacer(),
                    _box(60, 24, radius: 12),
                  ],
                ),
              ),
              // Placeholder body area mimicking the two address rows and footer.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  children: [
                    Row(children: [
                      _box(18, 18, radius: 9),
                      const SizedBox(width: 10),
                      Expanded(child: _box(double.infinity, 14)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      _box(18, 18, radius: 9),
                      const SizedBox(width: 10),
                      Expanded(child: _box(double.infinity, 14)),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      _box(100, 13),
                      const Spacer(),
                      _box(55, 16),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper that builds a grey rounded rectangle used as a content placeholder.
  Widget _box(double width, double height, {double radius = 6}) => Container(
        width: width == double.infinity ? null : width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
