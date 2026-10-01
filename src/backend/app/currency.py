import re

from app.errors import ApiError

_ZERO_DECIMAL = frozenset(
    {
        "BIF",
        "CLP",
        "DJF",
        "GNF",
        "ISK",
        "JPY",
        "KMF",
        "KRW",
        "PYG",
        "RWF",
        "UGX",
        "UYI",
        "VND",
        "VUV",
        "XAF",
        "XOF",
        "XPF",
        "IDR",
    }
)
_THREE_DECIMAL = frozenset({"BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"})
_CODE = re.compile(r"^[A-Z][A-Z0-9]{2,11}$")


def normalize_currency(value: str) -> str:
    code = value.strip().upper()
    if not _CODE.fullmatch(code):
        raise ApiError(422, "invalid_currency", "Use a currency code of 3 to 12 letters or digits")
    return code


def default_minor_unit(code: str) -> int:
    if code in _ZERO_DECIMAL:
        return 0
    if code in _THREE_DECIMAL:
        return 3
    return 2
