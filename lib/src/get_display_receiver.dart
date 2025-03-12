import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

class ScreenViewerApp extends StatefulWidget {
  @override
  _ScreenViewerAppState createState() => _ScreenViewerAppState();
}

class _ScreenViewerAppState extends State<ScreenViewerApp> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _socket;
  bool _isConnected = false;
  final List<Map<String, dynamic>> _pendingCandidates = [];

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _initializeWebSocket();
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _peerConnection?.close();
    _peerConnection = null; // ✅ Ensure reset
    _socket?.sink.close(status.goingAway);
    _socket = null; // ✅ Reset WebSocket
    super.dispose();
  }

  /// ✅ Initialize WebSocket connection with auto-reconnect
  void _initializeWebSocket() {
    final uri = Uri.parse('wss://d37f-103-125-36-242.ngrok-free.app/ws');
    _socket = WebSocketChannel.connect(uri);

    log('🌐 Connecting to WebSocket: $uri');

    _socket?.stream.listen(
      (message) async {
        log('📩 WebSocket Message Received: $message');
        _handleWebSocketMessage(message);
      },
      onError: (error) {
        log('❌ WebSocket Error: $error');
        _reconnectWebSocket();
      },
      onDone: () {
        log('🔌 WebSocket Disconnected');
        _reconnectWebSocket();
      },
    );

    setState(() => _isConnected = true);
    _initializePeerConnection();
  }

  /// ✅ Auto-reconnect WebSocket on failure
  void _reconnectWebSocket() {
    setState(() => _isConnected = false);
    Future.delayed(Duration(seconds: 3), () {
      log('🔄 Reconnecting WebSocket...');
      _initializeWebSocket();
    });
  }

  /// ✅ Handle incoming WebSocket messages
  void _handleWebSocketMessage(String message) async {
    try {
      final data = jsonDecode(message);

      switch (data['type']) {
        case 'offer':
          await _handleOffer(data);
          break;
        case 'answer':
          await _handleAnswer(data);
          break;
        case 'candidate':
          await _handleCandidate(data);
          break;
        default:
          log('⚠️ Unknown Message Type: $data');
      }
    } catch (e) {
      log('❌ Error decoding message: $e');
    }
  }

  /// ✅ Initialize WebRTC Peer Connection
  Future<void> _initializePeerConnection() async {
    if (_peerConnection != null) {
      log('⚠️ Peer Connection already initialized. Resetting...');
      await _peerConnection?.close();
      _peerConnection = null;
    }

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };

    _peerConnection = await createPeerConnection(config);
    log('✅ Peer Connection Initialized');

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      log('📡 Receiving Screen Stream');
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      log('📤 Sending ICE Candidate');
      if (_socket != null && _isConnected) {
        _socket?.sink.add(jsonEncode({
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }));
      }
    };

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      log('🔄 ICE State Changed: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        log('❌ ICE Connection Failed! Retrying...');
      }
    };
  }

  /// ✅ Create and send an SDP Offer
  Future<void> createAndSendOffer() async {
    await _initializePeerConnection();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // log('✅ Sending WebRTC Offer');
    // _socket?.sink.add(jsonEncode({
    //   'type': 'offer',
    //   'sdp': offer.sdp,
    // }));
  }

  /// ✅ Handle incoming WebRTC Offer
  Future<void> _handleOffer(Map<String, dynamic> offer) async {
    log('📩 Received WebRTC Offer');

    await _initializePeerConnection();

    if (_peerConnection?.getRemoteDescription() == null) {
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], 'offer'),
      );

      log('✅ Offer set. Creating and sending answer...');
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection?.setLocalDescription(answer);

      _socket?.sink.add(jsonEncode({
        'type': 'answer',
        'sdp': answer.sdp,
      }));
    } else {
      log('⚠️ Offer already set. Ignoring duplicate.');
    }
  }

  /// ✅ Handle incoming WebRTC Answer
  Future<void> _handleAnswer(Map<String, dynamic> answer) async {
    log('📩 Received WebRTC Answer');

    // If this device created the offer, apply the answer
    var data = await _peerConnection?.getLocalDescription();
    if (data?.type == 'offer') {
      log('✅ This device created the offer. Applying answer...');

      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], 'answer'),
      );

      // Apply queued ICE candidates (if any)
      for (var candidate in _pendingCandidates) {
        await _handleCandidate(candidate);
      }
      _pendingCandidates.clear();
    } else {
      log('⚠️ Unexpected answer received. Ignoring.');
    }
  }

  /// ✅ Handle ICE Candidate (store if SDP is not yet set)
  Future<void> _handleCandidate(Map<String, dynamic> data) async {
    try {
      log('📩 Received ICE Candidate: $data');

      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );

      if (_peerConnection?.getRemoteDescription() != null) {
        log('✅ Adding ICE Candidate');
        await _peerConnection?.addCandidate(candidate);
      } else {
        log('📌 Storing ICE Candidate until remoteDescription is set.');
        _pendingCandidates.add(data);
      }
    } catch (e) {
      log('❌ Error handling ICE candidate: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Screen Viewer')),
      body: Center(
        child: _remoteRenderer.textureId != null
            ? RTCVideoView(_remoteRenderer)
            : Text('Waiting for screen sharing...'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: createAndSendOffer,
        tooltip: 'Start WebRTC Connection',
        child: Icon(Icons.send),
      ),
    );
  }
}
