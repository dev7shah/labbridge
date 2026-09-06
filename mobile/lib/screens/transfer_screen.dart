import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/folder.dart';
import '../services/db_service.dart';
import '../services/transfer_service.dart';
import '../widgets/transfer_progress.dart';
import '../main.dart';
import 'scanner_screen.dart';

class TransferScreen extends StatefulWidget {
  final String? sessionId;
  final bool sendMode;

  const TransferScreen({
    super.key,
    required this.sessionId,
    this.sendMode = false,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final DbService _dbService = DbService();
  late final TransferService _transferService;

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  TransferProgress? _currentProgress;
  List<Folder> _currentFolderChildren = [];
  List<Folder> _folderBreadcrumbs = [];
  final List<String> _completedFiles = [];
  String? _error;
  double _speed = 0;

  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<TransferProgress?>? _progressSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<String>? _completionSub;

  @override
  void initState() {
    super.initState();
    _transferService = context.read<TransferService>();
    _init();
  }

  Future<void> _init() async {
    _statusSub = _transferService.connectionStatus.listen((status) {
      if (mounted) {
        setState(() => _connectionStatus = status);
      }
    });

    _progressSub = _transferService.progress.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
          _speed = _transferService.getTransferSpeed();
        });
      }
    });

    _errorSub = _transferService.errors.listen((error) {
      if (mounted) {
        setState(() => _error = error);
      }
    });

    _completionSub = _transferService.completions.listen((fileName) {
      if (mounted) {
        setState(() {
          _completedFiles.add(fileName);
          _currentProgress = null;
        });
      }
    });

    if (widget.sessionId != null) {
      await _connect();
    }
    await _loadFolderChildren(null);
  }

  Future<void> _loadFolderChildren(String? parentId) async {
    final children = await _dbService.getChildFolders(parentId);
    if (mounted) {
      setState(() {
        _currentFolderChildren = children;
        _transferService.setTargetFolder(parentId);
      });
    }
  }

  Future<void> _connect() async {
    if (widget.sessionId == null) return;

    setState(() {
      _error = null;
      _connectionStatus = ConnectionStatus.connecting;
    });

    await _transferService.connect(widget.sessionId!);
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    final file = File(filePath);
    await _transferService.sendFile(file);
  }

  Future<void> _launchGithub() async {
    final uri = Uri.parse('https://github.com/dev7shah');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _progressSub?.cancel();
    _errorSub?.cancel();
    _completionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionStatus == ConnectionStatus.connected;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text(
          '> TRANSFER_RELAY',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'monospace'),
        ),
        actions: [
          if (isConnected)
            IconButton(
              onPressed: () async {
                await _transferService.disconnect();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.close, color: Color(0xFFEF4444)),
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildConnectionStatus().animate().fadeIn().slideY(begin: -0.05),
            const SizedBox(height: 20),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  border: Border.all(color: const Color(0xFFEF4444), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().scale(),
              const SizedBox(height: 16),
            ],

            if (isConnected) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  border: Border.all(color: const Color(0xFF27272A), width: 1),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.folder_open, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'SAVE LOCATION',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildFolderSelector(),
                  ],
                ),
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05),
              const SizedBox(height: 20),
            ],

            if (_currentProgress != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  border: Border.all(color: const Color(0xFF27272A), width: 1),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.sync, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'ACTIVE TRANSFER',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TransferProgressWidget(
                      transferProgress: _currentProgress!,
                      speed: _speed,
                    ),
                  ],
                ),
              ).animate().fadeIn().scale(),
              const SizedBox(height: 20),
            ],

            if (widget.sendMode && isConnected && _currentProgress == null) ...[
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickAndSendFile,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file, color: Colors.black, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'PICK FILE TO SEND',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 150.ms).scale(),
              const SizedBox(height: 24),
            ],

            if (isConnected && _currentProgress == null && _completedFiles.isEmpty && !widget.sendMode) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  border: Border.all(color: const Color(0xFF27272A), width: 1),
                ),
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF121214),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: const Icon(Icons.cloud_sync_outlined, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'READY FOR TRANSFER',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Drop files on your PC terminal to transfer, or pick a local file to send.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _pickAndSendFile,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.upload_file, color: Colors.black, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'SEND A FILE',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms).scale(),
            ],

            if (_completedFiles.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.check, color: Color(0xFF22C55E), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'COMPLETED TRANSFERS',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ).animate().fadeIn(),
              const SizedBox(height: 12),
              ..._completedFiles.asMap().entries.map((entry) {
                final idx = entry.key;
                final name = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF09090B),
                      border: Border.all(color: const Color(0xFF27272A), width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 18),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Received successfully',
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
                  ).animate(delay: (40 * idx).ms).fadeIn().slideX(begin: 0.05),
                );
              }),
              const SizedBox(height: 12),
            ],

            if (widget.sessionId == null && !widget.sendMode && !isConnected) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  border: Border.all(color: const Color(0xFF27272A), width: 1),
                ),
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF121214),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'NO ACTIVE SESSION',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Scan the QR code displayed on your desktop or PC terminal to link devices.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 26),
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ScannerScreen()),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_scanner, color: Colors.black, size: 18),
                                SizedBox(width: 10),
                                Text(
                                  'SCAN QR TERMINAL',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms).scale(),
            ],

            const SizedBox(height: 24),

            if (isConnected)
              OutlinedButton.icon(
                onPressed: () async {
                  await _transferService.disconnect();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('DISCONNECT FROM PC', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 32),

            // Made By DEV7SHAH Badge
            Center(
              child: InkWell(
                onTap: _launchGithub,
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    IconData icon;
    String label;
    Color color;

    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        icon = Icons.check_circle_outline;
        label = '[ CONNECTED TO TERMINAL ]';
        color = const Color(0xFF22C55E);
        break;
      case ConnectionStatus.connecting:
        icon = Icons.sync;
        label = '[ CONNECTING... ]';
        color = const Color(0xFFF59E0B);
        break;
      case ConnectionStatus.error:
        icon = Icons.error_outline;
        label = '[ CONNECTION ERROR ]';
        color = const Color(0xFFEF4444);
        break;
      case ConnectionStatus.disconnected:
        icon = Icons.link_off;
        label = '[ DISCONNECTED ]';
        color = AppTheme.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF09090B),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (_connectionStatus == ConnectionStatus.connecting)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFolderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF121214),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() => _folderBreadcrumbs = []);
                    _loadFolderChildren(null);
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder,
                        size: 14,
                        color: _folderBreadcrumbs.isEmpty ? Colors.white : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ROOT',
                        style: TextStyle(
                          color: _folderBreadcrumbs.isEmpty
                              ? Colors.white
                              : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                ..._folderBreadcrumbs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final crumb = entry.value;
                  final isLast = i == _folderBreadcrumbs.length - 1;
                  return Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('/', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontFamily: 'monospace')),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _folderBreadcrumbs = _folderBreadcrumbs.sublist(0, i + 1);
                          });
                          _loadFolderChildren(crumb.id);
                        },
                        child: Text(
                          crumb.name.toUpperCase(),
                          style: TextStyle(
                            color: isLast
                                ? Colors.white
                                : AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF121214),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: Row(
            children: [
              const Icon(Icons.save, color: Colors.white, size: 14),
              const SizedBox(width: 10),
              Text(
                _folderBreadcrumbs.isEmpty
                    ? 'SAVING TO: /ROOT'
                    : 'SAVING TO: /${_folderBreadcrumbs.last.name.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_currentFolderChildren.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              'No sub-directories. Incoming files will save right here.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'monospace'),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _currentFolderChildren.map((folder) {
              return GestureDetector(
                onTap: () {
                  setState(() => _folderBreadcrumbs.add(folder));
                  _loadFolderChildren(folder.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121214),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_outlined, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        folder.name.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 16),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
