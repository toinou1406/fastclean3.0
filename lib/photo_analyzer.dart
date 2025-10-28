import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';

class PhotoAnalyzer {
  
  // Analyser une photo et retourner un score de suppression (0-100)
  Future<double> analyzePhoto(File photoFile, DateTime creationDate) async {
    double score = 0.0;
    
    // Charger l'image
    final bytes = await photoFile.readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) return 0.0;
    
    // 1. TEST DE FLOU (40 points max)
    final blurScore = _detectBlur(image);
    score += blurScore;
    
    // 2. TEST DE LUMINOSITÉ (35 points max)
    final darknessScore = _detectDarkness(image);
    score += darknessScore;
    
    // 3. TEST CAPTURE D'ÉCRAN (30 points max)
    final screenshotScore = _detectScreenshot(photoFile.path, image);
    score += screenshotScore;
    
    // 4. TEST RÉSOLUTION FAIBLE (25 points max)
    final lowResScore = _detectLowResolution(image);
    score += lowResScore;
    
    // 5. TEST ANCIENNETÉ (20 points max)
    final oldScore = _detectOldPhoto(creationDate);
    score += oldScore;
    
    return score.clamp(0.0, 100.0);
  }
  
  // DÉTECTION DE FLOU avec variance Laplacienne
  double _detectBlur(img.Image image) {
    // Convertir en niveaux de gris
    final gray = img.grayscale(image);
    
    // Calculer la variance du Laplacien (simplifié)
    double sum = 0.0;
    int count = 0;
    
    // Échantillonner tous les 4 pixels pour la vitesse
    for (int y = 1; y < gray.height - 1; y += 4) {
      for (int x = 1; x < gray.width - 1; x += 4) {
        // Opérateur Laplacien simplifié
        final center = _getGrayValue(gray, x, y);
        final top = _getGrayValue(gray, x, y - 1);
        final bottom = _getGrayValue(gray, x, y + 1);
        final left = _getGrayValue(gray, x - 1, y);
        final right = _getGrayValue(gray, x + 1, y);
        
        final laplacian = (4 * center - top - bottom - left - right).abs();
        sum += laplacian * laplacian;
        count++;
      }
    }
    
    final variance = sum / count;
    
    // Score basé sur la variance
    // Variance < 50 = très flou (40 points)
    // Variance > 200 = net (0 points)
    if (variance < 50) return 40.0;
    if (variance < 100) return 30.0;
    if (variance < 150) return 15.0;
    return 0.0;
  }
  
  int _getGrayValue(img.Image image, int x, int y) {
    final pixel = image.getPixel(x, y);
    return pixel.r.toInt(); // Déjà en niveaux de gris
  }
  
  // DÉTECTION DE LUMINOSITÉ FAIBLE
  double _detectDarkness(img.Image image) {
    double totalBrightness = 0.0;
    int sampleCount = 0;
    
    // Échantillonner tous les 8 pixels
    for (int y = 0; y < image.height; y += 8) {
      for (int x = 0; x < image.width; x += 8) {
        final pixel = image.getPixel(x, y);
        // Formule de luminance
        final brightness = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        totalBrightness += brightness;
        sampleCount++;
      }
    }
    
    final avgBrightness = totalBrightness / sampleCount;
    
    // Score basé sur la luminosité moyenne (0-255)
    if (avgBrightness < 30) return 35.0;  // Très sombre
    if (avgBrightness < 50) return 25.0;  // Sombre
    if (avgBrightness < 70) return 10.0;  // Un peu sombre
    return 0.0;
  }
  
  // DÉTECTION DE CAPTURE D'ÉCRAN
  double _detectScreenshot(String filename, img.Image image) {
    double score = 0.0;
    
    // Vérifier le nom du fichier
    final lowercaseName = filename.toLowerCase();
    if (lowercaseName.contains('screenshot') ||
        lowercaseName.contains('screen_') ||
        lowercaseName.contains('capture')) {
      score += 20.0;
    }
    
    // Vérifier les dimensions typiques d'écran mobile
    final aspectRatio = image.width / image.height;
    final commonRatios = [
      (1080 / 2340),  // 9:19.5 (Android moderne)
      (1080 / 2400),  // 9:20
      (1170 / 2532),  // iPhone 12/13/14
      (1284 / 2778),  // iPhone 14 Pro Max
    ];
    
    for (final ratio in commonRatios) {
      if ((aspectRatio - ratio).abs() < 0.01) {
        score += 10.0;
        break;
      }
    }
    
    return score.clamp(0.0, 30.0);
  }
  
  // DÉTECTION RÉSOLUTION FAIBLE
  double _detectLowResolution(img.Image image) {
    final totalPixels = image.width * image.height;
    
    // Moins de 250k pixels (500x500)
    if (totalPixels < 250000) return 25.0;
    if (totalPixels < 500000) return 15.0;
    return 0.0;
  }
  
  // DÉTECTION PHOTO ANCIENNE
  double _detectOldPhoto(DateTime creationDate) {
    final age = DateTime.now().difference(creationDate);
    
    if (age.inDays > 365) return 20.0;  // Plus d'un an
    if (age.inDays > 180) return 10.0;  // Plus de 6 mois
    return 0.0;
  }
  
  // CALCUL DE HASH POUR DOUBLONS (MD5)
  Future<String> calculateHash(File file) async {
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
  }
  
  // CALCUL DE HASH PERCEPTUEL (pHash simplifié)
  Future<String> calculatePerceptualHash(File file) async {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) return '';
    
    // 1. Redimensionner à 32x32
    final resized = img.copyResize(image, width: 32, height: 32);
    
    // 2. Convertir en niveaux de gris
    final gray = img.grayscale(resized);
    
    // 3. Calculer la moyenne
    double sum = 0.0;
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
        final pixel = gray.getPixel(x, y);
        sum += pixel.r.toDouble();
      }
    }
    final average = sum / (32 * 32);
    
    // 4. Générer le hash binaire
    String hash = '';
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
        final pixel = gray.getPixel(x, y);
        hash += pixel.r > average ? '1' : '0';
      }
    }
    
    return hash;
  }
  
  // CALCULER DISTANCE DE HAMMING entre deux hash
  int hammingDistance(String hash1, String hash2) {
    if (hash1.length != hash2.length) return 9999;
    
    int distance = 0;
    for (int i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) distance++;
    }
    return distance;
  }
}
