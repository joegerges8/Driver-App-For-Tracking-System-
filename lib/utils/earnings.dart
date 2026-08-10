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
// One constant so the Orders and Shipment screens can never disagree; change it
// here and both screens follow.
const int driverFeePerDelivery = 2;

// What the store owes the driver for [completedCount] delivered orders.
int driverPayFor(int completedCount) => completedCount * driverFeePerDelivery;
