// Mock file generated for subscription_screen_test.dart
// To regenerate: flutter pub run build_runner build --delete-conflicting-outputs

import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/data/models/user_info.dart';

// ignore_for_file: no_leading_underscores_for_local_identifiers

@GenerateMocks([AuthProvider])
void main() {}

// Manual mock implementation for AuthProvider
class MockAuthProvider extends Mock implements AuthProvider {
  @override
  bool isLoading = false;

  @override
  UserInfo? userInfo;

  @override
  String? errorMessage;

  @override
  AuthState state = AuthState.initial;

  @override
  bool get isAuthenticated => state == AuthState.authenticated;
}
