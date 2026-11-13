/// Average of a set of ratings. With fewer than three reviews there is no
/// average, and the screen says there are few ratings instead.
class StaffRatingSummary {
  const StaffRatingSummary({
    required this.average,
    required this.count,
    required this.verifiedCount,
    required this.fewRatings,
  });

  factory StaffRatingSummary.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        (json['average'] != null && json['average'] is! num) ||
        json['count'] is! int ||
        json['verified_count'] is! int ||
        json['few_ratings'] is! bool) {
      throw const FormatException('Rating summary is invalid');
    }
    return StaffRatingSummary(
      average: (json['average'] as num?)?.toDouble(),
      count: json['count']! as int,
      verifiedCount: json['verified_count']! as int,
      fewRatings: json['few_ratings']! as bool,
    );
  }

  final double? average;
  final int count;
  final int verifiedCount;
  final bool fewRatings;
}

/// A review of the agency's listings. It never identifies the customer.
class StaffReview {
  const StaffReview({
    required this.id,
    required this.listingId,
    required this.listingRating,
    required this.agencyRating,
    required this.comment,
    required this.verified,
    required this.createdAt,
    required this.agencyReply,
    required this.reported,
  });

  factory StaffReview.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['listing_id'] is! String ||
        json['listing_rating'] is! int ||
        json['agency_rating'] is! int ||
        (json['comment'] != null && json['comment'] is! String) ||
        json['verified'] is! bool ||
        json['created_at'] is! String ||
        (json['agency_reply'] != null && json['agency_reply'] is! String) ||
        json['reported'] is! bool) {
      throw const FormatException('Review fields are invalid');
    }
    return StaffReview(
      id: json['id']! as String,
      listingId: json['listing_id']! as String,
      listingRating: json['listing_rating']! as int,
      agencyRating: json['agency_rating']! as int,
      comment: json['comment'] as String?,
      verified: json['verified']! as bool,
      createdAt: DateTime.parse(json['created_at']! as String),
      agencyReply: json['agency_reply'] as String?,
      reported: json['reported']! as bool,
    );
  }

  final String id;
  final String listingId;
  final int listingRating;
  final int agencyRating;
  final String? comment;
  final bool verified;
  final DateTime createdAt;
  final String? agencyReply;
  final bool reported;

  /// The same review with a reply recorded.
  StaffReview withReply(String reply) => StaffReview(
    id: id,
    listingId: listingId,
    listingRating: listingRating,
    agencyRating: agencyRating,
    comment: comment,
    verified: verified,
    createdAt: createdAt,
    agencyReply: reply,
    reported: reported,
  );

  /// The same review marked as reported.
  StaffReview asReported() => StaffReview(
    id: id,
    listingId: listingId,
    listingRating: listingRating,
    agencyRating: agencyRating,
    comment: comment,
    verified: verified,
    createdAt: createdAt,
    agencyReply: agencyReply,
    reported: true,
  );
}

class StaffReviewList {
  const StaffReviewList({required this.summary, required this.reviews});

  factory StaffReviewList.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['reviews'] is! List<Object?>) {
      throw const FormatException('Review list is invalid');
    }
    return StaffReviewList(
      summary: StaffRatingSummary.fromJson(json['summary']),
      reviews: (json['reviews']! as List<Object?>)
          .map(StaffReview.fromJson)
          .toList(growable: false),
    );
  }

  final StaffRatingSummary summary;
  final List<StaffReview> reviews;
}
