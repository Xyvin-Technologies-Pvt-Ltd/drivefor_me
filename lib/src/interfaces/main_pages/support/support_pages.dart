import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:DriveForme/src/data/apis/support_api.dart';
import 'package:DriveForme/src/data/models/support_models.dart';
import 'package:DriveForme/src/data/services/support_events.dart';
import 'package:DriveForme/src/interfaces/main_pages/completed_trip_screens/raise_ticket_page.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';

class SupportTicketsPage extends ConsumerStatefulWidget {
  const SupportTicketsPage({super.key});
  @override
  ConsumerState<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends ConsumerState<SupportTicketsPage>
    with WidgetsBindingObserver {
  List<SupportTicket>? _tickets;
  String? _error;
  bool _loading = false;
  bool _reload = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_loading) {
      _reload = true;
      return;
    }
    _loading = true;
    try {
      final tickets = await ref.read(supportApiProvider).listTickets();
      if (mounted) {
        setState(() {
          _tickets = tickets;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _loading = false;
      if (_reload && mounted) {
        _reload = false;
        _load();
      }
    }
  }

  Future<void> _create() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RaiseTicketPage(category: 'General Support'),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(supportEventsProvider, (_, next) {
      if (next.hasValue) _load();
    });
    return Scaffold(
      appBar: AppBar(title: const Text('My support tickets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New ticket'),
      ),
      body: Column(
        children: [
          if (_error != null) _ErrorBanner(message: _error!, onRetry: _load),
          Expanded(
            child: _tickets == null
                ? (_error == null
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        if (_tickets!.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No support tickets yet. Create a ticket to contact our team.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final ticket in _tickets!)
                          ListTile(
                            leading: const Icon(Icons.support_agent),
                            title: Text(ticket.subject),
                            subtitle: Text(
                              '${ticket.code} · ${ticket.status}\n${ticket.preview.isEmpty ? ticket.description : ticket.preview}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: ticket.unread > 0
                                ? Badge(
                                    label: Text('${ticket.unread}'),
                                    child: const Icon(
                                      Icons.chat_bubble_outline,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      SupportChatPage(ticketId: ticket.id),
                                ),
                              );
                              if (mounted) _load();
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class SupportChatPage extends ConsumerStatefulWidget {
  const SupportChatPage({super.key, required this.ticketId});
  final String ticketId;
  @override
  ConsumerState<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends ConsumerState<SupportChatPage>
    with WidgetsBindingObserver {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  SupportTicket? _ticket;
  final Map<String, SupportMessage> _messages = {};
  String? _error;
  bool _loading = false;
  bool _reload = false;
  bool _sending = false;
  bool _olderLoading = false;
  bool _hasOlder = false;
  DateTime? _oldest;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
  }

  void _merge(List<SupportMessage> messages) {
    for (final message in messages) {
      _messages[message.id] = message;
    }
  }

  Future<void> _refresh() async {
    if (!_foreground) return;
    if (_loading) {
      _reload = true;
      return;
    }
    _loading = true;
    try {
      final api = ref.read(supportApiProvider);
      final ticket = await api.getTicket(widget.ticketId);
      if (!mounted) return;
      final initial = _ticket == null;
      setState(() => _ticket = ticket);
      final messages = await api.messages(widget.ticketId);
      if (!mounted) return;
      // Fill any gap after a long disconnect, rather than skipping replies
      // when more than one page arrived while the app was away.
      if (_messages.isNotEmpty) {
        var page = messages.toList();
        while (page.length == 50 &&
            !page.any((m) => _messages.containsKey(m.id))) {
          final cursor = page.first.createdAt;
          if (cursor == null) break;
          final older = await api.messages(widget.ticketId, before: cursor);
          if (!mounted) return;
          if (older.isEmpty || older.first.createdAt == cursor) break;
          messages.insertAll(0, older);
          page = older;
        }
      }
      final nearBottom =
          !_scroll.hasClients || _scroll.position.extentAfter < 100;
      setState(() {
        _ticket = ticket;
        _merge(messages);
        if (_oldest == null) {
          _hasOlder = messages.length == 50;
          _oldest = messages.isEmpty ? null : messages.first.createdAt;
        }
        _error = null;
      });
      if (initial || nearBottom) _scrollToBottom();
      if (_foreground &&
          ModalRoute.of(context)?.isCurrent == true &&
          ticket.unread > 0) {
        await api.markRead(widget.ticketId);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _loading = false;
      if (_reload && mounted) {
        _reload = false;
        _refresh();
      }
    }
  }

  Future<void> _loadOlder() async {
    if (_olderLoading || _oldest == null) return;
    setState(() => _olderLoading = true);
    try {
      final messages = await ref
          .read(supportApiProvider)
          .messages(widget.ticketId, before: _oldest);
      if (!mounted) return;
      final oldExtent = _scroll.hasClients
          ? _scroll.position.maxScrollExtent
          : 0.0;
      final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
      setState(() {
        _merge(messages);
        _hasOlder = messages.length == 50;
        if (messages.isNotEmpty) _oldest = messages.first.createdAt;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            (oldOffset + _scroll.position.maxScrollExtent - oldExtent).clamp(
              0.0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _olderLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(Object error) {
    showAppSnackBar(context, error.toString());
  }

  Future<void> _send() async {
    final content = _draft.text.trim();
    if (_sending || _ticket?.isOpen != true || content.isEmpty) return;
    if (content.length > 2000) {
      _showError('Messages can contain up to 2,000 characters.');
      return;
    }
    setState(() => _sending = true);
    try {
      final message = await ref
          .read(supportApiProvider)
          .sendMessage(widget.ticketId, content);
      if (!mounted) return;
      setState(() {
        _merge([message]);
        _draft.clear();
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
      // The server remains authoritative if support closes the ticket mid-send.
      if (error is SupportApiException && error.statusCode == 409) {
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(supportEventsProvider, (_, next) {
      final event = next.asData?.value;
      if (event != null &&
          (event['reconnected'] == true ||
              event['ticketId'] == widget.ticketId)) {
        _refresh();
      }
    });
    final ticket = _ticket;
    final messages = _messages.values.toList()
      ..sort((a, b) {
        final order = (a.createdAt ?? DateTime(1970)).compareTo(
          b.createdAt ?? DateTime(1970),
        );
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    return Scaffold(
      appBar: AppBar(
        title: Text(ticket?.code ?? 'Support conversation'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh conversation',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              _ErrorBanner(message: _error!, onRetry: _refresh),
            if (ticket == null)
              Expanded(
                child: Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : const Text('Unable to open this ticket.'),
                ),
              )
            else ...[
              ListTile(
                title: Text(ticket.subject),
                subtitle: Text(
                  '${ticket.status}${ticket.assignedName == null ? '' : ' · ${ticket.assignedName}'}',
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(ticket.description),
                      );
                    }
                    if (index == 1) {
                      return _hasOlder
                          ? Center(
                              child: TextButton(
                                onPressed: _olderLoading ? null : _loadOlder,
                                child: Text(
                                  _olderLoading
                                      ? 'Loading…'
                                      : 'Load older messages',
                                ),
                              ),
                            )
                          : const SizedBox.shrink();
                    }
                    return _MessageBubble(message: messages[index - 2]);
                  },
                ),
              ),
              if (!ticket.isOpen)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'This ticket is closed. You can still read the conversation.',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _draft,
                          enabled: !_sending,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Message support…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: IconButton(
                          tooltip: 'Send message',
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final SupportMessage message;
  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.isUser)
              Text(
                message.senderName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            SelectableText(message.content),
            const SizedBox(height: 4),
            Text(
              '${message.createdAt == null ? '' : DateFormat('d MMM, h:mm a').format(message.createdAt!.toLocal())}${message.isUser ? (message.isRead ? ' · Read' : ' · Sent') : ''}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(message),
    actions: [TextButton(onPressed: onRetry, child: const Text('Retry'))],
  );
}
