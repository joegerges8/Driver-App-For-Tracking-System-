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
//  4. Skeleton loading — pulsing grey placeholder cards are shown while data
//                     loads, instead of a plain spinner.
//  5. Empty states  — each tab shows a context-aware icon and message when empty.
//  6. Done tab      — read-only green cards for completed deliveries, loaded
//                     lazily when the driver first opens that tab.
//  7. Area filter   — chips above the tabs narrow every tab to one delivery
//                     area (Beirut, Metn, Keserwan, ...). Replaced an earlier
//                     per-city filter; see _AreaFilterBar for why.
//  8. Order search  — a field above the tabs that finds one order by its
//                     number, typed without the '#'. See _OrderSearchField.

import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/order_detail_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/utils/order_search.dart';
import 'package:delivery_boy_app/widgets/driver_pay_row.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Label the backend uses for orders whose city string could not be matched to
// an area. Kept in sync with UNKNOWN_AREA in the backend's areaLookup.js.
const String _unknownArea = 'Other';

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

  // What the driver has typed into the order-number search field, exactly as
  // typed. Normalising happens at comparison time so the field itself never
  // rewrites what someone is in the middle of typing.
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

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
    _searchController.dispose();
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
    final delivery = context.read<DeliveryProvider>();
    delivery.refreshMyOrders(token: token);

    // The banner above the tabs reports Completed and Your Earnings out of the
    // completed list, which otherwise only loads when the Done tab is opened —
    // so a driver who never opened that tab read $0 for work they had done.
    // Silent, so the Done tab keeps ownership of its own skeleton and error
    // states and this fetch cannot flash either of them on arrival.
    delivery.refreshCompletedOrders(token: token, silent: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Called when an inherited widget (like AuthProvider) changes — handles
    // the case where the token is restored from storage after initState runs.
    Future.microtask(_maybeFetch);
  }

  // Currently selected delivery area, or null for "All". Lives on the screen
  // rather than inside one tab so the same filter applies everywhere — picking
  // Keserwan narrows All, Pending, Returned and Completed at once.
  String? _selectedArea;

  // The areas actually present in the driver's orders, sorted, with the
  // catch-all bucket pushed to the end so it never crowds out real areas.
  List<String> _areasIn(List<List<OrderModel>> orderLists) {
    final areas = <String>{};
    var hasUnfiled = false;

    for (final list in orderLists) {
      for (final order in list) {
        // An empty area means the row predates the backend's area column, which
        // is the same situation for a driver as one the lookup could not place.
        if (order.area.isEmpty || order.area == _unknownArea) {
          hasUnfiled = true;
        } else {
          areas.add(order.area);
        }
      }
    }

    final sorted = areas.toList()..sort();

    // Only offer the catch-all chip alongside real areas. If nothing is
    // classified yet — an app pointed at a backend that hasn't been backfilled —
    // a lone "Other" chip filters nothing, so the bar stays hidden instead.
    if (hasUnfiled && sorted.isNotEmpty) sorted.add(_unknownArea);
    return sorted;
  }

  // Applies the selected area to a list. Orders with no area at all (written
  // before the backend started classifying) count as unfiled, so they show up
  // under the same chip as the ones the lookup could not place.
  List<OrderModel> _filterByArea(List<OrderModel> orders) {
    final selected = _selectedArea;
    if (selected == null) return orders;

    if (selected == _unknownArea) {
      return orders
          .where((o) => o.area.isEmpty || o.area == _unknownArea)
          .toList();
    }

    return orders.where((o) => o.area == selected).toList();
  }

  // The search as it will actually be compared — '#', spaces and case removed.
  // Empty when the field is empty or holds only punctuation, which every reader
  // below treats as "no search running".
  String get _query => normalizeOrderQuery(_searchText);

  bool get _isSearching => _query.isNotEmpty;

  // What a tab shows: the searched order, or the area-filtered list.
  //
  // A search deliberately ignores the area chips. Looking up a number is not
  // browsing — the driver has one specific order in mind, usually because a
  // customer is on the phone about it — and silently hiding it because a chip
  // from ten minutes ago points at another area would look exactly like the
  // order not existing. The chip bar hides itself while a search is running so
  // the two filters are never shown as if they were both in force.
  List<OrderModel> _visible(List<OrderModel> orders) {
    if (_isSearching) {
      return orders
          .where((o) => orderNumberMatches(o.orderNumber, _query))
          .toList();
    }

    return _filterByArea(orders);
  }

  @override
  Widget build(BuildContext context) {
    // context.watch rebuilds this widget automatically whenever DeliveryProvider
    // calls notifyListeners() (e.g. after a fetch completes).
    final l10n = context.l10n;
    final delivery = context.watch<DeliveryProvider>();

    // Determine whether any order is being actively delivered. The driver can
    // be carrying several at once, so this is a count, not a single order.
    final activeIds = delivery.activeOrderIds;
    final isActive = activeIds.isNotEmpty;

    // Pending tab: all orders except the ones currently being delivered.
    final pendingOrders = delivery.orders
        .where((o) => !activeIds.contains(o.id))
        .toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.myOrders,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: buttonMainColor,
          unselectedLabelColor: Colors.black45,
          indicatorColor: buttonMainColor,
          indicatorWeight: 3,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // The counts follow the search as well as the area filter, so a
          // driver searching 2693 reads which tab the order is sitting in
          // instead of having to open all four looking for it.
          tabs: [
            Tab(text: l10n.tabAll(_visible(delivery.orders).length)),
            Tab(text: l10n.tabPending(_visible(pendingOrders).length)),
            Tab(
              text: l10n.tabReturned(
                _visible(delivery.returnedOrders).length,
              ),
            ),
            Tab(
              text: l10n.tabCompleted(
                _visible(delivery.completedOrders).length,
              ),
            ),
          ],
        ),
      ),
      // The search field sits outside the RefreshIndicator so it stays put
      // while the list below it is loading, erroring or being pulled down.
      body: Column(
        children: [
          _OrderSearchField(
            controller: _searchController,
            onChanged: (text) => setState(() => _searchText = text),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                final token = context.read<AuthProvider>().token;
                if (token != null && token.isNotEmpty) {
                  await context.read<DeliveryProvider>().refreshMyOrders(
                    token: token,
                  );
                }
              },
              child: _buildBody(context, delivery, pendingOrders, isActive),
            ),
          ),
        ],
      ),
    );
  }

  // Decides what to show in the body based on the current loading/error state.
  Widget _buildBody(
    BuildContext context,
    DeliveryProvider delivery,
    List<OrderModel> pendingOrders,
    bool isActive,
  ) {
    final l10n = context.l10n;

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

    // Every area present across all four lists, so switching tabs never makes
    // the chip you selected disappear from the bar.
    final areas = _areasIn([
      delivery.orders,
      pendingOrders,
      delivery.returnedOrders,
      delivery.completedOrders,
    ]);

    // While a search is running the tabs show whatever matched the number, so
    // the empty state says so rather than claiming the driver has no orders.
    String emptyMessage(String whenBrowsing) =>
        _isSearching ? l10n.noOrderMatching(_query) : whenBrowsing;
    final String? emptyHint = _isSearching ? l10n.tryOtherTabs : null;

    // Main layout: earnings strip, area filter, then the four tab views.
    return Column(
      children: [
        _EarningsSummaryStrip(
          completedOrders: delivery.completedOrders,
          isActive: isActive,
        ),
        // Hidden during a search, which ignores the area filter — see _visible.
        if (areas.isNotEmpty && !_isSearching)
          _AreaFilterBar(
            areas: areas,
            selectedArea: _selectedArea,
            onSelected: (area) => setState(() {
              // Tapping the active chip clears the filter, so "All" is always
              // one tap away without hunting for it.
              _selectedArea = (area.isEmpty || _selectedArea == area)
                  ? null
                  : area;
            }),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // All tab — every assigned order.
              _OrderList(
                orders: _visible(delivery.orders),
                emptyMessage: emptyMessage(l10n.noOrdersAssigned),
                emptyHint: emptyHint,
              ),
              // Pending tab — orders not started yet.
              _OrderList(
                orders: _visible(pendingOrders),
                emptyMessage: emptyMessage(l10n.noPendingOrders),
                emptyHint: emptyHint,
              ),
              // Returned tab — orders the driver marked as returned.
              _OrderList(
                orders: _visible(delivery.returnedOrders),
                emptyMessage: emptyMessage(l10n.noReturnedOrders),
                emptyHint: emptyHint,
              ),
              // Done tab — read-only cards for completed deliveries.
              _CompletedOrderList(
                orders: _visible(delivery.completedOrders),
                delivery: delivery,
                emptyMessage: emptyMessage(l10n.noDeliveriesToday),
                emptyHint: emptyHint,
              ),
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
//   - Total Earned: the cash collected across completed orders. Orders the
//     customer paid online count as 0 — the driver never handled that money,
//     so including it would count the same payment twice.
//   - Completed:    how many orders have been marked as delivered.
//   - "In Progress" pill: shown only when a delivery is currently active.
//   - Your Earnings: the delivery fees the store owes the driver — a flat
//     amount per completed order, prepaid ones included, since the fee is for
//     making the delivery and not for carrying the cash.
//
// The values are derived from completedOrders (fetched from the Done tab
// endpoint), so the strip accurately reflects real delivered orders rather
// than just assigned ones.

class _EarningsSummaryStrip extends StatelessWidget {
  final List<OrderModel> completedOrders;
  final bool isActive;

  const _EarningsSummaryStrip({
    required this.completedOrders,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    // Sum what the driver actually collected. Orders the customer had already
    // paid online contribute 0 — see OrderModel.earnedPrice.
    final total = completedOrders.fold<int>(0, (sum, o) => sum + o.earnedPrice);

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
      child: Column(
        children: [
          Row(
            children: [
              _StatColumn(label: context.l10n.totalEarned, value: '\$$total'),
              const Spacer(),
              _StatColumn(
                label: context.l10n.completed,
                value: '${completedOrders.length}',
              ),
              // The "In Progress" pill is conditionally shown only when the
              // driver has accepted an order and is currently on the way.
              if (isActive) ...[
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping,
                        color: Colors.white,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.inProgress,
                        style: const TextStyle(
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

          // What the store owes the driver for those deliveries, under the
          // cash they collected for the store. Counts every completed order
          // rather than the area-filtered ones, matching the Completed figure
          // it sits under — the Shipment tab is where the driver breaks the
          // same total down by day, week or month.
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1, thickness: 1),
          const SizedBox(height: 10),
          DriverPayRow(count: completedOrders.length),
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
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
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

// ──────────────────────── Order Search Field ──────────────────────────────
//
// Finds one order by its number. A driver on the phone with a customer is told
// "order 2693" and types exactly that: no '#', no "order", no case to get
// right — orderNumberMatches strips all of it before comparing.
//
// The keyboard is the numeric one because every order number in the list is a
// number, and a driver holding a phone in one hand at a gate should not have to
// hunt for digits on a letter keyboard. Nothing is lost for a store whose
// numbers carry a prefix ('EN2693'): matching is on any part of the number, so
// the digits alone still find it.

class _OrderSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _OrderSearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.isNotEmpty;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: context.l10n.searchOrderNumber,
          hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black45),
          // Clearing is one tap, so a driver who searched an order and now
          // wants their list back is never left deleting digits.
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.black45,
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                    // Put the keyboard away with the search: the driver is
                    // going back to reading the list, not typing again.
                    FocusScope.of(context).unfocus();
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: buttonMainColor),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────── Area Filter Bar ─────────────────────────────────
//
// A horizontally scrollable row of filter chips — one per delivery area the
// driver currently has orders in, plus an "All" chip that clears the filter.
//
// This replaced a per-city filter. Cities come from the Shopify checkout as
// free text, so a single town produced several chips ("Zahle", "zahle",
// "Zahle Madine") and a busy driver could face dozens of them. The backend now
// maps each city onto a delivery area, which is both stable and the unit a
// dispatcher actually thinks in.

class _AreaFilterBar extends StatelessWidget {
  final List<String> areas;
  final String? selectedArea;
  final ValueChanged<String> onSelected;

  const _AreaFilterBar({
    required this.areas,
    required this.selectedArea,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip(
              context,
              label: context.l10n.filterAll,
              selected: selectedArea == null,
              onTap: () => onSelected(''),
            ),
            ...areas.map(
              (area) => _chip(
                context,
                // Area names come from the backend in English; only the
                // catch-all bucket has a translation to show.
                label: area == _unknownArea ? context.l10n.areaOther : area,
                selected: selectedArea == area,
                onTap: () => onSelected(area),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? buttonMainColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? buttonMainColor : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────── Order List (All / Returned tabs) ────────────────
//
// A scrollable list of orders.
// Tapping an order opens the OrderDetailScreen where the delivery is started.

class _OrderList extends StatelessWidget {
  final List<OrderModel> orders;
  final String emptyMessage;

  // Second line of the empty state. Null keeps the tab's usual one.
  final String? emptyHint;

  const _OrderList({
    required this.orders,
    required this.emptyMessage,
    this.emptyHint,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _EmptyState(message: emptyMessage, hint: emptyHint);
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

        // Determine if this order is one of the ones being actively delivered.
        final isCurrentActive = delivery.isDelivering(order.id);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrderListCard(
            order: order,
            isCurrentActive: isCurrentActive,
            onTap: () {
              // Set this order as the current one in the provider, then
              // navigate to the detail screen where the delivery is started.
              context.read<DeliveryProvider>().setCurrentOrder(order);
              NavigationHelper.push(context, const OrderDetailScreen());
            },
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
//   - Body:   delivery address.
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
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
                  // Delivery row — red pin icon marking the destination.
                  // A pickup row used to sit above it, joined by a short
                  // vertical line to read as a route. It only ever said
                  // "Current location", which is where the driver already is,
                  // so the destination is the whole of the route worth showing.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on, color: buttonMainColor, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.delivery,
                              style: const TextStyle(
                                color: Colors.black38,
                                fontSize: 11,
                              ),
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
                      const Icon(
                        Icons.person_outline,
                        size: 15,
                        color: Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      // The order's own value, not an earning — the delivery
                      // hasn't happened yet. Prepaid orders are flagged so the
                      // driver knows there is no cash to collect on arrival.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${order.price}',
                            style: TextStyle(
                              color: order.isPrepaid
                                  ? Colors.black38
                                  : buttonMainColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (order.isPrepaid)
                            Text(
                              context.l10n.prepaid,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black38,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      // Chevron hints that the card is tappable.
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.black26,
                        size: 20,
                      ),
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
        isActive ? context.l10n.statusActive : context.l10n.statusPending,
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
// Completed orders are read-only.

class _CompletedOrderList extends StatelessWidget {
  // Already narrowed by the area filter or the search; `delivery` is still
  // needed for the loading and error states, which are neither.
  final List<OrderModel> orders;
  final DeliveryProvider delivery;
  final String emptyMessage;
  final String? emptyHint;

  const _CompletedOrderList({
    required this.orders,
    required this.delivery,
    required this.emptyMessage,
    this.emptyHint,
  });

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
    if (orders.isEmpty) {
      return _EmptyState(
        message: emptyMessage,
        hint: emptyHint,
        isCompletedTab: true,
      );
    }

    // Render a green card for each completed order.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.item,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // "Delivered" badge in green.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Text(
                    context.l10n.statusDelivered,
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
                const Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: Colors.black45,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.deliveryAddress,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.person_outline,
                  size: 15,
                  color: Colors.black45,
                ),
                const SizedBox(width: 4),
                Text(
                  order.customerName,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(width: 12),
                // Mirrors the earnings strip: a prepaid order earned nothing,
                // so it shows $0 with its own price kept as a caption.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${order.earnedPrice}',
                      style: TextStyle(
                        color: order.isPrepaid ? Colors.black38 : buttonMainColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (order.isPrepaid)
                      Text(
                        '\$${order.price} ${context.l10n.prepaid.toLowerCase()}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black38,
                        ),
                      ),
                  ],
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
  final bool isCompletedTab;

  // Overrides the second line. Used by the search, where "pull down to refresh"
  // would be advice that cannot help — the order is simply on another tab.
  final String? hint;

  const _EmptyState({
    required this.message,
    this.hint,
    this.isCompletedTab = false,
  });

  @override
  Widget build(BuildContext context) {
    // A search that found nothing here is not the same emptiness as a tab with
    // no orders in it, and the magnifying glass says which one this is.
    final icon = hint != null
        ? Icons.search_off
        : isCompletedTab
            ? Icons.check_circle_outline
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
        Text(
          hint ??
              (isCompletedTab
                  ? context.l10n.completedWillAppearHere
                  : context.l10n.pullDownToRefresh),
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
    _opacity = Tween<double>(
      begin: 0.4,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller
        .dispose(); // Must dispose to stop the animation and free memory.
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
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                    Row(
                      children: [
                        _box(18, 18, radius: 9),
                        const SizedBox(width: 10),
                        Expanded(child: _box(double.infinity, 14)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _box(18, 18, radius: 9),
                        const SizedBox(width: 10),
                        Expanded(child: _box(double.infinity, 14)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [_box(100, 13), const Spacer(), _box(55, 16)],
                    ),
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
