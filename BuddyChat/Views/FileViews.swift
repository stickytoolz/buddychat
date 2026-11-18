import SwiftUI
import QuickLook

/// The box shown in a conversation for a file transfer.
struct FileCard: View {
    let offer: FileOffer
    let message: ChatMessage
    let buddyID: String
    @EnvironmentObject var store: ChatStore
    @State private var savedURL: URL?
    @State private var preview: URL?
    @State private var error: String?

    private var mine: Bool { message.from == store.myUID }
    private var meta: FileMeta? { store.fileMeta[conversationID(store.myUID, buddyID)]?[offer.tid] }
    private var progress: Double? { store.transferProgress[offer.tid] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 24)).foregroundStyle(Retro.them)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.name).font(Retro.titleFont(13)).foregroundStyle(Retro.ink).lineLimit(2)
                    Text(ChatStore.sizeLabel(offer.size)).font(Retro.body(11)).foregroundStyle(Retro.dark)
                }
            }
            if let url = savedURL, offer.isImage, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200)
                    .onTapGesture { preview = url }
            }
            if let progress {
                RetroProgress(value: progress)
                Text(mine ? "Sending… \(Int(progress * 100))%" : "Receiving… \(Int(progress * 100))%")
                    .font(Retro.body(11)).foregroundStyle(Retro.ink)
            } else {
                statusArea
            }
            if let error { Text(error).font(Retro.body(11)).foregroundStyle(.red) }
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Retro.face)
        .bevel()
        .onAppear { checkSaved() }
        .quickLookPreview($preview)
    }

    private var icon: String {
        if offer.isImage { return "photo" }
        if offer.mime.hasPrefix("audio/") { return "music.note" }
        if offer.mime.hasPrefix("video/") { return "film" }
        if offer.mime.contains("pdf") { return "doc.richtext" }
        return "doc"
    }

    @ViewBuilder
    private var statusArea: some View {
        let status = meta?.status
        if let url = savedURL {
            HStack {
                Button("Open") { preview = url }.buttonStyle(RetroButtonStyle(bold: true))
                ShareLink(item: url) {
                    Text("Save / Share").font(Retro.body(13)).foregroundStyle(Retro.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Retro.face).bevel()
                }
            }
        } else if mine {
            switch status {
            case .uploading?:
                let pct = meta.map { Int(Double($0.uploaded) / Double(max(1, $0.chunks)) * 100) } ?? 0
                Text("Sending… \(pct)%").font(Retro.body(11)).foregroundStyle(Retro.ink)
            case .ready?:
                HStack {
                    Text("Waiting for \(store.name(buddyID)) to accept").font(Retro.body(11)).foregroundStyle(Retro.dark)
                    Spacer()
                    Button("Cancel") { Task { await store.cancelFile(offer, to: buddyID) } }.buttonStyle(RetroButtonStyle())
                }
            case .accepted?: Text("\(store.name(buddyID)) is receiving it…").font(Retro.body(11)).foregroundStyle(Retro.ink)
            case .received?: Label("Received by \(store.name(buddyID))", systemImage: "checkmark.circle.fill")
                    .font(Retro.body(11)).foregroundStyle(.green)
            case .declined?: Text("\(store.name(buddyID)) declined the file.").font(Retro.body(11)).foregroundStyle(.red)
            case .canceled?: Text("You canceled this transfer.").font(Retro.body(11)).foregroundStyle(Retro.dark)
            case .failed?: Text("Sending failed.").font(Retro.body(11)).foregroundStyle(.red)
            case nil: Text("…").font(Retro.body(11))
            }
        } else {
            switch status {
            case .uploading?:
                let pct = meta.map { Int(Double($0.uploaded) / Double(max(1, $0.chunks)) * 100) } ?? 0
                Text("\(store.name(buddyID)) is sending… \(pct)%").font(Retro.body(11)).foregroundStyle(Retro.ink)
            case .ready?, .accepted?:
                Text("\(store.name(buddyID)) wants to send you this file.").font(Retro.body(11)).foregroundStyle(Retro.ink)
                HStack {
                    Button("Decline") { Task { await store.declineFile(offer, from: buddyID) } }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Accept") { accept() }.buttonStyle(RetroButtonStyle(bold: true))
                }
            case .received?: Text("Received on another device.").font(Retro.body(11)).foregroundStyle(Retro.dark)
            case .declined?: Text("You declined this file.").font(Retro.body(11)).foregroundStyle(Retro.dark)
            case .canceled?: Text("\(store.name(buddyID)) canceled this transfer.").font(Retro.body(11)).foregroundStyle(Retro.dark)
            case .failed?: Text("The transfer didn't finish.").font(Retro.body(11)).foregroundStyle(.red)
            case nil: Text("This file is no longer available.").font(Retro.body(11)).foregroundStyle(Retro.dark)
            }
        }
    }

    private func checkSaved() {
        let url = ChatStore.localURL(for: offer)
        if FileManager.default.fileExists(atPath: url.path) { savedURL = url }
    }

    private func accept() {
        error = nil
        Task {
            do { savedURL = try await store.acceptFile(offer, from: buddyID) }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// Chunky block-style progress bar.
struct RetroProgress: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            let blocks = max(1, Int(g.size.width / 11))
            let filled = Int(Double(blocks) * min(1, max(0, value)))
            HStack(spacing: 2) {
                ForEach(0..<blocks, id: \.self) { i in
                    Rectangle().fill(i < filled ? Retro.them : Color.clear).frame(width: 9)
                }
            }
            .padding(2)
        }
        .frame(height: 18)
        .background(Retro.field)
        .bevel(sunken: true)
    }
}
