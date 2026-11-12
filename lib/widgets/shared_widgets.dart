import 'dart:convert';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../services/app_data.dart';
import '../services/tutorial_service.dart';
import '../models/models.dart';
import '../widgets/tutorial_overlay.dart';
import '../screens/admin/messaging_screen.dart';
import '../screens/admin/loyal_customers_screen.dart';
import '../screens/employee/kiosk_management_screen.dart';

/// A single navigation destination in a sidebar/drawer/bottom-nav.
class NavItem {
  final IconData icon;
  final String label;
  final Widget Function() builder;
  NavItem({required this.icon, required this.label, required this.builder});
}

/// Compact, safe-area-aware mobile navigation used by the customer shell.
class MobileBottomNavigation extends StatelessWidget {
  final List<NavItem> items;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  const MobileBottomNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border, width: 1.2),
          boxShadow: AppShadows.lifted,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: List.generate(items.length, (i) {
            final item = items[i];
            final selected = i == selectedIndex;
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: item.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    constraints: const BoxConstraints(minHeight: 54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.beige : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: selected
                              ? AppColors.darkBrown
                              : AppColors.textMuted,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.15,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            color: selected
                                ? AppColors.darkBrown
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Responsive shell: NavigationRail/sidebar on wide screens and Drawer + AppBar
/// on narrow screens, with optional fixed bottom navigation for customer phones.
/// Used by Admin, Employee, and Customer sides alike.
///
/// Optional extras (used by the Admin side):
///  * [logoAsset]     – image shown at the top of the sidebar instead of the default logo.
///  * [homeItem]      – screen opened on start and when the sidebar logo is tapped
///                      (it is not listed in the sidebar itself).
///  * [dividerAfter]  – indexes in [items] that get a divider line right below them.
///  * [settingsItems] – extra screens listed in the navbar Settings menu
///                      (between Profile and Logout).
class AppShell extends StatefulWidget {
  final String title;
  final List<NavItem> items;
  final VoidCallback onLogout;
  final Widget? trailing; // e.g. notification bell
  final Widget? profileScreen;
  final String? logoAsset;
  final NavItem? homeItem;
  final Set<int> dividerAfter;
  final List<NavItem> settingsItems;
  final bool hideDrawer;
  final bool mobileBottomNavigation;

  /// Optional widget pinned to the bottom of the wide-screen sidebar
  /// (e.g. a status card). Null for Admin/Employee, so they are unchanged.
  final Widget? sidebarFooter;

  /// Optional: label of the nav item that gets a small "LIVE" tag.
  final String? liveItemLabel;

  /// Optional custom back handler (overrides default showExitConfirmationDialog)
  final Future<bool> Function()? onBack;
  const AppShell({
    super.key,
    required this.title,
    required this.items,
    required this.onLogout,
    this.trailing,
    this.profileScreen,
    this.logoAsset,
    this.homeItem,
    this.dividerAfter = const {},
    this.settingsItems = const [],
    this.hideDrawer = false,
    this.mobileBottomNavigation = false,
    this.sidebarFooter,
    this.liveItemLabel,
    this.onBack,
  });

  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _selected = 0; // -1 = home item (opened via the logo / Dashboard entry)
  int? _settingsIndex; // non-null = a Settings-menu screen is showing
  NavItem? _customNavItem;

  void openCustomNavItem(NavItem item) {
    setState(() {
      _customNavItem = item;
      _settingsIndex = null;
    });
  }

  void selectTabByLabel(String label) {
    if (label.toLowerCase() == 'messaging') {
      final user = AppData.instance.currentUser;
      final role = (user != null && user.fullName.trim().isNotEmpty)
          ? user.fullName.trim()
          : 'Admin';
      setState(() {
        _customNavItem = NavItem(
          icon: Icons.chat_outlined,
          label: 'Messaging',
          builder: () => MessagingScreen(currentRole: role),
        );
        _settingsIndex = null;
      });
      return;
    }
    final idx = widget.items.indexWhere(
      (item) => item.label.toLowerCase() == label.toLowerCase(),
    );
    if (idx != -1) {
      setState(() {
        _selected = idx;
        _settingsIndex = null;
        _customNavItem = null;
      });
    }
  }

  static const _defaultMark = 'assets/images/oc_logo.png';

  @override
  void initState() {
    super.initState();
    if (widget.homeItem != null) _selected = -1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLoginTutorial();
    });
  }

  Future<void> _checkFirstLoginTutorial() async {
    final user = AppData.instance.currentUser;
    if (user == null) return;
    final roleName = user.role.name;
    final completed = await TutorialService.instance.hasCompletedTutorial(user.id, roleName);
    if (!completed && mounted) {
      final steps = TutorialService.instance.getStepsForRole(roleName);
      if (steps.isNotEmpty) {
        await TutorialOverlay.show(
          context: context,
          steps: steps,
          onFinished: () {
            TutorialService.instance.setTutorialCompleted(user.id, roleName, true);
          },
        );
      }
    }
  }

  void replayTutorial() {
    final user = AppData.instance.currentUser;
    if (user == null) return;
    final roleName = user.role.name;
    final steps = TutorialService.instance.getStepsForRole(roleName);
    if (steps.isNotEmpty) {
      TutorialOverlay.show(
        context: context,
        steps: steps,
        onFinished: () {
          TutorialService.instance.setTutorialCompleted(user.id, roleName, true);
        },
      );
    }
  }

  bool get _isAtRootView {
    final rootIndex = widget.homeItem != null ? -1 : 0;
    return _customNavItem == null &&
        _settingsIndex == null &&
        _selected == rootIndex;
  }

  Future<bool> _handleShellBack() async {
    if (!_isAtRootView) {
      final rootIndex = widget.homeItem != null ? -1 : 0;
      setState(() {
        _customNavItem = null;
        _settingsIndex = null;
        _selected = rootIndex;
      });
      return true;
    }
    if (widget.onBack != null) {
      await widget.onBack!();
      return true;
    }
    await showExitConfirmationDialog(context);
    return true;
  }

  NavItem get _currentItem {
    if (_customNavItem != null) return _customNavItem!;
    if (_settingsIndex != null) return widget.settingsItems[_settingsIndex!];
    if (_selected == -1 && widget.homeItem != null) return widget.homeItem!;
    return widget.items[_selected < 0 ? 0 : _selected];
  }

  void _openProfile() {
    if (widget.profileScreen == null) return;
    setState(() {
      _customNavItem = NavItem(
        icon: Icons.person_outline,
        label: 'Profile',
        builder: () => widget.profileScreen!,
      );
      _settingsIndex = null;
    });
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text(
          'Are you sure you want to log out of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.onLogout();
    }
  }

  /// One sidebar / drawer destination. The active page is a solid white pill
  /// with black text so the current location is obvious at a glance.
  Widget _railNavItem(NavItem item, bool selected, VoidCallback onTap) {
    final fg =
        selected ? AppColors.darkBrown : Colors.white.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Material(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: selected
                ? AppColors.accent.withValues(alpha: 0.08)
                : AppColors.accent.withValues(alpha: 0.14),
            splashColor: selected ? Colors.black12 : Colors.white12,
            highlightColor: Colors.transparent,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.icon,
                      size: 19,
                      color: selected ? Colors.white : fg,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13.5,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  if (widget.liveItemLabel != null &&
                      item.label == widget.liveItemLabel) ...[
                    const SizedBox(width: 6),
                    _LiveTag(onLightBackground: selected),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Brand block at the top of the sidebar / drawer (non-clickable).
  Widget _sidebarHeader({bool inDrawer = false}) {
    final asset = widget.logoAsset ?? 'assets/images/OC_NAVBAR_LOGO.png';
    final brand = Image.asset(asset, height: 48, fit: BoxFit.contain);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Padding(padding: const EdgeInsets.all(4), child: brand),
    );
  }

  /// Sidebar/drawer nav list: [AppShell.items] with optional divider lines
  /// between groups. The Dashboard ([AppShell.homeItem]) is not listed here;
  /// it opens from the sidebar logo.
  Widget _navList({bool closeDrawer = false}) {
    final children = <Widget>[];

    for (var i = 0; i < widget.items.length; i++) {
      children.add(
        _railNavItem(
          widget.items[i],
          _settingsIndex == null && _customNavItem == null && i == _selected,
          () {
            setState(() {
              _selected = i;
              _settingsIndex = null;
              _customNavItem = null;
            });
            if (closeDrawer) Navigator.pop(context);
          },
        ),
      );
      if (widget.dividerAfter.contains(i) && i != widget.items.length - 1) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Divider(color: Colors.white12, height: 1),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: children,
    );
  }

  /// Profile-driven settings dropdown: Profile, any [AppShell.settingsItems], Logout.
  Widget _settingsButton({
    required Color iconColor,
    Offset offset = Offset.zero,
  }) {
    final user = AppData.instance.currentUser;
    final avatarBytes = user?.avatarBytes;
    final initials = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim().substring(0, 1).toUpperCase()
        : '?';
    final compact = MediaQuery.sizeOf(context).width < 420;
    final roleLabel = user?.roleLabel ?? 'User';

    final isLoyal = user != null && AppData.instance.isCustomerLoyal(user);

    return PopupMenuButton<String>(
      tooltip: 'Account menu',
      padding: EdgeInsets.zero,
      offset: offset,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      shadowColor: Colors.black26,
      color: AppColors.cardWhite,
      onSelected: (val) {
        if (val == 'profile') {
          _openProfile();
        } else if (val == 'tutorial') {
          replayTutorial();
        } else if (val == 'logout') {
          _confirmLogout(context);
        } else if (val.startsWith('settings:')) {
          final idx = int.parse(val.substring('settings:'.length));
          setState(() {
            _settingsIndex = idx;
            _customNavItem = null;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isLoyal ? AppColors.accent : AppColors.brown.withValues(alpha: 0.3),
                  width: isLoyal ? 2.5 : 1.5,
                ),
                boxShadow: isLoyal
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.45),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.darkBrown,
                backgroundImage:
                    avatarBytes != null ? MemoryImage(avatarBytes) : null,
                child: avatarBytes == null
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      )
                    : null,
              ),
            ),
            if (user != null && !compact) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            user.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: iconColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (AppData.instance.isCustomerLoyal(user)) ...[
                          const SizedBox(width: 4),
                          const LoyalBadge(fontSize: 9.0, iconSize: 9),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      roleLabel,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: iconColor),
          ],
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.darkBrown,
                  backgroundImage:
                      avatarBytes != null ? MemoryImage(avatarBytes) : null,
                  child: avatarBytes == null
                      ? Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user?.fullName ?? 'Account',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                                color: AppColors.darkBrown,
                              ),
                            ),
                          ),
                          if (user != null &&
                              AppData.instance.isCustomerLoyal(user)) ...[
                            const SizedBox(width: 6),
                            const LoyalBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'profile',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.brown.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: AppColors.brown,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'My Profile',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'tutorial',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.brown.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: AppColors.brown,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Help & Tutorial Tour',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
        for (int i = 0; i < widget.settingsItems.length; i++)
          PopupMenuItem<String>(
            value: 'settings:$i',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.brown.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.settingsItems[i].icon,
                      size: 18,
                      color: AppColors.brown,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.settingsItems[i].label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'logout',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Logout',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _todayLabel() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final n = DateTime.now();
    return '${weekdays[n.weekday - 1]}, ${months[n.month - 1]} ${n.day}, ${n.year}';
  }

  Widget _mobileBottomNavigation() {
    final hasMainTabSelected =
        _settingsIndex == null && _customNavItem == null && _selected >= 0;
    return MobileBottomNavigation(
      items: widget.items,
      selectedIndex: hasMainTabSelected ? _selected : null,
      onSelected: (index) => setState(() {
        _selected = index;
        _settingsIndex = null;
        _customNavItem = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExitConfirmationPopScope(
      onBack: _handleShellBack,
      child: AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final wide = MediaQuery.of(context).size.width >= 900;
        final item = _currentItem;
        final current = item.builder();
        final contentKey = ValueKey('${_settingsIndex ?? 'nav'}-$_selected');

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                  child: Container(
                    width: 272,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.darkBrown,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sidebarHeader(),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: Divider(color: Colors.white12, height: 1),
                          ),
                          const SizedBox(height: 10),
                          Expanded(child: _navList()),
                          if (widget.sidebarFooter != null)
                            widget.sidebarFooter!,
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Container(
                          height: 76,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: AppColors.cardWhite,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                            boxShadow: AppShadows.soft,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontSize: 22,
                                            letterSpacing: -0.4,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _todayLabel(),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.trailing != null) ...[
                                widget.trailing!,
                                const SizedBox(width: 12),
                              ],
                              if (widget.profileScreen != null)
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: _settingsButton(
                                    iconColor: AppColors.darkBrown,
                                    offset: const Offset(0, 4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: KeyedSubtree(key: contentKey, child: current),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Mobile layout
        return Scaffold(
          appBar: AppBar(
            title: Text(item.label),
            actions: [
              if (widget.trailing != null) ...[
                widget.trailing!,
                const SizedBox(width: 8),
              ],
              if (widget.profileScreen != null)
                _settingsButton(
                  iconColor: AppColors.darkBrown,
                  offset: const Offset(0, 4),
                ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: widget.hideDrawer
              ? null
              : Drawer(
                  elevation: 12,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(24),
                    ),
                  ),
                  backgroundColor: AppColors.darkBrown,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sidebarHeader(inDrawer: true),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Divider(color: Colors.white12, height: 1),
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _navList(closeDrawer: true)),
                      ],
                    ),
                  ),
                ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: widget.mobileBottomNavigation ? 90.0 : 0.0,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: KeyedSubtree(key: contentKey, child: current),
                  ),
                ),
              ),
              if (widget.mobileBottomNavigation)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: SafeArea(top: false, child: _mobileBottomNavigation()),
                ),
            ],
          ),
          bottomNavigationBar: null,
        );
      },
    ),
  );
}
}

/// Reusable hover/focus treatment for clickable menu and POS product cards.
/// Tiny "LIVE" tag shown beside a sidebar nav item (opt-in via
/// [AppShell.liveItemLabel]).
class _LiveTag extends StatelessWidget {
  final bool onLightBackground;
  const _LiveTag({required this.onLightBackground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: onLightBackground
            ? AppColors.beige
            : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'LIVE',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: onLightBackground
              ? AppColors.textMuted
              : Colors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class InteractiveProductCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const InteractiveProductCard({super.key, required this.child, this.onTap});

  @override
  State<InteractiveProductCard> createState() => _InteractiveProductCardState();
}

class _InteractiveProductCardState extends State<InteractiveProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered && widget.onTap != null;
    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: active ? 1.018 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(18),
            hoverColor: AppColors.accent.withValues(alpha: 0.07),
            splashColor: AppColors.accent.withValues(alpha: 0.16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFF7F7F7) : AppColors.cardWhite,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: active ? Colors.black : AppColors.border,
                  width: active ? 1.4 : 1,
                ),
                boxShadow: active ? AppShadows.lifted : AppShadows.soft,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Consistent image treatment for Menu/Kiosk and POS product cards.
class ProductImage extends StatelessWidget {
  final String? imageBase64;
  final double height;
  final IconData fallbackIcon;
  const ProductImage({
    super.key,
    this.imageBase64,
    this.height = 92,
    this.fallbackIcon = Icons.local_cafe_outlined,
  });

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(imageBase64!);
      } catch (_) {
        bytes = null;
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: height,
        width: double.infinity,
        color: AppColors.beige.withValues(alpha: 0.55),
        child: bytes == null
            ? Icon(fallbackIcon, size: 32, color: AppColors.textMuted)
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// Small KPI card used across dashboards. Neutral icon tile + large value.
/// ([color] is kept for API compatibility; the card stays monochrome.)
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;
  final bool trendUp;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.brown,
    this.trend,
    this.trendUp = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final tile = c.maxWidth < 170 ? 36.0 : 44.0;
          return Row(
            children: [
              Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(
                  color: AppColors.beige,
                  borderRadius: BorderRadius.circular(tile * 0.3),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.darkBrown, size: tile * 0.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                height: 1.15,
                                color: AppColors.darkBrown,
                              ),
                            ),
                          ),
                        ),
                        if (trend != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            trendUp
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 13,
                            color:
                                trendUp ? AppColors.success : AppColors.danger,
                          ),
                          Text(
                            trend!,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: trendUp
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Responsive grid of StatCards. Column count follows the width the grid
/// actually gets (not the window), so it also works in narrow dashboard columns.
class StatGrid extends StatelessWidget {
  final List<Widget> cards;
  const StatGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        var cols = w >= 700 ? 4 : (w >= 520 ? 3 : 2);
        // Avoid a ragged last row when an even count fits 2 columns cleanly.
        if (cols == 3 && cards.length % 3 != 0 && cards.length % 2 == 0)
          cols = 2;
        if (cards.isNotEmpty && cards.length < cols) cols = cards.length;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols < 1 ? 1 : cols,
            mainAxisExtent: 96,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (ctx, i) => cards[i],
        );
      },
    );
  }
}

/// Badge shown next to a customer's name when they qualify as a Loyal Customer.
class LoyalBadge extends StatelessWidget {
  final double fontSize;
  final double iconSize;
  const LoyalBadge({super.key, this.fontSize = 11, this.iconSize = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.darkBrown,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: iconSize, color: const Color(0xFFFFD700)),
          const SizedBox(width: 3),
          Text(
            'Loyal',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status pill, e.g. "Low Stock", "Paid", "Active". Its muted tone, icon dot
/// and readable label make order states easy to scan without relying on color.
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  Color _color() {
    switch (status) {
      case 'In Stock':
      case 'Active':
      case 'Paid':
      case 'Present':
      case 'Reviewed':
      case 'Restocked':
      case 'Completed':
        return AppColors.success;
      case 'Low Stock':
      case 'Pending':
      case 'Pending Verification':
      case 'Requested':
      case 'Late':
      case 'New':
      case 'Preparing':
        return AppColors.warning;
      case 'Ready':
      case 'Orders Ready':
        return AppColors.info;
      case 'Near Expiration':
        return AppColors.warning;
      case 'Out of Stock':
      case 'Expired':
      case 'Disabled':
      case 'Absent':
      case 'Declined':
      case 'Cancelled':
        return AppColors.danger;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: c.withValues(alpha: 0.25), spreadRadius: 2),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Monochrome notice / alert banner (icon tile + title + message + optional
/// action). Replaces ad-hoc tinted Cards so alerts match the black & white theme.
class NoticeBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 520;
        final tile = Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.darkBrown,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: Colors.white),
        );
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AppColors.darkBrown,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF495057),
              ),
            ),
          ],
        );
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.darkBrown.withValues(alpha: 0.18),
            ),
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tile,
                        const SizedBox(width: 12),
                        Expanded(child: text),
                      ],
                    ),
                    if (action != null)
                      Align(alignment: Alignment.centerRight, child: action!),
                  ],
                )
              : Row(
                  children: [
                    tile,
                    const SizedBox(width: 14),
                    Expanded(child: text),
                    if (action != null) ...[const SizedBox(width: 12), action!],
                  ],
                ),
        );
      },
    );
  }
}

/// A page scaffold with padding + scrolling used inside AppShell tabs.
/// Content is centered and capped at a readable width on very wide screens.
class SectionPage extends StatelessWidget {
  final String? subtitle;
  final List<Widget> children;
  final Widget? action;
  const SectionPage({
    super.key,
    this.subtitle,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return SingleChildScrollView(
      padding: wide
          ? const EdgeInsets.fromLTRB(28, 24, 28, 32)
          : const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtitle != null || action != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    children: [
                      if (subtitle != null)
                        Expanded(
                          child: Text(
                            subtitle!,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (action != null) action!,
                    ],
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared footer for [ResponsiveTable] and [PaginatedList]: range summary on
/// the left, bordered prev/next buttons on the right.
class _PageBar extends StatelessWidget {
  final int total, start, end, page, maxPage;
  final VoidCallback? onPrev, onNext;
  final bool attached; // true = footer of a table card (tinted, top border)
  const _PageBar({
    required this.total,
    required this.start,
    required this.end,
    required this.page,
    required this.maxPage,
    required this.onPrev,
    required this.onNext,
    this.attached = true,
  });

  Widget _btn(IconData icon, String tip, VoidCallback? onTap) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        side: BorderSide(
          color: onTap == null ? Colors.transparent : AppColors.border,
        ),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = Text(
      total == 0 ? 'No results' : 'Showing ${start + 1}–$end of $total',
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: attached ? 16 : 4,
        vertical: attached ? 10 : 8,
      ),
      decoration: attached
          ? const BoxDecoration(
              color: Color(0xFFFAFAFB),
              border: Border(top: BorderSide(color: AppColors.border)),
            )
          : null,
      child: Row(
        children: [
          Expanded(child: summary),
          if (maxPage > 0) ...[
            _btn(Icons.chevron_left_rounded, 'Previous page', onPrev),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${page + 1} / ${maxPage + 1}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkBrown,
                ),
              ),
            ),
            _btn(Icons.chevron_right_rounded, 'Next page', onNext),
          ],
        ],
      ),
    );
  }
}

/// Wraps a DataTable in horizontal scroll so it behaves on small screens.
/// Paginates its rows automatically — pass the FULL row list and this
/// widget slices it into pages with Prev/Next controls at the bottom.
/// Shows an empty state when there are no rows.
class ResponsiveTable extends StatefulWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final int rowsPerPage;
  const ResponsiveTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rowsPerPage = 10,
  });

  @override
  State<ResponsiveTable> createState() => _ResponsiveTableState();
}

class _ResponsiveTableState extends State<ResponsiveTable> {
  int _page = 0;

  int get _maxPage =>
      widget.rows.isEmpty ? 0 : (widget.rows.length - 1) ~/ widget.rowsPerPage;

  @override
  void didUpdateWidget(covariant ResponsiveTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If filtering/searching shrank the list (or data changed) enough that
    // the current page no longer exists, snap back to the last valid page.
    if (_page > _maxPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = _maxPage);
      });
    }
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.beige,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.inbox_outlined,
              size: 26,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No records found',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.darkBrown,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try adjusting your search or filters.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.rows.length;
    final start = (_page * widget.rowsPerPage).clamp(0, total).toInt();
    final end = (start + widget.rowsPerPage).clamp(0, total).toInt();
    final pageRows = widget.rows.sublist(start, end);

    return LayoutBuilder(
      builder: (context, constraints) {
        final colCount = widget.columns.length;
        final calcSpacing = colCount > 0
            ? (constraints.maxWidth / colCount - 50)
                .clamp(16.0, 44.0)
                .toDouble()
            : 24.0;

        return Material(
          color: AppColors.cardWhite,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    columns: widget.columns,
                    rows: pageRows,
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF1F3F5),
                    ),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: Color(0xFF495057),
                      letterSpacing: 0.3,
                    ),
                    dataTextStyle: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.darkBrown,
                    ),
                    headingRowHeight: 46,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 72,
                    columnSpacing: calcSpacing,
                    horizontalMargin: 20,
                    dividerThickness: 1,
                    border: const TableBorder(
                      horizontalInside: BorderSide(
                        color: Color(0x12000000),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
              if (total == 0) _emptyState(),
              if (total > 0)
                _PageBar(
                  total: total,
                  start: start,
                  end: end,
                  page: _page,
                  maxPage: _maxPage,
                  onPrev: _page > 0 ? () => setState(() => _page--) : null,
                  onNext:
                      _page < _maxPage ? () => setState(() => _page++) : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Paginates any list of items rendered as widgets (e.g. Cards), showing
/// [pageSize] at a time with the same Prev/Next page bar as [ResponsiveTable].
/// Use this for screens that build a Column of Cards via `.map()` instead of
/// a DataTable.
class PaginatedList<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final int pageSize;
  const PaginatedList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.pageSize = 6,
  });

  @override
  State<PaginatedList<T>> createState() => _PaginatedListState<T>();
}

class _PaginatedListState<T> extends State<PaginatedList<T>> {
  int _page = 0;

  int get _maxPage =>
      widget.items.isEmpty ? 0 : (widget.items.length - 1) ~/ widget.pageSize;

  @override
  void didUpdateWidget(covariant PaginatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page > _maxPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = _maxPage);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final total = widget.items.length;
    final start = (_page * widget.pageSize).clamp(0, total).toInt();
    final end = (start + widget.pageSize).clamp(0, total).toInt();
    final pageItems = widget.items.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in pageItems) widget.itemBuilder(context, item),
        if (widget.items.length > widget.pageSize)
          _PageBar(
            attached: false,
            total: total,
            start: start,
            end: end,
            page: _page,
            maxPage: _maxPage,
            onPrev: _page > 0 ? () => setState(() => _page--) : null,
            onNext: _page < _maxPage ? () => setState(() => _page++) : null,
          ),
      ],
    );
  }
}

/// Notification bell with unread badge + dropdown panel, shared by Admin/Employee shells.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  IconData _iconFor(String type) {
    switch (type) {
      case 'Inventory':
        return Icons.inventory_2_outlined;
      case 'Menu':
        return Icons.restaurant_menu_outlined;
      case 'Expiration':
        return Icons.timer_outlined;
      case 'POS':
        return Icons.point_of_sale_outlined;
      case 'Feedback':
        return Icons.star_outline;
      case 'Payroll':
        return Icons.payments_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  void _showNotificationsMenu(
    BuildContext context,
    AppData data,
    RenderBox button,
  ) async {
    data.markAllNotificationsRead();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final selectedType = await showMenu<String>(
      context: context,
      position: position,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: data.notifications.isEmpty
          ? [
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('No notifications'),
              ),
            ]
          : data.notifications.take(8).map((n) {
              return PopupMenuItem<String>(
                value: n.type,
                child: SizedBox(
                  width: 280,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_iconFor(n.type), size: 18, color: AppColors.darkBrown),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              n.body,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textMuted),
                    ],
                  ),
                ),
              );
            }).toList(),
    );

    if (selectedType != null && context.mounted) {
      final shell = AppShell.of(context);
      if (shell != null) {
        final user = AppData.instance.currentUser;
        final isAdmin = user?.role == UserRole.admin;

        String targetLabel = 'Dashboard';
        if (selectedType == 'Inventory' || selectedType == 'Expiration') {
          targetLabel = isAdmin ? 'Inventory Management' : 'Inventory';
        } else if (selectedType == 'Menu') {
          targetLabel = 'Menu Management';
        } else if (selectedType == 'POS') {
          targetLabel = 'POS';
        } else if (selectedType == 'Feedback') {
          targetLabel = 'Customer Feedback';
        } else if (selectedType == 'Payroll') {
          targetLabel = isAdmin ? 'Payroll Management' : 'Payroll';
        }
        shell.selectTabByLabel(targetLabel);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        return Builder(
          builder: (ctx) {
            return Tooltip(
              message: 'Notifications',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  final button = ctx.findRenderObject() as RenderBox?;
                  if (button != null) {
                    _showNotificationsMenu(context, data, button);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.darkBrown,
                      ),
                      if (data.unreadNotifications > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '${data.unreadNotifications}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Message button with unread badge for the header bar.
class MessagingButton extends StatelessWidget {
  const MessagingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;
        final user = data.currentUser;
        final currentRole = (user != null && user.fullName.trim().isNotEmpty)
            ? user.fullName.trim()
            : 'Admin';
        final unreadCount = data.unreadMessagesCount;

        return Tooltip(
          message: 'Messages',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              final shell = AppShell.of(context);
              if (shell != null) {
                (shell as dynamic).selectTabByLabel('Messaging');
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MessagingPage(currentRole: currentRole),
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_outlined, color: AppColors.darkBrown),
                  if (unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Standalone route page wrapper for MessagingScreen when opened from header button.
class MessagingPage extends StatelessWidget {
  final String currentRole;
  const MessagingPage({super.key, required this.currentRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text('Messaging'),
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.darkBrown,
        elevation: 0,
      ),
      body: MessagingScreen(currentRole: currentRole),
    );
  }
}

/// Header trailing actions (Messaging icon + Notification bell) shared by Admin and Employee shells.
class HeaderActions extends StatelessWidget {
  const HeaderActions({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MessagingButton(),
        SizedBox(width: 8),
        PendingOrdersButton(),
        SizedBox(width: 8),
        LoyalCustomersButton(),
        SizedBox(width: 8),
        NotificationBell(),
      ],
    );
  }
}

/// Pending orders button with badge count for the header bar.
class PendingOrdersButton extends StatelessWidget {
  const PendingOrdersButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        final pendingCount = AppData.instance.kioskOrders
            .where((o) => o.status == 'Pending')
            .length;

        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => const PendingOrdersModal(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Tooltip(
              message: 'Pending Orders',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.darkBrown,
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$pendingCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Star rating display (read-only) or input (editable).
class StarRating extends StatelessWidget {
  final int rating;
  final double size;
  final ValueChanged<int>? onChanged;
  const StarRating({
    super.key,
    required this.rating,
    this.size = 20,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating;
        final star = Icon(
          filled ? Icons.star : Icons.star_border,
          color: AppColors.accent,
          size: size,
        );
        if (onChanged == null) return star;
        return InkWell(onTap: () => onChanged!(i + 1), child: star);
      }),
    );
  }
}

Widget confirmDialogButton(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Color confirmColor,
  required VoidCallback onConfirm,
}) {
  return TextButton(
    onPressed: () {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: confirmColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: confirmColor),
          ),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                onConfirm();
              },
              style: FilledButton.styleFrom(backgroundColor: confirmColor),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
    child: Text(
      confirmLabel,
      style: TextStyle(color: confirmColor, fontWeight: FontWeight.w700),
    ),
  );
}

/// Formats a message's sent time the way chat apps do: a bare time for
/// today, "Yesterday, h:mm a" for the previous day, a weekday name for the
/// rest of the past week, and a short date beyond that.
String formatChatTimestamp(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(dt.year, dt.month, dt.day);
  final diffDays = today.difference(msgDay).inDays;

  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  final time = '$hour12:$minute $period';

  if (diffDays == 0) {
    return time;
  } else if (diffDays == 1) {
    return 'Yesterday, $time';
  } else if (diffDays > 1 && diffDays < 7) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[dt.weekday - 1]}, $time';
  } else {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, $time';
  }
}

/// Formatter for name fields:
/// 1. Disallows leading space.
/// 2. Disallows 2 or more consecutive spaces (single space only between words).
/// 3. Capitalizes the first letter of each word (Title Case).
/// 4. Filters out invalid characters (allows only letters, spaces, hyphens, apostrophes).
class NameTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    // Disallow leading space
    if (text.startsWith(' ')) {
      return oldValue;
    }

    // Disallow 2 or more consecutive spaces
    if (text.contains('  ')) {
      return oldValue;
    }

    // Allow only letters, spaces, hyphens, and apostrophes
    if (text.isNotEmpty &&
        !RegExp(r"^[\p{L}\p{M}\s\-']*$", unicode: true).hasMatch(text)) {
      return oldValue;
    }

    String formatted = _formatName(text);

    return TextEditingValue(text: formatted, selection: newValue.selection);
  }

  String _formatName(String text) {
    if (text.isEmpty) return text;

    final buffer = StringBuffer();
    bool capitalizeNext = true;

    for (int i = 0; i < text.length; i++) {
      String char = text[i];
      if (char == ' ' || char == '-' || char == "'") {
        buffer.write(char);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }
}

String? validateFirstName(String? v) {
  if (v == null || v.trim().isEmpty) return 'First name is required';
  final trimmed = v.trim();
  if (v.contains('  ')) return 'Double spaces are not allowed';
  if (trimmed.length < 2) return 'Must be at least 2 letters';
  if (!RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(trimmed)) {
    return 'First name can only contain letters';
  }
  return null;
}

String? validateLastName(String? v) {
  if (v == null || v.trim().isEmpty) return 'Last name is required';
  final trimmed = v.trim();
  if (v.contains('  ')) return 'Double spaces are not allowed';
  if (trimmed.length < 2) return 'Must be at least 2 letters';
  if (!RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(trimmed)) {
    return 'Last name can only contain letters';
  }
  return null;
}

void showAppSnack(BuildContext context, String message, {bool success = true}) {
  try {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final animationController = AnimationController(
      vsync: overlayState,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 250),
    );

    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    final fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOut,
    ));

    void removeOverlay() {
      if (!animationController.isAnimating && animationController.status != AnimationStatus.dismissed) {
        animationController.reverse().then((_) {
          if (overlayEntry.mounted) {
            overlayEntry.remove();
          }
          animationController.dispose();
        });
      }
    }

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SlideTransition(
              position: slideAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: removeOverlay,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  success ? 'SUCCESS' : 'NOTICE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  message,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                            onPressed: removeOverlay,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Dismiss',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlayEntry);
    animationController.forward();

    Future.delayed(const Duration(seconds: 4), () {
      removeOverlay();
    });
  } catch (_) {}
}

class CancelOrderDialog extends StatefulWidget {
  final OrderRecord order;
  const CancelOrderDialog({super.key, required this.order});

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
  static const List<String> _presetReasons = [
    'Changed my mind',
    'Ordered by mistake',
    'Wait time is too long',
    'Selected wrong item or add-on',
    'Need to change payment / order type',
    'Other reason',
  ];

  String _selectedReason = _presetReasons[0];
  final TextEditingController _customReasonController = TextEditingController();

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.cardWhite,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cancel Order #${o.displayOrderNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                      color: AppColors.darkBrown,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please select a reason for cancelling your order:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.darkBrown,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._presetReasons.map((reason) {
                      return RadioListTile<String>(
                        title: Text(reason, style: const TextStyle(fontSize: 13, color: AppColors.darkBrown)),
                        value: reason,
                        groupValue: _selectedReason,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.darkBrown,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedReason = val);
                          }
                        },
                      );
                    }),
                    if (_selectedReason == 'Other reason') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customReasonController,
                        autofocus: true,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Specify your reason *',
                          hintText: 'Type your reason here...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Keep Order'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    String finalReason = _selectedReason;
                    if (_selectedReason == 'Other reason') {
                      final custom = _customReasonController.text.trim();
                      if (custom.isEmpty) {
                        showAppSnack(
                          context,
                          'Please specify your reason for cancelling.',
                          success: false,
                        );
                        return;
                      }
                      finalReason = custom;
                    }
                    Navigator.pop(context, finalReason);
                  },
                  child: const Text('Confirm Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class OvernightCafeLogo extends StatelessWidget {
  final double size;
  final bool isDark;
  const OvernightCafeLogo({super.key, this.size = 32, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: Image.asset(
        'assets/images/logo.png',
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (ctx, err, stack) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size * 0.8,
              height: size * 0.8,
              decoration: BoxDecoration(
                color: isDark ? Colors.white : AppColors.darkBrown,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                'o',
                style: TextStyle(
                  color: isDark ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.6,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'overnight.cafe',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.darkBrown,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  const CustomDateRangePickerDialog({super.key, this.initialRange});

  @override
  State<CustomDateRangePickerDialog> createState() =>
      _CustomDateRangePickerDialogState();
}

class _CustomDateRangePickerDialogState
    extends State<CustomDateRangePickerDialog> {
  late DateTime _focusedMonth;
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedPreset = 'Custom';

  bool _isRangeToday(DateTimeRange? range) {
    if (range == null) return false;
    final now = DateTime.now();
    return range.start.year == now.year &&
        range.start.month == now.month &&
        range.start.day == now.day &&
        range.end.year == now.year &&
        range.end.month == now.month &&
        range.end.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (widget.initialRange == null || _isRangeToday(widget.initialRange)) {
      _startDate = today;
      _endDate = today;
      _selectedPreset = 'Today';
    } else {
      _startDate = widget.initialRange!.start;
      _endDate = widget.initialRange!.end;
      _selectedPreset = 'Custom';
    }
    _focusedMonth = DateTime(_startDate!.year, _startDate!.month, 1);
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedPreset = preset;
      switch (preset) {
        case 'Today':
          _startDate = today;
          _endDate = today;
          break;
        case 'Yesterday':
          final y = today.subtract(const Duration(days: 1));
          _startDate = y;
          _endDate = y;
          break;
        case 'Last 7 days':
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = today;
          break;
        case 'Last 30 days':
          _startDate = today.subtract(const Duration(days: 29));
          _endDate = today;
          break;
        case 'This month':
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = today;
          break;
        case 'Last month':
          final lastMonth = DateTime(today.year, today.month - 1, 1);
          final lastDayOfLastMonth = DateTime(today.year, today.month, 0);
          _startDate = lastMonth;
          _endDate = lastDayOfLastMonth;
          break;
        case 'Last year':
          _startDate = DateTime(today.year - 1, 1, 1);
          _endDate = DateTime(today.year - 1, 12, 31);
          break;
        case 'Custom':
          break;
        case 'All':
          _startDate = null;
          _endDate = null;
          break;
      }
      if (_startDate != null) {
        _focusedMonth = DateTime(_startDate!.year, _startDate!.month, 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final firstDayOfMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      1,
    );
    final startingWeekday =
        (firstDayOfMonth.weekday - 1) % 7; // Mon = 0, Sun = 6

    const presets = [
      'Today',
      'Yesterday',
      'Last 7 days',
      'Last 30 days',
      'This month',
      'Last month',
      'Last year',
      'Custom',
      'All',
    ];

    final screenWidth = MediaQuery.of(context).size.width;
    final mobile = screenWidth < 600;

    Widget buildCalendarArea({bool isMobile = false}) {
      return Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: Column(
          children: [
            // Month navigation header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month - 1,
                        1,
                      );
                    });
                  },
                ),
                Text(
                  '${monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 14 : 15,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month + 1,
                        1,
                      );
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: isMobile ? 6 : 12),
            // Weekday headers
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children:
                  ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                      .map(
                        (d) => SizedBox(
                          width: 32,
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isMobile ? 11 : 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
            SizedBox(height: isMobile ? 6 : 8),
            // Days grid
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 0,
                ),
                itemCount: 42,
                itemBuilder: (context, index) {
                  final dayOffset = index - startingWeekday;
                  final date = DateTime(
                    _focusedMonth.year,
                    _focusedMonth.month,
                    1 + dayOffset,
                  );
                  final isCurrentMonth =
                      date.month == _focusedMonth.month;

                  final normalizedDate = DateTime(
                    date.year,
                    date.month,
                    date.day,
                  );
                  final startNormalized = _startDate != null
                      ? DateTime(
                          _startDate!.year,
                          _startDate!.month,
                          _startDate!.day,
                        )
                      : null;
                  final endNormalized = _endDate != null
                      ? DateTime(
                          _endDate!.year,
                          _endDate!.month,
                          _endDate!.day,
                        )
                      : null;

                  final isStart = startNormalized != null &&
                      normalizedDate.isAtSameMomentAs(startNormalized);
                  final isEnd = endNormalized != null &&
                      normalizedDate.isAtSameMomentAs(endNormalized);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPreset = 'Custom';
                        if (_startDate == null ||
                            (_startDate != null && _endDate != null)) {
                          _startDate = date;
                          _endDate = null;
                        } else if (_startDate != null &&
                            _endDate == null) {
                          if (date.isBefore(_startDate!)) {
                            _startDate = date;
                          } else {
                            _endDate = date;
                          }
                        }
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (isSelected(
                          normalizedDate,
                          startNormalized,
                          endNormalized,
                        ))
                            ? const Color(0xFFF1F3F5)
                            : Colors.transparent,
                        borderRadius: isStart && _endDate == null
                            ? BorderRadius.circular(20)
                            : (isStart
                                ? const BorderRadius.horizontal(
                                    left: Radius.circular(20),
                                  )
                                : (isEnd
                                    ? const BorderRadius.horizontal(
                                        right: Radius.circular(20),
                                      )
                                    : null)),
                      ),
                      child: Container(
                        width: isMobile ? 28 : 32,
                        height: isMobile ? 28 : 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (isStart || isEnd)
                              ? const Color(0xFF1E222B)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: isMobile ? 11.5 : 12.5,
                            fontWeight: (isStart || isEnd)
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: (isStart || isEnd)
                                ? Colors.white
                                : (isCurrentMonth
                                    ? Colors.black87
                                    : Colors.grey.shade400),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    Widget buildApplyButton({bool isMobile = false}) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E222B),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            if (_selectedPreset == 'All') {
              Navigator.pop(context, null);
            } else if (_startDate != null && _endDate != null) {
              Navigator.pop(
                context,
                DateTimeRange(start: _startDate!, end: _endDate!),
              );
            } else if (_startDate != null) {
              Navigator.pop(
                context,
                DateTimeRange(start: _startDate!, end: _startDate!),
              );
            } else {
              Navigator.pop(context);
            }
          },
          child: Text(
            'Apply',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 13 : 13.5,
            ),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: mobile ? 360 : 620,
        height: mobile ? 500 : 440,
        color: Colors.white,
        child: mobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: presets.map((preset) {
                          final isSelected = _selectedPreset == preset;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => _applyPreset(preset),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF1E222B) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isSelected ? const Color(0xFF1E222B) : Colors.grey.shade300),
                                ),
                                child: Text(
                                  preset,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: buildCalendarArea(isMobile: true),
                  ),
                  buildApplyButton(isMobile: true),
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      border: Border(right: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            children: presets.map((preset) {
                              final isSelected = _selectedPreset == preset;
                              return InkWell(
                                onTap: () => _applyPreset(preset),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius:
                                        isSelected ? BorderRadius.circular(8) : null,
                                  ),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        preset,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? Colors.black
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.black,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        buildApplyButton(isMobile: false),
                      ],
                    ),
                  ),
                  Expanded(
                    child: buildCalendarArea(isMobile: false),
                  ),
                ],
              ),
      ),
    );
  }

  bool isSelected(DateTime date, DateTime? start, DateTime? end) {
    if (start == null) return false;
    if (end == null) return date.isAtSameMomentAs(start);
    return (date.isAfter(start) || date.isAtSameMomentAs(start)) &&
        (date.isBefore(end) || date.isAtSameMomentAs(end));
  }
}

class TitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
    if (text.length > 20) {
      text = text.substring(0, 20);
    }
    final words = text.split(' ');
    final capitalizedWords = words.map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() +
          (word.length > 1 ? word.substring(1).toLowerCase() : '');
    });
    final formatted = capitalizedWords.join(' ');

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class DateMaskTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String clean = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length > 8) {
      clean = clean.substring(0, 8);
    }

    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i == 2 || i == 4) {
        buffer.write('/');
      }
      buffer.write(clean[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

Future<DateTime?> showCustomExpirationDatePicker(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) =>
        CustomExpirationDatePickerDialog(initialDate: initialDate),
  );
}

class CustomExpirationDatePickerDialog extends StatefulWidget {
  final DateTime? initialDate;
  const CustomExpirationDatePickerDialog({super.key, this.initialDate});

  @override
  State<CustomExpirationDatePickerDialog> createState() =>
      _CustomExpirationDatePickerDialogState();
}

class _CustomExpirationDatePickerDialogState
    extends State<CustomExpirationDatePickerDialog> {
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  String _selectedPreset = 'Custom';
  late TextEditingController _typeDateController;
  String? _typeDateError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = widget.initialDate ?? now.add(const Duration(days: 30));
    _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    _typeDateController = TextEditingController(
      text:
          '${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.year}',
    );
  }

  @override
  void dispose() {
    _typeDateController.dispose();
    super.dispose();
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedPreset = preset;
      DateTime target;
      switch (preset) {
        case '10 Days Later':
          target = today.add(const Duration(days: 10));
          break;
        case '3 Months Later':
          target = DateTime(today.year, today.month + 3, today.day);
          break;
        case '6 Months Later':
          target = DateTime(today.year, today.month + 6, today.day);
          break;
        case '1 Year Later':
          target = DateTime(today.year + 1, today.month, today.day);
          break;
        case '2 Years Later':
          target = DateTime(today.year + 2, today.month, today.day);
          break;
        case 'Custom':
        default:
          return;
      }
      _selectedDate = target;
      _focusedMonth = DateTime(target.year, target.month, 1);
      _typeDateController.text =
          '${target.month.toString().padLeft(2, '0')}/${target.day.toString().padLeft(2, '0')}/${target.year}';
      _typeDateError = null;
    });
  }

  void _onDaySelected(DateTime date) {
    setState(() {
      _selectedPreset = 'Custom';
      _selectedDate = date;
      _typeDateController.text =
          '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
      _typeDateError = null;
    });
  }

  void _onTypedDateChanged(String val) {
    setState(() {
      _selectedPreset = 'Custom';
      final clean = val.trim();
      if (clean.length < 10) {
        _typeDateError = null;
        return;
      }
      final parts = clean.split('/');
      if (parts.length == 3 &&
          parts[0].length == 2 &&
          parts[1].length == 2 &&
          parts[2].length == 4) {
        final m = int.tryParse(parts[0]);
        final d = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (m != null &&
            d != null &&
            y != null &&
            m >= 1 &&
            m <= 12 &&
            d >= 1 &&
            d <= 31 &&
            y >= 2024 &&
            y <= 2100) {
          try {
            final parsed = DateTime(y, m, d);
            _selectedDate = parsed;
            _focusedMonth = DateTime(y, m, 1);
            _typeDateError = null;
            return;
          } catch (_) {}
        }
      }
      _typeDateError = 'Invalid date (MM/DD/YYYY)';
    });
  }

  @override
  Widget build(BuildContext context) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final firstDayOfMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      1,
    );
    final startingWeekday =
        (firstDayOfMonth.weekday - 1) % 7; // Mon = 0, Sun = 6

    const presets = [
      '10 Days Later',
      '3 Months Later',
      '6 Months Later',
      '1 Year Later',
      '2 Years Later',
      'Custom',
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 630,
        height: 480,
        color: Colors.white,
        child: Row(
          children: [
            // Left Sidebar Presets
            Container(
              width: 180,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: presets.map((preset) {
                        final isSelected = _selectedPreset == preset;
                        return InkWell(
                          onTap: () => _applyPreset(preset),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius:
                                  isSelected ? BorderRadius.circular(8) : null,
                            ),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  preset,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.black
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E222B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (_selectedPreset == 'Custom' &&
                            _typeDateController.text.trim().length != 10) {
                          setState(() {
                            _typeDateError = 'Invalid date (MM/DD/YYYY)';
                          });
                          return;
                        }
                        if (_typeDateError != null) return;
                        Navigator.pop(context, _selectedDate);
                      },
                      child: const Text(
                        'Apply',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Right Calendar Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Month navigation header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          onPressed: () {
                            setState(() {
                              _focusedMonth = DateTime(
                                _focusedMonth.year,
                                _focusedMonth.month - 1,
                                1,
                              );
                            });
                          },
                        ),
                        Text(
                          '${monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 20),
                          onPressed: () {
                            setState(() {
                              _focusedMonth = DateTime(
                                _focusedMonth.year,
                                _focusedMonth.month + 1,
                                1,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Weekday headers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children:
                          ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                              .map(
                                (d) => SizedBox(
                                  width: 32,
                                  child: Text(
                                    d,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 8),
                    // Days grid
                    Expanded(
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 0,
                        ),
                        itemCount: 42,
                        itemBuilder: (context, index) {
                          final dayOffset = index - startingWeekday;
                          final date = DateTime(
                            _focusedMonth.year,
                            _focusedMonth.month,
                            1 + dayOffset,
                          );
                          final isCurrentMonth =
                              date.month == _focusedMonth.month;

                          final isSelected = date.year == _selectedDate.year &&
                              date.month == _selectedDate.month &&
                              date.day == _selectedDate.day;

                          return InkWell(
                            onTap: () => _onDaySelected(date),
                            child: Container(
                              alignment: Alignment.center,
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF1E222B)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.white
                                        : (isCurrentMonth
                                            ? Colors.black87
                                            : Colors.grey.shade400),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Custom Date Text Field
                    TextField(
                      controller: _typeDateController,
                      maxLength: 10,
                      inputFormatters: [DateMaskTextInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Type Expiration Date (MM/DD/YYYY)',
                        errorText: _typeDateError,
                        counterText: '',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(
                          Icons.edit_calendar_outlined,
                          size: 18,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: _onTypedDateChanged,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper dialog to confirm exiting the application.
Future<bool> showExitConfirmationDialog(BuildContext context) async {
  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Exit App'),
      content: const Text('Are you sure you want to exit Overnight Cafe?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Exit'),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await SystemNavigator.pop();
    return true;
  }
  return false;
}

/// Helper widget that intercepts back button presses on root/entry screens
/// and shows a confirmation modal before exiting the app.
class ExitConfirmationPopScope extends StatelessWidget {
  final Widget child;
  final Future<bool> Function()? onBack;

  const ExitConfirmationPopScope({
    super.key,
    required this.child,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (onBack != null) {
          final handled = await onBack!();
          if (handled) return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        await showExitConfirmationDialog(context);
      },
      child: child,
    );
  }
}

Future<bool?> showEmailOtpDialog({
  required BuildContext context,
  required AppUser user,
  required String newEmail,
}) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EmailOtpDialog(user: user, newEmail: newEmail),
  );
}

class _EmailOtpDialog extends StatefulWidget {
  final AppUser user;
  final String newEmail;
  const _EmailOtpDialog({required this.user, required this.newEmail});

  @override
  State<_EmailOtpDialog> createState() => _EmailOtpDialogState();
}

class _EmailOtpDialogState extends State<_EmailOtpDialog> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _controllers.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });

    final err = await AppData.instance.verifyOtp(widget.user.id, code);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _verifying = false;
        _error = err;
      });
    } else {
      Navigator.pop(context, true);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await AppData.instance.sendEmailChangeOtp(widget.user, widget.newEmail);
      if (!mounted) return;
      setState(() {
        _resending = false;
        _error = null;
      });
      showAppSnack(context, 'A new code was sent to ${widget.newEmail}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _error = 'Failed to resend code: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Verify New Email'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A 6-digit verification code was sent to:\n${widget.newEmail}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: SizedBox(
                      width: 42,
                      child: TextField(
                        controller: _controllers[i],
                        focusNode: _nodes[i],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkBrown,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: AppColors.beige.withValues(alpha: 0.5),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.lightBrown.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.brown,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          if (v.isNotEmpty && i < 5) {
                            _nodes[i + 1].requestFocus();
                          }
                          if (v.isEmpty && i > 0) {
                            _nodes[i - 1].requestFocus();
                          }
                          if (v.isNotEmpty && i == 5) {
                            _verify();
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: _resending ? null : _resend,
              child: Text(
                _resending ? 'Sending...' : 'Resend Code',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _verifying ? null : _verify,
          child: _verifying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Verify & Save'),
        ),
      ],
    );
  }
}

Future<void> showEnlargedQrDialog(BuildContext context, String base64Str, {bool showSaveButton = true}) async {
  try {
    final bytes = base64Decode(base64Str);
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'GCash QR Code',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkBrown),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320, maxWidth: 320),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (showSaveButton) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkBrown,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    try {
                      final result = await FilePicker.platform.saveFile(
                        dialogTitle: 'Save GCash QR Code',
                        fileName: 'gcash_qr_code.png',
                        bytes: bytes,
                        type: FileType.image,
                      );
                      if (ctx.mounted && result != null) {
                        showAppSnack(ctx, 'QR Code image saved successfully!');
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        showAppSnack(ctx, 'Failed to save image: $e');
                      }
                    }
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Save / Download QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  } catch (e) {
    debugPrint('Error decoding/showing QR code dialog: $e');
  }
}


