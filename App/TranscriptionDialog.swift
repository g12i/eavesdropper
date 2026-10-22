import SwiftUI
import AppKit

struct TranscriptionDialog: View {
    @ObservedObject var model: TranscriptionDialogModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoSection
                    
                    if model.isShortRecording {
                        shortWarningSection
                    }

                    if !model.isModelReady && !model.state.isDone {
                        modelMissingSection
                    } else if !model.state.isDone {
                        languagePickerSection
                    }

                    statusSection
                }
                .padding()
            }

            Divider()

            buttonsSection
        }
        .frame(width: 440, height: 300)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recording Info")
                .font(.headline)
            Text(formatDate())
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Duration: \(formatDuration(model.audioSeconds))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var shortWarningSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "triangle.fill")
                .foregroundColor(.yellow)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text("Short Recording")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Recording is \(formatDuration(model.audioSeconds)). Short recordings often produce empty or inaccurate results.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(6)
    }

    private var modelMissingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription model not available")
                .font(.caption)
                .fontWeight(.semibold)
            Text(model.modelStatus)
                .font(.caption2)
                .foregroundColor(.secondary)
            Button("Download Model…") {
                model.presentOnboarding()
            }
            .font(.caption)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }

    private var languagePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Language")
                .font(.caption)
                .fontWeight(.semibold)
            Picker("", selection: $model.selectedLanguage) {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.state.isActive)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.state {
            case .queued(let lang):
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Queued for transcription")
                            .font(.caption)
                        if let pos = model.queuePosition {
                            Text("Position in queue: \(pos + 1)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

            case .loadingModel(let lang):
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading transcription model…")
                        .font(.caption)
                }
                Text("This may take several minutes on first run.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

            case .transcribing(let lang, let fraction):
                VStack(spacing: 4) {
                    ProgressView(value: fraction)
                    Text("Transcribing… \(Int(fraction * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .done(let detectedLang):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcript ready")
                            .font(.caption)
                            .fontWeight(.semibold)
                        if let lang = detectedLang {
                            Text("Detected language: \(lang)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Error")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

            default:
                EmptyView()
            }
        }
    }

    private var buttonsSection: some View {
        HStack(spacing: 12) {
            Button("Show in Finder") {
                model.openInFinder()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if case .done = model.state {
                Button("Open Transcript") {
                    model.openTranscript()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                secondaryActionButton
                primaryActionButton
            }
        }
        .padding()
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if model.isModelReady {
            switch model.state {
            case .done:
                Button("Transcribe Again") {
                    model.transcribe()
                }
                .keyboardShortcut(.defaultAction)

            case .queued, .loadingModel, .transcribing:
                Button("Cancel") {
                    model.cancel()
                }

            default:
                Button("Transcribe") {
                    model.transcribe()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isTranscribeDisabled)
            }
        }
    }

    @ViewBuilder
    private var secondaryActionButton: some View {
        if case .queued = model.state {
            Button("Cancel") {
                model.cancel()
            }
        } else if case .transcribing = model.state {
            Button("Cancel") {
                model.cancel()
            }
        }
    }

    private func formatDate() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: Date())
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
