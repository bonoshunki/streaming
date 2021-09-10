import 'package:flutter/material.dart';
import 'dart:core';
import '../models/connection.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class Stream extends StatefulWidget {
  static String tag = 'call_sample';
  final String host;
  final bool streamer;
  Stream({required this.host, required this.streamer});

  @override
  _StreamState createState() => _StreamState();
}

class _StreamState extends State<Stream> {
  Signaling? _signaling;
  Map<int, Signaling> _signalings = {};
  int n = 0;
  List<dynamic> _streamInfo = [];
  String? _selfId;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  // RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  Connection? _connection;
  Map<int, Connection?>? _connections;
  MediaStream? _localStream;

  // ignore: unused_element
  _StreamState();

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    // await _remoteRenderer.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
    _signaling?.close();
    _localRenderer.dispose();
    // _remoteRenderer.dispose();
  }

  void _connect() async {
    _signaling ??= Signaling(widget.host, widget.streamer, null, n)
      ..connect(widget.streamer);
    _signalings[n] = _signaling!;
    n++;
    _signaling?.onSignalingStateChange = (SignalingState state) {
      switch (state) {
        case SignalingState.ConnectionClosed:
        case SignalingState.ConnectionError:
        case SignalingState.ConnectionOpen:
          break;
      }
    };

    _signaling?.onCallStateChange =
        (Connection connection, CallState state, [MediaStream? stream]) {
      switch (state) {
        case CallState.CallStateNew:
          setState(() {
            _connection = connection;
            _connections?[n - 1] = connection;
            _inCalling = true;
            _localStream = stream;
          });
          _newSignaling();
          break;
        case CallState.CallStateBye:
          setState(() {
            _localRenderer.srcObject = null;
            // _remoteRenderer.srcObject = null;
            _inCalling = false;
            _connection = null;
          });
          break;
        case CallState.CallStateInvite:
        case CallState.CallStateConnected:
        case CallState.CallStateRinging:
      }
    };

    _signaling?.onPeersUpdate = ((event) {
      setState(() {
        _selfId = event['self'];
        _streamInfo = event['streamInfo'];
      });
    });

    _signaling?.onLocalStream = ((stream) {
      _localRenderer.srcObject = stream;
    });

    // _signaling?.onAddRemoteStream = ((_, stream) {
    //   print('aaaaaaaaaaaaaaaaaa');
    // });

    // _signaling?.onRemoveRemoteStream = ((_, stream) {
    //   _remoteRenderer.srcObject = null;
    // });
  }

  void _newSignaling() async {
    _signaling ??= Signaling(widget.host, widget.streamer, _localStream, n)
      ..connect(widget.streamer);
    _signalings[n] = _signaling!;
    n++;

    _signaling?.onCallStateChange =
        (Connection connection, CallState state, [MediaStream? stream]) {
      switch (state) {
        case CallState.CallStateNew:
          setState(() {
            _connection = connection;
            _connections?[n - 1] = connection;
            _inCalling = true;
            _localStream = stream;
          });
          _newSignaling();
          break;
        case CallState.CallStateBye:
          setState(() {
            _connections?[n - 1] = null;
          });
          break;
        case CallState.CallStateInvite:
        case CallState.CallStateConnected:
        case CallState.CallStateRinging:
      }
    };
  }

  _invitePeer(BuildContext context, bool useScreen) async {
    if (_signaling != null) {
      _signaling?.invite('video', useScreen);
    }
  }

  _hangUp() {
    if (_connection != null) {
      _signaling?.bye(_connection!.cid);
    }
  }

  _switchCamera() {
    _signaling?.switchCamera();
  }

  _muteMic() {
    _signaling?.muteMic();
  }

  _buildRow(context, peer) {
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(
            'ビデオ配信か画面共有かを選んでください (Screen sharing isn\'t available for now)'),
        onTap: null,
        trailing: SizedBox(
            width: 100.0,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  IconButton(
                    icon: Icon(
                      // self ? Icons.close : Icons.videocam,
                      //   color: self ? Colors.grey : Colors.black
                      Icons.videocam,
                      color: Colors.black,
                    ),
                    onPressed: () => _invitePeer(context, false),
                    tooltip: 'Video calling',
                  ),
                  IconButton(
                    icon: Icon(
                      // self ? Icons.close : Icons.screen_share,
                      //   color: self ? Colors.grey : Colors.black
                      Icons.screen_share,
                      color: Colors.grey,
                    ),
                    onPressed: () => _invitePeer(context, true),
                    tooltip: 'Screen sharing',
                  )
                ])),
        subtitle: Text('room id: ' + peer['roomId']),
      ),
      Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('配信をする'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: null,
            tooltip: 'setup',
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _inCalling
          ? SizedBox(
              width: 200.0,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    FloatingActionButton(
                      child: const Icon(Icons.switch_camera),
                      onPressed: _switchCamera,
                    ),
                    FloatingActionButton(
                      onPressed: _hangUp,
                      tooltip: 'Hangup',
                      child: Icon(Icons.call_end),
                      backgroundColor: Colors.pink,
                    ),
                    FloatingActionButton(
                      child: const Icon(Icons.mic_off),
                      onPressed: _muteMic,
                    )
                  ]))
          : null,
      body: _inCalling
          ? OrientationBuilder(builder: (context, orientation) {
              return Container(
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
                        child: RTCVideoView(_localRenderer),
                        decoration: BoxDecoration(color: Colors.black54),
                      )),
                  // Positioned(
                  //   left: 20.0,
                  //   top: 20.0,
                  //   child: Container(
                  //     width: orientation == Orientation.portrait ? 90.0 : 120.0,
                  //     height:
                  //         orientation == Orientation.portrait ? 120.0 : 90.0,
                  //     child: RTCVideoView(_localRenderer, mirror: true),
                  //     decoration: BoxDecoration(color: Colors.black54),
                  //   ),
                  // ),
                ]),
              );
            })
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: (_streamInfo != null ? _streamInfo.length : 0),
              itemBuilder: (context, i) {
                return _buildRow(context, _streamInfo[i]);
              }),
    );
  }
}
