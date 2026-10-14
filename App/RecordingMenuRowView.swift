import SwiftUI

struct RecordingMenuRowView: View {
    let row: RecordingMenuRow
    let action: () -> Void

    var body: some View {
        if let systemImage = row.systemImage {
            Button(action: action) {
                Label(row.menuLineTitle, systemImage: systemImage)
            }
        } else {
            Button(row.menuLineTitle, action: action)
        }
    }
}
