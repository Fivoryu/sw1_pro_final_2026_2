from __future__ import annotations


class QuoteApiError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        *,
        field_errors: list[dict[str, str]] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(code)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.field_errors = field_errors or []
        self.headers = headers or {}


class QuoteNotFoundError(Exception):
    """The requested quote or visible listing does not exist."""


class QuoteOfferVersionMismatchError(Exception):
    """The quote was created for a catalog version that is no longer current."""


class QuoteExpiredError(Exception):
    """The quote TTL has elapsed."""


class InvalidQuoteExtrasError(Exception):
    """Selected extras are duplicated or do not belong to the target listing."""


class UnsupportedRateLimitDialectError(Exception):
    """The database dialect cannot safely serialize quote rate-limit attempts."""


class InvalidListingTransitionError(Exception):
    """The requested listing action does not match its current state."""
