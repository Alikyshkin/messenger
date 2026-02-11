import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';

/// Унифицированный виджет состояния ошибки
class ErrorStateWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const ErrorStateWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.errorPadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              AppSpacing.spacingVerticalXL,
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: AppSizes.iconMD),
                label: Text(retryLabel ?? context.tr('retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
