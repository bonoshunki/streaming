import 'package:flutter/material.dart';
import 'dart:core';
import '../models/connection.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class Watch extends StatefulWidget {
  static String tag = 'call_sample';
  final String host;
  final bool streamer;
  Watch({required this.host, required this.streamer});

  @override
  _WatchState createState() => _WatchState();
}

class _WatchState extends State<Watch> {
  Signaling? _signaling;
  List<dynamic> _peers = [];
  String? _selfId;
  // RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  Connection? _connection;

  // ignore: unused_element
  _WatchState();

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _remoteRenderer.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
    _signaling?.close();
    _remoteRenderer.dispose();
  }

  void _connect() async {
    _signaling ??= Signaling(widget.host, widget.streamer, null, 0)
      ..connect(widget.streamer);
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
            _inCalling = true;
          });
          break;
        case CallState.CallStateBye:
          setState(() {
            _remoteRenderer.srcObject = null;
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
        _peers = event['peers'];
      });
    });

    _signaling?.onAddRemoteStream = ((_, stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    });

    _signaling?.onRemoveRemoteStream = ((_, stream) {
      _remoteRenderer.srcObject = null;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('???????????????'),
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
                    // FloatingActionButton(
                    //   child: const Icon(Icons.switch_camera),
                    //   onPressed: _switchCamera,
                    // ),
                    FloatingActionButton(
                      onPressed: _hangUp,
                      tooltip: 'Hangup',
                      child: Icon(Icons.call_end),
                      backgroundColor: Colors.pink,
                    ),
                    //   FloatingActionButton(
                    //     child: const Icon(Icons.mic_off),
                    //     onPressed: _muteMic,
                    //   )
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
                        child: RTCVideoView(_remoteRenderer),
                        decoration: BoxDecoration(color: Colors.black54),
                      )),
                  // Positioned(
                  //   left: 20.0,
                  //   top: 20.0,
                  //   child: Container(
                  //     width: orientation == Orientation.portrait ? 90.0 : 120.0,
                  //     height:
                  //         orientation == Orientation.portrait ? 120.0 : 90.0,
                  //     // child: RTCVideoView(_localRenderer, mirror: true),
                  //     decoration: BoxDecoration(color: Colors.black54),
                  //   ),
                  // ),
                ]),
              );
            })
          : null,
      // : ListView.builder(
      //     shrinkWrap: true,
      //     padding: const EdgeInsets.all(0.0),
      //     itemCount: (_peers != null ? _peers.length : 0),
      //     itemBuilder: (context, i) {
      //       return _buildRow(context, _peers[i]);
      //     }),
    );
  }
}
