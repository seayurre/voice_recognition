// Recorder
// NoiseMeter
// SpeechToText

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart' as sound;
import 'package:noise_meter/noise_meter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:porcupine_flutter/porcupine.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:voice_recognition/services/upload_service.dart';

enum SelectedSituation { calibration, motionGeneration, viewMotion }

const WAKE_WORD = "가나다라";
const PORCUPINE_ACCESS_KEY =
    "GQukfKf1TefwCCBynTFATbYrW7LTJyg6FAveMQ0opj8Prmi6iyrATA==";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SelectedSituation? _selectedSituation =
      SelectedSituation.calibration; //라디오 버튼 값

  //녹음에 필요한 것들
  final recorder = sound.FlutterSoundRecorder();
  bool isRecording = false; //녹음 상태
  String audioPath = ''; //녹음중단 시 경로 받아올 변수
  String playAudioPath = ''; //저장할때 받아올 변수 , 재생 시 필요

  //Porcupine
  late PorcupineManager _porcupineManager;

  //noise meter 패키지에서 필요한 것들 (from example code)
  NoiseReading? _latestReading;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  NoiseMeter? noiseMeter;

  DateTime? _belowThresholdStart;

  @override
  void initState() {
    super.initState();
    initRecorder();
    initPorcupine();
    noiseMeterStart();
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    stopPorcupine();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 10),

        //recorder가 켜져 있는지 아닌지 알려주는 것
        Container(
          margin: EdgeInsets.only(top: 20),
          height: 80,
          width: double.infinity,
          color: isRecording ? Colors.red : Colors.blue,
        ),
        Container(
          margin: EdgeInsets.only(top: 20),
          child: Text(
            'Noise: ${_latestReading?.meanDecibel.toStringAsFixed(2)} dB',
          ),
        ),

        //radio buttons
        ListTile(
          title: Text('Calibration'),
          leading: Radio<SelectedSituation>(
            groupValue: _selectedSituation,
            value: SelectedSituation.calibration,
            onChanged: (SelectedSituation? value) {
              setState(() {
                _selectedSituation = value;
              });
            },
          ),
        ),

        ListTile(
          title: Text('Motion Generation'),
          leading: Radio<SelectedSituation>(
            groupValue: _selectedSituation,
            value: SelectedSituation.motionGeneration,
            onChanged: (SelectedSituation? value) {
              setState(() {
                _selectedSituation = value;
              });
            },
          ),
        ),
        ListTile(
          title: Text('View Motion'),
          leading: Radio<SelectedSituation>(
            groupValue: _selectedSituation,
            value: SelectedSituation.viewMotion,
            onChanged: (SelectedSituation? value) {
              setState(() {
                _selectedSituation = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Future<bool> checkPermission() async => await Permission.microphone.isGranted;

  Future<void> requestPermission() async =>
      await Permission.microphone.request();

  Future initRecorder() async {
    if (!(await checkPermission())) await requestPermission();
    await recorder.openRecorder();

    recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  void initPorcupine() async {
    await createPorcupineManager();
    await _porcupineManager.start();
  }

  void stopPorcupine() async {
    await _porcupineManager.stop();
    await _porcupineManager.delete();
  }

  Future<void> createPorcupineManager() async {
    try {
      _porcupineManager = await PorcupineManager.fromBuiltInKeywords(
        PORCUPINE_ACCESS_KEY,
        [BuiltInKeyword.ALEXA],
        _wakeWordCallback,
      );
    } on PorcupineException catch (err) {
      print(err);
      print("=========An Error Occured========");
    }
  }

  void _wakeWordCallback(int keywordIndex) async {
    if (keywordIndex == 0) {
      // porcupine detected
      await record();
    } else {
      print("뭔가 잘못됐다");
    }
  }

  void onNoiseMeterData(NoiseReading noiseReading) async {
    if (isRecording && noiseReading.meanDecibel < 50) {
      if (_belowThresholdStart == null) {
        _belowThresholdStart = DateTime.now();
      } else {
        final duration = DateTime.now().difference(_belowThresholdStart!);
        if (duration >= const Duration(seconds: 1)) {
          await stop();
          UploadService uploadService = UploadService();
          await uploadService.uploadAudioFile(
            audioPath,
            'mp3',
            _selectedSituation == SelectedSituation.calibration
                ? "calibration"
                : _selectedSituation == SelectedSituation.motionGeneration
                ? "motionGeneration"
                : "viewMotion",
          );
          _belowThresholdStart = null;
        }
      }
    } else {
      _belowThresholdStart = null;
    }
    setState(() {
      _latestReading = noiseReading;
    });
  }

  void onNoiseMeterError(Object error) {
    print(error);
    stop();
  }

  Future<void> noiseMeterStart() async {
    noiseMeter ??= NoiseMeter();
    if (!(await checkPermission())) await requestPermission();
    _noiseSubscription = noiseMeter?.noise.listen(
      onNoiseMeterData,
      onError: onNoiseMeterError,
    );
  }

  void noiseMeterStop() {
    _noiseSubscription?.cancel();
  }

  Future<void> record() async {
    if (!(await checkPermission())) await requestPermission();
    await recorder.startRecorder(toFile: 'audio'); //codec 종류도 바꿀 수 있는 듯
    setState(() => isRecording = true);
  }

  Future<void> stop() async {
    final path = await recorder.stopRecorder();
    audioPath = path!;

    setState(() {
      isRecording = false;
    });

    final savedFilePath = await saveRecordingLocally();
    print("savedFilePath: $savedFilePath");
  }

  Future<String> saveRecordingLocally() async {
    if (audioPath.isEmpty) {
      return '';
    }
    // 녹음된 오디오 경로가 비어있으면 빈 문자열 반환

    final audioFile = File(audioPath);
    if (!audioFile.existsSync()) {
      return '';
    }
    // 파일이 존재하지 않으면 빈 문자열 반환

    try {
      final directory = await getApplicationDocumentsDirectory();
      final newPath = p.join(directory.path, 'recordings');
      // recordings 디렉터리 생성

      final newFile = File(p.join(newPath, 'audio.mp3'));
      // 여기서 'audio.mp3'는 파일명을 나타냄. 필요에 따라 변경 가능

      if (!(await newFile.parent.exists())) {
        await newFile.parent.create(recursive: true);
        // recordings 디렉터리가 없으면 생성
      }

      await audioFile.copy(newFile.path); // 기존 파일을 새로운 위치로 복사

      playAudioPath = newFile.path;

      return newFile.path; // 새로운 파일의 경로 반환
    } catch (e) {
      print('Error saving recording: $e');
      return ''; // 오류 발생 시 빈 문자열 반환
    }
  }
}
