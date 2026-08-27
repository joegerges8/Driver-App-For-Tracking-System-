// What the driver is actually paid, as opposed to what they collected.
//
// Two different numbers share the word "earnings" in this app and they must not
// be confused:
//
//  * OrderModel.earnedPrice — the cash the driver took from the customer at the
//    door. That money belongs to the store; the driver only carries it.
//  * driverPayFor below — the delivery fee the store owes the driver, a flat
//    amount per completed delivery. This is the figure that says what to hand
//    the driver at the end of the week.
//
// The fee is paid for delivering the order, so it does not depend on how the
// customer paid: a prepaid order the driver collected no cash for still earns
// the full fee, unlike earnedPrice which counts it as 0.

// The flat fee, in dollars, the driver is paid for each completed delivery.
// Not necessarily a whole number of dollars, hence the double.
// One constant so the Orders and Shipment screens can never disagree; change it
// here and both screens follow.
const double driverFeePerDelivery = 2.5;

// What the store owes the driver for [completedCount] delivered orders.
double driverPayFor(int completedCount) =>
    completedCount * driverFeePerDelivery;

// The pay as it appears on the banner, e.g. "17.50". Always two decimals: the
// fee is no longer a whole number, so a driver comparing "$17.5" with "$20"
// should not have to work out which is bigger.
String driverPayLabel(int completedCount) =>
    driverPayFor(completedCount).toStringAsFixed(2);
