/// Customer identity returned by the public customer authentication API.
class CustomerIdentity {
  const CustomerIdentity({required this.id, required this.email});

  final String id;
  final String email;
}

/// Access and refresh tokens returned by login and refresh.
class CustomerTokenPair {
  const CustomerTokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final Duration accessExpiresIn;
}
