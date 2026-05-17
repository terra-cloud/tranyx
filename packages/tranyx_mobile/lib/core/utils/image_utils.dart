import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ImageUtils {
  static final ImagePicker _picker = ImagePicker();

  static Future<File?> pickAndProcessImage({
    required BuildContext context,
    required ImageSource source,
  }) async {
    // 1. Handle Permissions
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission denied')),
          );
        }
        return null;
      }
    } else {
      // For gallery, permission handling varies by OS version,
      // but usually image_picker handles it or we use photo permission.
      // if (Platform.isIOS) {
      //   final status = await Permission.photos.request();
      //   print("DD");
      //   if (!status.isGranted && !status.isLimited) return null;
      // }
    }

    // 2. Pick Image
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 80, // Initial quality reduction
    );

    if (pickedFile == null) return null;

    // 3. Crop Image
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Photo',
          toolbarColor: Colors.indigo,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop Profile Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (croppedFile == null) return null;

    // 4. Compress Image
    return await _compressImage(File(croppedFile.path));
  }

  static Future<File?> _compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final path = tempDir.path;
    final targetPath = p.join(
      path,
      "${DateTime.now().millisecondsSinceEpoch}_compressed.jpg",
    );

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
      format: CompressFormat.jpeg,
    );

    if (result == null) return file; // Return original if compression fails
    return File(result.path);
  }
}
