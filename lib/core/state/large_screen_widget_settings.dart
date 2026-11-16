import 'package:flutter/material.dart';

enum LargeScreenWidgetKind { clock, date, text }

enum LargeScreenWidgetPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight
}

enum LargeScreenWidgetFont { inherit, sans, mono }

enum LargeScreenWidgetTone { ink, muted, accent, custom }

enum LargeScreenWidgetDecoration { none, rule, label }

enum LargeScreenWidgetTimezone { local, beijing, utc }

class LargeScreenWidgetSettings {
  const LargeScreenWidgetSettings({
    required this.id,
    this.kind = LargeScreenWidgetKind.clock,
    this.position = LargeScreenWidgetPosition.topRight,
    this.text = '',
    this.format = 'HH:mm',
    this.fontSize = 28,
    this.font = LargeScreenWidgetFont.inherit,
    this.weight = 400,
    this.tone = LargeScreenWidgetTone.ink,
    this.color = 0xFFFFFFFF,
    this.decoration = LargeScreenWidgetDecoration.none,
    this.timezone = LargeScreenWidgetTimezone.local,
    this.italic = false,
    this.letterSpacing = 0,
    this.opacity = 1,
    this.maxLines = 2,
    this.enabled = true,
  });
  final String id;
  final LargeScreenWidgetKind kind;
  final LargeScreenWidgetPosition position;
  final String text;
  final String format;
  final double fontSize;
  final LargeScreenWidgetFont font;
  final int weight;
  final LargeScreenWidgetTone tone;
  final int color;
  final LargeScreenWidgetDecoration decoration;
  final LargeScreenWidgetTimezone timezone;
  final bool italic;
  final double letterSpacing;
  final double opacity;
  final int maxLines;
  final bool enabled;
  bool get atTop => position.index < 3;
  int get column => position.index % 3;
  bool get needsClock =>
      kind != LargeScreenWidgetKind.text ||
      RegExp(r'\{(time|date|weekday)\}').hasMatch(text);
  String get label => switch (kind) {
        LargeScreenWidgetKind.clock => '时间',
        LargeScreenWidgetKind.date => '日期',
        LargeScreenWidgetKind.text => '文本',
      };
  TextAlign get textAlign =>
      [TextAlign.left, TextAlign.center, TextAlign.right][column];

  LargeScreenWidgetSettings copyWith(
          {String? id,
          LargeScreenWidgetKind? kind,
          LargeScreenWidgetPosition? position,
          String? text,
          String? format,
          double? fontSize,
          LargeScreenWidgetFont? font,
          int? weight,
          LargeScreenWidgetTone? tone,
          int? color,
          LargeScreenWidgetDecoration? decoration,
          LargeScreenWidgetTimezone? timezone,
          bool? italic,
          double? letterSpacing,
          double? opacity,
          int? maxLines,
          bool? enabled}) =>
      LargeScreenWidgetSettings(
          id: id ?? this.id,
          kind: kind ?? this.kind,
          position: position ?? this.position,
          text: text ?? this.text,
          format: format ?? this.format,
          fontSize: fontSize ?? this.fontSize,
          font: font ?? this.font,
          weight: weight ?? this.weight,
          tone: tone ?? this.tone,
          color: color ?? this.color,
          decoration: decoration ?? this.decoration,
          timezone: timezone ?? this.timezone,
          italic: italic ?? this.italic,
          letterSpacing: letterSpacing ?? this.letterSpacing,
          opacity: opacity ?? this.opacity,
          maxLines: maxLines ?? this.maxLines,
          enabled: enabled ?? this.enabled);

  factory LargeScreenWidgetSettings.fromJson(Map<String, dynamic> json,
      {required String fallbackId}) {
    T choice<T extends Enum>(String key, List<T> values, T fallback) =>
        values.firstWhere((v) => v.name == json[key], orElse: () => fallback);
    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    String string(String key, String fallback, int max) {
      final value = json[key];
      if (value is! String) return fallback;
      return value.length > max ? value.substring(0, max) : value;
    }

    final kind = choice(
        'kind', LargeScreenWidgetKind.values, LargeScreenWidgetKind.clock);
    return LargeScreenWidgetSettings(
      id: string('id', fallbackId, 100),
      kind: kind,
      position: choice('position', LargeScreenWidgetPosition.values,
          LargeScreenWidgetPosition.topRight),
      text: string('text', '', 500),
      format: string('format',
          kind == LargeScreenWidgetKind.date ? 'yyyy年M月d日 EEEE' : 'HH:mm', 100),
      fontSize: number('fontSize', 28, 12, 96),
      font: choice(
          'font', LargeScreenWidgetFont.values, LargeScreenWidgetFont.inherit),
      weight: [400, 600, 800].contains(json['weight'])
          ? json['weight'] as int
          : 400,
      tone: choice(
          'tone', LargeScreenWidgetTone.values, LargeScreenWidgetTone.ink),
      color: json['color'] is int
          ? (json['color'] as int).clamp(0, 0xFFFFFFFF)
          : 0xFFFFFFFF,
      decoration: choice('decoration', LargeScreenWidgetDecoration.values,
          LargeScreenWidgetDecoration.none),
      timezone: choice('timezone', LargeScreenWidgetTimezone.values,
          LargeScreenWidgetTimezone.local),
      italic: json['italic'] == true,
      letterSpacing: number('letterSpacing', 0, 0, 12),
      opacity: number('opacity', 1, .3, 1),
      maxLines: number('maxLines', 2, 1, 4).round(),
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'position': position.name,
        'text': text,
        'format': format,
        'fontSize': fontSize,
        'font': font.name,
        'weight': weight,
        'tone': tone.name,
        'color': color,
        'decoration': decoration.name,
        'timezone': timezone.name,
        'italic': italic,
        'letterSpacing': letterSpacing,
        'opacity': opacity,
        'maxLines': maxLines,
        'enabled': enabled,
      };
}

String formatLargeScreenDate(DateTime value, String format) {
  String pad(int n) => '$n'.padLeft(2, '0');
  const days = ['一', '二', '三', '四', '五', '六', '日'];
  final fields = <String, String>{
    'yyyy': '${value.year}',
    'yy': pad(value.year % 100),
    'MM': pad(value.month),
    'M': '${value.month}',
    'dd': pad(value.day),
    'd': '${value.day}',
    'EEEE': '星期${days[value.weekday - 1]}',
    'EEE': '周${days[value.weekday - 1]}',
    'HH': pad(value.hour),
    'H': '${value.hour}',
    'hh': pad(value.hour % 12 == 0 ? 12 : value.hour % 12),
    'h': '${value.hour % 12 == 0 ? 12 : value.hour % 12}',
    'mm': pad(value.minute),
    'ss': pad(value.second),
    'a': value.hour < 12 ? '上午' : '下午',
  };
  return format.replaceAllMapped(
      RegExp(r'yyyy|yy|EEEE|EEE|MM|dd|HH|hh|mm|ss|M|d|H|h|a'),
      (m) => fields[m[0]]!);
}

String largeScreenWidgetText(LargeScreenWidgetSettings widget, DateTime now,
    {String title = '', String artist = '', String channel = ''}) {
  final time = switch (widget.timezone) {
    LargeScreenWidgetTimezone.local => now.toLocal(),
    LargeScreenWidgetTimezone.beijing =>
      now.toUtc().add(const Duration(hours: 8)),
    LargeScreenWidgetTimezone.utc => now.toUtc(),
  };
  if (widget.kind != LargeScreenWidgetKind.text) {
    return formatLargeScreenDate(time, widget.format);
  }
  final fields = <String, String>{
    'title': title,
    'artist': artist,
    'channel': channel,
    'time': formatLargeScreenDate(time, widget.format),
    'date': formatLargeScreenDate(time, 'yyyy-MM-dd'),
    'weekday': formatLargeScreenDate(time, 'EEEE'),
  };
  return widget.text.replaceAllMapped(
      RegExp(r'\{(title|artist|channel|time|date|weekday)\}'),
      (m) => fields[m[1]] ?? '');
}
