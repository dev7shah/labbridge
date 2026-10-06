import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/transfer_service.dart';
import '../main.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _hasNavigated = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _scannerController.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_hasNavigated) {
        _scannerController.start();
      }
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_hasNavigated || _isProcessing) return;
    _isProcessing = true;

    try {
      for (final barcode in capture.barcodes) {
        final value = barcode.rawValue;
        if (value == null) continue;

        String? sessionId;
        int? expiry;

        try {
          final data = json.decode(value) as Map<String, dynamic>;
          sessionId = data['s'] as String?;
          expiry = data['e'] as int?;
        } catch (_) {
          final uri = Uri.tryParse(value);
          if (uri != null && uri.queryParameters.containsKey('s')) {
            sessionId = uri.queryParameters['s'];
            final expiryStr = uri.queryParameters['e'];
            if (expiryStr != null) {
              expiry = int.tryParse(expiryStr);
            }
          }
        }

        if (sessionId == null) continue;

        if (expiry != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now > expiry) {
            _showError('QR has expired, refresh the PC terminal');
            return;
          }
        }

        _hasNavigated = true;
        await _connectAndReturn(sessionId);
        return;
      }
    } finally {
      if (mounted && !_hasNavigated) {
        await Future.delayed(const Duration(seconds: 2));
      }
      _isProcessing = false;
    }
  }

  Future<void> _connectAndReturn(String sessionId) async {
    final transferService = Provider.of<TransferService>(context, listen: false);
    await transferService.connect(sessionId);
    
    if (!mounted) return;
    
    if (transferService.currentStatus == ConnectionStatus.connected) {
      Navigator.of(context).pop();
    } else {
      _hasNavigated = false;
      _showError('Failed to connect to session');
    }
  }

  int _lastErrorTime = 0;

  void _showError(String message) {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastErrorTime < 2000) return;
    _lastErrorTime = now;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showManualEntry() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF09090B),
        shape: Border.all(color: const Color(0xFF27272A), width: 1),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MANUAL SESSION ID',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter session ID displayed on PC Terminal',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'e.g. abc123def456',
                  hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13, fontFamily: 'monospace'),
                  filled: true,
                  fillColor: Color(0xFF121214),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF27272A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'monospace')),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    onPressed: () async {
                      final id = controller.text.trim();
                      if (id.length == 12 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id)) {
                        Navigator.pop(context);
                        await _connectAndReturn(id);
                      }
                    },
                    child: const Text('CONNECT', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),

          Positioned.fill(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.75),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(color: Colors.black),
                  ),
                  Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        width: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  Animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                    effects: [
                      SlideEffect(
                        begin: const Offset(0, 0),
                        end: const Offset(0, 256 / 2),
                        duration: 1600.ms,
                        curve: Curves.easeInOut,
                      ),
                    ],
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF09090B),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                bottom: 14,
                left: 16,
                right: 16,
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF121214),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary, size: 18),
                      tooltip: 'Back',
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      '[ QR TERMINAL SCANNER ]',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF121214),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: IconButton(
                      onPressed: () => _scannerController.toggleTorch(),
                      icon: const Icon(Icons.flash_on, color: Colors.white, size: 18),
                      tooltip: 'Toggle Flash',
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF09090B),
              padding: EdgeInsets.only(
                top: 20,
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Point camera at the QR code on PC Terminal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF121214),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _showManualEntry,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.keyboard, color: Colors.white, size: 16),
                              SizedBox(width: 10),
                              Text(
                                'ENTER SESSION ID MANUALLY',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 200.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
