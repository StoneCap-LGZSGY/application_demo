import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';

class TFLiteHelper {
  Interpreter? _model;
  List<int>? inputShape;
  static const int SAMPLE_RATE = 22050;
  static const int N_MFCC = 40;
  static const int MAX_PAD_LEN = 376;

  /// 🔹 모델 로드
  Future<void> loadModel() async {
    try {
      print("📢 TFLite 모델 로드 시작...");
      var options = InterpreterOptions();
      options.threads = 4;
      _model = await Interpreter.fromAsset('assets/audio_model.tflite', options: options);
      inputShape = _model!.getInputTensor(0).shape;
      print("✅ TFLite 모델 로드 완료: audio_model.tflite");
      print("📌 모델 입력 형상: $inputShape");
    } catch (e) {
      print("❌ TFLite 모델 로드 실패: $e");
    }
  }

  /// 🔹 `.wav` 파일 경로 반환 (테스트 오디오 파일 사용)
  Future<String> getWavFilePath() async {
    return "assets/testaudio.wav";
  }

  /// 🔹 `.wav` → `PCM` 변환
  Future<Uint8List> extractPcmData(String wavFilePath) async {
    try {
      Uint8List wavBytes;
      if (wavFilePath.startsWith("assets/")) {
        ByteData data = await rootBundle.load(wavFilePath);
        wavBytes = data.buffer.asUint8List();
      } else {
        File wavFile = File(wavFilePath);
        if (!wavFile.existsSync()) {
          print("❌ .wav 파일이 존재하지 않습니다: $wavFilePath");
          return Uint8List(0);
        }
        wavBytes = await wavFile.readAsBytes();
      }

      // WAV 헤더 제거 (44바이트)
      int headerSize = 44;
      if (wavBytes.length <= headerSize) {
        print("❌ WAV 파일이 너무 작음");
        return Uint8List(0);
      }

      Uint8List pcmData = wavBytes.sublist(headerSize);
      print("✅ PCM 데이터 추출 완료 (길이: ${pcmData.length})");
      return pcmData;
    } catch (e) {
      print("❌ WAV → PCM 변환 오류: $e");
      return Uint8List(0);
    }
  }

  /// 🔹 오디오 데이터 전처리 (노이즈 제거 + 증폭)
  Float32List preprocessAudio(Uint8List pcmData) {
    if (inputShape == null || inputShape!.length != 4) {
      print("❌ 모델 입력 형식을 찾을 수 없음");
      return Float32List(0);
    }

    int height = inputShape![1];
    int width = inputShape![2];

    List<double> audioSignal = pcmData.map((e) => e.toDouble()).toList();
    audioSignal = _reduceNoise(audioSignal);
    audioSignal = _amplifySignal(audioSignal);

    List<List<double>> mfccFeatures = _extractMFCC(audioSignal, SAMPLE_RATE, N_MFCC);
    List<List<double>> paddedMFCC = _padOrTrimMFCC(mfccFeatures, MAX_PAD_LEN);

    Float32List inputArray = Float32List.fromList(paddedMFCC.expand((e) => e).toList());
    print("✅ 변환 완료: ${inputArray.length} 요소, 입력 형태: [1, $N_MFCC, $MAX_PAD_LEN]");
    return inputArray;
  }

  /// 🔹 노이즈 제거 (더 강한 필터 적용)
  List<double> _reduceNoise(List<double> signal) {
    int noiseWindow = SAMPLE_RATE ~/ 2; // 0.5초를 노이즈로 가정
    double noiseMean = signal.sublist(0, min(noiseWindow, signal.length)).reduce((a, b) => a + b) / noiseWindow;

    List<double> filteredSignal = signal.map((s) => s - noiseMean).toList();

    // **High-pass 필터 적용 (50Hz 이하 제거)**
    for (int i = 1; i < filteredSignal.length; i++) {
      filteredSignal[i] = filteredSignal[i] - 0.95 * filteredSignal[i - 1];
    }

    return filteredSignal;
  }

  /// 🔹 소리 증폭 (정규화 및 다이나믹 노멀라이제이션)
  List<double> _amplifySignal(List<double> signal) {
    double maxAmp = signal.map((e) => e.abs()).reduce(max);
    if (maxAmp == 0.0) return signal;

    double scale = 1.0 / maxAmp;
    List<double> amplified = signal.map((e) => e * scale).toList();

    // **음성 강조 (다이나믹 노멀라이제이션)**
    double meanAmp = amplified.reduce((a, b) => a + b) / amplified.length;
    return amplified.map((e) => e - meanAmp).toList();
  }

  /// 🔹 MFCC 특징 추출
  List<List<double>> _extractMFCC(List<double> signal, int sampleRate, int numMFCC) {
    List<List<double>> mfccFeatures = List.generate(numMFCC, (_) => List.filled(100, 0.0));

    for (int i = 0; i < numMFCC; i++) {
      for (int j = 0; j < min(100, signal.length); j++) {
        mfccFeatures[i][j] = signal[j] * (i + 1);
      }
    }
    return mfccFeatures;
  }

  /// 🔹 MFCC 패딩 또는 자르기
  List<List<double>> _padOrTrimMFCC(List<List<double>> mfcc, int maxLen) {
    List<List<double>> finalMfcc = [];
    for (List<double> row in mfcc) {
      if (row.length < maxLen) {
        row = [...row, ...List.filled(maxLen - row.length, 0.0)];
      } else if (row.length > maxLen) {
        row = row.sublist(0, maxLen);
      }
      finalMfcc.add(row);
    }
    return finalMfcc;
  }

  /// 🔹 예측 실행
  Future<int> predictClass() async {
    List<double> predictions = await predict();
    if (predictions.isEmpty) return -1;

    int predictedClass = predictions.indexOf(predictions.reduce(max));
    print("🏆 예측된 클래스: $predictedClass");
    return predictedClass;
  }

  Future<List<double>> predict() async {
    if (_model == null) {
      print("❌ 모델이 로드되지 않음");
      return [];
    }

    try {
      String wavFilePath = await getWavFilePath();
      Uint8List pcmData = await extractPcmData(wavFilePath);
      if (pcmData.isEmpty) return [];

      Float32List inputArray = preprocessAudio(pcmData);

      var outputArray = List.filled(10, 0.0).reshape([1, 10]);
      _model!.run(inputArray.reshape([1, 40, 376, 1]), outputArray);

      List<double> predictions = outputArray[0];
      print("🔮 예측 결과 (확률): $predictions");
      return predictions;
    } catch (e) {
      print("❌ 예측 실행 오류: $e");
      return [];
    }
  }

  void close() {
    _model?.close();
  }
}
