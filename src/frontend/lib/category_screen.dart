import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api/auth_repository.dart';
import 'api/models.dart';
import 'main.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.auth});
  final AuthRepository auth;
  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  late Future<MonthlySpending> _future = widget.auth.monthlySpending();
  bool get canWrite => const {
    'owner',
    'admin',
    'member',
  }.contains(widget.auth.session?.household?.role);

  void reload() => setState(() => _future = widget.auth.monthlySpending());

  Future<void> edit({SpendingCategory? category}) async {
    final name = TextEditingController(text: category?.name ?? '');
    final currency = widget.auth.session?.household?.baseCurrency ?? 'IDR';
    final minorUnit = defaultMinorUnit(currency);
    final budget = TextEditingController(
      text: category?.budgetAtomic == null
          ? ''
          : Money(
              atomic: category!.budgetAtomic!,
              currency: currency,
              minorUnit: minorUnit,
            ).format().replaceFirst(RegExp(r'^\S+\s+'), ''),
    );
    var type = 'expense';
    String? error;
    var saving = false;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            24,
            22,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                category == null
                    ? 'Tambah kategori'
                    : 'Atur anggaran ${category.name}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              if (category == null) ...[
                TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Nama kategori'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Jenis'),
                  items: const [
                    DropdownMenuItem(
                      value: 'expense',
                      child: Text('Pengeluaran'),
                    ),
                    DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
                  ],
                  onChanged: (value) => update(() => type = value ?? type),
                ),
              ],
              if (category?.type == 'expense' ||
                  (category == null && type == 'expense')) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: budget,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: minorUnit == 0
                      ? const [ThousandsFormatter()]
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Anggaran bulanan (opsional)',
                    prefixText: '$currency ',
                    helperText:
                        'Kosongkan untuk tanpa batas. Gunakan koma untuk desimal.',
                    helperMaxLines: 2,
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.deepClay),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final amount = budget.text.trim().isEmpty
                            ? null
                            : parseMoneyInput(budget.text, minorUnit);
                        if (category == null && name.text.trim().isEmpty ||
                            budget.text.trim().isNotEmpty &&
                                (amount == null || amount <= 0)) {
                          update(
                            () => error = 'Isi nama dan anggaran yang benar.',
                          );
                          return;
                        }
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          if (category == null) {
                            await widget.auth.createCategory(
                              name: name.text.trim(),
                              type: type,
                              budgetAtomic: type == 'expense' ? amount : null,
                            );
                          } else {
                            await widget.auth.updateCategoryBudget(
                              id: category.id,
                              budgetAtomic: amount,
                            );
                          }
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        } catch (e) {
                          update(() {
                            saving = false;
                            error = describeAuthError(e);
                          });
                        }
                      },
                child: Text(saving ? 'Menyimpan…' : 'Simpan kategori'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: AppBar(
      title: const Text('Kategori & anggaran'),
      backgroundColor: AppColors.paper,
    ),
    body: FutureBuilder<MonthlySpending>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DataStateView(
            icon: Icons.pie_chart_outline,
            title: 'Memuat anggaran',
            message: 'Menghitung pengeluaran bulan ini.',
            loading: true,
          );
        }
        if (snapshot.hasError) {
          return DataStateView(
            icon: Icons.cloud_off_outlined,
            title: 'Anggaran belum dapat dimuat',
            message: describeAuthError(snapshot.error!),
            actionLabel: 'Coba lagi',
            onAction: reload,
          );
        }
        final report = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            reload();
            await _future.then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Anggaran bulan ${report.month}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Batas diperbarui setiap bulan. Pengeluaran dihitung dari transaksi yang tidak dibatalkan.',
                style: TextStyle(color: AppColors.mutedInk),
              ),
              if (canWrite) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah kategori'),
                ),
              ],
              const SizedBox(height: 20),
              if (report.items.isEmpty)
                const Text(
                  'Belum ada kategori pengeluaran. Tambahkan satu untuk mulai mengatur anggaran.',
                ),
              for (final c in report.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: canWrite ? () => edit(category: c) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (canWrite)
                                  const Icon(
                                    Icons.tune,
                                    size: 20,
                                    color: AppColors.forest,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${Money(atomic: c.spentAtomic, currency: report.currency, minorUnit: report.minorUnit).format()} / ${c.budgetAtomic == null ? 'Tanpa anggaran' : Money(atomic: c.budgetAtomic!, currency: report.currency, minorUnit: report.minorUnit).format()}',
                            ),
                            if (c.budgetAtomic != null) ...[
                              const SizedBox(height: 10),
                              LinearProgressIndicator(
                                value: (c.spentAtomic / c.budgetAtomic!).clamp(
                                  0.0,
                                  1.0,
                                ),
                                minHeight: 7,
                                color: c.spentAtomic >= c.budgetAtomic! * 0.9
                                    ? AppColors.deepClay
                                    : AppColors.forest,
                                backgroundColor: AppColors.paleMoss,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                c.spentAtomic > c.budgetAtomic!
                                    ? 'Melebihi anggaran'
                                    : c.spentAtomic >= c.budgetAtomic! * 0.9
                                    ? 'Hampir mencapai batas'
                                    : 'Masih dalam anggaran',
                                style: TextStyle(
                                  color: c.spentAtomic >= c.budgetAtomic! * 0.9
                                      ? AppColors.deepClay
                                      : AppColors.forest,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class CategoryPieSection extends StatelessWidget {
  const CategoryPieSection({
    super.key,
    required this.future,
    required this.onRetry,
  });
  final Future<MonthlySpending>? future;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => FutureBuilder<MonthlySpending>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Memuat pengeluaran per kategori…'),
        );
      }
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(describeAuthError(snapshot.error!)),
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        );
      }
      final data = snapshot.data!;
      final items = data.items.where((c) => c.spentAtomic > 0).toList()
        ..sort((a, b) => b.spentAtomic.compareTo(a.spentAtomic));
      final total = items.fold<int>(0, (sum, c) => sum + c.spentAtomic);
      const palette = [
        AppColors.forest,
        AppColors.deepClay,
        AppColors.moss,
        AppColors.ink,
        AppColors.quietInk,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pengeluaran per kategori',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${data.month} · ${data.currency}',
            style: const TextStyle(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            const Text(
              'Belum ada pengeluaran bulan ini. Transaksi yang dicatat akan muncul di sini.',
            )
          else ...[
            Center(
              child: Semantics(
                label:
                    'Total pengeluaran ${Money(atomic: total, currency: data.currency, minorUnit: data.minorUnit).format()}',
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: CustomPaint(
                    painter: _PiePainter([
                      for (final c in items) c.spentAtomic / total,
                    ], palette),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      color: palette[i % palette.length],
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(items[i].name)),
                    Text(
                      Money(
                        atomic: items[i].spentAtomic,
                        currency: data.currency,
                        minorUnit: data.minorUnit,
                      ).format(),
                    ),
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _PiePainter extends CustomPainter {
  const _PiePainter(this.parts, this.colors);
  final List<double> parts;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    var start = -math.pi / 2;
    for (var i = 0; i < parts.length; i++) {
      final sweep = parts[i] * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.parts != parts;
}
