import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../widgets/random_string.dart';

import '../widgets/websocket.dart'
    if (dart.library.js) '../widgets/websocket_web.dart';

enum SignalingState {
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

enum CallState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
}

class Connection {
  Connection({required this.cid, required this.rid});
  // connectionId
  String cid;
  // roomId
  String rid;
  RTCPeerConnection? pc;
  // RTCDataChannel? dc;
  List<RTCIceCandidate> remoteCandidates = [];
}

class Signaling {
  Signaling(this._host, this._streamer, this._localStream, this.number);

  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  String _selfId = randomNumeric(6);
  SimpleWebSocket? _socket;
  String _host;
  bool _streamer;
  int number;
  // static int _port = 3000;
  Map<String, Connection> _connections = {};
  MediaStream? _localStream;
  List<MediaStream> _remoteStreams = <MediaStream>[];

  Function(SignalingState state)? onSignalingStateChange;
  Function(Connection connection, CallState state, [MediaStream? stream])?
      onCallStateChange;
  Function(MediaStream stream)? onLocalStream;
  Function(Connection connection, MediaStream stream)? onAddRemoteStream;
  Function(Connection connection, MediaStream stream)? onRemoveRemoteStream;
  Function(dynamic event)? onPeersUpdate;

  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {
        'url': 'stun:stun.l.google.com:19302',
      }
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

  Future<void> _cleanConnections() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
      _localStream = null;
    }
    _connections.forEach((key, conn) async {
      await conn.pc?.close();
    });
    _connections.clear();
  }

  close() async {
    await _cleanConnections();
    _socket?.close();
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void muteMic() {
    if (_localStream != null) {
      bool enabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !enabled;
    }
  }

  Future<MediaStream> createStream(String media, bool userScreen) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': userScreen ? false : true,
      'video': userScreen
          ? true
          : {
              'mandatory': {
                'minWidth': '640',
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
    if (_streamer) onLocalStream?.call(stream);
    return stream;
  }

  _sendVer2(data) {
    _socket?.send(_encoder.convert(data));
  }

  Future<Connection> _createConnection(Connection? connection,
      {required String connectionId,
      required String media,
      required bool screenSharing}) async {
    var newConnection = connection ?? Connection(cid: connectionId, rid: _host);
    if (media != 'data' && _streamer)
      _localStream = _localStream ?? await createStream(media, screenSharing);
    print(_iceServers);
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'sdpSemantics': sdpSemantics}
    }, _config);
    if (media != 'data') {
      switch (sdpSemantics) {
        case 'plan-b':
          pc.onAddStream = (MediaStream stream) {
            onAddRemoteStream?.call(newConnection, stream);
            _remoteStreams.add(stream);
          };
          if (_streamer) {
            await pc.addStream(_localStream!);
          }
          break;
        case 'unified-plan':
          print('unified!');
          pc.onTrack = (event) {
            if (event.track.kind == 'video') {
              onAddRemoteStream?.call(newConnection, event.streams[0]);
              print('added remote video');
            }
          };
          if (_streamer) {
            _localStream!.getTracks().forEach((track) {
              pc.addTrack(track, _localStream!);
            });
          } else {
            var peerInit =
                RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly);
            pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: peerInit);
            pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeAudio, init: peerInit);
          }
          print('aaaaa');
          break;
      }
    }
    pc.onIceCandidate = (candidate) async {
      await Future.delayed(
          const Duration(seconds: 1),
          () => _sendVer2({
                'type': 'candidate',
                'from': _selfId,
                'candidate': {
                  'sdpMLineIndex': candidate.sdpMlineIndex,
                  'sdpMid': candidate.sdpMid,
                  'candidate': candidate.candidate,
                },
                'connection_id': connectionId,
              }));
    };

    pc.onIceConnectionState = (state) {};

    pc.onRemoveStream = (stream) {
      onRemoveRemoteStream?.call(newConnection, stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };
    newConnection.pc = pc;
    return newConnection;
  }

  Future<void> _createOffer(Connection connection, String media) async {
    try {
      RTCSessionDescription s = await connection.pc!.createOffer(_streamer
          ? {}
          : {
              'mandatory': {
                'OfferToReceiveAudio': true,
                'OfferToReceiveVideo': true,
              },
              'optional': [],
            });
      // RTCSessionDescription s = await connection.pc!
      //     .createOffer(media == 'data' ? _dcConstraints : {});
      await connection.pc!.setLocalDescription(s);
      _sendVer2({
        'type': 'offer',
        'description': {'sdp': s.sdp, 'type': s.type},
        'connection_id': connection.cid,
        'media': media,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  void invite(String media, bool useScreen) async {
    var connectionId = _selfId;
    Connection connection = await _createConnection(null,
        connectionId: connectionId, media: media, screenSharing: useScreen);
    _connections[connectionId] = connection;
    if (!_streamer) {
      _createOffer(connection, media);
    }
    onCallStateChange?.call(connection, CallState.CallStateNew);
  }

  Future<void> _closeConnection(Connection connection) async {
    _localStream?.getTracks().forEach((element) async {
      await element.stop();
    });
    await _localStream?.dispose();
    _localStream = null;

    await connection.pc?.close();
  }

  void bye(String connectionId) {
    // _send('bye', {
    //   'connection_id': connectionId,
    //   'from': _selfId,
    // });
    var conn = _connections[connectionId];
    if (conn != null) {
      _closeConnection(conn);
    }
  }

  Future<void> _createAnswer(Connection connection, String media) async {
    try {
      RTCSessionDescription s = await connection.pc!
          .createAnswer(media == 'data' ? _dcConstraints : {});
      await connection.pc!.setLocalDescription(s);
      _sendVer2({
        'type': 'answer',
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'connection_id': connection.cid,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  void _closeConnectionByPeerId(String peerId) {
    var connection;
    _connections.removeWhere((String key, Connection conn) {
      var ids = key.split('-');
      connection = conn;
      return peerId == ids[0] || peerId == ids[1];
    });
    if (connection != null) {
      _closeConnection(connection);
      onCallStateChange?.call(connection, CallState.CallStateBye);
    }
  }

  void onMessage(message) async {
    Map<String, dynamic> mapData = message;
    var data = mapData['data'];

    switch (mapData['type']) {
      case 'ping':
        {
          _sendVer2({
            'type': 'pong',
          });
        }
        break;
      case 'accept':
        {
          if (_streamer) {
            mapData['roomId'] = _host;
            List<dynamic> streamInfo = [];
            streamInfo.add(mapData);
            print(mapData);
            if (onPeersUpdate != null) {
              Map<String, dynamic> event = Map<String, dynamic>();
              event['self'] = _selfId;
              event['streamInfo'] = streamInfo;
              onPeersUpdate?.call(event);
            }
          } else {
            invite('video', false);
          }
        }
        break;
      case 'offer':
        {
          var description = mapData['description'];
          var media = mapData['media'];
          var connectionId = mapData['connection_id'];
          var connection = _connections[connectionId];
          var newConnection = await _createConnection(connection,
              connectionId: connectionId, media: media, screenSharing: false);
          _connections[connectionId] = newConnection;
          print('created new connection');
          await newConnection.pc?.setRemoteDescription(
              RTCSessionDescription(description['sdp'], description['type']));
          await _createAnswer(newConnection, media);
          if (newConnection.remoteCandidates.length > 0) {
            newConnection.remoteCandidates.forEach((candidate) async {
              await newConnection.pc?.addCandidate(candidate);
            });
            newConnection.remoteCandidates.clear();
          }
          onCallStateChange?.call(
              newConnection, CallState.CallStateNew, _localStream);
        }
        break;
      case 'answer':
        {
          var description = mapData['description'];
          var connectionId = mapData['connection_id'];
          var connection = _connections[connectionId];
          connection?.pc?.setRemoteDescription(
              RTCSessionDescription(description['sdp'], description['type']));
        }
        break;
      case 'candidate':
        {
          var candidateMap = mapData['candidate'];
          var connectionId = mapData['connection_id'];
          var connection = _connections[connectionId];
          RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
              candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);
          if (connection != null) {
            if (connection.pc != null) {
              await connection.pc?.addCandidate(candidate);
            } else {
              connection.remoteCandidates.add(candidate);
            }
          } else {
            _connections[connectionId] =
                Connection(cid: connectionId, rid: _host)
                  ..remoteCandidates.add(candidate);
          }
          await Future.delayed(
            const Duration(seconds: 2),
            () => print(connection!.pc!.connectionState),
          );
        }
        break;
      case 'leave':
        {
          var peerId = mapData as String;
          _closeConnectionByPeerId(peerId);
        }
        break;
      case 'bye':
        {
          var connectionId = data['connection_id'];
          print('bye: ' + connectionId);
          var connection = _connections.remove(connectionId);
          if (connection != null) {
            onCallStateChange?.call(connection, CallState.CallStateBye);
            _closeConnection(connection);
          }
        }
        break;
      case 'keepalive':
        {
          print('keepalive response!');
        }
        break;
      default:
        print('check well');
        break;
    }
  }

  Future<void> connect(bool streamer) async {
    var url = 'https://demia.tk/signaling';
    _socket = SimpleWebSocket(url);

    print('connect to $url');

    _socket?.onOpen = () {
      print('onOpen');
      onSignalingStateChange?.call(SignalingState.ConnectionOpen);
      _sendVer2({
        'type': streamer ? 'onair' : 'watch',
        'roomId': _host,
        'clientId': _selfId,
        'authnMetadata': null,
        'key': null,
      });
    };

    _socket?.onMessage = (message) {
      print('Received data: ' + message);
      onMessage(_decoder.convert(message));
    };

    _socket?.onClose = (int code, String reason) {
      print('Closed by server [$code => $reason]!');
      onSignalingStateChange?.call(SignalingState.ConnectionClosed);
    };

    await _socket?.connect();
  }
}
