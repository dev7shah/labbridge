import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/channel_service.dart';
import '../core/constants.dart';

class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final TextEditingController _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChannelService>(
      builder: (context, channelService, child) {
        if (!channelService.isConnected) {
          return const Center(
            child: Text(
              'No active channel',
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'monospace'),
            ),
          );
        }

        final isHostOnline = channelService.hostStatus == 'online';

        return Column(
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isHostOnline ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                      boxShadow: [
                        BoxShadow(
                          color: isHostOnline ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isHostOnline ? 'HOST ONLINE' : 'HOST OFFLINE',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.link_off, color: Color(0xFFEF4444), size: 18),
                    onPressed: () => channelService.clearChannel(),
                    tooltip: 'Revoke Channel',
                  ),
                ],
              ),
            ),

            // Messages List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: channelService.messages.length,
                itemBuilder: (context, index) {
                  final msg = channelService.messages[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: msg.isHost ? const Color(0xFF121214) : const Color(0xFF1A1A1D),
                      border: Border.all(color: const Color(0xFF27272A)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.isHost ? 'HOST' : 'YOU',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: msg.isHost ? const Color(0xFF60A5FA) : const Color(0xFFA1A1AA),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          msg.text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Input Area
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF27272A))),
                color: Color(0xFF09090B),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      enabled: isHostOnline,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: isHostOnline ? 'Send a prompt...' : 'Host offline...',
                        hintStyle: const TextStyle(color: AppTheme.textMuted),
                        filled: true,
                        fillColor: const Color(0xFF121214),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                        disabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF27272A))),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty && isHostOnline) {
                          channelService.sendMessage(val.trim());
                          _promptController.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: isHostOnline
                        ? () {
                            if (_promptController.text.trim().isNotEmpty) {
                              channelService.sendMessage(_promptController.text.trim());
                              _promptController.clear();
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: const Color(0xFF27272A),
                      disabledForegroundColor: const Color(0xFF52525B),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    child: const Text('SEND', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
