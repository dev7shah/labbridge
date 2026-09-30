import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'crypto_service.dart';
import '../core/config.dart';

class ChannelMessage {
  final String text;
  final DateTime timestamp;
  final bool isHost;

  ChannelMessage({required this.text, required this.timestamp, required this.isHost});
}

class ChannelService extends ChangeNotifier {
  static final ChannelService _instance = ChannelService._internal();
  factory ChannelService() => _instance;
  ChannelService._internal();

  final _storage = const FlutterSecureStorage();
  final _cryptoService = CryptoService();

  String? _channelId;
  String? _clientKey;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  
  String? get currentChannelId => _channelId;
  bool get isConnected => _isConnected;

  final List<ChannelMessage> _messages = [];
  List<ChannelMessage> get messages => List.unmodifiable(_messages);

  String _hostStatus = 'offline';
  String get hostStatus => _hostStatus;

  Timer? _reconnectTimer;
  Timer? _pingTimer;

  Future<bool> hasSavedChannel() async {
    final id = await _storage.read(key: 'channel_id');
    final ck = await _storage.read(key: 'channel_client_key');
    return id != null && ck != null;
  }

  Future<void> saveChannel(String channelId, String clientKey) async {
    await _storage.write(key: 'channel_id', value: channelId);
    await _storage.write(key: 'channel_client_key', value: clientKey);
  }

  Future<void> clearChannel() async {
    await _storage.delete(key: 'channel_id');
    await _storage.delete(key: 'channel_client_key');
    disconnect();
  }

  Future<void> loadAndConnect() async {
    final id = await _storage.read(key: 'channel_id');
    final ck = await _storage.read(key: 'channel_client_key');
    if (id != null && ck != null) {
      await connect(id, ck);
    }
  }

  Future<void> connect(String channelId, String clientKey) async {
    if (_isConnecting || _isConnected) return;
    _isConnecting = true;
    _channelId = channelId;
    _clientKey = clientKey;
    
    notifyListeners();

    try {
      final workerUrl = await AppConfig.getWorkerUrl();
      final wsUrl = '$workerUrl/c/$channelId/ws?role=client&key=$clientKey';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      await _channel!.ready.timeout(const Duration(seconds: 10));

      _isConnected = true;
      _isConnecting = false;
      notifyListeners();

      _startPingTimer();

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleMessage(dynamic message) {
    if (message is String) {
      if (message == 'pong') return;
      
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic> && decoded['type'] == 'status') {
          _hostStatus = decoded['host'] ?? 'offline';
          notifyListeners();
          return;
        }
      } catch (_) {}

      // Handle raw text message from host
      _messages.add(ChannelMessage(
        text: message,
        timestamp: DateTime.now(),
        isHost: true,
      ));
      notifyListeners();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _hostStatus = 'offline';
    _channel = null;
    _pingTimer?.cancel();
    notifyListeners();

    if (_channelId != null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        if (_channelId != null && _clientKey != null) {
          connect(_channelId!, _clientKey!);
        }
      });
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_isConnected && _channel != null) {
        _channel!.sink.add('ping');
      }
    });
  }

  void disconnect() {
    _channelId = null;
    _clientKey = null;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _hostStatus = 'offline';
    _messages.clear();
    notifyListeners();
  }

  void sendMessage(String text) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(text);
    _messages.add(ChannelMessage(
      text: text,
      timestamp: DateTime.now(),
      isHost: false,
    ));
    notifyListeners();
  }
}
