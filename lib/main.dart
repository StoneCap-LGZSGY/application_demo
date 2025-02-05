import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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
  String _recordingSource = '';
  String _filePath = '';
  bool _hasBluetoothConnection = false;

  @override
  void initState() {
    super.initState();
    _initializeRecorder();
  }

  Future<void> _initializeRecorder() async {
    await Permission.microphone.request();
    await Permission.bluetooth.request();
    await _recorder.openRecorder();
  }

  Future<void> _startRecording(String source) async {
    if (source == 'bluetooth' && !_hasBluetoothConnection) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('블루투스 이어폰이 연결되지 않다.')),
      );
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/audio_${source}_record.wav';

    setState(() {
      _recordingSource = source;
      _filePath = filePath;
    });

    await _recorder.startRecorder(toFile: filePath);
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
      _recordingSource = '';
    });

    // 녹음 완료 후 재생 페이지로 이동
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaybackScreen(filePath: _filePath),
      ),
    );
  }

  Future<void> _checkBluetoothConnection() async {
    setState(() {
      _hasBluetoothConnection = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('블루투스 이어폰이 연결되었습니다.')),
    );
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Multi Microphone Recorder'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _hasBluetoothConnection
                  ? '블루투스 이어폰 연결됨'
                  : '블루투스 이어폰 연결 안 됨',
              style: TextStyle(fontSize: 18, color: Colors.blueAccent),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkBluetoothConnection,
              child: Text('블루투스 상태 확인'),
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: !_isRecording
                  ? () => _startRecording('bluetooth')
                  : null,
              child: Text('블루투스 이어폰 마이크로 녹음'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording && _recordingSource == 'bluetooth'
                    ? Colors.grey
                    : Colors.blue,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: !_isRecording
                  ? () => _startRecording('phone')
                  : null,
              child: Text('휴대폰 마이크로 녹음'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording && _recordingSource == 'phone'
                    ? Colors.grey
                    : Colors.green,
              ),
            ),
            SizedBox(height: 20),
            if (_isRecording)
              ElevatedButton(
                onPressed: _stopRecording,
                child: Text('녹음 중지'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
              ),
            SizedBox(height: 20),
            Text(
              _isRecording
                  ? '녹음 중 ($_recordingSource)'
                  : '녹음을 시작하려면 버튼을 누르세요.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackScreen extends StatelessWidget {
  final String filePath;

  PlaybackScreen({required this.filePath});

  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Playback Recording'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '녹음 파일 경로:',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 10),
            Text(
              filePath,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _player.openPlayer();
                await _player.startPlayer(fromURI: filePath);
              },
              child: Text('녹음 재생'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _player.stopPlayer();
              },
              child: Text('재생 중지'),
            ),
          ],
        ),
      ),
    );
  }
}
