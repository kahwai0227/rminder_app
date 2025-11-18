import 'package:flutter/material.dart';

/// A simple global navigation service to allow showing dialogs from anywhere
/// using the root Navigator context.
class NavigationService {
  NavigationService._();
  static final NavigationService instance = NavigationService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
