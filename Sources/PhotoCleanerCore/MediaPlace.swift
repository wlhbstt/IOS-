import Foundation

public struct MediaPlace: Identifiable, Equatable, Sendable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let ids: [String]

    public static func group(_ records: [MediaRecord]) -> [MediaPlace] {
        struct Grid: Hashable {
            let latitude: Int
            let longitude: Int
        }
        var groups: [Grid: [MediaRecord]] = [:]
        for record in records {
            if Task.isCancelled { return [] }
            guard let latitude = record.latitude, let longitude = record.longitude,
                  latitude.isFinite, longitude.isFinite,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { continue }
            // Clamp the north/east boundary into the final 0.1-degree cell.
            let grid = Grid(latitude: min(899, Int(floor(latitude * 10))),
                            longitude: min(1799, Int(floor(longitude * 10))))
            groups[grid, default: []].append(record)
        }
        return groups.map { grid, records in
            MediaPlace(id: "\(grid.latitude):\(grid.longitude)",
                latitude: (Double(grid.latitude) + 0.5) / 10,
                longitude: (Double(grid.longitude) + 0.5) / 10,
                ids: MediaSorter.sorted(records, by: .newest).map(\.id))
        }.sorted {
            if $0.ids.count != $1.ids.count { return $0.ids.count > $1.ids.count }
            if $0.latitude != $1.latitude { return $0.latitude < $1.latitude }
            return $0.longitude < $1.longitude
        }
    }
}
