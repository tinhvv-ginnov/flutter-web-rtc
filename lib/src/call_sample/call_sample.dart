import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc_demo/src/call_sample/signaling_socketio.dart';
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
  String? meId;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  Session? _session;

  bool onMic = true;
  bool onCam = true;

  // ignore: unused_element
  _CallSampleState();

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _signaling?.close();
    super.dispose();
  }

  @override
  deactivate() {
    super.deactivate();
    _signaling?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  void _connect() async {
    _signaling ??= SignalingSocketIO(widget.channelName, widget.userName)..connect();
    _signaling?.onSignalingStateChange = (SignalingState state) {
      switch (state) {
        case SignalingState.ConnectionClosed:
        case SignalingState.ConnectionError:
        case SignalingState.ConnectionOpen:
          break;
      }
    };

    _signaling?.onCallStateChange = (Session session, CallState state) {
      switch (state) {
        case CallState.CallStateNew:
          setState(() {
            _session = session;
          });
          break;
        case CallState.CallStateBye:
          setState(() {
            _localRenderer.srcObject = null;
            _remoteRenderer.srcObject = null;
            _session = null;
          });
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

    _signaling?.onAddRemoteStream = ((_, stream) {
      setState(() {
        print('remote stream: $stream');
        _remoteRenderer.srcObject = stream;
      });
    });

    _signaling?.onRemoveRemoteStream = ((_, stream) {
      setState(() {
        _remoteRenderer.srcObject = null;
      });
    });

    _signaling?.onMe = ((me) {
      setState(() {
        meId = me;
      });
    });

    _signaling?.onReceivedCall = ((data) {
      _showMyDialog(data);
    });
  }

  Future<void> _showMyDialog(dynamic data) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Calling...'),
          content: Text('You receiving a call from ${data['name']}'),
          actions: <Widget>[
            ElevatedButton(
              style: ElevatedButton.styleFrom(primary: Colors.red),
              child: const Text('Reject'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: ElevatedButton.styleFrom(primary: Colors.blue),
              child: const Text(
                'Accept',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _signaling?.acceptCall(data);
              },
            ),
          ],
        );
      },
    );
  }

  _hangUp() {
    if (_session != null) {
      _signaling?.bye(_session!.sid);
    }
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
                      key: Key('cam'),
                      child: Icon(onCam ? Icons.videocam : Icons.videocam_off),
                      onPressed: _changeCam,
                    ),
                    FloatingActionButton(
                      key: Key('end'),
                      onPressed: _hangUp,
                      tooltip: 'Hangup',
                      child: Icon(Icons.call_end),
                      backgroundColor: Colors.pink,
                    ),
                    FloatingActionButton(
                      key: Key('mic'),
                      child: Icon(onMic ? Icons.mic : Icons.mic_off),
                      onPressed: _changeMic,
                    )
                  ])),
      body: Container(
        child: Stack(children: <Widget>[
          Positioned(
              left: 0.0,
              right: 0.0,
              top: 0.0,
              bottom: 0.0,
              child: Container(
                margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: RTCVideoView(_remoteRenderer),
                decoration: BoxDecoration(color: Colors.black54),
              )),
          Positioned(
            left: 20.0,
            top: 20.0,
            child: Container(
              width: 90.0,
              height: 120.0,
              child: RTCVideoView(_localRenderer, mirror: true),
              decoration: BoxDecoration(color: Colors.black54),
            ),
          ),
        ]),
      ),
    );
  }
}
