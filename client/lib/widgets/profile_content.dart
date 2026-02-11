import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../widgets/user_avatar.dart';
import '../screens/settings_screen.dart';
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';

String _friendsCountLabel(BuildContext context, int? count) {
  if (count == null) return '—';
  if (count == 0) return context.tr('no_friends');
  if (count == 1) return context.tr('one_friend');
  if (count >= 2 && count <= 4)
    return context.tr('friends_2_4').replaceFirst('%s', '$count');
  return context.tr('friends_5_plus').replaceFirst('%s', '$count');
}

String _formatBirthday(BuildContext context, String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  final months = [
    context.tr('jan'),
    context.tr('feb'),
    context.tr('mar'),
    context.tr('apr'),
    context.tr('may'),
    context.tr('jun'),
    context.tr('jul'),
    context.tr('aug'),
    context.tr('sep'),
    context.tr('oct'),
    context.tr('nov'),
    context.tr('dec'),
  ];
  final day = int.tryParse(parts[2]) ?? 0;
  final month = int.tryParse(parts[1]);
  final year = parts[0];
  if (month == null || month < 1 || month > 12) return iso;
  return '$day ${months[month - 1]} $year';
}

/// Виджет содержимого экрана профиля без Scaffold для встраивания в HomeScreen
class ProfileContent extends StatefulWidget {
  final NavigatorState? navigator;

  const ProfileContent({super.key, this.navigator});

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  bool _userRefreshed = false;

  @override
  void initState() {
    super.initState();
    if (!_userRefreshed) {
      _userRefreshed = true;
      // Не вызываем refreshUser автоматически, чтобы не вызывать лишние перестройки
      // Данные пользователя уже загружены в AuthService
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        final u = auth.user;
        if (u == null) return Center(child: Text(context.tr('not_authorized')));
        return Column(
          children: [
            // Заголовок и кнопка настроек
            Container(
              padding: AppSpacing.navigationPadding,
              height: AppSizes.appBarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      context.tr('profile'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: context.tr('settings'),
                    onPressed: () {
                      final nav = widget.navigator ?? Navigator.of(context);
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: AppSpacing.screenPaddingVertical,
                children: [
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPaddingLarge,
                      child: Column(
                        children: [
                          UserAvatar(
                            user: u,
                            radius: AppSizes.avatarXL,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            textStyle: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                          AppSpacing.spacingVerticalLG,
                          Text(
                            u.displayName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          AppSpacing.spacingVerticalXS,
                          Text(
                            '@${u.username}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (u.bio != null && u.bio!.isNotEmpty) ...[
                            AppSpacing.spacingVerticalMD,
                            Text(
                              u.bio!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                          if (u.birthday != null && u.birthday!.isNotEmpty) ...[
                            AppSpacing.spacingVerticalMD,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cake_outlined,
                                  size: AppSizes.iconSM,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                AppSpacing.spacingHorizontalMD,
                                Text(
                                  _formatBirthday(context, u.birthday!),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  AppSpacing.spacingVerticalMD,
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.people_outline),
                          title: Text(context.tr('friends')),
                          subtitle: Text(
                            _friendsCountLabel(context, u.friendsCount),
                          ),
                          onTap: () {
                            // Переключение на контакты будет обработано через навигацию
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: Text(context.tr('settings')),
                          subtitle: Text(context.tr('settings_subtitle')),
                          onTap: () {
                            final nav =
                                widget.navigator ?? Navigator.of(context);
                            nav.push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
