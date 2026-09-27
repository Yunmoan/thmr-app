import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// A local, account-scoped snapshot of collection metadata. Audio is streamed
/// and is intentionally not part of this cache.
class CachedCollections {
  const CachedCollections(this.collections, this.savedAt);

  final List<Collection> collections;
  final DateTime savedAt;
}

class CachedCollectionDetail {
  const CachedCollectionDetail(this.collection, this.items, this.savedAt);

  final Collection collection;
  final List<CollectionItem> items;
  final DateTime savedAt;
}

class CollectionCache {
  const CollectionCache();

  static final Map<String, int> _generations = {};

  int generation(String userId) => _generations[userId] ?? 0;

  String _prefix(String userId) =>
      'thmr_collection_cache_v1_${Uri.encodeComponent(userId)}_';
  String _listKey(String userId) => '${_prefix(userId)}list';
  String _detailKey(String userId, String collectionId) =>
      '${_prefix(userId)}detail_${Uri.encodeComponent(collectionId)}';

  Future<void> saveList(String userId, List<Collection> collections) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _listKey(userId),
      jsonEncode({
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'collections': collections.map(_collectionJson).toList(),
      }),
    );
    final validIds = collections.map((c) => _detailKey(userId, c.id)).toSet();
    for (final key in prefs
        .getKeys()
        .where((k) => k.startsWith('${_prefix(userId)}detail_'))) {
      if (!validIds.contains(key)) await prefs.remove(key);
    }
  }

  Future<CachedCollections?> readList(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey(userId));
    if (raw == null) return null;
    try {
      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return CachedCollections(
        (data['collections'] as List)
            .map((item) =>
                Collection.fromJson((item as Map).cast<String, dynamic>()))
            .toList(),
        DateTime.parse(data['savedAt'] as String),
      );
    } catch (_) {
      await prefs.remove(_listKey(userId));
      return null;
    }
  }

  Future<void> saveDetail(
      String userId, Collection collection, List<CollectionItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _detailKey(userId, collection.id),
      jsonEncode({
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'collection': _collectionJson(collection),
        'items': items.map(_itemJson).toList(),
      }),
    );
  }

  Future<CachedCollectionDetail?> readDetail(
      String userId, String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _detailKey(userId, collectionId);
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return CachedCollectionDetail(
        Collection.fromJson(
            (data['collection'] as Map).cast<String, dynamic>()),
        (data['items'] as List)
            .map((item) =>
                CollectionItem.fromJson((item as Map).cast<String, dynamic>()))
            .toList(),
        DateTime.parse(data['savedAt'] as String),
      );
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> clearUser(String userId) async {
    _generations[userId] = generation(userId) + 1;
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(_prefix(userId)))) {
      await prefs.remove(key);
    }
  }

  Map<String, Object?> _collectionJson(Collection c) => {
        'id': c.id,
        'name': c.name,
        'description': c.description,
        'position': c.position,
        'itemCount': c.itemCount,
        'createdAt': c.createdAt,
        'updatedAt': c.updatedAt,
        'share': {
          'enabled': c.share.enabled,
          'slug': c.share.slug,
          'expiresAt': c.share.expiresAt,
        },
      };

  Map<String, Object?> _itemJson(CollectionItem item) => {
        'id': item.id,
        'stationId': item.stationId,
        'trackId': item.trackId,
        'position': item.position,
        'title': item.title,
        'artist': item.artist,
        'album': item.album,
        'durationSec': item.durationSec,
        'coverUrl': item.coverUrl,
        'addedAt': item.addedAt,
      };
}
