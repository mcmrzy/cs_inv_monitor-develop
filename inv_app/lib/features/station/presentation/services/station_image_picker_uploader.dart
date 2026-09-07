import 'dart:io';

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/station/data/station_image_upload_service.dart';

class StationImageUploadResult {
  const StationImageUploadResult({
    required this.file,
    required this.url,
  });

  final File file;
  final String url;
}

typedef StationImagePickerUploader = Future<StationImageUploadResult?>
    Function();

/// 选择、方形裁剪并上传电站卡片图。用户取消时返回 null。
Future<StationImageUploadResult?> pickCropAndUploadStationImage() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 85,
  );
  if (picked == null) return null;

  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    maxWidth: 1024,
    maxHeight: 1024,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 85,
    uiSettings: [
      AndroidUiSettings(
        cropStyle: CropStyle.rectangle,
        lockAspectRatio: true,
        initAspectRatio: CropAspectRatioPreset.square,
        hideBottomControls: true,
      ),
      IOSUiSettings(
        cropStyle: CropStyle.rectangle,
        aspectRatioLockEnabled: true,
        aspectRatioPresets: [CropAspectRatioPreset.square],
      ),
    ],
  );
  if (cropped == null) return null;

  final file = File(cropped.path);
  final uploadService = StationImageUploadService(getIt<ApiClient>());
  final url = await uploadService.uploadStationImage(file);
  return StationImageUploadResult(file: file, url: url);
}
