import 'dart:async';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionScreen extends StatefulWidget {
  final VoidCallback onPermissionGranted;

  const PermissionScreen({super.key, required this.onPermissionGranted});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _animationController, curve: Curves.easeInOutCubic));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);

    final result = await PhotoManager.requestPermissionExtend();

    if (result.isAuth) {
      widget.onPermissionGranted();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Full photo access is required to use this app.'),
            backgroundColor: Colors.red.shade700,
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                openAppSettings();
              },
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage("assets/images/noise.png"),
            fit: BoxFit.cover,
            opacity: 0.05,
            colorFilter: ColorFilter.mode(
                theme.colorScheme.primary.withAlpha(25), BlendMode.colorBurn),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shield_moon_outlined,
                      size: 100,
                      color: theme.colorScheme.primary.withAlpha(204),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Grant Photo Access',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayLarge?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Our AI needs your permission to scan your gallery. It will find blurry, duplicate, and unwanted photos for you to delete.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(178),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildPrivacyChip(theme),
                    const SizedBox(height: 48),
                    _buildActionButton(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyChip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(76)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_outlined,
              color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            '100% Private & Secure',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return ScaleTransition(scale: animation, child: child);
      },
      child: _isLoading
          ? CircularProgressIndicator(
              key: const ValueKey('loader'),
              color: theme.colorScheme.primary,
            )
          : SizedBox(
              key: const ValueKey('button'),
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Grant Full Access'),
                onPressed: _requestPermission,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.labelLarge,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
    );
  }
}
