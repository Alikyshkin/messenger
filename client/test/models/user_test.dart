import 'package:flutter_test/flutter_test.dart';
import 'package:client/models/user.dart';

void main() {
  group('User', () {
    test('fromJson parses full user', () {
      final json = {
        'id': 1,
        'username': 'alice',
        'display_name': 'Alice',
        'bio': 'Hello',
        'avatar_url': 'https://example.com/ava.jpg',
        'public_key': 'key123',
        'email': 'alice@example.com',
      };
      final u = User.fromJson(json);
      expect(u.id, 1);
      expect(u.username, 'alice');
      expect(u.displayName, 'Alice');
      expect(u.bio, 'Hello');
      expect(u.avatarUrl, 'https://example.com/ava.jpg');
      expect(u.publicKey, 'key123');
      expect(u.email, 'alice@example.com');
    });

    test('fromJson uses username when display_name missing', () {
      final u = User.fromJson({'id': 2, 'username': 'bob'});
      expect(u.displayName, 'bob');
    });

    test('copyWith preserves unchanged fields', () {
      final u = User(
        id: 1,
        username: 'x',
        displayName: 'X',
        bio: 'b',
        email: 'x@x.com',
      );
      final u2 = u.copyWith(displayName: 'Y');
      expect(u2.username, 'x');
      expect(u2.displayName, 'Y');
      expect(u2.email, 'x@x.com');
    });
  });
}
