// Test for RMinder app onboarding functionality
//
// Tests verify that the first-run experience works correctly:
// 1. Shows onboarding screen on first launch
// 2. Shows main app after onboarding completion
// 3. Provides access to tips screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rminder_app/main.dart';
import 'package:rminder_app/providers/app_state.dart';
import 'package:rminder_app/screens/onboarding_screen.dart';
import 'package:rminder_app/screens/tips_screen.dart';

void main() {
  group('Onboarding Tests', () {
    setUp(() {
      // Clear shared preferences before each test
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Shows onboarding screen on first launch', (WidgetTester tester) async {
      // Build our app and trigger a frame
      await tester.pumpWidget(const MyApp());
      
      // Wait for app initialization
      await tester.pumpAndSettle();

      // Verify that onboarding screen is shown
      expect(find.text('Welcome to RMinder!'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Learn More'), findsOneWidget);
    });

    testWidgets('Navigates to tips screen from onboarding', (WidgetTester tester) async {
      // Build our app and trigger a frame
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Tap the "Learn More" button
      await tester.tap(find.text('Learn More'));
      await tester.pumpAndSettle();

      // Verify that tips screen is shown
      expect(find.text('How to Use RMinder'), findsOneWidget);
      expect(find.text('1. Set Up Your Budget'), findsOneWidget);
    });

    testWidgets('Completes onboarding and shows main app', (WidgetTester tester) async {
      // Build our app and trigger a frame
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Tap the "Get Started" button
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      // Verify that main app is shown (should see bottom navigation)
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
    });

    testWidgets('Shows main app on subsequent launches', (WidgetTester tester) async {
      // Set onboarding as completed
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});

      // Build our app and trigger a frame
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Verify that main app is shown directly (no onboarding)
      expect(find.text('Welcome to RMinder!'), findsNothing);
      expect(find.text('Budget'), findsOneWidget);
    });

    testWidgets('Help button opens tips screen from main app', (WidgetTester tester) async {
      // Set onboarding as completed
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});

      // Build our app and trigger a frame
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Find and tap the help button
      await tester.tap(find.byIcon(Icons.help_outline).first);
      await tester.pumpAndSettle();

      // Verify that tips screen is shown
      expect(find.text('How to Use RMinder'), findsOneWidget);
    });
  });

  group('AppState Tests', () {
    test('AppState initializes with correct default values', () {
      final appState = AppState();
      expect(appState.isOnboardingCompleted, false);
      expect(appState.isInitialized, false);
    });

    test('AppState marks onboarding as completed', () async {
      SharedPreferences.setMockInitialValues({});
      final appState = AppState();
      
      await appState.initialize();
      expect(appState.isOnboardingCompleted, false);
      
      await appState.completeOnboarding();
      expect(appState.isOnboardingCompleted, true);
    });

    test('AppState reads existing onboarding state', () async {
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      final appState = AppState();
      
      await appState.initialize();
      expect(appState.isOnboardingCompleted, true);
      expect(appState.isInitialized, true);
    });
  });
}
