import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app state that manages onboarding and other app-wide state.
///
/// We introduce this as a ChangeNotifier so we can expand later without
/// changing the widget tree. Screens can continue to read directly from the
/// database for now while we migrate incrementally.
class AppState extends ChangeNotifier {
  bool _isOnboardingCompleted = false;
  bool _isInitialized = false;

  bool get isOnboardingCompleted => _isOnboardingCompleted;
  bool get isInitialized => _isInitialized;

  /// Initialize the app state by checking if onboarding has been completed
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    _isOnboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    _isInitialized = true;
    notifyListeners();
  }

  /// Mark onboarding as completed
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    _isOnboardingCompleted = true;
    notifyListeners();
  }

  /// Reset onboarding state (useful for testing)
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', false);
    _isOnboardingCompleted = false;
    notifyListeners();
  }
}
