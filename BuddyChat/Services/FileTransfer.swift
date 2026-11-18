import Foundation
import UniformTypeIdentifiers

/// The "here's a file" part of a message.
struct FileOffer: Equatable {
    let tid: String
    let name: String
    let size: Int
    let mime: String

    init?(dict: [String: Any]) {
        guard let tid = dict["tid"] as? String, let name = dict["name"] as? String else { return nil }
        self.tid = tid
        self.name = name
        size = (dict["size"] as? NSNumber)?.intValue ?? 0
        mime = dict["mime"] as? String ?? "application/octet-stream"
    }

    var isImage: Bool { mime.hasPrefix("image/") }
}

/// Live status of a transfer, shared by both people.
struct FileMeta: Equatable {
    enum Status: String { case uploading, ready, accepted, received, declined, canceled, failed }
    let id: String
    let status: Status
    let chunks: Int
    let uploaded: Int

    init(id: String, dict: [String: Any]) {
        self.id = id
        status = Status(rawValue: dict["status"] as? String ?? "") ?? .uploading
        chunks = (dict["chunks"] as? NSNumber)?.intValue ?? 1
        uploaded = (dict["uploaded"] as? NSNumber)?.intValue ?? 0
    }
}

enum FileTransferError: LocalizedError {
    case tooBig, missing
    var errorDescription: String? {
        switch self {
        case .tooBig: return "That file is over 10 MB. BuddyChat can send files up to 10 MB."
        case .missing: return "That file isn't available anymore."
        }
    }
}

extension ChatStore {
    static let maxFileBytes = 10 * 1024 * 1024
    private static let chunkBytes = 192 * 1024

    static var receivedFolder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Received Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func localURL(for offer: FileOffer) -> URL {
        let safe = offer.name.replacingOccurrences(of: "/", with: "-")
        return receivedFolder.appendingPathComponent("\(offer.tid.suffix(6))-\(safe)")
    }

    static func sizeLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Sends a file: posts the offer right away, then uploads it in pieces with progress.
    func sendFile(_ data: Data, name: String, to uid: String) async throws {
        guard data.count <= Self.maxFileBytes else { throw FileTransferError.tooBig }
        let conv = conversationID(myUID, uid)
        let tid = "f" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        let mime = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let count = max(1, Int(ceil(Double(data.count) / Double(Self.chunkBytes))))

        try await db.put("filemeta/\(conv)/\(tid)", [
            "from": myUID, "to": uid, "name": name, "size": data.count, "mime": mime,
            "chunks": count, "uploaded": 0, "status": "uploading", "ts": Database.serverTimestamp,
        ] as [String: Any])
        try await send("📎 \(name) (\(Self.sizeLabel(data.count)))", to: uid, style: TextStyle(),
                       file: ["tid": tid, "name": name, "size": data.count, "mime": mime])
        transferProgress[tid] = 0
        do {
            for i in 0..<count {
                let start = i * Self.chunkBytes
                let piece = data.subdata(in: start..<min(data.count, start + Self.chunkBytes))
                try await db.put("filechunks/\(conv)/\(tid)/\(i)", piece.base64EncodedString())
                try await db.patch("filemeta/\(conv)/\(tid)", ["uploaded": i + 1])
                transferProgress[tid] = Double(i + 1) / Double(count)
            }
            try await db.patch("filemeta/\(conv)/\(tid)", ["status": "ready"])
            Sounds.shared.play(.send)
        } catch {
            try? await db.patch("filemeta/\(conv)/\(tid)", ["status": "failed"])
            transferProgress[tid] = nil
            throw error
        }
        transferProgress[tid] = nil
    }

    /// Downloads the file, saves it, and frees the space on the server.
    func acceptFile(_ offer: FileOffer, from uid: String) async throws -> URL {
        let conv = conversationID(myUID, uid)
        let meta = fileMeta[conv]?[offer.tid]
        let count = meta?.chunks ?? 1
        try? await db.patch("filemeta/\(conv)/\(offer.tid)", ["status": "accepted"])
        transferProgress[offer.tid] = 0
        var data = Data()
        do {
            for i in 0..<count {
                guard let b64 = try await db.get("filechunks/\(conv)/\(offer.tid)/\(i)") as? String,
                      let piece = Data(base64Encoded: b64) else { throw FileTransferError.missing }
                data.append(piece)
                transferProgress[offer.tid] = Double(i + 1) / Double(count)
            }
        } catch {
            transferProgress[offer.tid] = nil
            throw error
        }
        let url = Self.localURL(for: offer)
        try data.write(to: url)
        transferProgress[offer.tid] = nil
        try? await db.patch("filemeta/\(conv)/\(offer.tid)", ["status": "received"])
        try? await db.delete("filechunks/\(conv)/\(offer.tid)")
        Sounds.shared.play(.receive)
        return url
    }

    func declineFile(_ offer: FileOffer, from uid: String) async {
        let conv = conversationID(myUID, uid)
        try? await db.patch("filemeta/\(conv)/\(offer.tid)", ["status": "declined"])
        try? await db.delete("filechunks/\(conv)/\(offer.tid)")
    }

    func cancelFile(_ offer: FileOffer, to uid: String) async {
        let conv = conversationID(myUID, uid)
        try? await db.patch("filemeta/\(conv)/\(offer.tid)", ["status": "canceled"])
        try? await db.delete("filechunks/\(conv)/\(offer.tid)")
    }
}
