import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\TaskTemplate.title, order: .forward)]) private var tasks: [TaskTemplate]

    @State private var newTaskTitle: String = ""
    @State private var editTask: TaskTemplate?

    var body: some View {
        NavigationStack {
            List {
                Section("Lista zadań") {
                    if tasks.isEmpty {
                        Text("Brak zadań")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tasks) { task in
                            Button {
                                editTask = task
                                newTaskTitle = task.title
                            } label: {
                                HStack {
                                    Text(task.title)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }

                Section("Dodaj nowe") {
                    HStack {
                        TextField("Nowe zadanie", text: $newTaskTitle)
                            .textInputAutocapitalization(.sentences)
                        Button("Dodaj", action: add)
                            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Ustawienia")
            .toolbar { EditButton() }
            .sheet(item: $editTask) { task in
                NavigationStack {
                    Form {
                        Section("Edytuj zadanie") {
                            TextField("Tytuł", text: Binding(
                                get: { newTaskTitle },
                                set: { newTaskTitle = $0 }
                            ))
                                .textInputAutocapitalization(.sentences)
                        }
                    }
                    .navigationTitle("Edycja")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Anuluj") { editTask = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Zapisz") {
                                if let t = editTask {
                                    t.title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    try? context.save()
                                }
                                editTask = nil
                            }
                            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Divider()
                    Link("by peterwolf.pl", destination: URL(string: "https://peterwolf.pl")!)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                .background(.thinMaterial)
            }
        }
    }

    private func add() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let t = TaskTemplate(title: trimmed)
        context.insert(t)
        try? context.save()
        newTaskTitle = ""
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(tasks[i]) }
        try? context.save()
    }
}

#Preview {
    do {
        let container = try ModelContainer(for: TaskTemplate.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(TaskTemplate(title: "Code Review"))
        context.insert(TaskTemplate(title: "Implementacja feature'a"))
        try context.save()
        return SettingsView().modelContainer(container)
    } catch {
        return SettingsView()
    }
}

