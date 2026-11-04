import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/account/account_screen.dart';

class _FirstLoginAuthController extends AuthController {
  @override
  Future<void> signInWithToken(String token) async {
    state = state.copyWith(
      user: const ThmrUser(
        id: '1',
        naidsId: '1',
        username: 'first-login',
        nickname: '',
        email: 'first@example.com',
        realnameVerified: false,
        createdAt: null,
        needsNickname: true,
      ),
    );
  }
}

void main() {
  testWidgets(
      'first login prompt opens nickname editor after account card changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FirstLoginAuthController()),
        metaProvider.overrideWith((ref) async => const ThmrMeta(
              version: 'test',
              natayarkConfigured: true,
              voteThreshold: 0,
              maxPerUser: 0,
              maxItemsPerCollection: 0,
            )),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThmrTheme.light(),
        home: const Scaffold(body: AccountScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('使用 Natayark 账号登录'));
    navigatorKey.currentState!.pop('test-token');
    await tester.pumpAndSettle();
    expect(find.text('去设置'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
