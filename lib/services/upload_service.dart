import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class UploadService {
  Future<void> uploadAudioFile(
    String filePath,
    String fileType,
    String situation,
  ) async {
    var uri = Uri.parse('http://143.248.135.44:5000/upload'); // Flask 서버 주소
    try {
      var request =
          http.MultipartRequest('POST', uri)
            ..fields['situation'] = situation
            ..files.add(
              await http.MultipartFile.fromPath(
                'file',
                filePath,
                contentType:
                    fileType == 'mp3'
                        ? MediaType('audio', 'mpeg') // MP3
                        : MediaType('audio', 'wav'), // WAV
              ),
            );

      var response = await request.send();
      if (response.statusCode == 200) {
        print('Upload successful');
      } else {
        print('Upload failed');
      }
    } catch (e) {
      print(e);
    }
  }
}
