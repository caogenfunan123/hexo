import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import 'github_service.dart';

class ImageService {
  static const _channel = MethodChannel('hexo/native');
  final GitHubService github;

  ImageService(this.github);

  Future<Uint8List?> pickImageBytes() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('pickImage');
      if (result is Uint8List) return result;
      if (result is List) return Uint8List.fromList(result.cast<int>());
      if (result is String && result.isNotEmpty) {
        // base64
        return base64Decode(result);
      }
      if (result is Map) {
        final b64 = result['base64']?.toString();
        if (b64 != null && b64.isNotEmpty) return base64Decode(b64);
        final path = result['path']?.toString();
        if (path != null && path.isNotEmpty) {
          return await File(path).readAsBytes();
        }
      }
    } catch (e) {
      // fallback: try open document via channel returning path only
      rethrow;
    }
    return null;
  }

  /// 批量选择图片，返回字节列表
  Future<List<Uint8List>?> pickMultipleImageBytes() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('pickMultipleImages');
      if (result == null) return null;
      if (result is List) {
        final bytesList = <Uint8List>[];
        for (final item in result) {
          if (item is Uint8List) {
            bytesList.add(item);
          } else if (item is List<int>) {
            bytesList.add(Uint8List.fromList(item.cast<int>()));
          } else if (item is String && item.isNotEmpty) {
            bytesList.add(base64Decode(item));
          } else if (item is Map) {
            final b64 = item['base64']?.toString();
            if (b64 != null && b64.isNotEmpty) {
              bytesList.add(base64Decode(b64));
            } else {
              final path = item['path']?.toString();
              if (path != null && path.isNotEmpty) {
                bytesList.add(await File(path).readAsBytes());
              }
            }
          }
        }
        return bytesList.isNotEmpty ? bytesList : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> compressIfNeeded(
    Uint8List bytes,
    AppSettings settings,
  ) async {
    if (!settings.autoCompressImage) return bytes;
    try {
      // 根据 quality 计算目标宽度：quality 越低，缩放越激进
      final q = settings.compressQuality.clamp(10, 100);
      final baseWidth = settings.compressMaxWidth > 0
          ? settings.compressMaxWidth
          : 1600;
      // quality 70 以下按比例缩小宽度
      final effectiveWidth = q < 50
          ? (baseWidth * (0.5 + q / 100)).round()
          : q < 80
              ? (baseWidth * 0.8).round()
              : baseWidth;

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: effectiveWidth,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return bytes;
      final out = bd.buffer.asUint8List();
      // 如果重编码后更大且原图小于 2MB，保留原图
      if (out.lengthInBytes >= bytes.lengthInBytes && bytes.lengthInBytes < 2 * 1024 * 1024) {
        return bytes;
      }
      // 原图足够小则保留
      if (bytes.lengthInBytes <= 400 * 1024) return bytes;
      return out;
    } catch (_) {
      return bytes;
    }
  }

  /// 批量预处理图片（压缩、调整尺寸），返回预处理后的字节列表和统计信息
  Future<BatchPreprocessResult> preprocessImages(
    List<Uint8List> images,
    AppSettings settings, {
    void Function(int current, int total, int beforeKB, int afterKB)? onProgress,
  }) async {
    final processed = <Uint8List>[];
    int totalBefore = 0;
    int totalAfter = 0;
    final skipped = <int>[];

    for (var i = 0; i < images.length; i++) {
      final before = images[i].length;
      totalBefore += before;
      if (!settings.autoCompressImage) {
        processed.add(images[i]);
        totalAfter += before;
        skipped.add(i);
        continue;
      }
      try {
        final compressed = await compressIfNeeded(images[i], settings);
        final after = compressed.length;
        totalAfter += after;
        processed.add(compressed);
        onProgress?.call(i + 1, images.length, before ~/ 1024, after ~/ 1024);
      } catch (_) {
        processed.add(images[i]);
        totalAfter += before;
        skipped.add(i);
      }
    }

    final savedPercent = totalBefore > 0
        ? ((1 - totalAfter / totalBefore) * 100).toStringAsFixed(1)
        : '0.0';

    return BatchPreprocessResult(
      images: processed,
      totalBeforeBytes: totalBefore,
      totalAfterBytes: totalAfter,
      savedPercent: savedPercent,
      skippedCount: skipped.length,
    );
  }

  Future<String> uploadToImageBed(
    Uint8List bytes,
    AppSettings settings, {
    String? fileName,
    bool skipCompress = false,
  }) async {
    final name = fileName ??
        'img_${DateTime.now().millisecondsSinceEpoch}.png';
    final compressed = skipCompress ? bytes : await compressIfNeeded(bytes, settings);

    final token = settings.imageBedToken.isNotEmpty
        ? settings.imageBedToken
        : settings.effectiveGithubToken;
    if (token.isEmpty) throw Exception('请先配置图床 Token 或默认 GitHub Token');

    final owner = settings.imageBedOwner.isNotEmpty
        ? settings.imageBedOwner
        : '';
    final repo = settings.imageBedRepo;
    if (owner.isEmpty || repo.isEmpty) {
      throw Exception('请在设置中配置图床仓库 owner/repo');
    }
    final path =
        '${settings.imageBedPath.replaceAll(RegExp(r'/+$'), '')}/$name'
            .replaceAll(RegExp(r'^/+'), '');
    final rawUrl = await github.uploadBinary(
      token: token,
      owner: owner,
      repo: repo,
      branch: settings.imageBedBranch,
      path: path,
      bytes: compressed,
      message: 'chore: upload $name',
    );
    if (settings.imageBedCdn.isNotEmpty) {
      final cdn = settings.imageBedCdn.replaceAll(RegExp(r'/+$'), '');
      return '$cdn/$path';
    }
    // jsDelivr fallback
    return 'https://cdn.jsdelivr.net/gh/$owner/$repo@${settings.imageBedBranch}/$path';
  }

  String markdownImage(String url, {String alt = 'image'}) => '![$alt]($url)';

  /// 保存图片到本地项目目录（source/images/）
  /// 返回相对路径，如 images/2024-01-01-abc123.png
  Future<String> saveImageLocally(
    Uint8List bytes, {
    required String projectDir,
    String subDir = 'images',
    String? fileName,
  }) async {
    final dir = Directory('$projectDir/source/$subDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final name = fileName ?? '${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return '$subDir/$name';
  }
}

/// 批量预处理结果
class BatchPreprocessResult {
  final List<Uint8List> images;
  final int totalBeforeBytes;
  final int totalAfterBytes;
  final String savedPercent;
  final int skippedCount;

  const BatchPreprocessResult({
    required this.images,
    required this.totalBeforeBytes,
    required this.totalAfterBytes,
    required this.savedPercent,
    required this.skippedCount,
  });

  String get summary {
    final beforeKB = (totalBeforeBytes / 1024).toStringAsFixed(1);
    final afterKB = (totalAfterBytes / 1024).toStringAsFixed(1);
    if (skippedCount > 0) {
      return '$beforeKB KB → $afterKB KB (节省 $savedPercent%, $skippedCount 张跳过)';
    }
    return '$beforeKB KB → $afterKB KB (节省 $savedPercent%)';
  }
}
