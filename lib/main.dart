import 'dart:async';
import 'package:flutter/material.dart';
import 'tflite_helper.dart'; // 🔹 TFLite Helper 추가

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TFLiteHelper tfliteHelper = TFLiteHelper();
  await tfliteHelper.loadModel(); // 모델 로드

  // 🔹 테스트 실행
  int predictedClass = await tfliteHelper.predictClass();
  print("🏆 예측된 클래스: $predictedClass");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TestResultScreen(),
    );
  }
}

class TestResultScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("TFLite 테스트 실행")),
      body: Center(
        child: Text(
          "테스트 오디오 파일을 이용한 예측 실행 완료!\n결과는 로그를 확인하세요.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
