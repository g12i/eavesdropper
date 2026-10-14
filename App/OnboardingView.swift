import SwiftUI

struct OnboardingView: View {
    @ObservedObject var modelStore: WhisperModelStore
    var onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TapScribe — model transkrypcji")
                .font(.title2.bold())

            Text(
                """
                Po zatrzymaniu nagrania TapScribe tworzy transkrypt po polsku (Whisper). \
                Do tego potrzebny jest jednorazowy download modelu (~1,5 GB) w folderze \
                Application Support.
                """
            )
            .fixedSize(horizontal: false, vertical: true)

            Text("Nagrywanie dźwięku systemu (YouTube, rozmowy) nie wymaga modelu.")
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

                if !modelStore.detailLine.isEmpty {
                    Text(modelStore.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text(modelStore.statusLine)
                    .font(.body)

                if !modelStore.detailLine.isEmpty {
                    Text(modelStore.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                if modelStore.isReady {
                    Button("Kontynuuj") {
                        onFinished()
                    }
                    .keyboardShortcut(.defaultAction)
                } else if modelStore.isBusy {
                    Button("Anuluj pobieranie") {
                        modelStore.cancelDownload()
                    }
                } else {
                    Button("Pobierz model") {
                        modelStore.startDownload(forceRedownload: false)
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Później") {
                        onFinished()
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
        .task {
            await modelStore.refreshReadyState()
        }
        .onChange(of: modelStore.isBusy) { wasBusy, isBusy in
            if wasBusy, !isBusy, modelStore.isReady {
                onFinished()
            }
        }
        .onChange(of: modelStore.isReady) { _, isReady in
            if isReady, !modelStore.isBusy {
                onFinished()
            }
        }
    }
}
