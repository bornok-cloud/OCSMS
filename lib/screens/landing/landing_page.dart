import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter, PointMode;
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../auth/login_screen.dart';

// ---------------------------------------------------------------------------
// Design tokens — one source of truth for the landing page.
// Palette stays strictly black / white / grey (see AppColors).
//   desktop : >= 900  (two-column hero / about / footer)
//   tablet  : 600–899 (single column, roomy spacing)
//   mobile  : < 600   (single column, compact spacing)
// ---------------------------------------------------------------------------
const double _kMaxContentWidth = 1200;
const double _kTwoColumnBreakpoint = 900;
const double _kMobileBreakpoint = 600;
const double _kNavBreakpoint = 720;

const Color _kInk = Color(0xFF0A0A0A); // near-black used for dark sections
const Color _kBodyText = Color(0xFF495057); // body copy grey on light surfaces
const Color _kLine = Color(0x1F000000); // hairline on light surfaces
const double _kCardRadius = 24;

const String _kPhone = '0955-422-0644';
const String _kEmail = 'overnightcafee@gmail.com';
const String _kFacebook = 'Overnight Cafe';
const String _kInstagram = '@overnightcafee';
const String _kAddress = 'Brgy. Calumpang, Liliw, Laguna';
const String _kHours = '7:00 PM – 2:00 AM';

/// Horizontal page gutter that scales with the viewport.
double _pagePad(double width) {
  if (width >= _kTwoColumnBreakpoint) return 40;
  if (width >= _kMobileBreakpoint) return 28;
  return 20;
}

/// The café is open 7 PM – 2 AM every day (spans midnight).
bool _isOpenNow() {
  final h = DateTime.now().hour;
  return h >= 19 || h < 2;
}

void _goToLogin(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _aboutKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _contactKey = GlobalKey();
  final _scrollController = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 8;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kInk,
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            _Hero(
              onViewMenu: () => _scrollTo(_menuKey),
              onLogo: _scrollToTop,
              onAbout: () => _scrollTo(_aboutKey),
              onMenu: () => _scrollTo(_menuKey),
              onContact: () => _scrollTo(_contactKey),
            ),
            Container(key: _aboutKey, child: const _AboutSection()),
            // Rebuilds live when products stream in from Firestore.
            Container(
              key: _menuKey,
              child: ListenableBuilder(
                listenable: AppData.instance,
                builder: (context, _) => _MenuSection(products: List<Product>.of(AppData.instance.products)),
              ),
            ),
            _FinalCta(onLogin: () => _goToLogin(context)),
            Container(key: _contactKey, child: const _ContactFooter()),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// SHARED: buttons, eyebrow label, section wrapper
// ===========================================================================
class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool inverted; // true = white button (for black surfaces)
  final bool outlined;
  final bool compact;
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.inverted = false,
    this.outlined = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? (inverted ? Colors.white : _kInk) : (inverted ? _kInk : Colors.white);
    final bg = outlined ? Colors.transparent : (inverted ? Colors.white : _kInk);
    final borderColor = inverted ? Colors.white.withValues(alpha: 0.35) : _kInk.withValues(alpha: 0.6);
    final overlay = (outlined ? fg : (inverted ? _kInk : Colors.white)).withValues(alpha: 0.08);

    final style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(bg),
      foregroundColor: WidgetStatePropertyAll(fg),
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: WidgetStatePropertyAll(Size(0, compact ? 42 : 54)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: compact ? 20 : 28, vertical: 0)),
      shape: WidgetStatePropertyAll(StadiumBorder(
        side: outlined ? BorderSide(color: borderColor, width: 1.3) : BorderSide.none,
      )),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: compact ? 13.5 : 15, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      ),
      overlayColor: WidgetStatePropertyAll(overlay),
    );

    return ElevatedButton(
      style: style,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Icon(icon, size: compact ? 16 : 18),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  final bool onDark;
  const _Eyebrow(this.text, {this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white.withValues(alpha: 0.65) : AppColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 24, height: 1.5, color: color),
        const SizedBox(width: 10),
        Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.2, color: color),
        ),
      ],
    );
  }
}

/// Full-bleed background + centered, max-width content with responsive padding.
class _Section extends StatelessWidget {
  final Color color;
  final Widget child;
  final double topDesktop, bottomDesktop, topMobile, bottomMobile;
  const _Section({
    required this.color,
    required this.child,
    this.topDesktop = 104,
    this.bottomDesktop = 104,
    this.topMobile = 64,
    this.bottomMobile = 64,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = width < _kMobileBreakpoint;
    final pad = _pagePad(width);
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.fromLTRB(pad, mobile ? topMobile : topDesktop, pad, mobile ? bottomMobile : bottomDesktop),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: child,
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  const _Brand({required this.onTap, required this.compact});

  static const String _asset = 'assets/images/logo_white_cropped.png';
  static const double _aspect = 6250 / 1563;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 36.0 : 48.0;
    return Semantics(
      button: true,
      label: 'Overnight Cafe — back to top',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: SizedBox(
            width: h * _aspect,
            height: h,
            child: Image.asset(
              _asset,
              height: h,
              width: h * _aspect,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

// ===========================================================================
// HERO — full-bleed black "night" scene: headline + CTAs + tonight card
// ===========================================================================
class _Hero extends StatelessWidget {
  final VoidCallback onViewMenu;
  final VoidCallback onLogo;
  final VoidCallback onAbout;
  final VoidCallback onMenu;
  final VoidCallback onContact;

  const _Hero({
    required this.onViewMenu,
    required this.onLogo,
    required this.onAbout,
    required this.onMenu,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final twoCol = w >= _kTwoColumnBreakpoint;
    final mobile = w < _kMobileBreakpoint;
    final narrow = w < 440;
    final showLinks = w >= _kNavBreakpoint;

    final headlineSize = twoCol ? 68.0 : (mobile ? 42.0 : 56.0);

    final headerRow = Row(
      children: [
        _Brand(onTap: onLogo, compact: mobile),
        const Spacer(),
        if (showLinks) ...[
          _NavLink('About', onAbout),
          _NavLink('Menu', onMenu),
          _NavLink('Contact', onContact),
        ],
      ],
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _OpenStatusPill(),
        SizedBox(height: mobile ? 24 : 32),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Every cup tells a story. '),
              TextSpan(text: 'Best after dark.', style: TextStyle(color: Colors.white.withValues(alpha: 0.45))),
            ],
          ),
          style: TextStyle(
            fontSize: headlineSize,
            fontWeight: FontWeight.w900,
            height: 1.04,
            letterSpacing: headlineSize * -0.035,
            color: Colors.white,
          ),
        ),
        SizedBox(height: mobile ? 20 : 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'A street-style café for night owls, shift workers, and friends — handcrafted coffee and comforting snacks in a relaxed, curbside spot.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.65,
              fontSize: mobile ? 15.5 : 17,
            ),
          ),
        ),
        SizedBox(height: mobile ? 28 : 40),
        _HeroButtons(onViewMenu: onViewMenu, stacked: narrow),
      ],
    );

    return Container(
      width: double.infinity,
      color: _kInk,
      child: Stack(
        children: [
          const Positioned.fill(child: ClipRect(child: CustomPaint(painter: _NightBackdropPainter()))),
          _Section(
            color: Colors.transparent,
            topDesktop: 48,
            bottomDesktop: 112,
            topMobile: 24,
            bottomMobile: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                headerRow,
                SizedBox(height: mobile ? 36 : 56),
                twoCol
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 6, child: copy),
                          const SizedBox(width: 64),
                          const Expanded(flex: 4, child: _TonightCard()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          copy,
                          SizedBox(height: mobile ? 40 : 56),
                          const _TonightCard(),
                        ],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroButtons extends StatelessWidget {
  final VoidCallback onViewMenu;
  final bool stacked;
  const _HeroButtons({required this.onViewMenu, required this.stacked});

  @override
  Widget build(BuildContext context) {
    final viewMenu = _PillButton(
      label: 'View Menu',
      icon: Icons.arrow_downward_rounded,
      inverted: true,
      onPressed: onViewMenu,
    );
    final login = _PillButton(
      label: 'Login',
      icon: Icons.arrow_forward_rounded,
      inverted: true,
      outlined: true,
      onPressed: () => _goToLogin(context),
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [viewMenu, const SizedBox(height: 12), login],
      );
    }
    return Wrap(spacing: 14, runSpacing: 12, children: [viewMenu, login]);
  }
}

/// Small pill above the headline. State is conveyed by text + icon shape,
/// not by color alone.
class _OpenStatusPill extends StatelessWidget {
  const _OpenStatusPill();

  @override
  Widget build(BuildContext context) {
    final open = _isOpenNow();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(open ? Icons.circle : Icons.circle_outlined, size: 9, color: Colors.white),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              open ? 'Open now · until 2:00 AM' : 'Opens tonight · 7:00 PM',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// White "ticket" card on the black hero: hours, days, location, phone.
class _TonightCard extends StatelessWidget {
  const _TonightCard();

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < _kMobileBreakpoint;
    final open = _isOpenNow();

    return Container(
      padding: EdgeInsets.all(mobile ? 24 : 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kCardRadius),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 20))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'TONIGHT',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.2, color: AppColors.textMuted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: open ? _kInk : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _kInk, width: 1.2),
                ),
                child: Text(
                  open ? 'Open now' : 'Closed',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: open ? Colors.white : _kInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _kHours,
              style: TextStyle(fontSize: mobile ? 30 : 36, fontWeight: FontWeight.w900, letterSpacing: -1, color: _kInk, height: 1.1),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Monday – Sunday', style: TextStyle(fontSize: 14.5, color: _kBodyText, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          const Divider(color: _kLine, height: 1),
          const SizedBox(height: 20),
          const _CardRow(icon: Icons.location_on_outlined, label: 'Find us', value: _kAddress),
          const SizedBox(height: 16),
          const _CardRow(icon: Icons.phone_outlined, label: 'Call', value: _kPhone),
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _CardRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.beige, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: _kInk),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _kInk, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dot grid + crescent moon drawn behind the hero (matches the logo mark).
class _NightBackdropPainter extends CustomPainter {
  const _NightBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Dot grid
    const step = 30.0;
    final points = <Offset>[];
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Crescent moon (big circle minus an offset circle)
    final r = (size.width * 0.22).clamp(120.0, 300.0).toDouble();
    final center = Offset(size.width - r * 0.9, r * 1.05);
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
      Path()..addOval(Rect.fromCircle(center: center.translate(r * 0.42, -r * 0.22), radius: r * 0.86)),
    );
    canvas.drawPath(moon, Paint()..color = Colors.white.withValues(alpha: 0.10));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// ABOUT — editorial two-column: story left, audience list right
// ===========================================================================
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final twoCol = w >= _kTwoColumnBreakpoint;
    final mobile = w < _kMobileBreakpoint;

    final story = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Eyebrow('About us'),
        const SizedBox(height: 20),
        Text(
          'A café for the hours the city sleeps through.',
          style: TextStyle(
            fontSize: twoCol ? 44 : (mobile ? 30 : 38),
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: -1.4,
            color: _kInk,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Overnight Cafe is a street-style café concept that operates exclusively '
          'during the night hours, inspired by its namesake. It targets night owls, '
          'shift workers, and friends looking for a casual, late-night gathering spot. '
          'Provides a relaxed outdoor or curbside environment to sip coffee, '
          'converse, and unwind after standard business hours.',
          style: TextStyle(color: _kBodyText, height: 1.75, fontSize: mobile ? 15.5 : 17),
        ),
      ],
    );

    const audience = _AudienceList(items: [
      _AudienceItem('Night owls', 'A late-night spot that comes alive once standard business hours end.'),
      _AudienceItem('Shift workers', 'Coffee and comforting snacks when the rest of the day has already closed.'),
      _AudienceItem('Friends', 'Relaxed curbside seating made for long conversations and slow sips.'),
    ]);

    return _Section(
      color: Colors.white,
      child: twoCol
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: story),
                const SizedBox(width: 80),
                const Expanded(flex: 5, child: audience),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [story, SizedBox(height: mobile ? 40 : 56), audience],
            ),
    );
  }
}

class _AudienceItem {
  final String title, text;
  const _AudienceItem(this.title, this.text);
}

class _AudienceList extends StatelessWidget {
  final List<_AudienceItem> items;
  const _AudienceList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              border: Border(
                top: const BorderSide(color: _kLine),
                bottom: i == items.length - 1 ? const BorderSide(color: _kLine) : BorderSide.none,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: _kInk),
                      ),
                      const SizedBox(height: 6),
                      Text(items[i].text, style: const TextStyle(fontSize: 15.5, height: 1.6, color: _kBodyText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// MENU — category filter + responsive grid, with empty state
// ===========================================================================
class _MenuSection extends StatefulWidget {
  final List<Product> products;
  const _MenuSection({required this.products});

  @override
  State<_MenuSection> createState() => _MenuSectionState();
}

class _MenuSectionState extends State<_MenuSection> {
  static const _all = 'All';
  String _selected = _all;
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = width < _kMobileBreakpoint;

    final categories = widget.products.map((p) => p.category).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    // If the selected category vanished (e.g. live update), fall back to All.
    final selected = categories.contains(_selected) ? _selected : _all;
    final visible = selected == _all ? widget.products : widget.products.where((p) => p.category == selected).toList();

    // 3x3 on laptop/desktop (9 items), 2x3 on mobile/phone (6 items)
    final cols = mobile ? 2 : 3;
    final itemsPerPage = cols * 3; // 6 for mobile (2x3), 9 for desktop (3x3)
    final totalPages = (visible.length / itemsPerPage).ceil().clamp(1, 9999);

    final currentPage = _currentPage.clamp(0, totalPages - 1);
    final startIndex = currentPage * itemsPerPage;
    final endIndex = (startIndex + itemsPerPage).clamp(0, visible.length);
    final pagedItems = visible.sublist(startIndex, endIndex);

    return _Section(
      color: AppColors.cream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: Alignment.centerLeft, child: _Eyebrow('Menu')),
          const SizedBox(height: 20),
          Text(
            'Our Menu',
            style: TextStyle(
              fontSize: mobile ? 34 : 48,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
              height: 1.05,
              color: _kInk,
            ),
          ),
          if (categories.length > 1) ...[
            SizedBox(height: mobile ? 24 : 32),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in [_all, ...categories]) ...[
                    _FilterChip(
                      label: c,
                      selected: c == selected,
                      onTap: () {
                        setState(() {
                          _selected = c;
                          _currentPage = 0;
                        });
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(height: mobile ? 24 : 36),
          if (visible.isEmpty)
            _MenuEmptyState(hasProducts: widget.products.isNotEmpty)
          else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pagedItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: mobile ? 102 : 96,
                crossAxisSpacing: mobile ? 10 : 16,
                mainAxisSpacing: mobile ? 10 : 16,
              ),
              itemBuilder: (ctx, i) => _MenuCard(product: pagedItems[i]),
            ),
            if (totalPages > 1) ...[
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    color: currentPage > 0 ? _kInk : Colors.grey.shade400,
                    onPressed: currentPage > 0
                        ? () => setState(() => _currentPage = currentPage - 1)
                        : null,
                  ),
                  const SizedBox(width: 4),
                  if (mobile) ...[
                    for (int i = 0; i < totalPages; i++) ...[
                      InkWell(
                        onTap: () => setState(() => _currentPage = i),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: i == currentPage ? 16 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == currentPage ? _kInk : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    for (int i = 0; i < totalPages; i++) ...[
                      InkWell(
                        onTap: () => setState(() => _currentPage = i),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i == currentPage ? _kInk : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: i == currentPage ? _kInk : _kLine),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: i == currentPage ? Colors.white : _kInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    color: currentPage < totalPages - 1 ? _kInk : Colors.grey.shade400,
                    onPressed: currentPage < totalPages - 1
                        ? () => setState(() => _currentPage = currentPage + 1)
                        : null,
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter: $label',
      child: Material(
        color: selected ? _kInk : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? _kInk : _kLine, width: 1.2)),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : _kInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuEmptyState extends StatelessWidget {
  final bool hasProducts;
  const _MenuEmptyState({required this.hasProducts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_cafe_outlined, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            hasProducts ? 'Nothing in this category yet' : 'Our menu is being prepared',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _kInk),
          ),
          const SizedBox(height: 6),
          Text(
            hasProducts ? 'Try another category.' : 'Check back soon for tonight\'s lineup.',
            style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatefulWidget {
  final Product product;
  const _MenuCard({required this.product});

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = width < _kMobileBreakpoint;
    final p = widget.product;
    final soldOut = p.isOutOfStock;

    Uint8List? imageBytes;
    if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) {
      try {
        imageBytes = base64Decode(p.imageBase64!);
      } catch (_) {
        imageBytes = null;
      }
    }

    final imgSize = mobile ? 50.0 : 60.0;
    final nameSize = mobile ? 12.5 : 16.0;
    final catSize = mobile ? 10.5 : 13.0;
    final priceSize = mobile ? 12.5 : 16.0;
    final padH = mobile ? 8.0 : 14.0;
    final padV = mobile ? 8.0 : 12.0;
    final spacing = mobile ? 8.0 : 12.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hover ? _kInk.withValues(alpha: 0.55) : _kLine),
          boxShadow: _hover ? AppShadows.lifted : const <BoxShadow>[],
        ),
        child: Opacity(
          opacity: soldOut ? 0.55 : 1,
          child: mobile
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: imgSize,
                      height: imgSize,
                      decoration: BoxDecoration(color: AppColors.beige, borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: imageBytes != null
                          ? Image.memory(
                              imageBytes,
                              width: imgSize,
                              height: imgSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => p.emoji.isNotEmpty
                                  ? Text(p.emoji, style: const TextStyle(fontSize: 22))
                                  : const Icon(Icons.local_cafe_outlined, color: AppColors.brown, size: 20),
                            )
                          : (p.emoji.isNotEmpty
                              ? Text(p.emoji, style: const TextStyle(fontSize: 22))
                              : const Icon(Icons.local_cafe_outlined, color: AppColors.brown, size: 20)),
                    ),
                    SizedBox(width: spacing),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: nameSize, letterSpacing: -0.2, color: _kInk),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: catSize, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                peso(p.price),
                                maxLines: 1,
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: priceSize, letterSpacing: -0.3, color: _kInk),
                              ),
                              if (soldOut) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: _kInk.withValues(alpha: 0.5)),
                                  ),
                                  child: const Text('Sold out', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _kInk)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(color: AppColors.beige, borderRadius: BorderRadius.circular(16)),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: imageBytes != null
                          ? Image.memory(
                              imageBytes,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => p.emoji.isNotEmpty
                                  ? Text(p.emoji, style: const TextStyle(fontSize: 28))
                                  : const Icon(Icons.local_cafe_outlined, color: AppColors.brown, size: 26),
                            )
                          : (p.emoji.isNotEmpty
                              ? Text(p.emoji, style: const TextStyle(fontSize: 28))
                              : const Icon(Icons.local_cafe_outlined, color: AppColors.brown, size: 26)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2, color: _kInk),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            p.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          peso(p.price),
                          maxLines: 1,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3, color: _kInk),
                        ),
                        if (soldOut) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: _kInk.withValues(alpha: 0.5)),
                            ),
                            child: const Text('Sold out', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _kInk)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ===========================================================================
// FINAL CTA — black band inviting the visitor to log in
// ===========================================================================
class _FinalCta extends StatelessWidget {
  final VoidCallback onLogin;
  const _FinalCta({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final twoCol = w >= _kTwoColumnBreakpoint;
    final mobile = w < _kMobileBreakpoint;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Come by after dark.',
          style: TextStyle(
            fontSize: twoCol ? 52 : (mobile ? 34 : 44),
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: -1.6,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '$_kAddress · Open daily, $_kHours',
          style: TextStyle(fontSize: mobile ? 15 : 17, height: 1.5, color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );

    final button = _PillButton(label: 'Login', icon: Icons.arrow_forward_rounded, inverted: true, onPressed: onLogin);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kInk,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
      ),
      child: _Section(
        color: Colors.transparent,
        topDesktop: 88,
        bottomDesktop: 88,
        topMobile: 56,
        bottomMobile: 56,
        child: twoCol
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Expanded(child: text), const SizedBox(width: 40), button],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, SizedBox(height: mobile ? 28 : 32), button],
              ),
      ),
    );
  }
}

// ===========================================================================
// FOOTER — brand, contact, visit
// ===========================================================================
class _ContactFooter extends StatelessWidget {
  const _ContactFooter();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final twoCol = w >= _kTwoColumnBreakpoint;
    final mobile = w < _kMobileBreakpoint;

    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo_white_cropped.png', height: 44, filterQuality: FilterQuality.high),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Handcrafted coffee and comforting snacks for the night owls.',
            style: TextStyle(fontSize: 14.5, height: 1.6, color: Colors.white.withValues(alpha: 0.65)),
          ),
        ),
      ],
    );

    const contact = _FooterColumn(
      title: 'Get in touch',
      children: [
        _FooterLine(icon: Icon(Icons.phone_outlined, color: Colors.white, size: 18), label: _kPhone),
        _FooterLine(icon: Icon(Icons.email_outlined, color: Colors.white, size: 18), label: _kEmail),
        _FooterLine(icon: Icon(Icons.facebook, color: Colors.white, size: 18), label: _kFacebook),
        _FooterLine(icon: InstagramIcon(size: 18, color: Colors.white), label: _kInstagram),
      ],
    );

    const visit = _FooterColumn(
      title: 'Visit us',
      children: [
        _FooterLine(icon: Icon(Icons.access_time, color: Colors.white, size: 18), label: 'Monday – Sunday\n$_kHours'),
        _FooterLine(icon: Icon(Icons.location_on_outlined, color: Colors.white, size: 18), label: _kAddress),
      ],
    );

    return _Section(
      color: _kInk,
      topDesktop: 72,
      bottomDesktop: 36,
      topMobile: 48,
      bottomMobile: 28,
      child: Column(
        children: [
          if (twoCol)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: brand),
                const SizedBox(width: 40),
                const Expanded(flex: 4, child: contact),
                const SizedBox(width: 40),
                const Expanded(flex: 3, child: visit),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                brand,
                SizedBox(height: mobile ? 36 : 44),
                contact,
                SizedBox(height: mobile ? 32 : 40),
                visit,
              ],
            ),
          SizedBox(height: mobile ? 36 : 56),
          const SizedBox(width: double.infinity, child: Divider(color: Colors.white24, height: 1)),
          const SizedBox(height: 20),
          const Text(
            '© 2026 Overnight Cafe. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _FooterColumn({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.2, color: Colors.white.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          children[i],
        ],
      ],
    );
  }
}

class _FooterLine extends StatelessWidget {
  final Widget icon;
  final String label;
  const _FooterLine({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          alignment: Alignment.center,
          child: icon,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Instagram glyph (kept public — Material icons don't ship one)
// ===========================================================================
class InstagramIcon extends StatelessWidget {
  final double size;
  final Color color;
  const InstagramIcon({super.key, this.size = 18, this.color = AppColors.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color, width: size * 0.12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.38,
            height: size * 0.38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: size * 0.10),
            ),
          ),
          Positioned(
            top: size * 0.10,
            right: size * 0.10,
            child: Container(
              width: size * 0.12,
              height: size * 0.12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
