import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'tflite_helper.dart'; // 🔹 TFLite Helper 추가

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MicrophoneRecorder(),
    );
  }
}

class MicrophoneRecorder extends StatefulWidget {
  @override
  _MicrophoneRecorderState createState() => _MicrophoneRecorderState();
}

class _MicrophoneRecorderState extends State<MicrophoneRecorder> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String _filePath = '';
  Timer? _recordingTimer;

  final TFLiteHelper _tfliteHelper = TFLiteHelper(); // 🔹 TFLite Helper 추가

  @override
  void initState() {
    super.initState();
    _initializeRecorder();
    _tfliteHelper.loadModel(); // 🔹 모델 로드
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.storage,
    ].request();
  }

  Future<void> _initializeRecorder() async {
    await _requestPermissions();
    await _recorder.openRecorder();
  }

  Future<void> _startRecording() async {
    try {
      final directory = Directory('/storage/emulated/0/Download/record');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filePath = '${directory.path}/audio_record.wav';

      setState(() {
        _filePath = filePath;
        _isRecording = true;
      });

      await _recorder.startRecorder(toFile: filePath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음이 시작되었습니다. (최대 8.76초)')),
      );

      _recordingTimer = Timer(Duration(milliseconds: 8760), () {
        _stopRecording(autoStopped: true);
      });

    } catch (e) {
      print("❌ 녹음 시작 오류: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음을 시작할 수 없습니다: $e')),
      );
    }
  }

  Future<void> _stopRecording({bool autoStopped = false}) async {
    try {
      await _recorder.stopRecorder();
      _recordingTimer?.cancel();
      setState(() {
        _isRecording = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            autoStopped
                ? '녹음이 자동으로 중지되었습니다. (8.76초 초과)\n$_filePath'
                : '녹음이 저장되었습니다:\n$_filePath',
          ),
        ),
      );

      // 🔹 예측 실행
      int predictedClass = await _tfliteHelper.predictClass(); // `predictClass()` 사용

      // 🔹 결과 출력
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🏆 예측된 클래스: $predictedClass")),
      );

    } catch (e) {
      print("❌ 녹음 중지 오류: $e");
    }
  }

  @override
  void dispose() async {
    await _recorder.closeRecorder();
    _recordingTimer?.cancel();
    _tfliteHelper.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Multi Microphone Recorder & TFLite'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isRecording ? null : _startRecording,
              child: Text('🎤 녹음 시작'),
            ),
            SizedBox(height: 20),
            if (_isRecording)
              ElevatedButton(
                onPressed: _stopRecording,
                child: Text('🔴 녹음 중지'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
