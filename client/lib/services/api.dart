import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../models/chat.dart';
import '../models/friend_request.dart';

class Api {
  final String token;
  final String base = apiBaseUrl;

  Api(this.token);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  void _checkResponse(http.Response r) {
    if (r.statusCode >= 400) {
      final body = r.body;
      String msg = body;
      try {
        final m = jsonDecode(body) as Map<String, dynamic>;
        msg = m['error'] as String? ?? body;
      } catch (_) {}
      throw ApiException(r.statusCode, msg);
    }
  }

  Future<User> register(String username, String password, [String? displayName, String? email]) async {
    final r = await http.post(
      Uri.parse('$base/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'password': password,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
      }),
    );
    _checkResponse(r);
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AuthResponse> login(String username, String password) async {
    final r = await http.post(
      Uri.parse('$base/auth/login'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    _checkResponse(r);
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return AuthResponse(
      user: User.fromJson(data['user'] as Map<String, dynamic>),
      token: data['token'] as String,
    );
  }

  Future<User> me() async {
    final r = await http.get(Uri.parse('$base/users/me'), headers: _headers);
    _checkResponse(r);
    return User.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<User> patchMe({String? displayName, String? username, String? bio, String? publicKey, String? email}) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    if (publicKey != null) body['public_key'] = publicKey;
    if (email != null) body['email'] = email;
    final r = await http.patch(
      Uri.parse('$base/users/me'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkResponse(r);
    return User.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<User> uploadAvatar(List<int> fileBytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/users/me/avatar'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'avatar',
      fileBytes,
      filename: filename,
    ));
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return User.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Публичный профиль пользователя (имя, био, аватар, количество друзей — без списка друзей).
  Future<User> getUserProfile(int userId) async {
    final r = await http.get(Uri.parse('$base/users/$userId'), headers: _headers);
    _checkResponse(r);
    return User.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<User>> searchUsers(String q) async {
    final r = await http.get(
      Uri.parse('$base/users/search').replace(queryParameters: {'q': q}),
      headers: _headers,
    );
    _checkResponse(r);
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<User>> getContacts() async {
    final r = await http.get(Uri.parse('$base/contacts'), headers: _headers);
    _checkResponse(r);
    final list = jsonDecode(r.body) as List<dynamic>;
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
    return User.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<FriendRequest>> getFriendRequestsIncoming() async {
    final r = await http.get(Uri.parse('$base/contacts/requests/incoming'), headers: _headers);
    _checkResponse(r);
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((e) => FriendRequest.fromJson(e as Map<String, dynamic>)).toList();
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

  Future<List<ChatPreview>> getChats() async {
    final r = await http.get(Uri.parse('$base/chats'), headers: _headers);
    _checkResponse(r);
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((e) => ChatPreview.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> markMessagesRead(int peerId) async {
    final r = await http.patch(
      Uri.parse('$base/messages/$peerId/read'),
      headers: _headers,
    );
    _checkResponse(r);
  }

  Future<List<Message>> getMessages(int peerId, {int? before, int limit = 100}) async {
    final params = <String, String>{'limit': limit.toString()};
    if (before != null) params['before'] = before.toString();
    final r = await http.get(
      Uri.parse('$base/messages/$peerId').replace(queryParameters: params),
      headers: _headers,
    );
    _checkResponse(r);
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
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
    if (replyToId != null) body['reply_to_id'] = replyToId;
    if (isForwarded) {
      body['is_forwarded'] = true;
      if (forwardFromSenderId != null) body['forward_from_sender_id'] = forwardFromSenderId;
      if (forwardFromDisplayName != null) body['forward_from_display_name'] = forwardFromDisplayName;
    }
    final r = await http.post(
      Uri.parse('$base/messages'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkResponse(r);
    return Message.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<Message> sendMessageWithFile(
    int receiverId,
    String content,
    List<int> fileBytes,
    String filename, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/messages'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = content;
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
    ));
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<Message> sendVoiceMessage(
    int receiverId,
    List<int> fileBytes,
    String filename,
    int durationSec, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/messages'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = '';
    request.fields['attachment_kind'] = 'voice';
    request.fields['attachment_duration_sec'] = durationSec.toString();
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
    ));
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<Message> sendVideoNoteMessage(
    int receiverId,
    List<int> fileBytes,
    String filename,
    int durationSec, {
    bool attachmentEncrypted = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/messages'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = '';
    request.fields['attachment_kind'] = 'video_note';
    request.fields['attachment_duration_sec'] = durationSec.toString();
    if (attachmentEncrypted) request.fields['attachment_encrypted'] = 'true';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
    ));
    final streamed = await request.send();
    final r = await http.Response.fromStream(streamed);
    _checkResponse(r);
    return Message.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
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

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final r = await http.post(
      Uri.parse('$base/auth/change-password'),
      headers: _headers,
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
    );
    _checkResponse(r);
  }

  static Future<List<int>> getAttachmentBytes(String url) async {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw ApiException(r.statusCode, 'Ошибка загрузки');
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
    return Message.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<PollResult> votePoll(int pollId, int optionIndex) async {
    final r = await http.post(
      Uri.parse('$base/polls/$pollId/vote'),
      headers: _headers,
      body: jsonEncode({'option_index': optionIndex}),
    );
    _checkResponse(r);
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final opts = (data['options'] as List<dynamic>).cast<Map<String, dynamic>>();
    return PollResult(
      options: opts.map((o) => PollOptionResult(
        text: o['text'] as String,
        votes: o['votes'] as int,
        voted: o['voted'] as bool? ?? false,
      )).toList(),
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
  PollOptionResult({required this.text, required this.votes, required this.voted});
}

class AuthResponse {
  final User user;
  final String token;
  AuthResponse({required this.user, required this.token});
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}
