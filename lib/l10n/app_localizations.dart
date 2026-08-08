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
  String tabPending(int count) => '${_t('tabPending')} ($count)';
  String tabReturned(int count) => '${_t('tabReturned')} ($count)';
  String tabCompleted(int count) => '${_t('tabCompleted')} ($count)';
  String get totalEarned => _t('totalEarned');
  String get completed => _t('completed');
  String get inProgress => _t('inProgress');
  String get filterAll => _t('filterAll');
  String get areaOther => _t('areaOther');
  String get noOrdersAssigned => _t('noOrdersAssigned');
  String get noPendingOrders => _t('noPendingOrders');
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
  String get orderSummary => _t('orderSummary');
  String get paid => _t('paid');
  String get unpaidCod => _t('unpaidCod');
  String get pickupLocation => _t('pickupLocation');
  String get deliveryLocation => _t('deliveryLocation');
  String get you => _t('you');
  String get startDelivery => _t('startDelivery');
  String get markAsReturned => _t('markAsReturned');
  String get markAsDelivered => _t('markAsDelivered');
  String get gettingLocationRetry => _t('gettingLocationRetry');
  String get deliveryStartedSharing => _t('deliveryStartedSharing');
  String get orderMarkedReturned => _t('orderMarkedReturned');
  String get orderMarkedDelivered => _t('orderMarkedDelivered');
  String statusSyncFailed(String error) => '${_t('statusSyncFailed')}: $error';

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
    'tabPending': 'Pending',
    'tabReturned': 'Returned',
    'tabCompleted': 'Completed',
    'totalEarned': 'Total Earned',
    'completed': 'Completed',
    'inProgress': 'In Progress',
    'filterAll': 'All',
    'areaOther': 'Other',
    'noOrdersAssigned': 'No orders assigned yet',
    'noPendingOrders': 'No pending orders',
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
    'orderSummary': 'Order Summary',
    'paid': 'Paid',
    'unpaidCod': 'Unpaid (COD)',
    'pickupLocation': 'Pickup Location',
    'deliveryLocation': 'Delivery Location',
    'you': 'You',
    'startDelivery': 'Start Delivery',
    'markAsReturned': 'Mark as Returned',
    'markAsDelivered': 'Mark as Delivered',
    'gettingLocationRetry': 'Getting your current location… try again in a moment.',
    'deliveryStartedSharing': 'Delivery started. Your location is now being shared.',
    'orderMarkedReturned': 'Order marked as returned',
    'orderMarkedDelivered': 'Order marked as delivered',
    'statusSyncFailed': 'Status sync failed',

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
    'tabPending': 'قيد الانتظار',
    'tabReturned': 'مرتجعة',
    'tabCompleted': 'مكتملة',
    'totalEarned': 'إجمالي الأرباح',
    'completed': 'المكتملة',
    'inProgress': 'قيد التنفيذ',
    'filterAll': 'الكل',
    'areaOther': 'أخرى',
    'noOrdersAssigned': 'لا توجد طلبات مسندة بعد',
    'noPendingOrders': 'لا توجد طلبات قيد الانتظار',
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
    'orderSummary': 'ملخص الطلب',
    'paid': 'مدفوع',
    'unpaidCod': 'غير مدفوع (الدفع عند الاستلام)',
    'pickupLocation': 'موقع الاستلام',
    'deliveryLocation': 'موقع التوصيل',
    'you': 'أنت',
    'startDelivery': 'بدء التوصيل',
    'markAsReturned': 'تحديد كمرتجع',
    'markAsDelivered': 'تحديد كتم التوصيل',
    'gettingLocationRetry': 'جارٍ تحديد موقعك الحالي… حاول مرة أخرى بعد لحظات.',
    'deliveryStartedSharing': 'بدأ التوصيل. تتم مشاركة موقعك الآن.',
    'orderMarkedReturned': 'تم تحديد الطلب كمرتجع',
    'orderMarkedDelivered': 'تم تحديد الطلب كتم التوصيل',
    'statusSyncFailed': 'فشلت مزامنة الحالة',

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
