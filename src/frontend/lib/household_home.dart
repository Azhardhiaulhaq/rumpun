import 'package:flutter/material.dart';

import 'api/auth_repository.dart';
import 'api/models.dart';
import 'ledger_screen.dart';
import 'lists/lists_repository.dart';
import 'tunas/tunas.dart';
import 'main.dart';

const _sage = Color(0xFFEDF2ED);
const _apricot = Color(0xFFFFE9DB);
const _slate = Color(0xFF354C60);

class HouseholdHome extends StatefulWidget {
  const HouseholdHome({
    super.key,
    required this.auth,
    required this.onFinance,
    required this.onProfile,
    required this.onRecord,
    this.onLists,
  });
  final AuthRepository auth;
  final VoidCallback? onLists;
  final ValueChanged<int> onFinance;
  final VoidCallback onProfile;
  final Future<bool> Function() onRecord;

  @override
  State<HouseholdHome> createState() => _HouseholdHomeState();
}

class _HouseholdHomeState extends State<HouseholdHome> {
  late Future<Dashboard> _dashboard;
  late Future<CandidateList> _reviews;
  late Future<MonthlySpending> _spending;
  late Future<HouseholdPeople> _people;
  late Future<List<ListSummary>> _lists;
  bool _expanded = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _dashboard = widget.auth.dashboard();
    _reviews = widget.auth.candidates();
    _spending = widget.auth.monthlySpending();
    _people = widget.auth.people();
    _lists = ListsRepository(widget.auth).lists();
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([
      _dashboard.then<void>((_) {}, onError: (Object _) {}),
      _reviews.then<void>((_) {}, onError: (Object _) {}),
      _spending.then<void>((_) {}, onError: (Object _) {}),
      _people.then<void>((_) {}, onError: (Object _) {}),
      _lists.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  Future<void> _invite() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => InviteSheet(auth: widget.auth),
    );
    if (saved == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.auth.session;
    final canInvite = const {
      'owner',
      'admin',
    }.contains(session?.household?.role);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const PageStorageKey('household-home'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                const BrandMark(size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Rumpun',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Buka profil',
                  onPressed: widget.onProfile,
                  icon: const Icon(Icons.account_circle_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _HomeCard(
              color: _sage,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Rumah kita',
                              style: TextStyle(color: AppColors.mutedInk),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              session?.household?.name ?? 'Rumah tangga',
                              style: const TextStyle(
                                fontSize: 25,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Tunas(size: 44),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<HouseholdPeople>(
                    future: _people,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _InlineRetry(
                          message: 'Anggota belum dapat dimuat.',
                          onRetry: _refresh,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const _LoadingLine('Memuat anggota…');
                      }
                      final people = snapshot.data!;
                      if (people.members.isEmpty) {
                        return const Text(
                          'Belum ada anggota yang dapat ditampilkan.',
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 20,
                            runSpacing: 16,
                            children: [
                              for (final member in people.members)
                                SizedBox(
                                  width: 220,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 23,
                                        backgroundColor: member.isYou
                                            ? Colors.white
                                            : const Color(0xFFDCE5DF),
                                        foregroundColor: AppColors.forest,
                                        child: Text(
                                          _initials(member.displayName),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              member.displayName,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (member.isYou)
                                              const Text(
                                                'Kamu',
                                                style: TextStyle(
                                                  color: AppColors.mutedInk,
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          if (people.invites.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              '${people.invites.length} undangan menunggu',
                              style: const TextStyle(
                                color: AppColors.mutedInk,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (canInvite)
                    TextButton.icon(
                      onPressed: _invite,
                      icon: const Icon(
                        Icons.person_add_alt_1_outlined,
                        size: 20,
                      ),
                      label: const Text('Undang anggota'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        minimumSize: const Size(48, 48),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PeopleScreen(auth: widget.auth),
                        ),
                      ),
                      icon: const Icon(Icons.people_outline),
                      label: const Text('Lihat anggota'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _HomeCard(
              color: const Color(0xFFF8F8FA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: _slate,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Keuangan rumah',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _visible
                            ? 'Sembunyikan jumlah'
                            : 'Tampilkan jumlah',
                        onPressed: () => setState(() => _visible = !_visible),
                        icon: Icon(
                          _visible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 21,
                          color: AppColors.mutedInk,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Total aset keluarga',
                    style: TextStyle(color: AppColors.mutedInk, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<Dashboard>(
                    future: _dashboard,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _InlineRetry(
                          message: 'Saldo belum dapat dimuat.',
                          onRetry: _refresh,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const _LoadingLine('Memuat saldo…');
                      }
                      final data = snapshot.data!;
                      final currencies = data.currencies;
                      Widget amount(String currency, {bool primary = false}) =>
                          Text(
                            _visible
                                ? Money(
                                    atomic:
                                        data.totalsByCurrency[currency] ?? 0,
                                    currency: currency,
                                    minorUnit: defaultMinorUnit(currency),
                                  ).format()
                                : '••••••',
                            style: TextStyle(
                              fontSize: primary ? 29 : 18,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: _slate,
                            ),
                          );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          amount(currencies.first, primary: true),
                          if (currencies.length > 1) ...[
                            const SizedBox(height: 4),
                            amount(currencies[1]),
                          ],
                          if (data.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Belum ada catatan. Tambahkan akun untuk mulai.',
                                style: TextStyle(
                                  color: AppColors.mutedInk,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          _DetailSize(
                            duration: duration,
                            alignment: Alignment.topLeft,
                            curve: Curves.easeInOut,
                            child: _expanded
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final currency in currencies.skip(
                                          2,
                                        ))
                                          amount(currency),
                                        const Text(
                                          'Mata uang tetap terpisah, tanpa konversi.',
                                          style: TextStyle(
                                            color: AppColors.mutedInk,
                                            fontSize: 12,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => widget.onFinance(3),
                                          child: const Text(
                                            'Lihat akun dan aset',
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            icon: AnimatedRotation(
                              turns: _expanded ? .5 : 0,
                              duration: duration,
                              child: const Icon(Icons.expand_more, size: 20),
                            ),
                            label: Text(
                              _expanded ? 'Tutup rincian' : 'Rincian aset',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: _slate,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 48),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 18, color: AppColors.hairline),
                  FutureBuilder<MonthlySpending>(
                    future: _spending,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _InlineRetry(
                          message: 'Pengeluaran belum dapat dimuat.',
                          onRetry: _refresh,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const _LoadingLine('Memuat pengeluaran…');
                      }
                      final spending = snapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Pengeluaran bulan ini',
                              style: TextStyle(
                                color: AppColors.mutedInk,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _visible
                                  ? Money(
                                      atomic: spending.items.fold<int>(
                                        0,
                                        (sum, item) => sum + item.spentAtomic,
                                      ),
                                      currency: spending.currency,
                                      minorUnit: spending.minorUnit,
                                    ).format()
                                  : '••••••',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _slate,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  FutureBuilder<CandidateList>(
                    future: _reviews,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _InlineRetry(
                          message: 'Tinjauan belum dapat dimuat.',
                          onRetry: _refresh,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const _LoadingLine('Memeriksa usulan…');
                      }
                      final count = snapshot.data!.items.length;
                      if (count == 0) return const SizedBox.shrink();
                      return TextButton.icon(
                        onPressed: () => widget.onFinance(2),
                        icon: const Icon(Icons.fact_check_outlined, size: 19),
                        label: Text('Tinjau $count usulan'),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: AppColors.deepClay,
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _apricot,
                          foregroundColor: AppColors.deepClay,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () async {
                          if (await widget.onRecord() && mounted) {
                            await _refresh();
                          }
                        },
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Catat uang'),
                      ),
                      TextButton(
                        onPressed: () => widget.onFinance(0),
                        style: TextButton.styleFrom(
                          foregroundColor: _slate,
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Buka keuangan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ListsCard(
              lists: _lists,
              onOpen: widget.onLists,
              onRetry: _refresh,
            ),
            const SizedBox(height: 16),
            _HomeCard(
              color: const Color(0xFFF1F3F6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.location_on_outlined,
                      color: _slate,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lokasi keluarga',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Hanya berbagi saat kamu mulai',
                          style: TextStyle(
                            color: _slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Lihat sesi aktif dan tentukan area pertemuan.',
                          style: TextStyle(
                            color: AppColors.mutedInk,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/location'),
                          child: const Text('Buka lokasi'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  return words.isEmpty
      ? '?'
      : words.take(2).map((word) => word.characters.first.toUpperCase()).join();
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class _DetailSize extends StatelessWidget {
  const _DetailSize({
    required this.duration,
    required this.alignment,
    required this.curve,
    required this.child,
  });
  final Duration duration;
  final Alignment alignment;
  final Curve curve;
  final Widget child;
  @override
  Widget build(BuildContext context) => duration == Duration.zero
      ? child
      : AnimatedSize(
          duration: duration,
          alignment: alignment,
          curve: curve,
          child: child,
        );
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.mutedInk, fontSize: 13),
      ),
    ),
  );
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        message,
        style: const TextStyle(color: AppColors.mutedInk, fontSize: 13),
      ),
      TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
    ],
  );
}

class FinanceBalanceCard extends StatelessWidget {
  const FinanceBalanceCard({
    super.key,
    required this.dashboard,
    required this.visible,
    required this.onToggle,
  });
  final Dashboard dashboard;
  final bool visible;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => _HomeCard(
    color: _sage,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              color: _slate,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Total aset',
                style: TextStyle(
                  color: AppColors.mutedInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: visible ? 'Sembunyikan jumlah' : 'Tampilkan jumlah',
              onPressed: onToggle,
              icon: Icon(
                visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _slate,
                size: 21,
              ),
            ),
          ],
        ),
        for (final currency in dashboard.currencies)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: visible
                ? CountUpMoney(
                    money: dashboard.totalIn(currency),
                    style: TextStyle(
                      fontSize: currency == dashboard.currencies.first
                          ? 30
                          : 20,
                      height: 1.3,
                      color: _slate,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Text(
                    '••••••',
                    style: TextStyle(
                      fontSize: currency == dashboard.currencies.first
                          ? 30
                          : 20,
                      height: 1.3,
                      color: _slate,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        const SizedBox(height: 12),
        Text(
          dashboard.isEmpty
              ? 'Belum ada akun. Tambahkan akun untuk mulai mencatat.'
              : 'Mata uang terpisah · Berdasarkan catatan aset terakhir',
          style: const TextStyle(
            color: AppColors.mutedInk,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    super.key,
    required this.auth,
    this.initialDestination = 0,
  });
  final AuthRepository auth;
  final int initialDestination;
  @override
  State<FinanceScreen> createState() => FinanceScreenState();
}

class FinanceScreenState extends State<FinanceScreen> {
  late int _index = widget.initialDestination;
  late Future<CandidateList> _reviews = widget.auth.candidates();
  void select(int index) {
    setState(() {
      _index = index;
      _reviews = widget.auth.candidates();
    });
  }

  bool backToOverview() {
    if (_index == 0) return false;
    select(0);
    return true;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Keuangan',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final (index, label) in [
                'Ringkasan',
                'Riwayat',
                'Tinjau',
                'Akun & aset',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: index == _index ? _sage : null,
                      foregroundColor: index == _index
                          ? _slate
                          : AppColors.mutedInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => select(index),
                    child: index == 2
                        ? FutureBuilder<CandidateList>(
                            future: _reviews,
                            builder: (context, snapshot) => Row(
                              children: [
                                Text(label),
                                if (snapshot.hasData &&
                                    snapshot.data!.items.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text('(${snapshot.data!.items.length})'),
                                ],
                              ],
                            ),
                          )
                        : Text(label),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_index) {
            1 => LedgerScreen(
              key: const ValueKey('history'),
              auth: widget.auth,
              view: LedgerView.history,
            ),
            2 => ReviewScreen(auth: widget.auth),
            3 => LedgerScreen(
              key: const ValueKey('accounts'),
              auth: widget.auth,
              view: LedgerView.accounts,
            ),
            _ => HomeScreen(auth: widget.auth, financeOverview: true),
          },
        ),
      ],
    ),
  );
}

/// Beranda's window into Daftar: what is still to buy, with Tunas in its bakul.
class _ListsCard extends StatelessWidget {
  const _ListsCard({
    required this.lists,
    required this.onOpen,
    required this.onRetry,
  });
  final Future<List<ListSummary>> lists;
  final VoidCallback? onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ListSummary>>(
    future: lists,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final checklists = data?.where((l) => !l.isNote).toList() ?? const [];
      final open = checklists.fold<int>(0, (n, l) => n + l.openCount);
      final busiest = checklists.where((l) => l.openCount > 0).toList()
        ..sort((a, b) => b.openCount.compareTo(a.openCount));
      final String title;
      final String detail;
      if (snapshot.hasError) {
        title = 'Daftar belum termuat';
        detail = 'Tarik ke bawah untuk mencoba lagi.';
      } else if (data == null) {
        title = 'Memuat daftar…';
        detail = '';
      } else if (data.isEmpty) {
        title = 'Belum ada daftar';
        detail = 'Catat belanjaan bareng, dari HP masing-masing.';
      } else if (open == 0) {
        title = 'Belanjaan beres';
        detail = 'Tidak ada barang yang menunggu dibeli.';
      } else {
        title = '$open barang belum dibeli';
        detail = busiest.first.preview.take(3).join(' · ');
      }
      return Material(
        color: const Color(0xFFFFF1E6),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: snapshot.hasError ? onRetry : onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daftar belanja',
                        style: TextStyle(
                          color: AppColors.deepClay,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.mutedInk,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        snapshot.hasError ? 'Coba lagi' : 'Buka daftar',
                        style: const TextStyle(
                          color: AppColors.deepClay,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Tunas(
                  size: 96,
                  inBasket: true,
                  mood: snapshot.hasError
                      ? TunasMood.puzzled
                      : data == null
                      ? TunasMood.sleepy
                      : TunasMood.idle,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// How the month's spending sits against the budgets the household set, told
/// by Tunas. Every word and mood comes from the categories' real numbers.
class BudgetMoodCard extends StatelessWidget {
  const BudgetMoodCard({super.key, required this.spending, this.onOpen});
  final MonthlySpending spending;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final budgeted = spending.items
        .where((c) => (c.budgetAtomic ?? 0) > 0)
        .toList();
    if (budgeted.isEmpty) {
      return Material(
        color: const Color(0xFFF1F6EF),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
            child: Row(
              children: [
                const Tunas(size: 78),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Pasang anggaran bulanan',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Beri batas per kategori, lalu Tunas mengabari saat pengeluaran mendekati batas.',
                        style: TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Atur anggaran',
                        style: TextStyle(
                          color: AppColors.forest,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final over = budgeted
        .where((c) => c.spentAtomic > c.budgetAtomic!)
        .map((c) => c.name)
        .toList();
    final near = budgeted
        .where(
          (c) =>
              c.spentAtomic <= c.budgetAtomic! &&
              c.spentAtomic >= c.budgetAtomic! * 3 ~/ 4,
        )
        .map((c) => c.name)
        .toList();
    final spent = budgeted.fold<int>(0, (n, c) => n + c.spentAtomic);
    final limit = budgeted.fold<int>(0, (n, c) => n + c.budgetAtomic!);
    final share = limit == 0 ? 0.0 : spent / limit;
    final TunasMood mood;
    final String title;
    final String detail;
    final Color ground;
    if (over.isNotEmpty) {
      mood = TunasMood.puzzled;
      title = 'Ada anggaran yang lewat';
      detail = 'Lewat: ${_names(over)}.';
      ground = const Color(0xFFFBE3D7);
    } else if (near.isNotEmpty) {
      mood = TunasMood.puzzled;
      title = 'Hampir sampai batas';
      detail = 'Sudah 75% atau lebih: ${_names(near)}.';
      ground = const Color(0xFFFFF1E6);
    } else {
      mood = TunasMood.wave;
      title = 'Anggaran aman';
      detail = 'Semua kategori masih di bawah 75% anggaran bulan ini.';
      ground = _sage;
    }
    return Material(
      color: ground,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
          child: Row(
            children: [
              Tunas(size: 78, mood: mood),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: AppColors.mutedInk,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Semantics(
                      label:
                          '${(share * 100).round()} persen dari total anggaran terpakai',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: share.clamp(0.0, 1.0)),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                                value: value,
                                minHeight: 8,
                                color: over.isNotEmpty || near.isNotEmpty
                                    ? AppColors.deepClay
                                    : AppColors.forest,
                                backgroundColor: Colors.white,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _names(List<String> names) => names.length <= 2
      ? names.join(' dan ')
      : '${names.take(2).join(', ')}, dan ${names.length - 2} lainnya';
}

/// A money figure that counts up from zero the first time it appears.
class CountUpMoney extends StatelessWidget {
  const CountUpMoney({super.key, required this.money, required this.style});
  final Money money;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(money.format(), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Text(
        Money(
          atomic: (money.atomic * t).round(),
          currency: money.currency,
          minorUnit: money.minorUnit,
        ).format(),
        style: style,
      ),
    );
  }
}
