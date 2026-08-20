class UrlNormalizer {
  String normalize(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return value.trim().toLowerCase();
    final withoutFragment = uri.replace(fragment: '');
    return withoutFragment.toString().replaceFirst(RegExp(r'/$'), '').toLowerCase();
  }
}
