import Foundation
import SnagForgeDomain

/// One card of the combined library: an image project or a video recording.
enum LibraryEntry: Identifiable, Sendable {
    case image(ProjectLibraryItem)
    case video(VideoRecordingFiles.Item)
    var id: UUID {
        switch self { case .image(let item): item.id; case .video(let item): item.id }
    }
    var title: String {
        switch self { case .image(let item): item.document.title; case .video(let item): item.document.title }
    }
    var createdAt: Date {
        switch self { case .image(let item): item.document.createdAt; case .video(let item): item.document.createdAt }
    }

    /// Active images and videos, newest capture first or by name. `imageMatches` carries a finished
    /// content search for images; without it titles, tags and collections are matched directly.
    /// Tags and collections only count with Pro, as in the image library.
    static func combined(images: [ProjectLibraryItem], videos: [VideoRecordingFiles.Item], query: String,
                         imageMatches: Set<UUID>? = nil, includesOrganization: Bool, byName: Bool) -> [LibraryEntry] {
        let terms = LibrarySearch.terms(query)
        let matchingImages = images.filter { item in
            guard !terms.isEmpty else { return true }
            if let imageMatches { return imageMatches.contains(item.id) }
            var metadata = item.document
            if !includesOrganization { metadata.tags = []; metadata.collections = [] }
            return LibrarySearch.matches(metadata, query: query)
        }
        let matchingVideos = videos.filter { item in
            item.document.trashedAt == nil && terms.allSatisfy { LibrarySearch.fold(item.document.title).contains($0) }
        }
        return (matchingImages.map(LibraryEntry.image) + matchingVideos.map(LibraryEntry.video)).sorted { left, right in
            if byName {
                let order = left.title.localizedStandardCompare(right.title)
                if order != .orderedSame { return order == .orderedAscending }
            } else if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return left.id.uuidString < right.id.uuidString
        }
    }
}
