import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/chat_bubble.dart';

const _suggestions = [
  "What's the temperature?",
  'Is it raining right now?',
  'How is the air quality?',
  "What's the CO₂ level?",
  'Are all nodes online?',
  "Summarize my home's condition",
];

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().fetchHistory();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    final appState = context.read<AppStateProvider>();
    await context.read<ChatProvider>().sendMessage(
      text,
      _buildHomeState(appState),
      onCommand: (roomId, command) =>
          appState.sendCommand(roomId, command, reason: 'ai_command'),
    );
    _scrollToBottom();
  }

  /// Builds the state dict passed to the AI server.
  Map<String, dynamic> _buildHomeState(AppStateProvider appState) {
    return {
      'rooms': appState.rooms.map((room) {
        final sensorMap = <String, dynamic>{};
        for (final s in room.sensors) {
          switch (s.type.name) {
            case 'temperature':
              sensorMap['temperature'] = s.value;
            case 'humidity':
              sensorMap['humidity'] = s.value;
            case 'light':
              sensorMap['light_lux'] = s.value;
            case 'co2':
              sensorMap['co2_ppm'] = s.value;
            case 'rain':
              sensorMap['rain_detected'] = s.value;
            case 'airQuality':
              sensorMap['aqi'] = s.value;
          }
        }
        return {
          'room_id': room.id,
          'name': room.name,
          'is_online': room.isOnline,
          ...sensorMap,
        };
      }).toList(),
    };
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Clear all chat history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.errorColor),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ChatProvider>().clearHistory();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 16, color: AppTheme.secondaryColor),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GossipHome AI',
                    style: TextStyle(fontSize: 15)),
                Text(
                  'Ask about your home',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Consumer<ChatProvider>(
            builder: (_, provider, __) => provider.messages.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Clear chat',
                    onPressed: _clearHistory,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (_, provider, __) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.messages.isEmpty) {
                  return _buildWelcome(theme);
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: provider.messages.length,
                  itemBuilder: (_, i) =>
                      ChatBubble(message: provider.messages[i]),
                );
              },
            ),
          ),
          // Typing indicator
          Consumer<ChatProvider>(
            builder: (_, provider, __) {
              if (!provider.isSending) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome,
                          size: 13, color: AppTheme.secondaryColor),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        children: List.generate(
                          3,
                          (i) => Container(
                            margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor
                                  .withOpacity(0.4 + i * 0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Ask about your home…',
                      counterText: '',
                    ),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<ChatProvider>(
                  builder: (_, provider, __) => ValueListenableBuilder(
                    valueListenable: _inputCtrl,
                    builder: (_, value, __) {
                      final canSend =
                          value.text.trim().isNotEmpty && !provider.isSending;
                      return IconButton.filled(
                        onPressed: canSend
                            ? () => _send(_inputCtrl.text)
                            : null,
                        icon: const Icon(Icons.arrow_upward),
                        style: IconButton.styleFrom(
                          backgroundColor: canSend
                              ? AppTheme.primaryColor
                              : theme.colorScheme.onSurface.withOpacity(0.1),
                          foregroundColor:
                              canSend ? Colors.white : Colors.grey,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppTheme.secondaryColor.withOpacity(0.3),
                  width: 2),
            ),
            child: const Icon(Icons.auto_awesome,
                size: 28, color: AppTheme.secondaryColor),
          ),
          const SizedBox(height: 16),
          Text(
            'Ask me anything',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'I have access to your sensor readings,\nnode status, and automation flows.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'TRY ASKING',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map((s) => GestureDetector(
                      onTap: () => _send(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Text(
                          s,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
