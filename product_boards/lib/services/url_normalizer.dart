class UrlNormalizer {
  String normalize(String value) {
    var raw = value.trim();
    if (raw.isEmpty) return raw;
    final hash = raw.indexOf('#');
    if (hash >= 0) raw = raw.substring(0, hash);
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw.toLowerCase().replaceFirst(RegExp(r'/$'), '');
    final path = uri.path.length > 1 && uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      userInfo: uri.userInfo,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: path,
      query: uri.hasQuery ? uri.query : null,
    ).toString().toLowerCase();
  }
}
