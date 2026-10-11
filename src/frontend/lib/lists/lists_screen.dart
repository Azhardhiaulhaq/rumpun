import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/auth_repository.dart';
import '../main.dart' show AppColors, describeAuthError;
import '../tunas/tunas.dart';
import 'grocery_groups.dart';
import 'list_cover.dart';
import 'lists_repository.dart';

const _apricot = Color(0xFFFFE9DB);

Duration _motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

String _initials(String? name) {
  if (name == null || name.trim().isEmpty) return '?';
  final words = name.trim().split(RegExp(r'\s+'));
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// Household lists: groceries and notes both partners keep together.
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key, required this.auth, this.openListId});
  final AuthRepository auth;

  /// Opened from a notification, so the right list is one tap closer.
  final String? openListId;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  late final ListsRepository _repo = ListsRepository(widget.auth);
  late Future<List<ListSummary>> _lists = _repo.lists();
  bool? _notify;

  bool get _canEdit =>
      !const {'viewer', 'child'}.contains(widget.auth.session?.household?.role);

  @override
  void initState() {
    super.initState();
    _repo
        .notifyOnAdd()
        .then((value) {
          if (mounted) setState(() => _notify = value);
        })
        .catchError((Object _) {});
    final target = widget.openListId;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(target));
    }
  }

  Future<void> _refresh() async {
    final next = _repo.lists();
    setState(() {
      _lists = next;
    });
    await next.then<void>((_) {}, onError: (Object _) {});
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: _motion(context, 320),
        reverseTransitionDuration: _motion(context, 240),
        pageBuilder: (_, _, _) =>
            ListDetailScreen(repo: _repo, listId: id, canEdit: _canEdit),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<ListDetail>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => ListCoverSheet(repo: _repo),
    );
    if (created != null && mounted) {
      await _refresh();
      await _open(created.summary.id);
    }
  }

  Future<void> _toggleNotify(bool value) async {
    final previous = _notify;
    setState(() => _notify = value);
    try {
      await _repo.setNotifyOnAdd(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _notify = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeAuthError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.forest,
        onRefresh: _refresh,
        child: FutureBuilder<List<ListSummary>>(
          future: _lists,
          builder: (context, snapshot) {
            final lists = snapshot.data;
            final open = lists?.fold<int>(0, (n, l) => n + l.openCount) ?? 0;
            final children = <Widget>[
              _Header(
                openCount: open,
                listCount: lists?.length,
                canEdit: _canEdit,
                onCreate: _create,
              ),
              const SizedBox(height: 22),
            ];
            if (snapshot.hasError) {
              children.add(
                _TunasMessage(
                  mood: TunasMood.puzzled,
                  title: 'Daftar belum termuat',
                  message: describeAuthError(snapshot.error!),
                  action: 'Coba lagi',
                  onAction: _refresh,
                ),
              );
            } else if (lists == null) {
              children.add(
                const _TunasMessage(
                  mood: TunasMood.sleepy,
                  title: 'Memuat daftar…',
                  message: 'Tunas sedang mengambil catatan rumah.',
                ),
              );
            } else if (lists.isEmpty) {
              children.add(
                _TunasMessage(
                  mood: TunasMood.idle,
                  basket: true,
                  title: 'Bakulnya masih kosong',
                  message: _canEdit
                      ? 'Buat daftar belanja bulanan atau catatan, lalu isi bareng dari HP masing-masing.'
                      : 'Belum ada daftar di rumah ini.',
                  action: _canEdit ? 'Buat daftar pertama' : null,
                  onAction: _canEdit ? _create : null,
                ),
              );
            } else {
              for (final (index, list) in lists.indexed) {
                children.add(
                  _Appear(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ListCard(list: list, onTap: () => _open(list.id)),
                    ),
                  ),
                );
              }
            }
            if (_notify != null) {
              children.addAll([
                const SizedBox(height: 18),
                _NotifyRow(value: _notify!, onChanged: _toggleNotify),
              ]);
            }
            return ListView(
              key: const PageStorageKey('lists'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: children,
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.openCount,
    required this.listCount,
    required this.canEdit,
    required this.onCreate,
  });
  final int openCount;
  final int? listCount;
  final bool canEdit;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final summary = listCount == null || listCount == 0
        ? 'Belanjaan dan catatan seisi rumah.'
        : openCount == 0
        ? 'Semua belanjaan sudah beres.'
        : '$openCount barang belum dibeli.';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Daftar', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(
              summary,
              style: const TextStyle(color: AppColors.mutedInk, fontSize: 13.5),
            ),
          ],
        ),
        if (canEdit && (listCount ?? 0) > 0)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _apricot,
              foregroundColor: AppColors.deepClay,
              minimumSize: const Size(48, 48),
            ),
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Daftar baru'),
          ),
      ],
    );
  }
}

/// Tunas plus a short explanation: the empty, loading, and error states.
class _TunasMessage extends StatelessWidget {
  const _TunasMessage({
    required this.mood,
    required this.title,
    required this.message,
    this.basket = false,
    this.action,
    this.onAction,
  });
  final TunasMood mood;
  final String title;
  final String message;
  final bool basket;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6EF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Tunas(size: 150, mood: mood, inBasket: basket),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.mutedInk, height: 1.5),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _apricot,
                foregroundColor: AppColors.deepClay,
              ),
              onPressed: onAction,
              icon: const Icon(Icons.add, size: 20),
              label: Text(action!),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Cards slide up one after another on first load, so a long list does not
/// arrive as one flat block.
class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = _motion(context, 320 + 60 * index.clamp(0, 6));
    if (duration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.list, required this.onTap});
  final ListSummary list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = ListTint.of(list.tint);
    final done = list.itemCount - list.openCount;
    final status = list.isNote
        ? 'Catatan'
        : list.itemCount == 0
        ? 'Belum ada barang'
        : list.openCount == 0
        ? 'Semua sudah dibeli'
        : '${list.openCount} lagi';
    return Material(
      color: tint.ground,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              ListCoverIcon(
                icon: list.icon,
                tint: ListTint(
                  tint.key,
                  tint.label,
                  Colors.white,
                  tint.ink,
                  tint.accent,
                ),
                size: 54,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: tint.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
                        color: tint.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (list.preview.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        list.preview.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tint.ink.withValues(alpha: .8),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!list.isNote && list.itemCount > 0) ...[
                const SizedBox(width: 10),
                ProgressRing(done: done, total: list.itemCount, tint: tint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifyRow extends StatelessWidget {
  const _NotifyRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.hairline),
      borderRadius: BorderRadius.circular(18),
    ),
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: const Text(
        'Kabari saat ada barang baru',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: const Text(
        'Beberapa tambahan sekaligus jadi satu notifikasi.',
        style: TextStyle(fontSize: 12.5),
      ),
    ),
  );
}

/// Name, kind, icon, and colour. Used for both new lists and editing a cover.
class ListCoverSheet extends StatefulWidget {
  const ListCoverSheet({super.key, required this.repo, this.existing});
  final ListsRepository repo;
  final ListSummary? existing;

  @override
  State<ListCoverSheet> createState() => _ListCoverSheetState();
}

class _ListCoverSheetState extends State<ListCoverSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late String _kind = widget.existing?.kind ?? 'checklist';
  late String _icon = widget.existing?.icon ?? 'basket';
  late String _tint = widget.existing?.tint ?? 'sage';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Beri nama daftar dulu.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await widget.repo.create(name, _kind, icon: _icon, tint: _tint)
          : await widget.repo.rename(
              existing,
              name: name,
              icon: _icon,
              tint: _tint,
            );
      if (mounted) Navigator.pop(context, saved);
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
    final tint = ListTint.of(_tint);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        20,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: _motion(context, 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: ListCoverIcon(
                  key: ValueKey('$_icon$_tint'),
                  icon: _icon,
                  tint: tint,
                  size: 60,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.existing == null ? 'Daftar baru' : 'Ubah sampul',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Nama',
              hintText: 'Belanja bulanan',
              errorText: _error,
            ),
          ),
          if (widget.existing == null) ...[
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'checklist',
                  icon: Icon(Icons.checklist_rounded),
                  label: Text('Daftar centang'),
                ),
                ButtonSegment(
                  value: 'note',
                  icon: Icon(Icons.notes_rounded),
                  label: Text('Catatan bebas'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) => setState(() {
                _kind = value.first;
                if (_kind == 'note' && _icon == 'basket') _icon = 'note';
                if (_kind == 'checklist' && _icon == 'note') _icon = 'basket';
              }),
            ),
          ],
          const SizedBox(height: 18),
          const Text('Ikon', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in ListIcon.all)
                _Choice(
                  selected: _icon == icon.key,
                  label: icon.label,
                  onTap: () => setState(() => _icon = icon.key),
                  child: ListCoverIcon(icon: icon.key, tint: tint, size: 46),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Warna', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in ListTint.all)
                _Choice(
                  selected: _tint == option.key,
                  label: option.label,
                  onTap: () => setState(() => _tint = option.key),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: option.ground,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: option.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? 'Menyimpan…'
                  : widget.existing == null
                  ? 'Buat daftar'
                  : 'Simpan sampul',
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });
  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: AnimatedContainer(
          duration: _motion(context, 150),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.forest : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class ListDetailScreen extends StatefulWidget {
  const ListDetailScreen({
    super.key,
    required this.repo,
    required this.listId,
    required this.canEdit,
  });
  final ListsRepository repo;
  final String listId;
  final bool canEdit;

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  ListDetail? _detail;
  Object? _loadError;
  bool _busy = false;
  bool _grouped = true;
  final _newItem = TextEditingController();
  final _newItemFocus = FocusNode();
  final _body = TextEditingController();
  final _tunas = GlobalKey<TunasState>();
  String _savedBody = '';
  String _pendingClientId = '';
  String? _justAdded;
  bool _celebrate = false;

  @override
  void initState() {
    super.initState();
    _pendingClientId = widget.repo.newClientId();
    _load();
  }

  @override
  void dispose() {
    _newItem.dispose();
    _newItemFocus.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.repo.detail(widget.listId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loadError = null;
        if (_body.text == _savedBody) _body.text = detail.body;
        _savedBody = detail.body;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _toast(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(describeAuthError(error))));
  }

  void _replace(List<ListEntry> items) {
    final detail = _detail!;
    setState(
      () => _detail = ListDetail(
        summary: detail.summary,
        body: detail.body,
        items: items,
      ),
    );
  }

  Future<void> _add() async {
    final text = _newItem.text.trim();
    if (text.isEmpty || _busy) return;
    final parsed = splitQuantity(text);
    setState(() => _busy = true);
    try {
      final added = await widget.repo.addItem(
        widget.listId,
        clientId: _pendingClientId,
        text: parsed.$1,
        quantity: parsed.$2,
      );
      _pendingClientId = widget.repo.newClientId();
      _newItem.clear();
      _justAdded = added.id;
      _celebrate = false;
      _tunas.currentState?.play(TunasMood.hop);
      HapticFeedback.lightImpact();
      await _load();
    } catch (error) {
      // The same client key is kept, so tapping again cannot duplicate it.
      _toast(error);
    } finally {
      if (mounted) setState(() => _busy = false);
      _newItemFocus.requestFocus();
    }
  }

  Future<void> _setChecked(ListEntry item, bool checked) async {
    final detail = _detail!;
    final before = detail.items;
    final after = [
      for (final entry in before)
        entry.id == item.id ? entry.copyWith(checked: checked) : entry,
    ];
    _replace(after);
    final finished =
        checked &&
        after.isNotEmpty &&
        after.every((entry) => entry.checked) &&
        before.any((entry) => !entry.checked);
    if (finished) {
      setState(() => _celebrate = true);
      _tunas.currentState?.play(TunasMood.bloom);
      HapticFeedback.heavyImpact();
    } else if (checked) {
      _tunas.currentState?.play(TunasMood.wave);
      HapticFeedback.selectionClick();
    } else {
      setState(() => _celebrate = false);
    }
    try {
      await widget.repo.editItem(widget.listId, item.id, {'checked': checked});
      await _load();
    } catch (error) {
      if (mounted) _replace(before);
      _toast(error);
    }
  }

  Future<void> _delete(ListEntry item) async {
    final before = _detail!.items;
    _replace([
      for (final entry in before)
        if (entry.id != item.id) entry,
    ]);
    // Wait for the undo window before deleting on the server, so undo never
    // has to recreate the item and lose who added it.
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.text} dihapus.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Urungkan', onPressed: () {}),
      ),
    );
    final reason = await controller.closed;
    if (!mounted) return;
    if (reason == SnackBarClosedReason.action) {
      _replace(before);
      return;
    }
    try {
      await widget.repo.deleteItem(widget.listId, item.id);
    } catch (error) {
      if (mounted) _replace(before);
      _toast(error);
    }
  }

  Future<void> _editItem(ListEntry item) async {
    final result = await showModalBottomSheet<_ItemEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => _ItemSheet(item: item),
    );
    if (result == null) return;
    if (result.delete) {
      await _delete(item);
      return;
    }
    try {
      await widget.repo.editItem(widget.listId, item.id, {
        'text': result.text,
        'quantity': result.quantity,
        'note': result.note,
      });
      await _load();
    } catch (error) {
      _toast(error);
    }
  }

  Future<void> _saveBody() async {
    final detail = _detail;
    if (detail == null || _body.text == _savedBody) return;
    setState(() => _busy = true);
    try {
      final saved = await widget.repo.saveBody(detail.summary, _body.text);
      if (!mounted) return;
      setState(() {
        _detail = saved;
        _savedBody = saved.body;
      });
      _tunas.currentState?.play(TunasMood.wave);
    } catch (error) {
      _toast(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(String action) async {
    final detail = _detail!;
    switch (action) {
      case 'cover':
        final saved = await showModalBottomSheet<ListDetail>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.white,
          builder: (_) =>
              ListCoverSheet(repo: widget.repo, existing: detail.summary),
        );
        if (saved != null && mounted) setState(() => _detail = saved);
      case 'group':
        setState(() => _grouped = !_grouped);
      case 'clear':
        try {
          final cleared = await widget.repo.clearChecked(widget.listId);
          if (mounted) {
            setState(() {
              _detail = cleared;
              _celebrate = false;
            });
          }
        } catch (error) {
          _toast(error);
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Hapus ${detail.summary.name}?'),
            content: const Text(
              'Daftar ini hilang untuk semua anggota rumah dan tidak bisa dikembalikan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.deepClay,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Hapus daftar'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await widget.repo.delete(widget.listId);
          if (mounted) Navigator.pop(context);
        } catch (error) {
          _toast(error);
        }
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Catatan belum disimpan'),
          content: const Text('Perubahan terakhir akan hilang.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Kembali menulis'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Buang perubahan'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final tint = ListTint.of(detail?.summary.tint ?? 'sage');
    final hasChecked = detail?.items.any((item) => item.checked) ?? false;
    final dirty =
        detail != null && detail.summary.isNote && _body.text != _savedBody;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _body.text = _savedBody;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: tint.ground,
          surfaceTintColor: Colors.transparent,
          foregroundColor: tint.ink,
          title: const SizedBox.shrink(),
          actions: [
            if (detail != null && widget.canEdit)
              PopupMenuButton<String>(
                tooltip: 'Pilihan daftar',
                onSelected: _menu,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'cover',
                    child: Text('Ubah nama & sampul'),
                  ),
                  if (!detail.summary.isNote) ...[
                    PopupMenuItem(
                      value: 'group',
                      child: Text(
                        _grouped
                            ? 'Urutkan sesuai input'
                            : 'Kelompokkan per jenis',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      enabled: hasChecked,
                      child: const Text('Hapus yang sudah dibeli'),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Hapus daftar'),
                  ),
                ],
              ),
          ],
        ),
        body: _buildBody(detail, tint),
      ),
    );
  }

  Widget _hero(ListDetail detail, ListTint tint) {
    final total = detail.items.length;
    final done = detail.items.where((i) => i.checked).length;
    final isNote = detail.summary.isNote;
    final line = isNote
        ? (_body.text == _savedBody
              ? 'Tersimpan untuk seisi rumah.'
              : 'Ada perubahan belum disimpan.')
        : total == 0
        ? 'Belum ada barang.'
        : done == total
        ? 'Semua sudah dibeli. Hore!'
        : '${total - done} lagi dari $total barang.';
    final small = MediaQuery.sizeOf(context).width < 360;
    return Container(
      color: tint.ground,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ListCoverIcon(
                icon: detail.summary.icon,
                tint: ListTint(
                  tint.key,
                  tint.label,
                  Colors.white,
                  tint.ink,
                  tint.accent,
                ),
                size: 48,
              ),
              const Spacer(),
              Tunas(
                key: _tunas,
                size: small ? 76 : 96,
                mood: _celebrate ? TunasMood.bloom : TunasMood.idle,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail.summary.name,
            style: TextStyle(
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: tint.ink,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              line,
              style: TextStyle(color: tint.ink, fontWeight: FontWeight.w600),
            ),
          ),
          if (!isNote && total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: done / total),
                duration: _motion(context, 450),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  color: tint.accent,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(ListDetail? detail, ListTint tint) {
    if (detail == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: _loadError != null
            ? _TunasMessage(
                mood: TunasMood.puzzled,
                title: 'Daftar belum termuat',
                message: describeAuthError(_loadError!),
                action: 'Coba lagi',
                onAction: _load,
              )
            : const _TunasMessage(
                mood: TunasMood.sleepy,
                title: 'Memuat…',
                message: 'Sebentar, Tunas mengambil isi daftar.',
              ),
      );
    }
    if (detail.summary.isNote) {
      return Column(
        children: [
          _hero(detail, tint),
          Expanded(child: _noteBody()),
        ],
      );
    }
    final open = detail.items.where((item) => !item.checked).toList();
    final done = detail.items.where((item) => item.checked).toList();
    final sections = <Widget>[];
    if (_grouped) {
      final byGroup = <GroceryGroup, List<ListEntry>>{};
      for (final item in open) {
        byGroup.putIfAbsent(groupFor(item.text), () => []).add(item);
      }
      final order = [...groceryGroups, otherGroup];
      final usedGroups = order.where(byGroup.containsKey).toList();
      for (final group in usedGroups) {
        if (usedGroups.length > 1) {
          sections.add(_SectionLabel(group.label, inset: false));
        }
        sections.addAll(byGroup[group]!.map((item) => _row(item, tint)));
      }
    } else {
      sections.addAll(open.map((item) => _row(item, tint)));
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.forest,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 20),
              children: [
                // The hero scrolls with the items so a short screen with
                // large text still has room for the list itself.
                _hero(detail, tint),
                const SizedBox(height: 8),
                if (detail.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Text(
                      widget.canEdit
                          ? 'Ketik barang di bawah, misalnya "Telur 1 kg". Geser ke kanan untuk mencentang, ke kiri untuk menghapus.'
                          : 'Daftar masih kosong.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.mutedInk,
                        height: 1.5,
                      ),
                    ),
                  ),
                for (final section in sections)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: section,
                  ),
                if (done.isNotEmpty) ...[
                  _SectionLabel('Sudah dibeli (${done.length})'),
                  for (final item in done)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _row(item, tint),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (widget.canEdit) _composer(tint),
      ],
    );
  }

  Widget _row(ListEntry item, ListTint tint) {
    final details = [
      if (item.quantity != null) item.quantity!,
      if (item.note != null) item.note!,
    ].join(' · ');
    final who = item.checked ? item.checkedBy : item.addedBy;
    final tile = _ItemRow(
      key: ValueKey(item.id),
      item: item,
      details: details,
      who: who,
      whoLabel: item.checked ? 'Dicentang' : 'Ditambahkan',
      tint: tint,
      fresh: item.id == _justAdded,
      onToggle: widget.canEdit ? () => _setChecked(item, !item.checked) : null,
      onEdit: widget.canEdit ? () => _editItem(item) : null,
    );
    if (!widget.canEdit) return tile;
    return Dismissible(
      key: ValueKey('swipe-${item.id}'),
      background: _SwipeHint(
        alignment: Alignment.centerLeft,
        color: tint.accent,
        icon: item.checked ? Icons.undo_rounded : Icons.check_rounded,
        label: item.checked ? 'Belum' : 'Beres',
      ),
      secondaryBackground: const _SwipeHint(
        alignment: Alignment.centerRight,
        color: AppColors.deepClay,
        icon: Icons.delete_outline_rounded,
        label: 'Hapus',
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          unawaited(_setChecked(item, !item.checked));
          return false;
        }
        return true;
      },
      onDismissed: (_) => _delete(item),
      child: tile,
    );
  }

  // The composer is pinned; capping its text growth keeps the list visible
  // above it on small phones with very large text.
  Widget _composer(ListTint tint) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: _composerBody(tint),
  );

  Widget _composerBody(ListTint tint) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.hairline)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newItem,
                focusNode: _newItemFocus,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _add(),
                onChanged: (_) {
                  // A changed draft is a new item, not a retry of the last one.
                  _pendingClientId = widget.repo.newClientId();
                },
                decoration: InputDecoration(
                  hintText: 'Tambah barang, mis. Telur 1 kg',
                  counterText: '',
                  isDense: true,
                  fillColor: tint.ground.withValues(alpha: .5),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: tint.ink, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Tambahkan',
              style: IconButton.styleFrom(
                backgroundColor: _apricot,
                foregroundColor: AppColors.deepClay,
                minimumSize: const Size(52, 52),
              ),
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add_rounded, size: 26),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _noteBody() => Column(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            controller: _body,
            readOnly: !widget.canEdit,
            expands: true,
            maxLines: null,
            maxLength: 20000,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Tulis catatan untuk seisi rumah…',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              counterText: '',
            ),
            style: const TextStyle(fontSize: 16.5, height: 1.6),
          ),
        ),
      ),
      if (widget.canEdit)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy || _body.text == _savedBody ? null : _saveBody,
                child: const Text('Simpan catatan'),
              ),
            ),
          ),
        ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.inset = true});
  final String label;
  final bool inset;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(inset ? 20 : 8, 18, inset ? 20 : 8, 6),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.mutedInk,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
    ),
    alignment: alignment,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.details,
    required this.who,
    required this.whoLabel,
    required this.tint,
    required this.fresh,
    required this.onToggle,
    required this.onEdit,
  });
  final ListEntry item;
  final String details;
  final String? who;
  final String whoLabel;
  final ListTint tint;
  final bool fresh;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final row = Material(
      color: item.checked ? Colors.transparent : const Color(0xFFF8F8F6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              Semantics(
                checked: item.checked,
                label: item.text,
                child: _Check(checked: item.checked, tint: tint),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: _motion(context, 200),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: item.checked
                            ? AppColors.mutedInk
                            : AppColors.ink,
                        decoration: item.checked
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: AppColors.mutedInk,
                        decorationThickness: 2,
                      ),
                      child: Text(item.text),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: const TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              if (who != null)
                Tooltip(
                  message: '$whoLabel $who',
                  child: Semantics(
                    label: '$whoLabel $who',
                    child: ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: tint.ground,
                        foregroundColor: tint.ink,
                        child: Text(
                          _initials(who),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Ubah ${item.text}',
                  icon: const Icon(Icons.more_horiz_rounded),
                  color: AppColors.mutedInk,
                  onPressed: onEdit,
                ),
            ],
          ),
        ),
      ),
    );
    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: row,
    );
    if (!fresh || MediaQuery.disableAnimationsOf(context)) return padded;
    // A newly added item drops in so the eye follows it to its place.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.scale(scale: .92 + .08 * value, child: child),
      ),
      child: padded,
    );
  }
}

/// A round check that pops when ticked.
class _Check extends StatelessWidget {
  const _Check({required this.checked, required this.tint});
  final bool checked;
  final ListTint tint;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: Center(
      child: AnimatedContainer(
        duration: _motion(context, 220),
        curve: Curves.easeOutBack,
        width: checked ? 28 : 26,
        height: checked ? 28 : 26,
        decoration: BoxDecoration(
          color: checked ? tint.accent : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: checked ? tint.accent : AppColors.line,
            width: 2,
          ),
        ),
        child: AnimatedScale(
          scale: checked ? 1 : 0,
          duration: _motion(context, 220),
          curve: Curves.easeOutBack,
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
        ),
      ),
    ),
  );
}

/// "Telur 1 kg" becomes ("Telur", "1 kg"); "2 ikat bayam" becomes ("bayam", "2 ikat").
(String, String?) splitQuantity(String input) {
  const units =
      r'(?:kg|g|gr|gram|ons|l|liter|ml|pcs|buah|bh|biji|butir|bungkus|bks|pak|pack|sachet|botol|kaleng|ikat|sisir|lusin|karton|dus|kotak|lembar|papan|tray|rak)';
  final trailing = RegExp(
    '^(.+?)\\s+(\\d+(?:[.,]\\d+)?\\s*$units?)\$',
    caseSensitive: false,
  ).firstMatch(input);
  if (trailing != null) {
    return (trailing.group(1)!.trim(), trailing.group(2)!.trim());
  }
  final leading = RegExp(
    '^(\\d+(?:[.,]\\d+)?\\s*$units)\\s+(.+)\$',
    caseSensitive: false,
  ).firstMatch(input);
  if (leading != null) {
    return (leading.group(2)!.trim(), leading.group(1)!.trim());
  }
  return (input, null);
}

class _ItemEdit {
  const _ItemEdit({this.text, this.quantity, this.note, this.delete = false});
  final String? text;
  final String? quantity;
  final String? note;
  final bool delete;
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item});
  final ListEntry item;
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _text = TextEditingController(text: widget.item.text);
  late final _quantity = TextEditingController(text: widget.item.quantity);
  late final _note = TextEditingController(text: widget.item.note);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      22,
      24,
      22,
      MediaQuery.of(context).viewInsets.bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ubah barang', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Barang', errorText: _error),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _quantity,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Jumlah (opsional)',
            hintText: '1 kg',
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _note,
          maxLength: 240,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Catatan (opsional)',
            hintText: 'Merek atau ukuran',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.deepClay),
              onPressed: () =>
                  Navigator.pop(context, const _ItemEdit(delete: true)),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                if (_text.text.trim().isEmpty) {
                  setState(() => _error = 'Nama barang wajib diisi.');
                  return;
                }
                Navigator.pop(
                  context,
                  _ItemEdit(
                    text: _text.text.trim(),
                    quantity: _optional(_quantity),
                    note: _optional(_note),
                  ),
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ],
    ),
  );
}
