import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/utils/whatsapp.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = context.watch<DeliveryProvider>().currentOrder;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.orderDetails),
        centerTitle: false,
      ),
      body: order == null
          ? Center(child: Text(l10n.noOrderSelected))
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // customer information
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 20, top: 12),
                    child: Text(
                      l10n.customerInformation,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundImage: NetworkImage(
                        "https://images.pexels.com/photos/771742/pexels-photo-771742.jpeg?auto=compress&cs=tinysrgb&dpr=1&w=500",
                      ),
                    ),
                    title: Text(
                      order.customerName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${l10n.delivery} • ${order.customerPhone}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => launchUrl(
                            Uri(scheme: 'tel', path: order.customerPhone),
                          ),
                          child: CircleAvatar(
                            backgroundColor: iconColor,
                            child: Icon(Icons.phone, color: Colors.white),
                          ),
                        ),
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _openWhatsApp(context, order),
                          child: CircleAvatar(
                            backgroundColor: const Color(0xFF25D366),
                            child: FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            // order summary
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.orderSummary,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 7),
                    // The order number, then what is actually in the bag.
                    // The products come from the backend's line_items column
                    // (copied off the Shopify order); orders imported before
                    // that column existed carry none, and then the order
                    // number on its own is all there is to show.
                    Text(
                      order.item,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (order.lineItems.isNotEmpty) ...[
                      SizedBox(height: 10),
                      ...order.lineItems.map(
                        (lineItem) => Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Quantity badge — the number the driver counts
                              // against when handing the order over.
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${lineItem.quantity}x',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  lineItem.displayName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.credit_card_outlined),
                        SizedBox(width: 10),
                        Text(
                          "\$${order.price}",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 10),
                        // Dynamic payment status badge.
                        // Previously this was hardcoded to always show "Paid",
                        // which was misleading for COD orders where the customer
                        // has not yet handed over cash.
                        //
                        // Now we read order.isPaid (a bool on OrderModel) and:
                        //   - If false → orange empty circle + "Unpaid (COD)"
                        //     This is the default for every new incoming order.
                        //   - If true  → green checkmark + "Paid"
                        //     This is set automatically when the driver taps
                        //     "Mark as Delivered" (cash has been collected).
                        // A prepaid order (paid online before dispatch) is
                        // shown as its own state rather than plain "Paid":
                        // the driver must not ask for cash, and the amount is
                        // excluded from the earnings totals for that reason.
                        Icon(
                          order.isPaid ? Icons.check_circle_sharp : Icons.radio_button_unchecked,
                          color: order.isPaid ? iconColor : Colors.orange,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            order.isPrepaid
                                ? l10n.prepaidNoCash
                                : (order.isPaid ? l10n.paid : l10n.unpaidCod),
                            style: TextStyle(
                              fontSize: 16,
                              color: order.isPaid ? iconColor : Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Two notes sit between the order and its destination, and they
            // are deliberately not merged: the first came with the order and
            // the driver cannot change it, the second belongs to the driver.
            //
            // The customer note is the Shopify order note — "second floor, no
            // lift", "call before arriving". Orders without one show nothing
            // rather than an empty card, since there is nothing to add to it
            // from here.
            if (order.note.isNotEmpty) ...[
              SizedBox(height: 12),
              _NoteCard(
                title: l10n.customerNotes,
                body: order.note,
                icon: Icons.sticky_note_2_outlined,
              ),
            ],
            // The driver's own note always shows, empty or not — an invisible
            // card would leave nowhere to tap to write the first one.
            SizedBox(height: 12),
            _NoteCard(
              title: l10n.driverNote,
              body: order.driverNote,
              placeholder: l10n.noDriverNoteYet,
              icon: Icons.edit_note,
              actionLabel:
                  order.driverNote.isEmpty ? l10n.addNote : l10n.editNote,
              onEdit: () => _editDriverNote(context, order.driverNote),
            ),
            SizedBox(height: 12),
            // Delivery location.
            // The pickup step used to sit above this one, showing "Current
            // location / You". It said nothing the driver did not already
            // know — the pickup point is wherever they are when they tap
            // "Start Delivery" — so only the destination is shown now.
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: buttonMainColor,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.deliveryLocation,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                order.deliveryAddress,
                                style: TextStyle(fontSize: 13),
                              ),
                              SizedBox(height: 2),
                              Text(
                                order.customerName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // The "navigate here" button used to sit here. Orders
                        // carry a written address but no customer coordinates,
                        // so it had nothing to navigate to.
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // The whole delivery flow lives in this one bar:
      //   • Before starting  → a single "Start Delivery" button.
      //   • After starting   → "Mark as Returned" / "Mark as Delivered".
      // There is no accept/decline step, no pickup step and no in-app map:
      // the dispatcher flips the order to PICKED_UP from the dashboard, which
      // is what reveals the driver on the customer's tracking page. The GPS
      // itself starts flowing as soon as "Start Delivery" is tapped.
      bottomNavigationBar: order == null
          ? null
          : Consumer<DeliveryProvider>(
              builder: (context, provider, child) {
                final isDelivering = provider.isDelivering(order.id);

                return Container(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                    child: isDelivering
                        ? Row(
                            children: [
                              Expanded(
                                child: CustomButton(
                                  color: declineOrder,
                                  textColor: Colors.black54,
                                  title: l10n.markAsReturned,
                                  onPressed: () => _finishDelivery(
                                    context,
                                    returned: true,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: CustomButton(
                                  title: l10n.markAsDelivered,
                                  onPressed: () => _finishDelivery(
                                    context,
                                    returned: false,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : CustomButton(
                            title: l10n.startDelivery,
                            onPressed: () => _startDelivery(context),
                          ),
                  ),
                );
              },
            ),
    );
  }

  // Opens WhatsApp on the customer's chat with the introduction already typed —
  // who the driver is, which shop the order is from, what it costs, and a
  // request for the customer's location. The driver reads it over and hits
  // send: a wa.me link can only pre-fill the input box, never send by itself.
  //
  // The message goes out in English and Arabic together, because the driver has
  // no way of knowing which one this customer reads.
  Future<void> _openWhatsApp(BuildContext context, OrderModel order) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    // Free-form phone text from the Shopify checkout, so it needs normalising
    // before wa.me will accept it — a Lebanese '03 719 871' has to become
    // '9613719871'. Null means there is nothing dialable on the order.
    final number = toWhatsAppNumber(order.customerPhone);
    if (number == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.noWhatsAppNumber)));
      return;
    }

    // The driver profile is fetched separately from the token and can still be
    // in flight right after a cold start; the message drops the name rather
    // than waiting on it.
    final driver = context.read<AuthProvider>().driver;
    final driverName =
        (driver?['full_name'] ?? driver?['name'] ?? '').toString().trim();

    final message = buildOrderWhatsAppMessage(
      storeName: order.storeName,
      // 'Customer' is the placeholder for an order that arrived without a name,
      // and addressing someone as "Customer" reads worse than not naming them.
      customerName: order.customerName == OrderModel.unknownCustomerName
          ? ''
          : order.customerName,
      driverName: driverName,
      orderNumber: order.orderNumber,
      price: order.price,
      isPrepaid: order.isPrepaid,
    );

    // No canLaunchUrl guard on purpose: the Android manifest declares <queries>
    // only for tel: and navigation intents, so on Android 11+ the check would
    // report false for this https link and swallow a tap that in fact works.
    await launchUrl(
      Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  // Opens the note editor and saves what the driver typed. The sheet closes as
  // soon as they tap Save; the note is already on screen by then because the
  // provider writes it locally before syncing, so a slow network never holds
  // up the driver.
  Future<void> _editDriverNote(BuildContext context, String current) async {
    final l10n = context.l10n;
    final provider = context.read<DeliveryProvider>();
    final token = context.read<AuthProvider>().token ?? '';
    final messenger = ScaffoldMessenger.of(context);

    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // leaves room for the keyboard
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DriverNoteSheet(initialNote: current),
    );

    // Dismissed without saving.
    if (note == null) return;
    if (note.trim() == current.trim()) return;

    try {
      await provider.saveDriverNote(token: token, note: note);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.noteSaved)),
      );
    } catch (e) {
      // saveDriverNote has already put the old note back, so the card the
      // driver is looking at matches what the backend holds.
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.noteSaveFailed('$e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Starts the delivery: stamps the driver's current position as the pickup
  // point and kicks off background GPS sharing for this order. The screen
  // stays where it is — only the buttons at the bottom change.
  //
  // An order coming back out of the Returned tab is the one case that needs
  // the backend: it is closed there, so nothing about the restart would stick
  // until it is re-opened. That is the only failure this can report.
  Future<void> _startDelivery(BuildContext context) async {
    final l10n = context.l10n;
    final loc = context.read<CurrentLocationProvider>();
    if (loc.isLoading) {
      showAppSnackbar(
        context: context,
        type: SnackbarType.success,
        description: context.l10n.gettingLocationRetry,
      );
      return;
    }
    if (loc.errorMessage.isNotEmpty) {
      showAppSnackbar(
        context: context,
        type: SnackbarType.error,
        description: loc.errorMessage,
      );
      return;
    }

    // No confirmation snackbar on purpose. The bottom bar swapping from
    // "Start Delivery" to the returned/delivered pair already says the tap
    // landed, and drivers found being told their location is being shared —
    // every single time they start an order — worth removing.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<DeliveryProvider>().startDelivery(
        driverLocation: loc.currentLocation,
        token: context.read<AuthProvider>().token ?? '',
      );
    } catch (e) {
      // The provider has already put the order back in the Returned tab, so
      // the screen matches what the backend holds — the driver taps again
      // rather than setting off on a delivery nobody can see.
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.statusSyncFailed('$e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Closes out the order as either delivered or returned, then goes back to
  // the orders list. The provider updates local state straight away and syncs
  // the status to the backend in the background; a failed sync surfaces as an
  // error snackbar rather than blocking the driver.
  Future<void> _finishDelivery(
    BuildContext context, {
    required bool returned,
  }) async {
    final l10n = context.l10n;
    final provider = context.read<DeliveryProvider>();
    final token = context.read<AuthProvider>().token ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final update = returned
        ? provider.markReturned(token: token)
        : provider.markDelivered(token: token);

    showAppSnackbar(
      context: context,
      type: SnackbarType.success,
      description: returned
          ? l10n.orderMarkedReturned
          : l10n.orderMarkedDelivered,
    );

    if (navigator.canPop()) navigator.pop();

    try {
      await update;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.statusSyncFailed('$e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// One note card. Used for both notes on this screen so the two read as a pair:
// same shape, same warm background, differing only in whether they can be
// edited. Without onEdit it is a plain read-only card.
class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.title,
    required this.body,
    required this.icon,
    this.placeholder,
    this.actionLabel,
    this.onEdit,
  });

  final String title;
  final String body;
  final IconData icon;

  // Shown in place of the body when there is no note yet. Only meaningful on
  // an editable card — a read-only one with nothing to say is not built at all.
  final String? placeholder;
  final String? actionLabel;
  final VoidCallback? onEdit;

  static const Color _accent = Color(0xFF8D6E00);
  static const Color _background = Color(0xFFFFF8E1);

  @override
  Widget build(BuildContext context) {
    final isEmpty = body.isEmpty;

    return Material(
      color: _background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _accent, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _accent,
                            ),
                          ),
                        ),
                        if (onEdit != null && actionLabel != null)
                          Text(
                            actionLabel!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _accent,
                              decoration: TextDecoration.underline,
                              decorationColor: _accent,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 6),
                    // Notes are free text a person typed, so the line breaks
                    // they used are kept and the text wraps instead of being
                    // cut off.
                    Text(
                      isEmpty ? (placeholder ?? '') : body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: isEmpty ? Colors.black45 : Colors.black87,
                        fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
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
}

// The note editor. A bottom sheet rather than a dialog so the field stays
// above the keyboard on a phone, and stateful so the text field keeps its
// controller across the rebuilds the keyboard causes.
//
// Pops with the typed text on save, and with null when dismissed, which is how
// the caller tells "saved an empty note" (the driver clearing it) apart from
// "changed their mind".
class _DriverNoteSheet extends StatefulWidget {
  const _DriverNoteSheet({required this.initialNote});

  final String initialNote;

  @override
  State<_DriverNoteSheet> createState() => _DriverNoteSheetState();
}

class _DriverNoteSheetState extends State<_DriverNoteSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNote);

  // Matches MAX_DRIVER_NOTE_LENGTH in the backend's driverSelfController, which
  // rejects anything longer. Enforcing it here too means the driver is stopped
  // while typing rather than losing the note to an error on save.
  static const int _maxLength = 2000;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      // Lifts the sheet clear of the keyboard.
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.driverNote,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            maxLength: _maxLength,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: l10n.driverNoteHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(_controller.text.trim()),
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
