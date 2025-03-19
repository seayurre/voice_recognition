//code inspired from https://velog.io/@yevvon/flutterdart-%EC%9D%8C%EC%84%B1-%EB%85%B9%EC%9D%8C-%EC%9E%AC%EC%83%9D

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart' as sound;
import 'package:noise_meter/noise_meter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:voice_recognition/services/upload_service.dart';

enum SelectedSituation { calibration, motionGeneration, viewMotion }

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

  //noise meter 패키지에서 필요한 것들 (from example code)
  NoiseReading? _latestReading;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  NoiseMeter? noiseMeter;

  @override
  void initState() {
    super.initState();
    initRecorder();
    noiseMeterStart();
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    noiseMeterStop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          child: IconButton(
            onPressed: () async {
              if (recorder.isRecording) {
                await stop();
              } else {
                await record();
              }
              setState(() {});
            },
            icon: Icon(
              recorder.isRecording ? Icons.stop : Icons.mic,
              size: 30,
              color: Colors.black,
            ),
          ),
        ),
        Container(
          margin: EdgeInsets.only(top: 20),
          child: Text(
            isRecording ? "Mic: ON" : "Mic: OFF",
            style: TextStyle(fontSize: 25, color: Colors.blue),
          ),
        ),
        Container(
          margin: EdgeInsets.only(top: 20),
          child: Text(
            'Noise: ${_latestReading?.meanDecibel.toStringAsFixed(2)} dB',
          ),
        ),
        Text('Max: ${_latestReading?.maxDecibel.toStringAsFixed(2)} dB'),

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
        GestureDetector(
          onTap: () async {
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
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 40),
            child: Text('Send Audio'),
          ),
        ),
      ],
    );
  }

  void onData(NoiseReading noiseReading) async {
    if (!isRecording && noiseReading.meanDecibel > 60) {
      await record();
    }
    if (isRecording && noiseReading.meanDecibel < 50) {
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
    }
    setState(() {
      _latestReading = noiseReading;
    });
  }

  void onError(Object error) {
    print(error);
    stop();
  }

  Future<bool> checkPermission() async => await Permission.microphone.isGranted;

  Future<void> requestPermission() async =>
      await Permission.microphone.request();

  //record 관련 함수들
  //recorder initialization
  Future initRecorder() async {
    if (!(await checkPermission())) await requestPermission();
    await recorder.openRecorder();

    isRecording = true;
    recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  Future<void> noiseMeterStart() async {
    noiseMeter ??= NoiseMeter();
    if (!(await checkPermission())) await requestPermission();
    _noiseSubscription = noiseMeter?.noise.listen(onData, onError: onError);
    setState(() => isRecording = true);
  }

  void noiseMeterStop() {
    _noiseSubscription?.cancel();
    setState(() => isRecording = false);
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
