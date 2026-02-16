import 'dart:html' as html;

/// Отзывает blob URL на веб.
void revokeBlobUrl(String url) {
  try {
    html.Url.revokeObjectUrl(url);
  } catch (_) {
    // Игнорируем ошибки при отзыве URL
  }
}
