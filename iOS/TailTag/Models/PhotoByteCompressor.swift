import UIKit

enum PhotoByteCompressor {
    /// Shrinks a photo for storage. The original bytes are returned when decoding or encoding fails,
    /// and an empty result is never substituted for non-empty input.
    nonisolated static func compress(_ data: Data, maxSizeKB: Int = 800) -> Data {
        guard !data.isEmpty, let image = UIImage(data: data) else { return data }

        var compression: CGFloat = 0.8
        var imageData = image.jpegData(compressionQuality: compression)
        let maxBytes = maxSizeKB * 1024

        while let current = imageData, current.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }

        if let current = imageData, current.count > maxBytes, image.size.width > 0, image.size.height > 0 {
            let scale = sqrt(Double(maxBytes) / Double(current.count))
            let newSize = CGSize(
                width: max(image.size.width * scale, 1),
                height: max(image.size.height * scale, 1)
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resizedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            imageData = resizedImage.jpegData(compressionQuality: 0.7)
        }

        guard let compressed = imageData, !compressed.isEmpty else { return data }
        return compressed
    }
}
