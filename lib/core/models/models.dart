/// 后端 JSON 模型 — 字段名与后端 camelCase 完全一致。
/// 约定:所有 ID 一律 String;`*Ms` 为毫秒 epoch;时间字符串为 ISO 8601。
library;

import '../config.dart';

/// coverUrl 统一处理:Radio 后端返回相对路径(或空串),账号后端返回绝对 URL。
/// 非 http 开头一律拼 radioBaseUrl(FLUTTER.md 通用约定 4)。
String absolutizeCover(String coverUrl, String radioBaseUrl) {
  if (coverUrl.isEmpty) return '';
  if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
    return coverUrl;
  }
  return '$radioBaseUrl$coverUrl';
}

class StreamProfile {
  final String id;
  final int bitrateKbps;
  final int sampleRate;
  final int channels;
  final bool enabled;

  const StreamProfile({
    required this.id,
    required this.bitrateKbps,
    required this.sampleRate,
    required this.channels,
    required this.enabled,
  });

  factory StreamProfile.fromJson(Map<String, dynamic> j) => StreamProfile(
        id: j['id'] as String,
        bitrateKbps: (j['bitrateKbps'] as num?)?.toInt() ?? 0,
        sampleRate: (j['sampleRate'] as num?)?.toInt() ?? 0,
        channels: (j['channels'] as num?)?.toInt() ?? 0,
        enabled: j['enabled'] != false,
      );

  String get label => id.endsWith('k') ? id : '${bitrateKbps}k';
}

class TrackRef {
  final String trackId;
  final String title;
  final String artist;
  final String coverUrl; // 原始值(可能为相对路径)

  const TrackRef({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.coverUrl,
  });

  factory TrackRef.fromJson(Map<String, dynamic> j) => TrackRef(
        trackId: (j['trackId'] ?? '').toString(),
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        coverUrl: absolutizeCover(
            (j['coverUrl'] ?? '') as String, appConfig.radioBaseUrl),
      );

  String cover(String radioBase) => absolutizeCover(coverUrl, radioBase);
}

/// 适合粘贴到搜索框的曲目信息；空字段不产生多余分隔符。
String trackSearchText({
  required String title,
  required String artist,
  String album = '',
}) {
  final titleAndArtist = [title.trim(), artist.trim()]
      .where((part) => part.isNotEmpty)
      .join(' - ');
  final trimmedAlbum = album.trim();
  if (trimmedAlbum.isEmpty) return titleAndArtist;
  return titleAndArtist.isEmpty
      ? trimmedAlbum
      : '$titleAndArtist · $trimmedAlbum';
}

class CurrentTrack extends TrackRef {
  final int startedAtMs;
  final int expectedEndMs;
  final int positionSec;
  final int durationSec;

  const CurrentTrack({
    required super.trackId,
    required super.title,
    required super.artist,
    required super.coverUrl,
    required this.startedAtMs,
    required this.expectedEndMs,
    required this.positionSec,
    required this.durationSec,
  });

  factory CurrentTrack.fromJson(Map<String, dynamic> j) => CurrentTrack(
        trackId: (j['trackId'] ?? '').toString(),
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        coverUrl: absolutizeCover(
            (j['coverUrl'] ?? '') as String, appConfig.radioBaseUrl),
        startedAtMs: (j['startedAtMs'] as num?)?.toInt() ?? 0,
        expectedEndMs: (j['expectedEndMs'] as num?)?.toInt() ?? 0,
        positionSec: (j['positionSec'] as num?)?.toInt() ?? 0,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
      );
}

class QueueEntry extends TrackRef {
  final int plannedStartMs;
  final int plannedEndMs;
  final int durationSec;

  const QueueEntry({
    required super.trackId,
    required super.title,
    required super.artist,
    required super.coverUrl,
    required this.plannedStartMs,
    required this.plannedEndMs,
    required this.durationSec,
  });

  factory QueueEntry.fromJson(Map<String, dynamic> j) => QueueEntry(
        trackId: (j['trackId'] ?? '').toString(),
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        coverUrl: absolutizeCover(
            (j['coverUrl'] ?? '') as String, appConfig.radioBaseUrl),
        plannedStartMs: (j['plannedStartMs'] as num?)?.toInt() ?? 0,
        plannedEndMs: (j['plannedEndMs'] as num?)?.toInt() ?? 0,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
      );
}

class StationPublic {
  final bool enabled;
  final String title;
  final String description;
  final String accentColor;

  const StationPublic({
    required this.enabled,
    required this.title,
    required this.description,
    required this.accentColor,
  });

  factory StationPublic.fromJson(Map<String, dynamic> j) => StationPublic(
        enabled: j['enabled'] == true,
        title: (j['title'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        accentColor: (j['accentColor'] ?? '') as String,
      );
}

class StationInfo {
  final String id;
  final String name;
  final bool enabled;
  final StationPublic? public;
  final bool streamAuthEnabled;
  final List<StreamProfile> bitrates;

  const StationInfo({
    required this.id,
    required this.name,
    required this.enabled,
    required this.public,
    required this.streamAuthEnabled,
    required this.bitrates,
  });

  factory StationInfo.fromJson(Map<String, dynamic> j) => StationInfo(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        enabled: j['enabled'] != false,
        public:
            j['public'] == null ? null : StationPublic.fromJson(j['public']),
        streamAuthEnabled: j['streamAuthEnabled'] == true,
        bitrates: ((j['bitrates'] as List?) ?? const [])
            .map((e) => StreamProfile.fromJson(e))
            .toList(),
      );

  List<StreamProfile> get enabledBitrates =>
      bitrates.where((b) => b.enabled).toList();
}

class StationStatus {
  final StationInfo station;
  final int listeners;
  final int uniqueIps;
  final CurrentTrack? current;
  final TrackRef? previous;
  final List<QueueEntry> queue;

  const StationStatus({
    required this.station,
    required this.listeners,
    required this.uniqueIps,
    required this.current,
    required this.previous,
    required this.queue,
  });

  factory StationStatus.fromJson(Map<String, dynamic> j) {
    final totals = _optionalJsonMap(j['totals']);
    return StationStatus(
      station: StationInfo.fromJson(j['station'] as Map<String, dynamic>),
      listeners: (totals['listeners'] as num?)?.toInt() ?? 0,
      uniqueIps: (totals['uniqueIps'] as num?)?.toInt() ?? 0,
      current: j['current'] == null
          ? null
          : CurrentTrack.fromJson(j['current'] as Map<String, dynamic>),
      previous: j['previous'] == null
          ? null
          : TrackRef.fromJson(j['previous'] as Map<String, dynamic>),
      queue: ((j['queue'] as List?) ?? const [])
          .map((e) => QueueEntry.fromJson(e))
          .toList(),
    );
  }
}

// ---------------- 账号后端 ----------------

class ThmrUser {
  final String id;
  final String naidsId;
  final String username;
  final String nickname;
  final String email;
  final bool realnameVerified;
  final String? createdAt;
  final bool needsNickname;

  const ThmrUser({
    required this.id,
    required this.naidsId,
    required this.username,
    required this.nickname,
    required this.email,
    required this.realnameVerified,
    required this.createdAt,
    required this.needsNickname,
  });

  factory ThmrUser.fromJson(Map<String, dynamic> j) => ThmrUser(
        id: (j['id'] ?? '').toString(),
        naidsId: (j['naidsId'] ?? '').toString(),
        username: (j['username'] ?? '') as String,
        nickname: (j['nickname'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        realnameVerified: j['realnameVerified'] == true,
        createdAt: j['createdAt'] as String?,
        needsNickname: j['needsNickname'] == true,
      );

  String get displayName => nickname.isNotEmpty ? nickname : username;
}

class ShareInfo {
  final bool enabled;
  final String slug;
  final String? expiresAt;

  const ShareInfo({
    required this.enabled,
    required this.slug,
    required this.expiresAt,
  });

  factory ShareInfo.fromJson(Map<String, dynamic> j) => ShareInfo(
        enabled: j['enabled'] == true,
        slug: (j['slug'] ?? '') as String,
        expiresAt: j['expiresAt'] as String?,
      );
}

class Collection {
  final String id;
  final String name;
  final String description;
  final int position;
  final int itemCount;
  final String? createdAt;
  final String? updatedAt;
  final ShareInfo share;

  const Collection({
    required this.id,
    required this.name,
    required this.description,
    required this.position,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
    required this.share,
  });

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        position: (j['position'] as num?)?.toInt() ?? 0,
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
        createdAt: j['createdAt'] as String?,
        updatedAt: j['updatedAt'] as String?,
        share: ShareInfo.fromJson(_optionalJsonMap(j['share'])),
      );
}

class CollectionItem {
  final String id;
  final String stationId;
  final String trackId;
  final int position;
  final String title;
  final String artist;
  final String album;
  final int? durationSec;
  final String coverUrl; // 账号后端为绝对 URL
  final String? addedAt;

  const CollectionItem({
    required this.id,
    required this.stationId,
    required this.trackId,
    required this.position,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSec,
    required this.coverUrl,
    required this.addedAt,
  });

  factory CollectionItem.fromJson(Map<String, dynamic> j) => CollectionItem(
        id: (j['id'] ?? '').toString(),
        stationId: (j['stationId'] ?? '').toString(),
        trackId: (j['trackId'] ?? '').toString(),
        position: (j['position'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        album: (j['album'] ?? '') as String,
        durationSec: (j['durationSec'] as num?)?.toInt(),
        coverUrl: absolutizeCover(
            (j['coverUrl'] ?? '') as String, appConfig.radioBaseUrl),
        addedAt: j['addedAt'] as String?,
      );
}

/// `favorites/status` 返回的收藏夹轻量引用。
/// {collectionId, name, favorited, itemId} — 非完整 Collection 对象。
class FavCollectionRef {
  final String collectionId;
  final String name;
  final bool favorited;
  final String? itemId;

  const FavCollectionRef({
    required this.collectionId,
    required this.name,
    required this.favorited,
    required this.itemId,
  });

  factory FavCollectionRef.fromJson(Map<String, dynamic> j) => FavCollectionRef(
        collectionId: (j['collectionId'] ?? '').toString(),
        name: (j['name'] ?? '') as String,
        favorited: j['favorited'] == true,
        itemId: j['itemId']?.toString(),
      );
}

class FavoritesStatus {
  final bool favorited; // 以默认收藏夹为准
  final String? itemId;
  final String? collectionId;
  final List<FavCollectionRef> collections; // 首个 = 默认收藏夹

  const FavoritesStatus({
    required this.favorited,
    required this.itemId,
    required this.collectionId,
    required this.collections,
  });

  factory FavoritesStatus.fromJson(Map<String, dynamic> j) => FavoritesStatus(
        favorited: j['favorited'] == true,
        itemId: j['itemId']?.toString(),
        collectionId: j['collectionId']?.toString(),
        collections: ((j['collections'] as List?) ?? const [])
            .map((e) => FavCollectionRef.fromJson(e))
            .toList(),
      );
}

class LibraryTrack {
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String relativePath;
  final int? durationSec;
  final String coverUrl; // 代理返回绝对 URL

  const LibraryTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.relativePath,
    required this.durationSec,
    required this.coverUrl,
  });

  factory LibraryTrack.fromJson(Map<String, dynamic> j) => LibraryTrack(
        trackId: (j['trackId'] ?? '').toString(),
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        album: (j['album'] ?? '') as String,
        relativePath: (j['relativePath'] ?? '') as String,
        durationSec: (j['durationSec'] as num?)?.toInt(),
        coverUrl: absolutizeCover(
            (j['coverUrl'] ?? '') as String, appConfig.radioBaseUrl),
      );
}

class VoteRound {
  final int votes;
  final int threshold;
  final bool actionTaken;

  const VoteRound({
    required this.votes,
    required this.threshold,
    required this.actionTaken,
  });

  factory VoteRound.fromJson(Map<String, dynamic> j) => VoteRound(
        votes: (j['votes'] as num?)?.toInt() ?? 0,
        threshold: (j['threshold'] as num?)?.toInt() ?? 0,
        actionTaken: j['actionTaken'] == true,
      );
}

class VoteStatus {
  final String stationId;
  final bool active;
  final int listeners;
  final TrackRef? current;
  final VoteRound? round;
  final bool myVote;
  final String? reason;

  const VoteStatus({
    required this.stationId,
    required this.active,
    required this.listeners,
    required this.current,
    required this.round,
    required this.myVote,
    required this.reason,
  });

  factory VoteStatus.fromJson(Map<String, dynamic> j) => VoteStatus(
        stationId: (j['stationId'] ?? '') as String,
        active: j['active'] == true,
        listeners: (j['listeners'] as num?)?.toInt() ?? 0,
        current: j['current'] == null ? null : TrackRef.fromJson(j['current']),
        round: j['round'] == null ? null : VoteRound.fromJson(j['round']),
        myVote: j['myVote'] == true,
        reason: j['reason'] as String?,
      );
}

/// `GET /api/meta` — 启动时拉取,投票阈值 / 上限以它为准。
class ThmrMeta {
  final String version;
  final bool natayarkConfigured;
  final int voteThreshold;
  final int maxPerUser;
  final int maxItemsPerCollection;

  const ThmrMeta({
    required this.version,
    required this.natayarkConfigured,
    required this.voteThreshold,
    required this.maxPerUser,
    required this.maxItemsPerCollection,
  });

  factory ThmrMeta.fromJson(Map<String, dynamic> j) {
    final auth = _optionalJsonMap(j['auth']);
    final vote = _optionalJsonMap(j['vote']);
    final collections = _optionalJsonMap(j['collections']);
    return ThmrMeta(
      version: (j['version'] ?? '') as String,
      natayarkConfigured: auth['natayarkConfigured'] == true,
      voteThreshold: (vote['threshold'] as num?)?.toInt() ?? 0,
      maxPerUser: (collections['maxPerUser'] as num?)?.toInt() ?? 0,
      maxItemsPerCollection:
          (collections['maxItemsPerCollection'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, dynamic> _optionalJsonMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

/// mm:ss 工具。
String formatDuration(int? seconds) {
  final s = (seconds ?? 0).clamp(0, 359999);
  final m = s ~/ 60;
  return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
