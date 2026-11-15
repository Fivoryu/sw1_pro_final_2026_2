import 'dart:convert';

import 'package:captura_mobile/data/models/staff_review.dart';
import 'package:captura_mobile/data/services/staff_reviews_api.dart';
import 'package:captura_mobile/domain/staff_reviews_controller.dart';
import 'package:captura_mobile/ui/reviews/staff_reviews_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_chat_backend.dart';

Map<String, Object?> _summary({
  double? average,
  int count = 0,
  int verified = 0,
  bool few = true,
}) => {
  'average': average,
  'count': count,
  'verified_count': verified,
  'few_ratings': few,
};

Map<String, Object?> _review(
  String id, {
  String? comment,
  bool verified = false,
  String? reply,
  bool reported = false,
}) => {
  'id': id,
  'listing_id': 'listing-1',
  'listing_rating': 4,
  'agency_rating': 5,
  'comment': comment,
  'verified': verified,
  'created_at': '2026-11-13T10:00:00Z',
  'updated_at': '2026-11-13T10:00:00Z',
  'agency_reply': reply,
  'agency_reply_at': null,
  'reported': reported,
};

/// Stand-in for `/api/v1/staff/reviews`.
class _FakeReviewsBackend {
  Map<String, Object?> page = {'summary': _summary(), 'reviews': <Object?>[]};
  final List<http.Request> requests = [];
  final List<Map<String, Object?>> bodies = [];
  int replyStatus = 204;
  int reportStatus = 201;
  bool offline = false;

  StaffReviewsApi get api =>
      StaffReviewsApi(baseUrl: chatBaseUrl, client: MockClient(_handle));

  http.Response _json(Object body, int code) => http.Response(
    jsonEncode(body),
    code,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    final path = request.url.path;
    if (path == '/api/v1/staff/reviews') return _json(page, 200);
    if (path.endsWith('/reply')) {
      bodies.add(jsonDecode(request.body) as Map<String, Object?>);
      if (replyStatus == 409) {
        return _json({
          'detail': 'The review already has a reply',
          'code': 'conflict',
        }, 409);
      }
      return http.Response('', replyStatus);
    }
    if (path.endsWith('/report')) {
      bodies.add(jsonDecode(request.body) as Map<String, Object?>);
      if (reportStatus == 409) {
        return _json({
          'detail': 'The review already has an open report',
          'code': 'conflict',
        }, 409);
      }
      return _json({'id': 'rep-1'}, reportStatus);
    }
    return http.Response('', 404);
  }
}

Future<StaffReviewsController> _controller(
  _FakeReviewsBackend backend, {
  String role = 'agency_admin',
}) async {
  final signed = await signedInChat(FakeChatBackend(), role: role);
  final controller = StaffReviewsController(
    api: backend.api,
    session: signed.session,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('staff review model', () {
    test('parses a review and rejects malformed data', () {
      final review = StaffReview.fromJson(
        _review('r1', comment: 'ok', reported: true),
      );
      expect(review.reported, isTrue);
      expect(review.withReply('Gracias').agencyReply, 'Gracias');
      expect(() => StaffReview.fromJson({'id': 1}), throwsFormatException);
      expect(() => StaffReviewList.fromJson(null), throwsFormatException);
    });
  });

  group('summary wording', () {
    test('few reviews keep the counts and no number', () {
      expect(
        staffRatingSummaryText(
          StaffRatingSummary.fromJson(_summary(count: 2, verified: 1)),
        ),
        'Pocas calificaciones (2 calificaciones, 1 verificada)',
      );
    });

    test('enough reviews show the average', () {
      expect(
        staffRatingSummaryText(
          StaffRatingSummary.fromJson(
            _summary(average: 3.4, count: 5, verified: 2, few: false),
          ),
        ),
        '★ 3.4 · 5 calificaciones, 2 verificadas',
      );
    });
  });

  group('StaffReviewsController', () {
    test('loads the agency reviews with the bearer token', () async {
      final backend = _FakeReviewsBackend()
        ..page = {
          'summary': _summary(count: 1),
          'reviews': [_review('r1', comment: 'Bien')],
        };
      final controller = await _controller(backend);

      await controller.load();

      expect(controller.state, ReviewsLoadState.ready);
      expect(controller.list?.reviews.single.comment, 'Bien');
      expect(
        backend.requests.single.headers['Authorization'],
        startsWith('Bearer '),
      );
    });

    test('an administrator replies once and the reply shows locally', () async {
      final backend = _FakeReviewsBackend()
        ..page = {
          'summary': _summary(count: 1),
          'reviews': [_review('r1')],
        };
      final controller = await _controller(backend);
      await controller.load();

      final replied = await controller.reply(
        controller.list!.reviews.single,
        '  Gracias  ',
      );

      expect(replied, isTrue);
      expect(backend.bodies.single, {'body': 'Gracias'});
      expect(controller.list!.reviews.single.agencyReply, 'Gracias');
    });

    test('an administrator reports a review', () async {
      final backend = _FakeReviewsBackend()
        ..page = {
          'summary': _summary(count: 1),
          'reviews': [_review('r1')],
        };
      final controller = await _controller(backend);
      await controller.load();

      final reported = await controller.report(
        controller.list!.reviews.single,
        'Es falsa',
      );

      expect(reported, isTrue);
      expect(controller.list!.reviews.single.reported, isTrue);
    });

    test('an agent can read but not reply or report', () async {
      final backend = _FakeReviewsBackend()
        ..page = {
          'summary': _summary(count: 1),
          'reviews': [_review('r1')],
        };
      final controller = await _controller(backend, role: 'agent');
      await controller.load();

      expect(controller.canModerate, isFalse);
      expect(
        await controller.reply(controller.list!.reviews.single, 'x'),
        isFalse,
      );
      expect(
        await controller.report(controller.list!.reviews.single, 'x'),
        isFalse,
      );
      expect(backend.bodies, isEmpty);
    });

    test('a second reply or report explains the conflict', () async {
      final backend = _FakeReviewsBackend()
        ..replyStatus = 409
        ..reportStatus = 409
        ..page = {
          'summary': _summary(count: 1),
          'reviews': [_review('r1')],
        };
      final controller = await _controller(backend);
      await controller.load();
      final review = controller.list!.reviews.single;

      expect(await controller.reply(review, 'x'), isFalse);
      expect(controller.message, 'Esta reseña ya tiene una respuesta.');
      expect(await controller.report(review, 'x'), isFalse);
      expect(controller.message, 'Esta reseña ya tiene un reporte abierto.');
      expect(controller.list!.reviews.single.agencyReply, isNull);
    });

    test('an offline load fails with a message and no list', () async {
      final backend = _FakeReviewsBackend()..offline = true;
      final controller = await _controller(backend);

      await controller.load();

      expect(controller.state, ReviewsLoadState.failed);
      expect(controller.list, isNull);
      expect(controller.message, isNotNull);
    });
  });

  group('StaffReviewsScreen', () {
    Future<StaffReviewsController> pump(
      WidgetTester tester,
      _FakeReviewsBackend backend, {
      String role = 'agency_admin',
    }) async {
      late StaffReviewsController controller;
      await tester.runAsync(
        () async => controller = await _controller(backend, role: role),
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffReviewsScreen(controller: controller)),
      );
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byKey(const ValueKey('reviews-summary')).evaluate().isNotEmpty)
          break;
      }
      return controller;
    }

    testWidgets('an administrator sees badges and the reply and report buttons', (
      tester,
    ) async {
      final backend = _FakeReviewsBackend()
        ..page = {
          'summary': _summary(count: 2, verified: 1),
          'reviews': [
            _review('r1', comment: 'Excelente', verified: true),
            _review('r2', reply: 'Gracias', reported: true),
          ],
        };
      await pump(tester, backend);

      expect(
        find.text(
          'Atención de la inmobiliaria: Pocas calificaciones (2 calificaciones, 1 verificada)',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('verified-r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reported-r2')), findsOneWidget);
      expect(find.text('Tu respuesta: Gracias'), findsOneWidget);
      expect(find.byKey(const ValueKey('reply-button-r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reply-button-r2')), findsNothing);
      expect(find.byKey(const ValueKey('report-button-r2')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an agent sees no reply or report buttons', (tester) async {
      final backend = _FakeReviewsBackend()
        ..page = {
          'summary': _summary(count: 1),
          'reviews': [_review('r1')],
        };
      await pump(tester, backend, role: 'agent');

      expect(find.byKey(const ValueKey('review-r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reply-button-r1')), findsNothing);
      expect(find.byKey(const ValueKey('report-button-r1')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('replying through the dialog records the reply', (
      tester,
    ) async {
      final backend = _FakeReviewsBackend()
        ..page = {
          'summary': _summary(count: 1),
          'reviews': [_review('r1')],
        };
      await pump(tester, backend);

      await tester.tap(find.byKey(const ValueKey('reply-button-r1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('review-text')),
        'Gracias por avisar',
      );
      await tester.tap(find.byKey(const ValueKey('review-text-submit')));
      final replied = find.text('Tu respuesta: Gracias por avisar');
      for (var i = 0; i < 60 && replied.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(backend.bodies.single, {'body': 'Gracias por avisar'});
      expect(find.text('Tu respuesta: Gracias por avisar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
