// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Drop files, pick a target format, convert. Everything runs on this Mac.
struct PanelConverterView: View {
    @ObservedObject private var service = ConverterService.shared
    @State private var urls: [URL] = []
    @State private var selectedID: String?
    @State private var options = ConvertOptions()
    @State private var showAdvanced = false
    @State private var dropTargeted = false
    @State private var skipped = 0

    var onClose: () -> Void

    /// `initialURLs` carries files handed over by the Finder right-click action.
    init(initialURLs: [URL] = [], onClose: @escaping () -> Void) {
        self.onClose = onClose
        let supported = initialURLs.filter { $0.isFileURL && ConvertKind.kind(of: $0) != nil }
        _urls = State(initialValue: supported)
        _skipped = State(initialValue: initialURLs.count - supported.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if service.jobs.isEmpty {
                setup
            } else {
                progress
            }
        }
        .dropDestination(for: URL.self) { dropped, _ in
            guard !service.isRunning else { return false }
            return add(dropped)
        } isTargeted: { dropTargeted = $0 }
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private func close() {
        if service.isRunning { service.stop() }
        service.reset()
        onClose()
    }

    // MARK: Setup

    private var targets: [ConvertFormat] {
        _ = service.toolRevision
        return ConvertFormats.commonTargets(for: urls, libreOfficeAvailable: service.libreOfficeAvailable)
    }

    private var selectedFormat: ConvertFormat? {
        targets.first { $0.id == selectedID } ?? targets.first
    }

    private var setup: some View {
        VStack(spacing: 10) {
            if urls.isEmpty {
                dropZone
                Button(action: choose) {
                    Label("Choose Files…", systemImage: "plus.circle")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text("Audio, video, images, documents, PDFs and Excel spreadsheets.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                fileSummary
                formatPicker
                advanced
                actions
            }
        }
        .panelCard()
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(dropTargeted ? Color.chikitAccent : Color.secondary.opacity(0.35))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dropTargeted ? Color.chikitAccent.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .frame(height: 108)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(dropTargeted ? Color.chikitAccent : .secondary)
                    Text("Drop files to convert")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Results are saved next to the originals")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            )
    }

    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: urls.count == 1
                      ? (ConvertKind.kind(of: urls[0])?.symbolName ?? "doc")
                      : "doc.on.doc")
                    .foregroundStyle(Color.chikitAccent)
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Clear") { urls = []; selectedID = nil; skipped = 0 }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            if skipped > 0 {
                Text("\(skipped) unsupported file\(skipped == 1 ? "" : "s") skipped")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var formatPicker: some View {
        if targets.isEmpty {
            Text("These files have no format in common. Convert them separately.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text("Convert to")
                    .font(.system(size: 11.5))
                Spacer()
                Picker("", selection: Binding(get: { selectedFormat?.id ?? "" },
                                              set: { selectedID = $0 })) {
                    ForEach(targets) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
            }
            if let format = selectedFormat, let hint = ConverterService.missingToolHint(for: format) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(hint)
                        .font(.system(size: 10.5))
                        .textSelection(.enabled)
                    Spacer()
                    Button("Recheck") { service.refreshTools() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var advanced: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Quality").font(.system(size: 11))
                    Spacer()
                    Picker("", selection: $options.quality) {
                        ForEach(ConvertQuality.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                HStack {
                    Text("Paper size (PDF)").font(.system(size: 11))
                    Spacer()
                    Picker("", selection: $options.paper) {
                        ForEach(ConvertPaper.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                Toggle("Move originals to the Trash", isOn: $options.trashOriginals)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)
            }
            .padding(.top, 6)
        } label: {
            Text("Advanced").font(.system(size: 11, weight: .medium))
        }
    }

    private var actions: some View {
        HStack {
            Button("Add Files…", action: choose)
                .controlSize(.small)
            Spacer()
            Button {
                guard let format = selectedFormat else { return }
                service.convert(urls, to: format, options: options)
            } label: {
                Text("Convert").font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.chikitAccent)
            .controlSize(.small)
            .disabled(selectedFormat == nil
                      || (selectedFormat.flatMap(ConverterService.missingToolHint) != nil))
        }
    }

    // MARK: Progress

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            let total = service.jobs.count
            let finished = service.jobs.filter {
                if case .done = $0.status { return true }
                if case .failed = $0.status { return true }
                return false
            }.count
            if service.isRunning {
                ProgressView(value: Double(finished), total: Double(total))
                Text("Converting \(min(finished + 1, total)) of \(total)…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            ForEach(service.jobs) { job in
                jobRow(job)
            }
            if service.usedFallbackFolder {
                Text("The original folder is read-only, so results were saved to Downloads.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if service.isRunning {
                    Spacer()
                    Button("Stop") { service.stop() }
                        .controlSize(.small)
                } else {
                    Button("Show in Finder", action: reveal)
                        .controlSize(.small)
                        .disabled(!hasOutput)
                    Spacer()
                    Button("Convert More") {
                        service.reset()
                        urls = []
                        selectedID = nil
                        skipped = 0
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.chikitAccent)
                    .controlSize(.small)
                }
            }
        }
        .panelCard()
    }

    private func jobRow(_ job: ConverterService.Job) -> some View {
        HStack(alignment: .top, spacing: 6) {
            switch job.status {
            case .pending:
                Image(systemName: "circle").foregroundStyle(.tertiary)
            case .running:
                ProgressView().controlSize(.small).frame(width: 14, height: 14)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(job.url.lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch job.status {
                case .done(let output):
                    Text("→ \(output.lastPathComponent)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                case .failed(let message):
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                default:
                    EmptyView()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var hasOutput: Bool {
        service.jobs.contains { if case .done = $0.status { return true } else { return false } }
    }

    private func reveal() {
        let outputs = service.jobs.compactMap { job -> URL? in
            if case .done(let url) = job.status { return url }
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }

    // MARK: Files

    @discardableResult
    private func add(_ new: [URL]) -> Bool {
        var accepted = 0
        for url in new where url.isFileURL {
            guard ConvertKind.kind(of: url) != nil else { skipped += 1; continue }
            if !urls.contains(url) { urls.append(url) }
            accepted += 1
        }
        selectedID = nil
        return accepted > 0
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        PanelInteractionState.shared.viewKeepsPopoverOpen = true
        panel.begin { response in
            if response == .OK { add(panel.urls) }
        }
    }
}
