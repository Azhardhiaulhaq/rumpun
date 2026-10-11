import '../api/auth_repository.dart';

class SavedArea {
  const SavedArea({
    required this.id,
    required this.name,
    required this.version,
    required this.vertices,
  });
  factory SavedArea.fromJson(Map<String, dynamic> json) => SavedArea(
    id: json['id'] as String,
    name: json['name'] as String,
    version: json['version'] as int,
    vertices: (json['vertices'] as List)
        .map(
          (point) => (point as List)
              .map((value) => (value as num).toDouble())
              .toList(),
        )
        .toList(),
  );
  final String id;
  final String name;
  final int version;
  final List<List<double>> vertices;
}

class LocationRepository {
  const LocationRepository(this.auth);
  final AuthRepository auth;

  Future<List<SavedArea>> areas() async =>
      ((await auth.locationRequest('GET', '/areas')) as List)
          .map((item) => SavedArea.fromJson(item as Map<String, dynamic>))
          .toList();

  Future<SavedArea> saveArea(
    String name,
    List<List<double>> vertices, {
    SavedArea? previous,
  }) async => SavedArea.fromJson(
    (await auth.locationRequest(
          previous == null ? 'POST' : 'PATCH',
          previous == null ? '/areas' : '/areas/${previous.id}',
          body: {
            'name': name,
            'vertices': vertices,
            if (previous != null) 'version': previous.version,
          },
        ))
        as Map<String, dynamic>,
  );

  Future<void> deleteArea(String id) async {
    await auth.locationRequest('DELETE', '/areas/$id');
  }

  Future<List<Map<String, dynamic>>> sessions() async =>
      ((await auth.locationRequest('GET', '/sessions')) as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> preferences() async =>
      (await auth.locationRequest('GET', '/preferences'))
          as Map<String, dynamic>;

  Future<void> setPreferences({
    required bool starts,
    required bool arrivals,
  }) async {
    await auth.locationRequest(
      'PATCH',
      '/preferences',
      body: {'sharing_started': starts, 'arrival_alerts': arrivals},
    );
  }
}
