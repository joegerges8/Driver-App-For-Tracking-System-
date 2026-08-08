import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ShipmentScreen extends StatefulWidget {
  const ShipmentScreen({super.key});

  @override
  State<ShipmentScreen> createState() => _ShipmentScreenState();
}

class _ShipmentScreenState extends State<ShipmentScreen> {
  // Selected period for the earnings card: 'Day', 'Week', or 'Month'.
  String _period = 'Day';

  // Ensures we only fetch completed orders once per session.
  bool _hasFetched = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_maybeFetch);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Future.microtask(_maybeFetch);
  }

  void _maybeFetch() {
    if (_hasFetched) return;
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;
    _hasFetched = true;
    context.read<DeliveryProvider>().refreshCompletedOrders(token: token);
  }

  // Returns the start of the window for the selected period (UTC-normalised).
  DateTime _periodStart(DateTime now) {
    final today = DateUtils.dateOnly(now);
    switch (_period) {
      case 'Week':
        return today.subtract(Duration(days: today.weekday - 1));
      case 'Month':
        return DateTime(today.year, today.month, 1);
      default: // 'Day'
        return today;
    }
  }

  // Orders that fall within the selected period.
  List<OrderModel> _filtered(List<OrderModel> all) {
    final start = _periodStart(DateTime.now());
    return all.where((o) {
      final date = DateUtils.dateOnly(o.deliveredAt ?? DateTime.now());
      return !date.isBefore(start);
    }).toList();
  }

  // Groups orders by their delivery date, newest first.
  // Returns a list of (dateLabel, orders) pairs.
  List<MapEntry<String, List<OrderModel>>> _grouped(
    BuildContext context,
    List<OrderModel> all,
  ) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<DateTime, List<OrderModel>> map = {};
    for (final o in all) {
      final key = DateUtils.dateOnly(o.deliveredAt ?? now);
      map.putIfAbsent(key, () => []).add(o);
    }

    final sorted = map.keys.toList()..sort((a, b) => b.compareTo(a));

    return sorted.map((date) {
      String label;
      if (date == today) {
        label = l10n.today;
      } else if (date == yesterday) {
        label = l10n.yesterday;
      } else {
        label = '${l10n.shortMonths[date.month - 1]} ${date.day}';
      }
      return MapEntry(label, map[date]!);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final delivery = context.watch<DeliveryProvider>();
    final completedOrders = delivery.completedOrders;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.shipmentTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final token = context.read<AuthProvider>().token;
          if (token != null && token.isNotEmpty) {
            await context
                .read<DeliveryProvider>()
                .refreshCompletedOrders(token: token);
          }
        },
        child: _buildBody(context, delivery, completedOrders),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DeliveryProvider delivery,
      List<OrderModel> completedOrders) {
    final l10n = context.l10n;
    if (delivery.isLoadingCompleted) {
      return const _SkeletonList();
    }

    final err = delivery.completedError;
    if (err != null && err.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.wifi_off_outlined, size: 56, color: Colors.black12),
          const SizedBox(height: 12),
          Text(
            err.replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () {
                final token = context.read<AuthProvider>().token;
                if (token != null && token.isNotEmpty) {
                  context
                      .read<DeliveryProvider>()
                      .refreshCompletedOrders(token: token);
                }
              },
              child: Text(l10n.retry),
            ),
          ),
        ],
      );
    }

    final filtered = _filtered(completedOrders);
    final groups = _grouped(context, completedOrders);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      children: [
        // ── Earnings Card ─────────────────────────────────────────────
        _EarningsCard(
          period: _period,
          onPeriodChanged: (p) => setState(() => _period = p),
          filteredOrders: filtered,
        ),
        const SizedBox(height: 24),

        // ── History Section Header ────────────────────────────────────
        Text(
          l10n.deliveryHistory,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),

        if (completedOrders.isEmpty) ...[
          const SizedBox(height: 32),
          const Icon(Icons.local_shipping_outlined,
              size: 64, color: Colors.black12),
          const SizedBox(height: 12),
          Text(
            l10n.noDeliveriesYet,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.black38,
                fontSize: 16,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.completedWillAppearHere,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black26, fontSize: 13),
          ),
        ] else ...[
          for (final group in groups) ...[
            _DateGroupHeader(label: group.key),
            const SizedBox(height: 8),
            for (final order in group.value) ...[
              _HistoryCard(order: order),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

// ──────────────────────── Earnings Card ───────────────────────────────────

class _EarningsCard extends StatelessWidget {
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final List<OrderModel> filteredOrders;

  const _EarningsCard({
    required this.period,
    required this.onPeriodChanged,
    required this.filteredOrders,
  });

  @override
  Widget build(BuildContext context) {
    final total =
        filteredOrders.fold<int>(0, (sum, o) => sum + o.price);
    final count = filteredOrders.length;

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
          // Header — red stripe with total
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: buttonMainColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: buttonMainColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.totalEarned,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '\$$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      context.l10n.deliveries,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Period toggle
          Padding(
            padding: const EdgeInsets.all(16),
            child: _PeriodToggle(
                selected: period, onChanged: onPeriodChanged),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────── Period Toggle ────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _PeriodToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The values stay English because _period drives date maths elsewhere;
    // only the visible label is translated.
    const periods = ['Day', 'Week', 'Month'];
    final labels = {
      'Day': l10n.periodDay,
      'Week': l10n.periodWeek,
      'Month': l10n.periodMonth,
    };
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: periods
            .map((p) => Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected == p
                            ? buttonMainColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        labels[p]!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected == p
                              ? Colors.white
                              : Colors.black54,
                          fontWeight: selected == p
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ──────────────────────── Date Group Header ─────────────────────────────────

class _DateGroupHeader extends StatelessWidget {
  final String label;

  const _DateGroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: Colors.black12, thickness: 1)),
      ],
    );
  }
}

// ──────────────────────── History Card ─────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final OrderModel order;

  const _HistoryCard({required this.order});

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
          // Green header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
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

          // Body: address, customer, price
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
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black54),
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
                  style:
                      const TextStyle(fontSize: 13, color: Colors.black54),
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

// ──────────────────────── Skeleton Loading ────────────────────────────────

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      children: [
        // Earnings card skeleton
        _SkeletonBox(height: 140, radius: 16),
        const SizedBox(height: 24),
        _SkeletonBox(height: 18, width: 120),
        const SizedBox(height: 12),
        for (int i = 0; i < 3; i++) ...[
          _SkeletonBox(height: 100, radius: 16),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const _SkeletonBox({
    required this.height,
    this.width,
    this.radius = 6,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 0.85)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}
