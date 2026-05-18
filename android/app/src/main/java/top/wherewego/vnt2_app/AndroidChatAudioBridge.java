package top.wherewego.vnt2_app;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public final class AndroidChatAudioBridge {
    private static final String METHOD_CHANNEL = "top.wherewego.vnt2/chat_audio";
    private static final String MIC_STREAM_CHANNEL = "top.wherewego.vnt2/chat_audio/mic_stream";
    private static final int SAMPLE_RATE = 16000;
    private static final int CHANNEL_COUNT = 1;
    private static final int BITS_PER_SAMPLE = 16;
    private static final int AUDIO_PERMISSION_REQUEST_CODE = 4102;

    private final Activity activity;
    private final ExecutorService executor = Executors.newCachedThreadPool();
    private EventChannel.EventSink micEventSink;
    private AudioTrack incomingTrack;
    private AudioTrack voiceTrack;
    private AudioRecord voiceRecorder;
    private AudioRecord streamRecorder;
    private RandomAccessFile voiceFile;
    private Future<?> voiceRecordTask;
    private Future<?> micStreamTask;
    private String voicePath;
    private int voiceDataBytes;
    private final AtomicBoolean voiceRecording = new AtomicBoolean(false);
    private final AtomicBoolean micStreaming = new AtomicBoolean(false);
    private final AtomicBoolean voicePlaying = new AtomicBoolean(false);

    private AndroidChatAudioBridge(Activity activity) {
        this.activity = activity;
    }

    public static void init(FlutterEngine flutterEngine, Activity activity) {
        AndroidChatAudioBridge bridge = new AndroidChatAudioBridge(activity);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                METHOD_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            try {
                switch (call.method) {
                    case "init":
                        result.success(null);
                        break;
                    case "startVoiceRecord":
                        bridge.startVoiceRecord((String) call.argument("path"));
                        result.success(null);
                        break;
                    case "stopVoiceRecord":
                        result.success(bridge.stopVoiceRecord(false));
                        break;
                    case "cancelVoiceRecord":
                        bridge.stopVoiceRecord(true);
                        result.success(null);
                        break;
                    case "playVoiceFile":
                        bridge.playVoiceFile((String) call.argument("path"));
                        result.success(null);
                        break;
                    case "stopVoicePlayback":
                        bridge.stopVoicePlayback();
                        result.success(null);
                        break;
                    case "startMicrophoneStream":
                        bridge.startMicrophoneStream();
                        result.success(null);
                        break;
                    case "stopMicrophoneStream":
                        bridge.stopMicrophoneStream();
                        result.success(null);
                        break;
                    case "startIncomingPlayback":
                        bridge.startIncomingPlayback();
                        result.success(null);
                        break;
                    case "stopIncomingPlayback":
                        bridge.stopIncomingPlayback();
                        result.success(null);
                        break;
                    case "playIncomingPcm":
                        bridge.playIncomingPcm((byte[]) call.arguments);
                        result.success(null);
                        break;
                    case "dispose":
                        bridge.dispose();
                        result.success(null);
                        break;
                    default:
                        result.notImplemented();
                        break;
                }
            } catch (SecurityException e) {
                result.error("MICROPHONE_PERMISSION_DENIED", e.getMessage(), null);
            } catch (Exception e) {
                result.error("ANDROID_AUDIO_ERROR", e.getMessage(), null);
            }
        });
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                MIC_STREAM_CHANNEL
        ).setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                bridge.micEventSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                bridge.micEventSink = null;
                bridge.stopMicrophoneStream();
            }
        });
    }

    private void ensureMicPermission() {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }
        ActivityCompat.requestPermissions(
                activity,
                new String[]{Manifest.permission.RECORD_AUDIO},
                AUDIO_PERMISSION_REQUEST_CODE
        );
        throw new SecurityException("需要麦克风权限");
    }

    private AudioRecord createRecorder() {
        ensureMicPermission();
        int minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
        );
        int bufferSize = Math.max(minBuffer, SAMPLE_RATE / 5 * 2);
        AudioRecord recorder = new AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
        );
        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            recorder.release();
            throw new IllegalStateException("AudioRecord 初始化失败");
        }
        return recorder;
    }

    private AudioTrack createTrack() {
        int minBuffer = AudioTrack.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
        );
        int bufferSize = Math.max(minBuffer, SAMPLE_RATE / 5 * 2);
        return new AudioTrack(
                android.media.AudioManager.STREAM_VOICE_CALL,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
                AudioTrack.MODE_STREAM
        );
    }

    private void startVoiceRecord(String path) throws IOException {
        if (path == null || path.trim().isEmpty()) {
            throw new IllegalArgumentException("path is required");
        }
        if (!voiceRecording.compareAndSet(false, true)) {
            return;
        }
        voicePath = path;
        voiceDataBytes = 0;
        voiceFile = new RandomAccessFile(path, "rw");
        voiceFile.setLength(0);
        writeWavHeader(voiceFile, 0);
        voiceRecorder = createRecorder();
        voiceRecorder.startRecording();
        voiceRecordTask = executor.submit(() -> {
            byte[] buffer = new byte[Math.max(2048, AudioRecord.getMinBufferSize(
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
            ))];
            while (voiceRecording.get()) {
                int read = voiceRecorder.read(buffer, 0, buffer.length);
                if (read > 0) {
                    try {
                        voiceFile.write(buffer, 0, read);
                        voiceDataBytes += read;
                    } catch (IOException ignored) {
                        voiceRecording.set(false);
                    }
                }
            }
        });
    }

    private String stopVoiceRecord(boolean cancel) throws IOException {
        if (!voiceRecording.getAndSet(false)) {
            return voicePath;
        }
        if (voiceRecorder != null) {
            try {
                voiceRecorder.stop();
            } catch (Exception ignored) {
            }
            voiceRecorder.release();
            voiceRecorder = null;
        }
        waitTask(voiceRecordTask);
        voiceRecordTask = null;
        String result = voicePath;
        if (voiceFile != null) {
            writeWavHeader(voiceFile, voiceDataBytes);
            voiceFile.close();
            voiceFile = null;
        }
        if (cancel && result != null) {
            new File(result).delete();
        }
        voicePath = null;
        voiceDataBytes = 0;
        return result;
    }

    private void startMicrophoneStream() {
        if (!micStreaming.compareAndSet(false, true)) {
            return;
        }
        streamRecorder = createRecorder();
        streamRecorder.startRecording();
        micStreamTask = executor.submit(() -> {
            byte[] buffer = new byte[Math.max(2048, AudioRecord.getMinBufferSize(
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
            ))];
            while (micStreaming.get()) {
                int read = streamRecorder.read(buffer, 0, buffer.length);
                EventChannel.EventSink sink = micEventSink;
                if (read > 0 && sink != null) {
                    byte[] packet = new byte[read];
                    System.arraycopy(buffer, 0, packet, 0, read);
                    activity.runOnUiThread(() -> sink.success(packet));
                }
            }
        });
    }

    private void stopMicrophoneStream() {
        if (!micStreaming.getAndSet(false)) {
            return;
        }
        if (streamRecorder != null) {
            try {
                streamRecorder.stop();
            } catch (Exception ignored) {
            }
            streamRecorder.release();
            streamRecorder = null;
        }
        waitTask(micStreamTask);
        micStreamTask = null;
    }

    private void startIncomingPlayback() {
        if (incomingTrack != null) {
            return;
        }
        incomingTrack = createTrack();
        incomingTrack.play();
    }

    private void stopIncomingPlayback() {
        if (incomingTrack == null) {
            return;
        }
        try {
            incomingTrack.stop();
        } catch (Exception ignored) {
        }
        incomingTrack.release();
        incomingTrack = null;
    }

    private void playIncomingPcm(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            return;
        }
        startIncomingPlayback();
        incomingTrack.write(bytes, 0, bytes.length);
    }

    private void playVoiceFile(String path) {
        if (path == null || path.trim().isEmpty()) {
            throw new IllegalArgumentException("path is required");
        }
        stopVoicePlayback();
        voicePlaying.set(true);
        executor.execute(() -> {
            try (RandomAccessFile file = new RandomAccessFile(path, "r")) {
                byte[] pcm = readWavPcm(file);
                voiceTrack = createTrack();
                voiceTrack.play();
                voiceTrack.write(pcm, 0, pcm.length);
            } catch (Exception ignored) {
            } finally {
                stopVoicePlayback();
                voicePlaying.set(false);
            }
        });
    }

    private void stopVoicePlayback() {
        voicePlaying.set(false);
        if (voiceTrack == null) {
            return;
        }
        try {
            voiceTrack.stop();
        } catch (Exception ignored) {
        }
        voiceTrack.release();
        voiceTrack = null;
    }

    private void dispose() {
        try {
            stopVoiceRecord(true);
        } catch (Exception ignored) {
        }
        stopVoicePlayback();
        stopMicrophoneStream();
        stopIncomingPlayback();
    }

    private void waitTask(Future<?> task) {
        if (task == null) {
            return;
        }
        try {
            task.get();
        } catch (Exception ignored) {
        }
    }

    private byte[] readWavPcm(RandomAccessFile file) throws IOException {
        if (file.length() <= 44) {
            return new byte[0];
        }
        byte[] header = new byte[44];
        file.readFully(header);
        int dataSize = ByteBuffer.wrap(header, 40, 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .getInt();
        dataSize = Math.max(0, Math.min(dataSize, (int) (file.length() - 44)));
        byte[] pcm = new byte[dataSize];
        file.readFully(pcm);
        return pcm;
    }

    private void writeWavHeader(RandomAccessFile file, int dataSize) throws IOException {
        file.seek(0);
        ByteBuffer buffer = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        buffer.put(new byte[]{'R', 'I', 'F', 'F'});
        buffer.putInt(36 + dataSize);
        buffer.put(new byte[]{'W', 'A', 'V', 'E'});
        buffer.put(new byte[]{'f', 'm', 't', ' '});
        buffer.putInt(16);
        buffer.putShort((short) 1);
        buffer.putShort((short) CHANNEL_COUNT);
        buffer.putInt(SAMPLE_RATE);
        buffer.putInt(SAMPLE_RATE * CHANNEL_COUNT * BITS_PER_SAMPLE / 8);
        buffer.putShort((short) (CHANNEL_COUNT * BITS_PER_SAMPLE / 8));
        buffer.putShort((short) BITS_PER_SAMPLE);
        buffer.put(new byte[]{'d', 'a', 't', 'a'});
        buffer.putInt(dataSize);
        file.write(buffer.array());
    }
}
