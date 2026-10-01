"""The parser decides what a person is asked to confirm.

A wrong amount that looks plausible is the worst failure here, so most of
these tests are about refusing to guess rather than about reading more.
"""

from app.parsing import parse_transaction_email


def parse(sender: str, subject: str, body: str, is_html: bool = False):
    return parse_transaction_email(sender=sender, subject=subject, body=body, is_html=is_html)


class TestAmount:
    def test_takes_the_purchase_not_the_balance(self) -> None:
        # The balance is the larger number, and it is not what was spent.
        result = parse(
            "noreply@bca.co.id",
            "Notifikasi Transaksi BCA",
            "Telah terjadi transaksi pembayaran sebesar Rp 286.500 "
            "di TOKO SERBA ADA. Saldo akhir Rp 4.213.500.",
        )
        assert result.amount_atomic == 286500

    def test_skips_an_admin_fee(self) -> None:
        result = parse(
            "noreply@bankmandiri.co.id",
            "Transaksi Mandiri",
            "Transfer sebesar Rp 1.500.000 berhasil. Biaya admin Rp 6.500.",
        )
        assert result.amount_atomic == 1500000

    def test_refuses_when_every_figure_is_a_balance(self) -> None:
        # Nothing here is a transaction, so proposing one would be a guess.
        result = parse(
            "noreply@bca.co.id",
            "Info Rekening",
            "Saldo rekening Anda Rp 5.000.000. Limit kartu Rp 10.000.000.",
        )
        assert result.amount_atomic is None
        assert "amount_not_found" in result.warnings

    def test_reads_an_amount_with_no_space(self) -> None:
        result = parse("noreply@ovo.id", "Pembayaran", "Pembayaran Rp75.000 berhasil")
        assert result.amount_atomic == 75000

    def test_reads_an_amount_before_sentence_punctuation(self) -> None:
        result = parse("noreply@jago.com", "Payment", "You paid Rp 48.719.")
        assert result.amount_atomic == 48719

    def test_drops_the_minor_unit_rather_than_inflating(self) -> None:
        # "IDR 1.250.000,00" is 1.250.000 rupiah, not 125.000.000.
        result = parse("noreply@jago.com", "Transaksi", "Nominal IDR 1.250.000,00")
        assert result.amount_atomic == 1250000

    def test_reads_bca_comma_groups_without_truncating_the_amount(self) -> None:
        result = parse(
            "BCA <bca@bca.co.id>",
            "Internet Transaction Journal",
            "Transaction Type : QRIS Payment Payment to : BP RAFFLES HILLS "
            "Merchant Location : DEPOK Total Payment : IDR 43,148.00",
        )
        assert result.amount_atomic == 43148
        assert result.description == "BP RAFFLES HILLS"
        assert result.direction == "expense"

    def test_a_charged_fee_is_the_transaction_itself(self) -> None:
        result = parse(
            "Jago <noreply@jago.com>",
            "You've been charged an insufficient funds fee.",
            "You have been charged a fee of Rp Rp5.000 because the pocket balance is low.",
        )
        assert result.amount_atomic == 5000

    def test_no_money_means_no_amount(self) -> None:
        result = parse("news@random.com", "Newsletter", "Nothing financial here.")
        assert result.amount_atomic is None


class TestDirection:
    def test_shared_pocket_arrival_needs_transfer_account_mapping(self) -> None:
        result = parse(
            "Jago <noreply@jago.com>",
            "Money arrived in your Shared Pocket",
            "A member is adding Rp10.000 into Transport Pocket.",
        )
        assert result.direction == "transfer"
        assert not result.is_complete
        assert "transfer_needs_account_mapping" in result.warnings

    def test_money_arriving_is_income(self) -> None:
        result = parse("noreply@gopay.co.id", "Top up berhasil", "Dana masuk Rp 150.000")
        assert result.direction == "income"

    def test_money_leaving_is_an_expense(self) -> None:
        result = parse("noreply@bca.co.id", "Transaksi", "Pembayaran sebesar Rp 50.000")
        assert result.direction == "expense"

    def test_an_unclear_message_says_it_assumed(self) -> None:
        result = parse("x@unknown.com", "Info", "Rp 10.000")
        assert "direction_assumed" in result.warnings


class TestHtml:
    def test_reads_through_markup_and_nbsp(self) -> None:
        result = parse(
            "noreply@gopay.co.id",
            "Top up berhasil",
            "<html><body><p>Dana masuk sebesar <b>Rp&nbsp;150.000</b></p></body></html>",
            is_html=True,
        )
        assert result.amount_atomic == 150000
        assert result.direction == "income"

    def test_ignores_numbers_hidden_in_a_style_block(self) -> None:
        # A stylesheet is not transaction text; reading it could invent an
        # amount that no human ever saw.
        result = parse(
            "noreply@bca.co.id",
            "Transaksi",
            "<style>.x{width:Rp 999.999.999}</style><p>Sebesar Rp 25.000</p>",
            is_html=True,
        )
        assert result.amount_atomic == 25000


class TestDate:
    def test_converts_an_explicit_wib_time_to_utc(self) -> None:
        result = parse(
            "noreply@jago.com",
            "Payment",
            "Transaction Date 27 September 2026, 16:11 WIB Amount Rp 5.000",
        )
        assert result.occurred_at is not None
        assert result.occurred_at.isoformat() == "2026-09-27T09:11:00+00:00"

    def test_reads_a_numeric_date_and_time(self) -> None:
        result = parse("noreply@bca.co.id", "Transaksi", "Pada 19/09/2026 14:23 sebesar Rp 1.000")
        assert result.occurred_at is not None
        assert (result.occurred_at.day, result.occurred_at.month) == (19, 9)
        assert result.occurred_at.hour == 14

    def test_reads_an_indonesian_month_name(self) -> None:
        result = parse("noreply@ovo.id", "Bayar", "20 Sep 2026 sebesar Rp 1.000")
        assert result.occurred_at is not None
        assert result.occurred_at.month == 9

    def test_an_impossible_date_is_not_invented(self) -> None:
        result = parse("noreply@ovo.id", "Bayar", "45/45/2026 sebesar Rp 1.000")
        assert result.occurred_at is None
        assert "date_not_found" in result.warnings


class TestConfidence:
    def test_a_complete_known_sender_scores_full(self) -> None:
        result = parse(
            "noreply@bca.co.id",
            "Notifikasi Transaksi BCA",
            "Pembayaran sebesar Rp 286.500 pada 19/09/2026 14:23",
        )
        assert result.confidence_bps == 10000
        assert result.is_complete

    def test_an_unreadable_message_scores_low_and_is_incomplete(self) -> None:
        result = parse("news@random.com", "Newsletter", "Nothing here.")
        assert result.confidence_bps < 2000
        assert not result.is_complete

    def test_an_unknown_sender_is_flagged_but_still_parsed(self) -> None:
        result = parse("alerts@some-new-bank.id", "Transaksi", "Sebesar Rp 42.000 pada 19/09/2026")
        assert result.amount_atomic == 42000
        assert "unknown_sender" in result.warnings
        assert result.confidence_bps < 10000


class TestEvidence:
    def test_every_read_field_carries_its_snippet(self) -> None:
        # A reviewer should be able to see why the parser said what it said.
        result = parse(
            "noreply@bca.co.id",
            "Notifikasi Transaksi BCA",
            "Pembayaran sebesar Rp 286.500 pada 19/09/2026 14:23",
        )
        fields = {item["field"] for item in result.evidence}
        assert {"amount_atomic", "direction", "occurred_at", "description"} <= fields
        amount = next(i for i in result.evidence if i["field"] == "amount_atomic")
        assert "286.500" in amount["snippet"]

    def test_a_forwarded_subject_loses_its_prefix(self) -> None:
        result = parse("noreply@bca.co.id", "Fwd: Notifikasi Transaksi", "Sebesar Rp 1.000")
        assert result.description == "Notifikasi Transaksi"
