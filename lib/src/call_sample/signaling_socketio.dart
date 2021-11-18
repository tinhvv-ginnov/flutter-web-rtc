import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart';

import 'signaling.dart';

class SignalingSocketIO {
  SignalingSocketIO();

  Socket? _socket;
  Map<String, Session> _sessions = {};
  MediaStream? _localStream;
  List<MediaStream> _remoteStreams = <MediaStream>[];

  String me = '';

  Function(SignalingState state)? onSignalingStateChange;
  Function(Session session, CallState state)? onCallStateChange;
  Function(String me)? onMe;
  Function(dynamic data)? onReceivedCall;
  Function(MediaStream stream)? onLocalStream;
  Function(Session session, MediaStream stream)? onAddRemoteStream;
  Function(Session session, MediaStream stream)? onRemoveRemoteStream;
  Function(dynamic event)? onPeersUpdate;
  Function(Session session, RTCDataChannel dc, RTCDataChannelMessage data)?
      onDataChannelMessage;
  Function(Session session, RTCDataChannel dc)? onDataChannel;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
      /*
       * turn server configuration example.
      {
        'url': 'turn:123.45.67.89:3478',
        'username': 'change_to_real_user',
        'credential': 'change_to_real_secret'
      },
      */
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

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void changeMicStatus(bool status) {
    if (_localStream != null) {
      _localStream!.getAudioTracks()[0].enabled = status;
    }
  }

  void changeCamStatus(bool status) {
    if (_localStream != null) {
      _localStream!.getVideoTracks()[0].enabled = status;
    }
  }

  void acceptCall(dynamic data) async {
    var peerId = data['from'];
    var description = data['signal'];
    var sessionId = data['from'];
    var session = _sessions[sessionId];
    var newSession = await _createSession(session,
        peerId: peerId,
        sessionId: sessionId,
        media: 'video',
        screenSharing: false);
    _sessions[sessionId] = newSession;
    await newSession.pc?.setRemoteDescription(
        RTCSessionDescription(description['sdp'], description['type']));
    await _createAnswer(newSession, '1234');
    if (newSession.remoteCandidates.length > 0) {
      newSession.remoteCandidates.forEach((candidate) async {
        await newSession.pc?.addCandidate(candidate);
      });
      newSession.remoteCandidates.clear();
    }
    onCallStateChange?.call(newSession, CallState.CallStateNew);
  }

  void invite(String peerId, String name, String media, bool useScreen) async {
    Session session = await _createSession(null,
        peerId: peerId,
        sessionId: peerId,
        media: media,
        screenSharing: useScreen);
    _sessions[peerId] = session;
    _createOffer(session, name);
  }

  void bye(String sessionId) async {
    _send('endCall', {'id': sessionId});
    onCallStateChange?.call(
        _sessions.values.toList().first, CallState.CallStateBye);
    _sessions.forEach((key, value) {
      _closeSession(value);
    });
    _sessions.clear();
    _localStream = await createStream('video');
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
    });

    _socket?.onDisconnect((_) {
      onSignalingStateChange?.call(SignalingState.ConnectionClosed);
    });

    _socket?.on('me', (data) {
      print('me: ${data.toString()}');
      me = data;
      onMe?.call(data);
    });

    _socket?.on('endCall', (data) async {
      onCallStateChange?.call(
          _sessions.values.toList().first, CallState.CallStateBye);
      _sessions.forEach((key, value) {
        _closeSession(value);
      });
      _sessions.clear();
      _localStream = await createStream('video');
    });

    _socket?.on('callUser', (data) {
      print('callUser: ${data['from']}');
      final signal = data['signal'];
      final type = signal['type'];

      if (type == 'offer') {
        onReceivedCall?.call(data);
      }
    });

    _socket?.on('callAccepted', (data) {
      print('callAccepted: ${_getDataWrapper(data).toString()}');
      var signal = data['signal'];
      var sessionId = data['sessionId'];
      var session = _sessions[sessionId];
      print('pc: ${session?.pc}');
      session?.pc?.setRemoteDescription(
          RTCSessionDescription(signal['sdp'], signal['type']));

      onCallStateChange?.call(session!, CallState.CallStateNew);

      _send("updateMyMedia", {
        'type': "both",
        'currentMediaStatus': [true, true],
      });
    });

    _socket?.on("updateUserMedia", (data) {
      final currentMediaStatus = data['currentMediaStatus'];
      final type = data['type'];
      print("updateUserMedia $data");
      if (currentMediaStatus != null || currentMediaStatus != []) {
        switch (type) {
          case "video":
            break;
          case "mic":
            break;
          default:
            break;
        }
      }
    });
  }

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

  Future<Session> _createSession(Session? session,
      {required String peerId,
      required String sessionId,
      required String media,
      required bool screenSharing}) async {
    var newSession = session ?? Session(sid: sessionId, pid: peerId);
    _localStream = await createStream('video');
    print(_iceServers);
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'sdpSemantics': 'unified-plan'}
    }, _config);

    pc.onTrack = (event) {
      if (event.track.kind == 'video') {
        print('onTrackVideo: ${event.streams[0]}');
        onAddRemoteStream?.call(newSession, event.streams[0]);
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
    };

    pc.onIceConnectionState = (state) {};

    pc.onRemoveStream = (stream) {
      onRemoveRemoteStream?.call(newSession, stream);
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

  Future<void> _createOffer(Session session, String name) async {
    try {
      RTCSessionDescription s = await session.pc!.createOffer({});
      await session.pc!.setLocalDescription(s);
      _send('callUser', {
        'userToCall': session.pid,
        'from': me,
        'signalData': {'sdp': s.sdp, 'type': s.type},
        'name': name,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _createAnswer(Session session, String name) async {
    try {
      RTCSessionDescription s = await session.pc!.createAnswer({});
      await session.pc!.setLocalDescription(s);

      _send("answerCall", {
        'signal': {'sdp': s.sdp, 'type': s.type},
        'to': session.pid,
        'userName': name,
        'sessionId': session.pid,
        'type': "both",
        'myMediaStatus': [true, true],
      });
    } catch (e) {
      print(e.toString());
    }
  }

  dynamic _getDataWrapper(dynamic data) {
    if (data['signal'] != null || data['signalData'] != null) {
      var dataWrapped = Map.from(data);
      if (dataWrapped['signal'] != null) {
        dataWrapped['signal'] = dataWrapped['signal']['type'];
      }

      if (dataWrapped['signalData'] != null) {
        dataWrapped['signalData'] = dataWrapped['signalData']['type'];
      }

      return dataWrapped;
    } else {
      return data;
    }
  }

  _send(event, data) {
    print('=============>>>');
    print('event: $event');
    print('data: ${_getDataWrapper(data).toString()}');
    print('<<<=============');
    _socket?.emit(event, data);
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
