
import 'package:flutter_webrtc_demo/src/call_sample/signaling.dart';

class User {
  String? userId;
  String? userName;
  bool? video;
  bool? audio;

  Session? session;

  String get id => userId ?? '';

  User.fromJson(dynamic json) {
    if (json['userId'] != null) userId = json['userId'];
    if (json['from'] != null) userId = json['from'];
    final info = json['info'];

    userName = info['userName'];
    video = info['video'];
    audio = info['audio'];
  }

  static List<User> fromList(dynamic json) {
    final list = json as List<dynamic>;
    return list.map((e) => User.fromJson(e)).toList();
  }
}