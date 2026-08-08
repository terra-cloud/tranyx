import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

import 'package:shared/shared.dart';

final imgBBServiceProvider = Provider<ImgUploadService>((ref) {
  return ImgUploadService();
});

class ImgUploadService {
  static String get _apiKey => Env.get('IMGBB_API_KEY', defaultValue: '50952d72f276ff20aa3362f346b134ab');
  static String get apiUrl {
    return "https://api.imgbb.com/1/upload?key=$_apiKey";
  }

  Future<String?> uploadImage(File file, {int? expiration}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      request.files.add(await http.MultipartFile.fromPath('image', file.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data']['url'] as String?;
      } else {
        debugPrint("ImgBB Upload failed: ${response.body}".toString());
        return null;
      }
    } catch (e) {
      debugPrint("Error uploading to ImgBB: $e".toString());
      return null;
    }
  }

  Future<String?> uploadFromBytes(
    Uint8List bytes, {
    int? expiration,
    String filename = 'upload.jpg',
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      if (expiration != null) {
        request.fields['expiration'] = expiration.toString();
      }

      request.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: filename),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data']['url'] as String?;
      } else {
        debugPrint("ImgBB Upload failed: ${response.body}".toString());
        return null;
      }
    } catch (e) {
      debugPrint("Error uploading bytes to ImgBB: $e".toString());
      return null;
    }
  }
}
