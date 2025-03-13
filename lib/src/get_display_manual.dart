import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class GetDisplayManual extends StatefulWidget {
  @override
  _GetDisplayManualState createState() => _GetDisplayManualState();
}

class _GetDisplayManualState extends State<GetDisplayManual> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  TextEditingController offerController = TextEditingController();
  TextEditingController answerController = TextEditingController();

  /// ✅ Request background permission (Android only)
  Future<void> requestBackgroundPermission([bool isRetry = false]) async {
    try {
      var hasPermissions = await FlutterBackground.hasPermissions;
      if (!isRetry) {
        const androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: 'Screen Sharing',
          notificationText: 'Screen is being shared.',
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon:
              AndroidResource(name: 'livekit_ic_launcher', defType: 'mipmap'),
        );
        hasPermissions =
            await FlutterBackground.initialize(androidConfig: androidConfig);
      }
      if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
    } catch (e) {
      if (!isRetry) {
        await Future.delayed(
            Duration(seconds: 1), () => requestBackgroundPermission(true));
      }
      log('⚠️ Background permission error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
    _initializePeerConnection();
  }

  void _initializeRenderer() async {
    await _localRenderer.initialize();
    setState(() {}); // Ensure UI updates
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _peerConnection?.close();
    _localStream?.getTracks().forEach((track) => track.stop()); // Stop stream
    _localStream?.dispose();
    super.dispose();
  }

  /// ✅ Initialize WebRTC Peer Connection
  Future<void> _initializePeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      log('📤 ICE Candidate generated: ${candidate.candidate}');
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      log('🎥 Remote track received');
      if (event.streams.isNotEmpty) {
        _localRenderer.srcObject = event.streams[0];
      }
    };
  }

  /// ✅ Start Screen Sharing
  Future<void> startScreenSharing() async {
    try {
      await requestBackgroundPermission();
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': true,
      });

      log('✅ Screen share stream received');
      _localStream = stream;
      _localRenderer.srcObject = _localStream;

      _localStream?.getTracks().forEach((track) {
        log('🔗 Adding track: ${track.kind}');
        _peerConnection?.addTrack(track, _localStream!);
      });

      setState(() {}); // Update UI after setting the stream
    } catch (e) {
      log('❌ Error starting screen sharing: $e');
    }
  }

  /// ✅ Create Offer (Flutter → Web)
  Future<void> createOffer() async {
    if (_peerConnection == null) {
      log('⚠️ Peer connection not initialized');
      return;
    }

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    offerController.text = jsonEncode({'sdp': offer.sdp, 'type': offer.type});

    log('📤 Offer created & set as Local Description');
  }

  /// ✅ Create Answer (Web → Flutter)
  Future<void> createAnswer() async {
    if (_peerConnection == null) {
      log('⚠️ Peer connection not initialized');
      return;
    }

    final offerText = offerController.text;
    if (offerText.isEmpty) {
      log('⚠️ No offer available to set as Remote Description');
      return;
    }

    final offer = jsonDecode(offerText);
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    answerController.text =
        jsonEncode({'sdp': answer.sdp, 'type': answer.type});

    log('📥 Answer created & set as Local Description');
  }

  /// ✅ Apply Answer (Web → Flutter)
  Future<void> applyAnswer() async {
    if (_peerConnection == null) {
      log('⚠️ Peer connection not initialized');
      return;
    }

    if (_peerConnection?.signalingState ==
        RTCSignalingState.RTCSignalingStateStable) {
      log('⚠️ Already in stable state, skipping setRemoteDescription');
      return;
    }

    final answerText = answerController.text;
    if (answerText.isEmpty) {
      log('⚠️ No answer available to apply');
      return;
    }

    final answer = jsonDecode(answerText);
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answer['sdp'], answer['type']),
    );

    log('✅ Answer applied successfully');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Screen Sharing Host')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _localRenderer.textureId != null
                  ? RTCVideoView(_localRenderer)
                  : Text('Click Start Sharing to begin...'),
            ),
          ),
          ElevatedButton(
              onPressed: startScreenSharing,
              child: Text('Start Screen Sharing')),
          TextField(
              controller: offerController,
              decoration: InputDecoration(labelText: 'Offer SDP')),
          ElevatedButton(onPressed: createOffer, child: Text('Create Offer')),
          TextField(
              controller: answerController,
              decoration: InputDecoration(labelText: 'Answer SDP')),
          // ElevatedButton(onPressed: createAnswer, child: Text('Create Answer')),
          ElevatedButton(onPressed: applyAnswer, child: Text('Apply Answer')),
        ],
      ),
    );
  }
}
