import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/relay_mode.dart';

class ModeCard extends StatelessWidget {
  final RelayMode mode;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.mode,
    required this.isActive,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? AppColors.magenta : AppColors.navyLight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? AppColors.magenta
                  : isEnabled
                      ? AppColors.lightBlue.withValues(alpha: 0.3)
                      : Colors.transparent,
              width: 2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.magenta.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${mode.id}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isEnabled
                        ? (isActive ? AppColors.white : AppColors.white)
                        : AppColors.lightBlue.withValues(alpha: 0.5),
                  ),
                ),
                if (mode.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    mode.description!,
                    style: TextStyle(
                      fontSize: 10,
                      color: isEnabled
                          ? (isActive
                              ? AppColors.white.withValues(alpha: 0.8)
                              : AppColors.lightBlue)
                          : AppColors.lightBlue.withValues(alpha: 0.3),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
