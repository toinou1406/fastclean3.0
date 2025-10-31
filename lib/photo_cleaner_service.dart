
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'photo_analyzer.dart';


//##############################################################################
//# 1. ISOLATE DATA STRUCTURES & TOP-LEVEL FUNCTION
//##############################################################################

/// Wrapper containing all data returned from the background analysis isolate.
class IsolateAnalysisResult {
    final String assetId;
    final PhotoAnalysisResult analysis;

    IsolateAnalysisResult(this.assetId, this.analysis);
}

/// Top-level function executed in a separate isolate.
/// This function is the entry point for the background processing.
Future<IsolateAnalysisResult?> analyzePhotoInIsolate(String assetId) async {
    final AssetEntity? asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;

    // The PhotoManager sometimes fails to get the file. We must handle this.
    final File? file = await asset.file;
    if (file == null) return null;

    // The new analyzer performs all heavy lifting.
    final analyzer = PhotoAnalyzer();
    try {
        final analysisResult = await analyzer.analyze(file);
        return IsolateAnalysisResult(asset.id, analysisResult);
    } catch (e) {
        // If a single analysis fails, we don't want to crash the whole batch.
        // In a production app, you might log this error to a remote service.
        if (kDebugMode) {
            print("Failed to analyze asset $assetId: $e");
        }
        return null;
    }
}

//##############################################################################
//# 2. MAIN SERVICE & DATA MODELS
//##############################################################################

/// A unified class to hold the asset and its complete analysis result.
class PhotoResult {
  final AssetEntity asset;
  final PhotoAnalysisResult analysis;
  
  // For convenience, we expose the final score directly.
  double get score => analysis.finalScore;

  PhotoResult(this.asset, this.analysis);
}

class PhotoCleanerService {
  final DiskSpacePlus _diskSpace = DiskSpacePlus();
  final PhotoAnalyzer _analyzer = PhotoAnalyzer();
  final List<PhotoResult> _allPhotos = [];
  final Set<String> _seenPhotoIds = {};

  /// Scans all photos using a high-performance, batched background process.
  Future<void> scanPhotos() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      throw Exception('Full photo access permission is required.');
    }

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (albums.isEmpty) return;

    // Fetch all asset entities first (metadata only, very fast).
    List<AssetEntity> allAssets = [];
    for (final album in albums) {
        final assets = await album.getAssetListRange(start: 0, end: await album.assetCountAsync);
        allAssets.addAll(assets);
    }
    final uniqueAssetIds = allAssets.map((a) => a.id).toSet().toList();

    _allPhotos.clear();
    _seenPhotoIds.clear();

    // Create a list of analysis futures to run in isolates.
    final analysisFutures = uniqueAssetIds.map((id) => compute(analyzePhotoInIsolate, id)).toList();

    // --- BATCH PROCESSING --- 
    // This is critical for performance and memory management.
    final List<IsolateAnalysisResult> analysisResults = [];
    const batchSize = 50; // Process 50 photos at a time.

    for (int i = 0; i < analysisFutures.length; i += batchSize) {
        final end = (i + batchSize > analysisFutures.length) ? analysisFutures.length : i + batchSize;
        final batch = analysisFutures.sublist(i, end);
        final batchResults = await Future.wait(batch);
        analysisResults.addAll(batchResults.whereType<IsolateAnalysisResult>());
        
        // Optional: Provide progress updates to the UI here.
    }

    // Create a quick lookup map for assets by ID.
    final Map<String, AssetEntity> assetMap = {for (var asset in allAssets) asset.id: asset};

    // Populate the final list of results.
    _allPhotos.addAll(
        analysisResults.map((r) => PhotoResult(assetMap[r.assetId]!, r.analysis))
    );
  }

  /// ##########################################################################
  /// # NEW SELECTION ALGORITHM
  /// ##########################################################################
  Future<List<PhotoResult>> selectPhotosToDelete({List<String> excludedIds = const []}) async {
    List<PhotoResult> candidates = _allPhotos
        .where((p) => !excludedIds.contains(p.asset.id) && !_seenPhotoIds.contains(p.asset.id))
        .toList();

    final Set<String> markedForDeletion = {};

    // --- Step 1: Mark Exact Duplicates (using MD5 Hash) ---
    final md5Groups = <String, List<PhotoResult>>{};
    for (final photo in candidates) {
      md5Groups.putIfAbsent(photo.analysis.md5Hash, () => []).add(photo);
    }
    for (final group in md5Groups.values) {
      if (group.length > 1) {
        group.sort((a, b) => a.asset.createDateTime.compareTo(b.asset.createDateTime));
        // Mark all but the first (oldest) one for deletion.
        markedForDeletion.addAll(group.skip(1).map((p) => p.asset.id));
      }
    }

    // --- Step 2: Mark Similar Photos (using pHash) ---
    // This is O(n^2), but we only compare photos not already marked.
    List<PhotoResult> remainingCandidates = candidates.where((p) => !markedForDeletion.contains(p.asset.id)).toList();
    for (int i = 0; i < remainingCandidates.length; i++) {
        for (int j = i + 1; j < remainingCandidates.length; j++) {
            final p1 = remainingCandidates[i];
            final p2 = remainingCandidates[j];
            
            // Avoid re-comparing already processed pairs.
            if (markedForDeletion.contains(p1.asset.id) || markedForDeletion.contains(p2.asset.id)) continue;

            final distance = _analyzer.hammingDistance(p1.analysis.pHash, p2.analysis.pHash);

            // Threshold of < 10 is a good starting point for "very similar".
            if (distance < 10) {
                // Mark the photo with the *worse* (higher) score for deletion.
                if (p1.score >= p2.score) {
                    markedForDeletion.add(p1.asset.id);
                } else {
                    markedForDeletion.add(p2.asset.id);
                }
            }
        }
    }

    // --- Step 3: Combine and Sort ---
    List<PhotoResult> finalDeletionList = candidates.where((p) => markedForDeletion.contains(p.asset.id)).toList();

    // --- Step 4: Fill remaining slots with the highest-scoring (worst) photos ---
    int remainingSlots = 9 - finalDeletionList.length;
    if (remainingSlots > 0) {
        List<PhotoResult> otherBadPhotos = candidates
            .where((p) => !markedForDeletion.contains(p.asset.id))
            .toList();
        otherBadPhotos.sort((a, b) => b.score.compareTo(a.score));
        finalDeletionList.addAll(otherBadPhotos.take(remainingSlots));
    }

    // Final sort to show the absolute worst ones first.
    finalDeletionList.sort((a,b) => b.score.compareTo(a.score));
    
    final selected = finalDeletionList.take(9).toList();
    _seenPhotoIds.addAll(selected.map((p) => p.asset.id));
    
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
    
    final int totalSpace = (total * 1024 * 1024).toInt();
    final int usedSpace = ((total - free) * 1024 * 1024).toInt();

    return StorageInfo(
      totalSpace: totalSpace,
      usedSpace: usedSpace,
    );
  }
}

//##############################################################################
//# 3. UTILITY CLASSES
//##############################################################################

class StorageInfo {
  final int totalSpace;
  final int usedSpace;

  StorageInfo({required this.totalSpace, required this.usedSpace});

  double get usedPercentage => totalSpace > 0 ? (usedSpace / totalSpace) * 100 : 0;
  String get usedSpaceGB => (usedSpace / 1073741824).toStringAsFixed(1);
  String get totalSpaceGB => (totalSpace / 1073741824).toStringAsFixed(0);
}
