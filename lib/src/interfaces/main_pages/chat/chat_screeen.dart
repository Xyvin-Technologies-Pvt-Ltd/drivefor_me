import 'dart:async';

import 'package:DriveForme/src/data/apis/chat_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/chat_message_model.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? tripId;
  final String participantName;

  const ChatScreen({
    super.key,
    this.receiverId = '',
    this.receiverName = TripModel.noNameFound,
    this.tripId,
    this.participantName = TripModel.noNameFound,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _quickReplies = [
    "I've Arrived",
    "I'm on my way !",
    "Where are you ?",
  ];

  static const _chipBg = AppColors.chatChipBackground;
  static const _inputBorder = AppColors.tripBorder;
  static const _pollInterval = Duration(seconds: 5);

  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  Timer? _pollTimer;

  String get _displayName => widget.receiverName.isNotEmpty
      ? widget.receiverName
      : widget.participantName;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => _loadMessages(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _messageFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (widget.receiverId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Chat recipient is missing.';
        });
      }
      return;
    }

    final tripId = widget.tripId?.trim() ?? '';
    if (tripId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Trip chat is only available during an active trip.';
        });
      }
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _isLoading = _messages.isEmpty;
        _error = null;
      });
    }

    final response = await ref.read(chatApiProvider).getMessages(
          otherUserId: widget.receiverId,
          tripId: tripId,
        );

    if (!mounted) return;

    if (!response.success) {
      setState(() {
        _isLoading = false;
        _error = response.message ?? 'Failed to load messages.';
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _messages = response.data ?? [];
      _error = null;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage([String? text]) async {
    final content = (text ?? _messageController.text).trim();
    final tripId = widget.tripId?.trim() ?? '';
    if (content.isEmpty ||
        widget.receiverId.isEmpty ||
        tripId.isEmpty ||
        _isSending) {
      return;
    }

    setState(() => _isSending = true);
    final response = await ref.read(chatApiProvider).sendMessage(
          receiverId: widget.receiverId,
          content: content,
          tripId: tripId,
        );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (!response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.message ?? 'Failed to send message.')),
      );
      return;
    }

    _messageController.clear();
    await _loadMessages(silent: true);
  }

  void _applyQuickReply(String text) {
    _messageController.text = text;
    _messageFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: kScreenBg,
      resizeToAvoidBottomInset: true,
      appBar: _ChatAppBar(
        participantName: _displayName,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageArea()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                for (var i = 0; i < _quickReplies.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _QuickReplyChip(
                      label: _quickReplies[i],
                      onTap: () => _applyQuickReply(_quickReplies[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? 8 : 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocus,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    style: kStyle(kRegular, kSize15, color: kTextColor),
                    decoration: InputDecoration(
                      hintText: 'Type your message',
                      hintStyle: kStyle(
                        kRegular,
                        kSize15,
                        color: kTripMutedLabel,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: kWhite,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: _inputBorder,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: _inputBorder,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: _inputBorder,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : () => _sendMessage(),
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, color: kBrandBlue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageArea() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kBrandBlue));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: kStyle(kRegular, kSize15, color: kMutedText),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadMessages, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet.\nSay hello to your driver.',
          textAlign: TextAlign.center,
          style: kStyle(kRegular, kSize15, color: kTripMutedLabel, height: 1.4),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _MessageBubble(message: message);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final time = message.createdAt != null
        ? DateFormat('hh:mm a').format(message.createdAt!.toLocal())
        : '';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? kBrandBlue : AppColors.chatBubbleOther,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: kStyle(
                kRegular,
                kSize15,
                color: isMine ? kWhite : kTextColor,
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: kStyle(
                  kRegular,
                  kSize11,
                  color: isMine ? kWhite.withValues(alpha: 0.8) : kMutedText,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String participantName;
  final VoidCallback onBack;

  const _ChatAppBar({required this.participantName, required this.onBack});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: kWhite,
      surfaceTintColor: kWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: Material(
            color: kTripCloseBtnBg,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onBack,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 28,
                  color: kTextColor,
                ),
              ),
            ),
          ),
        ),
      ),
      title: Text(
        participantName,
        style: kStyle(kSemiBold, kSize17, color: kTextColor),
      ),
    );
  }
}

class _QuickReplyChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickReplyChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.chatChipBackground,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: kStyle(kMedium, kSize11, color: kTextColor),
          ),
        ),
      ),
    );
  }
}
