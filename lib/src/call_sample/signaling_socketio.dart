import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc_demo/src/models/user.dart';
import 'package:flutter_webrtc_demo/src/utils/turn.dart';
import 'package:socket_io_client/socket_io_client.dart';

import 'signaling.dart';
import 'package:collection/collection.dart';

class SignalingSocketIO {
  final String channelName;
  final String userName;

  SignalingSocketIO(this.channelName, this.userName);

  Socket? _socket;
  Map<String, Session> _sessions = {};
  MediaStream? _localStream;
  List<MediaStream> _remoteStreams = <MediaStream>[];

  List<User> callingUsers = [];

  User? get me =>
      callingUsers.firstWhereOrNull((element) => element.userName == userName);

  Function(SignalingState state)? onSignalingStateChange;
  Function(Session? session, CallState state)? onCallStateChange;
  Function(User user)? onCallingUser;
  Function(User user)? onUserLeft;
  Function(String me)? onMe;
  Function(dynamic data)? onReceivedCall;
  Function(MediaStream stream)? onLocalStream;
  Function(User user, MediaStream stream)? onAddRemoteStream;
  Function(User user, MediaStream stream)? onRemoveRemoteStream;
  Function(dynamic event)? onPeersUpdate;
  Function(Session session, RTCDataChannel dc, RTCDataChannelMessage data)?
      onDataChannelMessage;
  Function(Session session, RTCDataChannel dc)? onDataChannel;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };

  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  close() async {
    await _cleanSessions();
    _socket?.disconnect();
    _socket?.close();
  }

  Future<void> connect() async {
    var url = 'https://test-socket-21.herokuapp.com/';
    _socket = io(
        url,
        OptionBuilder()
            .setTransports(['websocket']) // for Flutter or Dart VM
            .disableAutoConnect() // disable auto-connection
            .build());
    _socket?.connect();

    print('connect to $url');

    _socket?.onConnect((_) async {
      print('connect');
      onSignalingStateChange?.call(SignalingState.ConnectionOpen);
      _localStream = await createStream('video');
      joinRoom();
      getListUsers();
    });

    _socket?.onDisconnect((_) {
      onSignalingStateChange?.call(SignalingState.ConnectionClosed);
    });

    _observer('receive-call', (p0) async {
      final signal = p0['signal'];
      final from = p0['from'];
      final user = User.fromJson(p0);
      user.userId = from;

      onCallingUser?.call(user);

      var newSession = await _createSession(user,
          peerId: from, sessionId: from, media: 'video', screenSharing: false);
      user.session = newSession;
      await newSession.pc?.setRemoteDescription(
          RTCSessionDescription(signal['sdp'], signal['type']));
      await _createAnswer(user);
      callingUsers.add(user);
    });

    _observer('receive-accepted', (p0) {
      var signal = p0['signal'];
      var sessionId = p0['answerId'];
      Session? session = callingUsers
          .firstWhereOrNull((element) => element.userId == sessionId)
          ?.session;
      print('pc: ${session?.pc}');
      session?.pc?.setRemoteDescription(
          RTCSessionDescription(signal['sdp'], signal['type']));

      onCallStateChange?.call(session!, CallState.CallStateNew);
    });

    _observer('receive-user-leave', (p0) async {
      final userId = p0['userId'];

      final user =
          callingUsers.firstWhereOrNull((element) => element.userId == userId);
      if (user == null) return;
      user.dispose();
      onUserLeft?.call(user);
      if (user.session != null) {
        _closeSession(user.session!);
      }
      callingUsers.remove(user);
      _localStream = await createStream('video');
    });

    _observer('receive-toggle-camera-audio', (p0) {
      final userId = p0['userId'];
      final switchTarget = p0['switchTarget'];
      final user =
          callingUsers.firstWhereOrNull((element) => element.userId == userId);
      if (user == null) return;
      if (switchTarget == 'video') {
        user.changeVideoState(!user.video);
      } else {
        user.changeAudioState(!user.audio);
      }
    });
  }

  void joinRoom() {
    _send('join-room', {'roomId': channelName, 'userName': userName});
  }

  void getListUsers() {
    _observer('list-user-join', (p0) {
      final users = User.fromList(p0);
      if (users.isEmpty) return;

      final me =
          users.firstWhereOrNull((element) => element.userName == userName);
      if (me != null &&
          callingUsers.firstWhereOrNull(
                  (element) => element.userName == userName) ==
              null) {
        callingUsers.add(me);
      }

      users.forEach((user) {
        // Skip existed user
        if (callingUsers.firstWhereOrNull(
                (element) => element.userName == user.userName) !=
            null) return;

        _createUserSession(user);
        callingUsers.add(user);
      });
    });
  }

  void _toggleMedia(bool video) {
    _send('call-toggle-camera-audio',
        {'roomId': channelName, 'switchTarget': video ? 'video' : 'audio'});
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void changeMicStatus(bool status) {
    if (_localStream != null) {
      _localStream!.getAudioTracks()[0].enabled = status;
      _toggleMedia(false);
    }
  }

  void changeCamStatus(bool status) {
    if (_localStream != null) {
      _localStream!.getVideoTracks()[0].enabled = status;
      _toggleMedia(true);
    }
  }

  void _createUserSession(User user) async {
    final session = await _createSession(user,
        peerId: user.id,
        sessionId: user.id,
        media: 'video',
        screenSharing: false);
    user.session = session;
    onCallingUser?.call(user);
    _createOffer(session);
  }

  void bye() async {
    _send('call-user-leave', {'roomId': channelName, 'leaver': me?.userId});
    onCallStateChange?.call(null, CallState.CallStateBye);
    callingUsers.forEach((value) {
      value.dispose();
      if (value.session != null) {
        _closeSession(value.session!);
      }
    });
    callingUsers.clear();
  }

  //https://github.com/flutter-webrtc/flutter-webrtc/issues/653
  Future<MediaStream> createStream(String media) async {
    final userScreen = false;
    final Map<String, dynamic> mediaConstraints = {
      'audio': userScreen ? false : true,
      'video': userScreen
          ? true
          : {
              'mandatory': {
                'minWidth':
                    '640', // Provide your own width, height and frame rate here
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
    };

    MediaStream stream = userScreen
        ? await navigator.mediaDevices.getDisplayMedia(mediaConstraints)
        : await navigator.mediaDevices.getUserMedia(mediaConstraints);
    onLocalStream?.call(stream);
    return stream;
  }

  Future<Session> _createSession(User user,
      {required String peerId,
      required String sessionId,
      required String media,
      required bool screenSharing}) async {
    var newSession = user.session ?? Session(sid: sessionId, pid: peerId);
    _localStream = await createStream('video');
    print(_iceServers);
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'sdpSemantics': 'unified-plan'}
    }, _config);

    pc.onTrack = (event) {
      if (event.track.kind == 'video') {
        print('onTrackVideo: ${event.streams[0]}');
        onAddRemoteStream?.call(user, event.streams[0]);
      } else if (event.track.kind == 'audio') {
        print('onTrackAudio: ${event.streams[0]}');
      }
    };
    _localStream!.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onIceCandidate = (candidate) async {
      if (candidate == null) {
        print('onIceCandidate: complete!');
        return;
      }
      print('ICE candidate: ${candidate.candidate}');
    };

    pc.onIceConnectionState = (state) {};

    pc.onRemoveStream = (stream) {
      onRemoveRemoteStream?.call(user, stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    pc.onDataChannel = (channel) {
      _addDataChannel(newSession, channel);
    };

    newSession.pc = pc;
    return newSession;
  }

  void _addDataChannel(Session session, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      onDataChannelMessage?.call(session, channel, data);
    };
    session.dc = channel;
    onDataChannel?.call(session, channel);
  }

  Future<void> _createOffer(Session session) async {
    try {
      RTCSessionDescription s = await session.pc!.createOffer({});
      await session.pc!.setLocalDescription(s);
      _send('call-user', {
        'userToCall': session.pid,
        'from': me?.userId,
        'signal': {'sdp': s.sdp, 'type': s.type},
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _createAnswer(User user) async {
    try {
      RTCSessionDescription s = await user.session!.pc!.createAnswer({});
      await user.session!.pc!.setLocalDescription(s);

      _send('accepted-call', {
        'signal': {'sdp': s.sdp, 'type': s.type},
        'to': user.userId
      });
    } catch (e) {
      print(e.toString());
    }
  }

  dynamic _getDataWrapper(dynamic data) {
    if (data is Map && data['signal'] != null) {
      var dataWrapped = Map.from(data);
      if (dataWrapped['signal'] != null) {
        dataWrapped['signal'] = dataWrapped['signal']['type'];
      }

      return dataWrapped;
    } else {
      return data;
    }
  }

  _send(event, data) {
    print('=======send======>>>');
    print('event: $event');
    print('data: ${_getDataWrapper(data).toString()}');
    _socket?.emit(event, data);
  }

  _observer(String event, Function(dynamic) handler) {
    _socket?.on(event, (data) {
      print('<<<======received=======');
      print('$event: ${_getDataWrapper(data).toString()}');
      handler(data);
    });
  }

  Future<void> _cleanSessions() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
      _localStream = null;
    }
    _sessions.forEach((key, sess) async {
      await sess.pc?.close();
      await sess.dc?.close();
    });
    _sessions.clear();
  }

  void _closeSessionByPeerId(String peerId) {
    var session;
    _sessions.removeWhere((String key, Session sess) {
      var ids = key.split('-');
      session = sess;
      return peerId == ids[0] || peerId == ids[1];
    });
    if (session != null) {
      _closeSession(session);
      onCallStateChange?.call(session, CallState.CallStateBye);
    }
  }

  Future<void> _closeSession(Session session) async {
    _localStream?.getTracks().forEach((element) async {
      await element.stop();
    });
    await _localStream?.dispose();
    _localStream = null;

    await session.pc?.close();
    await session.dc?.close();
  }
}
