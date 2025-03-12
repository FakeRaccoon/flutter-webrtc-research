import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc_example/src/widgets/screen_select_dialog.dart';
import 'package:web_socket_client/web_socket_client.dart' as IO;

/*
 * getDisplayMedia sample
 */
class GetDisplayMediaSample extends StatefulWidget {
  static String tag = 'get_display_media_sample';

  @override
  _GetDisplayMediaSampleState createState() => _GetDisplayMediaSampleState();
}

class _GetDisplayMediaSampleState extends State<GetDisplayMediaSample> {
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  DesktopCapturerSource? selected_source_;
  late IO.WebSocket _socket;
  RTCPeerConnection? _peerConnection;

  @override
  void initState() {
    super.initState();
    _connectToSocket();
    initRenderers();
  }

  @override
  void deactivate() {
    super.deactivate();
    if (_inCalling) {
      _stop();
    }
    _localRenderer.dispose();
  }

  /// WEB SOCKET
  void _connectToSocket() {
    try {
      log('Connecting to WebSocket...');

      final uri = Uri.parse('ws://10.10.4.21:8080/ws');
      const timeout = Duration(seconds: 10);

      _socket = IO.WebSocket(uri, timeout: timeout);
      _socket.connection.listen((event) async {
        log('🔍 Connection state: $event'); // ✅ Print the actual event state

        // Temporarily check event type
        if (event.toString().contains('open') ||
            event.toString().contains('Connected')) {
          log('✅ WebSocket is open! Initializing peer connection...');
          await _initializePeerConnection();
        }
      });

      try {
        _socket.messages.listen((message) async {
          try {
            if (message is String) {
              final data = jsonDecode(message);
              if (data is Map<String, dynamic>) {
                if (data.containsKey('offer')) {
                  _handleOffer(data);
                } else if (data.containsKey('answer')) {
                  _handleAnswer(data);
                } else if (data.containsKey('candidate')) {
                  _handleCandidate(data);
                }
              }
            }
          } catch (e) {
            log('Error parsing WebSocket message: $e');
          }
        });
      } catch (e) {
        log(e.toString());
      }

      log('WebSocket connection initialized.');
    } catch (e) {
      log('WebSocket connection failed: $e');
    }
  }

  Future<void> _initializePeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': []},
      ]
    };

    _peerConnection = await createPeerConnection(config);

    // _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
    //   log('🔼 Sending ICE Candidate: $candidate');

    //   // ✅ Convert RTCIceCandidate to JSON before sending
    //   _socket.send(jsonEncode({
    //     'type': 'candidate',
    //     'candidate': candidate.candidate,
    //     'sdpMid': candidate.sdpMid,
    //     'sdpMLineIndex': candidate.sdpMLineIndex,
    //   }));
    // };

    // _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
    //   log('ICE Connection State: $state');
    // };
  }

  void _handleOffer(Map<String, dynamic> data) async {
    log('📩 Received Offer: $data');

    if (_peerConnection == null) {
      log('❌ _peerConnection is null! Initializing...');
      await _initializePeerConnection();
    }

    var offer = RTCSessionDescription(data['sdp'], data['type']);

    // 🔹 Check WebRTC signaling state before setting remote offer
    if (_peerConnection?.signalingState ==
        RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      log('⚠️ Have local offer already! Resetting state...');
      await _peerConnection?.restartIce(); // Safely restart ICE process

      // Rollback any conflicting SDP
      await _peerConnection
          ?.setLocalDescription(RTCSessionDescription('', 'rollback'));
    }

    try {
      await _peerConnection?.setRemoteDescription(offer);
      log('✅ Successfully set remote description.');

      // var answer = await _peerConnection!.createAnswer();
      // await _peerConnection?.setLocalDescription(answer);
      // log('✅ Sent answer back.');

      // // ✅ Send answer as JSON
      // _socket.send(jsonEncode({
      //   'answer': {'sdp': answer.sdp, 'type': answer.type}
      // }));
    } catch (e) {
      log('❌ Failed to set remote description: $e');
    }
  }

  void _handleAnswer(Map<String, dynamic> data) async {
    log('📩 Received Answer: $data');

    var answer = RTCSessionDescription(data['sdp'], data['type']);
    await _peerConnection?.setRemoteDescription(answer);

    // 🔹 Ensure ICE is restarted if needed
    if (_peerConnection?.iceConnectionState ==
        RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      log('🔄 Restarting ICE due to disconnection...');
      await _peerConnection?.restartIce();
    }
  }

  void _handleCandidate(Map<String, dynamic> data) async {
    log('📩 Received ICE Candidate: $data');

    var candidate = RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      data['sdpMLineIndex'],
    );

    await _peerConnection?.addCandidate(candidate);

    // ✅ Convert RTCIceCandidate to JSON String before sending
    _socket.send(jsonEncode({
      'type': 'candidate',
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    }));
  }

  /// WEB RTC
  Future<void> initRenderers() async {
    await _localRenderer.initialize();
  }

  Future<void> selectScreenSourceDialog(BuildContext context) async {
    if (WebRTC.platformIsDesktop) {
      final source = await showDialog<DesktopCapturerSource>(
        context: context,
        builder: (context) => ScreenSelectDialog(),
      );
      if (source != null) {
        await _makeCall(source);
      }
    } else {
      if (WebRTC.platformIsAndroid) {
        // Android specific
        Future<void> requestBackgroundPermission([bool isRetry = false]) async {
          // Required for android screenshare.
          try {
            var hasPermissions = await FlutterBackground.hasPermissions;
            if (!isRetry) {
              const androidConfig = FlutterBackgroundAndroidConfig(
                notificationTitle: 'Screen Sharing',
                notificationText: 'LiveKit Example is sharing the screen.',
                notificationImportance: AndroidNotificationImportance.normal,
                notificationIcon: AndroidResource(
                    name: 'livekit_ic_launcher', defType: 'mipmap'),
              );
              hasPermissions = await FlutterBackground.initialize(
                  androidConfig: androidConfig);
            }
            if (hasPermissions &&
                !FlutterBackground.isBackgroundExecutionEnabled) {
              await FlutterBackground.enableBackgroundExecution();
            }
          } catch (e) {
            if (!isRetry) {
              return await Future<void>.delayed(const Duration(seconds: 1),
                  () => requestBackgroundPermission(true));
            }
            print('could not publish video: $e');
          }
        }

        await requestBackgroundPermission();
      }
      await _makeCall(null);
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> _makeCall(DesktopCapturerSource? source) async {
    setState(() {
      selected_source_ = source;
    });

    try {
      var stream =
          await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
        'video': selected_source_ == null
            ? true
            : {
                'deviceId': {'exact': selected_source_!.id},
                'mandatory': {'frameRate': 30.0}
              }
      });

      stream.getVideoTracks()[0].onEnded = () {
        log('Screen sharing stopped.');
      };

      _localStream = stream;
      _localRenderer.srcObject = _localStream;

      // 🔹 Add tracks to Peer Connection
      for (var track in _localStream!.getTracks()) {
        await _peerConnection?.addTrack(track, _localStream!);
      }

      if (_peerConnection == null) {
        log("❌ _peerConnection is null. Make sure it's initialized.");
        return;
      }
      //🔹 Create and send an offer
      var offer = await _peerConnection!.createOffer();
      await _peerConnection?.setLocalDescription(offer);

      log('🔼 Sending Offer: ${offer.toMap()}');
      _socket.send(jsonEncode(offer.toMap())); // ✅ Convert to JSON String
      _handleOffer(offer.toMap());
    } catch (e) {
      log('Error: $e');
    }

    setState(() {
      _inCalling = true;
    });
  }

  Future<void> _stop() async {
    try {
      if (kIsWeb) {
        _localStream?.getTracks().forEach((track) => track.stop());
      }
      await _localStream?.dispose();
      _localStream = null;
      _localRenderer.srcObject = null;
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _hangUp() async {
    await _stop();
    setState(() {
      _inCalling = false;
      _socket.close();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('GetDisplayMedia source: ' +
            (selected_source_ != null ? selected_source_!.name : '')),
        actions: [],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
              child: Stack(children: <Widget>[
            if (_inCalling) Text('Screen Recorded')
            // Container(
            //   margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
            //   width: MediaQuery.of(context).size.width,
            //   height: MediaQuery.of(context).size.height,
            //   decoration: BoxDecoration(color: Colors.black54),
            //   child: RTCVideoView(_localRenderer),
            // ),
          ]));
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _inCalling ? _hangUp() : selectScreenSourceDialog(context);
        },
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}
