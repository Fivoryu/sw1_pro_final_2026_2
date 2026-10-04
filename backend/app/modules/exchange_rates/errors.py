"""Domain errors for administered exchange rates and conversions."""


class InvalidExchangeRateError(ValueError):
    """Raised when an administered exchange rate is invalid."""


class MissingExchangeRateError(ValueError):
    """Raised when conversion requires a rate that has not been administered."""


class InvalidConversionError(ValueError):
    """Raised when conversion input is not a supported finite Decimal amount."""
