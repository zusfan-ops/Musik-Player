import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/jellyfin_profile_models.dart';
import '../providers/profile_jellyfin_provider.dart';

class UserAvatarWidget extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;

  const UserAvatarWidget({
    super.key,
    this.size = 38,
    this.onTap,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileJellyfinProvider>();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeSize = (size * dpr).round().clamp(64, 512);
    final radius = size * 0.28;

    Widget content = _buildPresetContent(profile.avatarPresetIndex, size);

    if (profile.avatarMode == AvatarSourceMode.customFile &&
        profile.customAvatarPath != null &&
        profile.customAvatarPath!.isNotEmpty) {
      content = Image.file(
        File(profile.customAvatarPath!),
        width: size,
        height: size,
        cacheWidth: decodeSize,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _buildPresetContent(profile.avatarPresetIndex, size),
      );
    } else if (profile.avatarMode == AvatarSourceMode.jellyfinAvatar &&
        profile.jellyfinUserAvatarUrl != null) {
      content = Image.network(
        profile.jellyfinUserAvatarUrl!,
        headers: profile.authHeaders,
        width: size,
        height: size,
        cacheWidth: decodeSize,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _buildPresetContent(profile.avatarPresetIndex, size),
      );
    }

    final avatarBox = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: showBorder
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1.5,
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(showBorder ? radius - 1.5 : radius),
        child: content,
      ),
    );

    if (onTap == null) return avatarBox;
    return GestureDetector(
      onTap: onTap,
      child: avatarBox,
    );
  }

  Widget _buildPresetContent(int presetIdx, double sz) {
    final style = AvatarPresetStyle.byIndex(presetIdx);
    return Container(
      width: sz,
      height: sz,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: style.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        style.icon,
        color: Colors.white,
        size: sz * 0.54,
      ),
    );
  }
}
