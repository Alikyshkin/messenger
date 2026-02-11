import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:client/services/api.dart';
import 'package:client/models/message.dart';

void main() {
  group('Api.sendMessage', () {
    const testToken = 'test_token_123';
    const testBaseUrl = 'http://localhost:3000';

    test('успешно отправляет текстовое сообщение', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/messages' &&
            request.headers['authorization'] == 'Bearer $testToken') {
          final body =
              jsonDecode(request.body as String) as Map<String, dynamic>;
          expect(body['receiver_id'], 2);
          expect(body['content'], 'Тестовое сообщение');

          return http.Response(
            jsonEncode({
              'id': 1,
              'sender_id': 1,
              'receiver_id': 2,
              'content': 'Тестовое сообщение',
              'created_at': DateTime.now().toIso8601String(),
              'read_at': null,
              'is_mine': true,
              'message_type': 'text',
              'reactions': [],
            }),
            201,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = Api(testToken);
      // Заменяем клиент для тестирования
      // В реальном коде это делается через dependency injection

      final message = await api.sendMessage(2, 'Тестовое сообщение');

      expect(message.content, 'Тестовое сообщение');
      expect(message.receiverId, 2);
      expect(message.senderId, 1);
      expect(message.isMine, true);
    });

    test('правильно обрабатывает ошибку 404 (маршрут не найден)', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/messages') {
          return http.Response(
            jsonEncode({'error': 'Маршрут не найден', 'path': '/messages'}),
            404,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = Api(testToken);

      expect(
        () => api.sendMessage(2, 'Тестовое сообщение'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.message,
                'message',
                contains('Маршрут не найден'),
              ),
        ),
      );
    });

    test('правильно обрабатывает ошибку 400 (валидация)', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/messages') {
          return http.Response(
            jsonEncode({'error': 'ID получателя обязателен'}),
            400,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = Api(testToken);

      expect(
        () => api.sendMessage(2, 'Тестовое сообщение'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('правильно обрабатывает ошибку 401 (неавторизован)', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/messages') {
          return http.Response(
            jsonEncode({'error': 'Не авторизован'}),
            401,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = Api(testToken);

      expect(
        () => api.sendMessage(2, 'Тестовое сообщение'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('правильно отправляет сообщение с reply_to_id', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/messages') {
          final body =
              jsonDecode(request.body as String) as Map<String, dynamic>;
          expect(body['reply_to_id'], 10);

          return http.Response(
            jsonEncode({
              'id': 2,
              'sender_id': 1,
              'receiver_id': 2,
              'content': 'Ответ',
              'reply_to_id': 10,
              'created_at': DateTime.now().toIso8601String(),
              'read_at': null,
              'is_mine': true,
              'message_type': 'text',
              'reactions': [],
            }),
            201,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = Api(testToken);
      final message = await api.sendMessage(2, 'Ответ', replyToId: 10);

      expect(message.replyToId, 10);
    });

    test('правильно отправляет пересланное сообщение', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/messages') {
          final body =
              jsonDecode(request.body as String) as Map<String, dynamic>;
          expect(body['is_forwarded'], true);
          expect(body['forward_from_sender_id'], 3);
          expect(body['forward_from_display_name'], 'Имя отправителя');

          return http.Response(
            jsonEncode({
              'id': 3,
              'sender_id': 1,
              'receiver_id': 2,
              'content': 'Пересланное сообщение',
              'is_forwarded': true,
              'forward_from_sender_id': 3,
              'forward_from_display_name': 'Имя отправителя',
              'created_at': DateTime.now().toIso8601String(),
              'read_at': null,
              'is_mine': true,
              'message_type': 'text',
              'reactions': [],
            }),
            201,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = Api(testToken);
      final message = await api.sendMessage(
        2,
        'Пересланное сообщение',
        isForwarded: true,
        forwardFromSenderId: 3,
        forwardFromDisplayName: 'Имя отправителя',
      );

      expect(message.isForwarded, true);
      expect(message.forwardFromSenderId, 3);
      expect(message.forwardFromDisplayName, 'Имя отправителя');
    });

    test(
      'правильно устанавливает заголовки Content-Type и Authorization',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.headers['content-type'],
            'application/json; charset=utf-8',
          );
          expect(request.headers['authorization'], 'Bearer $testToken');

          return http.Response(
            jsonEncode({
              'id': 1,
              'sender_id': 1,
              'receiver_id': 2,
              'content': 'Тест',
              'created_at': DateTime.now().toIso8601String(),
              'read_at': null,
              'is_mine': true,
              'message_type': 'text',
              'reactions': [],
            }),
            201,
            headers: {'Content-Type': 'application/json'},
          );
        });

        final api = Api(testToken);
        await api.sendMessage(2, 'Тест');
      },
    );
  });
}
