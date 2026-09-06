import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/formatters.dart';
import '../models/file_item.dart';
import '../services/db_service.dart';
import '../services/transfer_service.dart';
import 'scanner_screen.dart';
import 'transfer_screen.dart';
import '../widgets/file_tile.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DbService _dbService = DbService();
  StreamSubscription<String>? _completionSub;
  List<FileItem> _recentFiles = [];
  int _storageUsed = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final transferService = Provider.of<TransferService>(context, listen: false);
      _completionSub = transferService.completions.listen((_) {
        if (mounted) _loadData();
      });
    });
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final files = await _dbService.getRecentFiles(10);
    final storage = await _dbService.getStorageUsed();
    if (mounted) {
      setState(() {
        _recentFiles = files;
        _storageUsed = storage;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.textPrimary),
              )
            : RefreshIndicator(
                color: AppTheme.textPrimary,
                backgroundColor: AppTheme.surface,
                onRefresh: _loadData,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Header section edge-to-edge
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      decoration: const BoxDecoration(
                        color: Color(0xFF09090B),
                        border: Border(bottom: BorderSide(color: Color(0xFF27272A), width: 1)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF121214),
                              border: Border.all(color: const Color(0xFF27272A)),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Center(
                                child: Text('CF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CUEFLEX SYSTEM',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Deterministic Local Relay · Zero Cloud Storage',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Consumer<TransferService>(
                            builder: (context, transferService, child) {
                              final isConnected = transferService.currentStatus == ConnectionStatus.connected ||
                                  transferService.currentStatus == ConnectionStatus.connecting;

                              if (isConnected) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF09090B),
                                        border: Border.all(color: const Color(0xFF22C55E), width: 1),
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF22C55E),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  transferService.currentStatus == ConnectionStatus.connecting
                                                      ? 'STATUS: CONNECTING TO PC...'
                                                      : 'STATUS: CONNECTED TO PC',
                                                  style: const TextStyle(
                                                    color: Color(0xFF22C55E),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    fontFamily: 'monospace',
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                const Text(
                                                  'Active relay session · Ready for batch transfer',
                                                  style: TextStyle(
                                                    color: AppTheme.textSecondary,
                                                    fontSize: 11,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => transferService.disconnect(),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF121214),
                                                border: Border.all(color: const Color(0xFFEF4444)),
                                              ),
                                              child: const Text(
                                                'DISCONNECT',
                                                style: TextStyle(
                                                  color: Color(0xFFEF4444),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    _buildPrimaryButton(
                                      title: 'TRANSFER FILES TO PC',
                                      subtitle: 'Select documents, images or code files',
                                      icon: Icons.upload_file_rounded,
                                      onTap: () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        final result = await FilePicker.pickFiles(allowMultiple: true);
                                        if (result != null && result.files.isNotEmpty) {
                                          for (final f in result.files) {
                                            if (f.path != null) {
                                              try {
                                                await transferService.sendFile(File(f.path!));
                                              } catch (e) {
                                                messenger.showSnackBar(SnackBar(
                                                  content: Text('Failed to send ${f.name}: $e'),
                                                  backgroundColor: const Color(0xFFEF4444),
                                                  behavior: SnackBarBehavior.floating,
                                                ));
                                                break; // Stop sending subsequent files on error
                                              }
                                            }
                                          }
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    StreamBuilder<TransferProgress?>(
                                      stream: transferService.progress,
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
                                        final prog = snapshot.data!;
                                        if (prog.progress >= 1.0 || (prog.totalChunks > 0 && prog.completedChunks >= prog.totalChunks)) {
                                          return const SizedBox.shrink();
                                        }
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 16),
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF09090B),
                                            border: Border.all(color: const Color(0xFF27272A)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      prog.fileName,
                                                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 12),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text(
                                                    prog.percentage,
                                                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              LinearProgressIndicator(
                                                value: prog.progress,
                                                backgroundColor: const Color(0xFF18181B),
                                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                                minHeight: 4,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  _buildPrimaryButton(
                                    title: 'SCAN QR TO RECEIVE',
                                    subtitle: 'Open camera · Connect to PC Terminal',
                                    icon: Icons.qr_code_scanner_rounded,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const ScannerScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildSecondaryButton(
                                    title: 'SEND FILE TO PC',
                                    icon: Icons.upload_file_rounded,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const TransferScreen(
                                            sessionId: null,
                                            sendMode: true,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 36),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '> RECENT_FILES',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              Text(
                                '[ ${_recentFiles.length} FILES ]',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (_recentFiles.isEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF09090B),
                          border: Border.all(color: const Color(0xFF27272A)),
                        ),
                        padding: const EdgeInsets.all(28),
                        child: const Column(
                          children: [
                            Text(
                              'SYS_EMPTY_BUFFER',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Received or transferred files will appear here.',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._recentFiles.map((file) {
                        return FileTile(
                          file: file,
                          onTap: () => OpenFile.open(file.localPath),
                        );
                      }),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF09090B),
                          border: Border.all(color: const Color(0xFF27272A)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'STORAGE_ALLOCATION',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  Formatters.formatStorage(_storageUsed),
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF18181B),
                              ),
                                child: LinearProgressIndicator(
                                  value: (_storageUsed <= 0 || _storageUsed.isNaN)
                                      ? 0.02
                                      : (_storageUsed / (1024 * 1024 * 1024 * 10)).clamp(0.02, 1.0),
                                  backgroundColor: Colors.transparent,
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  minHeight: 6,
                                ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: InkWell(
                        onTap: () async {
                          final uri = Uri.parse('https://github.com/dev7shah');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121214),
                            border: Border.all(color: const Color(0xFF27272A)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.code, color: Colors.white, size: 14),
                              SizedBox(width: 8),
                              Text(
                                'MADE BY DEV7SHAH',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF000000), size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF3F3F46),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Color(0xFF000000), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF09090B),
        border: Border.all(color: const Color(0xFF27272A), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.textPrimary, size: 18),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
