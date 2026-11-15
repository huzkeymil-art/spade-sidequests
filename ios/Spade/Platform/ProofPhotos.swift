import UIKit

// Photos a child adds to show a parent that a quest was done.
//
// They stay on this iPhone, in Spade's own folder. They only leave it when the
// child chooses "Send the photo" in Allowance, which opens the share sheet.
// (They are not yet part of what iCloud keeps in step between the two phones.)

enum ProofPhotos {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spade/Proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The file for one finished quest. Board keys look like "2026-11-14:fq_abc".
    private static func file(_ key: String) -> URL {
        let safe = String(key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
        return folder.appendingPathComponent("\(safe).jpg")
    }

    /// Keeps a smaller copy of the photo for a finished quest. Returns false if it couldn't be saved.
    @discardableResult
    static func save(_ image: UIImage, for key: String) -> Bool {
        guard let data = shrink(image).jpegData(compressionQuality: 0.72) else { return false }
        do {
            try data.write(to: file(key), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The saved photo's file, if there is one.
    static func url(for key: String) -> URL? {
        let url = file(key)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func image(for key: String) -> UIImage? {
        url(for: key).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    /// Deletes photos for quests that are no longer on record.
    static func keepOnly(_ keys: [String]) {
        let keep = Set(keys.map { file($0).lastPathComponent })
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where !keep.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// At most 1,600 pixels on the long side: plenty to see, and quick to send.
    private static func shrink(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 1600 else { return image }
        let scale = 1600 / longest
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
