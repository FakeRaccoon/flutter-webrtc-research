import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class GetDisplayManual extends StatefulWidget {
  @override
  _GetDisplayManualState createState() => _GetDisplayManualState();
}

class _GetDisplayManualState extends State<GetDisplayManual> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  TextEditingController offerController = TextEditingController();
  TextEditingController answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _initializePeerConnection();
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _peerConnection?.close();
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

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };
  }

  /// ✅ Create Offer
  Future<void> createOffer() async {
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      log('📤 ICE Candidate generated');
    };

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    offerController.text = jsonEncode({'sdp': offer.sdp, 'type': offer.type});
  }

  /// ✅ Create Answer
  Future<void> createAnswer() async {
    final offer = jsonDecode(offerController.text);
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    answerController.text =
        jsonEncode({'sdp': answer.sdp, 'type': answer.type});
  }

  /// ✅ Apply Answer
  Future<void> applyAnswer() async {
    final answer = jsonDecode(answerController.text);
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answer['sdp'], answer['type']),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Screen Viewer')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _remoteRenderer.textureId != null
                  ? RTCVideoView(_remoteRenderer)
                  : Text('Waiting for screen sharing...'),
            ),
          ),
          TextField(
              controller: offerController,
              decoration: InputDecoration(labelText: 'Offer SDP')),
          ElevatedButton(onPressed: createOffer, child: Text('Create Offer')),
          TextField(
              controller: answerController,
              decoration: InputDecoration(labelText: 'Answer SDP')),
          ElevatedButton(onPressed: createAnswer, child: Text('Create Answer')),
          ElevatedButton(onPressed: applyAnswer, child: Text('Apply Answer')),
        ],
      ),
    );
  }
}
