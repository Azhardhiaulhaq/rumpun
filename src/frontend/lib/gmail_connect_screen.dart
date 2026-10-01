import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api/auth_repository.dart';
import 'api/models.dart';

class GmailConnectScreen extends StatefulWidget {
  const GmailConnectScreen({super.key, required this.auth, this.openUrl});

  final AuthRepository auth;
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<GmailConnectScreen> createState() => _GmailConnectScreenState();
}

class _GmailConnectScreenState extends State<GmailConnectScreen>
    with WidgetsBindingObserver {
  late Future<GmailConnection?> _connection;
  bool _busy = false;
  String? _error;
  int _days = 2;
  GmailSyncJob? _syncJob;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connection = widget.auth.gmailConnection();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _connection = widget.auth.gmailConnection();
      _error = null;
    });
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await widget.auth.connectGmail();
      final opened =
          await (widget.openUrl?.call(url) ??
              launchUrl(url, mode: LaunchMode.externalApplication));
      if (!opened) throw const NetworkException('Tidak bisa membuka Google.');
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Putuskan Gmail?'),
        content: const Text(
          'Rumpun akan berhenti membaca email baru dari akun ini. '
          'Kamu bisa menghubungkannya lagi nanti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Putuskan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.disconnectGmail();
      _reload();
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final job = await widget.auth.requestGmailSync(_days);
      if (!mounted) return;
      setState(() {
        _syncJob = job;
        _busy = false;
      });
      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _pollSync(),
      );
      await _pollSync();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _describe(error);
        });
      }
    }
  }

  Future<void> _pollSync() async {
    final id = _syncJob?.id;
    if (id == null || !mounted) return;
    try {
      final job = await widget.auth.gmailSyncJob(id);
      if (!mounted) return;
      setState(() => _syncJob = job);
      if (job.status == 'complete' || job.status == 'failed') {
        _syncTimer?.cancel();
        _reload();
      }
    } catch (error) {
      _syncTimer?.cancel();
      if (mounted) setState(() => _error = _describe(error));
    }
  }

  String _syncSummary(GmailSyncJob job) {
    final found =
        '${job.candidateCount} usulan baru dari ${job.discoveredCount} email baru.';
    return switch (job.status) {
      'complete' when job.unclassifiedCount > 0 =>
        '$found ${job.unclassifiedCount} email belum selesai diperiksa. '
            'Rumpun akan mencobanya lagi otomatis.',
      'complete' => found,
      'failed' when job.candidateCount > 0 =>
        '${job.candidateCount} usulan baru sudah masuk ke Tinjau, '
            'tetapi pemeriksaan terhenti. Coba lagi nanti.',
      'failed' => 'Pemeriksaan gagal. Coba lagi nanti.',
      _ => 'Sedang memeriksa email baru…',
    };
  }

  String _describe(Object error) {
    if (error is ApiException) {
      if (error.code == 'gmail_not_configured') {
        return 'Koneksi Gmail belum diatur di server Rumpun.';
      }
      return error.message;
    }
    if (error is NetworkException) return error.message;
    return 'Gmail belum bisa dihubungkan. Coba lagi.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Hubungkan Gmail')),
      body: SafeArea(
        child: FutureBuilder<GmailConnection?>(
          future: _connection,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _MessageState(
                title: 'Status Gmail belum terbuka',
                message: _describe(snapshot.error!),
                action: 'Coba lagi',
                onAction: _reload,
              );
            }
            final connection = snapshot.data;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    children: [
                      Text(
                        connection == null
                            ? 'Temukan transaksi dari Gmail'
                            : 'Gmail terhubung',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        connection == null
                            ? 'Hubungkan akun Google yang kamu pakai untuk masuk. '
                                  'Rumpun akan memeriksa email baru untuk menemukan transaksi.'
                            : connection.email,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE4E0D8)),
                        ),
                        child: connection == null
                            ? const Text(
                                'Google akan meminta izin membaca Gmail. '
                                'Isi email baru akan dikirim ke Jev (TypeSafe AI) '
                                'untuk menilai apakah ada transaksi. '
                                'Rumpun tidak mengirim email atas namamu atau '
                                'menghapusnya. Kamu bisa memutuskan akses kapan saja.',
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    connection.status == 'active'
                                        ? 'Koneksi aktif'
                                        : 'Perlu menghubungkan ulang',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    connection.lastSyncedAt == null
                                        ? 'Menunggu pemeriksaan email pertama.'
                                        : '${connection.awaitingJevCount} email menunggu pemeriksaan transaksi.',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    connection.classificationEnabled
                                        ? 'Usulan transaksi yang ditemukan akan muncul di Tinjau.'
                                        : 'Pemeriksaan transaksi belum aktif. '
                                              'Email belum akan muncul di Tinjau.',
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Perbarui status'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Text(_error!, style: TextStyle(color: colors.error)),
                        const SizedBox(height: 12),
                      ],
                      if (connection == null || connection.status != 'active')
                        FilledButton(
                          onPressed: _busy ? null : _connect,
                          child: Text(
                            _busy ? 'Membuka Google…' : 'Hubungkan Gmail',
                          ),
                        ),
                      if (connection != null) ...[
                        if (connection.status == 'active') ...[
                          Row(
                            children: [
                              const Expanded(child: Text('Periksa email dari')),
                              DropdownButton<int>(
                                value: _days,
                                items: const [1, 2, 7, 30, 90]
                                    .map(
                                      (days) => DropdownMenuItem(
                                        value: days,
                                        child: Text('$days hari terakhir'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (days) =>
                                          setState(() => _days = days ?? 2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed:
                                _busy ||
                                    _syncJob?.status == 'pending' ||
                                    _syncJob?.status == 'running'
                                ? null
                                : _sync,
                            icon: const Icon(Icons.sync),
                            label: const Text('Sinkronkan Gmail'),
                          ),
                          if (_syncJob != null) ...[
                            const SizedBox(height: 8),
                            Text(_syncSummary(_syncJob!)),
                          ],
                          const SizedBox(height: 12),
                        ],
                        if (connection.status != 'active')
                          const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _busy ? null : _disconnect,
                          child: const Text('Putuskan Gmail'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}
