import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_io/audio_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:record/record.dart';

import 'chat_logger.dart';
import 'chat_pcm_codec.dart';

class ChatAudioCapabilities {
  const ChatAudioCapabilities({
    required this.voiceNotes,
    required this.directCalls,
    required this.channelPtt,
    required this.headsetRecommended,
    this.unsupportedReason,
  });

  final bool voiceNotes;
  final bool directCalls;
  final bool channelPtt;
  final bool headsetRecommended;
  final String? unsupportedReason;

  bool get fullySupported => voiceNotes && directCalls && channelPtt;
}

class ChatAudioException implements Exception {
  const ChatAudioException({
    required this.code,
    required this.message,
    required this.userMessage,
    this.isPermissionDenied = false,
  });

  final String code;
  final String message;
  final String userMessage;
  final bool isPermissionDenied;

  @override
  String toString() => 'ChatAudioException($code): $message';
}

abstract class ChatAudioBackend {
  String get name;
  ChatAudioCapabilities get capabilities;
  String get preferredVoiceFileExtension;
  String get preferredVoiceCodecLabel;
  bool get isVoiceRecording;
  bool get isVoicePlaying;
  bool get isStreamingMic;
  bool get isIncomingStreamPlaying;
  String? get lastError;
  int? get liveInputSampleRate;
  int? get liveOutputSampleRate;

  Future<void> init();
  Future<void> startVoiceNoteRecording(String targetPath);
  Future<String?> stopVoiceNoteRecording();
  Future<void> cancelVoiceNoteRecording();
  Future<void> playVoiceFile(String filePath);
  Future<void> stopVoicePlayback();
  Future<void> startMicrophoneStream(void Function(Uint8List bytes) onAudioBytes);
  Future<void> stopMicrophoneStream();
  Future<void> startIncomingStreamPlayback();
  Future<void> stopIncomingStreamPlayback();
  Future<void> playIncomingPcm(Uint8List bytes);
  Future<void> dispose();
}

class ChatAudioService {
  ChatAudioService._({ChatAudioBackend? backend})
      : _backend = backend ?? _createDefaultBackend();

  static ChatAudioService? _instance;

  static ChatAudioService get instance => _instance ??= ChatAudioService._();

  @visibleForTesting
  static void resetForTest({ChatAudioBackend? backend}) {
    _instance = ChatAudioService._(backend: backend);
  }

  final ChatAudioBackend _backend;

  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bufferSize = 2048;

  String get backendName => _backend.name;
  ChatAudioCapabilities get capabilities => _backend.capabilities;
  bool get supportsVoiceNotes => _backend.capabilities.voiceNotes;
  bool get supportsDirectCalls => _backend.capabilities.directCalls;
  bool get supportsChannelPtt => _backend.capabilities.channelPtt;
  bool get isAudioFeatureSupported => _backend.capabilities.fullySupported;
  bool get headsetRecommended => _backend.capabilities.headsetRecommended;
  String get unsupportedReason =>
      _backend.capabilities.unsupportedReason ?? '当前平台暂不支持聊天室音频';
  String get preferredVoiceFileExtension => _backend.preferredVoiceFileExtension;
  String get preferredVoiceCodecLabel => _backend.preferredVoiceCodecLabel;
  String? get lastAudioError => _backend.lastError;
  int? get liveInputSampleRate => _backend.liveInputSampleRate;
  int? get liveOutputSampleRate => _backend.liveOutputSampleRate;

  bool get isVoiceRecording => _backend.isVoiceRecording;
  bool get isStreamingMic => _backend.isStreamingMic;
  bool get isIncomingStreamPlaying => _backend.isIncomingStreamPlaying;
  bool get isVoicePlaying => _backend.isVoicePlaying;

  Future<void> init() => _backend.init();

  Future<void> startVoiceNoteRecording(String targetPath) =>
      _backend.startVoiceNoteRecording(targetPath);

  Future<String?> stopVoiceNoteRecording() => _backend.stopVoiceNoteRecording();

  Future<void> cancelVoiceNoteRecording() => _backend.cancelVoiceNoteRecording();

  Future<void> playVoiceFile(String filePath) => _backend.playVoiceFile(filePath);

  Future<void> stopVoicePlayback() => _backend.stopVoicePlayback();

  Future<void> startMicrophoneStream(
    void Function(Uint8List bytes) onAudioBytes,
  ) =>
      _backend.startMicrophoneStream(onAudioBytes);

  Future<void> stopMicrophoneStream() => _backend.stopMicrophoneStream();

  Future<void> startIncomingStreamPlayback() =>
      _backend.startIncomingStreamPlayback();

  Future<void> stopIncomingStreamPlayback() =>
      _backend.stopIncomingStreamPlayback();

  Future<void> playIncomingPcm(Uint8List bytes) =>
      _backend.playIncomingPcm(bytes);

  Future<void> dispose() => _backend.dispose();

  String userMessageForError(
    Object error, {
    required String action,
  }) {
    if (error is ChatAudioException) {
      return error.userMessage;
    }
    return '$action失败: $error';
  }

  static ChatAudioBackend _createDefaultBackend() {
    if (kIsWeb) {
      return _FlutterSoundChatAudioBackend(ChatLogger.instance);
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return _FlutterSoundChatAudioBackend(ChatLogger.instance);
      case TargetPlatform.windows:
        return _WindowsChatAudioBackend(ChatLogger.instance);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return _UnsupportedChatAudioBackend(
          reason: '当前${defaultTargetPlatform.name}版本暂未接入聊天室音频',
        );
    }
  }
}

class _FlutterSoundChatAudioBackend implements ChatAudioBackend {
  _FlutterSoundChatAudioBackend(this._logger);

  final ChatLogger _logger;
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _voicePlayer = FlutterSoundPlayer();
  final FlutterSoundPlayer _streamPlayer = FlutterSoundPlayer();

  bool _initialized = false;
  bool _streamPlayerStarted = false;
  bool _isVoiceRecording = false;
  bool _isStreamingMic = false;
  String? _activeVoicePath;
  String? _lastError;
  StreamController<List<Int16List>>? _streamController;
  StreamSubscription<List<Int16List>>? _streamSubscription;
  Future<void> _playbackQueue = Future<void>.value();

  @override
  String get name => 'flutter_sound';

  @override
  ChatAudioCapabilities get capabilities => const ChatAudioCapabilities(
        voiceNotes: true,
        directCalls: true,
        channelPtt: true,
        headsetRecommended: false,
      );

  @override
  String get preferredVoiceFileExtension => '.wav';

  @override
  String get preferredVoiceCodecLabel => 'wav/pcm16/mono/16khz';

  @override
  bool get isVoiceRecording => _isVoiceRecording;

  @override
  bool get isVoicePlaying => !_voicePlayer.isStopped;

  @override
  bool get isStreamingMic => _isStreamingMic;

  @override
  bool get isIncomingStreamPlaying => _streamPlayerStarted;

  @override
  String? get lastError => _lastError;

  @override
  int? get liveInputSampleRate => ChatAudioService.sampleRate;

  @override
  int? get liveOutputSampleRate => ChatAudioService.sampleRate;

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    await _recorder.openRecorder();
    await _voicePlayer.openPlayer();
    await _streamPlayer.openPlayer();
    await _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));
    _initialized = true;
    await _logger.info('audio', '音频服务初始化完成', extra: {
      'backend': name,
      'voiceCodec': preferredVoiceCodecLabel,
      'sampleRate': ChatAudioService.sampleRate,
      'numChannels': ChatAudioService.numChannels,
      'bufferSize': ChatAudioService.bufferSize,
    });
  }

  @override
  Future<void> startVoiceNoteRecording(String targetPath) async {
    await init();
    if (_isStreamingMic) {
      throw StateError('正在实时语音中，不能录制语音消息');
    }
    _activeVoicePath = targetPath;
    _isVoiceRecording = true;
    try {
      await _recorder.startRecorder(
        codec: Codec.pcm16WAV,
        toFile: targetPath,
        sampleRate: ChatAudioService.sampleRate,
        numChannels: ChatAudioService.numChannels,
      );
      _lastError = null;
      await _logger.info('audio', '开始录制语音消息', extra: {
        'backend': name,
        'targetPath': targetPath,
        'codec': preferredVoiceCodecLabel,
      });
    } catch (error) {
      _isVoiceRecording = false;
      _lastError = error.toString();
      rethrow;
    }
  }

  @override
  Future<String?> stopVoiceNoteRecording() async {
    if (!_isVoiceRecording) {
      return null;
    }
    final result = await _recorder.stopRecorder();
    _isVoiceRecording = false;
    _lastError = null;
    await _logger.info('audio', '停止录制语音消息', extra: {
      'backend': name,
      'resultPath': result ?? _activeVoicePath,
    });
    return result ?? _activeVoicePath;
  }

  @override
  Future<void> cancelVoiceNoteRecording() async {
    final path = await stopVoiceNoteRecording();
    _activeVoicePath = null;
    if (path != null && path.isNotEmpty) {
      await _recorder.deleteRecord(fileName: path);
      await _logger.info('audio', '取消语音消息录制并删除临时文件', extra: {
        'backend': name,
        'path': path,
      });
    }
  }

  @override
  Future<void> playVoiceFile(String filePath) async {
    await init();
    if (!_voicePlayer.isStopped) {
      await _voicePlayer.stopPlayer();
    }
    await _voicePlayer.startPlayer(
      fromURI: filePath,
      codec: _guessCodecFromPath(filePath),
    );
    _lastError = null;
    await _logger.info('audio', '播放语音消息', extra: {
      'backend': name,
      'filePath': filePath,
    });
  }

  @override
  Future<void> stopVoicePlayback() async {
    if (!_voicePlayer.isStopped) {
      await _voicePlayer.stopPlayer();
      await _logger.info('audio', '停止语音消息播放', extra: {
        'backend': name,
      });
    }
  }

  @override
  Future<void> startMicrophoneStream(
    void Function(Uint8List bytes) onAudioBytes,
  ) async {
    await init();
    if (_isVoiceRecording) {
      throw StateError('正在录制语音消息，不能开启实时语音');
    }
    if (_isStreamingMic) {
      return;
    }
    _streamController?.close();
    _streamController = StreamController<List<Int16List>>();
    _streamSubscription = _streamController!.stream.listen((buffers) {
      if (buffers.isEmpty) {
        return;
      }
      final samples = buffers.first;
      final bytes = Uint8List.view(
        samples.buffer,
        samples.offsetInBytes,
        samples.lengthInBytes,
      );
      onAudioBytes(Uint8List.fromList(bytes));
    });
    _isStreamingMic = true;
    try {
      await _recorder.startRecorder(
        codec: Codec.pcm16,
        sampleRate: ChatAudioService.sampleRate,
        numChannels: ChatAudioService.numChannels,
        bufferSize: ChatAudioService.bufferSize,
        toStreamInt16: _streamController!.sink,
      );
      _lastError = null;
      await _logger.info('audio', '开始实时语音麦克风采集', extra: {
        'backend': name,
        'codec': 'pcm16/mono/16khz',
      });
    } catch (error) {
      _isStreamingMic = false;
      _lastError = error.toString();
      rethrow;
    }
  }

  @override
  Future<void> stopMicrophoneStream() async {
    if (!_isStreamingMic) {
      return;
    }
    await _recorder.stopRecorder();
    await _streamSubscription?.cancel();
    await _streamController?.close();
    _streamSubscription = null;
    _streamController = null;
    _isStreamingMic = false;
    await _logger.info('audio', '停止实时语音麦克风采集', extra: {
      'backend': name,
    });
  }

  @override
  Future<void> startIncomingStreamPlayback() async {
    await init();
    if (_streamPlayerStarted) {
      return;
    }
    await _streamPlayer.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: false,
      sampleRate: ChatAudioService.sampleRate,
      numChannels: ChatAudioService.numChannels,
      bufferSize: ChatAudioService.bufferSize,
    );
    _streamPlayerStarted = true;
    _lastError = null;
    await _logger.info('audio', '启动实时语音播放器', extra: {
      'backend': name,
      'codec': 'pcm16/mono/16khz',
    });
  }

  @override
  Future<void> stopIncomingStreamPlayback() async {
    if (!_streamPlayerStarted) {
      return;
    }
    await _streamPlayer.stopPlayer();
    _streamPlayerStarted = false;
    _playbackQueue = Future<void>.value();
    await _logger.info('audio', '停止实时语音播放器', extra: {
      'backend': name,
    });
  }

  @override
  Future<void> playIncomingPcm(Uint8List bytes) async {
    await startIncomingStreamPlayback();
    final data = Int16List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 2,
    );
    _playbackQueue = _playbackQueue.then((_) async {
      if (!_streamPlayerStarted) {
        return;
      }
      await _streamPlayer.feedInt16FromStream([Int16List.fromList(data)]);
    }).catchError((_) {});
    await _playbackQueue;
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) {
      return;
    }
    await stopVoicePlayback();
    await stopIncomingStreamPlayback();
    await stopMicrophoneStream();
    if (_isVoiceRecording) {
      await stopVoiceNoteRecording();
    }
    await _voicePlayer.closePlayer();
    await _streamPlayer.closePlayer();
    await _recorder.closeRecorder();
    _initialized = false;
    await _logger.info('audio', '音频服务已释放', extra: {
      'backend': name,
    });
  }

  Codec _guessCodecFromPath(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) {
      return Codec.opusOGG;
    }
    if (lower.endsWith('.wav')) {
      return Codec.pcm16WAV;
    }
    return Codec.defaultCodec;
  }
}

class _WindowsChatAudioBackend implements ChatAudioBackend {
  _WindowsChatAudioBackend(this._logger);

  final ChatLogger _logger;
  final AudioIo _audioIo = AudioIo.instance;
  final AudioRecorder _recorder = AudioRecorder();
  final Downsample48kTo16kPcm16 _downsampler = Downsample48kTo16kPcm16();
  final Upsample16kPcm16To48kFloat64 _upsampler =
      Upsample16kPcm16To48kFloat64();
  final Upsample16kPcm16To48kFloat64 _voiceUpsampler =
      Upsample16kPcm16To48kFloat64();
  Future<void>? _voicePlaybackTask;
  StreamSubscription<List<double>>? _micSubscription;

  bool _initialized = false;
  bool _liveEngineStarted = false;
  bool _isVoiceRecording = false;
  bool _isVoicePlaying = false;
  bool _isStreamingMic = false;
  bool _isIncomingStreamPlaying = false;
  String? _activeVoicePath;
  String? _lastError;
  int? _liveInputSampleRate;
  int? _liveOutputSampleRate;
  int _sentPackets = 0;
  int _receivedPackets = 0;

  @override
  String get name => 'windows_audio_io_record';

  @override
  ChatAudioCapabilities get capabilities => const ChatAudioCapabilities(
        voiceNotes: true,
        directCalls: true,
        channelPtt: true,
        headsetRecommended: true,
      );

  @override
  String get preferredVoiceFileExtension => '.wav';

  @override
  String get preferredVoiceCodecLabel => 'wav/pcm16/mono/16khz';

  @override
  bool get isVoiceRecording => _isVoiceRecording;

  @override
  bool get isVoicePlaying => _isVoicePlaying;

  @override
  bool get isStreamingMic => _isStreamingMic;

  @override
  bool get isIncomingStreamPlaying => _isIncomingStreamPlaying;

  @override
  String? get lastError => _lastError;

  @override
  int? get liveInputSampleRate => _liveInputSampleRate;

  @override
  int? get liveOutputSampleRate => _liveOutputSampleRate;

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _logger.info('audio', '音频服务初始化完成', extra: {
      'backend': name,
      'voiceCodec': preferredVoiceCodecLabel,
      'liveCodec': 'pcm16/mono/16khz via audio_io(48khz float64 mono)',
      'headsetRecommended': capabilities.headsetRecommended,
    });
  }

  @override
  Future<void> startVoiceNoteRecording(String targetPath) async {
    await init();
    if (_isStreamingMic || _isIncomingStreamPlaying) {
      throw const ChatAudioException(
        code: 'LIVE_AUDIO_BUSY',
        message: '实时语音进行中，不能录制语音消息',
        userMessage: '当前正在语音中，请先退出实时语音再录制语音消息',
      );
    }
    try {
      _activeVoicePath = targetPath;
      _isVoiceRecording = true;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: ChatAudioService.sampleRate,
          numChannels: ChatAudioService.numChannels,
        ),
        path: targetPath,
      );
      _lastError = null;
      await _logger.info('audio', '开始录制语音消息', extra: {
        'backend': name,
        'targetPath': targetPath,
        'codec': preferredVoiceCodecLabel,
      });
    } catch (error) {
      _isVoiceRecording = false;
      throw await _mapAndLogError(
        action: '开始录制语音消息',
        error: error,
        extra: {
          'targetPath': targetPath,
        },
      );
    }
  }

  @override
  Future<String?> stopVoiceNoteRecording() async {
    if (!_isVoiceRecording) {
      return null;
    }
    final result = await _recorder.stop();
    _isVoiceRecording = false;
    _lastError = null;
    await _logger.info('audio', '停止录制语音消息', extra: {
      'backend': name,
      'resultPath': result ?? _activeVoicePath,
    });
    return result ?? _activeVoicePath;
  }

  @override
  Future<void> cancelVoiceNoteRecording() async {
    if (!_isVoiceRecording) {
      return;
    }
    await _recorder.cancel();
    _activeVoicePath = null;
    _isVoiceRecording = false;
    _lastError = null;
    await _logger.info('audio', '取消语音消息录制', extra: {
      'backend': name,
    });
  }

  @override
  Future<void> playVoiceFile(String filePath) async {
    await init();
    try {
      if (_isVoicePlaying) {
        await stopVoicePlayback();
      }
      final wav = _decodePcm16Wav(await File(filePath).readAsBytes());
      await _ensureLiveEngineStarted();
      _isVoicePlaying = true;
      _voicePlaybackTask = _playVoiceWav(wav)
          .catchError((Object error) async {
            _lastError = error.toString();
            await _logger.error('audio', '播放语音消息失败', extra: {
              'backend': name,
              'filePath': filePath,
              'error': error.toString(),
            });
          })
          .whenComplete(() async {
            _isVoicePlaying = false;
            await _stopLiveEngineIfIdle();
          });
      _lastError = null;
      await _logger.info('audio', '播放语音消息', extra: {
        'backend': name,
        'filePath': filePath,
      });
    } catch (error) {
      throw await _mapAndLogError(
        action: '播放语音消息',
        error: error,
        extra: {'filePath': filePath},
      );
    }
  }

  @override
  Future<void> stopVoicePlayback() async {
    if (!_isVoicePlaying) {
      return;
    }
    _isVoicePlaying = false;
    await _voicePlaybackTask;
    _voicePlaybackTask = null;
    await _logger.info('audio', '停止语音消息播放', extra: {
      'backend': name,
    });
    await _stopLiveEngineIfIdle();
  }

  @override
  Future<void> startMicrophoneStream(
    void Function(Uint8List bytes) onAudioBytes,
  ) async {
    await init();
    if (_isVoiceRecording) {
      throw const ChatAudioException(
        code: 'VOICE_NOTE_BUSY',
        message: '语音消息录制中，不能开启实时语音',
        userMessage: '当前正在录制语音消息，请先结束录制再进入实时语音',
      );
    }
    if (_isStreamingMic) {
      return;
    }

    try {
      await _ensureLiveEngineStarted();
      _downsampler.reset();
      _sentPackets = 0;
      _micSubscription?.cancel();
      _micSubscription = _audioIo.input.listen((samples) async {
        final packet = _downsampler.process(samples);
        if (packet.isEmpty) {
          return;
        }
        onAudioBytes(packet);
        _sentPackets++;
        if (_sentPackets == 1 || _sentPackets % 25 == 0) {
          await _logger.info('audio.live', 'Windows 麦克风音频已重采样并发出', extra: {
            'backend': name,
            'packetCount': _sentPackets,
            'inputSamples': samples.length,
            'outputBytes': packet.length,
          });
        }
      });
      _isStreamingMic = true;
      _lastError = null;
      await _logger.info('audio.live', '开始 Windows 实时麦克风采集', extra: {
        'backend': name,
        'inputSampleRate': _liveInputSampleRate,
        'outputSampleRate': ChatAudioService.sampleRate,
      });
    } catch (error) {
      await _micSubscription?.cancel();
      _micSubscription = null;
      _isStreamingMic = false;
      throw await _mapAndLogError(
        action: '启动实时麦克风采集',
        error: error,
      );
    }
  }

  @override
  Future<void> stopMicrophoneStream() async {
    if (!_isStreamingMic) {
      return;
    }
    await _micSubscription?.cancel();
    _micSubscription = null;
    _downsampler.reset();
    _isStreamingMic = false;
    await _logger.info('audio.live', '停止 Windows 实时麦克风采集', extra: {
      'backend': name,
    });
    await _stopLiveEngineIfIdle();
  }

  @override
  Future<void> startIncomingStreamPlayback() async {
    await init();
    if (_isIncomingStreamPlaying) {
      return;
    }
    try {
      await _ensureLiveEngineStarted();
      _isIncomingStreamPlaying = true;
      _receivedPackets = 0;
      _upsampler.reset();
      _lastError = null;
      await _logger.info('audio.live', '启动 Windows 实时语音播放', extra: {
        'backend': name,
        'inputSampleRate': ChatAudioService.sampleRate,
        'outputSampleRate': _liveOutputSampleRate,
      });
    } catch (error) {
      _isIncomingStreamPlaying = false;
      throw await _mapAndLogError(
        action: '启动实时语音播放',
        error: error,
      );
    }
  }

  @override
  Future<void> stopIncomingStreamPlayback() async {
    if (!_isIncomingStreamPlaying) {
      return;
    }
    _isIncomingStreamPlaying = false;
    _upsampler.reset();
    await _logger.info('audio.live', '停止 Windows 实时语音播放', extra: {
      'backend': name,
    });
    await _stopLiveEngineIfIdle();
  }

  @override
  Future<void> playIncomingPcm(Uint8List bytes) async {
    await startIncomingStreamPlayback();
    final samples = _upsampler.process(bytes);
    if (samples.isEmpty) {
      return;
    }
    _audioIo.output.add(samples);
    _receivedPackets++;
    if (_receivedPackets == 1 || _receivedPackets % 25 == 0) {
      await _logger.info('audio.live', 'Windows 语音包已重采样并播放', extra: {
        'backend': name,
        'packetCount': _receivedPackets,
        'inputBytes': bytes.length,
        'outputSamples': samples.length,
      });
    }
  }

  @override
  Future<void> dispose() async {
    await stopVoicePlayback();
    if (_isVoiceRecording) {
      await cancelVoiceNoteRecording();
    }
    await stopMicrophoneStream();
    await stopIncomingStreamPlayback();
    await _micSubscription?.cancel();
    await _recorder.dispose();
    _initialized = false;
  }

  Future<void> _playVoiceWav(_Pcm16Wav wav) async {
    _voiceUpsampler.reset();
    const chunkInputSamples = 320;
    for (var offset = 0; offset < wav.samples.length && _isVoicePlaying;) {
      final end = (offset + chunkInputSamples).clamp(0, wav.samples.length);
      final chunk = Int16List.sublistView(wav.samples, offset, end);
      final output = _voiceSamplesToOutput(chunk, wav.sampleRate);
      if (output.isNotEmpty && _isVoicePlaying) {
        _audioIo.output.add(output);
      }
      offset = end;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  List<double> _voiceSamplesToOutput(Int16List samples, int sampleRate) {
    if (sampleRate == ChatAudioService.sampleRate) {
      final pcmBytes = Uint8List.view(
        samples.buffer,
        samples.offsetInBytes,
        samples.lengthInBytes,
      );
      return _voiceUpsampler.process(pcmBytes);
    }
    if (sampleRate == 48000) {
      return List<double>.generate(
        samples.length,
        (index) => (samples[index] / 32768.0).clamp(-1.0, 1.0).toDouble(),
        growable: false,
      );
    }
    throw ChatAudioException(
      code: 'UNSUPPORTED_WAV_SAMPLE_RATE',
      message: 'Unsupported WAV sample rate: $sampleRate',
      userMessage: '当前语音文件采样率不受支持',
    );
  }

  _Pcm16Wav _decodePcm16Wav(Uint8List bytes) {
    if (bytes.length < 44) {
      throw const ChatAudioException(
        code: 'INVALID_WAV',
        message: 'WAV file is too small',
        userMessage: '语音文件格式无效',
      );
    }
    final data = ByteData.sublistView(bytes);
    String tag(int offset, int length) =>
        String.fromCharCodes(bytes.sublist(offset, offset + length));
    if (tag(0, 4) != 'RIFF' || tag(8, 4) != 'WAVE') {
      throw const ChatAudioException(
        code: 'INVALID_WAV',
        message: 'Missing RIFF/WAVE header',
        userMessage: '语音文件格式无效',
      );
    }

    var offset = 12;
    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;
    while (offset + 8 <= bytes.length) {
      final chunkId = tag(offset, 4);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;
      if (chunkDataOffset + chunkSize > bytes.length) {
        break;
      }
      if (chunkId == 'fmt ') {
        audioFormat = data.getUint16(chunkDataOffset, Endian.little);
        channels = data.getUint16(chunkDataOffset + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataOffset + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataOffset;
        dataLength = chunkSize;
      }
      offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (audioFormat != 1 || bitsPerSample != 16 || dataOffset == null) {
      throw const ChatAudioException(
        code: 'UNSUPPORTED_WAV',
        message: 'Only PCM16 WAV files are supported',
        userMessage: '当前只支持 PCM16 WAV 语音文件',
      );
    }
    final channelCount = channels ?? 1;
    final frameCount = (dataLength ?? 0) ~/ (2 * channelCount);
    final samples = Int16List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      var mixed = 0;
      for (var channel = 0; channel < channelCount; channel++) {
        mixed += data.getInt16(
          dataOffset + (frame * channelCount + channel) * 2,
          Endian.little,
        );
      }
      samples[frame] =
          (mixed / channelCount).round().clamp(-32768, 32767).toInt();
    }
    return _Pcm16Wav(samples: samples, sampleRate: sampleRate ?? 16000);
  }

  Future<void> _ensureLiveEngineStarted() async {
    if (_liveEngineStarted) {
      return;
    }
    await _audioIo.requestLatency(AudioIoLatency.Realtime);
    await _audioIo.start();
    final format = await _audioIo.getFormat();
    _liveInputSampleRate = _extractSampleRate(format, 'input');
    _liveOutputSampleRate = _extractSampleRate(format, 'output');
    _liveEngineStarted = true;
    _lastError = null;
    await _logger.info('audio.live', '启动 Windows 实时音频引擎', extra: {
      'backend': name,
      'inputSampleRate': _liveInputSampleRate,
      'outputSampleRate': _liveOutputSampleRate,
      'headsetRecommended': capabilities.headsetRecommended,
    });
  }

  Future<void> _stopLiveEngineIfIdle() async {
    if (!_liveEngineStarted ||
        _isIncomingStreamPlaying ||
        _isStreamingMic ||
        _isVoicePlaying) {
      return;
    }
    await _audioIo.stop();
    _liveEngineStarted = false;
    await _logger.info('audio.live', '停止 Windows 实时音频引擎', extra: {
      'backend': name,
    });
  }

  int _extractSampleRate(Map<String, dynamic>? format, String key) {
    final section = format?[key];
    if (section is Map && section['sampleRate'] is num) {
      return (section['sampleRate'] as num).round();
    }
    return 48000;
  }

  Future<ChatAudioException> _mapAndLogError({
    required String action,
    required Object error,
    Map<String, Object?> extra = const {},
  }) async {
    final mapped = _mapError(action, error);
    _lastError = mapped.message;
    await _logger.error('audio', '$action失败', extra: {
      'backend': name,
      'error': mapped.toString(),
      ...extra,
    });
    return mapped;
  }

  ChatAudioException _mapError(String action, Object error) {
    if (error is ChatAudioException) {
      return error;
    }
    if (error is AudioIoException) {
      if (error.isPermissionDenied) {
        return const ChatAudioException(
          code: 'MICROPHONE_PERMISSION_DENIED',
          message: 'Windows 麦克风权限被拒绝',
          userMessage:
              '请在 Windows 设置 > 隐私和安全性 > 麦克风 中允许桌面应用访问麦克风，然后重新进入语音',
          isPermissionDenied: true,
        );
      }
      return ChatAudioException(
        code: 'AUDIO_IO_ERROR',
        message: error.message,
        userMessage: '$action失败，请检查麦克风、耳机或其他音频设备是否可用',
      );
    }
    return ChatAudioException(
      code: 'AUDIO_ERROR',
      message: error.toString(),
      userMessage: '$action失败，请检查音频设备是否正常并建议佩戴耳机后重试',
    );
  }
}

class _Pcm16Wav {
  const _Pcm16Wav({
    required this.samples,
    required this.sampleRate,
  });

  final Int16List samples;
  final int sampleRate;
}

class _UnsupportedChatAudioBackend implements ChatAudioBackend {
  _UnsupportedChatAudioBackend({required String reason})
      : _reason = reason,
        _capabilities = ChatAudioCapabilities(
          voiceNotes: false,
          directCalls: false,
          channelPtt: false,
          headsetRecommended: false,
          unsupportedReason: reason,
        );

  final String _reason;
  final ChatAudioCapabilities _capabilities;

  @override
  String get name => 'unsupported';

  @override
  ChatAudioCapabilities get capabilities => _capabilities;

  @override
  String get preferredVoiceFileExtension => '.wav';

  @override
  String get preferredVoiceCodecLabel => 'unsupported';

  @override
  bool get isVoiceRecording => false;

  @override
  bool get isVoicePlaying => false;

  @override
  bool get isStreamingMic => false;

  @override
  bool get isIncomingStreamPlaying => false;

  @override
  String? get lastError => _reason;

  @override
  int? get liveInputSampleRate => null;

  @override
  int? get liveOutputSampleRate => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> startVoiceNoteRecording(String targetPath) async {
    throw ChatAudioException(
      code: 'UNSUPPORTED_PLATFORM',
      message: _reason,
      userMessage: _reason,
    );
  }

  @override
  Future<String?> stopVoiceNoteRecording() async => null;

  @override
  Future<void> cancelVoiceNoteRecording() async {}

  @override
  Future<void> playVoiceFile(String filePath) async {
    throw ChatAudioException(
      code: 'UNSUPPORTED_PLATFORM',
      message: _reason,
      userMessage: _reason,
    );
  }

  @override
  Future<void> stopVoicePlayback() async {}

  @override
  Future<void> startMicrophoneStream(
    void Function(Uint8List bytes) onAudioBytes,
  ) async {
    throw ChatAudioException(
      code: 'UNSUPPORTED_PLATFORM',
      message: _reason,
      userMessage: _reason,
    );
  }

  @override
  Future<void> stopMicrophoneStream() async {}

  @override
  Future<void> startIncomingStreamPlayback() async {
    throw ChatAudioException(
      code: 'UNSUPPORTED_PLATFORM',
      message: _reason,
      userMessage: _reason,
    );
  }

  @override
  Future<void> stopIncomingStreamPlayback() async {}

  @override
  Future<void> playIncomingPcm(Uint8List bytes) async {
    throw ChatAudioException(
      code: 'UNSUPPORTED_PLATFORM',
      message: _reason,
      userMessage: _reason,
    );
  }

  @override
  Future<void> dispose() async {}
}
