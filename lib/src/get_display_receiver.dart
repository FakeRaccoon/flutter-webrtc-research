import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class ScreenViewerApp extends StatefulWidget {
  @override
  _ScreenViewerAppState createState() => _ScreenViewerAppState();
}

class _ScreenViewerAppState extends State<ScreenViewerApp> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _socket;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _initializeWebSocket();
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _socket?.sink.close(status.goingAway);

    super.dispose();
  }

  /// ✅ Initialize WebSocket connection
  void _initializeWebSocket() {
    final uri = Uri.parse('wss://d37f-103-125-36-242.ngrok-free.app/ws');
    _socket = WebSocketChannel.connect(uri);

    log('🌐 Connecting to WebSocket: $uri');

    // _socket?.sink.add(jsonEncode({'type': 'offer', 'sdp': ''}));

    _socket?.stream.listen((message) async {
      log('📩 WebSocket Message Received: $message'); // <-- Check if this logs

      if (message is String) {
        try {
          final data = jsonDecode(message);
          log('🔍 Decoded Message: ${data['type']}');

          if (data['type'] == 'offer') {
            log('🔍 Decoded Message offer');

            await _handleOffer(data);
          } else if (data['type'] == 'candidate') {
            await _handleCandidate(data);
          } else {
            log('ℹ️ Unknown Message Type: $data');
          }
        } catch (e) {
          log('❌ Error decoding message: $e');
        }
      }
    }, onError: (error) {
      log('❌ WebSocket Error: $error');
    }, onDone: () {
      log('🔌 WebSocket Disconnected');
      setState(() => _isConnected = false);
    });

    setState(() => _isConnected = true);
    _initializePeerConnection();
  }

  /// ✅ Initialize WebRTC Peer Connection
  Future<void> _initializePeerConnection() async {
    if (_peerConnection != null) {
      log('⚠️ Peer Connection already initialized.');
      return;
    }

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };

    _peerConnection = await createPeerConnection(config);

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
          'device': 'receiver',
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

  /// ✅ Handle WebRTC Offer
  Future<void> _handleOffer(Map<String, dynamic> offer) async {
    log('📩 Received _handleOffer 001');

    try {
      log('📩 Received _handleOffer 002');

      log('📩 Received WebRTC Offer: $offer');

      // Ensure Peer Connection is initialized
      log('📩 Received _handleOffer 003');

      await _initializePeerConnection();
      log('📩 Received _handleOffer 004');

      await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']));
      log('📩 Received _handleOffer 005');

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection?.setLocalDescription(answer);

      _socket?.sink.add(jsonEncode({
        'type': 'answer',
        'sdp': answer.sdp,
      }));

      log('📩 Received _handleOffer 006');

      // ✅ Add ICE candidates from the offer (if available)
      if (offer.containsKey('candidate')) {
        for (var candidate in offer['candidate']) {
          await _handleCandidate(candidate);
        }
      }
      log('📩 Received _handleOffer 007');
    } catch (e) {
      log('❌ Error handling WebRTC offer: $e');
    }
  }

  /// ✅ Handle ICE Candidate
  Future<void> _handleCandidate(Map<String, dynamic> data) async {
    try {
      log('📩 Received ICE Candidate: $data');

      // Ensure Peer Connection is initialized
      await _initializePeerConnection();

      var candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );

      await _peerConnection?.addCandidate(candidate);
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
    );
  }
}
