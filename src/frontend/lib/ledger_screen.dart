import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/auth_repository.dart';
import 'api/models.dart';
import 'main.dart';

enum LedgerView { all, accounts, history }

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({
    super.key,
    required this.auth,
    this.view = LedgerView.all,
  });

  final AuthRepository auth;
  final LedgerView view;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerData {
  const _LedgerData(this.dashboard, this.accounts, this.history);
  final Dashboard dashboard;
  final List<LedgerAccount> accounts;
  final LedgerHistory history;
}

class _LedgerScreenState extends State<LedgerScreen> {
  late Future<_LedgerData> _future;
  final List<LedgerEntry> _older = [];
  String? _cursor;
  bool _hasLoadedPage = false;
  bool _loadingMore = false;
  String? _pageError;

  bool get _canWrite => const {
    'owner',
    'admin',
    'member',
  }.contains(widget.auth.session?.household?.role);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LedgerData> _load() async {
    final results = await Future.wait<Object>([
      widget.auth.dashboard(),
      widget.auth.accounts(),
      widget.auth.transactions(),
    ]);
    return _LedgerData(
      results[0] as Dashboard,
      results[1] as List<LedgerAccount>,
      results[2] as LedgerHistory,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
      _older.clear();
      _cursor = null;
      _hasLoadedPage = false;
      _pageError = null;
    });
    await next.then<void>((_) {}).catchError((Object _) {});
  }

  Future<void> _loadMore(String cursor) async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _pageError = null;
    });
    try {
      final page = await widget.auth.transactions(cursor: cursor);
      if (!mounted) return;
      setState(() {
        _older.addAll(page.items);
        _cursor = page.nextCursor;
        _hasLoadedPage = true;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pageError = describeAuthError(error);
        _loadingMore = false;
      });
    }
  }

  Future<void> _addAccount() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _AccountSheet(
        auth: widget.auth,
        baseCurrency: widget.auth.session?.household?.baseCurrency ?? 'IDR',
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _openValuation(LedgerAccount account) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ValuationSheet(
        auth: widget.auth,
        account: account,
        canWrite: _canWrite,
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _openEntry(
    LedgerEntry entry,
    List<LedgerAccount> accounts,
  ) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _EntrySheet(
        auth: widget.auth,
        entry: entry,
        accounts: accounts,
        canWrite: _canWrite,
      ),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: widget.view == LedgerView.all
          ? AppBar(
              backgroundColor: AppColors.paper,
              title: const Text('Akun & catatan'),
            )
          : null,
      body: FutureBuilder<_LedgerData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const DataStateView(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Membuka catatan',
              message: 'Akun dan riwayat rumah tangga sedang dimuat.',
              loading: true,
            );
          }
          if (snapshot.hasError) {
            return DataStateView(
              icon: Icons.cloud_off_outlined,
              title: 'Catatan belum dapat dibuka',
              message: describeAuthError(snapshot.error!),
              actionLabel: 'Coba lagi',
              onAction: _refresh,
            );
          }
          final data = snapshot.data!;
          String? previousKind;
          final balances = {
            for (final a in data.dashboard.holdings) a.accountId: a,
          };
          final entries = [...data.history.items, ..._older];
          final nextCursor = _hasLoadedPage ? _cursor : data.history.nextCursor;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              children: [
                if (widget.view != LedgerView.history) ...[
                  Text(
                    'Akun dan aset',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Nilai tiap mata uang tetap terpisah. Aset dinilai sesuai catatan terakhirmu.',
                    style: TextStyle(color: AppColors.mutedInk, height: 1.4),
                  ),
                  if (_canWrite) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _addAccount,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah akun atau aset'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (data.accounts.isEmpty)
                    const _LedgerNote(
                      'Belum ada akun. Tambahkan tempat uang atau aset untuk mulai mencatat.',
                    )
                  else
                    ...([
                      ...data.accounts,
                    ]..sort((a, b) => a.kind.compareTo(b.kind))).map((account) {
                      final showHeading = previousKind != account.kind;
                      previousKind = account.kind;
                      final balance = balances[account.id];
                      final canValue = const {
                        'investment',
                        'physical_asset',
                        'other',
                      }.contains(account.kind);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeading)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                              child: Text(
                                _kindLabel(account.kind),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: canValue
                                    ? () => _openValuation(account)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _kindIcon(account.kind),
                                        color: AppColors.forest,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              account.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              '${_kindLabel(account.kind)} · ${account.currency}${account.unit == null ? '' : ' · ${account.unit}'}',
                                              style: const TextStyle(
                                                color: AppColors.mutedInk,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                            if (balance?.quantity != null)
                                              Text(
                                                '${_trimQuantity(balance!.quantity!)} ${account.unit ?? ''}',
                                                style: const TextStyle(
                                                  color: AppColors.mutedInk,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              canValue &&
                                                      balance?.valuedAt == null
                                                  ? 'Belum dinilai'
                                                  : balance?.balance.format() ??
                                                        'Saldo belum tersedia',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.forest,
                                              ),
                                              textAlign: TextAlign.end,
                                            ),
                                            if (canValue)
                                              Text(
                                                balance?.valuedAt == null
                                                    ? 'Catat nilai'
                                                    : 'Lihat nilai',
                                                style: const TextStyle(
                                                  color: AppColors.deepClay,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                ],
                if (widget.view != LedgerView.accounts) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Riwayat transaksi',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  if (entries.isEmpty)
                    const _LedgerNote(
                      'Belum ada transaksi. Catat uang masuk, keluar, atau pindah dana dari beranda.',
                    )
                  else
                    ...entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openEntry(entry, data.accounts),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    entry.description,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_transactionLabel(entry)} · ${_formatDate(entry.occurredAt)}',
                                    style: const TextStyle(
                                      color: AppColors.mutedInk,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.amount.format(
                                      signed: true,
                                      sign: entry.direction == 'out' ? -1 : 1,
                                    ),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.forest,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_pageError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _pageError!,
                      style: const TextStyle(color: AppColors.deepClay),
                    ),
                  ],
                  if (nextCursor != null)
                    TextButton(
                      onPressed: _loadingMore
                          ? null
                          : () => _loadMore(nextCursor),
                      child: Text(
                        _loadingMore
                            ? 'Memuat transaksi…'
                            : 'Tampilkan lebih lama',
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LedgerNote extends StatelessWidget {
  const _LedgerNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Text(
      message,
      style: const TextStyle(color: AppColors.mutedInk, height: 1.4),
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _trimQuantity(String value) => value.contains('.')
    ? value.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
    : value;

String _kindLabel(String kind) => switch (kind) {
  'cash' => 'Tunai',
  'bank' => 'Bank',
  'ewallet' => 'Dompet digital',
  'credit_card' => 'Kartu kredit',
  'budget_envelope' => 'Amplop anggaran',
  'investment' => 'Investasi',
  'foreign_currency' => 'Mata uang asing',
  'physical_asset' => 'Aset fisik',
  'loan' => 'Pinjaman',
  _ => 'Lainnya',
};

IconData _kindIcon(String kind) => switch (kind) {
  'bank' => Icons.account_balance_outlined,
  'ewallet' => Icons.wallet_outlined,
  'investment' => Icons.trending_up,
  'physical_asset' => Icons.home_work_outlined,
  'loan' || 'credit_card' => Icons.credit_card,
  'foreign_currency' => Icons.currency_exchange,
  _ => Icons.account_balance_wallet_outlined,
};

String _transactionLabel(LedgerEntry entry) => switch (entry.type) {
  'income' => 'Uang masuk',
  'expense' => 'Uang keluar',
  'transfer' => 'Pindah dana',
  'opening_balance' => 'Saldo awal',
  'refund' => 'Pengembalian',
  'adjustment' => 'Koreksi',
  'reversal' => 'Pembatalan',
  _ => entry.type,
};

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.auth, required this.baseCurrency});
  final AuthRepository auth;
  final String baseCurrency;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _currency = TextEditingController();
  final _unit = TextEditingController();
  final _precision = TextEditingController();
  String _kind = 'bank';
  bool _saving = false;
  String? _error;
  final _key = 'account-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _currency.text = widget.baseCurrency;
  }

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _unit.dispose();
    _precision.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.createAccount(
        name: _name.text.trim(),
        kind: _kind,
        currency: _currency.text.trim().toUpperCase(),
        minorUnit: _precision.text.trim().isEmpty
            ? null
            : int.parse(_precision.text.trim()),
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        idempotencyKey: _key,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeAuthError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      22,
      22,
      22,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tambah akun atau aset',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Simpan uang, utang, investasi, atau barang berharga pada tempatnya sendiri.',
            style: TextStyle(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nama akun atau aset'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Tulis namanya.' : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Bentuk'),
            items: [
              for (final kind in const [
                'bank',
                'cash',
                'ewallet',
                'foreign_currency',
                'investment',
                'physical_asset',
                'credit_card',
                'loan',
                'budget_envelope',
                'other',
              ])
                DropdownMenuItem(value: kind, child: Text(_kindLabel(kind))),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _currency,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Kode mata uang atau satuan nilai',
              helperText: 'Contoh: IDR, USD, JPY, XAU. 3–12 karakter.',
            ),
            validator: (value) =>
                RegExp(
                  r'^[A-Za-z][A-Za-z0-9]{2,11}$',
                ).hasMatch((value ?? '').trim())
                ? null
                : 'Isi kode 3–12 karakter, diawali huruf.',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _precision,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Desimal (opsional)',
              helperText: 'Kosongkan untuk mengikuti mata uang. Maksimal 8.',
              helperMaxLines: 2,
            ),
            validator: (value) {
              if ((value ?? '').isEmpty) return null;
              final parsed = int.tryParse(value!);
              return parsed != null && parsed <= 8 ? null : 'Pilih angka 0–8.';
            },
          ),
          if (const {
            'investment',
            'physical_asset',
            'other',
          }.contains(_kind)) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Satuan jumlah (opsional)',
                helperText: 'Contoh: gram, lembar, unit.',
              ),
              validator: (value) =>
                  (value ?? '').length > 40 ? 'Maksimal 40 huruf.' : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.deepClay)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Menyimpan…' : 'Simpan akun'),
          ),
        ],
      ),
    ),
  );
}

class _ValuationSheet extends StatefulWidget {
  const _ValuationSheet({
    required this.auth,
    required this.account,
    required this.canWrite,
  });
  final AuthRepository auth;
  final LedgerAccount account;
  final bool canWrite;

  @override
  State<_ValuationSheet> createState() => _ValuationSheetState();
}

class _ValuationSheetState extends State<_ValuationSheet> {
  final _form = GlobalKey<FormState>();
  final _value = TextEditingController();
  final _quantity = TextEditingController();
  late Future<List<AssetValuation>> _history;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;
  final _key = 'valuation-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _history = widget.auth.valuations(widget.account.id);
  }

  @override
  void dispose() {
    _value.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.recordValuation(
        accountId: widget.account.id,
        valueAtomic: parseMoneyInput(_value.text, widget.account.minorUnit)!,
        quantity: _quantity.text.trim().isEmpty
            ? null
            : _quantity.text.trim().replaceAll(',', '.'),
        effectiveAt: _date,
        idempotencyKey: _key,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeAuthError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      22,
      22,
      22,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.account.name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Setiap penilaian tersimpan dalam riwayat. Nilai terbaru tampil di beranda.',
          style: TextStyle(color: AppColors.mutedInk),
        ),
        if (widget.canWrite) ...[
          const SizedBox(height: 18),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: widget.account.minorUnit == 0
                      ? const [ThousandsFormatter()]
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Nilai saat ini',
                    prefixText: '${widget.account.currency} ',
                    helperText: widget.account.minorUnit > 0
                        ? 'Gunakan koma untuk desimal.'
                        : null,
                  ),
                  validator: (value) =>
                      parseMoneyInput(value ?? '', widget.account.minorUnit) ==
                          null
                      ? 'Isi nilai yang sah.'
                      : null,
                ),
                const SizedBox(height: 12),
                if (widget.account.unit != null)
                  TextFormField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Jumlah ${widget.account.unit}',
                    ),
                    validator: (value) =>
                        (value ?? '').isEmpty ||
                            RegExp(
                              r'^\d+(?:[,.]\d{1,18})?$',
                            ).hasMatch(value!.trim())
                        ? null
                        : 'Gunakan angka dan maksimal 18 desimal.',
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (selected != null) setState(() => _date = selected);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Tanggal nilai: ${_formatDate(_date)}'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.deepClay),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Menyimpan…' : 'Catat nilai'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text('Riwayat nilai', style: Theme.of(context).textTheme.titleMedium),
        FutureBuilder<List<AssetValuation>>(
          future: _history,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Memuat riwayat nilai…'),
              );
            }
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Riwayat nilai belum dapat dimuat. ${describeAuthError(snapshot.error!)}',
                    style: const TextStyle(color: AppColors.deepClay),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _history = widget.auth.valuations(widget.account.id);
                    }),
                    child: const Text('Coba lagi'),
                  ),
                ],
              );
            }
            final values = snapshot.data ?? [];
            if (values.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Belum ada nilai yang dicatat.'),
              );
            }
            return Column(
              children: [
                for (final value in values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(value.value.format()),
                    subtitle: Text(
                      '${_formatDate(value.effectiveAt)}${value.quantity == null ? '' : ' · ${_trimQuantity(value.quantity!)} ${value.unit ?? ''}'}',
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({
    required this.auth,
    required this.entry,
    required this.accounts,
    required this.canWrite,
  });
  final AuthRepository auth;
  final LedgerEntry entry;
  final List<LedgerAccount> accounts;
  final bool canWrite;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;
  final _key = 'reverse-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _name(String? id) {
    for (final account in widget.accounts) {
      if (account.id == id) return account.name;
    }
    return 'Akun';
  }

  Future<void> _reverse() async {
    if (_saving) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Tulis alasan pembatalan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.reverseTransaction(
        transactionId: widget.entry.id,
        reason: _reason.text.trim(),
        idempotencyKey: _key,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeAuthError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        22,
        22,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.description,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${_transactionLabel(entry)} · ${_formatDate(entry.occurredAt)}',
            style: const TextStyle(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 18),
          Text(
            entry.amount.format(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Akun: ${_name(entry.accountId)}'),
          if (entry.destinationAmount != null) ...[
            const SizedBox(height: 10),
            Text('Diterima: ${entry.destinationAmount!.format()}'),
            Text('Ke: ${_name(entry.destinationAccountId)}'),
          ],
          if (entry.reversesTransactionId != null) ...[
            const SizedBox(height: 14),
            const Text('Ini catatan pembatalan. Catatan asal tetap tersimpan.'),
          ],
          if (widget.canWrite && entry.reversesTransactionId == null) ...[
            const SizedBox(height: 22),
            const Text(
              'Salah catat? Pembatalan membuat catatan balik tanpa menghapus yang asli.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Alasan pembatalan'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.deepClay)),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _saving ? null : _reverse,
              child: Text(_saving ? 'Membatalkan…' : 'Batalkan transaksi'),
            ),
          ],
        ],
      ),
    );
  }
}
