import SwiftUI

/// Settings › Protocols: build named routines TESS runs on command.
struct RoutinesPage: View {
    @EnvironmentObject var assistant: Assistant
    @ObservedObject private var store = RoutineStore.shared

    var body: some View {
        PageHeader("Protocols", "Your own routines. Say “Hey Tess, run work mode” and she does every step in order.") {
            Button { _ = store.add() } label: { Label("New protocol", systemImage: "plus") }
                .buttonStyle(ThemedButtonStyle(kind: .primary))
        }

        if store.routines.isEmpty {
            Card {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.tertiary)
                    Text("No protocols yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text("Press New protocol to make one — for example “Focus” that opens your work apps and turns on Do Not Disturb through a Shortcut.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(26)
            }
        }

        ForEach(store.routines) { routine in
            RoutineCard(routine: binding(routine.id)) {
                assistant.runRoutine(routine)
            } delete: {
                store.delete(routine.id)
            }
        }

        Card(footer: "“Run Shortcut” runs any shortcut from Apple's Shortcuts app by name — use it for Focus modes, HomeKit scenes and more. “Say” steps are spoken at the end.") {
            SettingRow("lightbulb", "Tips", subtitle: "Name protocols the way you'd say them. TESS ignores the words “protocol” and “mode” when matching, so “run work” also finds “Work mode”.") {
                EmptyView()
            }
        }
    }

    private func binding(_ id: UUID) -> Binding<Routine> {
        Binding(
            get: { store.routines.first { $0.id == id } ?? Routine(name: "", steps: []) },
            set: { updated in
                if let index = store.routines.firstIndex(where: { $0.id == id }) { store.routines[index] = updated }
            }
        )
    }
}

private struct RoutineCard: View {
    @Binding var routine: Routine
    let run: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconBadge(icon: "bolt.circle", tint: Theme.orange, size: 30)
                TextField("", text: $routine.name, prompt: Text("Protocol name"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { run() } label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(ThemedButtonStyle(kind: .primary))
                Button { delete() } label: { Image(systemName: "trash") }
                    .buttonStyle(ThemedButtonStyle(kind: .destructive))
                    .help("Delete this protocol")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(Theme.stroke).frame(height: 1)

            ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                StepRow(number: index + 1, step: stepBinding(step.id), isFirst: index == 0,
                        isLast: index == routine.steps.count - 1) { offset in
                    move(step.id, by: offset)
                } remove: {
                    routine.steps.removeAll { $0.id == step.id }
                }
                if index < routine.steps.count - 1 { RowDivider() }
            }

            HStack {
                Menu {
                    ForEach(RoutineStep.Kind.allCases) { kind in
                        Button { routine.steps.append(RoutineStep(kind, "")) } label: {
                            Label(kind.title, systemImage: kind.icon)
                        }
                    }
                } label: {
                    Label("Add step", systemImage: "plus.circle")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Text("Say “Hey Tess, run \(routine.name.lowercased())”")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func stepBinding(_ id: UUID) -> Binding<RoutineStep> {
        Binding(
            get: { routine.steps.first { $0.id == id } ?? RoutineStep(.say, "") },
            set: { updated in
                if let index = routine.steps.firstIndex(where: { $0.id == id }) { routine.steps[index] = updated }
            }
        )
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = routine.steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard routine.steps.indices.contains(target) else { return }
        routine.steps.swapAt(index, target)
    }
}

private struct StepRow: View {
    let number: Int
    @Binding var step: RoutineStep
    let isFirst: Bool
    let isLast: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondary)
                .frame(width: 18)
            IconBadge(icon: step.kind.icon, tint: Theme.accent, size: 26)
            Picker("", selection: $step.kind) {
                ForEach(RoutineStep.Kind.allCases) { Text($0.title).tag($0) }
            }
            .themedMenu()
            .frame(width: 150, alignment: .leading)
            TextField("", text: $step.value, prompt: Text(step.kind.placeholder))
                .themedField(width: nil)
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(isFirst)
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(isLast)
                Button { remove() } label: { Image(systemName: "xmark") }
                    .help("Remove step")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
