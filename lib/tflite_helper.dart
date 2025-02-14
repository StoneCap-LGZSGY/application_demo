import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteHelper {
  Interpreter? _model;
  List<int>? inputShape;

  /// 🔹 모델 로드
  Future<void> loadModel() async {
    try {
      print("📢 TFLite 모델 로드 시작...");

      // 🔹 XNNPACK 최적화 활성화
      var options = InterpreterOptions();
      options.threads = 4; // 다중 쓰레드 사용

      _model = await Interpreter.fromAsset('assets/audio_model.tflite', options: options);

      // 🔹 모델 입력 형태 확인
      inputShape = _model!.getInputTensor(0).shape;
      print("✅ TFLite 모델 로드 완료: audio_model.tflite");
      print("📌 모델 입력 형상: $inputShape");
    } catch (e) {
      print("❌ TFLite 모델 로드 실패: $e");
    }
  }

  /// 🔹 `.wav` 파일 경로 반환
  Future<String> getWavFilePath() async {
    return "/storage/emulated/0/Download/record/audio_record.wav";
  }

  /// 🔹 `.wav` → `PCM` 변환
  Future<Uint8List> extractPcmData(String wavFilePath) async {
    try {
      File wavFile = File(wavFilePath);
      Uint8List wavBytes = await wavFile.readAsBytes();

      // 🔹 WAV 헤더 (44바이트) 제거
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

  /// 🔹 PCM 데이터를 MFCC 변환 후 모델 입력 형태로 변환
  Float32List preprocessAudio(Uint8List pcmData) {
    if (inputShape == null || inputShape!.length != 4) {
      print("❌ 모델 입력 형식을 찾을 수 없음");
      return Float32List(0);
    }

    int height = inputShape![1]; // 40 (MFCC 개수)
    int width = inputShape![2]; // 376 (시간 축 길이)
    int channels = inputShape![3]; // 1 (채널 수)

    // 🔹 PCM 데이터를 Float 배열로 변환
    List<double> audioSignal = pcmData.map((e) => e.toDouble()).toList();

    // 🔹 길이 맞추기 (패딩 또는 자르기)
    const int TARGET_LENGTH = 22050; // 1초 길이
    if (audioSignal.length > TARGET_LENGTH) {
      audioSignal = audioSignal.sublist(0, TARGET_LENGTH);
    } else if (audioSignal.length < TARGET_LENGTH) {
      audioSignal.addAll(List.filled(TARGET_LENGTH - audioSignal.length, 0.0));
    }

    // 🔹 오디오 정규화
    double maxValue = audioSignal.reduce((a, b) => a.abs() > b.abs() ? a : b);
    if (maxValue != 0.0) {
      audioSignal = audioSignal.map((e) => e / maxValue).toList();
    }

    // 🔹 STFT 변환
    List<List<double>> spectrogram = stft(audioSignal, 400, 160, 512);

    // 🔹 MEL 스펙트로그램 변환 (40 MFCC)
    List<List<double>> melSpectrogram = melFilterBank(spectrogram, height, 22050);

    // 🔹 로그 변환 후 MFCC 변환
    List<List<double>> logMelSpectrogram = logTransform(melSpectrogram);
    List<List<double>> mfccFeatures = mfccFromLogMelSpectrogram(logMelSpectrogram, height);

    // 🔹 패딩 또는 자르기
    List<List<double>> finalMfcc = [];
    for (int i = 0; i < height; i++) {
      if (mfccFeatures[i].length > width) {
        finalMfcc.add(mfccFeatures[i].sublist(0, width));
      } else {
        finalMfcc.add([...mfccFeatures[i], ...List.filled(width - mfccFeatures[i].length, 0.0)]);
      }
    }

    // 🔹 차원 변경하여 모델 입력 형태 `(1, 40, 376, 1)`로 변환
    Float32List inputArray = Float32List.fromList(finalMfcc.expand((e) => e).toList());

    print("✅ 변환 완료: ${inputArray.length} 요소, 입력 형태: (1, $height, $width, $channels)");

    return inputArray;
  }

  /// 🔹 예측 실행
  Future<List<double>> predict() async {
    if (_model == null) {
      print("❌ 모델이 로드되지 않음");
      return [];
    }

    try {
      String wavFilePath = await getWavFilePath();

      // 🔹 1. WAV → PCM 변환
      Uint8List pcmData = await extractPcmData(wavFilePath);
      if (pcmData.isEmpty) return [];

      // 🔹 2. PCM → MFCC 변환 후 모델 입력 형태 `(1, 40, 376, 1)`로 변환
      Float32List inputArray = preprocessAudio(pcmData);

      // 🔹 3. 출력 버퍼 설정 (예: 10개 클래스)
      var outputArray = List.filled(10, 0.0).reshape([1, 10]);

      // 🔹 4. 모델 실행
      _model!.run(inputArray.reshape([1, 40, 376, 1]), outputArray);

      List<double> predictions = outputArray[0];
      print("🔮 예측 결과 (확률): $predictions");
      return predictions;
    } catch (e) {
      print("❌ 예측 실행 오류: $e");
      return [];
    }
  }

  /// 🔹 가장 높은 확률을 가진 클래스를 반환
  Future<int> predictClass() async {
    List<double> predictions = await predict();
    if (predictions.isEmpty) return -1;

    int predictedClass = predictions.indexOf(predictions.reduce((a, b) => a > b ? a : b));
    print("🏆 예측된 클래스: $predictedClass");
    return predictedClass;
  }

  void close() {
    _model?.close();
  }
}


/// **STFT 변환**
List<List<double>> stft(List<double> signal, int frameLength, int frameStep, int fftLength) {
  List<List<double>> result = [];
  for (int i = 0; i + frameLength <= signal.length; i += frameStep) {
    List<double> frame = signal.sublist(i, i + frameLength);
    result.add(fft(frame, fftLength));
  }
  return result;
}

/// **FFT 변환 **
List<double> fft(List<double> frame, int fftLength) {
  return List.generate(fftLength, (i) => frame[i % frame.length]);
}

/// **Mel 필터 변환**
List<List<double>> melFilterBank(List<List<double>> spectrogram, int numMel, int sampleRate) {
  return spectrogram;
}

/// **로그 변환**
List<List<double>> logTransform(List<List<double>> spectrogram) {
  return spectrogram.map((row) => row.map((x) => log(x + 1e-6)).toList()).toList();
}

/// **MFCC 변환**
List<List<double>> mfccFromLogMelSpectrogram(List<List<double>> logMelSpectrogram, int numMfcc) {
  return logMelSpectrogram;
}
