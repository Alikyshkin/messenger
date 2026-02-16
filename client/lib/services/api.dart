import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../models/chat.dart';
import '../models/group.dart';
import '../models/friend_request.dart';

List<MessageReaction> _parseReactions(dynamic v) {
  if (v is! List) {
    return [];
  }
  final list = <MessageReaction>[];
  for (final e in v) {
    if (e is! Map<String, dynamic>) continue;
    final emoji = e['emoji'] as String?;
    final ids = e['user_ids'];
    if (emoji == null || emoji.isEmpty) continue;
    final userIds = ids is List
        ? (ids
              .map((x) => x is int ? x : (x is num ? x.toInt() : null))
              .whereType<int>()
              .toList())
        : <int>[];
    list.add(MessageReaction(emoji: emoji, userIds: userIds));
  }
  return list;
}

class Api {
  final String token;
  final String base = apiBaseUrl;

  Api(this.token);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// Декодируем тело ответа как UTF-8 (корректное отображение кириллицы в сообщениях и профилях).
  static String _utf8Body(http.Response r) {
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  void _checkResponse(http.Response r) {
    if (r.statusCode >= 400) {
      final body = _utf8Body(r);
      String msg = body;
      try {
        final m = jsonDecode(body) as Map<String, dynamic>;
        msg = m['error'] as String? ?? body;
      } catch (_) {}
      throw ApiException(r.statusCode, msg);
    }
  }

  Future<User> register(
    String username,
    String password, [
    String? displayName,
    String? email,
  ]) async {
    final r = await http.post(
      Uri.parse('$base/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'password': password,
        if (displayName != null && displayName.isNotEmpty)
          'displayName': displayName,
        if (email != null && email.trim().isNotEmpty)
          'email': email.trim().toLowerCase(),
      }),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AuthResponse> login(String username, String password) async {
    final r = await http.post(
      Uri.parse('$base/auth/login'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return AuthResponse(
      user: User.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  /// Получить список доступных OAuth провайдеров
  Future<OAuthProviders> getOAuthProviders() async {
    final r = await http.get(Uri.parse('$base/auth/oauth/providers'), headers: _headers);
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return OAuthProviders(
      google: data['google'] as bool? ?? false,
      vk: data['vk'] as bool? ?? false,
      telegram: data['telegram'] as bool? ?? false,
      phone: data['phone'] as bool? ?? false,
    );
  }

  Future<AuthResponse> loginWithGoogle(String idToken) async {
    final r = await http.post(
      Uri.parse('$base/auth/oauth/google'),
      headers: _headers,
      body: jsonEncode({'idToken': idToken}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return AuthResponse(
      user: User.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  Future<AuthResponse> loginWithVk(String accessToken, String userId) async {
    final r = await http.post(
      Uri.parse('$base/auth/oauth/vk'),
      headers: _headers,
      body: jsonEncode({'accessToken': accessToken, 'userId': userId}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return AuthResponse(
      user: User.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  Future<AuthResponse> loginWithTelegram(Map<String, dynamic> authData) async {
    final r = await http.post(
      Uri.parse('$base/auth/oauth/telegram'),
      headers: _headers,
      body: jsonEncode(authData),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return AuthResponse(
      user: User.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  Future<void> sendPhoneCode(String phone) async {
    final r = await http.post(
      Uri.parse('$base/auth/oauth/phone/send-code'),
      headers: _headers,
      body: jsonEncode({'phone': phone}),
    );
    _checkResponse(r);
  }

  Future<AuthResponse> verifyPhoneCode(String phone, String code) async {
    final r = await http.post(
      Uri.parse('$base/auth/oauth/phone/verify'),
      headers: _headers,
      body: jsonEncode({'phone': phone, 'code': code}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return AuthResponse(
      user: User.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  Future<User> me() async {
    final r = await http.get(Uri.parse('$base/users/me'), headers: _headers);
    _checkResponse(r);
    return User.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<void> deleteAccount() async {
    final r = await http.delete(Uri.parse('$base/users/me'), headers: _headers);
    _checkResponse(r);
  }

  Future<User> patchMe({
    String? displayName,
    String? username,
    String? bio,
    String? publicKey,
    String? email,
    String? birthday,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) {
      body['display_name'] = displayName;
    }
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    if (publicKey != null) body['public_key'] = publicKey;
    if (email != null) body['email'] = email;
    if (birthday != null) body['birthday'] = birthday.isEmpty ? null : birthday;
    if (phone != null) body['phone'] = phone.isEmpty ? null : phone;
    final r = await http.patch(
      Uri.parse('$base/users/me'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkResponse(r);
    return User.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<User> uploadAvatar(List<int> fileBytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/users/me/avatar'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes('avatar', fileBytes, filename: filename),
    );
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return User.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  /// Публичный профиль пользователя (имя, био, аватар, количество друзей — без списка друзей).
  Future<User> getUserProfile(int userId) async {
    final r = await http.get(
      Uri.parse('$base/users/$userId'),
      headers: _headers,
    );
    _checkResponse(r);
    return User.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<void> blockUser(int userId) async {
    final r = await http.post(
      Uri.parse('$base/users/$userId/block'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  Future<void> unblockUser(int userId) async {
    final r = await http.delete(
      Uri.parse('$base/users/$userId/block'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  Future<List<User>> searchUsers(String q) async {
    final r = await http.get(
      Uri.parse('$base/users/search').replace(queryParameters: {'q': q}),
      headers: _headers,
    );
    _checkResponse(r);
    final list = jsonDecode(_utf8Body(r)) as List<dynamic>;
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<User>> getContacts() async {
    final r = await http.get(Uri.parse('$base/contacts'), headers: _headers);
    _checkResponse(r);
    final json = jsonDecode(_utf8Body(r));
    // API возвращает { data: [...], pagination: {...} } или просто массив
    final list = json is Map<String, dynamic>
        ? (json['data'] as List<dynamic>? ?? [])
        : (json as List<dynamic>);
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Отправить заявку в друзья (друг появится в списке после одобрения).
  Future<User> addContact(String username) async {
    final r = await http.post(
      Uri.parse('$base/contacts'),
      headers: _headers,
      body: jsonEncode({'username': username}),
    );
    _checkResponse(r);
    return User.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<List<FriendRequest>> getFriendRequestsIncoming() async {
    final r = await http.get(
      Uri.parse('$base/contacts/requests/incoming'),
      headers: _headers,
    );
    _checkResponse(r);
    final list = jsonDecode(_utf8Body(r)) as List<dynamic>;
    return list
        .map((e) => FriendRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Идентификаторы пользователей, которым я отправил заявку в друзья (ожидают подтверждения).
  Future<List<int>> getFriendRequestsOutgoing() async {
    final r = await http.get(
      Uri.parse('$base/contacts/requests/outgoing'),
      headers: _headers,
    );
    _checkResponse(r);
    final list = jsonDecode(_utf8Body(r)) as List<dynamic>;
    return list
        .map((e) => (e as Map<String, dynamic>)['to_user_id'] as int)
        .toList();
  }

  Future<void> acceptFriendRequest(int requestId) async {
    final r = await http.post(
      Uri.parse('$base/contacts/requests/$requestId/accept'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  Future<void> rejectFriendRequest(int requestId) async {
    final r = await http.post(
      Uri.parse('$base/contacts/requests/$requestId/reject'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  Future<void> removeContact(int userId) async {
    final r = await http.delete(
      Uri.parse('$base/contacts/$userId'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  /// Найти пользователей по номерам телефонов (из контактов устройства).
  Future<List<User>> findUsersByPhones(List<String> phones) async {
    if (phones.isEmpty) {
      return [];
    }
    try {
      final r = await http.post(
        Uri.parse('$base/users/find-by-phones'),
        headers: _headers,
        body: jsonEncode({'phones': phones}),
      );
      _checkResponse(r);
      final json = jsonDecode(_utf8Body(r));
      // API может вернуть массив или объект с data
      final list = json is Map<String, dynamic>
          ? (json['data'] as List<dynamic>? ?? [])
          : (json as List<dynamic>? ?? []);
      return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException(
        500,
        'Ошибка при поиске пользователей по телефонам: ${e.toString()}',
      );
    }
  }

  Future<List<ChatPreview>> getChats() async {
    final r = await http.get(Uri.parse('$base/chats'), headers: _headers);
    _checkResponse(r);
    final json = jsonDecode(_utf8Body(r));
    // API возвращает { data: [...], pagination: {...} } или просто массив
    final list = json is Map<String, dynamic>
        ? (json['data'] as List<dynamic>? ?? [])
        : (json as List<dynamic>);
    return list
        .map((e) => ChatPreview.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Получить медиа файлы из чата
  Future<Map<String, dynamic>> getMedia(
    int peerId, {
    String type = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$base/media/$peerId').replace(
      queryParameters: {
        'type': type,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    final r = await http.get(uri, headers: _headers);
    _checkResponse(r);
    return jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
  }

  /// Получить медиа файлы из группового чата
  Future<Map<String, dynamic>> getGroupMedia(
    int groupId, {
    String type = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$base/media/groups/$groupId').replace(
      queryParameters: {
        'type': type,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    final r = await http.get(uri, headers: _headers);
    _checkResponse(r);
    return jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
  }

  /// Получить статус синхронизации
  Future<Map<String, dynamic>> getSyncStatus() async {
    final r = await http.get(Uri.parse('$base/sync/status'), headers: _headers);
    _checkResponse(r);
    return jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
  }

  /// Синхронизировать сообщения
  Future<Map<String, dynamic>> syncMessages(
    String lastSyncTime, {
    List<int>? peerIds,
  }) async {
    final r = await http.post(
      Uri.parse('$base/sync/messages'),
      headers: _headers,
      body: jsonEncode({
        'lastSyncTime': lastSyncTime,
        ...?peerIds != null ? {'peerIds': peerIds} : null,
      }),
    );
    _checkResponse(r);
    return jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
  }

  Future<void> markMessagesRead(int peerId) async {
    final r = await http.patch(
      Uri.parse('$base/messages/$peerId/read'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  /// Редактирует текстовое сообщение. Возвращает обновлённый контент.
  Future<String> editMessage(int messageId, String content) async {
    final r = await http.patch(
      Uri.parse('$base/messages/$messageId'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );
    _checkResponse(r);
    final json = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return json['content'] as String;
  }

  Future<List<Message>> getMessages(
    int peerId, {
    int? before,
    int limit = 100,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (before != null) {
      params['before'] = before.toString();
    }
    final r = await http.get(
      Uri.parse('$base/messages/$peerId').replace(queryParameters: params),
      headers: _headers,
    );
    _checkResponse(r);
    final json = jsonDecode(_utf8Body(r));
    // API возвращает { data: [...], pagination: {...} } или просто массив
    final list = json is Map<String, dynamic>
        ? (json['data'] as List<dynamic>? ?? [])
        : (json as List<dynamic>);
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Message> sendMessage(
    int receiverId,
    String content, {
    int? replyToId,
    bool isForwarded = false,
    int? forwardFromSenderId,
    String? forwardFromDisplayName,
  }) async {
    final body = <String, dynamic>{
      'receiver_id': receiverId,
      'content': content,
    };
    if (replyToId != null) {
      body['reply_to_id'] = replyToId;
    }
    if (isForwarded) {
      body['is_forwarded'] = true;
      if (forwardFromSenderId != null) {
        body['forward_from_sender_id'] = forwardFromSenderId;
      }
      if (forwardFromDisplayName != null) {
        body['forward_from_display_name'] = forwardFromDisplayName;
      }
    }
    http.Response? r;
    try {
      r = await http.post(
        Uri.parse('$base/messages'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(r);
      final json = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
      return Message.fromJson(json);
    } catch (e) {
      // Если это ошибка парсинга, но запрос был успешным (201), значит сообщение отправлено
      if (r != null && r.statusCode == 201) {
        // Пытаемся распарсить ответ еще раз с более мягкой обработкой
        try {
          final json = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
          return Message.fromJson(json);
        } catch (_) {
          // Если все равно не получается, выбрасываем ошибку парсинга
          throw ApiException(
            500,
            'Ошибка парсинга ответа сервера: ${e.toString()}',
          );
        }
      }
      // Для всех остальных ошибок пробрасываем дальше
      rethrow;
    }
  }

  Future<Message> sendMissedCallMessage(int receiverId) async {
    final body = <String, dynamic>{
      'receiver_id': receiverId,
      'type': 'missed_call',
      'content': '',
    };
    final r = await http.post(
      Uri.parse('$base/messages'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkResponse(r);
    final json = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return Message.fromJson(json);
  }

  Future<Message> sendMessageWithFile(
    int receiverId,
    String content,
    List<int> fileBytes,
    String filename, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$base/messages'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = content;
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  /// Отправка нескольких файлов (например, альбом фото). Возвращает список сообщений.
  Future<List<Message>> sendMessageWithMultipleFiles(
    int receiverId,
    String content,
    List<({List<int> bytes, String filename})> files, {
    bool attachmentEncrypted = false,
  }) async {
    if (files.isEmpty) {
      return [];
    }
    final request = http.MultipartRequest('POST', Uri.parse('$base/messages'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = content;
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    for (final f in files) {
      request.files.add(
        http.MultipartFile.fromBytes('file', f.bytes, filename: f.filename),
      );
    }
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r));
    if (data is Map<String, dynamic> && data['messages'] != null) {
      final list = data['messages'] as List<dynamic>;
      return list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [Message.fromJson(data as Map<String, dynamic>)];
  }

  Future<Message> sendVoiceMessage(
    int receiverId,
    List<int> fileBytes,
    String filename,
    int durationSec, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$base/messages'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = '';
    request.fields['attachment_kind'] = 'voice';
    request.fields['attachment_duration_sec'] = durationSec.toString();
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<Message> sendVideoNoteMessage(
    int receiverId,
    List<int> fileBytes,
    String filename,
    int durationSec, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$base/messages'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = '';
    request.fields['attachment_kind'] = 'video_note';
    request.fields['attachment_duration_sec'] = durationSec.toString();
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<void> deleteMessage(int messageId, {bool forMe = false}) async {
    final uri = Uri.parse('$base/messages/$messageId');
    final url = forMe ? uri.replace(queryParameters: {'for_me': 'true'}) : uri;
    final r = await http.delete(url, headers: _headers);
    _checkResponse(r);
  }

  Future<List<MessageReaction>> setMessageReaction(
    int messageId,
    String emoji,
  ) async {
    final r = await http.post(
      Uri.parse('$base/messages/$messageId/reaction'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'emoji': emoji}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    final reactions = data['reactions'];
    return _parseReactions(reactions);
  }

  Future<List<MessageReaction>> setGroupMessageReaction(
    int groupId,
    int messageId,
    String emoji,
  ) async {
    final r = await http.post(
      Uri.parse('$base/groups/$groupId/messages/$messageId/reaction'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'emoji': emoji}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    return _parseReactions(data['reactions']);
  }

  Future<void> forgotPassword(String email) async {
    final r = await http.post(
      Uri.parse('$base/auth/forgot-password'),
      headers: _headers,
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );
    _checkResponse(r);
  }

  Future<void> resetPassword(String token, String newPassword) async {
    final r = await http.post(
      Uri.parse('$base/auth/reset-password'),
      headers: _headers,
      body: jsonEncode({'token': token, 'newPassword': newPassword}),
    );
    _checkResponse(r);
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final r = await http.post(
      Uri.parse('$base/auth/change-password'),
      headers: _headers,
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    _checkResponse(r);
  }

  static Future<List<int>> getAttachmentBytes(String url) async {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, 'Ошибка загрузки');
    }
    List<int> bytes = r.bodyBytes;
    if (url.endsWith('.gz')) {
      bytes = GZipDecoder().decodeBytes(bytes);
    }
    return bytes;
  }

  Future<Message> sendPoll(
    int receiverId,
    String question,
    List<String> options, {
    bool multiple = false,
  }) async {
    final r = await http.post(
      Uri.parse('$base/messages'),
      headers: _headers,
      body: jsonEncode({
        'receiver_id': receiverId,
        'type': 'poll',
        'question': question,
        'options': options,
        'multiple': multiple,
      }),
    );
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<PollResult> votePoll(int pollId, int optionIndex) async {
    final r = await http.post(
      Uri.parse('$base/polls/$pollId/vote'),
      headers: _headers,
      body: jsonEncode({'option_index': optionIndex}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    final opts = (data['options'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return PollResult(
      options: opts
          .map(
            (o) => PollOptionResult(
              text: o['text'] as String,
              votes: o['votes'] as int,
              voted: o['voted'] as bool? ?? false,
            ),
          )
          .toList(),
    );
  }

  // ——— Группы ———
  Future<List<Group>> getGroups() async {
    final r = await http.get(Uri.parse('$base/groups'), headers: _headers);
    _checkResponse(r);
    final list = jsonDecode(_utf8Body(r)) as List<dynamic>;
    return list.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Group> createGroup(
    String name,
    List<int> memberIds, {
    List<int>? avatarBytes,
    String? avatarFilename,
  }) async {
    if (avatarBytes != null &&
        avatarBytes.isNotEmpty &&
        avatarFilename != null) {
      final request = http.MultipartRequest('POST', Uri.parse('$base/groups'));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['name'] = name;
      request.fields['member_ids'] = jsonEncode(memberIds);
      request.files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          avatarBytes,
          filename: avatarFilename,
        ),
      );
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      _checkResponse(resp);
      return Group.fromJson(
        jsonDecode(_utf8Body(resp)) as Map<String, dynamic>,
      );
    }
    final r = await http.post(
      Uri.parse('$base/groups'),
      headers: _headers,
      body: jsonEncode({'name': name, 'member_ids': memberIds}),
    );
    _checkResponse(r);
    return Group.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<Group> getGroup(int groupId) async {
    final r = await http.get(
      Uri.parse('$base/groups/$groupId'),
      headers: _headers,
    );
    _checkResponse(r);
    return Group.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<Group> updateGroup(
    int groupId, {
    String? name,
    List<int>? avatarBytes,
    String? avatarFilename,
  }) async {
    if (avatarBytes != null &&
        avatarBytes.isNotEmpty &&
        avatarFilename != null) {
      final request = http.MultipartRequest(
        'PATCH',
        Uri.parse('$base/groups/$groupId'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      if (name != null) {
        request.fields['name'] = name;
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          avatarBytes,
          filename: avatarFilename,
        ),
      );
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      _checkResponse(resp);
      return Group.fromJson(
        jsonDecode(_utf8Body(resp)) as Map<String, dynamic>,
      );
    }
    final body = <String, dynamic>{};
    if (name != null) {
      body['name'] = name;
    }
    if (body.isEmpty) {
      throw ApiException(400, 'Укажите name и/или загрузите avatar');
    }
    final r = await http.patch(
      Uri.parse('$base/groups/$groupId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkResponse(r);
    return Group.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<void> addGroupMembers(int groupId, List<int> userIds) async {
    final r = await http.post(
      Uri.parse('$base/groups/$groupId/members'),
      headers: _headers,
      body: jsonEncode({'user_ids': userIds}),
    );
    _checkResponse(r);
  }

  Future<void> removeGroupMember(int groupId, int userId) async {
    final r = await http.delete(
      Uri.parse('$base/groups/$groupId/members/$userId'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  Future<List<Message>> getGroupMessages(
    int groupId, {
    int? before,
    int limit = 100,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (before != null) {
      params['before'] = before.toString();
    }
    final r = await http.get(
      Uri.parse(
        '$base/groups/$groupId/messages',
      ).replace(queryParameters: params),
      headers: _headers,
    );
    _checkResponse(r);
    final json = jsonDecode(_utf8Body(r));
    // API возвращает { data: [...], pagination: {...} } или просто массив
    final list = json is Map<String, dynamic>
        ? (json['data'] as List<dynamic>? ?? [])
        : (json as List<dynamic>);
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markGroupMessagesRead(int groupId, int lastMessageId) async {
    final r = await http.patch(
      Uri.parse('$base/groups/$groupId/read'),
      headers: _headers,
      body: jsonEncode({'last_message_id': lastMessageId}),
    );
    _checkResponse(r);
  }

  Future<Message> sendGroupMessage(
    int groupId,
    String content, {
    int? replyToId,
    bool isForwarded = false,
    int? forwardFromSenderId,
    String? forwardFromDisplayName,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (replyToId != null) {
      body['reply_to_id'] = replyToId;
    }
    if (isForwarded) {
      body['is_forwarded'] = true;
      if (forwardFromSenderId != null) {
        body['forward_from_sender_id'] = forwardFromSenderId;
      }
      if (forwardFromDisplayName != null) {
        body['forward_from_display_name'] = forwardFromDisplayName;
      }
    }
    final r = await http.post(
      Uri.parse('$base/groups/$groupId/messages'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<Message> sendGroupMessageWithFile(
    int groupId,
    String content,
    List<int> fileBytes,
    String filename, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/groups/$groupId/messages'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['content'] = content;
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  /// Отправка нескольких файлов в группу (альбом). Возвращает список сообщений.
  Future<List<Message>> sendGroupMessageWithMultipleFiles(
    int groupId,
    String content,
    List<({List<int> bytes, String filename})> files, {
    bool attachmentEncrypted = false,
  }) async {
    if (files.isEmpty) {
      return [];
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/groups/$groupId/messages'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['content'] = content;
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    for (final f in files) {
      request.files.add(
        http.MultipartFile.fromBytes('file', f.bytes, filename: f.filename),
      );
    }
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r));
    if (data is Map<String, dynamic> && data['messages'] != null) {
      final list = data['messages'] as List<dynamic>;
      return list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [Message.fromJson(data as Map<String, dynamic>)];
  }

  Future<Message> sendGroupVoiceMessage(
    int groupId,
    List<int> fileBytes,
    String filename,
    int durationSec, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/groups/$groupId/messages'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['content'] = '';
    request.fields['attachment_kind'] = 'voice';
    request.fields['attachment_duration_sec'] = durationSec.toString();
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<Message> sendGroupVideoNoteMessage(
    int groupId,
    List<int> fileBytes,
    String filename,
    int durationSec, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/groups/$groupId/messages'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['content'] = '';
    request.fields['attachment_kind'] = 'video_note';
    request.fields['attachment_duration_sec'] = durationSec.toString();
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<Message> sendGroupPoll(
    int groupId,
    String question,
    List<String> options, {
    bool multiple = false,
  }) async {
    final r = await http.post(
      Uri.parse('$base/groups/$groupId/messages'),
      headers: _headers,
      body: jsonEncode({
        'content': question,
        'type': 'poll',
        'question': question,
        'options': options,
        'multiple': multiple,
      }),
    );
    _checkResponse(r);
    return Message.fromJson(jsonDecode(_utf8Body(r)) as Map<String, dynamic>);
  }

  Future<PollResult> voteGroupPoll(
    int groupId,
    int pollId,
    int optionIndex,
  ) async {
    final r = await http.post(
      Uri.parse('$base/groups/$groupId/polls/$pollId/vote'),
      headers: _headers,
      body: jsonEncode({'option_index': optionIndex}),
    );
    _checkResponse(r);
    final data = jsonDecode(_utf8Body(r)) as Map<String, dynamic>;
    final opts = (data['options'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return PollResult(
      options: opts
          .map(
            (o) => PollOptionResult(
              text: o['text'] as String,
              votes: o['votes'] as int,
              voted: o['voted'] as bool? ?? false,
            ),
          )
          .toList(),
    );
  }
}

class PollResult {
  final List<PollOptionResult> options;
  PollResult({required this.options});
}

class PollOptionResult {
  final String text;
  final int votes;
  final bool voted;
  PollOptionResult({
    required this.text,
    required this.votes,
    required this.voted,
  });
}

class AuthResponse {
  final User user;
  final String token;
  AuthResponse({required this.user, required this.token});
}

class OAuthProviders {
  final bool google;
  final bool vk;
  final bool telegram;
  final bool phone;
  OAuthProviders({
    required this.google,
    required this.vk,
    required this.telegram,
    required this.phone,
  });
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}
