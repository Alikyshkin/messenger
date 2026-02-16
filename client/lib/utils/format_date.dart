/// Форматирует дату сообщения для отображения в списке (короткий формат).
String formatMessageDate(String iso8601) {
  try {
    final dt = DateTime.parse(iso8601);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    if (msgDate == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (msgDate == yesterday) {
      return 'Вчера';
    }
    if (now.difference(dt).inDays < 7) {
      const days = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
      return days[dt.weekday % 7];
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  } catch (_) {
    return '';
  }
}
