//
//  FormViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Title row used in place of the search field when a view has nothing to search.
struct PanelHeader: View {
    let title: String
    let icon: String?
    let assetsPath: String
    var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ThawSpacing.row) {
                IconView(value: icon ?? "icon:Terminal", assetsPath: assetsPath, size: 20)
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            ZStack {
                Divider()
                if isLoading {
                    ProgressView().progressViewStyle(.linear).frame(height: 2)
                }
            }
            .frame(height: 2)
        }
    }
}

/// Keeps the launcher panel from hiding while a sheet such as NSOpenPanel has focus.
enum ModalGuard {
    private(set) static var isActive = false

    static func run<T>(_ body: () -> T) -> T {
        isActive = true
        defer {
            isActive = false
            NSApp.windows.first { $0 is LauncherPanel && $0.isVisible }?.makeKey()
        }
        return body()
    }

    static func choosePaths(directories: Bool, multiple: Bool) -> [String] {
        run {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = directories
            panel.canChooseFiles = !directories
            panel.allowsMultipleSelection = multiple
            panel.level = .modalPanel
            return panel.runModal() == .OK ? panel.urls.map(\.path) : []
        }
    }
}

// MARK: Manifest fields (preferences and arguments)

/// One preference or argument from a manifest, edited as text ("true"/"false" for checkboxes).
struct FieldEditor: View {
    let field: FieldSpec
    @Binding var value: String

    var body: some View {
        Group {
            switch field.type {
            case "checkbox":
                Toggle(isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" })) {
                    label
                    if let checkboxLabel = field.label {
                        Text(checkboxLabel)
                    }
                }
            case "dropdown":
                Picker(selection: $value) {
                    ForEach(field.options, id: \.value) { Text($0.title).tag($0.value) }
                } label: { label }
            case "password":
                SecureField(text: $value, prompt: field.placeholder.map { Text($0) }) { label }
            case "file", "directory":
                LabeledContent {
                    HStack {
                        Text(value.isEmpty ? "None" : (value as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(value.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            if let path = ModalGuard.choosePaths(directories: field.type == "directory", multiple: false).first {
                                value = path
                            }
                        }
                    }
                } label: { label }
            default:
                TextField(text: $value, prompt: field.placeholder.map { Text($0) }) { label }
            }
        }
        .help(field.detail ?? "")
    }

    private var label: some View {
        Text(field.required ? "\(field.title) *" : field.title)
    }
}

/// Asks for a command's required preferences or its arguments before it runs.
struct SetupView: View {
    @ObservedObject var model: LauncherModel
    let request: SetupRequest
    @FocusState private var focusedField: String?

    var body: some View {
        let command = request.command
        VStack(spacing: 0) {
            PanelHeader(
                title: request.kind == .preferences ? "Set Up \(command.extensionTitle)" : command.title,
                icon: command.icon,
                assetsPath: command.assetsPath
            )
            Form {
                Section {
                    ForEach(request.fields) { field in
                        FieldEditor(field: field, value: Binding(
                            get: { model.setupValues[field.name] ?? "" },
                            set: { model.setupValues[field.name] = $0 }
                        ))
                        .focused($focusedField, equals: field.name)
                    }
                } footer: {
                    Text(request.kind == .preferences
                        ? "\(command.extensionTitle) needs these before it can run. Change them later in Floe Settings."
                        : "Arguments for \(command.title).")
                        .font(ThawType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Footer(primary: request.kind == .preferences ? "Save and Continue" : "Run Command") {
                if let error = model.setupError {
                    Text(error).foregroundStyle(.red).lineLimit(1)
                } else {
                    Text("Esc to cancel").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { focusedField = request.fields.first { $0.type != "checkbox" }?.name }
    }
}

// MARK: Extension forms

/// Renders a Raycast `<Form>`; values live in the session and go out with onChange and onSubmit.
struct FormBody: View {
    @ObservedObject var session: ExtensionSession
    let focusToken: Int
    @FocusState private var focusedField: Int?

    var body: some View {
        let fields = session.view?.content ?? []
        Form {
            ForEach(fields) { node in
                field(node)
                    .focused($focusedField, equals: node.id)
                if let error = node.string("error") {
                    Text(error).font(ThawType.footnote).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { focusFirst(fields) }
        .onChange(of: focusToken) { focusFirst(fields) }
    }

    private func focusFirst(_ fields: [Node]) {
        focusedField = fields.first { ["Form.TextField", "Form.PasswordField", "Form.TextArea"].contains($0.type) }?.id
    }

    private func text(_ node: Node) -> Binding<String> {
        Binding(get: { session.formValue(node) as? String ?? "" }, set: { session.setFormValue(node, $0) })
    }

    private func title(_ node: Node) -> String {
        node.string("title") ?? ""
    }

    @ViewBuilder
    private func field(_ node: Node) -> some View {
        switch node.type {
        case "Form.TextField":
            TextField(title(node), text: text(node), prompt: node.string("placeholder").map { Text($0) })
                .help(node.string("info") ?? "")
        case "Form.PasswordField":
            SecureField(title(node), text: text(node), prompt: node.string("placeholder").map { Text($0) })
        case "Form.TextArea":
            LabeledContent(title(node)) {
                TextEditor(text: text(node))
                    .font(ThawType.body)
                    .frame(minHeight: 80, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 6))
            }
        case "Form.Checkbox":
            Toggle(isOn: Binding(get: { session.formValue(node) as? Bool ?? false }, set: { session.setFormValue(node, $0) })) {
                Text(title(node))
                if let label = node.string("label") {
                    Text(label)
                }
            }
        case "Form.DatePicker":
            DatePicker(
                title(node),
                selection: date(node),
                displayedComponents: node.props["type"] as? String == "date" ? [.date] : [.date, .hourAndMinute]
            )
        case "Form.Dropdown":
            let items = node.descendants(ofType: "Dropdown.Item")
            Picker(title(node), selection: text(node)) {
                ForEach(items) { item in Text(item.string("title") ?? "").tag(item.props["value"] as? String ?? "") }
            }
        case "Form.TagPicker":
            tagPicker(node)
        case "Form.FilePicker":
            filePicker(node)
        case "Form.Description":
            LabeledContent(title(node)) { Text(node.string("text") ?? "").foregroundStyle(.secondary) }
        case "Form.Separator":
            Divider()
        default:
            EmptyView()
        }
    }

    private func date(_ node: Node) -> Binding<Date> {
        Binding(
            get: {
                (session.formValue(node) as? String).flatMap { try? Date($0, strategy: .iso8601) } ?? Date()
            },
            set: { session.setFormValue(node, $0.formatted(.iso8601)) }
        )
    }

    private func tagPicker(_ node: Node) -> some View {
        let items = node.descendants(ofType: "Form.TagPicker.Item")
        let selected = session.formValue(node) as? [String] ?? []
        let titles = items.filter { selected.contains($0.props["value"] as? String ?? "") }.compactMap { $0.string("title") }
        return LabeledContent(title(node)) {
            Menu(titles.isEmpty ? (node.string("placeholder") ?? "None") : titles.joined(separator: ", ")) {
                ForEach(items) { item in
                    let value = item.props["value"] as? String ?? ""
                    Toggle(item.string("title") ?? value, isOn: Binding(
                        get: { selected.contains(value) },
                        set: { isOn in session.setFormValue(node, isOn ? selected + [value] : selected.filter { $0 != value }) }
                    ))
                }
            }
            .fixedSize()
        }
    }

    private func filePicker(_ node: Node) -> some View {
        let paths = session.formValue(node) as? [String] ?? []
        return LabeledContent(title(node)) {
            HStack {
                Text(paths.isEmpty ? "None" : paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                    .foregroundStyle(paths.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Button("Choose…") {
                    let chosen = ModalGuard.choosePaths(
                        directories: node.bool("canChooseDirectories") && !node.bool("canChooseFiles"),
                        multiple: node.props["allowMultipleSelection"] as? Bool ?? true
                    )
                    if !chosen.isEmpty {
                        session.setFormValue(node, chosen)
                    }
                }
            }
        }
    }
}
