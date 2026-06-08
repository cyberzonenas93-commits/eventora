import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../domain/models/account_models.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

const _supportTopics = <String>[
  'Tickets and payments',
  'Account access',
  'Event safety',
  'Hosting and organizer setup',
  'Promotions and creative services',
  'Other support',
];

const _supportPriorities = <String>['normal', 'high', 'urgent'];

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _replyController = TextEditingController();
  final _service = _SupportChatService();

  var _topic = _supportTopics.first;
  var _priority = _supportPriorities.first;
  var _formHydrated = false;
  var _showNewTicketForm = true;
  var _creatingTicket = false;
  var _sendingReply = false;
  String? _selectedTicketId;
  String? _formError;
  String? _replyError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_formHydrated) return;
    final viewer = context.read<VennuzoSessionController>().viewer;
    _nameController.text = viewer.displayName == 'Guest'
        ? ''
        : viewer.displayName;
    _emailController.text = viewer.email ?? '';
    _phoneController.text = viewer.phone ?? '';
    _formHydrated = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final viewer = session.viewer;

    return Scaffold(
      appBar: AppBar(title: const Text('Support chat')),
      body: viewer.isGuest
          ? _GuestSupportPrompt(
              onSignIn: _openSignIn,
              onCreateAccount: _openSignUp,
            )
          : StreamBuilder<List<_SupportTicket>>(
              stream: _service.watchTickets(viewer.uid!),
              builder: (context, snapshot) {
                final tickets = snapshot.data ?? const <_SupportTicket>[];
                final selectedTicket = _selectTicket(tickets);
                final showForm = _showNewTicketForm || tickets.isEmpty;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: [
                    _SupportIntroCard(ticketCount: tickets.length),
                    const SizedBox(height: 16),
                    if (snapshot.hasError)
                      _InlineError(
                        message:
                            'Support tickets could not load. Check your connection and try again.',
                      ),
                    if (tickets.isNotEmpty) ...[
                      _TicketListCard(
                        tickets: tickets,
                        selectedTicketId: selectedTicket?.id,
                        loading:
                            snapshot.connectionState == ConnectionState.waiting,
                        onSelect: (ticket) {
                          setState(() {
                            _selectedTicketId = ticket.id;
                            _showNewTicketForm = false;
                          });
                          _service.markUserRead(ticket.id).ignore();
                        },
                        onNewTicket: () =>
                            setState(() => _showNewTicketForm = true),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (showForm) ...[
                      _NewSupportTicketForm(
                        nameController: _nameController,
                        emailController: _emailController,
                        phoneController: _phoneController,
                        subjectController: _subjectController,
                        messageController: _messageController,
                        topic: _topic,
                        priority: _priority,
                        error: _formError,
                        creating: _creatingTicket,
                        onTopicChanged: (value) {
                          if (value == null) return;
                          setState(() => _topic = value);
                        },
                        onPriorityChanged: (value) {
                          if (value == null) return;
                          setState(() => _priority = value);
                        },
                        onSubmit: () => _createTicket(viewer),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (selectedTicket != null)
                      _ConversationCard(
                        ticket: selectedTicket,
                        service: _service,
                        replyController: _replyController,
                        sendingReply: _sendingReply,
                        replyError: _replyError,
                        onSendReply: () => _sendReply(viewer, selectedTicket),
                      )
                    else if (!showForm)
                      const _EmptyConversationCard(),
                  ],
                );
              },
            ),
    );
  }

  _SupportTicket? _selectTicket(List<_SupportTicket> tickets) {
    if (tickets.isEmpty) return null;
    final selectedId = _selectedTicketId;
    if (selectedId == null || selectedId.isEmpty) return tickets.first;
    for (final ticket in tickets) {
      if (ticket.id == selectedId) return ticket;
    }
    return tickets.first;
  }

  Future<void> _createTicket(VennuzoViewer viewer) async {
    final validationError = _ticketValidationError();
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    setState(() {
      _creatingTicket = true;
      _formError = null;
    });
    try {
      final ticketId = await _service.createTicket(
        viewer: viewer,
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        topic: _topic,
        subject: _subjectController.text.trim(),
        priority: _priority,
        body: _messageController.text.trim(),
      );
      if (!mounted) return;
      _subjectController.clear();
      _messageController.clear();
      setState(() {
        _selectedTicketId = ticketId;
        _showNewTicketForm = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Support chat created.')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _formError =
            'Support chat could not be created. Check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _creatingTicket = false);
      }
    }
  }

  Future<void> _sendReply(VennuzoViewer viewer, _SupportTicket ticket) async {
    final body = _replyController.text.trim();
    if (body.isEmpty) {
      setState(() => _replyError = 'Write a message before sending.');
      return;
    }

    setState(() {
      _sendingReply = true;
      _replyError = null;
    });
    try {
      await _service.sendMessage(
        ticketId: ticket.id,
        viewer: viewer,
        body: body,
      );
      if (!mounted) return;
      _replyController.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _replyError =
            'Message could not be sent. Check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _sendingReply = false);
      }
    }
  }

  String? _ticketValidationError() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();

    if (name.length < 2) {
      return 'Enter your name so support knows who to help.';
    }
    if (!_looksLikeEmail(email)) {
      return 'Enter a valid email address.';
    }
    if (subject.length < 2) {
      return 'Add a short subject for the support chat.';
    }
    if (message.length < 10) {
      return 'Tell support what happened in at least 10 characters.';
    }
    return null;
  }

  bool _looksLikeEmail(String value) {
    final trimmed = value.trim();
    return trimmed.contains('@') &&
        trimmed.contains('.') &&
        trimmed.length >= 5;
  }

  Future<void> _openSignIn() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const SignInScreen()));
    if (mounted) setState(() => _formHydrated = false);
  }

  Future<void> _openSignUp() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const SignUpScreen()));
    if (mounted) setState(() => _formHydrated = false);
  }
}

class _SupportIntroCard extends StatelessWidget {
  const _SupportIntroCard({required this.ticketCount});

  final int ticketCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.palette.teal.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.support_agent_rounded,
                    color: context.palette.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Chat with Vennuzo support',
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              ticketCount == 0
                  ? 'Start a support chat for account access, tickets, payments, hosting, promotions, or safety concerns.'
                  : 'Continue an existing support conversation or start a new one.',
              style: context.text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _NewSupportTicketForm extends StatelessWidget {
  const _NewSupportTicketForm({
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.subjectController,
    required this.messageController,
    required this.topic,
    required this.priority,
    required this.error,
    required this.creating,
    required this.onTopicChanged,
    required this.onPriorityChanged,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController subjectController;
  final TextEditingController messageController;
  final String topic;
  final String priority;
  final String? error;
  final bool creating;
  final ValueChanged<String?> onTopicChanged;
  final ValueChanged<String?> onPriorityChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start a support chat',
              style: context.text.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                helperText: 'Optional',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: topic,
              decoration: const InputDecoration(labelText: 'Topic'),
              items: _supportTopics
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: creating ? null : onTopicChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: _supportPriorities
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(_priorityLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: creating ? null : onPriorityChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subjectController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              minLines: 4,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'What do you need help with?',
                alignLabelWithHint: true,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              _InlineError(message: error!),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: creating ? null : onSubmit,
                icon: creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(creating ? 'Creating chat...' : 'Create chat'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketListCard extends StatelessWidget {
  const _TicketListCard({
    required this.tickets,
    required this.selectedTicketId,
    required this.loading,
    required this.onSelect,
    required this.onNewTicket,
  });

  final List<_SupportTicket> tickets;
  final String? selectedTicketId;
  final bool loading;
  final ValueChanged<_SupportTicket> onSelect;
  final VoidCallback onNewTicket;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your conversations',
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                ),
                TextButton.icon(
                  onPressed: onNewTicket,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              ...tickets.map(
                (ticket) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TicketTile(
                    ticket: ticket,
                    selected: ticket.id == selectedTicketId,
                    onTap: () => onSelect(ticket),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({
    required this.ticket,
    required this.selected,
    required this.onTap,
  });

  final _SupportTicket ticket;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = ticket.status == 'closed'
        ? context.palette.muted
        : ticket.status == 'awaiting_user'
        ? context.palette.mint
        : context.palette.warm;

    return Semantics(
      button: true,
      selected: selected,
      label: ticket.subject,
      hint: '${_statusLabel(ticket.status)} support conversation',
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? VennuzoTheme.surfaceBright
                : context.palette.canvas,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? context.palette.teal : context.palette.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyLarge?.copyWith(
                        color: context.palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: _statusLabel(ticket.status),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ticket.latestMessage.isEmpty
                    ? ticket.topic
                    : ticket.latestMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MetaChip(label: ticket.topic),
                  if (ticket.userUnreadCount > 0)
                    _MetaChip(label: '${ticket.userUnreadCount} new'),
                  _MetaChip(label: _formatSupportTime(ticket.lastMessageAt)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.ticket,
    required this.service,
    required this.replyController,
    required this.sendingReply,
    required this.replyError,
    required this.onSendReply,
  });

  final _SupportTicket ticket;
  final _SupportChatService service;
  final TextEditingController replyController;
  final bool sendingReply;
  final String? replyError;
  final VoidCallback onSendReply;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ticket.subject,
              style: context.text.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(label: ticket.topic),
                _MetaChip(label: _statusLabel(ticket.status)),
                _MetaChip(label: _priorityLabel(ticket.priority)),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<_SupportMessage>>(
              stream: service.watchMessages(ticket.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _InlineError(
                    message: 'Messages could not load.',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                final messages = snapshot.data ?? const <_SupportMessage>[];
                if (messages.isEmpty) {
                  return Text(
                    'No messages yet.',
                    style: context.text.bodyMedium,
                  );
                }
                return Column(
                  children: messages
                      .map((message) => _MessageBubble(message: message))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            if (ticket.status == 'closed')
              Text(
                'This support chat is closed. Start a new chat if you need more help.',
                style: context.text.bodyMedium,
              )
            else ...[
              Semantics(
                container: true,
                explicitChildNodes: true,
                child: TextField(
                  key: const ValueKey('support_reply_text_field'),
                  controller: replyController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Support reply',
                    hintText: 'Write a message to Vennuzo support',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              if (replyError != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: replyError!),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: sendingReply ? null : onSendReply,
                  icon: sendingReply
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(sendingReply ? 'Sending...' : 'Send message'),
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

  final _SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final fromAdmin = message.senderType == 'admin';
    return Align(
      alignment: fromAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fromAdmin
              ? context.palette.canvas
              : context.palette.teal.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: fromAdmin
                ? context.palette.border
                : context.palette.teal.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fromAdmin ? 'Vennuzo support' : 'You',
              style: context.text.labelMedium?.copyWith(
                color: fromAdmin ? context.palette.teal : context.palette.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(message.body, style: context.text.bodyMedium),
            const SizedBox(height: 6),
            Text(
              _formatSupportTime(message.createdAt),
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestSupportPrompt extends StatelessWidget {
  const _GuestSupportPrompt({
    required this.onSignIn,
    required this.onCreateAccount,
  });

  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sign in to chat with support',
                  style: context.text.titleLarge?.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 12),
                Text(
                  'Support chats are tied to your Vennuzo account so the team can follow up securely.',
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onCreateAccount,
                    child: const Text('Create account'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onSignIn,
                    child: const Text('I already have an account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyConversationCard extends StatelessWidget {
  const _EmptyConversationCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Select a support conversation to view messages.',
          style: context.text.bodyMedium,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.border),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(color: context.palette.slate),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.error.withValues(alpha: 0.5)),
      ),
      child: Text(
        message,
        style: context.text.bodyMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _SupportChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<_SupportTicket>> watchTickets(String uid) {
    return _firestore
        .collection('support_tickets')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final tickets =
              snapshot.docs.map(_SupportTicket.fromFirestore).toList()
                ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
          return tickets;
        });
  }

  Stream<List<_SupportMessage>> watchMessages(String ticketId) {
    return _firestore
        .collection('support_tickets')
        .doc(ticketId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(_SupportMessage.fromFirestore).toList(),
        );
  }

  Future<String> createTicket({
    required VennuzoViewer viewer,
    required String name,
    required String email,
    required String phone,
    required String topic,
    required String subject,
    required String priority,
    required String body,
  }) async {
    final uid = viewer.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('A signed-in account is required.');
    }

    final ticketRef = _firestore.collection('support_tickets').doc();
    final ticketData = <String, Object?>{
      'userId': uid,
      'createdBy': uid,
      'name': name,
      'email': email,
      'topic': topic,
      'subject': subject,
      'status': 'open',
      'priority': priority,
      'source': 'mobile_app',
      'latestMessage': body,
      'adminUnreadCount': 0,
      'userUnreadCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastCustomerMessageAt': FieldValue.serverTimestamp(),
    };
    if (phone.isNotEmpty) {
      ticketData['phone'] = phone;
    }

    await ticketRef.set(ticketData);
    await ticketRef.collection('messages').add({
      'senderType': 'user',
      'senderId': uid,
      'senderName': name,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ticketRef.id;
  }

  Future<void> sendMessage({
    required String ticketId,
    required VennuzoViewer viewer,
    required String body,
  }) async {
    final uid = viewer.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('A signed-in account is required.');
    }

    await _firestore
        .collection('support_tickets')
        .doc(ticketId)
        .collection('messages')
        .add({
          'senderType': 'user',
          'senderId': uid,
          'senderName': viewer.displayName,
          'body': body,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> markUserRead(String ticketId) async {
    await _firestore.collection('support_tickets').doc(ticketId).set({
      'userUnreadCount': 0,
      'lastUserReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class _SupportTicket {
  const _SupportTicket({
    required this.id,
    required this.topic,
    required this.subject,
    required this.status,
    required this.priority,
    required this.latestMessage,
    required this.userUnreadCount,
    required this.lastMessageAt,
  });

  final String id;
  final String topic;
  final String subject;
  final String status;
  final String priority;
  final String latestMessage;
  final int userUnreadCount;
  final DateTime lastMessageAt;

  factory _SupportTicket.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _SupportTicket(
      id: doc.id,
      topic: '${data['topic'] ?? 'Support'}',
      subject: '${data['subject'] ?? 'Support chat'}',
      status: '${data['status'] ?? 'open'}',
      priority: '${data['priority'] ?? 'normal'}',
      latestMessage: '${data['latestMessage'] ?? ''}',
      userUnreadCount: (data['userUnreadCount'] as num?)?.toInt() ?? 0,
      lastMessageAt: _dateFromFirestore(data['lastMessageAt']),
    );
  }
}

class _SupportMessage {
  const _SupportMessage({
    required this.senderType,
    required this.body,
    required this.createdAt,
  });

  final String senderType;
  final String body;
  final DateTime createdAt;

  factory _SupportMessage.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _SupportMessage(
      senderType: '${data['senderType'] ?? 'user'}',
      body: '${data['body'] ?? ''}',
      createdAt: _dateFromFirestore(data['createdAt']),
    );
  }
}

DateTime _dateFromFirestore(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _statusLabel(String value) {
  return switch (value) {
    'awaiting_support' => 'Needs reply',
    'awaiting_user' => 'Replied',
    'closed' => 'Closed',
    _ => 'Open',
  };
}

String _priorityLabel(String value) {
  return switch (value) {
    'urgent' => 'Urgent',
    'high' => 'High',
    _ => 'Normal',
  };
}

String _formatSupportTime(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return 'Just now';
  final now = DateTime.now();
  final difference = now.difference(value);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${value.month}/${value.day}/${value.year}';
}
