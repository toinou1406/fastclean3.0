import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'photo_cleaner_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'permission_screen.dart';
import 'full_screen_image_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primarySeedColor = Colors.deepPurple;

    final TextTheme appTextTheme = TextTheme(
      displayLarge: GoogleFonts.oswald(fontSize: 57, fontWeight: FontWeight.bold),
      titleLarge: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500),
      bodyMedium: GoogleFonts.openSans(fontSize: 14),
      labelLarge: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w500),
    );

    final ThemeData theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primarySeedColor,
        brightness: Brightness.dark,
      ),
      textTheme: appTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.oswald(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: primarySeedColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );

    return MaterialApp(
      title: 'Photo Cleaner',
      theme: theme,
      home: const AppFlow(),
    );
  }
}

class AppFlow extends StatefulWidget {
  const AppFlow({super.key});

  @override
  State<AppFlow> createState() => _AppFlowState();
}

class _AppFlowState extends State<AppFlow> {
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final ps = await PhotoManager.requestPermissionExtend();
    setState(() {
      _hasPermission = ps.isAuth;
    });
  }

  void _onPermissionGranted() {
    setState(() {
      _hasPermission = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _hasPermission
        ? const HomeScreen()
        : PermissionScreen(onPermissionGranted: _onPermissionGranted);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final PhotoCleanerService _service = PhotoCleanerService();
  
  StorageInfo? _storageInfo;
  List<PhotoResult> _selectedPhotos = [];
  final Set<String> _ignoredPhotos = {};
  bool _isLoading = false;
  bool _hasScanned = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }
  
  Future<void> _loadStorageInfo() async {
    final info = await _service.getStorageInfo();
    if (mounted) {
      setState(() {
        _storageInfo = info;
      });
    }
  }
  
  Future<void> _sortPhotos() async {
    setState(() {
      _isLoading = true;
      _selectedPhotos = [];
      _ignoredPhotos.clear();
    });
    _fadeController.reset();
    
    try {
      if (!_hasScanned) {
        await _service.scanPhotos();
        if (mounted) setState(() => _hasScanned = true);
      }
      
      final photos = await _service.selectPhotosToDelete();
      
      if (mounted) {
        setState(() {
          _selectedPhotos = photos;
          _isLoading = false;
        });
        _fadeController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
  
  Future<void> _deletePhotos() async {
    setState(() => _isLoading = true);
    
    try {
      final photosToDelete = _selectedPhotos
          .where((p) => !_ignoredPhotos.contains(p.asset.id))
          .toList();
      
      await _service.deletePhotos(photosToDelete);
      
      if (mounted) {
        setState(() {
          _selectedPhotos = [];
          _ignoredPhotos.clear();
          _isLoading = false;
        });
      }
      
      await _loadStorageInfo();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photos deleted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting photos: $e')),
        );
      }
    }
  }
  
  void _toggleIgnoredPhoto(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (_ignoredPhotos.contains(id)) {
        _ignoredPhotos.remove(id);
      } else {
        _ignoredPhotos.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: Platform.environment.containsKey('FLUTTER_TEST')
            ? null
            : const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage("assets/images/noise.png"),
                  fit: BoxFit.cover, 
                  opacity: 0.05,
                ),
              ),
        child: SafeArea(
          child: Column(
            children: [
              // HEADER
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text('AI Photo Cleaner', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 36)),
                    const SizedBox(height: 20),
                    if (_storageInfo != null) 
                      StorageIndicator(storageInfo: _storageInfo!),
                  ],
                ),
              ),
              
              const Divider(),
              
              // PHOTO GRID
              Expanded(
                child: _isLoading
                    ? const LoadingState()
                    : _selectedPhotos.isEmpty
                        ? const EmptyState()
                        : FadeTransition(
                            opacity: _fadeAnimation,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: _selectedPhotos.length,
                              itemBuilder: (context, index) {
                                final photo = _selectedPhotos[index];
                                return PhotoCard(
                                  photo: photo,
                                  isIgnored: _ignoredPhotos.contains(photo.asset.id),
                                  onLongPress: () => _toggleIgnoredPhoto(photo.asset.id),
                                );
                              },
                            ),
                          ),
              ),
              
              // ACTION BUTTONS
              Padding(
                padding: const EdgeInsets.all(20),
                child: _selectedPhotos.isEmpty
                    ? ActionButton(
                        label: 'Sort',
                        icon: Icons.sort,
                        onPressed: _isLoading ? null : _sortPhotos,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: ActionButton(
                              label: 'Re-sort',
                              icon: Icons.refresh,
                              onPressed: _isLoading ? null : _sortPhotos,
                              backgroundColor: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ActionButton(
                              label: 'Delete',
                              icon: Icons.delete_forever,
                              onPressed: _isLoading ? null : _deletePhotos,
                              backgroundColor: Colors.red[800],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StorageIndicator extends StatelessWidget {
  final StorageInfo storageInfo;
  const StorageIndicator({super.key, required this.storageInfo});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Used Storage', style: Theme.of(context).textTheme.titleLarge),
            Text('${storageInfo.usedSpaceGB} / ${storageInfo.totalSpaceGB}', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: storageInfo.usedPercentage / 100,
            minHeight: 12,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              storageInfo.usedPercentage > 80 ? Colors.red.shade400 : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class PhotoCard extends StatefulWidget {
  final PhotoResult photo;
  final bool isIgnored;
  final VoidCallback onLongPress;

  const PhotoCard({
    super.key,
    required this.photo,
    required this.isIgnored,
    required this.onLongPress,
  });

  @override
  State<PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<PhotoCard> with SingleTickerProviderStateMixin {
  late AnimationController _swayController;
  late Animation<double> _swayAnimation;

  @override
  void initState() {
    super.initState();
    _swayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _swayAnimation = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(
        parent: _swayController,
        curve: Curves.easeInOut,
      ),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _swayController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _swayController.forward();
      }
    });

    if (widget.isIgnored) {
      _swayController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant PhotoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isIgnored != oldWidget.isIgnored) {
      if (widget.isIgnored) {
        _swayController.forward();
      } else {
        _swayController.stop();
        _swayController.reset();
      }
    }
  }

  @override
  void dispose() {
    _swayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenImageView(asset: widget.photo.asset),
          ),
        );
      },
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _swayAnimation,
        builder: (context, child) {
          return Transform.rotate(
            angle: widget.isIgnored ? _swayAnimation.value : 0,
            child: child,
          );
        },
        child: Card(
          elevation: 8,
          shadowColor: Colors.black.withAlpha(128),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColorFiltered(
                colorFilter: ColorFilter.mode(
                  widget.isIgnored ? Colors.grey : Colors.transparent,
                  BlendMode.saturation,
                ),
                child: FutureBuilder(
                  future: widget.photo.asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(snapshot.data!, fit: BoxFit.cover);
                    }
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(153),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${widget.photo.score.toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;

  const ActionButton({super.key, required this.label, required this.icon, this.onPressed, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.primary,
        minimumSize: const Size(double.infinity, 60),
        shadowColor: (backgroundColor ?? Theme.of(context).colorScheme.primary).withAlpha(128),
        elevation: 8,
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(strokeWidth: 6),
          const SizedBox(height: 24),
          Text('Analyzing Photos...', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library, size: 100, color: Theme.of(context).colorScheme.primary.withAlpha(178)),
          const SizedBox(height: 24),
          Text('Press "Sort" to Begin', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          Text('Let the AI find photos you can delete', style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center,),
        ],
      ),
    );
  }
}
