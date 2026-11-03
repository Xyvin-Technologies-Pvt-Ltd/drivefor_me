import 'package:DriveForme/src/interfaces/main_pages/support/support_pages.dart';
import 'package:DriveForme/src/data/apis/notification_api.dart';
import 'package:DriveForme/src/data/apis/trip_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/notification_model.dart';
import 'package:DriveForme/src/data/providers/notification_provider.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/utils/trip_navigation.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: kScreenBg,
      appBar: AppBar(
        backgroundColor: kWhite,
        surfaceTintColor: kWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Align(
            alignment: Alignment.center,
            child: _RoundBackButton(
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        title: Text(
          'Notifications',
          style: kStyle(kSemiBold, kSize18, color: kBrandBlue),
        ),
      ),
      body: notificationsAsync.when(
        loading: () => const _NotificationsShimmer(),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: kStyle(kRegular, kSize15, color: kMutedText),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(notificationsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 56,
                    color: kMutedText.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No notifications yet.',
                    style: kStyle(kRegular, kSize15, color: kMutedText),
                  ),
                ],
              ),
            );
          }

          final sections = _groupByDate(notifications);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView(
              children: [
                for (final section in sections) ...[
                  _DateHeader(label: section.dateLabel),
                  for (var i = 0; i < section.items.length; i++) ...[
                    _DismissibleNotificationTile(
                      item: section.items[i],
                      onTap: () =>
                          _onNotificationTap(context, ref, section.items[i]),
                      onDelete: () =>
                          _deleteNotification(context, ref, section.items[i]),
                    ),
                    if (i < section.items.length - 1)
                      const Divider(height: 1, indent: 72, color: kLineGrey),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onNotificationTap(
    BuildContext context,
    WidgetRef ref,
    NotificationModel item,
  ) async {
    if (!item.isRead) {
      final response = await ref
          .read(notificationApiProvider)
          .markAsRead(item.id);
      if (!response.success && context.mounted) {
        showAppSnackBar(
          context,
          response.message ?? 'Failed to mark as read.',
        );
      }
      ref.invalidate(notificationsProvider);
    }

    if (!context.mounted) return;
    if (item.type == 'support' ||
        item.payload['action'] == 'open_support_chat') {
      final ticketId = item.payload['ticketId']?.toString();
      if (ticketId != null && RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(ticketId)) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SupportChatPage(ticketId: ticketId),
          ),
        );
      }
      return;
    }

    if (item.type != 'trip_accepted' &&
        item.type != 'trip_reassigned' &&
        item.type != 'driver_assigned' &&
        item.type != 'trip_cancelled') {
      return;
    }

    final tripId = item.payload['tripId']?.toString();
    if (tripId == null || tripId.isEmpty) return;

    final tripResponse = await ref.read(tripApiProvider).getTripById(tripId);
    if (!context.mounted) return;

    if (!tripResponse.success || tripResponse.data == null) {
      showAppSnackBar(
        context,
        tripResponse.message ?? 'Could not load trip details.',
      );
      return;
    }

    final trip = tripResponse.data!;
    if (trip.isCancelled) {
      NavigationService().pushNamed(
        'cancelled_trip_details',
        arguments: trip.toCancelledDetailsArguments(),
      );
      return;
    }

    final target = tripNavigationTarget(trip);
    if (target == null) return;

    NavigationService().pushNamed(target.route, arguments: target.arguments);
  }

  Future<void> _deleteNotification(
    BuildContext context,
    WidgetRef ref,
    NotificationModel item,
  ) async {
    final response = await ref
        .read(notificationApiProvider)
        .deleteNotification(item.id);
    if (!context.mounted) return;

    if (!response.success) {
      showAppSnackBar(context, response.message ?? 'Failed to delete.');
      return;
    }

    ref.invalidate(notificationsProvider);
  }

  List<_NotificationSection> _groupByDate(List<NotificationModel> items) {
    final sorted = [...items]
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    final map = <String, List<NotificationModel>>{};
    for (final item in sorted) {
      final label = item.dateSectionLabel;
      map.putIfAbsent(label, () => []).add(item);
    }

    return map.entries
        .map(
          (entry) =>
              _NotificationSection(dateLabel: entry.key, items: entry.value),
        )
        .toList();
  }
}

class _NotificationsShimmer extends StatelessWidget {
  const _NotificationsShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: kShimmerBaseColor,
          highlightColor: kWhite,
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: kShimmerBaseColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationSection {
  final String dateLabel;
  final List<NotificationModel> items;

  const _NotificationSection({required this.dateLabel, required this.items});
}

class _DateHeader extends StatelessWidget {
  final String label;

  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(label, style: kTripNotificationTimeM),
    );
  }
}

class _DismissibleNotificationTile extends StatelessWidget {
  final NotificationModel item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DismissibleNotificationTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: kRed,
        child: const Icon(Icons.delete_outline, color: kWhite),
      ),
      onDismissed: (_) => onDelete(),
      child: _NotificationTile(item: item, onTap: onTap, onDelete: onDelete),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: item.isRead ? kWhite : kActiveGreenBg.withValues(alpha: 0.25),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kTripCloseBtnBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: kBrandBlue,
                    ),
                  ),
                  if (!item.isRead)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: kRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: kTripNotificationBodyR.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(item.body, style: kTripNotificationBodyR),
                    const SizedBox(height: 6),
                    Text(item.timeAgo, style: kTripNotificationTimeM),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.close, size: 20, color: kMutedText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RoundBackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kTripCloseBtnBg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.chevron_left_rounded, size: 28, color: kTextColor),
        ),
      ),
    );
  }
}
