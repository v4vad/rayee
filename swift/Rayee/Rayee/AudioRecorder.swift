//
//  AudioRecorder.swift
//  Rayee
//
//  Records 16kHz mono Float32 audio with AVAudioEngine and stops automatically
//  after the user has been silent for the configured time.
//

import Foundation
import AVFoundation

// Errors that can occur during recording
enum AudioRecorderError: LocalizedError {
    case noMicrophonePermission
    case engineStartFailed(String)
    case noAudioRecorded

    var errorDescription: String? {
        switch self {
        case .noMicrophonePermission:
            return "Microphone permission not granted. Please allow in System Settings."
        case .engineStartFailed(let message):
            return "Failed to start audio recording: \(message)"
        case .noAudioRecorded:
            return "No audio was recorded."
        }
    }
}

// Result of a recording session
struct RecordingResult {
    let duration: TimeInterval  // How long the recording was
    let audioData: [Float]      // 16kHz mono samples, passed straight to WhisperKit
}

class AudioRecorder {
    // Audio format settings - Whisper expects 16kHz mono
    private let sampleRate: Double = Config.audioSampleRate
    private let channels: AVAudioChannelCount = 1  // Mono

    // Silence detection settings
    private var silenceDuration: TimeInterval   // How long silence triggers stop
    private let maxDuration: TimeInterval = Config.maxRecordingDuration  // Always enforced

    // Speech detection and which samples to keep (see SpeechGate)
    private let adaptiveVADEnabled: Bool
    private var gate: SpeechGate

    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // Recording state
    private var isRecording = false
    private var recordingStartTime: Date?
    private var lastSpeechTime: Date?

    // Callbacks
    var onRecordingComplete: ((Result<RecordingResult, AudioRecorderError>) -> Void)?
    var onAudioLevel: ((Float) -> Void)?  // For UI feedback
    /// Every converted 16kHz mono buffer, silence included, before the speech gate. Called on the audio thread.
    var onRawBuffer: ((AVAudioPCMBuffer) -> Void)?

    init(silenceDuration: TimeInterval = Config.defaultSilenceDuration,
         adaptiveVADEnabled: Bool = false) {
        self.silenceDuration = silenceDuration
        self.adaptiveVADEnabled = adaptiveVADEnabled
        self.gate = SpeechGate(adaptive: adaptiveVADEnabled)
    }

    // MARK: - Public Methods

    /// Request microphone permission
    /// Returns true if permission granted, false otherwise
    static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[AudioRecorder] Microphone permission status: \(status.rawValue)")
        // Status values: 0=notDetermined, 1=restricted, 2=denied, 3=authorized

        switch status {
        case .authorized:
            print("[AudioRecorder] Permission already authorized")
            return true
        case .notDetermined:
            // Request permission
            print("[AudioRecorder] Permission not determined, requesting...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            print("[AudioRecorder] Permission request result: \(granted)")
            return granted
        case .denied:
            print("[AudioRecorder] Permission denied by user")
            return false
        case .restricted:
            print("[AudioRecorder] Permission restricted by system policy")
            return false
        @unknown default:
            print("[AudioRecorder] Unknown permission status")
            return false
        }
    }

    /// Check if microphone permission is granted
    static func hasMicrophonePermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Start recording audio
    /// Recording will automatically stop when silence is detected or max duration reached
    func startRecording() throws {
        guard !isRecording else {
            print("[AudioRecorder] Already recording")
            return
        }

        // Reset state
        gate = SpeechGate(adaptive: adaptiveVADEnabled)
        recordingStartTime = Date()
        lastSpeechTime = nil
        isRecording = true

        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioRecorderError.engineStartFailed("Failed to create audio engine")
        }

        inputNode = engine.inputNode
        guard let input = inputNode else {
            throw AudioRecorderError.engineStartFailed("No audio input available")
        }

        // Get the native format and create our target format
        let nativeFormat = input.outputFormat(forBus: 0)

        // Our target format: 16kHz, mono, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw AudioRecorderError.engineStartFailed("Failed to create target audio format")
        }

        // Create converter from native format to our target format
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw AudioRecorderError.engineStartFailed("Failed to create audio converter")
        }

        // Calculate buffer sizes
        // We'll process in 100ms chunks for responsive silence detection
        let bufferSize = AVAudioFrameCount(nativeFormat.sampleRate * 0.1)

        // Install tap on input node
        input.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        // Start the engine
        do {
            try engine.start()
            print("[AudioRecorder] Recording started")
        } catch {
            isRecording = false
            audioEngine = nil
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }

    /// Stop recording and save the audio file
    func stopRecording() {
        guard isRecording else { return }

        isRecording = false

        // Stop and clean up audio engine
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        print("[AudioRecorder] Recording stopped")

        // Check if we got any audio
        let audioData = gate.kept
        if audioData.isEmpty {
            onRecordingComplete?(.failure(.noAudioRecorded))
            return
        }

        let duration = Double(audioData.count) / sampleRate
        onRecordingComplete?(.success(RecordingResult(duration: duration, audioData: audioData)))
    }

    /// Cancel recording without saving
    func cancelRecording() {
        isRecording = false
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        gate = SpeechGate(adaptive: adaptiveVADEnabled)
        print("[AudioRecorder] Recording cancelled")
    }

    // MARK: - Private Methods

    /// Converts one microphone buffer to 16kHz mono.
    /// The input block hands the buffer over exactly once, then reports "no data for now".
    /// Returning the same buffer on every call makes the converter read the same audio twice
    /// whenever it asks for more input to fill its output.
    static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            print("[AudioRecorder] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        return output
    }

    /// Process incoming audio buffer
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        guard isRecording else { return }

        // Convert to our target format (16kHz mono)
        guard let convertedBuffer = AudioRecorder.convert(buffer, using: converter, to: targetFormat),
              let channelData = convertedBuffer.floatChannelData?[0] else {
            return
        }
        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0 else { return }
        onRawBuffer?(convertedBuffer)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Calculate audio level (RMS)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(frameLength))

        // Report audio level to UI
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(rms)
        }

        // Decide whether this is speech and which samples to keep
        let now = Date()
        if gate.feed(samples, rms: rms) {
            lastSpeechTime = now
        }

        // Check stopping conditions
        let elapsed = now.timeIntervalSince(recordingStartTime ?? now)

        // Stop if max duration reached (only if timeout is enabled)
        if elapsed >= maxDuration {
            print("[AudioRecorder] Max duration reached")
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording()
            }
            return
        }

        // Stop if silence after speech
        if gate.speechDetected, let lastSpeech = lastSpeechTime,
           now.timeIntervalSince(lastSpeech) >= silenceDuration {
            print("[AudioRecorder] Silence detected, stopping")
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording()
            }
        }
    }
}

/// Decides which samples to keep and whether each chunk is speech.
/// Pure logic with no audio hardware, so it can be unit-tested with made-up chunks.
struct SpeechGate {
    private let adaptive: Bool
    private let preRollSampleLimit: Int
    private let calibrationChunkTarget = 2  // 2 chunks × 100ms = 200ms

    private(set) var threshold: Float
    private(set) var speechDetected = false
    private(set) var kept: [Float] = []

    private var preRoll: [Float] = []
    private var calibrationRMS: [Float] = []

    init(
        fixedThreshold: Float = Config.silenceThreshold,
        adaptive: Bool,
        preRollSampleLimit: Int = Int(Config.audioSampleRate * Config.preRollDuration)
    ) {
        self.threshold = fixedThreshold
        self.adaptive = adaptive
        self.preRollSampleLimit = preRollSampleLimit
    }

    /// Feeds one chunk of 16kHz samples with its RMS level. Returns true if the chunk is speech.
    mutating func feed(_ samples: [Float], rms: Float) -> Bool {
        // Adaptive mode: the first chunks measure the room. Keep their audio in the
        // pre-roll anyway, because the user may already be talking.
        if adaptive && calibrationRMS.count < calibrationChunkTarget {
            calibrationRMS.append(rms)
            if calibrationRMS.count == calibrationChunkTarget {
                threshold = Self.adaptedThreshold(from: calibrationRMS)
                print("[SpeechGate] Adaptive VAD calibrated: threshold=\(threshold)")
            }
            appendToPreRoll(samples)
            return false
        }

        let isSpeech = rms > threshold
        if isSpeech && !speechDetected {
            speechDetected = true
            kept.append(contentsOf: preRoll)
            preRoll.removeAll()
            print("[SpeechGate] Speech detected")
        }

        if speechDetected {
            kept.append(contentsOf: samples)
        } else {
            appendToPreRoll(samples)
        }
        return isSpeech
    }

    /// 1.5× the room's average level, kept between the minimum and maximum allowed thresholds.
    static func adaptedThreshold(from rmsValues: [Float]) -> Float {
        let average = rmsValues.reduce(0, +) / Float(max(rmsValues.count, 1))
        return min(max(average * 1.5, Config.minSilenceThreshold), Config.maxAdaptiveSilenceThreshold)
    }

    private mutating func appendToPreRoll(_ samples: [Float]) {
        preRoll.append(contentsOf: samples)
        if preRoll.count > preRollSampleLimit {
            preRoll.removeFirst(preRoll.count - preRollSampleLimit)
        }
    }
}
