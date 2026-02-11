import 'package:flutter_test/flutter_test.dart';
import 'package:client/models/message.dart';

void main() {
  group('Message', () {
    test('fromJson parses text message', () {
      final json = {
        'id': 10,
        'sender_id': 1,
        'receiver_id': 2,
        'content': 'Hello',
        'created_at': '2025-01-01T12:00:00Z',
        'read_at': null,
        'is_mine': true,
        'attachment_url': null,
        'message_type': 'text',
        'attachment_encrypted': false,
      };
      final m = Message.fromJson(json);
      expect(m.id, 10);
      expect(m.senderId, 1);
      expect(m.receiverId, 2);
      expect(m.content, 'Hello');
      expect(m.isMine, true);
      expect(m.hasAttachment, false);
      expect(m.isPoll, false);
      expect(m.attachmentEncrypted, false);
    });

    test('fromJson parses message with attachment', () {
      final json = {
        'id': 11,
        'sender_id': 1,
        'receiver_id': 2,
        'content': '(файл)',
        'created_at': '2025-01-01T12:00:00Z',
        'is_mine': false,
        'attachment_url': 'https://example.com/file.pdf',
        'attachment_filename': 'doc.pdf',
        'attachment_kind': 'file',
        'attachment_encrypted': true,
      };
      final m = Message.fromJson(json);
      expect(m.attachmentUrl, 'https://example.com/file.pdf');
      expect(m.attachmentFilename, 'doc.pdf');
      expect(m.hasAttachment, true);
      expect(m.attachmentEncrypted, true);
    });

    test('fromJson parses poll message', () {
      final json = {
        'id': 12,
        'sender_id': 1,
        'receiver_id': 2,
        'content': 'Question?',
        'created_at': '2025-01-01T12:00:00Z',
        'is_mine': true,
        'message_type': 'poll',
        'poll_id': 5,
        'poll': {
          'id': 5,
          'question': 'Question?',
          'options': [
            {'text': 'A', 'votes': 2, 'voted': true},
            {'text': 'B', 'votes': 1, 'voted': false},
          ],
          'multiple': false,
        },
      };
      final m = Message.fromJson(json);
      expect(m.isPoll, true);
      expect(m.poll!.id, 5);
      expect(m.poll!.question, 'Question?');
      expect(m.poll!.options.length, 2);
      expect(m.poll!.options[0].text, 'A');
      expect(m.poll!.options[0].votes, 2);
      expect(m.poll!.options[0].voted, true);
    });

    test('isVoice and isVideoNote', () {
      expect(
        Message.fromJson({
          'id': 1,
          'sender_id': 1,
          'receiver_id': 2,
          'content': '',
          'created_at': '',
          'is_mine': false,
          'attachment_kind': 'voice',
          'attachment_url': 'https://x/voice.m4a',
        }).isVoice,
        true,
      );
      expect(
        Message.fromJson({
          'id': 1,
          'sender_id': 1,
          'receiver_id': 2,
          'content': '',
          'created_at': '',
          'is_mine': false,
          'attachment_kind': 'video_note',
          'attachment_url': 'https://x/v.mp4',
        }).isVideoNote,
        true,
      );
    });

    test('fromJson parses message with reactions', () {
      final json = {
        'id': 20,
        'sender_id': 1,
        'receiver_id': 2,
        'content': 'Hi',
        'created_at': '2025-01-01T12:00:00Z',
        'is_mine': true,
        'message_type': 'text',
        'reactions': [
          {
            'emoji': '👍',
            'user_ids': [2, 3],
          },
          {
            'emoji': '❤️',
            'user_ids': [1],
          },
        ],
      };
      final m = Message.fromJson(json);
      expect(m.reactions.length, 2);
      expect(m.reactions[0].emoji, '👍');
      expect(m.reactions[0].userIds, [2, 3]);
      expect(m.reactions[0].count, 2);
      expect(m.reactions[1].emoji, '❤️');
      expect(m.reactions[1].userIds, [1]);
      expect(m.reactions[1].count, 1);
    });

    test('fromJson parses message without reactions as empty list', () {
      final m = Message.fromJson({
        'id': 1,
        'sender_id': 1,
        'receiver_id': 2,
        'content': 'x',
        'created_at': '',
        'is_mine': false,
      });
      expect(m.reactions, isEmpty);
    });

    test('copyWith updates reactions', () {
      final m = Message.fromJson({
        'id': 1,
        'sender_id': 1,
        'receiver_id': 2,
        'content': 'x',
        'created_at': '',
        'is_mine': false,
        'reactions': [
          {
            'emoji': '👍',
            'user_ids': [2],
          },
        ],
      });
      final updated = m.copyWith(
        reactions: [
          MessageReaction(emoji: '❤️', userIds: [2, 3]),
        ],
      );
      expect(updated.reactions.length, 1);
      expect(updated.reactions[0].emoji, '❤️');
      expect(updated.reactions[0].count, 2);
      expect(m.reactions[0].emoji, '👍'); // original unchanged
    });

    test('isGroupMessage when group_id present', () {
      final m = Message.fromJson({
        'id': 1,
        'sender_id': 1,
        'receiver_id': 0,
        'group_id': 5,
        'content': 'x',
        'created_at': '',
        'is_mine': false,
      });
      expect(m.isGroupMessage, true);
      expect(m.groupId, 5);
    });
  });
}
