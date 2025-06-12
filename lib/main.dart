import 'dart:io';
import 'package:flutter/material.dart';
import 'my_dart_app.dart';

/// DEVELOPMENT ONLY: Overrides HTTP certificate validation (DO NOT USE IN PRODUCTION)
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    var client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  // Platform integration for desktop builds can be added here if needed.
  runApp(MyApp());
}