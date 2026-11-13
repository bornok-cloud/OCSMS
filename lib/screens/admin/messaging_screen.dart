import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import '../../widgets/shared_widgets.dart';

/// Shared real-time messaging UI for Admin and Employees (Customers strictly excluded).
/// Supports Group Chats, Employee-to-Employee, and Admin conversations.
/// Dynamically places the latest active conversation at the top.
class MessagingScreen extends StatefulWidget {
  final String currentRole; // Employee name or Admin full name
  const MessagingScreen({super.key, required this.currentRole});
  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  String? _selectedId; // Unique ID to prevent selection jumping
  bool _showChatMobile = false;
  final _msgCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final Set<String> _expandedMessageTimeIds = {};

  @override
  void dispose() {
    _msgCtrl.dispose();
    _searchCtrl.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
    } else {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
        }
      });
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
        }
      });
    }
  }

  String getFirstNameOnly(String senderName) {
    if (senderName.trim().isEmpty) return senderName;
    if (senderName.trim().toLowerCase() == 'admin') return 'Admin';
    for (final user in AppData.instance.users) {
      if (user.fullName.trim().toLowerCase() == senderName.trim().toLowerCase()) {
        if (user.firstName != null && user.firstName!.trim().isNotEmpty) {
          return user.firstName!.trim();
        }
      }
    }
    final parts = senderName.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty) return parts.first;
    return senderName;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(msgDay).inDays;

    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final timeStr = '$hour12:$minute $period';

    if (diffDays == 0) {
      return 'Today, $timeStr';
    } else if (diffDays == 1) {
      return 'Yesterday, $timeStr';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final dayName = weekdays[dt.weekday - 1];
      final monthName = months[dt.month - 1];
      return '$dayName, $monthName ${dt.day}, ${dt.year} • $timeStr';
    }
  }

  String _formatTileTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(msgDay).inDays;

    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final timeStr = '$hour12:$minute $period';

    if (diffDays == 0) {
      return timeStr;
    } else if (diffDays == 1) {
      return 'Yesterday';
    } else {
      return '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';
    }
  }

  Widget _buildDateSeparator(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.beigeDark.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.darkBrown,
          ),
        ),
      ),
    );
  }

  bool get _isAdmin =>
      AppData.instance.currentUser?.role == UserRole.admin ||
      widget.currentRole == 'Admin';

  String get _senderName {
    final cu = AppData.instance.currentUser;
    if (cu != null && cu.fullName.trim().isNotEmpty) {
      return cu.fullName.trim();
    }
    return widget.currentRole;
  }

  AppUser? _findUserByName(String name) {
    final trimmed = name.trim().toLowerCase();
    for (final u in AppData.instance.users) {
      if (u.fullName.trim().toLowerCase() == trimmed) return u;
    }
    return null;
  }

  Widget _buildGroupAvatar(Conversation c, {double radius = 18}) {
    Uint8List? bytes;
    if (c.groupImageBase64 != null && c.groupImageBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(c.groupImageBase64!);
      } catch (_) {}
    }

    if (bytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.accent,
        backgroundImage: MemoryImage(bytes),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accent,
      child: Icon(Icons.groups, color: Colors.white, size: radius * 0.9),
    );
  }

  Widget _buildUserAvatar(String name, {double radius = 18, bool isGroup = false, Conversation? conversation}) {
    if (isGroup && conversation != null) {
      return _buildGroupAvatar(conversation, radius: radius);
    }
    if (isGroup) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.accent,
        child: Icon(Icons.groups, color: Colors.white, size: radius * 0.9),
      );
    }

    final user = _findUserByName(name);
    Uint8List? bytes;
    if (user?.profileImage != null && user!.profileImage!.isNotEmpty) {
      try {
        bytes = base64Decode(user.profileImage!);
      } catch (_) {}
    }

    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';

    if (bytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.brown,
        backgroundImage: MemoryImage(bytes),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.brown,
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: radius * 0.75),
      ),
    );
  }

  String _getDisplayTitle(Conversation c) {
    if (c.isGroup) return c.withName;

    final myName = _senderName.toLowerCase();

    if (c.id.startsWith('p2p_')) {
      final parts = c.id.replaceFirst('p2p_', '').split('_');
      final otherParts = parts.where((p) => p.trim().toLowerCase() != myName && p != 'Admin').toList();
      if (otherParts.isNotEmpty) {
        return otherParts.first;
      }
    }

    if (c.withName != 'Admin' && c.withName.toLowerCase() != myName) {
      return c.withName;
    }

    return c.withName;
  }

  List<Conversation> get _conversations {
    final data = AppData.instance;
    List<Conversation> list = [];
    final cu = AppData.instance.currentUser;
    final myFullName = cu?.fullName.trim().toLowerCase() ?? '';
    final myRoleName = widget.currentRole.trim().toLowerCase();

    bool isMember(Conversation c) {
      return c.members.any((m) {
        final mLower = m.trim().toLowerCase();
        return mLower == myFullName ||
               mLower == myRoleName ||
               (mLower == 'admin' && _isAdmin);
      });
    }

    bool isParticipant(Conversation c) {
      if (isMember(c)) return true;
      final idLower = c.id.toLowerCase();
      final withLower = c.withName.toLowerCase();
      return idLower.contains(myFullName) ||
             idLower.contains(myRoleName) ||
             (idLower.contains('admin') && _isAdmin) ||
             withLower == myFullName ||
             withLower == myRoleName;
    }

    for (final c in data.adminEmployeeChats) {
      if (data.isConversationHiddenForMe(c.id, widget.currentRole)) continue;
      if (c.isGroup) {
        // Group Chat: ONLY show if current user is listed in c.members
        if (isMember(c)) {
          list.add(c);
        }
      } else {
        // 1-on-1 Personal Chat:
        if (_isAdmin) {
          // Admin sees all 1-on-1 personal chats
          list.add(c);
        } else {
          // Employee sees 1-on-1 personal chats where they are a participant
          if (isParticipant(c)) {
            list.add(c);
          }
        }
      }
    }

    // Sort: Latest message or active chat at the top
    list.sort((a, b) {
      final cuObj = AppData.instance.currentUser;
      final clearedAtA = data.getRoleClearedTimestamp(a.id, widget.currentRole);
      final clearedAtB = data.getRoleClearedTimestamp(b.id, widget.currentRole);

      final visibleA = a.messages.where((m) {
        if (m.deletedFor.contains(_senderName) || (cuObj != null && m.deletedFor.contains(cuObj.fullName))) return false;
        if (clearedAtA != null && (m.timestamp.isBefore(clearedAtA) || m.timestamp.isAtSameMomentAs(clearedAtA))) return false;
        return true;
      }).toList();

      final visibleB = b.messages.where((m) {
        if (m.deletedFor.contains(_senderName) || (cuObj != null && m.deletedFor.contains(cuObj.fullName))) return false;
        if (clearedAtB != null && (m.timestamp.isBefore(clearedAtB) || m.timestamp.isAtSameMomentAs(clearedAtB))) return false;
        return true;
      }).toList();

      final timeA = visibleA.isNotEmpty ? visibleA.last.timestamp : DateTime(1970);
      final timeB = visibleB.isNotEmpty ? visibleB.last.timestamp : DateTime(1970);
      return timeB.compareTo(timeA);
    });

    return list;
  }

  void _send() {
    if (_msgCtrl.text.trim().isEmpty) return;
    final convos = _conversations;
    if (convos.isEmpty) return;
    
    final convo = convos.firstWhere(
      (c) => c.id == _selectedId, 
      orElse: () => convos.first
    );
    
    AppData.instance.sendMessage(
      conversationId: convo.id,
      sender: _senderName,
      text: _msgCtrl.text.trim(),
      isGroup: convo.isGroup,
      groupId: convo.isGroup ? convo.id : '',
      convoName: convo.withName,
    );
    _msgCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _saveAttachment(String base64Data, String defaultName) async {
    try {
      final bytes = base64Decode(base64Data);
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Attachment As...',
        fileName: defaultName,
        bytes: bytes,
      );
      if (outputFile != null && mounted) {
        showAppSnack(context, 'Attachment saved successfully.');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, 'Failed to save attachment: $e');
    }
  }

  void _forwardMessage(ChatMessage message) {
    final convos = _conversations;
    if (convos.isEmpty) {
      showAppSnack(context, 'No conversations available to forward to.');
      return;
    }

    String? targetConvoId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.forward_rounded, color: AppColors.accent),
              SizedBox(width: 8),
              Text('Forward Message'),
            ],
          ),
          content: SizedBox(
            width: 340,
            height: 320,
            child: ListView.builder(
              itemCount: convos.length,
              itemBuilder: (context, index) {
                final c = convos[index];
                final title = _getDisplayTitle(c);
                final isSelected = targetConvoId == c.id;

                return ListTile(
                  leading: _buildUserAvatar(c.isGroup ? '' : title, radius: 18, isGroup: c.isGroup, conversation: c),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: Text(c.isGroup ? 'Group Chat (${c.members.length} members)' : 'Personal Chat', style: const TextStyle(fontSize: 11.5)),
                  trailing: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? AppColors.accent : AppColors.textMuted,
                  ),
                  onTap: () {
                    setDialogState(() {
                      targetConvoId = c.id;
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: targetConvoId == null
                  ? null
                  : () {
                      final target = convos.firstWhere((c) => c.id == targetConvoId);
                      AppData.instance.sendMessage(
                        conversationId: target.id,
                        sender: _senderName,
                        text: message.text,
                        imageUrl: message.imageUrl,
                        fileName: message.fileName,
                        fileData: message.fileData,
                        isGroup: target.isGroup,
                        groupId: target.isGroup ? target.id : '',
                        convoName: target.withName,
                      );
                      Navigator.pop(ctx);
                      showAppSnack(context, 'Message forwarded to ${_getDisplayTitle(target)}.');
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                    },
              child: const Text('Forward'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewFullImage(BuildContext context, ChatMessage message) {
    if (message.imageUrl == null || message.imageUrl!.isEmpty) return;

    Uint8List? bytes;
    try {
      bytes = base64Decode(message.imageUrl!);
    } catch (_) {
      bytes = null;
    }

    if (bytes == null) {
      showAppSnack(context, 'Unable to load full image.');
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sent by ${getFirstNameOnly(message.sender)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      formatChatTimestamp(message.timestamp),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Colors.white),
                      tooltip: 'Save Image',
                      onPressed: () => _saveAttachment(message.imageUrl!, 'image_${DateTime.now().millisecondsSinceEpoch}.jpg'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_rounded, color: Colors.white),
                      tooltip: 'Forward Image',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _forwardMessage(message);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: const EdgeInsets.all(20),
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(
                    bytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Send Attachment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkBrown)),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.image_outlined, color: AppColors.accent),
                ),
                title: const Text('Send Image', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Max size: 20MB', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendImage();
                },
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brown.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.insert_drive_file_outlined, color: AppColors.brown),
                ),
                title: const Text('Send File / Document', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Max size: 20MB', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFile();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      if (file.bytes!.length > 20 * 1024 * 1024) {
        if (!mounted) return;
        showAppSnack(context, 'Image size exceeds the 20MB limit.');
        return;
      }

      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.image_rounded, color: AppColors.accent),
              SizedBox(width: 10),
              Text('Send Picture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260, maxWidth: 300),
                  child: Image.memory(
                    file.bytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Are you sure you want to send this picture?', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: AppColors.darkBrown),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final base64Image = base64Encode(file.bytes!);
      final convos = _conversations;
      if (convos.isEmpty) return;
      final convo = convos.firstWhere(
        (c) => c.id == _selectedId,
        orElse: () => convos.first,
      );

      AppData.instance.sendMessage(
        conversationId: convo.id,
        sender: _senderName,
        text: _msgCtrl.text.trim(),
        imageUrl: base64Image,
        isGroup: convo.isGroup,
        groupId: convo.isGroup ? convo.id : '',
        convoName: convo.withName,
      );
      _msgCtrl.clear();
      _scrollToBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      Future.delayed(const Duration(milliseconds: 50), () => _scrollToBottom());
      Future.delayed(const Duration(milliseconds: 150), () => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Failed to send image: $e');
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      if (file.bytes!.length > 20 * 1024 * 1024) {
        if (!mounted) return;
        showAppSnack(context, 'File size exceeds the 20MB limit.');
        return;
      }

      final base64File = base64Encode(file.bytes!);
      final convos = _conversations;
      if (convos.isEmpty) return;
      final convo = convos.firstWhere(
        (c) => c.id == _selectedId,
        orElse: () => convos.first,
      );

      AppData.instance.sendMessage(
        conversationId: convo.id,
        sender: _senderName,
        text: _msgCtrl.text.trim().isNotEmpty ? _msgCtrl.text.trim() : 'Sent file: ${file.name}',
        fileName: file.name,
        fileData: base64File,
        isGroup: convo.isGroup,
        groupId: convo.isGroup ? convo.id : '',
        convoName: convo.withName,
      );
      _msgCtrl.clear();
      _scrollToBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      Future.delayed(const Duration(milliseconds: 50), () => _scrollToBottom());
      Future.delayed(const Duration(milliseconds: 150), () => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Failed to send file: $e');
    }
  }

  Widget _buildMessageMenu(ChatMessage m, bool mine, Conversation convo) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
      tooltip: 'Message options',
      padding: EdgeInsets.zero,
      splashRadius: 16,
      onSelected: (value) {
        if (value == 'view') {
          _viewFullImage(context, m);
        } else if (value == 'save') {
          if (m.imageUrl != null && m.imageUrl!.isNotEmpty) {
            _saveAttachment(m.imageUrl!, 'image_${DateTime.now().millisecondsSinceEpoch}.jpg');
          } else if (m.fileData != null && m.fileData!.isNotEmpty) {
            _saveAttachment(m.fileData!, m.fileName ?? 'file');
          }
        } else if (value == 'forward') {
          _forwardMessage(m);
        } else if (value == 'delete') {
          _showMessageOptions(convo, m, mine);
        }
      },
      itemBuilder: (ctx) => [
        if (m.imageUrl != null && m.imageUrl!.isNotEmpty)
          const PopupMenuItem(
            value: 'view',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 18, color: AppColors.darkBrown),
                SizedBox(width: 8),
                Text('View Image'),
              ],
            ),
          ),
        if ((m.imageUrl != null && m.imageUrl!.isNotEmpty) || (m.fileData != null && m.fileData!.isNotEmpty))
          const PopupMenuItem(
            value: 'save',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_outlined, size: 18, color: AppColors.darkBrown),
                SizedBox(width: 8),
                Text('Save File'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'forward',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forward_outlined, size: 18, color: AppColors.darkBrown),
              SizedBox(width: 8),
              Text('Forward'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Delete options'),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppData.instance,
      builder: (context, _) {
        final convos = _conversations;
        final wide = MediaQuery.of(context).size.width >= 750;

        if (convos.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.cream,
            appBar: !_isAdmin && !wide ? AppBar(title: const Text('Messaging')) : null,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No conversations available yet.', style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showNewChatDialog(context),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Start New Chat'),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _createNewGroupDialog(context),
                      icon: const Icon(Icons.group_add),
                      label: const Text('Create Group Chat'),
                    )
                  ]
                ],
              ),
            ),
          );
        }
        
        // Auto-select first convo if none selected or if selected one is gone
        if (_selectedId == null || !convos.any((c) => c.id == _selectedId)) {
          _selectedId = convos.first.id;
        }
        
        final convo = convos.firstWhere((c) => c.id == _selectedId, orElse: () => convos.first);

        // 1. Sidebar/List of conversations
        final list = Container(
          width: wide ? 320 : double.infinity,
          color: AppColors.cardWhite,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search chats...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.darkBrown, width: 1.5)),
                          fillColor: AppColors.cream,
                          filled: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.darkBrown,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 18),
                        tooltip: 'New Chat',
                        onPressed: () => _showNewChatDialog(context),
                      ),
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.group_add_outlined, color: Colors.white, size: 18),
                          tooltip: 'New Group Chat',
                          onPressed: () => _createNewGroupDialog(context),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: convos.length,
                  itemBuilder: (ctx, i) {
                    final c = convos[i];
                    final displayTitle = _getDisplayTitle(c);

                    if (_searchCtrl.text.isNotEmpty && !displayTitle.toLowerCase().contains(_searchCtrl.text.toLowerCase())) {
                      return const SizedBox.shrink();
                    }

                    final cuObj = AppData.instance.currentUser;
                    final clearedAt = AppData.instance.getRoleClearedTimestamp(c.id, widget.currentRole);

                    final visibleConvoMessages = c.messages.where((m) {
                      if (m.deletedFor.contains(_senderName) || (cuObj != null && m.deletedFor.contains(cuObj.fullName))) {
                        return false;
                      }
                      if (clearedAt != null && (m.timestamp.isBefore(clearedAt) || m.timestamp.isAtSameMomentAs(clearedAt))) {
                        return false;
                      }
                      return true;
                    }).toList();

                    final unread = visibleConvoMessages.any((m) => !m.read && m.sender != _senderName && m.sender != widget.currentRole && m.sender != 'Admin');
                    final last = visibleConvoMessages.isNotEmpty ? visibleConvoMessages.last : null;
                    final isSelected = c.id == _selectedId;
                    final isMine = last != null && (last.sender == _senderName || last.sender == cuObj?.fullName || last.sender == widget.currentRole);
                    final senderFirstName = last != null ? getFirstNameOnly(last.sender) : '';
                    final hasImage = last != null && last.imageUrl != null && last.imageUrl!.isNotEmpty;
                    final hasFile = last != null && last.fileData != null && last.fileData!.isNotEmpty;
                    final timeLabel = last != null ? _formatTileTime(last.timestamp) : '';

                    String subtitleText = 'No messages yet';
                    if (last != null) {
                      if (hasImage) {
                        if (isMine) {
                          subtitleText = 'You: Sent a photo.';
                        } else {
                          if (c.isGroup) {
                            subtitleText = '$senderFirstName Sent a photo.';
                          } else {
                            subtitleText = 'Sent a photo.';
                          }
                        }
                      } else if (hasFile) {
                        if (isMine) {
                          subtitleText = 'You: Sent a file.';
                        } else {
                          if (c.isGroup) {
                            subtitleText = '$senderFirstName Sent a file.';
                          } else {
                            subtitleText = 'Sent a file.';
                          }
                        }
                      } else {
                        if (isMine) {
                          subtitleText = 'You: ${last.text}';
                        } else {
                          if (c.isGroup) {
                            subtitleText = '$senderFirstName: ${last.text}';
                          } else {
                            subtitleText = last.text;
                          }
                        }
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedId = c.id;
                            _showChatMobile = true;
                          });
                          AppData.instance.markMessagesAsRead(c.id, _senderName);
                          _scrollToBottom();
                          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                          Future.delayed(const Duration(milliseconds: 50), () => _scrollToBottom());
                          Future.delayed(const Duration(milliseconds: 150), () => _scrollToBottom());
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: wide && isSelected ? AppColors.beige : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: wide && isSelected ? AppColors.beigeDark : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (wide && isSelected)
                                Container(
                                  width: 3.5,
                                  height: 32,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.darkBrown,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              _buildUserAvatar(c.isGroup ? '' : displayTitle, radius: 20, isGroup: c.isGroup, conversation: c),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            displayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
                                              fontSize: 13.5,
                                              color: AppColors.darkBrown,
                                            ),
                                          ),
                                        ),
                                        if (timeLabel.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            timeLabel,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                                              color: unread ? AppColors.darkBrown : AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            subtitleText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: unread ? FontWeight.w800 : FontWeight.normal,
                                              color: unread ? Colors.black : AppColors.textMuted,
                                            ),
                                          ),
                                        ),
                                        if (unread) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.accent,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'NEW',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textMuted),
                                          tooltip: 'Delete conversation',
                                          splashRadius: 16,
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _confirmDeleteConversation(c, displayTitle),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

        // Clean Header Title
        final chatHeaderTitle = _getDisplayTitle(convo);

        if (wide || _showChatMobile) {
          _scrollToBottom();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AppData.instance.markMessagesAsRead(convo.id, _senderName);
            _scrollToBottom();
          });
          Future.delayed(const Duration(milliseconds: 50), () => _scrollToBottom());
          Future.delayed(const Duration(milliseconds: 150), () => _scrollToBottom());
        }

        // 2. Chat Workspace
        final chat = Column(
          children: [
            Container(
              color: AppColors.beige,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  if (!wide) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.darkBrown),
                      onPressed: () => setState(() => _showChatMobile = false),
                    ),
                    const SizedBox(width: 4),
                  ],
                  _buildUserAvatar(convo.isGroup ? '' : chatHeaderTitle, radius: 20, isGroup: convo.isGroup, conversation: convo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(chatHeaderTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkBrown)),
                        if (convo.isGroup)
                          Text('${convo.members.length} members', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  if (convo.isGroup) ...[
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: AppColors.darkBrown),
                      tooltip: 'Group Chat Settings',
                      onPressed: () => _showGroupSettingsDialog(context, convo),
                    )
                  ]
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final cuObj = AppData.instance.currentUser;
                  final clearedAt = AppData.instance.getRoleClearedTimestamp(convo.id, widget.currentRole);

                  final visibleMessages = convo.messages.where((m) {
                    if (m.deletedFor.contains(_senderName) || (cuObj != null && m.deletedFor.contains(cuObj.fullName))) {
                      return false;
                    }
                    if (clearedAt != null && (m.timestamp.isBefore(clearedAt) || m.timestamp.isAtSameMomentAs(clearedAt))) {
                      return false;
                    }
                    return true;
                  }).toList();

                  return ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: visibleMessages.length,
                    itemBuilder: (ctx, i) {
                      final m = visibleMessages[i];
                      final myFullName = cuObj?.fullName.trim() ?? '';
                      final mine = m.sender == _senderName ||
                          (myFullName.isNotEmpty && m.sender == myFullName) ||
                          m.sender == widget.currentRole;

                      final showDateHeader = i == 0 || !_isSameDay(m.timestamp, visibleMessages[i - 1].timestamp);
                      final isExpanded = _expandedMessageTimeIds.contains(m.id);

                      final borderRadius = BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: mine ? const Radius.circular(14) : Radius.zero,
                        bottomRight: mine ? Radius.zero : const Radius.circular(14),
                      );

                  final bubbleContent = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        if (_expandedMessageTimeIds.contains(m.id)) {
                          _expandedMessageTimeIds.remove(m.id);
                        } else {
                          _expandedMessageTimeIds.add(m.id);
                        }
                      });
                    },
                    child: ClipRRect(
                      borderRadius: borderRadius,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * (wide ? 0.45 : 0.72),
                        ),
                        decoration: BoxDecoration(
                          color: mine ? AppColors.brown : AppColors.beigeDark.withValues(alpha: 0.6),
                          borderRadius: borderRadius,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!mine && convo.isGroup)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(getFirstNameOnly(m.sender), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.accentDark)),
                              ),
                            if (m.imageUrl != null && m.imageUrl!.isNotEmpty) ...[
                              GestureDetector(
                                onTap: () => _viewFullImage(context, m),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Builder(
                                    builder: (context) {
                                      try {
                                        final bytes = base64Decode(m.imageUrl!);
                                        return ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: MediaQuery.of(context).size.width * (wide ? 0.38 : 0.6),
                                            maxHeight: 360,
                                          ),
                                          child: Image.memory(
                                            bytes,
                                            fit: BoxFit.contain,
                                          ),
                                        );
                                      } catch (_) {
                                        return const Text('[Image Load Error]', style: TextStyle(color: AppColors.danger));
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (m.fileData != null && m.fileData!.isNotEmpty) ...[
                              InkWell(
                                onTap: () => _saveAttachment(m.fileData!, m.fileName ?? 'file'),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: mine ? Colors.white.withValues(alpha: 0.15) : AppColors.beige,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.insert_drive_file, color: mine ? Colors.white : AppColors.brown, size: 24),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              m.fileName ?? 'Attachment',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: mine ? Colors.white : AppColors.darkBrown,
                                              ),
                                            ),
                                            const Text('Tap to save attachment', style: TextStyle(fontSize: 10, color: Colors.white70)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (m.text.isNotEmpty)
                              Text(m.text, style: TextStyle(color: mine ? Colors.white : AppColors.darkBrown, fontSize: 14)),
                            if (isExpanded) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    formatChatTimestamp(m.timestamp),
                                    style: TextStyle(fontSize: 9.5, color: mine ? Colors.white70 : AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );

                  final msgAvatar = _buildUserAvatar(m.sender, radius: 14);

                  final messageRow = !mine
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              msgAvatar,
                              const SizedBox(width: 8),
                              Flexible(child: bubbleContent),
                              _buildMessageMenu(m, mine, convo),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildMessageMenu(m, mine, convo),
                              Flexible(child: bubbleContent),
                              const SizedBox(width: 8),
                              msgAvatar,
                            ],
                          ),
                        );

                  if (showDateHeader) {
                    return Column(
                      children: [
                        _buildDateSeparator(_formatDateHeader(m.timestamp)),
                        messageRow,
                      ],
                    );
                  }
                  return messageRow;
                },
              );
            },
          ),
        ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.cardWhite,
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.brown),
                    tooltip: 'Add attachment',
                    onPressed: () => _showAttachmentOptions(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: 'Type a message or add attachment...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppColors.beigeDark),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
          ],
        );

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        // Responsive Master-Detail Split Screen Layout with Margins
        Widget content;
        if (wide) {
          content = Row(
            children: [
              list,
              const VerticalDivider(width: 1),
              Expanded(child: chat),
            ],
          );
        } else {
          content = _showChatMobile ? chat : list;
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.soft,
            ),
            child: content,
          ),
        );
      },
    );
  }

  void _showMessageOptions(Conversation convo, ChatMessage m, bool mine) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Message Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkBrown)),
              const SizedBox(height: 8),
              if (mine) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_forever_outlined, color: AppColors.danger),
                  ),
                  title: const Text('Delete for Everyone', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Removes this message from the chat for all participants.', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteMessage(
                      title: 'Delete for Everyone?',
                      message: 'This message will be permanently removed from this chat for everyone involved. This cannot be undone.',
                      onConfirm: () => AppData.instance.deleteMessageForEveryone(m.id),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
              ],
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.darkBrown.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.visibility_off_outlined, color: AppColors.darkBrown),
                ),
                title: const Text('Delete for You', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Hides this message only from your own chat.', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteMessage(
                    title: 'Delete for You?',
                    message: 'This message will be hidden from your chat only. Other participants will still see it.',
                    onConfirm: () => AppData.instance.deleteMessageForMe(m.id),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMessage({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteConversation(Conversation c, String displayTitle) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.25), width: 1.5),
                ),
                child: const Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 32),
              ),
              const SizedBox(height: 18),
              const Text(
                'Delete Conversation?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkBrown,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.45),
                  children: [
                    const TextSpan(text: 'Are you sure you want to delete the conversation with '),
                    TextSpan(
                      text: '"$displayTitle"',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.darkBrown),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.info_outline_rounded, color: AppColors.danger, size: 18),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'This will clear the conversation for you. Other participants will still be able to see their chat history.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.danger.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFFD0D0D0)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await AppData.instance.clearConversationForMe(c.id, widget.currentRole);
                        if (!mounted) return;
                        if (_selectedId == c.id) {
                          setState(() {
                            _selectedId = null;
                            _showChatMobile = false;
                          });
                        }
                        showAppSnack(context, 'Conversation deleted for you.');
                      },
                      icon: const Icon(Icons.delete_rounded, size: 18),
                      label: const Text(
                        'Delete Chat',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createNewGroupDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final cu = AppData.instance.currentUser;
    final myName = cu?.fullName.trim() ?? widget.currentRole.trim();
    final selectedMembers = <String>[myName];
    String? groupImageBase64;

    // STRICTLY EXCLUDE CUSTOMERS: Only admins and employees
    final eligibleUsers = AppData.instance.users
        .where((u) => u.role != UserRole.customer && u.fullName.trim() != myName && u.status == 'Active')
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickGroupPhoto() async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                withData: true,
              );
              if (result == null || result.files.isEmpty) return;
              final file = result.files.first;
              if (file.bytes == null) return;
              setDialogState(() {
                groupImageBase64 = base64Encode(file.bytes!);
              });
            } catch (e) {
              if (ctx.mounted) showAppSnack(ctx, 'Failed to pick photo: $e');
            }
          }

          Uint8List? imageBytes;
          if (groupImageBase64 != null && groupImageBase64!.isNotEmpty) {
            try {
              imageBytes = base64Decode(groupImageBase64!);
            } catch (_) {}
          }

          return AlertDialog(
            title: const Text('Create Group Chat'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Group Photo Picker
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.accent,
                            backgroundImage: imageBytes != null ? MemoryImage(imageBytes) : null,
                            child: imageBytes == null
                                ? const Icon(Icons.groups, size: 32, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: pickGroupPhoto,
                            icon: const Icon(Icons.photo_camera, size: 16),
                            label: Text(groupImageBase64 == null ? 'Set Group Photo' : 'Change Group Photo'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      maxLength: 20,
                      inputFormatters: [LengthLimitingTextInputFormatter(20)],
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        hintText: 'e.g. Kitchen Staff (Max 20 chars)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Add Members (Admins & Employees):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(height: 8),
                    if (eligibleUsers.isEmpty)
                      const Text('No eligible users available.', style: TextStyle(color: AppColors.textMuted))
                    else
                      ...eligibleUsers.map((u) {
                        final isChecked = selectedMembers.contains(u.fullName);
                        return CheckboxListTile(
                          secondary: _buildUserAvatar(u.fullName, radius: 16),
                          title: Text(u.fullName),
                          subtitle: Text(u.roleLabel),
                          value: isChecked,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                if (!selectedMembers.contains(u.fullName)) selectedMembers.add(u.fullName);
                              } else {
                                selectedMembers.remove(u.fullName);
                              }
                            });
                          },
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final gName = nameCtrl.text.trim();
                  if (gName.isEmpty) {
                    showAppSnack(context, 'Please enter a group name.');
                    return;
                  }
                  if (gName.length > 20) {
                    showAppSnack(context, 'Group name must be at most 20 characters.');
                    return;
                  }
                  AppData.instance.createGroupChat(gName, selectedMembers, groupImageBase64: groupImageBase64);
                  Navigator.pop(ctx);
                  showAppSnack(context, 'Group "$gName" created successfully.');
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGroupSettingsDialog(BuildContext context, Conversation convo) {
    final cu = AppData.instance.currentUser;
    final myName = cu?.fullName.trim() ?? widget.currentRole.trim();
    final selectedMembers = List<String>.from(convo.members);
    final nameCtrl = TextEditingController(text: convo.withName);
    String? groupImageBase64 = convo.groupImageBase64;

    // STRICTLY EXCLUDE CUSTOMERS: Only admins and employees
    final eligibleUsers = AppData.instance.users
        .where((u) => u.role != UserRole.customer && u.status == 'Active')
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickGroupPhoto() async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                withData: true,
              );
              if (result == null || result.files.isEmpty) return;
              final file = result.files.first;
              if (file.bytes == null) return;
              setDialogState(() {
                groupImageBase64 = base64Encode(file.bytes!);
              });
            } catch (e) {
              if (ctx.mounted) showAppSnack(ctx, 'Failed to pick photo: $e');
            }
          }

          Uint8List? imageBytes;
          if (groupImageBase64 != null && groupImageBase64!.isNotEmpty) {
            try {
              imageBytes = base64Decode(groupImageBase64!);
            } catch (_) {}
          }

          return AlertDialog(
            title: const Text('Group Chat Settings'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Group Photo
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: AppColors.accent,
                            backgroundImage: imageBytes != null ? MemoryImage(imageBytes) : null,
                            child: imageBytes == null
                                ? const Icon(Icons.groups, size: 34, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: pickGroupPhoto,
                                icon: const Icon(Icons.photo_camera, size: 16),
                                label: Text(groupImageBase64 == null ? 'Set Photo' : 'Change Photo'),
                              ),
                              if (groupImageBase64 != null)
                                TextButton(
                                  onPressed: () => setDialogState(() => groupImageBase64 = null),
                                  child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      maxLength: 20,
                      inputFormatters: [LengthLimitingTextInputFormatter(20)],
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Members (Admins & Employees):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(height: 8),
                    ...eligibleUsers.map((u) {
                      final isChecked = selectedMembers.contains(u.fullName);
                      return CheckboxListTile(
                        secondary: _buildUserAvatar(u.fullName, radius: 16),
                        title: Text(u.fullName),
                        subtitle: Text(u.roleLabel),
                        value: isChecked,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              if (!selectedMembers.contains(u.fullName)) selectedMembers.add(u.fullName);
                            } else {
                              if (u.fullName == myName && selectedMembers.length <= 1) return;
                              selectedMembers.remove(u.fullName);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final gName = nameCtrl.text.trim();
                  if (gName.isEmpty) {
                    showAppSnack(context, 'Group name cannot be empty.');
                    return;
                  }
                  if (gName.length > 20) {
                    showAppSnack(context, 'Group name must be at most 20 characters.');
                    return;
                  }
                  AppData.instance.updateGroupDetails(
                    convo.id,
                    groupName: gName,
                    memberNames: selectedMembers,
                    groupImageBase64: groupImageBase64 ?? '',
                  );
                  Navigator.pop(ctx);
                  showAppSnack(context, 'Group settings updated.');
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showNewChatDialog(BuildContext context) {
    final data = AppData.instance;
    final cu = data.currentUser;
    final myName = cu?.fullName.trim() ?? widget.currentRole.trim();

    // STRICTLY EXCLUDE CUSTOMERS: Only admins and employees
    final availableUsers = data.users
        .where((u) => u.role != UserRole.customer && u.fullName.trim() != myName && u.status == 'Active')
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.chat_bubble_outline_rounded, color: AppColors.accent),
            SizedBox(width: 10),
            Text('Start New Conversation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 360,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a team member to start a direct message:',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: availableUsers.isEmpty
                    ? const Center(child: Text('No users available to chat.', style: TextStyle(color: AppColors.textMuted)))
                    : ListView.separated(
                        itemCount: availableUsers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                        itemBuilder: (context, index) {
                          final u = availableUsers[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            leading: _buildUserAvatar(u.fullName, radius: 22),
                            title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(u.roleLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                            onTap: () {
                              Navigator.pop(ctx);
                              final List<String> names = [myName, u.fullName]..sort();
                              final convoId = 'p2p_${names[0]}_${names[1]}';

                              AppData.instance.ensureConversationExists(
                                id: convoId,
                                withName: u.fullName,
                                members: [myName, u.fullName],
                                currentRoleOrName: widget.currentRole,
                              );

                              setState(() {
                                _selectedId = convoId;
                                _showChatMobile = true;
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: AppColors.darkBrown),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
