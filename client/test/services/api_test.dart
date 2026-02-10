import 'package:flutter_test/flutter_test.dart';
import 'package:client/services/api.dart';

void main() {
  group('ApiException', () {
    test('message and statusCode', () {
      final e = ApiException(400, 'Bad request');
      expect(e.statusCode, 400);
      expect(e.message, 'Bad request');
      expect(e.toString(), 'Bad request');
    });
  });
}
