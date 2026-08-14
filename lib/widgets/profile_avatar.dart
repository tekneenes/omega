import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/user_profile.dart';

/// Reusable profile avatar widget that displays either:
/// 1. A base64-encoded profile photo (from Firebase, for paired devices)
/// 2. A local file photo (for the current user)
/// 3. A preset icon (tablet, parent, child, etc.)
class ProfileAvatar extends StatelessWidget {
  final UserProfile? profile;
  final double radius;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;

  /// Global memory cache for decoded base64 image bytes to prevent flickering on rebuilds
  static final Map<String, Uint8List> _base64Cache = {};

  const ProfileAvatar({
    super.key,
    required this.profile,
    this.radius = 30,
    this.borderColor,
    this.borderWidth = 2,
    this.backgroundColor,
  });

  static Uint8List _getDecodedBytes(String b64) {
    if (_base64Cache.containsKey(b64)) {
      return _base64Cache[b64]!;
    }
    final bytes = base64Decode(b64);
    if (_base64Cache.length > 50) {
      _base64Cache.remove(_base64Cache.keys.first);
    }
    _base64Cache[b64] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final bgColor = backgroundColor ?? Colors.white.withValues(alpha: 0.2);
    final border = borderColor ?? Colors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: border, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: _buildImage(size),
      ),
    );
  }

  Widget _buildImage(double size) {
    if (profile == null) {
      return _buildIcon(Icons.person_rounded, size);
    }

    // Priority 1: base64 photo from Firebase (paired device's shared photo)
    if (profile!.photoBase64 != null && profile!.photoBase64!.isNotEmpty) {
      try {
        final bytes = _getDecodedBytes(profile!.photoBase64!);
        return Image.memory(
          bytes,
          key: ValueKey(profile!.photoBase64),
          gaplessPlayback: true,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => _buildIcon(Icons.person_rounded, size),
        );
      } catch (_) {
        // Fall through to default icon
      }
    }

    // Priority 2: local file path (current user's photo on this device)
    if (!kIsWeb && profile!.avatarIcon.startsWith('/')) {
      try {
        final file = File(profile!.avatarIcon);
        if (file.existsSync()) {
          return Image.file(
            file,
            key: ValueKey(profile!.avatarIcon),
            gaplessPlayback: true,
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: (_, __, ___) => _buildIcon(Icons.person_rounded, size),
          );
        }
      } catch (_) {
        // Fall through to default icon
      }
    }

    // Priority 3: Default silhouette icon (Icons.person_rounded) everywhere
    return _buildIcon(Icons.person_rounded, size);
  }

  Widget _buildIcon(IconData icon, double size) {
    return Center(
      child: Icon(
        icon,
        color: Colors.white,
        size: size * 0.55,
      ),
    );
  }
}
