import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/desktop_notification_center.dart';

class DesktopNotificationOverlay extends StatelessWidget {
  const DesktopNotificationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Consumer<DesktopNotificationCenter>(
      builder: (context, center, child) {
        if (center.items.isEmpty) {
          return const SizedBox.shrink();
        }

        return DefaultTextStyle.merge(
          style: textTheme.bodySmall,
          child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topRight,
          child: center.collapsed
              ? _CollapsedPill(
                  count: center.items.length,
                  onTap: center.toggleCollapsed,
                )
              : _NotificationPanel(
                  items: center.items,
                  onCollapse: center.toggleCollapsed,
                  onDismiss: center.dismiss,
                  onClearAll: center.clearAll,
                ),
          ),
        );
      },
    );
  }
}

class _CollapsedPill extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _CollapsedPill({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: (textTheme.labelMedium ?? const TextStyle()).copyWith(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  final List<DesktopNotification> items;
  final VoidCallback onCollapse;
  final ValueChanged<int> onDismiss;
  final VoidCallback onClearAll;

  const _NotificationPanel({
    required this.items,
    required this.onCollapse,
    required this.onDismiss,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.notifications, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notifications',
                    style: (textTheme.titleSmall ?? const TextStyle()).copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClearAll,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[400],
                    textStyle: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                      fontSize: 11,
                    ),
                  ),
                  child: const Text('Clear'),
                ),
                IconButton(
                  icon: const Icon(Icons.expand_less, color: Colors.white, size: 18),
                  onPressed: onCollapse,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _NotificationCard(
                  item: item,
                  onDismiss: () => onDismiss(item.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final DesktopNotification item;
  final VoidCallback onDismiss;

  const _NotificationCard({required this.item, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasProgress = item.maxProgress > 1 && !item.isComplete;
    final progress = hasProgress
        ? (item.progress / item.maxProgress).clamp(0.0, 1.0)
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: (textTheme.labelMedium ?? const TextStyle()).copyWith(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: onDismiss,
              ),
            ],
          ),
          Text(
            item.body,
            style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: Colors.grey[400],
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasProgress) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[850],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
            ),
          ],
          if (item.isComplete) ...[
            const SizedBox(height: 6),
            Text(
              'Completed',
              style: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                color: Colors.grey[500],
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
