import 'package:flutter_test/flutter_test.dart';

import 'package:pinzon/services/url_normalizer.dart';

void main() {
  test('normalization removes fragment and trailing slash but keeps query for MVP', () {
    final normalizer = UrlNormalizer();
    expect(
      normalizer.normalize('HTTPS://Example.com/item/?utm_source=x#section'),
      'https://example.com/item?utm_source=x',
    );
  });
}
