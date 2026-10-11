import 'dart:math';

import '../api/auth_repository.dart';

class ListSummary {
  const ListSummary({
    required this.id,
    required this.name,
    required this.kind,
    this.icon = 'basket',
    this.tint = 'sage',
    required this.version,
    required this.itemCount,
    required this.openCount,
    required this.preview,
    required this.updatedAt,
  });

  factory ListSummary.fromJson(Map<String, dynamic> json) => ListSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String,
    icon: json['icon'] as String? ?? 'basket',
    tint: json['tint'] as String? ?? 'sage',
    version: json['version'] as int,
    itemCount: json['item_count'] as int,
    openCount: json['open_count'] as int,
    preview: (json['preview'] as List).cast<String>(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final String name;
  final String kind;
  final String icon;
  final String tint;
  final int version;
  final int itemCount;
  final int openCount;
  final List<String> preview;
  final DateTime updatedAt;

  bool get isNote => kind == 'note';
}

class ListEntry {
  const ListEntry({
    required this.id,
    required this.text,
    this.quantity,
    this.note,
    required this.checked,
    this.checkedBy,
    this.addedBy,
  });

  factory ListEntry.fromJson(Map<String, dynamic> json) => ListEntry(
    id: json['id'] as String,
    text: json['text'] as String,
    quantity: json['quantity'] as String?,
    note: json['note'] as String?,
    checked: json['checked'] as bool,
    checkedBy: json['checked_by'] as String?,
    addedBy: json['added_by'] as String?,
  );

  final String id;
  final String text;
  final String? quantity;
  final String? note;
  final bool checked;
  final String? checkedBy;
  final String? addedBy;

  ListEntry copyWith({bool? checked}) => ListEntry(
    id: id,
    text: text,
    quantity: quantity,
    note: note,
    checked: checked ?? this.checked,
    checkedBy: checkedBy,
    addedBy: addedBy,
  );
}

class ListDetail {
  const ListDetail({
    required this.summary,
    required this.body,
    required this.items,
  });

  factory ListDetail.fromJson(Map<String, dynamic> json) => ListDetail(
    summary: ListSummary.fromJson(json),
    body: json['body'] as String? ?? '',
    items: (json['items'] as List)
        .map((item) => ListEntry.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final ListSummary summary;
  final String body;
  final List<ListEntry> items;
}

class ListsRepository {
  ListsRepository(this.auth);
  final AuthRepository auth;
  final _random = Random.secure();

  /// A per-add key so a retry on a weak connection never creates a twin item.
  String newClientId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<List<ListSummary>> lists() async =>
      ((await auth.listsRequest('GET', '')) as List)
          .map((item) => ListSummary.fromJson(item as Map<String, dynamic>))
          .toList();

  Future<ListDetail> detail(String id) async => ListDetail.fromJson(
    (await auth.listsRequest('GET', '/$id')) as Map<String, dynamic>,
  );

  Future<ListDetail> create(
    String name,
    String kind, {
    String icon = 'basket',
    String tint = 'sage',
  }) async => ListDetail.fromJson(
    (await auth.listsRequest(
          'POST',
          '',
          body: {'name': name, 'kind': kind, 'icon': icon, 'tint': tint},
        ))
        as Map<String, dynamic>,
  );

  Future<ListDetail> rename(
    ListSummary list, {
    String? name,
    String? icon,
    String? tint,
  }) async => ListDetail.fromJson(
    (await auth.listsRequest(
          'PATCH',
          '/${list.id}',
          body: {
            'version': list.version,
            'name': ?name,
            'icon': ?icon,
            'tint': ?tint,
          },
        ))
        as Map<String, dynamic>,
  );

  Future<ListDetail> saveBody(ListSummary list, String body) async =>
      ListDetail.fromJson(
        (await auth.listsRequest(
              'PATCH',
              '/${list.id}',
              body: {'version': list.version, 'body': body},
            ))
            as Map<String, dynamic>,
      );

  Future<void> delete(String id) async {
    await auth.listsRequest('DELETE', '/$id');
  }

  Future<ListEntry> addItem(
    String listId, {
    required String clientId,
    required String text,
    String? quantity,
    String? note,
  }) async => ListEntry.fromJson(
    (await auth.listsRequest(
          'POST',
          '/$listId/items',
          body: {
            'client_id': clientId,
            'text': text,
            'quantity': quantity,
            'note': note,
          },
        ))
        as Map<String, dynamic>,
  );

  Future<ListEntry> editItem(
    String listId,
    String itemId,
    Map<String, dynamic> changes,
  ) async => ListEntry.fromJson(
    (await auth.listsRequest('PATCH', '/$listId/items/$itemId', body: changes))
        as Map<String, dynamic>,
  );

  Future<void> deleteItem(String listId, String itemId) async {
    await auth.listsRequest('DELETE', '/$listId/items/$itemId');
  }

  Future<ListDetail> clearChecked(String listId) async => ListDetail.fromJson(
    (await auth.listsRequest('POST', '/$listId/clear-checked'))
        as Map<String, dynamic>,
  );

  Future<bool> notifyOnAdd() async =>
      ((await auth.listsRequest('GET', '/preferences'))
              as Map<String, dynamic>)['items_added']
          as bool;

  Future<void> setNotifyOnAdd(bool value) async {
    await auth.listsRequest(
      'PATCH',
      '/preferences',
      body: {'items_added': value},
    );
  }
}
