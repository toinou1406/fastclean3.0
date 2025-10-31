import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'photo_analyzer.dart';

// --- Isolate Data Structures ---

/// Input data for the background analysis isolate.
class AnalysisInput {
  final String assetId;
  AnalysisInput(this.assetId);
}

/// Result data from the background analysis isolate.
class AnalysisResult {
  final String id;
  final double score;
  final String hash;
  final String perceptualHash;

  AnalysisResult({
    required this.id,
    required this.score,
    required this.hash,
    required this.perceptualHash,
  });
}

/// Top-level function to be executed in a separate isolate for photo analysis.
/// This prevents the UI from freezing during heavy computation.
Future<AnalysisResult?> analyzePhotoInIsolate(AnalysisInput input) async {
  final analyzer = PhotoAnalyzer();
  // Note: The try-catch block is removed here. The 'compute' function will
  // automatically propagate any exception to the Future on the main thread.
  final AssetEntity? asset = await AssetEntity.fromId(input.assetId);
  if (asset == null) return null;

  final File? file = await asset.file;
  if (file == null) return null;

  final score = await analyzer.analyzePhoto(file, asset.createDateTime);
  final hash = await analyzer.calculateHash(file);
  final pHash = await analyzer.calculatePerceptualHash(file);

  return AnalysisResult(
    id: asset.id,
    score: score,
    hash: hash,
    perceptualHash: pHash,
  );
}

// --- Main Service ---

class PhotoResult {
  final AssetEntity asset;
  final double score;
  final String hash;
  final String perceptualHash;

  PhotoResult(this.asset, this.score, this.hash, this.perceptualHash);
}

class PhotoCleanerService {
  final DiskSpacePlus _diskSpace = DiskSpacePlus();
  final List<PhotoResult> _allPhotos = [];
  final Set<String> _seenPhotoIds = {};

  /// Scans all photos from all albums in the background without blocking the UI.
  Future<void> scanPhotos() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      throw Exception('Full photo access permission is required to scan photos.');
    }

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (albums.isEmpty) return;

    List<AssetEntity> allAssets = [];
    for (final album in albums) {
      final List<AssetEntity> assets = await album.getAssetListRange(start: 0, end: await album.assetCountAsync);
      allAssets.addAll(assets);
    }
    
    // Remove duplicates by ID, in case albums overlap
    allAssets = allAssets.toSet().toList();
    
    _allPhotos.clear();
    _seenPhotoIds.clear();

    // Create a list of futures for the isolate computations
    final List<Future<AnalysisResult?>> analysisFutures = allAssets
        .map((asset) => compute(analyzePhotoInIsolate, AnalysisInput(asset.id)))
        .toList();

    // Process futures in batches to avoid overwhelming the system
    final List<AnalysisResult> analysisResults = [];
    const batchSize = 50;
    for (var i = 0; i < analysisFutures.length; i += batchSize) {
      final batch = analysisFutures.skip(i).take(batchSize);
      final batchResults = await Future.wait(batch);
      analysisResults.addAll(batchResults.whereType<AnalysisResult>());
    }

    final Map<String, AssetEntity> assetMap = {for (var asset in allAssets) asset.id: asset};

    _allPhotos.addAll(
      analysisResults.map((r) {
        return PhotoResult(assetMap[r.id]!, r.score, r.hash, r.perceptualHash);
      })
    );
  }

  /// Selects the worst photos to delete based on a scoring algorithm.
  Future<List<PhotoResult>> selectPhotosToDelete({List<String> excludedIds = const []}) async {
    List<PhotoResult> candidates = _allPhotos
        .where((p) => !excludedIds.contains(p.asset.id) && !_seenPhotoIds.contains(p.asset.id))
        .toList();

    // 1. MARK EXACT DUPLICATES (MD5 hash)
    Map<String, List<PhotoResult>> hashGroups = {};
    for (var photo in candidates) {
      hashGroups.putIfAbsent(photo.hash, () => []).add(photo);
    }

    List<PhotoResult> scoredCandidates = [];
    for (var group in hashGroups.values) {
      if (group.length > 1) {
        group.sort((a, b) => a.asset.createDateTime.compareTo(b.asset.createDateTime));
        scoredCandidates.add(group.first); // Keep the oldest
        for (int i = 1; i < group.length; i++) {
          scoredCandidates.add(PhotoResult(group[i].asset, 110.0, group[i].hash, group[i].perceptualHash)); // High score for duplicates
        }
      } else {
        scoredCandidates.add(group.first);
      }
    }
    
    candidates = scoredCandidates;

    // 2. DETECT SIMILAR PHOTOS (perceptual hash)
    for (int i = 0; i < candidates.length; i++) {
      for (int j = i + 1; j < candidates.length; j++) {
        final pHash1 = candidates[i].perceptualHash;
        final pHash2 = candidates[j].perceptualHash;
        
        if (pHash1.isEmpty || pHash2.isEmpty) continue;

        final distance = PhotoAnalyzer().hammingDistance(pHash1, pHash2);

        if (distance < 5) { // Very similar
          PhotoResult photoToBoost;
          if (candidates[i].score >= candidates[j].score) {
             photoToBoost = candidates[i];
          } else {
             photoToBoost = candidates[j];
          }
           final boostedScore = photoToBoost.score + 50.0;
           final indexToUpdate = candidates.indexWhere((p) => p.asset.id == photoToBoost.asset.id);
           if (indexToUpdate != -1) {
             candidates[indexToUpdate] = PhotoResult(photoToBoost.asset, boostedScore, photoToBoost.hash, photoToBoost.perceptualHash);
           }
        }
      }
    }

    // 3. SORT BY SCORE AND RETURN THE 9 WORST
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final selected = candidates.take(9).toList();
    for (var photo in selected) {
      _seenPhotoIds.add(photo.asset.id);
    }
    return selected;
  }

  /// Deletes the selected photos from the device.
  Future<void> deletePhotos(List<PhotoResult> photos) async {
    if (photos.isEmpty) return;
    final ids = photos.map((p) => p.asset.id).toList();
    await PhotoManager.editor.deleteWithIds(ids);
  }

  /// Gets storage information from the device.
  Future<StorageInfo> getStorageInfo() async {
    final double total = await _diskSpace.getTotalDiskSpace ?? 0.0;
    final double free = await _diskSpace.getFreeDiskSpace ?? 0.0;
    
    // The plugin returns space in MB, convert to bytes for consistency
    final int totalSpace = (total * 1024 * 1024).toInt();
    final int usedSpace = ((total - free) * 1024 * 1024).toInt();

    return StorageInfo(
      totalSpace: totalSpace,
      usedSpace: usedSpace,
    );
  }
}

class StorageInfo {
  final int totalSpace;
  final int usedSpace;

  StorageInfo({required this.totalSpace, required this.usedSpace});

  double get usedPercentage => totalSpace > 0 ? (usedSpace / totalSpace) * 100 : 0;
  String get usedSpaceGB => (usedSpace / 1073741824).toStringAsFixed(1);
  String get totalSpaceGB => (totalSpace / 1073741824).toStringAsFixed(0);
}
