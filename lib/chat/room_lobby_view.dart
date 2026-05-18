import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_manager.dart';
import 'chat_models.dart';
import 'chat_peer_labels.dart';

class RoomLobbyView extends StatefulWidget {
  const RoomLobbyView({
    super.key,
    this.scopedNetworkKey,
    required this.onOpenChannelConversation,
    required this.onOpenDirectPeer,
  });

  final String? scopedNetworkKey;
  final Future<void> Function(String conversationId) onOpenChannelConversation;
  final Future<void> Function(ChatPeer peer) onOpenDirectPeer;

  @override
  State<RoomLobbyView> createState() => _RoomLobbyViewState();
}

class _RoomLobbyViewState extends State<RoomLobbyView> {
  int _lastStatusVersion = -1;

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
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatManager,
      builder: (context, _) {
        _showStatusSnackBarIfNeeded(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 520 ? 10.0 : 16.0;
            final sections = [
              _buildSectionCard(
                context: context,
                icon: Icons.forum_outlined,
                title: '默认大厅',
                subtitle: '每个已连接网络自动创建一个公共大厅',
                count: _lobbyConversations.length,
                child: _buildLobbyConversationList(),
              ),
              _buildSectionCard(
                context: context,
                icon: Icons.meeting_room_outlined,
                title: '房间',
                subtitle: '创建公开房间或邀请成员加入私密房间',
                count: _roomConversations.length,
                trailing: FilledButton.icon(
                  onPressed: _connectedNetworkKeys.isEmpty
                      ? null
                      : _showCreateRoomDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('创建房间'),
                ),
                child: _buildRoomList(),
              ),
              _buildSectionCard(
                context: context,
                icon: Icons.people_alt_outlined,
                title: '在线成员',
                subtitle: '点击成员发起私信，右键查看更多操作',
                count: _onlinePeers.length,
                child: _buildOnlinePeerList(),
              ),
            ];

            return ListView(
              padding: EdgeInsets.all(horizontalPadding),
              children: [
                _buildOverviewPanel(context),
                const SizedBox(height: 14),
                _buildDebugToolsCard(context),
                const SizedBox(height: 14),
                _buildResponsiveCardGrid(sections),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildResponsiveCardGrid(List<Widget> children) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        const minCardWidth = 320.0;
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

  Widget _buildOverviewPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasNetwork = _connectedNetworkKeys.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withOpacity(0.14),
            colorScheme.secondaryContainer.withOpacity(0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.72),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                hasNetwork ? Icons.hub_outlined : Icons.cloud_off_outlined,
                color: hasNetwork ? colorScheme.primary : colorScheme.outline,
                size: 26,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasNetwork ? '聊天室已连接' : '等待组网连接',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasNetwork
                        ? '可创建房间、进入大厅或向在线成员发起私信'
                        : '连接组网后会自动启用大厅、房间和私信',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _buildMetricChip(
              context,
              icon: Icons.lan_outlined,
              label: '网络',
              value: '${_connectedNetworkKeys.length}',
            ),
            _buildMetricChip(
              context,
              icon: Icons.meeting_room_outlined,
              label: '房间',
              value: '${_roomConversations.length}',
            ),
            _buildMetricChip(
              context,
              icon: Icons.people_alt_outlined,
              label: '在线',
              value: '${_onlinePeers.length}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  Widget _buildDebugToolsCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '联调工具',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '网络 ${_connectedNetworkKeys.length} 个 · 在线设备 ${_onlinePeers.length} 个',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => chatManager.debugRefreshNow(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新发现'),
                ),
                OutlinedButton.icon(
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
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobbyConversationList() {
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
          onTap: () => widget.onOpenChannelConversation(
            conversation.conversationId,
          ),
          title: conversation.title,
          subtitle: subtitle,
          trailing: conversation.unreadCount > 0
              ? _buildUnreadBadge(conversation.unreadCount)
              : null,
        );
      }).toList(),
    );
  }

  Widget _buildRoomList() {
    final rooms = _scopedChannels
        .where((channel) => !ChatManager.isLobbyChannelId(channel.channelId))
        .toList();
    if (rooms.isEmpty) {
      return _buildEmptyHint('还没有房间', '点击右上角创建公开房间或私密房间');
    }
    return Column(
      children: rooms.map((channel) {
        final conversationId = ChatIds.channelConversationId(
          channel.networkKey,
          channel.channelId,
        );
        final selected = chatManager.selectedConversationId == conversationId;
        final isOwner = chatManager.isChannelOwner(channel);
        final roomTypeLabel = channel.isPrivate
            ? (channel.joined ? '私密房间 · 已加入' : '私密房间 · 待加入')
            : (channel.joined ? '公开房间 · 已加入' : '公开房间');
        final subtitle = _hasMultipleNetworks
            ? '${channel.networkKey} · $roomTypeLabel'
            : roomTypeLabel;
        return _buildSelectableTile(
          selected: selected,
          accentColor: channel.isPrivate
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.secondary,
          tags: [_buildRoomTypeTag(channel.isPrivate)],
          onTap: () => widget.onOpenChannelConversation(conversationId),
          title: channel.name,
          subtitle: subtitle,
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'join') {
                unawaited(chatManager.joinChannel(channel));
              } else if (value == 'leave') {
                unawaited(chatManager.leaveChannel(channel));
              } else if (value == 'voice') {
                unawaited(chatManager.joinChannelVoice(channel));
              } else if (value == 'rename') {
                unawaited(_showRenameRoomDialog(channel));
              } else if (value == 'members') {
                unawaited(_showManageMembersDialog(channel));
              } else if (value == 'invite') {
                unawaited(_showInviteMembersDialog(channel));
              } else if (value == 'archive') {
                unawaited(chatManager.archiveChannel(channel));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: channel.joined ? 'leave' : 'join',
                child: Text(channel.joined ? '退出房间' : '加入房间'),
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
                  child: Text('房间改名'),
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
                  child: Text('隐藏房间'),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOnlinePeerList() {
    if (_onlinePeers.isEmpty) {
      return _buildEmptyHint('暂无在线设备', '等待其他设备加入当前组网');
    }
    return Column(
      children: _onlinePeers.map((peer) {
        final friendStatus = chatManager.friendStatusOf(peer.peerId);
        return _buildSelectableTile(
          selected: false,
          onTap: () => widget.onOpenDirectPeer(peer),
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
                onPressed: () => widget.onOpenDirectPeer(peer),
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
      await widget.onOpenDirectPeer(peer);
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withOpacity(0.08)
            : (accentColor?.withOpacity(0.08) ??
                colorScheme.surface.withOpacity(0.45)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withOpacity(0.20)
              : (accentColor?.withOpacity(0.20) ??
                  Theme.of(context).dividerColor.withOpacity(0.35)),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: onSecondaryTapDown,
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: onTap,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

  Future<void> _showCreateRoomDialog() async {
    final connectedNetworks = _connectedNetworkKeys;
    if (connectedNetworks.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可用的已连接网络')),
      );
      return;
    }
    String? selectedNetworkKey = chatManager.preferredNetworkKey(
          scopedNetworkKey: _scopedNetworkKey,
        ) ??
        connectedNetworks.first;
    bool isPrivate = false;
    final selectedIds = <String>{};
    final nameController = TextEditingController();
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
                screenWidth < 560 ? screenWidth - 64 : 460.0;
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Row(
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('创建房间')),
                ],
              ),
              content: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.meeting_room_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                candidates.isEmpty
                                    ? '当前没有其他在线成员，也可以先创建本地房间。其他设备上线后会同步公开房间。'
                                    : '房间会绑定到当前组网，公开房间会向在线成员同步。',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                                  child: Text(
                                    networkKey,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isPrivate,
                        title: const Text('私密房间'),
                        subtitle: const Text('仅邀请勾选的在线成员，未受邀成员不可见'),
                        onChanged: (value) => setState(() => isPrivate = value),
                      ),
                      if (isPrivate) ...[
                        const SizedBox(height: 8),
                        Text(
                          '邀请成员',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 240),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: candidates.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('当前网络暂无在线成员'),
                                )
                              : ListView(
                                  physics: const ClampingScrollPhysics(),
                                  shrinkWrap: true,
                                  children: candidates.map((peer) {
                                    return CheckboxListTile(
                                      value:
                                          selectedIds.contains(peer.peerId),
                                      title: Text(chatPeerPrimaryName(peer)),
                                      subtitle: Text(
                                        buildMemberPeerSubtitle(
                                          peer,
                                          hasMultipleNetworks:
                                              _hasMultipleNetworks,
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
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('创建房间'),
                ),
              ],
            );
          },
        );
      },
    );
    if (created != true) {
      nameController.dispose();
      return;
    }
    final trimmed = nameController.text.trim();
    nameController.dispose();
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
        invitedPeers: invited,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ChatManager.roomCreateFailureMessage(error))),
      );
      return;
    }
    final conversationId = chatManager.selectedConversationId;
    if (conversationId != null && mounted) {
      await widget.onOpenChannelConversation(conversationId);
    }
  }

  Future<void> _showRenameRoomDialog(ChatChannel channel) async {
    final controller = TextEditingController(text: channel.name);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('房间改名'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '输入新的房间名称',
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
                final messenger = ScaffoldMessenger.of(this.context);
                await Clipboard.setData(ClipboardData(text: report));
                if (!mounted) {
                  return;
                }
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('诊断信息已复制')),
                );
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
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('日志已复制')),
                );
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
}
