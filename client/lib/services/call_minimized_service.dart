import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/group.dart';

/// Состояние свернутого звонка
class MinimizedCallState {
  final bool isMinimized;
  final User? peer; // Для индивидуального звонка
  final Group? group; // Для группового звонка
  final bool isVideoCall;
  final bool isGroupCall;

  MinimizedCallState({
    this.isMinimized = false,
    this.peer,
    this.group,
    this.isVideoCall = true,
    this.isGroupCall = false,
  });

  MinimizedCallState copyWith({
    bool? isMinimized,
    User? peer,
    Group? group,
    bool? isVideoCall,
    bool? isGroupCall,
  }) {
    return MinimizedCallState(
      isMinimized: isMinimized ?? this.isMinimized,
      peer: peer ?? this.peer,
      group: group ?? this.group,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      isGroupCall: isGroupCall ?? this.isGroupCall,
    );
  }
}

/// Сервис для управления свернутым состоянием звонка
class CallMinimizedService extends ChangeNotifier {
  MinimizedCallState _state = MinimizedCallState();

  MinimizedCallState get state => _state;
  bool get isMinimized => _state.isMinimized;
  User? get peer => _state.peer;
  Group? get group => _state.group;
  bool get isVideoCall => _state.isVideoCall;
  bool get isGroupCall => _state.isGroupCall;

  /// Свернуть индивидуальный звонок
  void minimizeCall(User peer, bool isVideoCall) {
    _state = MinimizedCallState(
      isMinimized: true,
      peer: peer,
      isVideoCall: isVideoCall,
      isGroupCall: false,
    );
    notifyListeners();
  }

  /// Свернуть групповой звонок
  void minimizeGroupCall(Group group, bool isVideoCall) {
    _state = MinimizedCallState(
      isMinimized: true,
      group: group,
      isVideoCall: isVideoCall,
      isGroupCall: true,
    );
    notifyListeners();
  }

  /// Развернуть звонок
  void expandCall() {
    _state = MinimizedCallState(isMinimized: false);
    notifyListeners();
  }

  /// Завершить звонок (очистить состояние)
  void endCall() {
    _state = MinimizedCallState(isMinimized: false);
    notifyListeners();
  }
}
