import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_windows/webview_windows.dart';

String? extractYouTubeId(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final idOnly = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  if (idOnly.hasMatch(text)) return text;

  final patterns = <RegExp>[
    RegExp(r'(?:youtube\.com/(?:[^/]+/.+/|(?:v|embed)/|.*[?&]v=)|youtu\.be/)([^"&?/\s]{11})', caseSensitive: false),
    RegExp(r'youtube\.com/shorts/([^"&?/\s]{11})', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      final id = match.group(1);
      if (id != null && idOnly.hasMatch(id)) return id;
    }
  }

  return null;
}

String buildYouTubeEmbedUrl(String videoId) {
  return 'https://www.youtube-nocookie.com/embed/$videoId?rel=0&modestbranding=1';
}

class YouTubeBlockWidget extends StatefulWidget {
  final String source;
  final String title;

  const YouTubeBlockWidget({
    super.key,
    required this.source,
    this.title = 'YouTube Video',
  });

  @override
  State<YouTubeBlockWidget> createState() => _YouTubeBlockWidgetState();
}

class _YouTubeBlockWidgetState extends State<YouTubeBlockWidget> {
  final WebviewController _controller = WebviewController();
  bool _ready = false;
  String? _error;
  bool _launchedExternal = false;

  String? get _videoId => extractYouTubeId(widget.source);

  String get _watchUrl {
    final id = _videoId;
    if (id == null) return widget.source;
    return 'https://www.youtube.com/watch?v=$id';
  }

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      final id = _videoId;
      if (id == null) {
        setState(() => _error = 'Khong trich xuat duoc YouTube ID.');
        return;
      }

      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.loadUrl(buildYouTubeEmbedUrl(id));

      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Khong the mo YouTube nhung: $e');
        if (!_launchedExternal) {
          _launchedExternal = true;
          launchUrlString(_watchUrl, mode: LaunchMode.externalApplication);
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0xFF0B1220),
          child: Stack(
            children: [
              if (_ready) Positioned.fill(child: Webview(_controller)),
              if (!_ready && _error == null)
                const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_error != null)
                _FallbackPanel(
                  title: widget.title,
                  message: _error!,
                  url: _watchUrl,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FallbackPanel extends StatelessWidget {
  final String title;
  final String message;
  final String url;

  const _FallbackPanel({
    required this.title,
    required this.message,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_display, size: 42, color: Colors.white70),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => launchUrlString(url, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Mo YouTube tren trinh duyet'),
            ),
          ],
        ),
      ),
    );
  }
}
