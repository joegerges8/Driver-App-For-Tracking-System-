import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/order_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String? _lastFetchToken;

  void _maybeFetch() {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;
    if (_lastFetchToken == token) return;

    _lastFetchToken = token;
    context.read<DeliveryProvider>().refreshMyOrders(token: token);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_maybeFetch);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If the token is loaded after init (e.g. persisted login), fetch once.
    Future.microtask(_maybeFetch);
  }

  @override
  Widget build(BuildContext context) {
    final delivery = context.watch<DeliveryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: RefreshIndicator(
        onRefresh: () async {
          final token = context.read<AuthProvider>().token;
          if (token != null && token.isNotEmpty) {
            await context.read<DeliveryProvider>().refreshMyOrders(token: token);
          }
        },
        child: Builder(
          builder: (context) {
            if (delivery.isLoadingOrders) {
              return const Center(child: CircularProgressIndicator());
            }

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

            if (delivery.orders.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 48),
                  Center(child: Text('No assigned orders yet')),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: delivery.orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = delivery.orders[index];
                final isSelected = delivery.currentOrder?.id == order.id;

                return ListTile(
                  title: Text(order.item),
                  subtitle: Text(order.deliveryAddress),
                  trailing: Text('\$${order.price}'),
                  selected: isSelected,
                  onTap: () {
                    context.read<DeliveryProvider>().setCurrentOrder(order);
                    NavigationHelper.push(context, const OrderDetailScreen());
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
