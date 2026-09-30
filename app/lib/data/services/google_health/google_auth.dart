// Google OAuth for the Google Health API ("Enhanced mode"): Authorization
// Code + PKCE via flutter_appauth (AppAuth generates the verifier/challenge),
// tokens in flutter_secure_storage (Android Keystore-backed).
//
// Scope set and endpoints follow Pulse `Core/API/GoogleAuth.swift`
// (Luraxx/pulse @ 1f8975c, Apache-2.0, see third_party/pulse/NOTICE), minus
// profile.readonly (we don't need it).
//
// Client ID comes from `--dart-define=GOOGLE_OAUTH_CLIENT_ID=<id>.apps.googleusercontent.com`.
// Without it the source reports available:false, "Not configured".
// Android redirect: the reversed client id scheme
// `com.googleusercontent.apps.<id>:/oauthredirect`; the SAME scheme must be
// passed to Gradle: `-PairlogOAuthScheme=com.googleusercontent.apps.<id>`
// (see android/app/build.gradle.kts), or override with
// `--dart-define=GOOGLE_OAUTH_REDIRECT=...`.

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../domain/models.dart';
import '../../common/source_exception.dart';
import '../../common/time.dart';
import 'ghapi_mapping.dart';

class GoogleOAuthConfig {
  const GoogleOAuthConfig({required this.clientId, this.redirectOverride = ''});

  factory GoogleOAuthConfig.fromEnvironment() => const GoogleOAuthConfig(
    clientId: String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID'),
    redirectOverride: String.fromEnvironment('GOOGLE_OAUTH_REDIRECT'),
  );

  final String clientId;
  final String redirectOverride;

  bool get configured => clientId.trim().isNotEmpty && redirectUrl != null;

  String? get redirectUrl {
    if (redirectOverride.isNotEmpty) return redirectOverride;
    const suffix = '.apps.googleusercontent.com';
    final id = clientId.trim();
    if (!id.endsWith(suffix)) return null;
    return 'com.googleusercontent.apps.${id.substring(0, id.length - suffix.length)}:/oauthredirect';
  }
}

abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore([this._s = const FlutterSecureStorage()]);
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);
}

class MemoryTokenStore implements TokenStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String? value) async =>
      value == null ? _m.remove(key) : _m[key] = value;
}

class GoogleAuth {
  GoogleAuth(
    this.config,
    this.store, {
    FlutterAppAuth? appAuth,
    this.clock = systemClock,
  }) : _appAuth = appAuth ?? const FlutterAppAuth();

  final GoogleOAuthConfig config;
  final TokenStore store;
  final FlutterAppAuth _appAuth;
  final Clock clock;

  static const _kAccess = 'ghapi.access_token';
  static const _kRefresh = 'ghapi.refresh_token';
  static const _kExpiry = 'ghapi.expiry_ms';

  static const _service = AuthorizationServiceConfiguration(
    authorizationEndpoint: GhMap.authorizationEndpoint,
    tokenEndpoint: GhMap.tokenEndpoint,
  );

  Future<bool> get signedIn async => (await store.read(_kRefresh)) != null;

  Future<bool> signIn() async {
    if (!config.configured) return false;
    final res = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        config.redirectUrl!,
        serviceConfiguration: _service,
        scopes: GhMap.scopes,
        // Ask for a refresh token every time (Google only returns one on
        // consent).
        promptValues: const ['consent'],
        additionalParameters: const {'access_type': 'offline'},
      ),
    );
    await _save(
      res.accessToken,
      res.refreshToken,
      res.accessTokenExpirationDateTime,
    );
    return res.refreshToken != null || res.accessToken != null;
  }

  Future<void> signOut() async {
    await store.write(_kAccess, null);
    await store.write(_kRefresh, null);
    await store.write(_kExpiry, null);
  }

  Future<void> _save(String? access, String? refresh, DateTime? expiry) async {
    if (access != null) await store.write(_kAccess, access);
    if (refresh != null) await store.write(_kRefresh, refresh);
    await store.write(
      _kExpiry,
      (expiry ?? clock().add(const Duration(minutes: 50)))
          .millisecondsSinceEpoch
          .toString(),
    );
  }

  /// A non-expired access token, refreshing when < 60 s remain.
  Future<String> validAccessToken() async {
    final access = await store.read(_kAccess);
    final exp = int.tryParse(await store.read(_kExpiry) ?? '');
    final fresh =
        exp != null &&
        DateTime.fromMillisecondsSinceEpoch(exp)
            .isAfter(clock().add(const Duration(seconds: 60)));
    if (access != null && fresh) return access;
    return refresh();
  }

  Future<String> refresh() async {
    final rt = await store.read(_kRefresh);
    if (rt == null || !config.configured) {
      throw SourceException(
        SourceKind.googleHealthApi,
        'oauth',
        'Not signed in',
        status: 'denied',
      );
    }
    try {
      final res = await _appAuth.token(
        TokenRequest(
          config.clientId,
          config.redirectUrl!,
          refreshToken: rt,
          serviceConfiguration: _service,
          scopes: GhMap.scopes,
        ),
      );
      await _save(
        res.accessToken,
        res.refreshToken,
        res.accessTokenExpirationDateTime,
      );
      final a = res.accessToken;
      if (a == null) throw StateError('No access token in refresh response');
      return a;
    } catch (e) {
      // Testing-mode clients' refresh tokens expire after 7 days.
      throw SourceException(
        SourceKind.googleHealthApi,
        'oauth',
        // Shown in the sync log: plain words, not the exception ($e).
        'Sign-in expired. Turn on Enhanced mode again in Data sources.',
        status: 'denied',
      );
    }
  }
}
