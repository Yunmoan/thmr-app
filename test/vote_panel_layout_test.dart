import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/listen/widgets/vote_panel.dart';

final _station = StationStatus.fromJson({
  'station': {'id': 'test', 'name': '电台'},
  'current': {'trackId': 'track', 'startedAtMs': 100, 'title': '曲目'},
});
VoteStatus _vote(
        {int threshold = 3, bool actionTaken = false, bool active = true}) =>
    VoteStatus.fromJson({
      'stationId': 'test',
      'active': active,
      'current': {'trackId': 'track', 'startedAtMs': 100},
      'round': {'votes': 1, 'threshold': threshold, 'actionTaken': actionTaken},
    });

void main() {
  for (final width in [280.0, 360.0, 700.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('vote slots stay in place at $width px and $scale x text',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final pending = Completer<VoteStatus>();
        Future<VoteStatus> response = pending.future;
        final container = ProviderContainer(overrides: [
          voteStatusProvider.overrideWith((ref) => response),
        ]);
        var disposed = false;
        addTearDown(() {
          if (!disposed) container.dispose();
        });
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [
              ThmrTokens.resolve(AccentTheme.cirno, Brightness.dark)
            ]),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                VotePanel(status: _station),
                const SizedBox(key: ValueKey('after-vote'), height: 20),
              ]),
            ))),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull);
        final bounds = tester.getRect(find.byType(VotePanel));
        final button = tester.getRect(find.byType(FilledButton));
        final progress = tester.getRect(find.byType(LinearProgressIndicator));
        final below = tester.getRect(find.byKey(const ValueKey('after-vote')));
        void unchanged() {
          expect(tester.getRect(find.byType(VotePanel)), bounds);
          expect(tester.getRect(find.byType(FilledButton)), button);
          expect(
              tester.getRect(find.byType(LinearProgressIndicator)), progress);
          expect(
              tester.getRect(find.byKey(const ValueKey('after-vote'))), below);
          expect(tester.takeException(), isNull);
        }

        pending.complete(_vote());
        await tester.pumpAndSettle();
        unchanged();
        for (final value in [
          _vote(threshold: 0),
          _vote(actionTaken: true),
          _vote(active: false),
          _vote()
        ]) {
          response = Future.value(value);
          container.invalidate(voteStatusProvider);
          await tester.pumpAndSettle();
          unchanged();
        }
        final failure = Completer<VoteStatus>();
        response = failure.future;
        container.invalidate(voteStatusProvider);
        await tester.pumpAndSettle();
        failure.completeError(Exception('offline'));
        await tester.pumpAndSettle();
        unchanged();
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        disposed = true;
      });
    }
  }
}
