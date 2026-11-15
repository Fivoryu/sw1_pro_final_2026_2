/// Average of a set of ratings. Fewer than three reviews carry no average:
/// the app then says there are few ratings instead of showing a number.
class RatingSummary {
  const RatingSummary({
    required this.average,
    required this.count,
    required this.verifiedCount,
    required this.fewRatings,
  });

  factory RatingSummary.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        (json['average'] != null && json['average'] is! num) ||
        json['count'] is! int ||
        json['verified_count'] is! int ||
        json['few_ratings'] is! bool) {
      throw const FormatException('Rating summary is invalid');
    }
    return RatingSummary(
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

/// A review as the API shows it: it never identifies the customer or who in
/// the agency answered.
class Review {
  const Review({
    required this.id,
    required this.listingId,
    required this.listingRating,
    required this.agencyRating,
    required this.comment,
    required this.verified,
    required this.createdAt,
    required this.agencyReply,
  });

  factory Review.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['listing_id'] is! String ||
        json['listing_rating'] is! int ||
        json['agency_rating'] is! int ||
        (json['comment'] != null && json['comment'] is! String) ||
        json['verified'] is! bool ||
        json['created_at'] is! String ||
        (json['agency_reply'] != null && json['agency_reply'] is! String)) {
      throw const FormatException('Review fields are invalid');
    }
    return Review(
      id: json['id']! as String,
      listingId: json['listing_id']! as String,
      listingRating: json['listing_rating']! as int,
      agencyRating: json['agency_rating']! as int,
      comment: json['comment'] as String?,
      verified: json['verified']! as bool,
      createdAt: DateTime.parse(json['created_at']! as String),
      agencyReply: json['agency_reply'] as String?,
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
}

List<Review> _reviews(Object? json) {
  if (json is! List<Object?>)
    throw const FormatException('Reviews are invalid');
  return json.map(Review.fromJson).toList(growable: false);
}

/// Public reviews of a listing, with the summary of its agency.
class ListingReviews {
  const ListingReviews({
    required this.agencyId,
    required this.agencyName,
    required this.listing,
    required this.agency,
    required this.reviews,
  });

  factory ListingReviews.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['agency_id'] is! String ||
        json['agency_name'] is! String) {
      throw const FormatException('Listing reviews are invalid');
    }
    return ListingReviews(
      agencyId: json['agency_id']! as String,
      agencyName: json['agency_name']! as String,
      listing: RatingSummary.fromJson(json['listing']),
      agency: RatingSummary.fromJson(json['agency']),
      reviews: _reviews(json['reviews']),
    );
  }

  final String agencyId;
  final String agencyName;
  final RatingSummary listing;
  final RatingSummary agency;
  final List<Review> reviews;
}

/// The agency's profile: its summary across all listings and every review.
class AgencyReviews {
  const AgencyReviews({
    required this.agencyName,
    required this.summary,
    required this.reviews,
  });

  factory AgencyReviews.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['agency_name'] is! String) {
      throw const FormatException('Agency reviews are invalid');
    }
    return AgencyReviews(
      agencyName: json['agency_name']! as String,
      summary: RatingSummary.fromJson(json['summary']),
      reviews: _reviews(json['reviews']),
    );
  }

  final String agencyName;
  final RatingSummary summary;
  final List<Review> reviews;
}

/// Why a customer cannot rate yet.
enum ReviewBlock { noConversation, awaitingReply, other }

/// The signed-in customer's review of a listing and whether they may write one.
class MyReview {
  const MyReview({
    required this.canReview,
    required this.block,
    required this.review,
  });

  factory MyReview.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['can_review'] is! bool ||
        (json['reason'] != null && json['reason'] is! String)) {
      throw const FormatException('My review is invalid');
    }
    final reason = json['reason'] as String?;
    return MyReview(
      canReview: json['can_review']! as bool,
      block: switch (reason) {
        null => null,
        'no_conversation' => ReviewBlock.noConversation,
        'awaiting_reply' => ReviewBlock.awaitingReply,
        _ => ReviewBlock.other,
      },
      review: json['review'] == null ? null : Review.fromJson(json['review']),
    );
  }

  final bool canReview;
  final ReviewBlock? block;
  final Review? review;
}
