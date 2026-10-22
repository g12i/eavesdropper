import SwiftUI

struct OnboardingView: View {
    @ObservedObject var modelStore: WhisperModelStore
    var onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Model")
                .font(.title2.bold())

            Text(
                """
                After stopping a recording, Eavesdropper creates a transcript using Whisper. \
                This requires a one-time model download (~1.5 GB) to the Application Support folder.
                """
            )
            .fixedSize(horizontal: false, vertical: true)

            Text("System audio recording (YouTube, calls) works immediately without the model.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if modelStore.isBusy {
                ProgressView(value: modelStore.downloadFraction) {
                    Text(modelStore.statusLine)
                } currentValueLabel: {
                    if let fraction = modelStore.downloadFraction {
                        Text("\(Int(fraction * 100))%")
                    }
                }
                .progressViewStyle(.linear)
            } else {
                Text(modelStore.statusLine)
                    .font(.body)
            }

            if !modelStore.detailLine.isEmpty {
                Text(modelStore.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if modelStore.isReady {
                    Button("Continue") {
                        onFinished()
                    }
                    .keyboardShortcut(.defaultAction)
                } else if modelStore.isBusy {
                    Button(modelStore.isLoadingModel ? "Cancel" : "Cancel Download") {
                        modelStore.cancelDownload()
                    }
                } else {
                    Button("Download Model") {
                        modelStore.startDownload(forceRedownload: false)
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Later") {
                        onFinished()
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            modelStore.refreshReadyState()
        }
        .onChange(of: modelStore.isBusy) { wasBusy, isBusy in
            if wasBusy, !isBusy, modelStore.isReady {
                onFinished()
            }
        }
    }
}
