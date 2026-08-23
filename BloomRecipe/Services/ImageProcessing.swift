import UIKit

enum ImageProcessing {
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1280, quality: CGFloat = 0.72) -> Data? {
        let resized = resize(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
