import 'package:flutter/material.dart';

// ─── App translations (English / Arabic) ─────────────────────────────────────
// Every user-facing string in the app lives in the two maps at the bottom of
// this file. Screens read them through `context.l10n.someKey` instead of
// hard-coding English text, so switching the language rebuilds the whole UI
// with the Arabic strings and no screen needs to know which language is active.
//
// Why hand-written instead of `flutter gen-l10n` + .arb files:
// the string set is small and fully owned by this app, so a plain map keeps the
// whole translation table readable in one place with no code generation step in
// the build.
//
// Text direction is NOT handled here — MaterialApp derives it from the active
// locale via GlobalWidgetsLocalizations, so picking Arabic automatically flips
// the entire layout to RTL (nav bar order, list padding, row alignment).
// ─────────────────────────────────────────────────────────────────────────────
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = [Locale('en'), Locale('ar')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // Non-null because the delegate is registered in MaterialApp and loads
  // synchronously, so an AppLocalizations is always in the widget tree.
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  bool get isArabic => locale.languageCode == 'ar';

  // Falls back to English for any key missing from the Arabic table, so a
  // forgotten translation shows readable text instead of a raw key.
  String _t(String key) =>
      (isArabic ? _ar[key] : _en[key]) ?? _en[key] ?? key;

  // ── Language picker ───────────────────────────────────────────────────────
  String get language => _t('language');
  String get english => _t('english');
  String get arabic => _t('arabic');

  // ── Bottom navigation ─────────────────────────────────────────────────────
  String get navHome => _t('navHome');
  String get navOrders => _t('navOrders');
  String get navShipment => _t('navShipment');
  String get navProfile => _t('navProfile');

  // ── Login ─────────────────────────────────────────────────────────────────
  String get driverPortal => _t('driverPortal');
  String get welcomeBack => _t('welcomeBack');
  String get signIn => _t('signIn');
  String get enterCredentials => _t('enterCredentials');
  String get email => _t('email');
  String get password => _t('password');
  String get logIn => _t('logIn');
  String get dontHaveAccount => _t('dontHaveAccount');
  String get signUp => _t('signUp');
  String get emailPasswordRequired => _t('emailPasswordRequired');

  // ── Signup ────────────────────────────────────────────────────────────────
  String get createAccount => _t('createAccount');
  String get joinDeliveryTeam => _t('joinDeliveryTeam');
  String get fillYourDetails => _t('fillYourDetails');
  String get fullName => _t('fullName');
  String get phone => _t('phone');
  String get allFieldsRequired => _t('allFieldsRequired');
  String get enterValidEmail => _t('enterValidEmail');
  String get alreadyHaveAccount => _t('alreadyHaveAccount');

  // ── Profile ───────────────────────────────────────────────────────────────
  String get profileTitle => _t('profileTitle');
  String get totalDeliveries => _t('totalDeliveries');
  String get changePassword => _t('changePassword');
  String get logOut => _t('logOut');
  String get logOutConfirm => _t('logOutConfirm');
  String get cancel => _t('cancel');
  String get currentPassword => _t('currentPassword');
  String get newPassword => _t('newPassword');
  String get confirmNewPassword => _t('confirmNewPassword');
  String get fieldRequired => _t('fieldRequired');
  String get atLeastSixCharacters => _t('atLeastSixCharacters');
  String get passwordsDoNotMatch => _t('passwordsDoNotMatch');
  String get updatePassword => _t('updatePassword');
  String get passwordUpdated => _t('passwordUpdated');

  // ── Orders ────────────────────────────────────────────────────────────────
  String get myOrders => _t('myOrders');
  String tabAll(int count) => '${_t('tabAll')} ($count)';
  String tabReturned(int count) => '${_t('tabReturned')} ($count)';
  String tabCompleted(int count) => '${_t('tabCompleted')} ($count)';
  String get totalEarned => _t('totalEarned');
  // The driver's own pay — the delivery fees owed to them — as opposed to
  // totalEarned above, which is the store's cash they collected at the door.
  String get yourEarnings => _t('yourEarnings');
  String get filterAll => _t('filterAll');
  String get areaOther => _t('areaOther');
  // Hint inside the search field on the Orders tab. The example is a phone
  // number without its +961, since that is what a driver types.
  String get searchPhoneNumber => _t('searchPhoneNumber');
  // Empty state while a search is running. The query may be a phone number or
  // an order number, so the sentence names neither.
  String noOrderMatching(String query) =>
      _t('noOrderMatching').replaceFirst('{n}', query);
  // Sits under the message above when the order is on a tab the driver has
  // since moved away from by hand — the search itself opens the right one.
  String get tryOtherTabs => _t('tryOtherTabs');
  // Sits there instead when the number matched nothing on any tab, so the
  // driver is not sent hunting through three empty ones.
  String get orderNotInYourList => _t('orderNotInYourList');
  String get noOrdersAssigned => _t('noOrdersAssigned');
  String get noReturnedOrders => _t('noReturnedOrders');
  String get noDeliveriesToday => _t('noDeliveriesToday');
  String get completedWillAppearHere => _t('completedWillAppearHere');
  String get pullDownToRefresh => _t('pullDownToRefresh');
  String get pickup => _t('pickup');
  String get delivery => _t('delivery');
  String get statusActive => _t('statusActive');
  String get statusPending => _t('statusPending');
  String get statusDelivered => _t('statusDelivered');

  // ── Order detail ──────────────────────────────────────────────────────────
  String get orderDetails => _t('orderDetails');
  String get noOrderSelected => _t('noOrderSelected');
  String get customerInformation => _t('customerInformation');
  // Shown when the WhatsApp button is tapped on an order whose phone number is
  // missing or unusable. This one follows the app's locale like every other
  // string here — unlike the message sent TO the customer, which carries both
  // languages at once (see lib/utils/whatsapp.dart).
  String get noWhatsAppNumber => _t('noWhatsAppNumber');
  String get orderSummary => _t('orderSummary');
  // Heading of the note card carrying the instructions written on the order in
  // Shopify. Named for the reader's point of view — it is the note that came
  // with the order, as opposed to the one the driver writes below it.
  String get customerNotes => _t('customerNotes');
  // The driver's own note on the order, written and edited in the app.
  String get driverNote => _t('driverNote');
  String get addNote => _t('addNote');
  String get editNote => _t('editNote');
  String get noDriverNoteYet => _t('noDriverNoteYet');
  String get driverNoteHint => _t('driverNoteHint');
  String get save => _t('save');
  String get noteSaved => _t('noteSaved');
  String noteSaveFailed(String error) => '${_t('noteSaveFailed')}: $error';
  String get paid => _t('paid');
  String get unpaidCod => _t('unpaidCod');
  // Shown on orders the customer had already paid online: no cash is
  // collected for them, so they count as 0 in the earnings totals.
  String get prepaid => _t('prepaid');
  String get prepaidNoCash => _t('prepaidNoCash');
  // The customer paid by Whish transfer at the door. Shown as the payment
  // state once recorded; the amount counts as 0 in the earnings totals, since
  // the money went to the Whish account and never into the driver's bag.
  String get paidByWhish => _t('paidByWhish');
  // The third button in the delivery bar — closes the order and records the
  // Whish payment in one tap — and the confirmation around it: the payment is
  // written to Shopify, so it needs a deliberate yes before it goes out.
  String get deliveredPaidByWhish => _t('deliveredPaidByWhish');
  String get whishConfirmTitle => _t('whishConfirmTitle');
  String get whishConfirmBody => _t('whishConfirmBody');
  String get confirm => _t('confirm');
  String get whishPaymentRecorded => _t('whishPaymentRecorded');
  String get pickupLocation => _t('pickupLocation');
  String get deliveryLocation => _t('deliveryLocation');
  String get you => _t('you');
  String get startDelivery => _t('startDelivery');
  String get markAsReturned => _t('markAsReturned');
  String get markAsDelivered => _t('markAsDelivered');
  String get gettingLocationRetry => _t('gettingLocationRetry');
  String get orderMarkedReturned => _t('orderMarkedReturned');
  String get orderMarkedDelivered => _t('orderMarkedDelivered');
  String statusSyncFailed(String error) => '${_t('statusSyncFailed')}: $error';
  String get statusQueuedOffline => _t('statusQueuedOffline');
  String pendingSyncBanner(int count) =>
      count == 1 ? _t('pendingSyncOne') : '$count ${_t('pendingSyncMany')}';

  // ── Home / map ────────────────────────────────────────────────────────────
  String get currentLocation => _t('currentLocation');
  String get youAreHere => _t('youAreHere');
  String get gettingYourLocation => _t('gettingYourLocation');
  String get mapsNotConfigured => _t('mapsNotConfigured');

  // ── Home order cards ──────────────────────────────────────────────────────
  String get ongoingOrder => _t('ongoingOrder');
  String get newOrderAvailable => _t('newOrderAvailable');
  String get pickupLabel => _t('pickupLabel');
  String get deliveryLabel => _t('deliveryLabel');
  String get viewOngoingOrder => _t('viewOngoingOrder');
  String get viewOrderDetails => _t('viewOrderDetails');

  // ── Shipment ──────────────────────────────────────────────────────────────
  String get shipmentTitle => _t('shipmentTitle');
  String get deliveries => _t('deliveries');
  String get deliveryHistory => _t('deliveryHistory');
  String get noDeliveriesYet => _t('noDeliveriesYet');
  String get retry => _t('retry');
  String get periodDay => _t('periodDay');
  String get periodWeek => _t('periodWeek');
  String get periodMonth => _t('periodMonth');
  String get today => _t('today');
  String get yesterday => _t('yesterday');

  // Short month names used by the delivery-history date headers.
  List<String> get shortMonths => isArabic
      ? const [
          'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
          'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
        ]
      : const [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];

  // ── Tracking setup ────────────────────────────────────────────────────────
  // The screen that walks the driver through the phone settings their location
  // needs in order to keep reporting while the app is in the background.
  String get trackingSetupTitle => _t('trackingSetupTitle');
  String get trackingSetupIntro => _t('trackingSetupIntro');
  String get trackingBannerFix => _t('trackingBannerFix');
  String get trackingBannerIncomplete => _t('trackingBannerIncomplete');
  String get trackingBannerStopped => _t('trackingBannerStopped');
  String get trackingStepLocationTitle => _t('trackingStepLocationTitle');
  String get trackingStepLocationBody => _t('trackingStepLocationBody');
  String get trackingStepBatteryTitle => _t('trackingStepBatteryTitle');
  String get trackingStepBatteryBody => _t('trackingStepBatteryBody');
  String get trackingStepAutostartTitle => _t('trackingStepAutostartTitle');
  String get trackingStepRecentsTitle => _t('trackingStepRecentsTitle');
  String get trackingStepRecentsBody => _t('trackingStepRecentsBody');
  String get trackingStepGpsTitle => _t('trackingStepGpsTitle');
  String get trackingStepGpsBody => _t('trackingStepGpsBody');
  String get trackingOpenSettings => _t('trackingOpenSettings');
  String get trackingGrant => _t('trackingGrant');
  String get trackingDone => _t('trackingDone');
  String get trackingAllSet => _t('trackingAllSet');
  String get trackingRecheck => _t('trackingRecheck');
  String get trackingFinish => _t('trackingFinish');

  /// The autostart step's wording, which is the one that differs per phone —
  /// Transsion's "Power Marathon" on Infinix and Tecno is a different screen
  /// with a different name from MIUI's autostart list.
  String trackingStepAutostartBody(String? vendorKey) =>
      _t('trackingAutostart_${vendorKey ?? 'generic'}');

  // ── Toasts ────────────────────────────────────────────────────────────────
  String get toastSuccess => _t('toastSuccess');
  String get toastFail => _t('toastFail');

  static const Map<String, String> _en = {
    'language': 'Language',
    'english': 'English',
    'arabic': 'العربية',

    'navHome': 'Home',
    'navOrders': 'Orders',
    'navShipment': 'Shipment',
    'navProfile': 'Profile',

    'driverPortal': 'Driver Portal',
    'welcomeBack': 'Welcome back',
    'signIn': 'Sign In',
    'enterCredentials': 'Enter your credentials to continue',
    'email': 'Email',
    'password': 'Password',
    'logIn': 'Log In',
    'dontHaveAccount': "Don't have an account?  ",
    'signUp': 'Sign Up',
    'emailPasswordRequired': 'Email and password are required',

    'createAccount': 'Create Account',
    'joinDeliveryTeam': 'Join the delivery team',
    'fillYourDetails': 'Fill in your details to get started',
    'fullName': 'Full Name',
    'phone': 'Phone',
    'allFieldsRequired': 'All fields are required',
    'enterValidEmail': 'Enter a valid email address',
    'alreadyHaveAccount': 'Already have an account?  ',

    'profileTitle': 'Profile',
    'totalDeliveries': 'Total Deliveries',
    'changePassword': 'Change Password',
    'logOut': 'Log out',
    'logOutConfirm': 'Are you sure you want to log out?',
    'cancel': 'Cancel',
    'currentPassword': 'Current password',
    'newPassword': 'New password',
    'confirmNewPassword': 'Confirm new password',
    'fieldRequired': 'Required',
    'atLeastSixCharacters': 'At least 6 characters',
    'passwordsDoNotMatch': 'Passwords do not match',
    'updatePassword': 'Update Password',
    'passwordUpdated': 'Password updated',

    'myOrders': 'My Orders',
    'tabAll': 'All',
    'tabReturned': 'Returned',
    'tabCompleted': 'Completed',
    'totalEarned': 'Total Earned',
    'yourEarnings': 'Your Earnings',
    'filterAll': 'All',
    'areaOther': 'Other',
    'searchPhoneNumber': 'Search phone number, e.g. 70218542',
    'noOrderMatching': 'No order matching {n} here',
    'tryOtherTabs': 'Check the other tabs',
    'orderNotInYourList': 'This order is not in your list',
    'noOrdersAssigned': 'No orders assigned yet',
    'noReturnedOrders': 'No returned orders',
    'noDeliveriesToday': 'No deliveries completed today',
    'completedWillAppearHere': 'Completed deliveries will appear here',
    'pullDownToRefresh': 'Pull down to refresh',
    'pickup': 'Pickup',
    'delivery': 'Delivery',
    'statusActive': 'Active',
    'statusPending': 'Pending',
    'statusDelivered': 'Delivered',

    'orderDetails': 'Order Details',
    'noOrderSelected': 'No order selected',
    'customerInformation': 'Customer Information',
    'noWhatsAppNumber': 'This customer has no valid WhatsApp number',
    'orderSummary': 'Order Summary',
    'customerNotes': 'Customer Notes',
    'driverNote': 'Driver Note',
    'addNote': 'Add note',
    'editNote': 'Edit',
    'noDriverNoteYet': 'No note yet — tap to add one.',
    'driverNoteHint': 'e.g. gate code, best time to call, where you left it',
    'save': 'Save',
    'noteSaved': 'Note saved',
    'noteSaveFailed': 'Could not save note',
    'paid': 'Paid',
    'unpaidCod': 'Unpaid (COD)',
    'prepaid': 'Prepaid',
    'prepaidNoCash': 'Paid online — no cash collected',
    'paidByWhish': 'Paid by Whish',
    'deliveredPaidByWhish': 'Delivered & Paid by Whish',
    'whishConfirmTitle': 'Delivered and paid by Whish?',
    'whishConfirmBody':
        'Only confirm after the Whish transfer has gone through. '
        'This marks the order delivered, records the payment in Shopify, '
        'and the amount will not count in your collected cash.',
    'confirm': 'Confirm',
    'whishPaymentRecorded': 'Order delivered — paid by Whish',
    'pickupLocation': 'Pickup Location',
    'deliveryLocation': 'Delivery Location',
    'you': 'You',
    'startDelivery': 'Start Delivery',
    'markAsReturned': 'Mark as Returned',
    'markAsDelivered': 'Mark as Delivered',
    'gettingLocationRetry': 'Getting your current location… try again in a moment.',
    'orderMarkedReturned': 'Order marked as returned',
    'orderMarkedDelivered': 'Order marked as delivered',
    'statusSyncFailed': 'Status sync failed',
    'statusQueuedOffline':
        'Saved on your phone — it will reach the dashboard when you are back online',
    'pendingSyncOne': '1 finished order is waiting to sync',
    'pendingSyncMany': 'finished orders are waiting to sync',

    'currentLocation': 'Current Location',
    'youAreHere': 'You are here!',
    'gettingYourLocation': 'Getting your location....',
    'mapsNotConfigured': 'Google Maps is not configured for web.\n'
        'Run with --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY',

    'ongoingOrder': 'Ongoing Order',
    'newOrderAvailable': 'New Order Available',
    'pickupLabel': 'Pickup - ',
    'deliveryLabel': 'Delivery - ',
    'viewOngoingOrder': 'View ongoing order',
    'viewOrderDetails': 'View order details',

    'shipmentTitle': 'Shipment',
    'deliveries': 'Deliveries',
    'deliveryHistory': 'Delivery History',
    'noDeliveriesYet': 'No deliveries yet',
    'retry': 'Retry',
    'periodDay': 'Day',
    'periodWeek': 'Week',
    'periodMonth': 'Month',
    'today': 'Today',
    'yesterday': 'Yesterday',

    'trackingSetupTitle': 'Keep tracking alive',
    'trackingSetupIntro':
        'Your phone can stop the app from sharing your location while you are '
        'using Maps or talking to a customer. These settings stop that from '
        'happening. You only need to do this once.',
    'trackingBannerFix': 'Fix',
    'trackingBannerIncomplete':
        'Your location may stop when you leave the app.',
    'trackingBannerStopped':
        'Your location stopped reaching the office. Check your settings.',
    'trackingStepLocationTitle': 'Allow location all the time',
    'trackingStepLocationBody':
        'Choose "Allow all the time", not "Only while using the app". Without '
        'it your location stops the moment you open another app.',
    'trackingStepBatteryTitle': 'Turn off battery optimisation',
    'trackingStepBatteryBody':
        'Set this app to Unrestricted so the phone does not put it to sleep '
        'while you are driving.',
    'trackingStepAutostartTitle': 'Allow background running',
    'trackingStepRecentsTitle': 'Lock the app in recents',
    'trackingStepRecentsBody':
        'Open your recent apps, then hold this app and tap the padlock. A '
        'locked app is not closed when the phone clears memory.',
    'trackingStepGpsTitle': 'Turn on GPS',
    'trackingStepGpsBody':
        'Location is switched off on this phone. Turn it on to start sharing '
        'your position.',
    'trackingOpenSettings': 'Open settings',
    'trackingGrant': 'Allow',
    'trackingDone': 'Done',
    'trackingAllSet': 'All set — your location will keep working.',
    'trackingRecheck': 'Check again',
    'trackingFinish': 'Finish',

    // Per-vendor wording for the background-running step. Transsion first: it
    // is the one Infinix and Tecno drivers need.
    'trackingAutostart_transsion':
        'Tap below, then turn this app ON in the auto-start list. Also open '
        'Phone Manager and remove this app from Power Marathon or the app '
        'freezer, so it is not closed in the background.',
    'trackingAutostart_xiaomi':
        'Tap below and turn Autostart ON for this app. Then, under Battery '
        'saver, set it to No restrictions.',
    'trackingAutostart_oppo':
        'Tap below and allow this app to start in the background, then set '
        'its battery usage to Allow background running.',
    'trackingAutostart_vivo':
        'Tap below and allow this app to start in the background, then allow '
        'high background power use.',
    'trackingAutostart_huawei':
        'Tap below, then set this app to Manage manually and turn on '
        'Auto-launch, Secondary launch and Run in background.',
    'trackingAutostart_generic':
        'Tap below and allow this app to run in the background.',

    'toastSuccess': 'Successful',
    'toastFail': 'Fail',
  };

  static const Map<String, String> _ar = {
    'language': 'اللغة',
    'english': 'English',
    'arabic': 'العربية',

    'navHome': 'الرئيسية',
    'navOrders': 'الطلبات',
    'navShipment': 'الشحنات',
    'navProfile': 'حسابي',

    'driverPortal': 'بوابة السائق',
    'welcomeBack': 'أهلاً بعودتك',
    'signIn': 'تسجيل الدخول',
    'enterCredentials': 'أدخل بياناتك للمتابعة',
    'email': 'البريد الإلكتروني',
    'password': 'كلمة المرور',
    'logIn': 'تسجيل الدخول',
    'dontHaveAccount': 'ليس لديك حساب؟  ',
    'signUp': 'إنشاء حساب',
    'emailPasswordRequired': 'البريد الإلكتروني وكلمة المرور مطلوبان',

    'createAccount': 'إنشاء حساب',
    'joinDeliveryTeam': 'انضم إلى فريق التوصيل',
    'fillYourDetails': 'أدخل بياناتك للبدء',
    'fullName': 'الاسم الكامل',
    'phone': 'رقم الهاتف',
    'allFieldsRequired': 'جميع الحقول مطلوبة',
    'enterValidEmail': 'أدخل بريداً إلكترونياً صالحاً',
    'alreadyHaveAccount': 'لديك حساب بالفعل؟  ',

    'profileTitle': 'حسابي',
    'totalDeliveries': 'إجمالي التوصيلات',
    'changePassword': 'تغيير كلمة المرور',
    'logOut': 'تسجيل الخروج',
    'logOutConfirm': 'هل أنت متأكد أنك تريد تسجيل الخروج؟',
    'cancel': 'إلغاء',
    'currentPassword': 'كلمة المرور الحالية',
    'newPassword': 'كلمة المرور الجديدة',
    'confirmNewPassword': 'تأكيد كلمة المرور الجديدة',
    'fieldRequired': 'مطلوب',
    'atLeastSixCharacters': '6 أحرف على الأقل',
    'passwordsDoNotMatch': 'كلمتا المرور غير متطابقتين',
    'updatePassword': 'تحديث كلمة المرور',
    'passwordUpdated': 'تم تحديث كلمة المرور',

    'myOrders': 'طلباتي',
    'tabAll': 'الكل',
    'tabReturned': 'مرتجعة',
    'tabCompleted': 'مكتملة',
    'totalEarned': 'إجمالي الأرباح',
    'yourEarnings': 'أرباحك',
    'filterAll': 'الكل',
    'areaOther': 'أخرى',
    'searchPhoneNumber': 'ابحث برقم الهاتف، مثال 70218542',
    'noOrderMatching': 'لا يوجد طلب مطابق لـ {n} هنا',
    'tryOtherTabs': 'تحقّق من التبويبات الأخرى',
    'orderNotInYourList': 'هذا الطلب ليس في قائمتك',
    'noOrdersAssigned': 'لا توجد طلبات مسندة بعد',
    'noReturnedOrders': 'لا توجد طلبات مرتجعة',
    'noDeliveriesToday': 'لم تكتمل أي توصيلة اليوم',
    'completedWillAppearHere': 'ستظهر التوصيلات المكتملة هنا',
    'pullDownToRefresh': 'اسحب للأسفل للتحديث',
    'pickup': 'الاستلام',
    'delivery': 'التوصيل',
    'statusActive': 'جارية',
    'statusPending': 'قيد الانتظار',
    'statusDelivered': 'تم التوصيل',

    'orderDetails': 'تفاصيل الطلب',
    'noOrderSelected': 'لم يتم اختيار أي طلب',
    'customerInformation': 'معلومات العميل',
    'noWhatsAppNumber': 'لا يوجد رقم واتساب صالح لهذا الزبون',
    'orderSummary': 'ملخص الطلب',
    'customerNotes': 'ملاحظات العميل',
    'driverNote': 'ملاحظة السائق',
    'addNote': 'إضافة ملاحظة',
    'editNote': 'تعديل',
    'noDriverNoteYet': 'لا توجد ملاحظة بعد — اضغط للإضافة.',
    'driverNoteHint': 'مثال: رمز البوابة، أفضل وقت للاتصال، مكان تسليم الطلب',
    'save': 'حفظ',
    'noteSaved': 'تم حفظ الملاحظة',
    'noteSaveFailed': 'تعذّر حفظ الملاحظة',
    'paid': 'مدفوع',
    'unpaidCod': 'غير مدفوع (الدفع عند الاستلام)',
    'prepaid': 'مدفوع مسبقاً',
    'prepaidNoCash': 'تم الدفع عبر الإنترنت — لا يوجد مبلغ مُحصَّل',
    'paidByWhish': 'مدفوع عبر ويش',
    'deliveredPaidByWhish': 'تم التوصيل والدفع عبر ويش',
    'whishConfirmTitle': 'تم التوصيل والدفع عبر ويش؟',
    'whishConfirmBody':
        'أكّد فقط بعد وصول تحويل ويش. سيتم تسجيل الطلب كمُوصَّل وتسجيل '
        'الدفعة في شوبيفاي، ولن يُحتسب المبلغ ضمن المبلغ النقدي الذي جمعته.',
    'confirm': 'تأكيد',
    'whishPaymentRecorded': 'تم توصيل الطلب — مدفوع عبر ويش',
    'pickupLocation': 'موقع الاستلام',
    'deliveryLocation': 'موقع التوصيل',
    'you': 'أنت',
    'startDelivery': 'بدء التوصيل',
    'markAsReturned': 'تحديد كمرتجع',
    'markAsDelivered': 'تحديد كتم التوصيل',
    'gettingLocationRetry': 'جارٍ تحديد موقعك الحالي… حاول مرة أخرى بعد لحظات.',
    'orderMarkedReturned': 'تم تحديد الطلب كمرتجع',
    'orderMarkedDelivered': 'تم تحديد الطلب كتم التوصيل',
    'statusSyncFailed': 'فشلت مزامنة الحالة',
    'statusQueuedOffline':
        'تم الحفظ على هاتفك — سيصل إلى لوحة التحكم عند عودة الاتصال',
    'pendingSyncOne': 'طلب واحد منتهٍ بانتظار المزامنة',
    'pendingSyncMany': 'طلبات منتهية بانتظار المزامنة',

    'currentLocation': 'الموقع الحالي',
    'youAreHere': 'أنت هنا!',
    'gettingYourLocation': 'جارٍ تحديد موقعك....',
    'mapsNotConfigured': 'خرائط Google غير مهيأة للويب.\n'
        'شغّل التطبيق مع ‎--dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY',

    'ongoingOrder': 'طلب جارٍ',
    'newOrderAvailable': 'طلب جديد متاح',
    'pickupLabel': 'الاستلام - ',
    'deliveryLabel': 'التوصيل - ',
    'viewOngoingOrder': 'عرض الطلب الجاري',
    'viewOrderDetails': 'عرض تفاصيل الطلب',

    'shipmentTitle': 'الشحنات',
    'deliveries': 'التوصيلات',
    'deliveryHistory': 'سجل التوصيلات',
    'noDeliveriesYet': 'لا توجد توصيلات بعد',
    'retry': 'إعادة المحاولة',
    'periodDay': 'يوم',
    'periodWeek': 'أسبوع',
    'periodMonth': 'شهر',
    'today': 'اليوم',
    'yesterday': 'أمس',

    'trackingSetupTitle': 'حافظ على عمل التتبع',
    'trackingSetupIntro':
        'قد يوقف هاتفك مشاركة موقعك أثناء استخدامك للخرائط أو حديثك مع الزبون. '
        'هذه الإعدادات تمنع ذلك. تحتاج إلى ضبطها مرة واحدة فقط.',
    'trackingBannerFix': 'إصلاح',
    'trackingBannerIncomplete': 'قد يتوقف موقعك عند خروجك من التطبيق.',
    'trackingBannerStopped': 'توقف وصول موقعك إلى المكتب. راجع الإعدادات.',
    'trackingStepLocationTitle': 'السماح بالموقع طوال الوقت',
    'trackingStepLocationBody':
        'اختر «السماح طوال الوقت» وليس «أثناء استخدام التطبيق فقط». بدون ذلك '
        'يتوقف موقعك فور فتحك تطبيقًا آخر.',
    'trackingStepBatteryTitle': 'إيقاف تحسين البطارية',
    'trackingStepBatteryBody':
        'اضبط هذا التطبيق على «غير مقيّد» حتى لا يوقفه الهاتف أثناء القيادة.',
    'trackingStepAutostartTitle': 'السماح بالعمل في الخلفية',
    'trackingStepRecentsTitle': 'ثبّت التطبيق في التطبيقات الأخيرة',
    'trackingStepRecentsBody':
        'افتح التطبيقات الأخيرة، ثم اضغط مطوّلًا على هذا التطبيق واضغط على '
        'القفل. التطبيق المقفل لا يُغلق عند تفريغ ذاكرة الهاتف.',
    'trackingStepGpsTitle': 'تشغيل GPS',
    'trackingStepGpsBody':
        'خدمة الموقع مغلقة على هذا الهاتف. شغّلها لبدء مشاركة موقعك.',
    'trackingOpenSettings': 'فتح الإعدادات',
    'trackingGrant': 'السماح',
    'trackingDone': 'تم',
    'trackingAllSet': 'كل شيء جاهز — سيستمر عمل موقعك.',
    'trackingRecheck': 'تحقق مرة أخرى',
    'trackingFinish': 'إنهاء',

    'trackingAutostart_transsion':
        'اضغط بالأسفل، ثم فعّل هذا التطبيق في قائمة التشغيل التلقائي. وافتح '
        'أيضًا مدير الهاتف واستثنِ التطبيق من Power Marathon أو مجمّد '
        'التطبيقات حتى لا يُغلق في الخلفية.',
    'trackingAutostart_xiaomi':
        'اضغط بالأسفل وفعّل «التشغيل التلقائي» لهذا التطبيق، ثم اضبط موفّر '
        'البطارية على «بلا قيود».',
    'trackingAutostart_oppo':
        'اضغط بالأسفل واسمح لهذا التطبيق بالعمل في الخلفية، ثم اضبط استهلاك '
        'البطارية على السماح بالعمل في الخلفية.',
    'trackingAutostart_vivo':
        'اضغط بالأسفل واسمح لهذا التطبيق بالعمل في الخلفية، ثم اسمح باستهلاك '
        'طاقة مرتفع في الخلفية.',
    'trackingAutostart_huawei':
        'اضغط بالأسفل، ثم اضبط التطبيق على «إدارة يدوية» وفعّل التشغيل '
        'التلقائي والتشغيل الثانوي والعمل في الخلفية.',
    'trackingAutostart_generic':
        'اضغط بالأسفل واسمح لهذا التطبيق بالعمل في الخلفية.',

    'toastSuccess': 'تم بنجاح',
    'toastFail': 'فشل',
  };
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales
          .any((l) => l.languageCode == locale.languageCode);

  // Strings are compiled into the app, so there is nothing async to wait for.
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

// Shorthand so screens can write `context.l10n.myOrders` instead of the longer
// `AppLocalizations.of(context).myOrders`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
