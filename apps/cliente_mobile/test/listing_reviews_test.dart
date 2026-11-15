import 'dart:convert';

import 'package:cliente_mobile/data/models/review_models.dart';
import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:cliente_mobile/data/services/customer_reviews_api.dart';
import 'package:cliente_mobile/domain/customer_session_controller.dart';
import 'package:cliente_mobile/domain/listing_reviews_controller.dart';
import 'package:cliente_mobile/ui/features/reviews/agency_reviews_screen.dart';
import 'package:cliente_mobile/ui/features/reviews/listing_reviews_section.dart';
import 'package:cliente_mobile/ui/features/reviews/review_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_customer_backend.dart';

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
  int listingRating = 4,
  int agencyRating = 5,
  String? comment,
  bool verified = false,
  String? reply,
}) => {
  'id': id,
  'listing_id': 'listing-1',
  'listing_rating': listingRating,
  'agency_rating': agencyRating,
  'comment': comment,
  'verified': verified,
  'created_at': '2026-11-13T10:00:00Z',
  'updated_at': '2026-11-13T10:00:00Z',
  'agency_reply': reply,
  'agency_reply_at': null,
};

/// Programmable stand-in for the review endpoints.
class _FakeReviewsBackend {
  Map<String, Object?> listing = {
    'agency_id': 'agency-1',
    'agency_name': 'Andina Inmuebles',
    'listing': _summary(),
    'agency': _summary(),
    'reviews': <Object?>[],
  };
  Map<String, Object?> agency = {
    'agency_name': 'Andina Inmuebles',
    'summary': _summary(),
    'reviews': <Object?>[],
  };
  Map<String, Object?> mine = {
    'can_review': true,
    'reason': null,
    'review': null,
  };
  int writeStatus = 201;
  final List<String> requests = [];
  final List<Map<String, Object?>> writes = [];
  bool offline = false;

  CustomerReviewsApi get api => CustomerReviewsApi(
    baseUrl: 'https://api.example.test',
    accessTokenProvider: () async => 'token',
    client: MockClient(_handle),
  );

  http.Response _json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (offline) throw http.ClientException('offline');
    final path = request.url.path;
    if (path == '/api/v1/listings/listing-1/reviews') {
      return _json(listing, 200);
    }
    if (path == '/api/v1/public/agencies/agency-1/reviews') {
      return _json(agency, 200);
    }
    if (path == '/api/v1/customer/reviews/listings/listing-1') {
      if (request.method == 'GET') return _json(mine, 200);
      if (writeStatus == 403) {
        return _json({'detail': 'no', 'code': 'forbidden'}, 403);
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      writes.add(body);
      final saved = _review(
        'r-new',
        listingRating: body['listing_rating']! as int,
        agencyRating: body['agency_rating']! as int,
        comment: body['comment'] as String?,
      );
      mine = {'can_review': true, 'reason': null, 'review': saved};
      return _json(saved, writeStatus);
    }
    return http.Response('', 404);
  }
}

Future<CustomerSessionController> _session(
  WidgetTester? tester, {
  required bool signedIn,
}) async {
  final session = CustomerSessionController(
    api: CustomerAuthApi(
      baseUrl: 'https://api.example.test',
      client: FakeCustomerBackend().client,
    ),
    tokenStore: InMemoryCustomerTokenStore(signedIn ? 'stored' : null),
  );
  if (tester != null) {
    await tester.runAsync(session.restore);
  } else {
    await session.restore();
  }
  return session;
}

void main() {
  group('review models', () {
    test('parse a summary, a review and an eligibility block', () {
      final summary = RatingSummary.fromJson(
        _summary(average: 3.4, count: 5, verified: 2, few: false),
      );
      expect(summary.average, 3.4);
      expect(summary.verifiedCount, 2);
      final mine = MyReview.fromJson({
        'can_review': false,
        'reason': 'awaiting_reply',
        'review': null,
      });
      expect(mine.block, ReviewBlock.awaitingReply);
      expect(Review.fromJson(_review('r1', comment: 'ok')).comment, 'ok');
    });

    test('reject malformed data', () {
      expect(
        () => RatingSummary.fromJson({'count': 'x'}),
        throwsFormatException,
      );
      expect(() => Review.fromJson({'id': 1}), throwsFormatException);
      expect(() => ListingReviews.fromJson(null), throwsFormatException);
    });
  });

  group('summary wording', () {
    test('few reviews show no number but keep the counts', () {
      expect(
        ratingSummaryText(
          RatingSummary.fromJson(_summary(count: 2, verified: 1)),
        ),
        'Pocas calificaciones (2 calificaciones, 1 verificada)',
      );
    });

    test('enough reviews show the average with both counts', () {
      expect(
        ratingSummaryText(
          RatingSummary.fromJson(
            _summary(average: 3.4, count: 5, verified: 2, few: false),
          ),
        ),
        '★ 3.4 · 5 calificaciones, 2 verificadas',
      );
    });

    test('no reviews says so', () {
      expect(
        ratingSummaryText(RatingSummary.fromJson(_summary())),
        'Sin calificaciones todavía',
      );
    });
  });

  group('ListingReviewsController', () {
    test('signed out: loads only the public ratings', () async {
      final backend = _FakeReviewsBackend();
      final controller = ListingReviewsController(
        api: backend.api,
        listingId: 'listing-1',
        isSignedIn: () => false,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.reviews?.agencyName, 'Andina Inmuebles');
      expect(controller.mine, isNull);
      expect(backend.requests, ['GET /api/v1/listings/listing-1/reviews']);
    });

    test('signed in: also loads the own review and eligibility', () async {
      final backend = _FakeReviewsBackend()
        ..mine = {
          'can_review': false,
          'reason': 'no_conversation',
          'review': null,
        };
      final controller = ListingReviewsController(
        api: backend.api,
        listingId: 'listing-1',
        isSignedIn: () => true,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.mine?.block, ReviewBlock.noConversation);
    });

    test('submit sends both ratings and reloads', () async {
      final backend = _FakeReviewsBackend();
      final controller = ListingReviewsController(
        api: backend.api,
        listingId: 'listing-1',
        isSignedIn: () => true,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final saved = await controller.submit(
        listingRating: 4,
        agencyRating: 5,
        comment: 'Muy bueno',
      );

      expect(saved, isTrue);
      expect(backend.writes.single, {
        'listing_rating': 4,
        'agency_rating': 5,
        'comment': 'Muy bueno',
      });
      expect(controller.mine?.review?.listingRating, 4);
    });

    test('a 403 explains that the customer cannot rate yet', () async {
      final backend = _FakeReviewsBackend()..writeStatus = 403;
      final controller = ListingReviewsController(
        api: backend.api,
        listingId: 'listing-1',
        isSignedIn: () => true,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final saved = await controller.submit(listingRating: 4, agencyRating: 5);

      expect(saved, isFalse);
      expect(controller.message, 'Todavía no podés calificar este inmueble.');
    });

    test('an offline load reports a safe message', () async {
      final backend = _FakeReviewsBackend()..offline = true;
      final controller = ListingReviewsController(
        api: backend.api,
        listingId: 'listing-1',
        isSignedIn: () => false,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.reviews, isNull);
      expect(controller.message, isNotNull);
    });
  });

  group('ListingReviewsSection', () {
    Future<void> pump(
      WidgetTester tester,
      _FakeReviewsBackend backend, {
      required bool signedIn,
    }) async {
      final session = await _session(tester, signedIn: signedIn);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListingReviewsSection(
                api: backend.api,
                listingId: 'listing-1',
                sessionController: session,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find
            .byKey(const ValueKey('listing-rating-summary'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
    }

    testWidgets('shows both summaries, the verified badge and the reply', (
      tester,
    ) async {
      final backend = _FakeReviewsBackend()
        ..listing = {
          'agency_id': 'agency-1',
          'agency_name': 'Andina Inmuebles',
          'listing': _summary(average: 3.4, count: 5, verified: 1, few: false),
          'agency': _summary(count: 2),
          'reviews': [
            _review(
              'r1',
              comment: 'Excelente',
              verified: true,
              reply: 'Gracias',
            ),
          ],
        };
      await pump(tester, backend, signedIn: false);

      expect(
        find.text('Inmueble: ★ 3.4 · 5 calificaciones, 1 verificada'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Atención de Andina Inmuebles: Pocas calificaciones (2 calificaciones, 0 verificadas)',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('verified-r1')), findsOneWidget);
      expect(
        find.text('Respuesta de la inmobiliaria: Gracias'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('review-sign-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-review-form')), findsNothing);
    });

    testWidgets('a customer who has not chatted is told to chat first', (
      tester,
    ) async {
      final backend = _FakeReviewsBackend()
        ..mine = {
          'can_review': false,
          'reason': 'no_conversation',
          'review': null,
        };
      await pump(tester, backend, signedIn: true);

      expect(find.byKey(const ValueKey('review-blocked')), findsOneWidget);
      expect(find.textContaining('Chateá con la inmobiliaria'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-review-form')), findsNothing);
    });

    testWidgets('an eligible customer rates through the form', (tester) async {
      final backend = _FakeReviewsBackend();
      await pump(tester, backend, signedIn: true);

      await tester.tap(find.byKey(const ValueKey('open-review-form')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('review-unverified-note')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('review-submit')));
      await tester.pump();
      expect(find.byKey(const ValueKey('review-error')), findsOneWidget);
      expect(backend.writes, isEmpty);

      await tester.tap(find.byKey(const ValueKey('listing-star-4')));
      await tester.tap(find.byKey(const ValueKey('agency-star-5')));
      await tester.enterText(
        find.byKey(const ValueKey('review-comment')),
        'Muy bueno',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review-submit')));
      for (var i = 0; i < 30 && backend.writes.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(backend.writes.single['listing_rating'], 4);
      expect(backend.writes.single['agency_rating'], 5);
      expect(find.text('Editar mi calificación'), findsOneWidget);
    });

    testWidgets('the agency profile lists every review', (tester) async {
      final backend = _FakeReviewsBackend()
        ..agency = {
          'agency_name': 'Andina Inmuebles',
          'summary': _summary(average: 4.0, count: 3, few: false),
          'reviews': [_review('r1', comment: 'Rápidos'), _review('r2')],
        };
      await tester.pumpWidget(
        MaterialApp(
          home: AgencyReviewsScreen(
            api: backend.api,
            agencyId: 'agency-1',
            agencyName: 'Andina Inmuebles',
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find
            .byKey(const ValueKey('agency-profile-summary'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      expect(
        find.text('Atención: ★ 4.0 · 3 calificaciones, 0 verificadas'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('review-r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('review-r2')), findsOneWidget);
    });
  });
}
