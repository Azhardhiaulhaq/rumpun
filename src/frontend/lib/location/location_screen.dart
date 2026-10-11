import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../api/auth_repository.dart';
import '../api/models.dart';
import '../main.dart';
import '../tunas/tunas.dart';
import 'location_repository.dart';

String _memberInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  return words.isEmpty
      ? '?'
      : words.take(2).map((word) => word.characters.first.toUpperCase()).join();
}

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, required this.auth});
  final AuthRepository auth;
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  static const _native = MethodChannel('rumpun/location');
  bool get _nativeSharingAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  late final LocationRepository repository = LocationRepository(widget.auth);
  List<SavedArea> areas = [];
  List<Map<String, dynamic>> sessions = [];
  Map<String, String> memberNames = {};
  final map = MapController();
  final corners = <LatLng>[];
  final name = TextEditingController();
  bool loading = true, busy = false, editing = false;
  String? error;
  Timer? timer;
  int minutes = 60;
  StreamSubscription<Position>? _localPositions;
  Position? _localPosition;
  LatLng? _localMarker;
  Timer? _markerMotion;

  Future<void> _watchLocalPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    _localPositions =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
          ),
        ).listen(
          (position) {
            if (!mounted) return;
            final first = _localPosition == null;
            final target = LatLng(position.latitude, position.longitude);
            final origin = _localMarker ?? target;
            _markerMotion?.cancel();
            setState(() {
              _localPosition = position;
            });
            if (MediaQuery.disableAnimationsOf(context) || first) {
              setState(() => _localMarker = target);
            } else {
              final watch = Stopwatch()..start();
              _markerMotion = Timer.periodic(const Duration(milliseconds: 16), (
                timer,
              ) {
                if (!mounted) {
                  timer.cancel();
                  return;
                }
                final progress = (watch.elapsedMilliseconds / 400).clamp(
                  0.0,
                  1.0,
                );
                final t = Curves.easeOut.transform(progress);
                setState(
                  () => _localMarker = LatLng(
                    origin.latitude + (target.latitude - origin.latitude) * t,
                    origin.longitude +
                        (target.longitude - origin.longitude) * t,
                  ),
                );
                if (progress >= 1) timer.cancel();
              });
            }
            if (first && !loading) {
              map.move(LatLng(position.latitude, position.longitude), 16);
            }
          },
          onError: (Object _) {
            if (mounted) setState(() => _localPosition = null);
          },
        );
  }

  SavedArea? editingArea;
  int? selectedCorner;

  Future<void> _manageAreas() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .55,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Area pertemuan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text('Perubahan berlaku untuk sesi berikutnya.'),
            if (areas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Belum ada area tersimpan.'),
              ),
            for (final area in areas)
              ListTile(
                title: Text(area.name),
                subtitle: Text('${area.vertices.length} sudut'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    editingArea = area;
                    editing = true;
                    name.text = area.name;
                    corners
                      ..clear()
                      ..addAll(area.vertices.map((p) => LatLng(p[0], p[1])));
                  });
                  map.move(corners.first, 16);
                },
                trailing: IconButton(
                  tooltip: 'Hapus ${area.name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: sheetContext,
                      builder: (context) => AlertDialog(
                        title: Text('Hapus ${area.name}?'),
                        content: const Text(
                          'Sesi yang sudah berjalan tetap memakai batas sebelumnya.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Batal'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Hapus'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                      await _run(() => repository.deleteArea(area.id));
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _preferences() async {
    final values = await repository.preferences();
    if (!mounted) return;
    var starts = values['sharing_started'] as bool;
    var arrivals = values['arrival_alerts'] as bool;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Notifikasi lokasi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SwitchListTile(
                title: const Text('Berbagi dimulai'),
                value: starts,
                onChanged: (value) => update(() => starts = value),
              ),
              SwitchListTile(
                title: const Text('Kedatangan di area'),
                value: arrivals,
                onChanged: (value) => update(() => arrivals = value),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _run(
                    () => repository.setPreferences(
                      starts: starts,
                      arrivals: arrivals,
                    ),
                  );
                },
                child: const Text('Simpan preferensi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _centre() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw PlatformException(
        code: 'location_permission',
        message: 'Izinkan lokasi untuk memusatkan peta.',
      );
    }
    final position = await Geolocator.getCurrentPosition();
    if (mounted) map.move(LatLng(position.latitude, position.longitude), 16);
  }

  Future<void> _extend() async {
    final session = mine;
    if (session == null) return;
    final item =
        await widget.auth.locationRequest(
              'POST',
              '/sessions/${session['id']}/extend',
              body: {
                'minutes': minutes,
                'request_key': DateTime.now().microsecondsSinceEpoch.toString(),
              },
            )
            as Map<String, dynamic>;
    if (!_nativeSharingAvailable) return;
    await _native.invokeMethod('extend', {
      'token': item['tracking_token'],
      'remaining': DateTime.parse(
        item['expires_at'] as String,
      ).difference(DateTime.now()).inMilliseconds,
    });
  }

  Map<String, dynamic>? get mine => sessions
      .where((s) => s['user_id'] == widget.auth.session?.user.id)
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    _load();
    _watchLocalPosition();
    timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await Future.wait([
        repository.areas(),
        repository.sessions(),
        widget.auth.people(),
      ]);
      final active = _nativeSharingAvailable
          ? await _native.invokeMethod<String>('status')
          : null;
      final interrupted = _nativeSharingAvailable
          ? await _native.invokeMethod<String>('interrupted')
          : null;
      if (interrupted != null && active != interrupted) {
        await widget.auth.locationRequest(
          'POST',
          '/sessions/$interrupted/stop',
        );
        await _native.invokeMethod('clear');
        if (mounted) {
          await _load();
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        areas = data[0] as List<SavedArea>;
        sessions = data[1] as List<Map<String, dynamic>>;
        final people = data[2] as HouseholdPeople;
        memberNames = {
          for (final member in people.members)
            member.userId: member.displayName,
        };
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e is PlatformException ? e.message : describeAuthError(e);
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = describeAuthError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _start() async {
    if (!_nativeSharingAvailable) {
      throw PlatformException(
        code: 'location_platform',
        message: 'Berbagi lokasi saat ini tersedia di Android.',
      );
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw PlatformException(
        code: 'location_disabled',
        message: 'Aktifkan lokasi perangkat terlebih dahulu.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        await Geolocator.getLocationAccuracy() !=
            LocationAccuracyStatus.precise) {
      throw PlatformException(
        code: 'precise_location',
        message: 'Lokasi presisi diperlukan untuk mendeteksi kedatangan.',
      );
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mulai berbagi lokasi?'),
        content: Text(
          'Semua anggota rumah dapat melihat lokasimu selama $minutes menit, sampai ${TimeOfDay.fromDateTime(DateTime.now().add(Duration(minutes: minutes))).format(context)}. Kedatangan di area tersimpan akan memberi notifikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mulai berbagi'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final device = await _native.invokeMethod<String>('device');
    final item =
        await widget.auth.locationRequest(
              'POST',
              '/sessions',
              body: {
                'minutes': minutes,
                'device_id': device,
                'request_key': DateTime.now().microsecondsSinceEpoch.toString(),
              },
            )
            as Map<String, dynamic>;
    try {
      await _native.invokeMethod('start', {
        'session': item['id'],
        'device': device,
        'token': item['tracking_token'],
        'base': widget.auth.apiBaseUrl,
        'areas': item['areas'],
        'remaining': DateTime.parse(
          item['expires_at'] as String,
        ).difference(DateTime.now()).inMilliseconds,
      });
    } catch (_) {
      await widget.auth.locationRequest('POST', '/sessions/${item['id']}/stop');
      rethrow;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    _localPositions?.cancel();
    _markerMotion?.cancel();
    name.dispose();
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Lokasi keluarga'),
      actions: [
        IconButton(
          tooltip: 'Lokasi saya',
          onPressed: busy ? null : () => _run(_centre),
          icon: const Icon(Icons.my_location),
        ),
        IconButton(
          tooltip: 'Notifikasi lokasi',
          onPressed: busy ? null : () => _run(_preferences),
          icon: const Icon(Icons.notifications_outlined),
        ),
      ],
    ),
    body: loading
        ? const DataStateView(
            icon: Icons.map_outlined,
            title: 'Memuat lokasi',
            message: 'Mengambil area dan sesi aktif.',
            loading: true,
          )
        : Column(
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: Text(error!)),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter: const LatLng(-6.2, 106.8),
                    initialZoom: 12,
                    onTap: (_, point) {
                      if (editing) {
                        setState(() {
                          if (selectedCorner != null) {
                            corners[selectedCorner!] = point;
                            selectedCorner = null;
                          } else if (corners.length < 64) {
                            corners.add(point);
                          }
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'app.rumpun.mobile',
                    ),
                    PolygonLayer(
                      polygons: [
                        for (final area in areas)
                          Polygon(
                            points: area.vertices
                                .map((p) => LatLng(p[0], p[1]))
                                .toList(),
                            color: AppColors.forest.withValues(alpha: .12),
                            borderColor: AppColors.forest,
                            borderStrokeWidth: 2,
                          ),
                        if (corners.length >= 3)
                          Polygon(
                            points: corners,
                            color: AppColors.clay.withValues(alpha: .15),
                            borderColor: AppColors.clay,
                            borderStrokeWidth: 2,
                          ),
                      ],
                    ),

                    MarkerLayer(
                      markers: [
                        if (_localPosition != null)
                          Marker(
                            point:
                                _localMarker ??
                                LatLng(
                                  _localPosition!.latitude,
                                  _localPosition!.longitude,
                                ),
                            width: 48,
                            height: 48,
                            child: Semantics(
                              label: 'Lokasi saya',
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF354C60),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _memberInitials(
                                    widget.auth.session?.user.displayName ?? '',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        for (final s in sessions)
                          if (s['position'] != null &&
                              (s['user_id'] != widget.auth.session?.user.id ||
                                  _localPosition == null))
                            Marker(
                              point: LatLng(
                                (s['position']['latitude'] as num).toDouble(),
                                (s['position']['longitude'] as num).toDouble(),
                              ),
                              width: 64,
                              height: 64,
                              child: MemberPin(
                                initials: _memberInitials(
                                  memberNames[s['user_id']] ?? '',
                                ),
                                label:
                                    'Lokasi ${memberNames[s['user_id']] ?? 'anggota keluarga'}',
                                fresh:
                                    DateTime.now()
                                        .difference(
                                          DateTime.parse(
                                            s['position']['observed_at']
                                                as String,
                                          ),
                                        )
                                        .inSeconds <
                                    60,
                              ),
                            ),
                        for (final p in corners)
                          Marker(
                            point: p,
                            width: 24,
                            height: 24,
                            child: const Icon(
                              Icons.circle,
                              size: 12,
                              color: AppColors.clay,
                            ),
                          ),
                      ],
                    ),
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap contributors'),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .45,
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (editing) ...[
                          TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: 'Nama area',
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (corners.isNotEmpty)
                            DropdownButton<int>(
                              hint: const Text('Pindahkan sudut'),
                              value: selectedCorner,
                              items: List.generate(
                                corners.length,
                                (i) => DropdownMenuItem(
                                  value: i,
                                  child: Text('Sudut ${i + 1}'),
                                ),
                              ),
                              onChanged: (i) =>
                                  setState(() => selectedCorner = i),
                            ),
                          Text(
                            '${corners.length} titik · Ketuk peta untuk menambah sudut',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: corners.isEmpty
                                    ? null
                                    : () =>
                                          setState(() => corners.removeLast()),
                                child: const Text('Urungkan'),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  editing = false;
                                  corners.clear();
                                }),
                                child: const Text('Batal'),
                              ),
                              FilledButton(
                                onPressed: busy || corners.length < 3
                                    ? null
                                    : () => _run(() async {
                                        await repository.saveArea(
                                          name.text,
                                          corners
                                              .map(
                                                (p) => [
                                                  p.latitude,
                                                  p.longitude,
                                                ],
                                              )
                                              .toList(),
                                          previous: editingArea,
                                        );
                                        setState(() {
                                          editingArea = null;
                                          selectedCorner = null;
                                          editing = false;
                                          corners.clear();
                                          name.clear();
                                        });
                                      }),
                                child: const Text('Simpan area'),
                              ),
                            ],
                          ),
                        ] else ...[
                          _SharingStatus(
                            sharing: mine != null,
                            others: sessions
                                .where(
                                  (s) =>
                                      s['user_id'] !=
                                      widget.auth.session?.user.id,
                                )
                                .map(
                                  (s) =>
                                      memberNames[s['user_id']] ??
                                      'Anggota keluarga',
                                )
                                .toList(),
                            minutesLeft: mine == null
                                ? null
                                : DateTime.parse(
                                    mine!['expires_at'] as String,
                                  ).difference(DateTime.now()).inMinutes,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: minutes,
                            decoration: InputDecoration(
                              labelText: mine == null
                                  ? 'Durasi berbagi'
                                  : 'Tambah durasi',
                            ),
                            items: [30, 60, 120, 240]
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text('$m menit'),
                                  ),
                                )
                                .toList(),
                            onChanged: (m) => setState(() => minutes = m!),
                          ),
                          for (final session in sessions)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '${memberNames[session['user_id']] ?? 'Anggota keluarga'} · ${session['position'] == null ? 'Lokasi belum diperbarui' : '${DateTime.now().difference(DateTime.parse(session['position']['observed_at'] as String)).inSeconds.clamp(0, 99999)} dtk lalu · ±${(session['position']['accuracy'] as num).round()} m'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.mutedInk,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (_nativeSharingAvailable || mine != null)
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: mine == null
                                        ? AppColors.forest
                                        : const Color(0xFFB3261E),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => _run(
                                          mine == null
                                              ? _start
                                              : () async {
                                                  if (_nativeSharingAvailable) {
                                                    await _native.invokeMethod(
                                                      'stop',
                                                    );
                                                  }
                                                  await widget.auth.locationRequest(
                                                    'POST',
                                                    '/sessions/${mine!['id']}/stop',
                                                  );
                                                },
                                        ),
                                  child: Text(
                                    mine == null
                                        ? 'Mulai berbagi'
                                        : 'Stop berbagi',
                                  ),
                                ),
                              if (mine != null && _nativeSharingAvailable)
                                TextButton(
                                  onPressed: busy ? null : () => _run(_extend),
                                  child: const Text('Perpanjang'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                onPressed: busy ? null : _manageAreas,
                                icon: const Icon(
                                  Icons.layers_outlined,
                                  size: 20,
                                ),
                                label: const Text('Kelola area'),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        editing = true;
                                        editingArea = null;
                                        corners.clear();
                                        name.clear();
                                      }),
                                icon: const Icon(
                                  Icons.add_location_alt_outlined,
                                ),
                                label: const Text('Tambah area'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}

/// Tunas narrates who is sharing: resting when nobody is, waving while you
/// share, hopping when someone else's location is on the map.
class _SharingStatus extends StatelessWidget {
  const _SharingStatus({
    required this.sharing,
    required this.others,
    required this.minutesLeft,
  });
  final bool sharing;
  final List<String> others;
  final int? minutesLeft;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String detail;
    final TunasMood mood;
    if (sharing) {
      mood = TunasMood.wave;
      title = 'Kamu sedang berbagi';
      detail =
          'Sisa ${(minutesLeft ?? 0).clamp(0, 100000)} menit. Anggota rumah bisa melihat posisimu.';
    } else if (others.isNotEmpty) {
      mood = TunasMood.hop;
      title = '${others.join(' dan ')} sedang berbagi';
      detail = 'Posisinya tampil di peta selama sesi berlangsung.';
    } else {
      mood = TunasMood.sleepy;
      title = 'Belum ada yang berbagi';
      detail = 'Lokasi hanya tampil saat seseorang memulainya sendiri.';
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          color: sharing ? const Color(0xFFE3EEE2) : const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Tunas(key: ValueKey(mood), size: 64, mood: mood),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 12.5,
                      height: 1.4,
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

/// A household member on the map. A soft ring spreads from fresh positions so
/// the eye finds them; a stale position stays still, so the map never implies
/// a live location it does not have.
class MemberPin extends StatefulWidget {
  const MemberPin({
    super.key,
    required this.initials,
    required this.label,
    required this.fresh,
  });
  final String initials;
  final String label;
  final bool fresh;

  @override
  State<MemberPin> createState() => _MemberPinState();
}

class _MemberPinState extends State<MemberPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MemberPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.fresh &&
        tunasIdleMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_ripple.isAnimating) {
      _ripple.repeat();
    } else if (!animate) {
      _ripple.stop();
      _ripple.value = 0;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: AnimatedBuilder(
      animation: _ripple,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          if (_ripple.isAnimating)
            Container(
              width: 40 + 24 * _ripple.value,
              height: 40 + 24 * _ripple.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.forest.withValues(
                  alpha: .28 * (1 - _ripple.value),
                ),
              ),
            ),
          child!,
        ],
      ),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.fresh ? AppColors.forest : AppColors.mutedInk,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Text(
          widget.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );
}
