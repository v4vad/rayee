//
//  AudioRecorder.swift
//  Rayee
//
//  Records audio using AVFoundation and detects silence to auto-stop.
//  This runs in Swift (not Python) so it can use the app's microphone permission.
//

import Foundation
import AVFoundation

// Errors that can occur during recording
enum AudioRecorderError: LocalizedError {
    case noMicrophonePermission
    case engineStartFailed(String)
    case noAudioRecorded
    case failedToSaveFile(String)

    var errorDescription: String? {
        switch self {
        case .noMicrophonePermission:
            return "Microphone permission not granted. Please allow in System Settings."
        case .engineStartFailed(let message):
            return "Failed to start audio recording: \(message)"
        case .noAudioRecorded:
            return "No audio was recorded."
        case .failedToSaveFile(let message):
            return "Failed to save audio file: \(message)"
        }
    }
}

// Result of a recording session
struct RecordingResult {
    let audioPath: URL      // Path to the saved WAV file
    let duration: TimeInterval  // How long the recording was
}

class AudioRecorder {
    // Audio format settings - must match what Python/Whisper expects
    private let sampleRate: Double = Config.audioSampleRate
    private let channels: AVAudioChannelCount = 1  // Mono

    // Silence detection settings
    private let silenceThreshold: Float = Config.silenceThreshold
    private var silenceDuration: TimeInterval   // How long silence triggers stop
    private let maxDuration: TimeInterval = Config.maxRecordingDuration

    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // Recording state
    private var isRecording = false
    private var audioBuffer: [Float] = []
    private var recordingStartTime: Date?
    private var lastSpeechTime: Date?
    private var speechDetected = false

    // Callbacks
    var onSpeechDetected: (() -> Void)?
    var onRecordingComplete: ((Result<RecordingResult, AudioRecorderError>) -> Void)?
    var onAudioLevel: ((Float) -> Void)?  // For UI feedback

    init(silenceDuration: TimeInterval = Config.defaultSilenceDuration) {
        self.silenceDuration = silenceDuration
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
        audioBuffer = []
        recordingStartTime = Date()
        lastSpeechTime = nil
        speechDetected = false
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
        if audioBuffer.isEmpty {
            onRecordingComplete?(.failure(.noAudioRecorded))
            return
        }

        // Save to WAV file
        do {
            let audioPath = try saveToWavFile()
            let duration = Double(audioBuffer.count) / sampleRate
            let result = RecordingResult(audioPath: audioPath, duration: duration)
            onRecordingComplete?(.success(result))
        } catch let error as AudioRecorderError {
            onRecordingComplete?(.failure(error))
        } catch {
            onRecordingComplete?(.failure(.failedToSaveFile(error.localizedDescription)))
        }
    }

    /// Cancel recording without saving
    func cancelRecording() {
        isRecording = false
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        audioBuffer = []
        print("[AudioRecorder] Recording cancelled")
    }

    // MARK: - Private Methods

    /// Process incoming audio buffer
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        guard isRecording else { return }

        // Convert to our target format (16kHz mono)
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * (sampleRate / buffer.format.sampleRate)
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            print("[AudioRecorder] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // Get the audio data
        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let frameLength = Int(convertedBuffer.frameLength)

        // Calculate audio level (RMS)
        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))

        // Report audio level to UI
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(rms)
        }

        // Check for speech vs silence
        let isSpeech = rms > silenceThreshold
        let now = Date()

        if isSpeech {
            if !speechDetected {
                speechDetected = true
                DispatchQueue.main.async { [weak self] in
                    self?.onSpeechDetected?()
                }
                print("[AudioRecorder] Speech detected")
            }
            lastSpeechTime = now
        }

        // Only keep audio after speech is detected
        if speechDetected {
            // Append samples to buffer
            for i in 0..<frameLength {
                audioBuffer.append(channelData[i])
            }
        }

        // Check stopping conditions
        let elapsed = now.timeIntervalSince(recordingStartTime ?? now)

        // Stop if max duration reached
        if elapsed >= maxDuration {
            print("[AudioRecorder] Max duration reached")
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording()
            }
            return
        }

        // Stop if silence after speech
        if speechDetected, let lastSpeech = lastSpeechTime {
            let silenceTime = now.timeIntervalSince(lastSpeech)
            if silenceTime >= silenceDuration {
                print("[AudioRecorder] Silence detected, stopping")
                DispatchQueue.main.async { [weak self] in
                    self?.stopRecording()
                }
            }
        }
    }

    /// Save audio buffer to WAV file
    private func saveToWavFile() throws -> URL {
        // Create the .rayee directory if needed
        let rayeeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rayee")

        try? FileManager.default.createDirectory(
            at: rayeeDir,
            withIntermediateDirectories: true
        )

        let audioPath = rayeeDir.appendingPathComponent("audio_buffer.wav")

        // Create WAV file
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw AudioRecorderError.failedToSaveFile("Failed to create audio format")
        }

        guard let audioFile = try? AVAudioFile(
            forWriting: audioPath,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            throw AudioRecorderError.failedToSaveFile("Failed to create audio file")
        }

        // Create buffer with our audio data
        let frameCount = AVAudioFrameCount(audioBuffer.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioRecorderError.failedToSaveFile("Failed to create audio buffer")
        }

        buffer.frameLength = frameCount

        // Copy our samples to the buffer
        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in audioBuffer.enumerated() {
                channelData[index] = sample
            }
        }

        // Write to file
        do {
            try audioFile.write(from: buffer)
        } catch {
            throw AudioRecorderError.failedToSaveFile(error.localizedDescription)
        }

        let duration = Double(audioBuffer.count) / sampleRate
        print("[AudioRecorder] Saved \(duration)s of audio to \(audioPath.path)")

        return audioPath
    }
}
