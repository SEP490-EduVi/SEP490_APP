import 'package:flutter/material.dart';

class GameResultScreen extends StatelessWidget {
  final Map<String, dynamic> result;
  final String packageTitle;
  final VoidCallback? onPlayAgain;

  const GameResultScreen({
    super.key,
    required this.result,
    required this.packageTitle,
    this.onPlayAgain,
  });

  @override
  Widget build(BuildContext context) {
    final status = (result['status'] as String?) ?? 'completed';
    final score = (result['score'] as num?)?.toInt() ?? 0;
    final durationMs = (result['durationMs'] as num?)?.toInt() ?? 0;
    final accuracy = (result['accuracy'] as num?)?.toDouble();
    final completedAt = result['completedAt'] as String?;
    final correct = (result['correct'] as num?)?.toInt();
    final total = (result['total'] as num?)?.toInt();

    final isCompleted = status == 'completed';
    final isFailed = status == 'failed';

    final statusColor = isCompleted
        ? const Color(0xFF16A34A)
        : isFailed
            ? const Color(0xFFDC2626)
            : const Color(0xFFD97706);

    final statusBg = isCompleted
        ? const Color(0xFFDCFCE7)
        : isFailed
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFEF3C7);

    final statusLabel = isCompleted
        ? 'Hoàn thành'
        : isFailed
            ? 'Thất bại'
            : 'Đã thoát';

    final statusIcon = isCompleted
        ? Icons.emoji_events_rounded
        : isFailed
            ? Icons.cancel_rounded
            : Icons.exit_to_app_rounded;

    String formatDuration(int ms) {
      if (ms <= 0) return '—';
      final totalSec = ms ~/ 1000;
      final min = totalSec ~/ 60;
      final sec = totalSec % 60;
      if (min == 0) return '${sec}s';
      return '${min}m ${sec.toString().padLeft(2, '0')}s';
    }

    String formatCompleted(String? iso) {
      if (iso == null) return '';
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) return iso;
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$d/$mo/${dt.year} $h:$mi';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F6FF),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF8FBFF), Color(0xFFECF2FF)],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header icon
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: statusBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.15),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(statusIcon, size: 48, color: statusColor),
                    ),
                    const SizedBox(height: 20),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Title
                    Text(
                      'Kết quả: $packageTitle',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    if (completedAt != null && completedAt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        formatCompleted(completedAt),
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    // Stats card
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFAFFFFFF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDDE8F5)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x08000000),
                            blurRadius: 20,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _StatRow(
                            icon: Icons.stars_rounded,
                            iconColor: const Color(0xFFD97706),
                            iconBg: const Color(0xFFFEF3C7),
                            label: 'Điểm số',
                            value: score > 0 ? '$score%' : (correct != null && total != null && total > 0 ? '$correct/$total câu đúng' : '0'),
                            valueStyle: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                            ),
                            isFirst: true,
                          ),
                          if (correct != null && total != null && total > 0 && score > 0) ...[
                            const Divider(
                              height: 1,
                              color: Color(0xFFF1F5F9),
                              indent: 20,
                              endIndent: 20,
                            ),
                            _StatRow(
                              icon: Icons.check_circle_rounded,
                              iconColor: const Color(0xFF16A34A),
                              iconBg: const Color(0xFFDCFCE7),
                              label: 'Câu đúng',
                              value: '$correct / $total',
                            ),
                          ],
                          const Divider(
                            height: 1,
                            color: Color(0xFFF1F5F9),
                            indent: 20,
                            endIndent: 20,
                          ),
                          _StatRow(
                            icon: Icons.center_focus_strong_rounded,
                            iconColor: const Color(0xFF2563EB),
                            iconBg: const Color(0xFFEFF6FF),
                            label: 'Độ chính xác',
                            value: accuracy != null
                                ? '${(accuracy * 100).toStringAsFixed(1)}%'
                                : '—',
                          ),
                          const Divider(
                            height: 1,
                            color: Color(0xFFF1F5F9),
                            indent: 20,
                            endIndent: 20,
                          ),
                          _StatRow(
                            icon: Icons.timer_rounded,
                            iconColor: const Color(0xFF7C3AED),
                            iconBg: const Color(0xFFF5F3FF),
                            label: 'Thời gian chơi',
                            value: formatDuration(durationMs),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.home_rounded, size: 20),
                            label: const Text('Về trang chủ'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF475569),
                              side: const BorderSide(
                                color: Color(0xFFCBD5E1),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        if (onPlayAgain != null) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onPlayAgain!();
                              },
                              icon: const Icon(
                                Icons.replay_rounded,
                                size: 20,
                              ),
                              label: const Text('Chơi lại'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                elevation: 2,
                                shadowColor: const Color(0x402563EB),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final TextStyle? valueStyle;
  final bool isFirst;
  final bool isLast;

  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    this.valueStyle,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        isFirst ? 20 : 14,
        20,
        isLast ? 20 : 14,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: valueStyle ??
                const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
