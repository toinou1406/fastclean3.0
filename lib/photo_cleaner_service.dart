import 'package:photo_manager/photo_manager.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'photo_analyzer.dart';

class PhotoResult {
  final AssetEntity asset;
  final double score;
  final String hash;
  final String perceptualHash;

  PhotoResult(this.asset, this.score, this.hash, this.perceptualHash);
}

class PhotoCleanerService {
  final PhotoAnalyzer _analyzer = PhotoAnalyzer();
  final DiskSpacePlus _diskSpace = DiskSpacePlus();
  final List<PhotoResult> _allPhotos = [];
  final Set<String> _seenPhotoIds = {};

  // SCANNER TOUTES LES PHOTOS
  Future<void> scanPhotos() async {
    // Demander permission
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      throw Exception('Permission refusée');
    }

    // Récupérer toutes les photos
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    if (albums.isEmpty) return;

    final recentAlbum = albums.first;
    final photos = await recentAlbum.getAssetListRange(
      start: 0,
      end: 10000, // Maximum 10k photos
    );

    _allPhotos.clear();

    // Analyser chaque photo (en parallèle par batch de 10)
    for (int i = 0; i < photos.length; i += 10) {
      final batch = photos.skip(i).take(10).toList();
      final results = await Future.wait(
        batch.map((photo) => _analyzePhoto(photo))
      );
      _allPhotos.addAll(results.whereType<PhotoResult>());
    }
  }

  Future<PhotoResult?> _analyzePhoto(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file == null) return null;

      // Analyser la photo
      final score = await _analyzer.analyzePhoto(file, asset.createDateTime);
      final hash = await _analyzer.calculateHash(file);
      final pHash = await _analyzer.calculatePerceptualHash(file);

      return PhotoResult(asset, score, hash, pHash);
    } catch (e) {
      // Gérer l'erreur silencieusement
      return null;
    }
  }

  // SÉLECTIONNER LES 9 PHOTOS À SUPPRIMER
  Future<List<PhotoResult>> selectPhotosToDelete({List<String> excludedIds = const []}) async {
    List<PhotoResult> candidates = _allPhotos
        .where((p) => !excludedIds.contains(p.asset.id) && !_seenPhotoIds.contains(p.asset.id))
        .toList();

    // 1. MARQUER LES DOUBLONS EXACTS (hash MD5 identique)
    Map<String, List<PhotoResult>> hashGroups = {};
    for (var photo in candidates) {
      hashGroups.putIfAbsent(photo.hash, () => []).add(photo);
    }

    for (var group in hashGroups.values) {
      if (group.length > 1) {
        // Garder la première, marquer les autres comme doublons
        for (int i = 1; i < group.length; i++) {
          group[i] = PhotoResult(
            group[i].asset,
            100.0, // Score maximum pour doublon
            group[i].hash,
            group[i].perceptualHash,
          );
        }
      }
    }

    // 2. DÉTECTER LES PHOTOS SIMILAIRES (pHash proche)
    for (int i = 0; i < candidates.length; i++) {
      for (int j = i + 1; j < candidates.length; j++) {
        final distance = _analyzer.hammingDistance(
          candidates[i].perceptualHash,
          candidates[j].perceptualHash,
        );

        // Si très similaires (distance < 5 bits)
        if (distance < 5) {
          // Augmenter le score de celle qui a déjà le score le plus élevé
          if (candidates[i].score >= candidates[j].score) {
            candidates[i] = PhotoResult(
              candidates[i].asset,
              candidates[i].score + 80.0,
              candidates[i].hash,
              candidates[i].perceptualHash,
            );
          } else {
            candidates[j] = PhotoResult(
              candidates[j].asset,
              candidates[j].score + 80.0,
              candidates[j].hash,
              candidates[j].perceptualHash,
            );
          }
        }
      }
    }

    // 3. TRIER PAR SCORE ET RETOURNER LES 9 PIRES
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final selected = candidates.take(9).toList();
    for (var photo in selected) {
      _seenPhotoIds.add(photo.asset.id);
    }
    return selected;
  }

  // SUPPRIMER LES PHOTOS SÉLECTIONNÉES
  Future<void> deletePhotos(List<PhotoResult> photos) async {
    final ids = photos.map((p) => p.asset.id).toList();
    await PhotoManager.editor.deleteWithIds(ids);
  }

  // OBTENIR L'ESPACE DE STOCKAGE
  Future<StorageInfo> getStorageInfo() async {
    final double total = await _diskSpace.getTotalDiskSpace ?? 0.0;
    final double free = await _diskSpace.getFreeDiskSpace ?? 0.0;

    final int totalSpace = total.toInt() * 1024 * 1024;
    final int usedSpace = (total - free).toInt() * 1024 * 1024;

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
  String get usedSpaceGB => '${(usedSpace / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  String get totalSpaceGB => '${(totalSpace / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
}
