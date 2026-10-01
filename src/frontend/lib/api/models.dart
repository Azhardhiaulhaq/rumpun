/// Response shapes mirrored from `src/backend/app/schemas.py`.
library;

class GmailConnection {
  const GmailConnection({
    required this.email,
    required this.status,
    required this.connectedAt,
    required this.lastSyncedAt,
    required this.awaitingJevCount,
    required this.classificationEnabled,
  });

  factory GmailConnection.fromJson(Map<String, dynamic> json) =>
      GmailConnection(
        email: json['email'] as String,
        status: json['status'] as String,
        connectedAt: DateTime.parse(json['connected_at'] as String),
        lastSyncedAt: json['last_synced_at'] == null
            ? null
            : DateTime.parse(json['last_synced_at'] as String),
        awaitingJevCount: json['awaiting_jev_count'] as int,
        classificationEnabled: json['classification_enabled'] as bool? ?? false,
      );

  final String email;
  final String status;
  final DateTime connectedAt;
  final DateTime? lastSyncedAt;
  final int awaitingJevCount;
  final bool classificationEnabled;
}

class GmailSyncJob {
  const GmailSyncJob({
    required this.id,
    required this.status,
    required this.days,
    required this.discoveredCount,
    required this.candidateCount,
    this.unclassifiedCount = 0,
    this.errorCode,
  });

  factory GmailSyncJob.fromJson(Map<String, dynamic> json) => GmailSyncJob(
    id: json['id'] as String,
    status: json['status'] as String,
    days: json['days'] as int,
    discoveredCount: json['discovered_count'] as int,
    candidateCount: json['candidate_count'] as int,
    unclassifiedCount: json['unclassified_count'] as int? ?? 0,
    errorCode: json['error_code'] as String?,
  );

  final String id;
  final String status;
  final int days;
  final int discoveredCount;
  final int candidateCount;

  /// Emails the sync could not check yet. The server retries them on its own
  /// schedule, so they are reported, not treated as a failure.
  final int unclassifiedCount;
  final String? errorCode;
}

int defaultMinorUnit(String currency) {
  if (const {
    'BIF',
    'CLP',
    'DJF',
    'GNF',
    'ISK',
    'JPY',
    'KMF',
    'KRW',
    'PYG',
    'RWF',
    'UGX',
    'UYI',
    'VND',
    'VUV',
    'XAF',
    'XOF',
    'XPF',
    'IDR',
  }.contains(currency)) {
    return 0;
  }
  if (const {
    'BHD',
    'IQD',
    'JOD',
    'KWD',
    'LYD',
    'OMR',
    'TND',
  }.contains(currency)) {
    return 3;
  }
  return 2;
}

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

  factory HouseholdMember.fromJson(Map<String, dynamic> json) =>
      HouseholdMember(
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

  factory HouseholdPeople.fromJson(Map<String, dynamic> json) =>
      HouseholdPeople(
        members: [
          for (final m in json['members'] as List<dynamic>)
            HouseholdMember.fromJson(m as Map<String, dynamic>),
        ],
        invites: [
          for (final i in json['invites'] as List<dynamic>)
            PendingInvite.fromJson(i as Map<String, dynamic>),
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
      household: household == null
          ? null
          : HouseholdContext.fromJson(household),
      isNewUser: json['is_new_user'] as bool? ?? false,
      pendingInvites: [
        for (final invite in (json['pending_invites'] as List<dynamic>? ?? []))
          InviteSummary.fromJson(invite as Map<String, dynamic>),
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
  const Money({required this.atomic, required this.currency, this.minorUnit});

  final int atomic;
  final String currency;
  final int? minorUnit;

  int get _digits => minorUnit ?? defaultMinorUnit(currency);
  int get _scale => List<int>.generate(
    _digits,
    (index) => index,
  ).fold<int>(1, (value, _) => value * 10);

  String get symbol => currency == 'IDR' ? 'Rp' : currency;

  /// Indonesian grouping: dot for thousands, comma for the decimal.
  /// [sign] forces a leading mark: the API sends expenses as positive numbers
  /// with a type, so the direction lives outside the amount.
  String format({bool signed = false, int? sign}) {
    final negative = (sign ?? (atomic < 0 ? -1 : 1)) < 0;
    final digits = _digits;
    final scale = _scale;
    final abs = atomic.abs();
    final whole = (abs ~/ scale).toString();

    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
      grouped.write(whole[i]);
    }
    final minor = digits == 0
        ? ''
        : ',${(abs % scale).toString().padLeft(digits, '0')}';

    final mark = negative ? '−' : (signed ? '+' : '');
    return '$mark$symbol $grouped$minor';
  }

  String get masked =>
      '$symbol '
          '•' *
      7;

  /// Shortened for chart axes and captions, where the full grouping would not
  /// fit and the exact rupiah does not matter. Indonesian scale words, because
  /// the household reads amounts as "tiga juta", not "three million".
  String get compact {
    final scale = _scale;
    final whole = atomic.abs() ~/ scale;
    final mark = atomic < 0 ? '−' : '';
    String trim(double value) {
      final text = value.toStringAsFixed(value.abs() >= 10 ? 0 : 1);
      return text.endsWith('.0')
          ? text.substring(0, text.length - 2)
          : text.replaceAll('.', ',');
    }

    if (whole >= 1000000000) return '$mark$symbol ${trim(whole / 1000000000)}m';
    if (whole >= 1000000) return '$mark$symbol ${trim(whole / 1000000)}jt';
    if (whole >= 1000) return '$mark$symbol ${trim(whole / 1000)}rb';
    return '$mark$symbol $whole';
  }
}

class AccountBalance {
  const AccountBalance({
    required this.accountId,
    required this.name,
    required this.kind,
    required this.balance,
    this.quantity,
    this.unit,
    this.valuedAt,
  });

  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
    accountId: json['account_id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String,
    balance: Money(
      atomic: json['balance_atomic'] as int,
      currency: json['currency'] as String,
      minorUnit:
          json['minor_unit'] as int? ??
          defaultMinorUnit(json['currency'] as String),
    ),
    quantity: json['quantity']?.toString(),
    unit: json['unit'] as String?,
    valuedAt: json['valued_at'] == null
        ? null
        : DateTime.parse(json['valued_at'] as String).toLocal(),
  );

  final String accountId;
  final String name;
  final String kind;
  final Money balance;
  final String? quantity;
  final String? unit;
  final DateTime? valuedAt;
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
          minorUnit:
              json['minor_unit'] as int? ??
              defaultMinorUnit(json['currency'] as String),
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
      json['household'] as Map<String, dynamic>,
    ),
    totalsByCurrency: {
      for (final e
          in (json['totals_by_currency'] as Map<String, dynamic>).entries)
        e.key: e.value as int,
    },
    accounts: [
      for (final a in json['accounts'] as List<dynamic>)
        AccountBalance.fromJson(a as Map<String, dynamic>),
    ],
    recentTransactions: [
      for (final t in json['recent_transactions'] as List<dynamic>)
        RecentTransaction.fromJson(t as Map<String, dynamic>),
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
    minorUnit: _minorUnitFor(household.baseCurrency),
  );

  int _minorUnitFor(String currency) {
    for (final account in accounts) {
      if (account.balance.currency == currency) {
        return account.balance.minorUnit ?? defaultMinorUnit(currency);
      }
    }
    return defaultMinorUnit(currency);
  }

  /// Currencies held outside the household's base, which the headline excludes.
  Map<String, int> get otherCurrencies => {
    for (final e in totalsByCurrency.entries)
      if (e.key != household.baseCurrency) e.key: e.value,
  };

  /// Accounts a person actually holds money in. Equity is the balancing side
  /// of every entry rather than somewhere money sits, so it is left out of
  /// both the count and the breakdown; including it would double the ledger
  /// and show a large negative account nobody recognises.
  List<AccountBalance> get holdings => [
    for (final a in accounts)
      if (a.kind != 'equity') a,
  ];

  List<AccountBalance> holdingsIn(String currency) => [
    for (final a in holdings)
      if (a.balance.currency == currency) a,
  ];

  /// One card per currency the household actually holds, base currency first.
  ///
  /// A currency only earns a card once it carries a balance, so the carousel
  /// grows as real holdings appear instead of showing empty cards for accounts
  /// that exist but hold nothing. The base currency is always present, because
  /// a household with nothing yet still needs somewhere to read that zero.
  List<String> get currencies {
    final base = household.baseCurrency;
    final rest = [
      for (final e in totalsByCurrency.entries)
        if (e.key != base && e.value != 0) e.key,
    ]..sort();
    return [base, ...rest];
  }

  Money totalIn(String currency) => Money(
    atomic: totalsByCurrency[currency] ?? 0,
    currency: currency,
    minorUnit: _minorUnitFor(currency),
  );
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
    this.recipientName,
    this.recipientAccount,
    this.accountId,
    this.direction,
    this.issuer,
    this.transactionType,
    this.categoryId,
    this.destinationAccountId,
    this.suggestedFields = const {},
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
      recipientName: json['recipient_name'] as String?,
      recipientAccount: json['recipient_account'] as String?,
      accountId: proposed['account_id'] as String?,
      direction: json['direction'] as String?,
      issuer: json['issuer'] as String?,
      transactionType:
          proposed['transaction_type'] as String? ??
          json['direction'] as String? ??
          'expense',
      categoryId: proposed['category_id'] as String?,
      destinationAccountId: proposed['destination_account_id'] as String?,
      suggestedFields: {
        for (final field in json['suggested_fields'] as List<dynamic>? ?? [])
          field as String,
      },
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
  final String? recipientName;
  final String? recipientAccount;

  /// The account the email was matched to, if any. Most bank emails do not
  /// say which of the household's accounts paid, so this is usually null.
  final String? accountId;

  /// "expense", "income", or "transfer", as read from the email.
  final String? direction;

  /// The bank or wallet that sent the email, e.g. "Jago".
  final String? issuer;
  final String? transactionType;
  final String? categoryId;
  final String? destinationAccountId;

  /// Only spending can be posted from an email today. Money arriving or moving
  /// between the household's own accounts would be booked as a loss.
  bool get isRecordable => true;

  /// Proposed fields Jev filled in, such as "account_id", which the app marks
  /// as suggestions to check. A field a person changed is no longer listed.
  final Set<String> suggestedFields;

  bool isSuggested(String field) => suggestedFields.contains(field);

  /// The email lacked a fact only a person can supply (amount, description,
  /// or date). Accounts and categories are picked while confirming, so the
  /// server keeps this state in step with the proposal after every edit.
  bool get needsInput =>
      state == 'needs_input' || amount == null || description == null;
}

class CandidateDetail {
  const CandidateDetail({
    required this.candidate,
    required this.subject,
    required this.senderDomain,
    required this.issuer,
    required this.receivedAt,
  });

  factory CandidateDetail.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as Map<String, dynamic>;
    final metadata = source['metadata'] as Map<String, dynamic>;
    return CandidateDetail(
      candidate: Candidate.fromJson(json),
      subject: metadata['subject'] as String?,
      senderDomain: source['sender_domain'] as String?,
      issuer: metadata['issuer'] as String?,
      receivedAt: DateTime.parse(source['received_at'] as String).toLocal(),
    );
  }

  final Candidate candidate;
  final String? subject;
  final String? senderDomain;
  final String? issuer;
  final DateTime receivedAt;
}

class CandidateList {
  const CandidateList({required this.items, required this.nextCursor});

  factory CandidateList.fromJson(Map<String, dynamic> json) => CandidateList(
    items: [
      for (final c in json['items'] as List<dynamic>)
        Candidate.fromJson(c as Map<String, dynamic>),
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
    this.minorUnit = 2,
    this.unit,
    this.visibility = 'household',
  });

  factory LedgerAccount.fromJson(Map<String, dynamic> json) => LedgerAccount(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String,
    currency: json['currency'] as String,
    minorUnit:
        json['minor_unit'] as int? ??
        defaultMinorUnit(json['currency'] as String),
    unit: json['unit'] as String?,
    visibility: json['visibility'] as String? ?? 'household',
  );

  final String id;
  final String name;
  final String kind;
  final String currency;
  final int minorUnit;
  final String? unit;
  final String visibility;
}

class SpendingCategory {
  const SpendingCategory({
    required this.id,
    required this.name,
    required this.type,
    this.budgetAtomic,
    this.spentAtomic = 0,
  });
  factory SpendingCategory.fromJson(Map<String, dynamic> json) =>
      SpendingCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['category_type'] as String,
        budgetAtomic: json['budget_atomic'] as int?,
        spentAtomic: json['spent_atomic'] as int? ?? 0,
      );
  final String id;
  final String name;
  final String type;
  final int? budgetAtomic;
  final int spentAtomic;
}

class MonthlySpending {
  const MonthlySpending({
    required this.month,
    required this.currency,
    required this.minorUnit,
    required this.items,
  });
  factory MonthlySpending.fromJson(Map<String, dynamic> json) =>
      MonthlySpending(
        month: json['month'] as String,
        currency: json['currency'] as String,
        minorUnit: json['minor_unit'] as int,
        items: [
          for (final row in json['items'] as List<dynamic>)
            SpendingCategory.fromJson(row as Map<String, dynamic>),
        ],
      );
  final String month;
  final String currency;
  final int minorUnit;
  final List<SpendingCategory> items;
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.description,
    required this.occurredAt,
    required this.amount,
    required this.direction,
    this.accountId,
    this.destinationAccountId,
    this.destinationAmount,
    this.reversesTransactionId,
    this.categoryId,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: json['id'] as String,
    type: json['transaction_type'] as String,
    description: json['description'] as String,
    occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
    amount: Money(
      atomic: json['amount_atomic'] as int,
      currency: json['currency'] as String,
      minorUnit:
          json['minor_unit'] as int? ??
          defaultMinorUnit(json['currency'] as String),
    ),
    direction: json['direction'] as String? ?? 'in',
    accountId: json['account_id'] as String?,
    destinationAccountId: json['destination_account_id'] as String?,
    destinationAmount: json['destination_amount_atomic'] == null
        ? null
        : Money(
            atomic: json['destination_amount_atomic'] as int,
            currency: json['destination_currency'] as String,
            minorUnit:
                json['destination_minor_unit'] as int? ??
                defaultMinorUnit(json['destination_currency'] as String),
          ),
    reversesTransactionId: json['reverses_transaction_id'] as String?,
    categoryId: json['category_id'] as String?,
  );

  final String id;
  final String type;
  final String description;
  final DateTime occurredAt;
  final Money amount;
  final String direction;
  final String? accountId;
  final String? destinationAccountId;
  final Money? destinationAmount;
  final String? reversesTransactionId;
  final String? categoryId;
}

class LedgerHistory {
  const LedgerHistory({required this.items, required this.nextCursor});

  factory LedgerHistory.fromJson(Map<String, dynamic> json) => LedgerHistory(
    items: [
      for (final item in json['items'] as List<dynamic>)
        LedgerEntry.fromJson(item as Map<String, dynamic>),
    ],
    nextCursor: json['next_cursor'] as String?,
  );

  final List<LedgerEntry> items;
  final String? nextCursor;
}

class AssetValuation {
  const AssetValuation({
    required this.id,
    required this.accountId,
    required this.value,
    required this.effectiveAt,
    required this.source,
    this.quantity,
    this.unit,
  });

  factory AssetValuation.fromJson(Map<String, dynamic> json) => AssetValuation(
    id: json['id'] as String,
    accountId: json['account_id'] as String,
    value: Money(
      atomic: json['value_atomic'] as int,
      currency: json['currency'] as String,
      minorUnit:
          json['minor_unit'] as int? ??
          defaultMinorUnit(json['currency'] as String),
    ),
    quantity: json['quantity'] as String?,
    unit: json['unit'] as String?,
    effectiveAt: DateTime.parse(json['effective_at'] as String).toLocal(),
    source: json['source'] as String,
  );

  final String id;
  final String accountId;
  final Money value;
  final String? quantity;
  final String? unit;
  final DateTime effectiveAt;
  final String source;
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

/// One period on the home charts.
class TrendBucket {
  const TrendBucket({
    required this.start,
    required this.label,
    required this.spent,
    required this.received,
    required this.netWorth,
    required this.complete,
  });

  factory TrendBucket.fromJson(Map<String, dynamic> json, String currency) =>
      TrendBucket(
        start: DateTime.parse(json['start'] as String),
        label: json['label'] as String,
        spent: Money(atomic: json['spent_atomic'] as int, currency: currency),
        received: Money(
          atomic: json['received_atomic'] as int,
          currency: currency,
        ),
        netWorth: Money(
          atomic: json['net_worth_atomic'] as int,
          currency: currency,
        ),
        complete: json['complete'] as bool,
      );

  final DateTime start;
  final String label;
  final Money spent;
  final Money received;
  final Money netWorth;

  /// False while the period is still running, so the chart can mark the last
  /// column as partial instead of drawing it as a real fall.
  final bool complete;
}

class Trends {
  const Trends({
    required this.currency,
    required this.granularity,
    required this.buckets,
    this.changeBps,
    this.spendChangeBps,
  });

  factory Trends.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    return Trends(
      currency: currency,
      granularity: json['granularity'] as String,
      buckets: [
        for (final b in json['buckets'] as List<dynamic>)
          TrendBucket.fromJson(b as Map<String, dynamic>, currency),
      ],
      changeBps: json['change_bps'] as int?,
      spendChangeBps: json['spend_change_bps'] as int?,
    );
  }

  final String currency;
  final String granularity;
  final List<TrendBucket> buckets;

  /// Net worth movement between the last two finished periods, in basis
  /// points. Null when there is nothing to compare against yet.
  final int? changeBps;
  final int? spendChangeBps;

  /// Periods that have ended. The one in progress is excluded from
  /// comparisons, because a partial week is not a smaller week.
  List<TrendBucket> get finished => [
    for (final b in buckets)
      if (b.complete) b,
  ];

  bool get hasSpending => buckets.any((b) => b.spent.atomic > 0);

  /// True once two finished periods exist, which is the point at which a
  /// direction can honestly be drawn.
  bool get canCompare => finished.length >= 2;
}
