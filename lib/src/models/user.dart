
import 'dart:async';

import 'package:flutter_webrtc_demo/src/call_sample/signaling.dart';

class User {
  String? userId;
  String? userName;
  bool video = true;
  bool audio = true;

  bool active = true;

  Session? session;

  String get id => userId ?? '';

  StreamController _audioStream = StreamController<bool>.broadcast();

  /// Audio stream
  Stream get audioStream => _audioStream.stream;

  StreamController _videoStream = StreamController<bool>.broadcast();

  /// Video stream
  Stream get videoStream => _videoStream.stream;

  /// Change audio state
  changeAudioState(bool state) {
    audio = state;
    _audioStream.sink.add(state);
  }

  /// Change video state
  changeVideoState(bool state) {
    video = state;
    _videoStream.sink.add(state);
  }

  User.fromJson(dynamic json) {
    if (json['userId'] != null) userId = json['userId'];
    if (json['from'] != null) userId = json['from'];
    final info = json['info'];

    userName = info['userName'];
    video = info['video'];
    audio = info['audio'];

    changeAudioState(audio);
    changeVideoState(video);
  }

  static List<User> fromList(dynamic json) {
    final list = json as List<dynamic>;
    return list.map((e) => User.fromJson(e)).toList();
  }

  /// Release resources
  dispose() {
    _audioStream.close();
    _videoStream.close();
    active = false;
  }
}