import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class BackendNotConfiguredException implements Exception {
  const BackendNotConfiguredException([
    this.message =
        'Supabase backend is not configured. Provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define-from-file=.env.supabase.json.',
  ]);
  final String message;

  @override
  String toString() => message;
}

class BackendFunctionException implements Exception {
  const BackendFunctionException({
    required this.message,
    this.code = 'internal',
    this.status = 500,
  });

  final String code;
  final String message;
  final int status;

  @override
  String toString() => message;
}

/// Centralized Supabase initialization and typed Edge Function caller.
/// Safe to reference in unit/widget tests when `Supabase.initialize` has not run.
class SupabaseService {
  const SupabaseService._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _publishableKeyEnv =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _anonKeyEnv =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static String get supabaseAnonKey =>
      _publishableKeyEnv.trim().isNotEmpty ? _publishableKeyEnv : _anonKeyEnv;
  static const String authRedirectUrl = String.fromEnvironment(
    'NOTED_AUTH_REDIRECT_URL',
    defaultValue: 'noted://app/auth-callback',
  );

  static bool _initialized = false;
  static SupabaseClient? _testClientOverride;

  static bool get isConfigured {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();
    return (url.startsWith('https://') || url.startsWith('http://')) &&
        key.isNotEmpty &&
        !key.startsWith('YOUR_');
  }

  static bool get isInitialized => _initialized || _testClientOverride != null;

  static void setTestClient(SupabaseClient? client) {
    _testClientOverride = client;
  }

  static Future<void> initialize() async {
    if (_initialized || !isConfigured) return;
    await Supabase.initialize(
      url: supabaseUrl.trim(),
      publishableKey: supabaseAnonKey.trim(),
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _initialized = true;
  }

  static SupabaseClient? get maybeClient {
    if (_testClientOverride != null) return _testClientOverride;
    if (!_initialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static SupabaseClient get client {
    final instance = maybeClient;
    if (instance == null) {
      throw const BackendNotConfiguredException();
    }
    return instance;
  }

  static Future<Map<String, dynamic>> invokeFunction(
    String functionName,
    Map<String, dynamic> body, {
    SupabaseClient? clientOverride,
  }) async {
    final activeClient = clientOverride ?? client;
    try {
      final response = await activeClient.functions.invoke(
        functionName,
        body: body,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return const {};
    } on FunctionException catch (error) {
      var code = 'internal';
      var message = error.reasonPhrase ?? 'Request could not be completed.';
      final details = error.details;
      Map<String, dynamic>? parsed;
      if (details is Map) {
        parsed = Map<String, dynamic>.from(details);
      } else if (details is String && details.trim().startsWith('{')) {
        try {
          parsed = Map<String, dynamic>.from(jsonDecode(details) as Map);
        } catch (_) {}
      }
      if (parsed != null) {
        code = (parsed['code'] ??
                (parsed['error'] is Map
                    ? (parsed['error'] as Map)['code']
                    : null) ??
                code)
            .toString();
        message = (parsed['message'] ??
                (parsed['error'] is Map
                    ? (parsed['error'] as Map)['message']
                    : null) ??
                message)
            .toString();
      }
      throw BackendFunctionException(
        code: code,
        message: message,
        status: error.status,
      );
    }
  }
}
