#if canImport(GrumpySqueezeCore)
import GrumpySqueezeCore
#endif
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HSplitView {
                VStack(spacing: 16) {
                    dropZone
                    itemList
                }
                .padding(24)
                .frame(minWidth: 580)
                settings
                    .frame(width: 320)
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Grumpy Squeeze", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Grumpy Squeeze")
                    .font(.title2.weight(.bold))
                Text("Local image compression. Nothing leaves your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityIdentifier("errorMessage")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var dropZone: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(forestGreen.opacity(isTargeted ? 0.18 : 0.10))
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(forestGreen)
            }
            .frame(width: 54, height: 54)

            VStack(spacing: 4) {
                Text(isTargeted ? "Release to add" : "Drop images or folders")
                    .font(.headline)
                Text("Folders are scanned recursively")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Choose files or folders…") { model.chooseInputs() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(forestGreen)
                .accessibilityIdentifier("chooseInputsButton")
        }
        .frame(maxWidth: .infinity, minHeight: 174)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? sage.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
                .strokeBorder(
                    forestGreen.opacity(isTargeted ? 0.9 : 0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.25, dash: [7, 5])
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            model.replaceInputs(with: urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .accessibilityIdentifier("dropZone")
    }

    @ViewBuilder
    private var itemList: some View {
        if model.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                VStack(spacing: 4) {
                    Text("Your queue is empty")
                        .font(.headline)
                    Text("Added images will appear here, ready to compress.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.07))
            }
            .accessibilityIdentifier("itemsTable")
        } else {
            Table(model.items) {
                TableColumn("Image") { item in
                    HStack(spacing: 10) {
                        Image(systemName: "photo")
                            .foregroundStyle(forestGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.sourceURL.lastPathComponent)
                                .fontWeight(.medium)
                            Text(item.relativePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Format") { item in
                    Text("\(item.format.rawValue.uppercased()) → \(finalFormat(for: item).rawValue.uppercased())")
                }.width(110)
                TableColumn("Before") { item in
                    Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                }.width(70)
                TableColumn("After") { item in
                    Text(finalSize(for: item))
                        .foregroundStyle(model.results[item.id] == nil ? .secondary : .primary)
                }.width(70)
                TableColumn("Status") { item in
                    Label(status(for: item).rawValue, systemImage: statusSymbol(for: item))
                        .foregroundStyle(statusColor(for: item))
                        .help(model.results[item.id]?.error ?? status(for: item).rawValue)
                }.width(110)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.07))
                    .allowsHitTesting(false)
            }
            .accessibilityIdentifier("itemsTable")
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsSection("Compression", systemImage: "slider.horizontal.3") {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Quality")
                            Spacer()
                            Text("\(Int(model.quality * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.quality, in: 0.1...1, step: 0.05)
                            .tint(forestGreen)
                            .accessibilityIdentifier("qualitySlider")
                        Divider()
                        Picker("Format", selection: $model.outputFormat) {
                            Text("Keep original").tag(OutputFormat.original)
                            ForEach(OutputFormat.allCases.filter { $0 != .original }, id: \.self) {
                                Text($0.rawValue.uppercased()).tag($0)
                            }
                        }
                        .accessibilityIdentifier("formatPicker")
                        Divider()
                        Toggle("Preserve embedded metadata", isOn: $model.preserveMetadata)
                            .tint(forestGreen)
                            .accessibilityIdentifier("preserveMetadataToggle")
                        Toggle("Export metadata as JSON", isOn: $model.exportJSON)
                            .tint(forestGreen)
                            .accessibilityIdentifier("exportJSONToggle")
                    }
                }

                settingsSection("Resolution", systemImage: "aspectratio") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Resize", selection: $model.resolutionMode) {
                            ForEach(ResolutionMode.allCases, id: \.self) { mode in
                                Text(resolutionLabel(mode)).tag(mode)
                            }
                        }
                        .accessibilityIdentifier("resolutionPicker")

                        if usesCustomWidth {
                            resolutionField("Width", value: $model.resolutionWidth)
                                .accessibilityIdentifier("resolutionWidthField")
                        }
                        if usesCustomHeight {
                            resolutionField("Height", value: $model.resolutionHeight)
                                .accessibilityIdentifier("resolutionHeightField")
                        }
                        if model.resolutionMode != .original {
                            Label(resolutionHelp, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                settingsSection("Destination", systemImage: "folder") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            model.destinationURL?.path(percentEncoded: false) ?? "Original locations",
                            systemImage: model.destinationURL == nil ? "arrow.uturn.backward" : "folder.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                        HStack {
                            Button("Choose…") { model.chooseDestination() }
                                .accessibilityIdentifier("chooseDestinationButton")
                            if model.destinationURL != nil {
                                Button("Use originals") { model.clearDestination() }
                            }
                        }
                    }
                }

                settingsSection("Batch", systemImage: "chart.bar") {
                    VStack(spacing: 11) {
                        summaryRow("Files", "\(model.items.count)")
                        Divider()
                        summaryRow("Completed", "\(model.summary.completed)")
                        summaryRow("No improvement", "\(model.summary.noImprovement)")
                        summaryRow("Errors", "\(model.summary.errors)")
                        summaryRow("Saved", ByteCountFormatter.string(fromByteCount: model.summary.bytesSaved, countStyle: .file))
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.primary.opacity(0.06))
                }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isProcessing {
                ProgressView(value: Double(model.results.count), total: Double(max(model.items.count, 1)))
                    .frame(width: 180)
                    .accessibilityIdentifier("batchProgress")
                Text("\(model.results.count) of \(model.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Label(
                    model.items.isEmpty ? "Ready for images" : "\(model.items.count) item\(model.items.count == 1 ? "" : "s") ready",
                    systemImage: model.items.isEmpty ? "checkmark.circle" : "photo.stack"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Text(model.isProcessing ? "processing" : "idle-\(model.results.count)")
                .font(.caption2)
                .foregroundStyle(.clear)
                .accessibilityLabel(model.isProcessing ? "processing" : "idle-\(model.results.count)")
                .accessibilityIdentifier("batchState")
                .id("batch-\(model.isProcessing)-\(model.results.count)")
            Spacer()
            Button("Show in Finder") { model.revealResults() }
                .disabled(model.results.isEmpty)
                .accessibilityIdentifier("showInFinderButton")
            Button("Cancel") { model.cancel() }
                .disabled(!model.isProcessing)
                .accessibilityIdentifier("cancelButton")
            Button("Compress") { model.compress() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(forestGreen)
                .disabled(model.items.isEmpty || model.isProcessing)
                .keyboardShortcut(.return)
                .accessibilityIdentifier("compressButton")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func resolutionField(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("px")
                .foregroundStyle(.secondary)
        }
    }

    private func resolutionLabel(_ mode: ResolutionMode) -> String {
        switch mode {
        case .original: "Original size"
        case .percent90: "90%"
        case .percent75: "75%"
        case .half: "Half · 50%"
        case .third: "Third · 33%"
        case .quarter: "Quarter · 25%"
        case .customWidth: "Specific width"
        case .customHeight: "Specific height"
        case .fit: "Fit within"
        case .exact: "Exact size"
        }
    }

    private var usesCustomWidth: Bool {
        [.customWidth, .fit, .exact].contains(model.resolutionMode)
    }

    private var usesCustomHeight: Bool {
        [.customHeight, .fit, .exact].contains(model.resolutionMode)
    }

    private var resolutionHelp: String {
        switch model.resolutionMode {
        case .customWidth: "Height is calculated automatically. Images are never enlarged."
        case .customHeight: "Width is calculated automatically. Images are never enlarged."
        case .fit: "Fits inside this box while preserving aspect ratio. Images are never enlarged."
        case .exact: "Uses the exact width and height and may change the aspect ratio. Images are never enlarged."
        default: "Reduces both dimensions while preserving aspect ratio."
        }
    }

    private func status(for item: DiscoveredImage) -> ItemStatus {
        model.results[item.id]?.status ?? (model.isProcessing ? .processing : .pending)
    }

    private func finalFormat(for item: DiscoveredImage) -> ImageFormat {
        model.outputFormat.imageFormat ?? item.format
    }

    private func finalSize(for item: DiscoveredImage) -> String {
        guard let result = model.results[item.id],
              result.status == .completed || result.status == .noImprovement else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: result.finalBytes, countStyle: .file)
    }

    private func statusSymbol(for item: DiscoveredImage) -> String {
        switch status(for: item) {
        case .pending: "clock"
        case .processing: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .noImprovement: "equal.circle"
        case .cancelled: "xmark.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for item: DiscoveredImage) -> Color {
        switch status(for: item) {
        case .completed: forestGreen
        case .error: .red
        default: .secondary
        }
    }

    private var forestGreen: Color {
        Color("ForestGreen", bundle: resourceBundle)
    }

    private var sage: Color {
        Color("Sage", bundle: resourceBundle)
    }

    private var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}
