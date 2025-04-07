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
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:voice_recognition/services/upload_service.dart';

enum SelectedSituation { calibration, motionGeneration, viewMotion }

const WAKE_WORD = "가나다라";

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
  bool isNoiseMeterRecording = false;

  //speech_to_text 패키지에서 필요한 것들
  final SpeechToText _speechToText = SpeechToText(); //SpeechToText Object
  bool _sttEnabled = false;
  String _sttText = '';

  @override
  void initState() {
    super.initState();
    //initRecorder();
    _initSTT();
    //noiseMeterStart();
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    noiseMeterStop();
    _stopSTT();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 10),
        // TextButton(
        //   onPressed: () async {
        //     if (isNoiseMeterRecording) {
        //       noiseMeterStop();
        //     } else {
        //       await noiseMeterStart();
        //     }
        //     setState(() {});
        //   },
        //   child: Container(
        //     padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        //     child: Text(
        //       isNoiseMeterRecording ? 'Recording Off' : 'Recording On',
        //       style: TextStyle(fontSize: 20),
        //     ),
        //   ),
        // ),

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
            if (_speechToText.isNotListening) {
              await _startSTT();
            } else {
              _stopSTT();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 40),
            child: Text(
              _speechToText.isNotListening ? 'Start STT' : 'Stop STT',
            ),
          ),
        ),
        SizedBox(height: 16),
        Text('stt word: $_sttText'),
      ],
    );
  }

  void noiseMeterOnData(NoiseReading noiseReading) async {
    setState(() {
      _latestReading = noiseReading;
    });
    if (isRecording && noiseReading.meanDecibel < 50) {
      await Future.delayed(Duration(milliseconds: 2000));
      //recorder 정지 및 파일 전송
      final path = await recorder.stopRecorder();
      audioPath = path!;

      setState(() {
        isRecording = false;
      });

      final savedFilePath = await saveRecordingLocally();
      print("savedFilePath: $savedFilePath");
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
      noiseMeterStop();
    }
    setState(() {});
  }

  void onError(Object error) {
    print(error);
  }

  Future<bool> checkPermission() async => await Permission.microphone.isGranted;

  Future<void> requestPermission() async =>
      await Permission.microphone.request();

  Future initRecorder() async {
    if (!(await checkPermission())) await requestPermission();
    await recorder.openRecorder();

    recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  Future<void> noiseMeterStart() async {
    noiseMeter ??= NoiseMeter();
    if (!(await checkPermission())) await requestPermission();
    _noiseSubscription = noiseMeter?.noise.listen(
      noiseMeterOnData,
      onError: onError,
    );
    setState(() => isNoiseMeterRecording = true);
  }

  void noiseMeterStop() {
    _noiseSubscription?.cancel();
    setState(() => isNoiseMeterRecording = false);
  }

  void _initSTT() async {
    if (!(await checkPermission())) await requestPermission();
    _sttEnabled = await _speechToText.initialize(
      onError: errorListener,
      onStatus: statusListener,
    );
    print('Speech enabled: $_sttEnabled');
    setState(() {});
  }

  Future _startSTT() async {
    debugPrint("========================debug print=====================");
    await _speechToText.listen(
      listenFor: Duration(seconds: 10),
      onResult: _onSpeechResult,
      localeId: 'ko_KR',
      listenOptions: SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    setState(() {
      _sttEnabled = true;
    });
  }

  void _stopSTT() async {
    await _speechToText.stop();
    print('stop STT');
    setState(() {
      _sttEnabled = false;
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) async {
    print('-------speech result--------');
    print(result.recognizedWords);
    setState(() {
      _sttText = result.recognizedWords;
    });
    // if (result.recognizedWords == WAKE_WORD) {
    //   //완전히 동일하긴 어려우니 어느 정도 relaxation을 두어야 하는데...
    //   print("으으아아ㅓㄻ나ㅣ어라ㅣㅁ너");
    //   _stopSTT();
    //   await recorder.startRecorder(toFile: 'audio');
    //   noiseMeterStart();
    //   setState(() => isRecording = true);
    // }
  }

  void errorListener(SpeechRecognitionError error) async {
    debugPrint(error.errorMsg.toString());
    await Future.delayed(Duration(milliseconds: 500));
  }

  void statusListener(String status) async {
    debugPrint("status $status");
    if (status == "done" && _sttEnabled) {
      //done이면 다시 시작
      setState(() {
        _sttText = "";
        _sttEnabled = false;
      });
      await _startSTT();
    }
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
