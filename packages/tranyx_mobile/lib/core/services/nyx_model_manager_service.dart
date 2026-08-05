import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum NyxModelStage {
  notDownloaded,
  downloading,
  ready,
  error,
}

class NyxModelStatus {
  final NyxModelStage stage;
  final double progress; // 0.0 to 1.0
  final int downloadedBytes;
  final int totalBytes;
  final String? errorMessage;
  final String? modelPath;

  const NyxModelStatus({
    required this.stage,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.modelPath,
  });

  bool get isReady => stage == NyxModelStage.ready;
  bool get isDownloading => stage == NyxModelStage.downloading;

  NyxModelStatus copyWith({
    NyxModelStage? stage,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
    String? modelPath,
  }) {
    return NyxModelStatus(
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      modelPath: modelPath ?? this.modelPath,
    );
  }
}

class NyxModelManagerNotifier extends Notifier<NyxModelStatus> {
  static const int _ggufMagicHeader = 0x46554747;
  http.Client? _downloadClient;
  bool _isAutoStarted = false;

  @override
  NyxModelStatus build() {
    checkModelStatus();
    return const NyxModelStatus(stage: NyxModelStage.notDownloaded);
  }

  /// Checks if GGUF model binary exists and passes header verification
  Future<bool> checkModelStatus() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final targetFile = File('${docDir.path}/model.gguf');

      final candidatePaths = [
        targetFile.path,
        '${docDir.path}/Llama-3-7B-Instruct-Q4_K_M.gguf',
        '/sdcard/Download/model.gguf',
        '/sdcard/Download/Llama-3-7B-Instruct-Q4_K_M.gguf',
        '/storage/emulated/0/Download/model.gguf',
      ];

      for (final path in candidatePaths) {
        final f = File(path);
        if (await _verifyGgufHeader(f)) {
          state = NyxModelStatus(
            stage: NyxModelStage.ready,
            progress: 1.0,
            modelPath: f.path,
          );
          return true;
        }
      }

      state = const NyxModelStatus(stage: NyxModelStage.notDownloaded);
      return false;
    } catch (e) {
      state = NyxModelStatus(
        stage: NyxModelStage.notDownloaded,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Verifies GGUF magic header
  Future<bool> _verifyGgufHeader(File file) async {
    try {
      if (!file.existsSync()) return false;
      final handle = await file.open(mode: FileMode.read);
      final bytes = await handle.read(4);
      await handle.close();

      if (bytes.length < 4) return false;
      final header = ByteData.sublistView(bytes).getUint32(0, Endian.little);
      return header == _ggufMagicHeader;
    } catch (_) {
      return false;
    }
  }

  /// Auto-checks status on splash / app launch and initiates background download if not downloaded
  Future<void> autoStartBackgroundDownload({String? customUrl}) async {
    if (_isAutoStarted) return;
    _isAutoStarted = true;

    final isReady = await checkModelStatus();
    if (!isReady) {
      debugPrint('NyxModelManager: Auto-starting background model download on first load...');
      startDownload(customUrl: customUrl);
    }
  }

  /// Downloads GGUF model binary in background with real-time stream progress updates
  Future<void> startDownload({String? customUrl}) async {
    if (state.isDownloading || state.isReady) return;

    final defaultUrl = customUrl ??
        'https://huggingface.co/lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf';

    state = const NyxModelStatus(
      stage: NyxModelStage.downloading,
      progress: 0.01,
    );

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final tempFile = File('${docDir.path}/model.gguf.tmp');
      final finalFile = File('${docDir.path}/model.gguf');

      _downloadClient = http.Client();
      final request = http.Request('GET', Uri.parse(defaultUrl));
      final response = await _downloadClient!.send(request);

      if (response.statusCode != 200) {
        state = NyxModelStatus(
          stage: NyxModelStage.error,
          errorMessage: 'Server returned HTTP ${response.statusCode}',
        );
        return;
      }

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;

        final double prog = contentLength > 0
            ? (downloaded / contentLength).clamp(0.0, 1.0)
            : 0.5;

        state = NyxModelStatus(
          stage: NyxModelStage.downloading,
          progress: prog,
          downloadedBytes: downloaded,
          totalBytes: contentLength,
        );
      }

      await sink.close();

      // Rename temp file to final file
      if (tempFile.existsSync()) {
        if (finalFile.existsSync()) await finalFile.delete();
        await tempFile.rename(finalFile.path);
      }

      if (await _verifyGgufHeader(finalFile)) {
        state = NyxModelStatus(
          stage: NyxModelStage.ready,
          progress: 1.0,
          downloadedBytes: downloaded,
          totalBytes: downloaded,
          modelPath: finalFile.path,
        );
        debugPrint('NyxModelManager: Background GGUF model download complete & verified!');
      } else {
        state = const NyxModelStatus(
          stage: NyxModelStage.error,
          errorMessage: 'Downloaded model file failed GGUF header verification.',
        );
      }
    } catch (e) {
      debugPrint('NyxModelManager download error: $e');
      state = NyxModelStatus(
        stage: NyxModelStage.error,
        errorMessage: 'Download failed: $e',
      );
    } finally {
      _downloadClient?.close();
      _downloadClient = null;
    }
  }

  /// Cancels ongoing download
  void cancelDownload() {
    _downloadClient?.close();
    _downloadClient = null;
    state = const NyxModelStatus(stage: NyxModelStage.notDownloaded);
  }
}

final nyxModelStatusProvider =
    NotifierProvider<NyxModelManagerNotifier, NyxModelStatus>(
  NyxModelManagerNotifier.new,
);
