import AppKit
import SwiftData
import SwiftUI

struct PinboardsPane: View {
    @Query(sort: \Pinboard.order) private var pinboards: [Pinboard]
    @Environment(\.modelContext) private var context

    @State private var newName: String = ""
    @State private var pendingDelete: Pinboard?

    var body: some View {
        Form {
            Section("Pinboards") {
                if pinboards.isEmpty {
                    Text("No pinboards yet. Create one to group clipboard items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ForEach(pinboards) { board in
                        PinboardRow(
                            board: board,
                            canMoveUp: canMoveUp(board),
                            canMoveDown: canMoveDown(board),
                            onMoveUp: { moveUp(board) },
                            onMoveDown: { moveDown(board) },
                            onDelete: { pendingDelete = board }
                        )
                    }
                }
            }

            Section("Create") {
                HStack {
                    TextField("New pinboard name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addPinboard)
                    Button("Add") { addPinboard() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Delete pinboard?", isPresented: .constant(pendingDelete != nil), presenting: pendingDelete) { board in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                delete(board)
                pendingDelete = nil
            }
        } message: { board in
            let n = board.items.count
            if n > 0 {
                Text("\(n) item\(n == 1 ? "" : "s") will be returned to History.")
            } else {
                Text("\"\(board.name)\" is empty.")
            }
        }
    }

    private func addPinboard() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let next = (pinboards.map(\.order).max() ?? -1) + 1
        let board = Pinboard(name: name, order: next)
        context.insert(board)
        try? context.save()
        newName = ""
        AppState.shared.refresh()
    }

    private func delete(_ board: Pinboard) {
        for item in board.items { item.pinboard = nil }
        context.delete(board)
        try? context.save()
        AppState.shared.refresh()
    }

    private func canMoveUp(_ board: Pinboard) -> Bool {
        guard let idx = pinboards.firstIndex(where: { $0.id == board.id }) else { return false }
        return idx > 0
    }

    private func canMoveDown(_ board: Pinboard) -> Bool {
        guard let idx = pinboards.firstIndex(where: { $0.id == board.id }) else { return false }
        return idx < pinboards.count - 1
    }

    private func moveUp(_ board: Pinboard)   { swap(board, delta: -1) }
    private func moveDown(_ board: Pinboard) { swap(board, delta: +1) }

    private func swap(_ board: Pinboard, delta: Int) {
        guard let idx = pinboards.firstIndex(where: { $0.id == board.id }) else { return }
        let target = idx + delta
        guard target >= 0, target < pinboards.count else { return }
        let other = pinboards[target]
        let o = board.order
        board.order = other.order
        other.order = o
        try? context.save()
        AppState.shared.refresh()
    }
}

private struct PinboardRow: View {
    @Bindable var board: Pinboard
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp)
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown)
            }
            .font(.system(size: 10))

            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36)

            TextField("Name", text: $board.name)
                .textFieldStyle(.plain)

            Spacer()

            Text("\(board.items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var colorBinding: Binding<Color> {
        Binding<Color>(
            get: { Color(hex: board.accentColorHex) ?? .orange },
            set: { board.accentColorHex = $0.toHex() ?? "#FF6A3D" }
        )
    }
}

private extension Color {
    func toHex() -> String? {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
