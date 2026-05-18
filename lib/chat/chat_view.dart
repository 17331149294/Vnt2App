import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vnt2_app/utils/toast_utils.dart';

import 'chat_manager.dart';
import 'chat_models.dart';
import 'chat_peer_labels.dart';
import 'chat_repository.dart';

enum ChatRoomSection { channels, directMessages }

class ChatRoomView extends StatefulWidget {
  const ChatRoomView({
    super.key,
    required this.section,
    this.scopedNetworkKey,
  });

  final ChatRoomSection section;
  final String? scopedNetworkKey;

  @override
  State<ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<ChatRoomView> {
  final TextEditingController _textController = TextEditingController();
  int _lastStatusVersion = -1;
  bool _showEmojiPicker = false;

  bool get _isRefreshingDiscovery => chatManager.isRefreshingDiscovery;

  String? get _scopedNetworkKey {
    final value = widget.scopedNetworkKey?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  List<ChatConversationSummary> get _lobbyConversations =>
      chatManager.lobbyConversationsForScope(
        scopedNetworkKey: _scopedNetworkKey,
      );

  List<ChatConversationSummary> get _roomConversations =>
      chatManager.roomConversationsForScope(
        scopedNetworkKey: _scopedNetworkKey,
      );

  List<ChatConversationSummary> get _directConversations =>
      chatManager.directConversationsForScope(
        scopedNetworkKey: _scopedNetworkKey,
      );

  List<ChatConversationSummary> get _channelConversations =>
      chatManager.channelConversationsForScope(
        scopedNetworkKey: _scopedNetworkKey,
      );

  List<ChatChannel> get _scopedChannels =>
      chatManager.channelsForScope(scopedNetworkKey: _scopedNetworkKey);

  List<ChatPeer> get _onlinePeers => chatManager.onlinePeersForScope(
        scopedNetworkKey: _scopedNetworkKey,
      );

  List<String> get _connectedNetworkKeys =>
      chatManager.connectedNetworkKeysForScope(
        scopedNetworkKey: _scopedNetworkKey,
      );

  bool get _hasMultipleNetworks => chatManager.hasMultipleNetworksInScope(
      scopedNetworkKey: _scopedNetworkKey);

  @override
  void initState() {
    super.initState();
    unawaited(chatManager.init());
    if (widget.section == ChatRoomSection.channels) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureInitialChannelSelection());
      });
    }
  }

  @override
  void didUpdateWidget(covariant ChatRoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section ||
        oldWidget.scopedNetworkKey != widget.scopedNetworkKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.section != ChatRoomSection.channels) {
          return;
        }
        unawaited(_ensureInitialChannelSelection());
      });
    }
  }

  Future<void> _refreshDiscovery() async {
    if (_isRefreshingDiscovery) {
      return;
    }
    await chatManager.debugRefreshNow();
  }

  Future<void> _ensureInitialChannelSelection() async {
    await chatManager.init();
    await chatManager.syncConnections();
    if (!mounted || widget.section != ChatRoomSection.channels) {
      return;
    }
    final conversation = chatManager.selectedConversation;
    if (conversation == null ||
        !chatMatchesNetworkScope(
          conversation.networkKey,
          _scopedNetworkKey,
        )) {
      await chatManager.openPreferredChannelConversation(
        scopedNetworkKey: _scopedNetworkKey,
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatManager,
      builder: (context, _) {
        _showStatusSnackBarIfNeeded(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            final leftPane = _buildSidebar(context, widget.section);
            final showConversationOnlyOnNarrow =
                _shouldShowConversationOnlyOnNarrow();
            final rightPane = _buildConversationPane(
              context,
              onShowSidebar: !isWide && showConversationOnlyOnNarrow
                  ? () => _showSidebarSheet(context)
                  : null,
            );
            if (isWide) {
              return Container(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerLowest
                    .withOpacity(0.55),
                child: Row(
                  children: [
                    SizedBox(width: 360, child: leftPane),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).dividerColor.withOpacity(0.16),
                    ),
                    Expanded(child: rightPane),
                  ],
                ),
              );
            }
            if (showConversationOnlyOnNarrow) {
              return rightPane;
            }
            return leftPane;
          },
        );
      },
    );
  }

  void _showStatusSnackBarIfNeeded(BuildContext context) {
    final message = chatManager.statusMessage;
    if (message == null ||
        message.isEmpty ||
        chatManager.statusVersion == _lastStatusVersion) {
      return;
    }
    _lastStatusVersion = chatManager.statusVersion;
    if (!chatManager.consumeStatusVersion(chatManager.statusVersion) ||
        !chatManager.shouldShowStatusSnackBar(message)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showTopToast(context, message, isSuccess: !_isErrorStatusMessage(message));
    });
  }

  bool _isErrorStatusMessage(String message) {
    return message.contains('失败') ||
        message.contains('错误') ||
        message.contains('异常') ||
        message.contains('超时') ||
        message.contains('不可用') ||
        message.contains('无法');
  }

  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final value = _textController.value;
    final isComposing = value.composing.isValid && !value.composing.isCollapsed;
    if (isComposing) {
      return KeyEventResult.ignored;
    }
    unawaited(_sendText());
    return KeyEventResult.handled;
  }

  Widget _buildSidebar(
    BuildContext context,
    ChatRoomSection section, {
    VoidCallback? onEntryActivated,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.of(context).size.width < 600;
    final sectionCards = section == ChatRoomSection.channels
        ? [
            _buildSectionCard(
              context: context,
              compact: compact,
              title: '大厅和房间',
              count: _lobbyConversations.length + _roomConversations.length,
              child: _buildRoomConversationList(
                onEntryActivated: onEntryActivated,
              ),
            ),
          ]
        : [
            _buildSectionCard(
              context: context,
              compact: compact,
              title: '私信会话',
              count: _directConversations.length,
              child: _buildConversationList(
                _directConversations,
                emptyTitle: '还没有私信会话',
                emptySubtitle: '从在线成员发起私聊后会出现在这里',
                onEntryActivated: onEntryActivated,
              ),
            ),
            _buildSectionCard(
              context: context,
              compact: compact,
              title: '在线成员',
              count: _onlinePeers.length,
              child: _buildOnlinePeerList(
                onEntryActivated: onEntryActivated,
              ),
            ),
          ];
    return Container(
      color: colorScheme.surface,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 16,
          compact ? 8 : 14,
          compact ? 8 : 16,
          compact ? 12 : 20,
        ),
        children: [
          _buildDebugToolsCard(context, compact: compact),
          SizedBox(height: compact ? 8 : 14),
          _buildResponsiveCardGrid(
            sectionCards,
            compact: compact,
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveCardGrid(
    List<Widget> children, {
    bool compact = false,
  }) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = compact ? 8.0 : 14.0;
        final minCardWidth = compact ? 260.0 : 300.0;
        var columns =
            ((constraints.maxWidth + spacing) / (minCardWidth + spacing))
                .floor();
        if (columns < 1) {
          columns = 1;
        }
        if (columns > children.length) {
          columns = children.length;
        }
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: cardWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }

  Widget _buildDebugToolsCard(BuildContext context, {bool compact = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final outlinedButtonStyle = OutlinedButton.styleFrom(
      backgroundColor: colorScheme.surface.withOpacity(0.82),
      disabledBackgroundColor: colorScheme.surface.withOpacity(0.46),
      side: BorderSide(color: colorScheme.primary.withOpacity(0.18)),
    );
    final tonalButtonStyle = FilledButton.styleFrom(
      backgroundColor: colorScheme.surface.withOpacity(0.82),
      disabledBackgroundColor: colorScheme.surface.withOpacity(0.46),
      foregroundColor: colorScheme.primary,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withOpacity(0.14),
            colorScheme.secondaryContainer.withOpacity(0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        border: Border.all(color: colorScheme.primary.withOpacity(0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 32 : 38,
                  height: compact ? 32 : 38,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    color: colorScheme.primary,
                    size: compact ? 19 : null,
                  ),
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Text(
                    widget.section == ChatRoomSection.channels ? '聊天室' : '私信',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 15 : null,
                        ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 5 : 10),
            Text(
              '网络 ${_connectedNetworkKeys.length} 个 · 在线设备 ${_onlinePeers.length} 个',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: compact ? 8 : 14),
            Wrap(
              spacing: compact ? 6 : 8,
              runSpacing: compact ? 6 : 8,
              children: [
                OutlinedButton.icon(
                  style: compact
                      ? outlinedButtonStyle.merge(_compactButtonStyle(context))
                      : outlinedButtonStyle,
                  onPressed:
                      _isRefreshingDiscovery ? null : _refreshDiscovery,
                  icon: _isRefreshingDiscovery
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isRefreshingDiscovery ? '刷新中' : '刷新发现'),
                ),
                if (widget.section == ChatRoomSection.channels)
                  OutlinedButton.icon(
                    style: compact
                        ? outlinedButtonStyle.merge(_compactButtonStyle(context))
                        : outlinedButtonStyle,
                    onPressed: _connectedNetworkKeys.isEmpty
                        ? null
                        : _showCreateChannelDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('创建房间'),
                  ),
                OutlinedButton.icon(
                  style: compact
                      ? outlinedButtonStyle.merge(_compactButtonStyle(context))
                      : outlinedButtonStyle,
                  onPressed: chatManager.isBuildingDiagnostics
                      ? null
                      : _showDiagnosticsDialog,
                  icon: chatManager.isBuildingDiagnostics
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.medical_information_outlined),
                  label:
                      Text(chatManager.isBuildingDiagnostics ? '加载中' : '查看诊断'),
                ),
                FilledButton.tonalIcon(
                  style: compact
                      ? tonalButtonStyle.merge(_compactFilledButtonStyle(context))
                      : tonalButtonStyle,
                  onPressed: _confirmClearChatData,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('清空聊天数据'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    bool compact = false,
    required String title,
    required int count,
    required Widget child,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.34),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.45)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 15 : null,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
            SizedBox(height: compact ? 8 : 12),
            SizedBox(
              height: compact ? 225 : 280,
              child: SingleChildScrollView(
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _compactButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      textStyle: Theme.of(context).textTheme.labelMedium,
    );
  }

  ButtonStyle _compactFilledButtonStyle(BuildContext context) {
    return FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      textStyle: Theme.of(context).textTheme.labelMedium,
    );
  }

  Widget _buildConversationList(
    List<ChatConversationSummary> conversations, {
    required String emptyTitle,
    required String emptySubtitle,
    VoidCallback? onEntryActivated,
  }) {
    if (conversations.isEmpty) {
      return _buildEmptyHint(emptyTitle, emptySubtitle);
    }
    return Column(
      children: conversations.map((conversation) {
        final selected =
            chatManager.selectedConversationId == conversation.conversationId;
        final title = conversation.title.isEmpty ? '未命名会话' : conversation.title;
        return _buildSelectableTile(
          selected: selected,
          onTap: () {
            onEntryActivated?.call();
            chatManager.selectConversation(conversation.conversationId);
          },
          title: title,
          subtitle: conversation.lastPreview.isEmpty
              ? '暂无消息'
              : conversation.lastPreview,
          trailing: conversation.unreadCount > 0
              ? _buildUnreadBadge(conversation.unreadCount)
              : null,
        );
      }).toList(),
    );
  }

  Widget _buildLobbyConversationList({VoidCallback? onEntryActivated}) {
    if (_lobbyConversations.isEmpty) {
      return _buildEmptyHint('默认大厅尚未就绪', '连接组网后会自动创建默认大厅');
    }
    return Column(
      children: _lobbyConversations.map((conversation) {
        final selected =
            chatManager.selectedConversationId == conversation.conversationId;
        final subtitle = _hasMultipleNetworks
            ? '${conversation.networkKey} · 默认公共大厅'
            : '默认公共大厅';
        return _buildSelectableTile(
          selected: selected,
          accentColor: Theme.of(context).colorScheme.primary,
          onTap: () {
            onEntryActivated?.call();
            chatManager.selectConversation(conversation.conversationId);
          },
          title: conversation.title,
          subtitle: subtitle,
          trailing: conversation.unreadCount > 0
              ? _buildUnreadBadge(conversation.unreadCount)
              : null,
        );
      }).toList(),
    );
  }

  Widget _buildRoomConversationList({VoidCallback? onEntryActivated}) {
    final conversations = [
      ..._lobbyConversations,
      ..._roomConversations,
    ];
    if (conversations.isEmpty) {
      return _buildEmptyHint('大厅尚未就绪', '连接组网后会自动创建大厅');
    }
    return Column(
      children: conversations.map((conversation) {
        final selected =
            chatManager.selectedConversationId == conversation.conversationId;
        final isLobby = ChatManager.isLobbyChannelId(conversation.channelId);
        final channel = conversation.channelId == null
            ? null
            : _scopedChannels
                .where((item) => item.channelId == conversation.channelId)
                .cast<ChatChannel?>()
                .firstOrNull;
        final roomTypeLabel = isLobby
            ? '默认公共大厅'
            : (channel?.isPrivate == true ? '私密房间' : '公开房间');
        final passwordLabel = channel?.passwordHash.isNotEmpty == true &&
                channel?.joined != true
            ? ' · 需密码'
            : '';
        final subtitle = _hasMultipleNetworks
            ? '${conversation.networkKey} · $roomTypeLabel$passwordLabel'
            : '$roomTypeLabel$passwordLabel';
        return _buildSelectableTile(
          selected: selected,
          accentColor: isLobby
              ? Theme.of(context).colorScheme.primary
              : (channel?.isPrivate == true
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.secondary),
          tags: isLobby
              ? const []
              : [_buildRoomTypeTag(channel?.isPrivate == true)],
          onTap: () {
            onEntryActivated?.call();
            chatManager.selectConversation(conversation.conversationId);
          },
          title: conversation.title,
          subtitle: subtitle,
          trailing: conversation.unreadCount > 0
              ? _buildUnreadBadge(conversation.unreadCount)
              : null,
        );
      }).toList(),
    );
  }

  Widget _buildChannelList() {
    if (_scopedChannels.isEmpty) {
      return _buildEmptyHint('还没有频道', '点击右上角创建公开频道或私密频道');
    }
    return Column(
      children: _scopedChannels.map((channel) {
        final conversationId = ChatIds.channelConversationId(
          channel.networkKey,
          channel.channelId,
        );
        final selected = chatManager.selectedConversationId == conversationId;
        final isOwner = chatManager.isChannelOwner(channel);
        return _buildSelectableTile(
          selected: selected,
          onTap: () => chatManager.selectConversation(conversationId),
          title: channel.name,
          subtitle: channel.isPrivate
              ? (channel.joined
                  ? '私密频道 · 已加入'
                  : '私密频道 · 待加入${channel.passwordHash.isNotEmpty ? ' · 需密码' : ''}')
              : (channel.joined
                  ? '公开频道 · 已加入'
                  : '公开频道${channel.passwordHash.isNotEmpty ? ' · 需密码' : ''}'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'join') {
                unawaited(_joinChannel(channel));
              } else if (value == 'leave') {
                chatManager.leaveChannel(channel);
              } else if (value == 'voice') {
                chatManager.joinChannelVoice(channel);
              } else if (value == 'rename') {
                _showRenameChannelDialog(channel);
              } else if (value == 'members') {
                _showManageMembersDialog(channel);
              } else if (value == 'invite') {
                _showInviteMembersDialog(channel);
              } else if (value == 'archive') {
                chatManager.archiveChannel(channel);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: channel.joined ? 'leave' : 'join',
                child: Text(channel.joined ? '退出频道' : '加入频道'),
              ),
              PopupMenuItem(
                value: 'voice',
                enabled: chatManager.isChatAudioSupported,
                child: Text(
                  chatManager.isChatAudioSupported ? '进入语音' : '进入语音（当前平台不支持）',
                ),
              ),
              if (isOwner)
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('频道改名'),
                ),
              if (isOwner)
                const PopupMenuItem(
                  value: 'members',
                  child: Text('管理成员'),
                ),
              if (isOwner)
                const PopupMenuItem(
                  value: 'invite',
                  child: Text('邀请成员'),
                ),
              if (isOwner)
                const PopupMenuItem(
                  value: 'archive',
                  child: Text('归档频道'),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFriendList() {
    if (chatManager.friendPeers.isEmpty) {
      return _buildEmptyHint('还没有好友', '可以先从在线设备发起好友申请');
    }
    return Column(
      children: chatManager.friendPeers.map((peer) {
        final status = chatManager.friendStatusOf(peer.peerId);
        final subtitle = switch (status) {
          ChatFriendStatus.pending => '等待处理',
          ChatFriendStatus.friend => peer.isOnline ? '在线' : '离线',
          ChatFriendStatus.blocked => '已拉黑',
          ChatFriendStatus.stranger => '陌生人',
        };
        return _buildSelectableTile(
          selected: false,
          onTap: status == ChatFriendStatus.blocked
              ? () => _showRemarkDialog(peer)
              : () => chatManager.openDirectConversation(peer),
          title: peer.displayName,
          subtitle:
              '${peer.virtualIp}${_hasMultipleNetworks ? ' · ${peer.networkKey}' : ''} · $subtitle',
          trailing: status == ChatFriendStatus.pending
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => chatManager.acceptFriend(peer.peerId),
                      tooltip: '通过',
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                    IconButton(
                      onPressed: () => chatManager.rejectFriend(peer.peerId),
                      tooltip: '拒绝',
                      icon: const Icon(Icons.cancel_outlined),
                    ),
                  ],
                )
              : PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'chat') {
                      chatManager.openDirectConversation(peer);
                    } else if (value == 'remark') {
                      _showRemarkDialog(peer);
                    } else if (value == 'remove') {
                      chatManager.removeFriend(peer.peerId);
                    } else if (value == 'block') {
                      chatManager.blockPeer(peer.peerId);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'chat', child: Text('发起私聊')),
                    PopupMenuItem(value: 'remark', child: Text('设置备注')),
                    PopupMenuItem(value: 'remove', child: Text('删除好友')),
                    PopupMenuItem(value: 'block', child: Text('拉黑')),
                  ],
                ),
        );
      }).toList(),
    );
  }

  Widget _buildOnlinePeerList({VoidCallback? onEntryActivated}) {
    if (_onlinePeers.isEmpty) {
      return _buildEmptyHint('暂无在线设备', '等待其他设备加入当前组网');
    }
    return Column(
      children: _onlinePeers.map((peer) {
        final friendStatus = chatManager.friendStatusOf(peer.peerId);
        return _buildSelectableTile(
          selected: false,
          onTap: () {
            onEntryActivated?.call();
            chatManager.openDirectConversation(peer);
          },
          onSecondaryTapDown: (details) =>
              _showPeerContextMenu(peer, details.globalPosition),
          title: chatPeerPrimaryName(peer),
          subtitle: buildOnlinePeerSubtitle(
            peer,
            hasMultipleNetworks: _hasMultipleNetworks,
            friendStatus: friendStatus,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => chatManager.openDirectConversation(peer),
                tooltip: '私聊',
                icon: const Icon(Icons.chat_bubble_outline),
              ),
              IconButton(
                onPressed: friendStatus != ChatFriendStatus.stranger
                    ? null
                    : () => chatManager.requestFriend(peer),
                tooltip: '加好友',
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _showPeerContextMenu(
    ChatPeer peer,
    Offset globalPosition,
  ) async {
    final friendStatus = chatManager.friendStatusOf(peer.peerId);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(value: 'chat', child: Text('发起私信')),
        const PopupMenuItem(value: 'request_control', child: Text('请求控制')),
        const PopupMenuItem(value: 'invite_control', child: Text('邀请控制')),
        if (friendStatus == ChatFriendStatus.stranger)
          const PopupMenuItem(value: 'friend', child: Text('加好友')),
        const PopupMenuItem(value: 'remark', child: Text('设置备注')),
        const PopupMenuItem(value: 'block', child: Text('拉黑')),
      ],
    );
    if (selected == null) {
      return;
    }
    if (selected == 'chat') {
      await chatManager.openDirectConversation(peer);
      return;
    }
    if (selected == 'request_control') {
      await chatManager.requestRemoteControl(peer);
      return;
    }
    if (selected == 'invite_control') {
      await chatManager.inviteRemoteControl(peer);
      return;
    }
    if (selected == 'friend') {
      await chatManager.requestFriend(peer);
      return;
    }
    if (selected == 'remark') {
      await _showRemarkDialog(peer);
      return;
    }
    if (selected == 'block') {
      await chatManager.blockPeer(peer.peerId);
    }
  }

  Future<void> _joinChannel(ChatChannel channel) async {
    if (!chatManager.channelRequiresPassword(channel)) {
      await chatManager.joinChannel(channel);
      return;
    }
    final password = await _showChannelPasswordDialog(channel);
    if (password == null) {
      return;
    }
    await chatManager.joinChannel(channel, password: password);
  }

  Future<String?> _showChannelPasswordDialog(ChatChannel channel) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('加入 ${channel.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '频道密码',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) =>
                Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('加入'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget _buildSelectableTile({
    required bool selected,
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color? accentColor,
    List<Widget> tags = const [],
    void Function(TapDownDetails details)? onSecondaryTapDown,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.of(context).size.width < 600;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: EdgeInsets.only(bottom: compact ? 5 : 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withOpacity(0.10)
            : (accentColor?.withOpacity(0.08) ??
                colorScheme.surface.withOpacity(0.42)),
        borderRadius: BorderRadius.circular(compact ? 9 : 11),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withOpacity(0.24)
              : (accentColor?.withOpacity(0.20) ??
                  colorScheme.outlineVariant.withOpacity(0.20)),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: onSecondaryTapDown,
        child: ListTile(
          dense: true,
          minVerticalPadding: compact ? 4 : null,
          contentPadding:
              EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 0 : 4,
          ),
          shape:
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(compact ? 9 : 11)),
          onTap: onTap,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: compact ? 14 : null,
                  ),
                ),
              ),
              for (final tag in tags) ...[
                const SizedBox(width: 8),
                tag,
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
          trailing: trailing,
        ),
      ),
    );
  }

  Widget _buildRoomTypeTag(bool isPrivate) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isPrivate ? colorScheme.tertiary : colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        isPrivate ? '私密' : '公开',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildUnreadBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  bool _conversationMatchesCurrentSection(
      ChatConversationSummary? conversation) {
    if (conversation == null ||
        !chatMatchesNetworkScope(conversation.networkKey, _scopedNetworkKey)) {
      return false;
    }
    return switch (widget.section) {
      ChatRoomSection.channels =>
        conversation.type == ChatConversationType.channel,
      ChatRoomSection.directMessages =>
        conversation.type == ChatConversationType.direct,
    };
  }

  bool _shouldShowConversationOnlyOnNarrow() {
    return _conversationMatchesCurrentSection(chatManager.selectedConversation);
  }

  void _showSidebarSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final height = MediaQuery.of(sheetContext).size.height * 0.82;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: SafeArea(
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildSidebar(
                sheetContext,
                widget.section,
                onEntryActivated: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConversationPane(
    BuildContext context, {
    VoidCallback? onShowSidebar,
  }) {
    final conversation = chatManager.selectedConversation;
    final section = widget.section;
    if (section == ChatRoomSection.channels &&
        _channelConversations.isNotEmpty &&
        conversation == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureInitialChannelSelection());
      });
    }
    if (!_conversationMatchesCurrentSection(conversation)) {
      return Center(
        child: _buildEmptyHint(
          section == ChatRoomSection.channels ? '聊天室已启用' : '私信已启用',
          section == ChatRoomSection.channels
              ? '从大厅选择默认大厅或房间后开始交流'
              : '从左侧私信会话或在线成员开始一对一聊天',
        ),
      );
    }
    final activeConversation = conversation!;
    final peer = chatManager.findPeer(activeConversation.peerId);
    final channel = activeConversation.channelId == null
        ? null
        : _scopedChannels
            .where((item) => item.channelId == activeConversation.channelId)
            .cast<ChatChannel?>()
            .firstOrNull;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerLowest.withOpacity(0.35),
      child: Column(
        children: [
          _buildConversationHeader(
            activeConversation,
            peer,
            channel,
            onShowSidebar: onShowSidebar,
          ),
          if (chatManager.callSession?.isIncoming == true &&
              chatManager.callSession?.state == ChatCallState.ringing)
            _buildIncomingCallBanner(),
          if (chatManager.remoteAssistSession?.peerId ==
              activeConversation.peerId)
            _buildRemoteAssistBanner(peer),
          Expanded(
            child: chatManager.activeMessages.isEmpty
                ? Center(
                    child: _buildEmptyHint('暂无消息', '现在可以发送文字、图片、文件和语音'),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width >= 980
                          ? 28
                          : 14,
                      vertical: 18,
                    ),
                    itemCount: chatManager.activeMessages.length,
                    itemBuilder: (context, index) {
                      final message = chatManager.activeMessages[index];
                      return _buildMessageItem(message);
                    },
                  ),
          ),
          _buildInputBar(activeConversation, channel),
        ],
      ),
    );
  }

  Widget _buildConversationHeader(ChatConversationSummary conversation,
      ChatPeer? peer, ChatChannel? channel,
      {VoidCallback? onShowSidebar}) {
    final session = chatManager.callSession;
    final isDirectCall = session?.type == ChatCallType.direct &&
        session?.peerId == conversation.peerId &&
        session?.state != ChatCallState.ended;
    final isChannelVoice = session?.type == ChatCallType.channel &&
        session?.channelId == conversation.channelId &&
        session?.joinedVoice == true;
    final audioSupported = chatManager.isChatAudioSupported;
    final remoteAssistReason = peer == null
        ? '当前会话不支持远程协助'
        : chatManager.remoteAssistUnavailableMessageForPeer(peer);
    final subtitle = conversation.type == ChatConversationType.direct
        ? '${peer?.virtualIp ?? ''} · ${peer?.isOnline == true ? '在线' : '离线'}'
        : ChatManager.isLobbyChannelId(conversation.channelId)
            ? '默认公共大厅'
            : '${channel?.isPrivate == true ? '私密房间' : '公开房间'} · ${channel?.joined == true ? '已加入' : '未加入'}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.94),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final actions = <Widget>[
            if (conversation.type == ChatConversationType.direct && peer != null)
              IconButton(
                onPressed: remoteAssistReason == null
                    ? () => chatManager.inviteRemoteControl(peer)
                    : null,
                tooltip: remoteAssistReason ?? '邀请对方控制当前设备',
                icon: const Icon(Icons.screen_share_outlined),
              ),
            if (conversation.type == ChatConversationType.direct && peer != null)
              IconButton(
                onPressed: remoteAssistReason == null
                    ? () => chatManager.requestRemoteControl(peer)
                    : null,
                tooltip: remoteAssistReason ?? '请求控制对方设备',
                icon: const Icon(Icons.control_camera_outlined),
              ),
            if (conversation.type == ChatConversationType.direct && peer != null)
              IconButton(
                onPressed: audioSupported
                    ? (isDirectCall
                        ? chatManager.hangupCall
                        : (peer.isOnline
                            ? () => chatManager.startPrivateCall(peer)
                            : null))
                    : null,
                tooltip: audioSupported
                    ? (isDirectCall ? '挂断语音' : '发起语音')
                    : chatManager.chatAudioUnsupportedReason,
                icon: Icon(isDirectCall ? Icons.call_end : Icons.call),
              ),
            if (conversation.type == ChatConversationType.channel &&
                channel != null)
              FilledButton.tonalIcon(
                onPressed: audioSupported
                    ? (isChannelVoice
                        ? chatManager.leaveChannelVoice
                        : () => chatManager.joinChannelVoice(channel))
                    : null,
                icon:
                    Icon(isChannelVoice ? Icons.headset_off : Icons.headset_mic),
                label: Text(isChannelVoice ? '离开语音' : '加入语音'),
              ),
          ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onShowSidebar != null)
                IconButton(
                  onPressed: onShowSidebar,
                  tooltip: widget.section == ChatRoomSection.channels
                      ? '切换大厅和房间'
                      : '切换私信会话',
                  icon: const Icon(Icons.view_list_rounded),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (audioSupported &&
                        chatManager.chatAudioHeadsetRecommended)
                      Text(
                        '语音建议佩戴耳机或耳麦',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (compact)
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                )
              else
                Row(mainAxisSize: MainAxisSize.min, children: actions),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIncomingCallBanner() {
    final session = chatManager.callSession;
    final caller = chatManager.findPeer(session?.peerId);
    final audioSupported = chatManager.isChatAudioSupported;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.ring_volume),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${caller?.displayName ?? '对方'} 正在呼叫你',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: chatManager.rejectIncomingCall,
            child: const Text('拒绝'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: audioSupported ? chatManager.acceptIncomingCall : null,
            child: Text(audioSupported ? '接听' : '暂不支持'),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteAssistBanner(ChatPeer? peer) {
    final session = chatManager.remoteAssistSession;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final title = session.mode == RemoteAssistMode.requestControl
        ? (session.isIncoming
            ? '${peer?.displayName ?? '对方'} 请求控制当前设备'
            : '已向对方发送控制请求')
        : (session.isIncoming
            ? '${peer?.displayName ?? '对方'} 邀请你去控制其设备'
            : '已邀请对方来控制当前设备');
    final subtitle = switch (session.state) {
      RemoteAssistState.pending => session.isIncoming ? '等待你处理' : '等待对方处理',
      RemoteAssistState.accepted => '对方已同意，准备启动远程协助',
      RemoteAssistState.ready => '远程协助准备完成',
      RemoteAssistState.active => '远程协助会话已启动',
      RemoteAssistState.rejected => '远程协助请求已被拒绝',
      RemoteAssistState.ended => '远程协助会话已结束',
      RemoteAssistState.failed => '远程协助启动失败',
    };
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.desktop_windows_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (session.isIncoming && session.state == RemoteAssistState.pending)
            TextButton(
              onPressed: chatManager.rejectRemoteAssist,
              child: const Text('拒绝'),
            ),
          if (session.isIncoming && session.state == RemoteAssistState.pending)
            const SizedBox(width: 8),
          if (session.isIncoming && session.state == RemoteAssistState.pending)
            FilledButton(
              onPressed: chatManager.acceptRemoteAssist,
              child: const Text('同意'),
            ),
          if (!session.isIncoming && session.state == RemoteAssistState.pending)
            FilledButton.tonal(
              onPressed: chatManager.cancelRemoteAssist,
              child: const Text('取消'),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message) {
    final isOutgoing = message.direction == ChatMessageDirection.outgoing;
    final peer = chatManager.findPeer(message.senderPeerId);
    final colorScheme = Theme.of(context).colorScheme;
    final senderInfo = _senderTooltip(message);
    final bubbleColor = isOutgoing
        ? colorScheme.primary.withOpacity(0.13)
        : colorScheme.surface.withOpacity(0.86);
    final bubbleBorderColor = isOutgoing
        ? colorScheme.primary.withOpacity(0.18)
        : colorScheme.outlineVariant.withOpacity(0.28);
    final failed = message.status == ChatMessageStatus.failed;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth =
            constraints.maxWidth < 720 ? constraints.maxWidth * 0.84 : 560.0;
        final bubble = GestureDetector(
          onLongPressStart: (details) => _showMessageActions(
            message,
            details.globalPosition,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isOutgoing)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: CustomPaint(
                    size: const Size(9, 14),
                    painter: _BubbleTailPainter(
                      color: bubbleColor,
                      borderColor: bubbleBorderColor,
                      pointsRight: false,
                    ),
                  ),
                ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: bubbleBorderColor),
                  ),
                  child: _buildMessageContent(message),
                ),
              ),
              if (isOutgoing)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: CustomPaint(
                    size: const Size(9, 14),
                    painter: _BubbleTailPainter(
                      color: bubbleColor,
                      borderColor: bubbleBorderColor,
                      pointsRight: true,
                    ),
                  ),
                ),
            ],
          ),
        );
        final statusTime = Wrap(
          spacing: 8,
          runSpacing: 2,
          alignment: isOutgoing ? WrapAlignment.end : WrapAlignment.start,
          children: [
            Text(
              _statusText(message.status, message.attachmentId != null),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Tooltip(
              message: _formatFullDateTime(message.receivedAt),
              waitDuration: const Duration(milliseconds: 350),
              child: GestureDetector(
                onTap: () => _showInfoSnackBar(
                  _formatFullDateTime(message.receivedAt),
                ),
                child: Text(
                  TimeOfDay.fromDateTime(message.receivedAt).format(context),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        );
        final senderName = isOutgoing
            ? '我'
            : (peer?.displayName ?? message.senderPeerId);
        final nameWidget = Tooltip(
          message: senderInfo,
          waitDuration: const Duration(milliseconds: 350),
          child: GestureDetector(
            onTap: () => _showInfoSnackBar(senderInfo),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        );
        final messageRow = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOutgoing) ...[
              nameWidget,
              const SizedBox(width: 8),
            ],
            if (failed) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '发送失败，点击重试',
                  onPressed: () => _showRetryFailedMessage(message),
                  icon: const Icon(
                    Icons.error,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
            Flexible(child: bubble),
            if (isOutgoing) ...[
              const SizedBox(width: 8),
              nameWidget,
            ],
          ],
        );
        return Align(
          alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: isOutgoing
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  messageRow,
                  const SizedBox(height: 4),
                  statusTime,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _senderTooltip(ChatMessage message) {
    return chatManager.peerDeviceInfo(message.senderPeerId, message.networkKey);
  }

  String _formatFullDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  void _showInfoSnackBar(String text) {
    showTopToast(context, text, isSuccess: true);
  }

  Future<void> _showRetryFailedMessage(ChatMessage message) async {
    showTopToast(
      context,
      message.kind == ChatMessageKind.text ? '正在重试发送消息' : '请重新选择附件发送',
      isSuccess: message.kind == ChatMessageKind.text,
    );
    if (message.kind == ChatMessageKind.text) {
      unawaited(chatManager.retryMessage(message.messageId));
    } else if (message.kind == ChatMessageKind.image) {
      unawaited(chatManager.sendPickedImage());
    } else {
      unawaited(chatManager.sendPickedFile());
    }
  }

  Future<void> _showMessageActions(
    ChatMessage message,
    Offset position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('复制')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _messageCopyText(message)));
      if (!mounted) {
        return;
      }
      _showInfoSnackBar('已复制');
    } else if (action == 'delete') {
      await chatManager.deleteMessage(message.messageId);
    }
  }

  String _messageCopyText(ChatMessage message) {
    if (message.kind == ChatMessageKind.text) {
      return message.text;
    }
    final fileName = message.metadata['fileName'] as String?;
    return fileName?.isNotEmpty == true
        ? fileName!
        : _statusText(message.status, message.attachmentId != null);
  }

  Widget _buildMessageContent(ChatMessage message) {
    return FutureBuilder<ChatAttachment?>(
      future: message.attachmentId == null
          ? Future.value(null)
          : ChatRepository.instance.getAttachment(message.attachmentId!),
      builder: (context, snapshot) {
        final attachment = snapshot.data;
        if (message.kind == ChatMessageKind.text || attachment == null) {
          return Text(message.text);
        }
        final canAccept = message.direction == ChatMessageDirection.incoming &&
            message.status == ChatMessageStatus.awaitingAccept;
        final hasFile = attachment.localPath.isNotEmpty &&
            File(attachment.localPath).existsSync();
        final widgets = <Widget>[];
        if (message.kind == ChatMessageKind.image && hasFile) {
          widgets.add(
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(attachment.localPath),
                width: 220,
                height: 160,
                fit: BoxFit.cover,
              ),
            ),
          );
          widgets.add(const SizedBox(height: 8));
        } else {
          widgets.add(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  message.kind == ChatMessageKind.voiceNote
                      ? Icons.keyboard_voice_outlined
                      : Icons.insert_drive_file_outlined,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    attachment.fileName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
          widgets.add(const SizedBox(height: 8));
        }
        widgets.add(
          Text(
            '${(attachment.size / 1024).toStringAsFixed(1)} KB',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
        if (message.kind == ChatMessageKind.voiceNote &&
            hasFile &&
            message.status == ChatMessageStatus.transferred) {
          widgets.add(const SizedBox(height: 8));
          widgets.add(
            FilledButton.tonalIcon(
              onPressed: chatManager.isChatAudioSupported
                  ? () => chatManager.playVoiceMessage(message)
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放语音'),
            ),
          );
        }
        if (canAccept) {
          widgets.add(const SizedBox(height: 12));
          widgets.add(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () =>
                      chatManager.rejectAttachment(attachment.attachmentId),
                  child: const Text('拒绝'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      chatManager.acceptAttachment(attachment.attachmentId),
                  child: const Text('接收'),
                ),
              ],
            ),
          );
        }
        if (message.direction == ChatMessageDirection.outgoing &&
            message.status == ChatMessageStatus.awaitingAccept) {
          widgets.add(const SizedBox(height: 8));
          widgets.add(
            Text(
              '等待对方确认接收',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgets,
        );
      },
    );
  }

  String _statusText(ChatMessageStatus status, bool hasAttachment) {
    return switch (status) {
      ChatMessageStatus.pending => '发送中',
      ChatMessageStatus.sent => '已发送',
      ChatMessageStatus.delivered => '已送达',
      ChatMessageStatus.failed => '失败',
      ChatMessageStatus.awaitingAccept => hasAttachment ? '待接收' : '待处理',
      ChatMessageStatus.accepted => '已同意',
      ChatMessageStatus.rejected => '已拒绝',
      ChatMessageStatus.transferred => '已接收',
      ChatMessageStatus.expired => '已过期',
    };
  }

  Widget _buildInputBar(
    ChatConversationSummary conversation,
    ChatChannel? channel,
  ) {
    final session = chatManager.callSession;
    final isChannelVoice = session?.type == ChatCallType.channel &&
        session?.channelId == conversation.channelId &&
        session?.joinedVoice == true;
    final audioSupported = chatManager.isChatAudioSupported;
    final currentSpeaker = session?.speakerPeerId?.isNotEmpty == true
        ? chatManager.findPeer(session!.speakerPeerId)?.displayName ??
            session.speakerPeerId
        : '暂无';
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          if (!audioSupported)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${chatManager.chatAudioUnsupportedReason}，文字、图片和文件聊天不受影响',
                    ),
                  ),
                ],
              ),
            ),
          if (audioSupported && chatManager.chatAudioHeadsetRecommended)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.headphones_outlined),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Windows 语音聊天建议佩戴耳机或耳麦，以获得更稳定的通话效果'),
                  ),
                ],
              ),
            ),
          if (chatManager.isVoiceRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.mic, color: Colors.red),
                  SizedBox(width: 8),
                  Text('正在录制语音，松开发送，移出取消'),
                ],
              ),
            ),
          if (session?.type == ChatCallType.direct &&
              session?.state != ChatCallState.ended &&
              conversation.peerId == session?.peerId)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.call),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session?.state == ChatCallState.active
                          ? '语音通话中'
                          : '等待对方接听...',
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: chatManager.hangupCall,
                    child: const Text('挂断'),
                  ),
                ],
              ),
            ),
          if (isChannelVoice)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.multitrack_audio),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '房间语音中 · ${session?.participants.length ?? 1} 人 · 当前发言: $currentSpeaker',
                    ),
                  ),
                  Listener(
                    onPointerDown: (_) => chatManager.requestPtt(),
                    onPointerUp: (_) => chatManager.releasePtt(),
                    onPointerCancel: (_) => chatManager.releasePtt(),
                    child: FilledButton(
                      onPressed: () {},
                      child: const Text('按住说话'),
                    ),
                  ),
                ],
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final tools = <Widget>[
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showEmojiPicker = !_showEmojiPicker;
                    });
                  },
                  tooltip: '表情',
                  icon: Icon(_showEmojiPicker
                      ? Icons.keyboard_alt_outlined
                      : Icons.emoji_emotions_outlined),
                ),
                IconButton(
                  onPressed: chatManager.isSendingAttachment
                      ? null
                      : chatManager.sendPickedImage,
                  tooltip: chatManager.isSendingAttachment ? '附件发送中' : '发送图片',
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton(
                  onPressed: chatManager.isSendingAttachment
                      ? null
                      : chatManager.sendPickedFile,
                  tooltip: chatManager.isSendingAttachment ? '附件发送中' : '发送文件',
                  icon: const Icon(Icons.attach_file),
                ),
                if (audioSupported)
                  Listener(
                    onPointerDown: (_) {
                      unawaited(chatManager.startVoiceNoteRecording());
                    },
                    onPointerUp: (_) {
                      unawaited(chatManager.finishVoiceNoteRecording());
                    },
                    onPointerCancel: (_) =>
                        unawaited(chatManager.cancelVoiceNoteRecording()),
                    child: IconButton(
                      onPressed: () {},
                      tooltip: '按住录语音',
                      icon: const Icon(Icons.keyboard_voice_outlined),
                    ),
                  )
                else
                  IconButton(
                    onPressed: null,
                    tooltip: chatManager.chatAudioUnsupportedReason,
                    icon: const Icon(Icons.keyboard_voice_outlined),
                  ),
              ];
              final composer = Focus(
                onKeyEvent: _handleComposerKey,
                child: TextField(
                  controller: _textController,
                  maxLength: ChatManager.textLimit,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: '输入消息...',
                    counterText: '',
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.34),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withOpacity(0.7),
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _sendText(),
                ),
              );
              final inputRow = compact
                  ? Column(
                      children: [
                        composer,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: tools),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: _sendText,
                              icon: const Icon(Icons.send),
                              label: const Text('发送'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: composer),
                        const SizedBox(width: 8),
                        ...tools,
                        const SizedBox(width: 4),
                        FilledButton.icon(
                          onPressed: _sendText,
                          icon: const Icon(Icons.send),
                          label: const Text('发送'),
                        ),
                      ],
                    );
              return Column(
                children: [
                  inputRow,
                  if (_showEmojiPicker) ...[
                    const SizedBox(height: 8),
                    _buildEmojiPicker(),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _textController.text;
    _textController.clear();
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }
    await chatManager.sendTextMessage(text);
  }

  Widget _buildEmojiPicker() {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: colorScheme.surface,
        child: EmojiPicker(
          textEditingController: _textController,
          onEmojiSelected: (category, emoji) {},
          config: const Config(
            height: 260,
            checkPlatformCompatibility: true,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHint(String title, String subtitle) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.forum_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _showCreateChannelDialog() async {
    final connectedNetworks = _connectedNetworkKeys;
    if (connectedNetworks.isEmpty) {
      if (!mounted) {
        return;
      }
      showTopToast(context, '当前没有可用的已连接网络', isSuccess: false);
      return;
    }
    String? selectedNetworkKey = chatManager.preferredNetworkKey(
          scopedNetworkKey: _scopedNetworkKey,
        ) ??
        connectedNetworks.first;
    bool isPrivate = false;
    final selectedIds = <String>{};
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final currentNetworkKey = selectedNetworkKey ?? '';
            final candidates =
                chatManager.onlinePeersForNetwork(currentNetworkKey);
            final screenWidth = MediaQuery.of(context).size.width;
            final dialogWidth =
                screenWidth < 560 ? screenWidth - 64 : 420.0;
            return AlertDialog(
              title: const Text('创建房间'),
              content: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (connectedNetworks.length > 1) ...[
                      DropdownButtonFormField<String>(
                        value: selectedNetworkKey,
                        decoration: const InputDecoration(
                          labelText: '所属网络',
                          border: OutlineInputBorder(),
                        ),
                        items: connectedNetworks
                            .map(
                              (networkKey) => DropdownMenuItem(
                                value: networkKey,
                                child: Text(networkKey),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedNetworkKey = value;
                            selectedIds.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '房间名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '房间密码（可选）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isPrivate,
                      title: const Text('私密房间'),
                      subtitle: Text(
                        candidates.isEmpty
                            ? '暂无在线成员，也可以先创建本地私密房间'
                            : '私密房间只邀请指定成员',
                      ),
                      onChanged: (value) => setState(() => isPrivate = value),
                    ),
                    if (isPrivate) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 220,
                        child: candidates.isEmpty
                            ? const Center(child: Text('当前网络暂无在线成员'))
                            : ListView(
                                children: candidates.map((peer) {
                                  return CheckboxListTile(
                                    value: selectedIds.contains(peer.peerId),
                                    title: Text(peer.displayName),
                                    subtitle: Text(peer.virtualIp),
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          selectedIds.add(peer.peerId);
                                        } else {
                                          selectedIds.remove(peer.peerId);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
    if (created != true) {
      nameController.dispose();
      passwordController.dispose();
      return;
    }
    final trimmed = nameController.text.trim();
    final password = passwordController.text;
    nameController.dispose();
    passwordController.dispose();
    if (trimmed.isEmpty) {
      return;
    }
    final networkKey = selectedNetworkKey;
    if (networkKey == null) {
      return;
    }
    final invited = chatManager
        .onlinePeersForNetwork(networkKey)
        .where((peer) => selectedIds.contains(peer.peerId))
        .toList();
    try {
      await chatManager.createChannel(
        networkKey: networkKey,
        name: trimmed,
        isPrivate: isPrivate,
        password: password,
        invitedPeers: invited,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showTopToast(
        context,
        ChatManager.roomCreateFailureMessage(error),
        isSuccess: false,
      );
    }
  }

  Future<void> _showDiagnosticsDialog() async {
    if (chatManager.isBuildingDiagnostics) {
      return;
    }
    final reportFuture = chatManager.buildDiagnosticsReport();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('聊天室联调诊断'),
          content: SizedBox(
            width: 640,
            child: FutureBuilder<String>(
              future: reportFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return SingleChildScrollView(
                  child: SelectableText(
                    snapshot.data!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: _showChatDebugLogDialog,
              child: const Text('查看日志'),
            ),
            TextButton(
              onPressed: () async {
                final report = await reportFuture;
                final navigator = Navigator.of(context);
                await Clipboard.setData(ClipboardData(text: report));
                if (!mounted) {
                  return;
                }
                navigator.pop();
                showTopToast(this.context, '诊断信息已复制', isSuccess: true);
              },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showChatDebugLogDialog() async {
    final log = await chatManager.readChatDebugLog();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('chat-debug.log'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: SelectableText(
                log,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: log));
                if (!mounted) {
                  return;
                }
                showTopToast(this.context, '日志已复制', isSuccess: true);
              },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearChatData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空聊天室本地数据'),
          content: const Text(
            '这会删除当前机器上的聊天数据库、附件缓存、房间本地状态和聊天室日志。用于双机联调前清场，是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await chatManager.clearAllChatData();
  }

  Future<void> _showRenameChannelDialog(ChatChannel channel) async {
    final controller = TextEditingController(text: channel.name);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('频道改名'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '输入新的频道名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (saved == true) {
      await chatManager.renameChannel(channel, controller.text);
    }
    controller.dispose();
  }

  Future<void> _showInviteMembersDialog(ChatChannel channel) async {
    final allCandidates = _onlinePeers
        .where((peer) => peer.networkKey == channel.networkKey)
        .toList();
    final selectedIds = <String>{};
    final invited = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('邀请成员到 ${channel.name}'),
              content: SizedBox(
                width: 420,
                height: 300,
                child: ListView(
                  children: allCandidates.map((peer) {
                    return _buildDialogListItem(
                      child: CheckboxListTile(
                        value: selectedIds.contains(peer.peerId),
                        title: Text(chatPeerPrimaryName(peer)),
                        subtitle: Text(
                          buildMemberPeerSubtitle(
                            peer,
                            hasMultipleNetworks: _hasMultipleNetworks,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedIds.add(peer.peerId);
                            } else {
                              selectedIds.remove(peer.peerId);
                            }
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('邀请'),
                ),
              ],
            );
          },
        );
      },
    );
    if (invited != true) {
      return;
    }
    final peers = allCandidates
        .where((peer) => selectedIds.contains(peer.peerId))
        .toList();
    await chatManager.inviteMembersToChannel(channel, peers);
  }

  Future<void> _showManageMembersDialog(ChatChannel channel) async {
    final peers = await chatManager.channelPeers(channel);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('管理 ${channel.name} 成员'),
          content: SizedBox(
            width: 460,
            height: 320,
            child: peers.isEmpty
                ? const Center(child: Text('暂无成员'))
                : ListView(
                    children: peers.map((peer) {
                      final isOwner = peer.peerId == channel.ownerPeerId;
                      return _buildDialogListItem(
                        child: ListTile(
                          title: Text(chatPeerPrimaryName(peer)),
                          subtitle: Text(
                            buildMemberPeerSubtitle(
                              peer,
                              hasMultipleNetworks: _hasMultipleNetworks,
                              suffix: isOwner ? '房主' : null,
                            ),
                          ),
                          trailing: isOwner
                              ? const Text('房主')
                              : TextButton(
                                  onPressed: () async {
                                    Navigator.of(context).pop();
                                    await chatManager.removeMemberFromChannel(
                                      channel,
                                      peer,
                                    );
                                  },
                                  child: const Text('移除'),
                                ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogListItem({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.32)),
      ),
      child: child,
    );
  }

  Future<void> _showRemarkDialog(ChatPeer peer) async {
    final controller = TextEditingController(text: peer.remark);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('设置 ${peer.deviceName} 的备注'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '输入本地备注',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (saved == true) {
      await chatManager.updateRemark(peer.peerId, controller.text);
    }
    controller.dispose();
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({
    required this.color,
    required this.borderColor,
    required this.pointsRight,
  });

  final Color color;
  final Color borderColor;
  final bool pointsRight;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsRight) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, size.height / 2)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return color != oldDelegate.color ||
        borderColor != oldDelegate.borderColor ||
        pointsRight != oldDelegate.pointsRight;
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
