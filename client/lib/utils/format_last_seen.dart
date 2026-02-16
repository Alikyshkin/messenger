import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Форматирует last_seen (ISO 8601) в читаемую строку.
String formatLastSeen(BuildContext context, String? lastSeen, bool? isOnline) {
  if (isOnline == true) {
    return context.tr('online');
  }
  if (lastSeen == null || lastSeen.isEmpty) {
    return '';
  }
  DateTime? dt;
  try {
    dt = DateTime.parse(lastSeen);
  } catch (_) {
    return context.tr('last_seen_long_ago');
  }
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) {
    return context.tr('last_seen_just_now');
  }
  if (diff.inMinutes < 60) {
    return context.tr('last_seen_minutes').replaceFirst('%s', '${diff.inMinutes}');
  }
  if (diff.inHours < 24) {
    return context.tr('last_seen_hours').replaceFirst('%s', '${diff.inHours}');
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (dt.day == yesterday.day && dt.month == yesterday.month && dt.year == yesterday.year) {
    return context.tr('last_seen_yesterday');
  }
  if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return context.tr('last_seen_today').replaceFirst('%s', '$h:$m');
  }
  return context.tr('last_seen_long_ago');
}
