/// Response shapes mirrored from `src/backend/app/schemas.py`.
library;

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String,
      );

  final String id;
  final String email;
  final String displayName;
}

class HouseholdContext {
  const HouseholdContext({
    required this.id,
    required this.name,
    required this.role,
    required this.baseCurrency,
    required this.isNamed,
  });

  factory HouseholdContext.fromJson(Map<String, dynamic> json) =>
      HouseholdContext(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        baseCurrency: json['base_currency'] as String,
        isNamed: json['is_named'] as bool? ?? true,
      );

  final String id;
  final String name;
  final String role;
  final String baseCurrency;

  /// False while the household still carries the name generated at sign-in.
  final bool isNamed;

  bool get canEdit => role == 'owner' || role == 'admin';
}

/// An offer for this account to join someone else's household.
class InviteSummary {
  const InviteSummary({
    required this.id,
    required this.householdName,
    required this.role,
    required this.invitedByName,
  });

  factory InviteSummary.fromJson(Map<String, dynamic> json) => InviteSummary(
        id: json['id'] as String,
        householdName: json['household_name'] as String,
        role: json['role'] as String,
        invitedByName: json['invited_by_name'] as String,
      );

  final String id;
  final String householdName;
  final String role;
  final String invitedByName;
}

class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
    required this.isYou,
  });

  factory HouseholdMember.fromJson(Map<String, dynamic> json) => HouseholdMember(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        isYou: json['is_you'] as bool? ?? false,
      );

  final String userId;
  final String displayName;
  final String email;
  final String role;
  final bool isYou;
}

class PendingInvite {
  const PendingInvite({
    required this.id,
    required this.email,
    required this.role,
  });

  factory PendingInvite.fromJson(Map<String, dynamic> json) => PendingInvite(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
      );

  final String id;
  final String email;
  final String role;
}

class HouseholdPeople {
  const HouseholdPeople({required this.members, required this.invites});

  factory HouseholdPeople.fromJson(Map<String, dynamic> json) => HouseholdPeople(
        members: [
          for (final m in json['members'] as List<dynamic>)
            HouseholdMember.fromJson(m as Map<String, dynamic>)
        ],
        invites: [
          for (final i in json['invites'] as List<dynamic>)
            PendingInvite.fromJson(i as Map<String, dynamic>)
        ],
      );

  final List<HouseholdMember> members;
  final List<PendingInvite> invites;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.household,
    this.isNewUser = false,
    this.pendingInvites = const [],
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final household = json['household'] as Map<String, dynamic>?;
    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      household:
          household == null ? null : HouseholdContext.fromJson(household),
      isNewUser: json['is_new_user'] as bool? ?? false,
      pendingInvites: [
        for (final invite in (json['pending_invites'] as List<dynamic>? ?? []))
          InviteSummary.fromJson(invite as Map<String, dynamic>)
      ],
    );
  }

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  /// Null while the user has signed in but not yet joined a household.
  final HouseholdContext? household;

  /// True only on the response that created the account.
  final bool isNewUser;

  /// Invitations waiting for this account's email address.
  final List<InviteSummary> pendingInvites;

  AuthSession withHousehold(HouseholdContext next) => AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
        household: next,
        isNewUser: isNewUser,
      );

  AuthSession withInvites(List<InviteSummary> next) => AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
        household: household,
        isNewUser: isNewUser,
        pendingInvites: next,
      );

  /// The user has signed in but belongs nowhere yet.
  bool get needsOnboarding => household == null;

  /// The household exists but still carries its generated name.
  bool get needsHouseholdSetup =>
      household != null && !household!.isNamed && household!.canEdit;
}

/// Carries the backend's machine-readable `code` so callers can branch on the
/// failure without string-matching the human message.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;

  @override
  String toString() => 'NetworkException: $message';
}

/// Money arrives as an integer in the currency's smallest unit, so no rounding
/// happens between the ledger and the screen.
class Money {
  const Money({required this.atomic, required this.currency});

  final int atomic;
  final String currency;

  /// IDR has no minor unit in practice; everything else here is two decimals.
  static const _minorDigits = {'IDR': 0, 'USD': 2, 'EUR': 2, 'SGD': 2, 'MYR': 2};

  int get _digits => _minorDigits[currency] ?? 2;

  String get symbol => currency == 'IDR' ? 'Rp' : currency;

  /// Indonesian grouping: dot for thousands, comma for the decimal.
  /// [sign] forces a leading mark: the API sends expenses as positive numbers
  /// with a type, so the direction lives outside the amount.
  String format({bool signed = false, int? sign}) {
    final negative = (sign ?? (atomic < 0 ? -1 : 1)) < 0;
    final digits = _digits;
    final scale = [1, 10, 100][digits];
    final abs = atomic.abs();
    final whole = (abs ~/ scale).toString();

    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
      grouped.write(whole[i]);
    }
    final minor =
        digits == 0 ? '' : ',${(abs % scale).toString().padLeft(digits, '0')}';

    final mark = negative ? '−' : (signed ? '+' : '');
    return '$mark$symbol $grouped$minor';
  }

  String get masked => '$symbol ' '•' * 7;
}

class AccountBalance {
  const AccountBalance({
    required this.accountId,
    required this.name,
    required this.kind,
    required this.balance,
  });

  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
        accountId: json['account_id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        balance: Money(
          atomic: json['balance_atomic'] as int,
          currency: json['currency'] as String,
        ),
      );

  final String accountId;
  final String name;
  final String kind;
  final Money balance;
}

class RecentTransaction {
  const RecentTransaction({
    required this.id,
    required this.transactionType,
    required this.description,
    required this.occurredAt,
    required this.amount,
  });

  factory RecentTransaction.fromJson(Map<String, dynamic> json) =>
      RecentTransaction(
        id: json['id'] as String,
        transactionType: json['transaction_type'] as String,
        description: json['description'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        amount: Money(
          atomic: json['amount_atomic'] as int,
          currency: json['currency'] as String,
        ),
      );

  final String id;
  final String transactionType;
  final String description;
  final DateTime occurredAt;
  final Money amount;

  bool get isIncome => transactionType == 'income';
}

class Dashboard {
  const Dashboard({
    required this.household,
    required this.totalsByCurrency,
    required this.accounts,
    required this.recentTransactions,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
        household: HouseholdContext.fromJson(
            json['household'] as Map<String, dynamic>),
        totalsByCurrency: {
          for (final e in (json['totals_by_currency'] as Map<String, dynamic>)
              .entries)
            e.key: e.value as int
        },
        accounts: [
          for (final a in json['accounts'] as List<dynamic>)
            AccountBalance.fromJson(a as Map<String, dynamic>)
        ],
        recentTransactions: [
          for (final t in json['recent_transactions'] as List<dynamic>)
            RecentTransaction.fromJson(t as Map<String, dynamic>)
        ],
      );

  final HouseholdContext household;
  final Map<String, int> totalsByCurrency;
  final List<AccountBalance> accounts;
  final List<RecentTransaction> recentTransactions;

  bool get isEmpty => accounts.isEmpty && recentTransactions.isEmpty;

  /// The headline figure. Only the household's own currency is summed; mixing
  /// currencies into one number would be a lie.
  Money get total => Money(
        atomic: totalsByCurrency[household.baseCurrency] ?? 0,
        currency: household.baseCurrency,
      );

  /// Currencies held outside the household's base, which the headline excludes.
  Map<String, int> get otherCurrencies => {
        for (final e in totalsByCurrency.entries)
          if (e.key != household.baseCurrency) e.key: e.value
      };
}

class Candidate {
  const Candidate({
    required this.id,
    required this.state,
    required this.version,
    required this.confidenceBps,
    required this.description,
    required this.amount,
    required this.occurredAt,
    required this.createdAt,
  });

  factory Candidate.fromJson(Map<String, dynamic> json) {
    final proposed = json['proposed'] as Map<String, dynamic>;
    final atomic = proposed['amount_atomic'] as int?;
    final occurred = proposed['occurred_at'] as String?;
    return Candidate(
      id: json['id'] as String,
      state: json['state'] as String,
      version: json['version'] as int,
      confidenceBps: json['confidence_bps'] as int,
      description: proposed['description'] as String?,
      amount: atomic == null
          ? null
          : Money(atomic: atomic, currency: proposed['currency'] as String),
      occurredAt: occurred == null ? null : DateTime.parse(occurred).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final String state;
  final int version;
  final int confidenceBps;
  final String? description;
  final Money? amount;
  final DateTime? occurredAt;
  final DateTime createdAt;

  /// The parser could not fill everything in, so a person must before this
  /// can be confirmed.
  bool get needsInput =>
      state == 'needs_input' || amount == null || description == null;
}

class CandidateList {
  const CandidateList({required this.items, required this.nextCursor});

  factory CandidateList.fromJson(Map<String, dynamic> json) => CandidateList(
        items: [
          for (final c in json['items'] as List<dynamic>)
            Candidate.fromJson(c as Map<String, dynamic>)
        ],
        nextCursor: json['next_cursor'] as String?,
      );

  final List<Candidate> items;
  final String? nextCursor;
}

class LedgerAccount {
  const LedgerAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.currency,
  });

  factory LedgerAccount.fromJson(Map<String, dynamic> json) => LedgerAccount(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        currency: json['currency'] as String,
      );

  final String id;
  final String name;
  final String kind;
  final String currency;
}

/// The address a household forwards its bank email to, plus how setup is
/// going. Null on the repository means no address has been created yet.
class InboxAddress {
  const InboxAddress({
    required this.address,
    required this.state,
    required this.verificationCode,
    required this.messageCount,
    required this.lastMessageAt,
  });

  factory InboxAddress.fromJson(Map<String, dynamic> json) => InboxAddress(
        address: json['address'] as String,
        state: json['state'] as String,
        verificationCode: json['verification_code'] as String?,
        messageCount: json['message_count'] as int,
        lastMessageAt: json['last_message_at'] == null
            ? null
            : DateTime.parse(json['last_message_at'] as String).toLocal(),
      );

  final String address;
  final String state;
  final String? verificationCode;
  final int messageCount;
  final DateTime? lastMessageAt;

  bool get isActive => state == 'active';

  /// Gmail sends a code before it will forward anything, so setup is only
  /// finished once mail actually arrives.
  bool get awaitingVerification => state == 'pending_verification';
}
