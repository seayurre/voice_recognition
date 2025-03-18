//code inspired from https://velog.io/@yevvon/flutterdart-%EC%9D%8C%EC%84%B1-%EB%85%B9%EC%9D%8C-%EC%9E%AC%EC%83%9D

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart' as sound;
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

  Duration duration = Duration.zero; //총 시간
  Duration position = Duration.zero; //진행중인 시간

  //녹음에 필요한 것들
  final recorder = sound.FlutterSoundRecorder();
  bool isRecording = false; //녹음 상태
  String audioPath = ''; //녹음중단 시 경로 받아올 변수
  String playAudioPath = ''; //저장할때 받아올 변수 , 재생 시 필요

  //재생에 필요한 것들
  final AudioPlayer audioPlayer = AudioPlayer();
  bool isPlaying = false;

  @override
  void initState() {
    super.initState();
    playAudio();
    initRecorder();

    audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        isPlaying = state == PlayerState.playing;
      });
    });

    audioPlayer.onDurationChanged.listen((newDuration) {
      setState(() {
        duration = newDuration;
      });
    });

    audioPlayer.onPositionChanged.listen((newPosition) {
      setState(() {
        position = newPosition;
      });
    });
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Slider(
          min: 0,
          max: duration.inSeconds.toDouble(),
          value: position.inSeconds.toDouble(),
          onChanged: (value) async {
            setState(() {
              position = Duration(seconds: value.toInt());
            });
            await audioPlayer.seek(position);
          },
          activeColor: Colors.black,
          inactiveColor: Colors.grey,
        ),
        SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatTime(position), style: TextStyle(color: Colors.brown)),
              SizedBox(width: 20),
              CircleAvatar(
                radius: 15,
                backgroundColor: Colors.transparent,
                child: IconButton(
                  padding: EdgeInsets.only(bottom: 50),
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.brown,
                  ),
                  iconSize: 25,
                  onPressed: () async {
                    print("isplaying 전 : $isPlaying");
                    if (isPlaying) {
                      //재생중이면
                      await audioPlayer.pause(); //멈추고
                      setState(() {
                        isPlaying = false; //상태변경하기
                      });
                    } else {
                      //멈춘 상태였으면
                      await playAudio();
                      await audioPlayer.resume(); // 녹음된 오디오 재생
                    }
                  },
                ),
              ),
              SizedBox(width: 20),
              Text(formatTime(duration), style: TextStyle(color: Colors.brown)),
            ],
          ),
        ),
        SizedBox(height: 20),
        SizedBox(
          child: IconButton(
            onPressed: () async {
              if (recorder.isRecording) {
                print("stop() 호출됨");
                await stop();
              } else {
                print("record() 호출됨");
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
            ); //audiopath가 맞나?
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

  //recorder initialization
  Future initRecorder() async {
    final status = await Permission.microphone.request();

    if (status != PermissionStatus.granted) {
      throw "녹음 권한을 얻지 못했습니다.";
    }
    await recorder.openRecorder();

    isRecording = true;
    recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  Future record() async {
    await recorder.startRecorder(toFile: 'audio'); //codec 종류도 바꿀 수 있는 듯
  }

  Future<void> stop() async {
    final path = await recorder.stopRecorder();
    audioPath = path!;

    setState(() {
      isRecording = false;
    });
    print("stop called");

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

  String formatTime(Duration duration) {
    int minutes = duration.inMinutes.remainder(60);
    int seconds = duration.inSeconds.remainder(60);

    String result = '$minutes:${seconds.toString().padLeft(2, '0')}';
    return result;
  }

  Future<void> playAudio() async {
    try {
      if (isPlaying == PlayerState.playing) {
        await audioPlayer.stop(); // 이미 재생 중인 경우 정지시킵니다.
      }

      await audioPlayer.setSourceDeviceFile(playAudioPath);
      await Future.delayed(Duration(milliseconds: 500));

      setState(() {
        duration = duration;
        isPlaying = true;
      });

      audioPlayer.play;

      print('오디오 재생 시작: $playAudioPath');
      print("duration: $duration");
    } catch (e) {
      print("audioPath : $playAudioPath");
      print("오디오 재생 중 오류 발생 : $e");
    }
  }
}
