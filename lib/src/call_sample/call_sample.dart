import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc_demo/src/call_sample/signaling_socketio.dart';
import 'package:flutter_webrtc_demo/src/models/user.dart';
import 'dart:core';
import 'signaling.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallSample extends StatefulWidget {
  final String channelName;
  final String userName;

  CallSample(this.channelName, this.userName);

  @override
  _CallSampleState createState() => _CallSampleState();
}

class _CallSampleState extends State<CallSample> {
  SignalingSocketIO? _signaling;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  Map<User, RTCVideoRenderer> _remoteRenderers = {};

  bool onMic = true;
  bool onCam = true;

  bool _disposed = false;

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _localRenderer.initialize();
  }

  @override
  void dispose() {
    _disposed = true;
    _dispose();
    super.dispose();
  }

  _dispose() async {
    print('==> dispose');
    await _signaling?.close();
    await _localRenderer.dispose();
    _remoteRenderers.values.toList().forEach((element) async {
      await element.dispose();
    });
  }

  void _connect() async {
    _signaling ??= SignalingSocketIO(widget.channelName, widget.userName)
      ..connect();
    _signaling?.onSignalingStateChange = (SignalingState state) {
      switch (state) {
        case SignalingState.ConnectionClosed:
        case SignalingState.ConnectionError:
        case SignalingState.ConnectionOpen:
          break;
      }
    };

    _signaling?.onCallStateChange = (Session? session, CallState state) {
      switch (state) {
        case CallState.CallStateNew:
          break;
        case CallState.CallStateBye:
          setState(() {
            _localRenderer.srcObject = null;
          });
          Navigator.of(context).pop();
          break;
        case CallState.CallStateInvite:
        case CallState.CallStateConnected:
        case CallState.CallStateRinging:
      }
    };

    _signaling?.onLocalStream = ((stream) {
      setState(() {
        _localRenderer.srcObject = stream;
      });
    });

    _signaling?.onCallingUser = ((user) async {
      final _renderer = RTCVideoRenderer();
      await _renderer.initialize();
      _remoteRenderers[user] = _renderer;
    });

    _signaling?.onUserLeft = ((user) async {
      setState(() {
        final renderer = _remoteRenderers.remove(user);
        renderer?.dispose();
      });
    });

    _signaling?.onAddRemoteStream = ((user, stream) {
      setState(() {
        _remoteRenderers[user]?.srcObject = stream;
      });
    });

    _signaling?.onRemoveRemoteStream = ((user, stream) {
      setState(() {
        _remoteRenderers[user]?.srcObject = null;
      });
    });
  }

  _hangUp() {
    _signaling?.bye();
  }

  _switchCamera() {
    _signaling?.switchCamera();
  }

  _changeMic() {
    setState(() {
      onMic = !onMic;
    });
    _signaling?.changeMicStatus(onMic);
  }

  _changeCam() {
    setState(() {
      onCam = !onCam;
    });
    _signaling?.changeCamStatus(onCam);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
          width: 200.0,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                FloatingActionButton(
                  heroTag: Key('cam'),
                  child: Icon(onCam ? Icons.videocam : Icons.videocam_off),
                  onPressed: _changeCam,
                ),
                FloatingActionButton(
                  heroTag: Key('end'),
                  onPressed: _hangUp,
                  tooltip: 'Hangup',
                  child: Icon(Icons.call_end),
                  backgroundColor: Colors.pink,
                ),
                FloatingActionButton(
                  heroTag: Key('mic'),
                  child: Icon(onMic ? Icons.mic : Icons.mic_off),
                  onPressed: _changeMic,
                )
              ])),
      body: Container(
        padding: EdgeInsets.only(bottom: 80, top: 20),
        child: _contentView(),
      ),
    );
  }

  Widget _contentView() {
    if (_disposed) return SizedBox();
    switch (_remoteRenderers.values.length) {
      case 1:
        return _twoUsersView();
      case 2:
        return _threeUsersView();
      case 3:
        return _fourUsersView();
      case 4:
        return _fiveUsersView();
      default:
        return _onlyMeView();
    }
  }

  Widget _onlyMeView() {
    return Column(
      children: [
        Expanded(child: RTCVideoView(_localRenderer)),
      ],
    );
  }

  Widget _twoUsersView() {
    return Column(
      children: [
        Expanded(child: RTCVideoView(_localRenderer)),
        Expanded(child: _videoView(_remoteRenderers.keys.first))
      ],
    );
  }

  Widget _threeUsersView() {
    final users = _remoteRenderers.keys.toList();
    return Column(
      children: [
        Expanded(child: RTCVideoView(_localRenderer)),
        Expanded(child: _videoView(users.first)),
        Expanded(child: _videoView(users[1]))
      ],
    );
  }

  Widget _fourUsersView() {
    final users = _remoteRenderers.keys.toList();
    return Column(
      children: [
        Expanded(
            child: Row(
          children: [
            Expanded(child: RTCVideoView(_localRenderer)),
            Expanded(child: _videoView(users.first)),
          ],
        )),
        Expanded(
            child: Row(
          children: [
            Expanded(child: _videoView(users[1])),
            Expanded(child: _videoView(users[2]))
          ],
        )),
      ],
    );
  }

  Widget _fiveUsersView() {
    final users = _remoteRenderers.keys.toList();
    return Column(
      children: [
        Expanded(
            child: Row(
          children: [
            Expanded(child: RTCVideoView(_localRenderer)),
            Expanded(child: _videoView(users.first)),
          ],
        )),
        Expanded(
            child: Row(
          children: [
            Expanded(child: _videoView(users[1])),
            Expanded(child: _videoView(users[2])),
            Expanded(child: _videoView(users[3]))
          ],
        )),
      ],
    );
  }

  Widget _videoView(User user) {
    if (!user.active) return SizedBox();
    final renderer = _remoteRenderers[user];
    if (renderer == null) return SizedBox();
    return Stack(
      children: [
        RTCVideoView(renderer),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text(user.userName ?? '', style: TextStyle(fontSize: 20),),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(3))
                  ),
                  child: StreamBuilder(
                    stream: user.audioStream,
                    builder: (context, snapshot) {
                      var data = user.audio;
                      if (snapshot.hasData) data = snapshot.data as bool;
                      if (data) {
                        return Icon(Icons.mic, color: Colors.green,);
                      } else {
                        return Icon(Icons.mic_off, color: Colors.red,);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 8,
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(3))
                  ),
                  child: StreamBuilder(
                    stream: user.videoStream,
                    builder: (context, snapshot) {
                      var data = user.video;
                      if (snapshot.hasData) data = snapshot.data as bool;
                      if (data) {
                        return Icon(Icons.videocam, color: Colors.green,);
                      } else {
                        return Icon(Icons.videocam_off, color: Colors.red,);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }
}
