import SwiftUI

struct TapScribeMenuPanelView: View {
    let globalStatusLabel: String
    let globalStatusTone: RecordingStatusTone
    let rows: [RecordingMenuRow]
    let isRecording: Bool

    var onToggleRecording: () -> Void
    var onSelectRow: (RecordingMenuRow) -> Void
    var onShowInFinder: () -> Void
    var onOpenModelSettings: () -> Void
    var onRedownloadModel: () -> Void
    var onOpenSystemAudioSettings: () -> Void
    var onQuit: () -> Void
    var onAppearRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            globalHeader
            Divider()
            recordingsList
            Divider()
            actionsBlock
        }
        .frame(width: 280)
        .background(.regularMaterial)
        .onAppear(perform: onAppearRefresh)
    }

    private var globalHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(globalStatusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(globalStatusTone.foregroundColor)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var recordingsList: some View {
        Group {
            if rows.isEmpty {
                Text("Brak nagrań")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(rows) { row in
                            recordingRow(row)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func recordingRow(_ row: RecordingMenuRow) -> some View {
        Button {
            onSelectRow(row)
        } label: {
            HStack(spacing: 8) {
                rowIcon(row)
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(.secondary)

                Text(row.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(row.trailingStatus)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(row.statusTone.foregroundColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(row.statusTone.foregroundColor.opacity(0.18))
                    )
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowIcon(_ row: RecordingMenuRow) -> some View {
        if let systemImage = row.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 13))
        } else {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(RecordingStatusTone.working.foregroundColor)
        }
    }

    private var rowBackground: some View {
        Color(nsColor: .quaternarySystemFill)
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelAction(isRecording ? "Zakończ nagrywanie" : "Start nagrywania", action: onToggleRecording)
            panelAction("Pokaż w Finderze", action: onShowInFinder)

            Menu {
                Button("Model transkrypcji…", action: onOpenModelSettings)
                Button("Pobierz ponownie model…", action: onRedownloadModel)
                Divider()
                Button("Dźwięk systemu (TCC)…", action: onOpenSystemAudioSettings)
            } label: {
                HStack {
                    Text("Ustawienia")
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)

            panelAction("Zakończ", action: onQuit)
        }
        .padding(.vertical, 4)
    }

    private func panelAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
