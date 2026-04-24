import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/screen/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider( 
      providers: [ 
        ChangeNotifierProvider(create: (_)=> CurrentLocationProvider()),
        ChangeNotifierProvider(create: (_)=> DeliveryProvider()),
        // Added in this change:
        // AuthProvider stores JWT + driver profile and persists token.
        ChangeNotifierProvider(create: (_)=> AuthProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // Added in this change:
        // AuthGate decides whether to show Login/Signup or the main app.
        home: const AuthGate(),
      ),
    );
  }
}
