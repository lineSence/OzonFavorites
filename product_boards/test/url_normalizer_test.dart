import 'package:flutter_test/flutter_test.dart';
import 'package:pinzon/services/url_normalizer.dart';

void main() {
  test('removes fragment and trailing slash but keeps query', () {
    final value = UrlNormalizer().normalize('https://EXAMPLE.com/item/?utm_source=x#section');
    expect(value, 'https://example.com/item?utm_source=x');
  });
}
