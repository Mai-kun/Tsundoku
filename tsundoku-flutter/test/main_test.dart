import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/main.dart';

void main() {
  group('parseBaseUrl CLI argument parsing', () {
    test('parses --url <value>', () {
      final url = parseBaseUrl(['--url', 'http://127.0.0.1:5099']);
      expect(url, 'http://127.0.0.1:5099');
    });

    test('parses --url=<value>', () {
      final url = parseBaseUrl(['--url=http://192.168.1.100:5000']);
      expect(url, 'http://192.168.1.100:5000');
    });

    test('ignores unrelated flags and finds --url', () {
      final url = parseBaseUrl(['--verbose', '--data-dir', '/tmp', '--url', 'http://localhost:5000']);
      expect(url, 'http://localhost:5000');
    });

    test('falls back to default http://127.0.0.1:5000 on desktop when no args provided', () {
      final url = parseBaseUrl([]);
      expect(url, 'http://127.0.0.1:5000');
    });
  });
}
