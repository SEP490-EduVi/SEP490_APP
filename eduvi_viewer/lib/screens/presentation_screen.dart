import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/eduvi_schema.dart';
import '../models/presentation_adapter.dart';
import '../services/asset_service.dart';
import '../widgets/slide_viewer.dart';

class PresentationScreen extends StatefulWidget {
  final EduViSchema schema;
  final int initialSlideIndex;
  final ValueChanged<int>? onExitSlideChanged;

  const PresentationScreen({
    super.key,
    required this.schema,
    this.initialSlideIndex = 0,
    this.onExitSlideChanged,
  });

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  late final PageController _pageController;
  late final AssetService _assetService;
  late int _currentPage;
  bool _hasKeyboardFocus = false;
  bool _leftZoneHovered = false;
  bool _rightZoneHovered = false;

  int get _totalPages => widget.schema.cards.length;
  bool get _hasSlides => _totalPages > 0;
  bool get _canGoNext => _currentPage + 1 < _totalPages;
  bool get _canGoPrev => _currentPage > 0;

  bool get _shouldBlockSpaceNavigation {
    final card = widget.schema.slideAt(_currentPage);
    return card?.hasLearningInteractiveBlocks ?? false;
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.schema.clampSlideIndex(widget.initialSlideIndex);
    _pageController = PageController(initialPage: _currentPage);
    _assetService = AssetService(widget.schema.assets);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToPage(int page) async {
    if (page < 0 || page >= _totalPages || page == _currentPage) return;
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() => _goToPage(_currentPage + 1);
  void _prev() => _goToPage(_currentPage - 1);
  void _goToSlide(int index) => _goToPage(index);

  void _exitPresentation() {
    widget.onExitSlideChanged?.call(_currentPage);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop<int>(_currentPage);
    }
  }

  bool _isTypingInTextField() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;

    if (focusedContext.widget is EditableText) {
      return true;
    }

    return focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_hasSlides) return KeyEventResult.ignored;
    if (_isTypingInTextField()) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.space &&
        _shouldBlockSpaceNavigation) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
        _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _prev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _exitPresentation();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSlides) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8F6),
        body: Center(
          child: Text(
            'Không có slide để trình chiếu',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final viewPadding = MediaQuery.paddingOf(context);
    final topBarOffset = viewPadding.top;
    final topBarHeight = 48.0;
    final bottomOverlaySpacing = math.max(16.0, viewPadding.bottom + 10);
    final contentTop = topBarOffset + topBarHeight;
    final edgeZoneWidth = math.max(
      30.0,
      MediaQuery.sizeOf(context).width * 0.05,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: Focus(
        autofocus: true,
        onFocusChange: (hasFocus) {
          if (_hasKeyboardFocus != hasFocus) {
            setState(() => _hasKeyboardFocus = hasFocus);
          }
        },
        onKeyEvent: _handleKey,
        child: Stack(
          key: const Key('presentation-mode-root'),
          children: [
            Positioned.fill(
              top: contentTop,
              bottom: bottomOverlaySpacing + 18,
              child: PageView.builder(
                key: const Key('presentation-page-view'),
                controller: _pageController,
                itemCount: _totalPages,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, index) {
                  final card = widget.schema.cards[index];
                  return SlideViewer(
                    key: ValueKey(card.id),
                    card: card,
                    assetService: _assetService,
                    onNextSlide: _next,
                    presentationMode: true,
                    isActiveSlide: index == _currentPage,
                    allowUserInteraction: card.hasUserInteractiveBlocks,
                  );
                },
              ),
            ),
            Positioned(
              top: topBarOffset,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            Positioned.fill(
              top: contentTop,
              child: Row(
                children: [
                  SizedBox(
                    width: edgeZoneWidth,
                    child: _EdgeNavigationZone(
                      icon: Icons.chevron_left,
                      enabled: _canGoPrev,
                      showIcon: _leftZoneHovered || _hasKeyboardFocus,
                      onTap: _prev,
                      onHoverChanged: (hovered) {
                        if (_leftZoneHovered != hovered) {
                          setState(() => _leftZoneHovered = hovered);
                        }
                      },
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: edgeZoneWidth,
                    child: _EdgeNavigationZone(
                      icon: Icons.chevron_right,
                      enabled: _canGoNext,
                      showIcon: _rightZoneHovered || _hasKeyboardFocus,
                      onTap: _next,
                      onHoverChanged: (hovered) {
                        if (_rightZoneHovered != hovered) {
                          setState(() => _rightZoneHovered = hovered);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: bottomOverlaySpacing,
              left: 0,
              right: 0,
              child: _buildProgressDots(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final title = widget.schema.metadata.title.trim().isEmpty
        ? 'Untitled'
        : widget.schema.metadata.title.trim();

    return Container(
      key: const Key('presentation-top-bar'),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.black.withValues(alpha: 0.8),
      child: Row(
        children: [
          IconButton(
            key: const Key('presentation-exit-button'),
            onPressed: _exitPresentation,
            tooltip: 'Thoát trình chiếu',
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_currentPage + 1}/$_totalPages',
            key: const Key('presentation-slide-counter'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildProgressDots() {
    return Center(
      child: Container(
        key: const Key('presentation-dot-indicator'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_totalPages, (i) {
            final isActive = i == _currentPage;
            return GestureDetector(
              onTap: () => _goToSlide(i),
              behavior: HitTestBehavior.translucent,
              child: AnimatedContainer(
                key: Key('presentation-dot-$i'),
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.98)
                      : Colors.white.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _EdgeNavigationZone extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool showIcon;
  final VoidCallback onTap;
  final ValueChanged<bool> onHoverChanged;

  const _EdgeNavigationZone({
    required this.icon,
    required this.enabled,
    required this.showIcon,
    required this.onTap,
    required this.onHoverChanged,
  });

  bool get _hoverEnabled {
    if (kIsWeb) {
      return true;
    }
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _hoverEnabled ? (_) => onHoverChanged(true) : null,
      onExit: _hoverEnabled ? (_) => onHoverChanged(false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: showIcon ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: enabled ? 0.35 : 0.2),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Icon(
                icon,
                size: 22,
                color: enabled
                    ? Colors.white.withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
