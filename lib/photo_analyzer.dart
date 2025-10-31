
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';

// Note to developer: This file has been completely rewritten by the AI expert
// to implement a high-performance, multi-stage photo analysis pipeline.

//##############################################################################
//# 1. ANALYSIS RESULT & SCORING MODEL
//##############################################################################

/// A comprehensive data model holding all analysis metrics for a single photo.
/// This structured data is crucial for the scoring engine and for debugging.
class PhotoAnalysisResult {
  // --- Core Identifiers ---
  final String md5Hash;
  final String pHash;

  // --- Stage 1: Fast Heuristics ---
  final double blurScore;         // Lower is blurrier (Laplacian Variance)
  final double luminanceScore;    // Mean pixel brightness (0-255)
  final double entropyScore;        // Lower is less detailed (Histogram Entropy)
  final double edgeDensityScore;    // Higher means more edges (Sobel Operator)

  // --- Stage 2: On-Device AI (Placeholders) ---
  final int faceCount;            // Detected faces (e.g., from MediaPipe)
  final double aestheticScore;      // AI-based quality score (e.g., from MobileNetV3)

  // --- Final Score ---
  /// The combined "badness" score. Higher means more likely to be a candidate for deletion.
  double finalScore = 0.0;

  PhotoAnalysisResult({
    required this.md5Hash,
    required this.pHash,
    required this.blurScore,
    required this.luminanceScore,
    required this.entropyScore,
    required this.edgeDensityScore,
    this.faceCount = 0,
    this.aestheticScore = 0.5, // Default neutral score
  }) {
    // Calculate the final combined score upon instantiation.
    finalScore = _calculateFinalScore();
  }

  /// ##########################################################################
  /// # SCORING ENGINE
  /// ##########################################################################
  /// This is the core logic that translates raw metrics into a "delete" recommendation.
  /// Each condition adds "penalty points". The higher the score, the worse the photo.
  /// This approach is modular and easy to tune.
  double _calculateFinalScore() {
    double score = 0;

    // --- RULE 1: Severe Blur ---
    // Laplacian variance threshold, determined empirically. Very low variance = very blurry.
    if (blurScore < 80.0) {
      score += 45; // High penalty
    }

    // --- RULE 2: Very Dark Photo ---
    // Low mean brightness AND low entropy (few details) is a strong signal for a bad photo.
    if (luminanceScore < 50.0 && entropyScore < 1.5) {
      score += 30; // High penalty
    } else if (luminanceScore < 50.0) {
      score += 15; // Medium penalty for just being dark
    }
    
    // --- RULE 3: Document / Whiteboard ---
    // High edge density is characteristic of text and documents.
    if (edgeDensityScore > 0.08) { // 8% of pixels are edges
        score += 25;
    }

    // --- RULE 4: Potentially Useless (No People, Low Detail) ---
    // Photos without faces and low detail are often expendable.
    if (faceCount == 0 && entropyScore < 1.2) {
      score += 20;
    }
    
    // --- RULE 5: AI Aesthetic Score ---
    // Directly factor in the AI's opinion. We map the [0,1] range to a [-20, 20] penalty/bonus.
    // A photo the AI rates as 0.0 (bad) gets +20 points. A photo rated 1.0 (good) gets -20 points.
    score += (1.0 - aestheticScore - 0.5) * 40;

    // Normalize score to be roughly within 0-100 for easier display.
    return max(0, min(100, score));
  }
}


//##############################################################################
//# 2. THE PHOTO ANALYZER SERVICE
//##############################################################################

class PhotoAnalyzer {

  // --- HASHING ---

  /// Calculates a fast, cryptographic hash (MD5) of the file bytes.
  /// Used for finding exact duplicates.
  Future<String> calculateMd5Hash(File file) async {
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
  }

  /// ##########################################################################
  /// # PERCEPTUAL HASH (pHash) IMPLEMENTATION
  /// ##########################################################################
  /// Detects "similar" images, resilient to resizing and minor edits.
  Future<String> calculatePerceptualHash(img.Image resizedImage) async {
    // 1. Convert to grayscale.
    final grayscaleImg = img.grayscale(resizedImage);
    
    // 2. Downsize to a tiny 8x8 image. This removes high frequencies and details.
    final smallImg = img.copyResize(grayscaleImg, width: 8, height: 8, interpolation: img.Interpolation.average);

    // 3. Calculate the average pixel value.
    double total = 0;
    for (int y = 0; y < smallImg.height; y++) {
      for (int x = 0; x < smallImg.width; x++) {
        total += smallImg.getPixel(x, y).r;
      }
    }
    final double average = total / 64.0;

    // 4. Generate the binary hash.
    // Each bit is 1 if the pixel is >= average, 0 otherwise.
    BigInt hash = BigInt.zero;
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            if (smallImg.getPixel(x, y).r >= average) {
                hash |= (BigInt.one << (y * 8 + x));
            }
        }
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Calculates the Hamming distance between two pHashes.
  /// This is the number of bits that are different. A lower number means more similar.
  int hammingDistance(String pHash1, String pHash2) {
    if (pHash1.length != pHash2.length) return pHash1.length; // Should not happen

    final val1 = BigInt.parse(pHash1, radix: 16);
    final val2 = BigInt.parse(pHash2, radix: 16);
    
    BigInt xor = val1 ^ val2;
    int distance = 0;
    while (xor > BigInt.zero) {
        distance += (xor & BigInt.one) == BigInt.one ? 1 : 0;
        xor >>= 1;
    }
    return distance;
  }

  // --- FAST HEURISTICS ---

  /// ##########################################################################
  /// # BLUR DETECTION (Laplacian Variance)
  /// ##########################################################################
  /// Measures the amount of edges in an image. Blurry images have fewer/weaker edges.
  double _calculateLaplacianVariance(img.Image image) {
    // Apply Laplacian filter. It highlights edges.
    final laplace = img.convolution(image, filter: [
      0,  1,  0,
      1, -4,  1,
      0,  1,  0,
    ]);

    // Calculate the variance of the pixel intensities in the filtered image.
    // Low variance = weak edges = blur.
    final pixels = laplace.getBytes(order: img.ChannelOrder.red);
    double mean = pixels.reduce((a, b) => a + b) / pixels.length;
    double variance = pixels.map((p) => pow(p - mean, 2)).reduce((a, b) => a + b) / pixels.length;
    return variance;
  }

  /// ##########################################################################
  /// # DARKNESS & DETAIL (Luminance & Entropy)
  /// ##########################################################################
  Map<String, double> _calculateLuminanceAndEntropy(img.Image image) {
    final luminances = <int>[];
    final histogram = List<int>.filled(256, 0);

    for (final pixel in image) {
      final luminance = pixel.r.toInt(); // Already grayscale
      luminances.add(luminance);
      histogram[luminance]++;
    }

    // Mean Luminance
    final double meanLuminance = luminances.reduce((a, b) => a + b) / luminances.length;

    // Shannon Entropy
    double entropy = 0.0;
    final int totalPixels = luminances.length;
    for (int count in histogram) {
      if (count > 0) {
        double probability = count / totalPixels;
        entropy -= probability * log2(probability);
      }
    }

    return {'luminance': meanLuminance, 'entropy': entropy};
  }

  /// ##########################################################################
  /// # DOCUMENT DETECTION (Edge Density)
  /// ##########################################################################
  double _calculateEdgeDensity(img.Image image) {
    final edgeImage = img.sobel(image);
    final edgePixels = edgeImage.getBytes(order: img.ChannelOrder.red);
    
    // Count pixels that are clearly edges (threshold empirically set).
    int edgeCount = edgePixels.where((p) => p > 50).length;
    
    return edgeCount / edgePixels.length;
  }

  // --- ON-DEVICE AI (PLACEHOLDERS) ---

  /// Placeholder for running a TFLite model for face detection.
  /// In a real implementation, you would use a package like `google_mlkit_face_detection`.
  Future<int> _detectFaces(img.Image image) async {
    // ---- REAL IMPLEMENTATION ----
    // final inputImage = InputImage.fromBytes(bytes: img.encodeJpg(image), ...);
    // final faceDetector = GoogleMlKit.vision.faceDetector();
    // final faces = await faceDetector.processImage(inputImage);
    // await faceDetector.close();
    // return faces.length;
    // ---- END REAL IMPLEMENTATION ----
    
    // For now, return a placeholder value.
    return 0;
  }
  
  /// Placeholder for running a TFLite model for aesthetic quality.
  /// You would use a package like `tflite_flutter` and a pre-trained MobileNetV3-based model.
  Future<double> _getAestheticScore(img.Image image) async {
      // ---- REAL IMPLEMENTATION ----
      // final interpreter = await Interpreter.fromAsset('models/aesthetic_model.tflite');
      // var input = img.copyResize(image, width: 224, height: 224);
      // // ... preprocess input tensor ...
      // interpreter.run(input, output);
      // return output[0][0]; // Assuming model output is a single quality score.
      // ---- END REAL IMPLEMENTATION ----

      return 0.5; // Return neutral score for now.
  }


  //##############################################################################
  //# 3. MAIN ANALYSIS PIPELINE
  //##############################################################################

  /// Orchestrates the full analysis pipeline for a single photo.
  /// Designed to be run inside a Flutter `compute` Isolate.
  Future<PhotoAnalysisResult> analyze(File photoFile) async {
    // --- STAGE 0: Decode and Prepare Image ---
    // This is the most memory-intensive part. We do it once.
    final imageBytes = await photoFile.readAsBytes();
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw Exception("Could not decode image: ${photoFile.path}");
    }
    
    // Create a smaller, grayscale version for fast heuristics. This is a KEY optimization.
    final lowResGray = img.copyResize(originalImage, width: 128, height: 128, interpolation: img.Interpolation.average);
    img.grayscale(lowResGray);

    // --- STAGE 1: Run Hashing & Fast Heuristics in Parallel ---
    final md5Future = calculateMd5Hash(photoFile);
    final pHashFuture = calculatePerceptualHash(lowResGray); // Use the pre-resized image
    final blurScore = _calculateLaplacianVariance(lowResGray);
    final lumAndEntropy = _calculateLuminanceAndEntropy(lowResGray);
    final edgeScore = _calculateEdgeDensity(lowResGray);

    // --- STAGE 2: Run "Slower" AI Models in Parallel (using placeholders) ---
    // In a real app, the full-resolution `originalImage` might be needed for the AI models.
    final faceCountFuture = _detectFaces(originalImage); 
    final aestheticScoreFuture = _getAestheticScore(originalImage);

    // --- STAGE 3: Await All Results and Assemble ---
    final results = await Future.wait([
      md5Future,
      pHashFuture,
      faceCountFuture,
      aestheticScoreFuture,
    ]);

    return PhotoAnalysisResult(
      md5Hash: results[0] as String,
      pHash: results[1] as String,
      blurScore: blurScore,
      luminanceScore: lumAndEntropy['luminance']!,
      entropyScore: lumAndEntropy['entropy']!,
      edgeDensityScore: edgeScore,
      faceCount: results[2] as int,
      aestheticScore: results[3] as double,
    );
  }
}
