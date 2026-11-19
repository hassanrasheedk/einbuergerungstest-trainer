import Foundation
import SwiftUI

struct Question: Codable, Identifiable, Hashable, Sendable {
    struct English: Codable, Hashable, Sendable {
        let question: String
        let answers: [String]
        let explanation: String
    }

    let id: String
    let number: Int
    let state: String?
    let question: String
    let answers: [String]
    let correct: Int
    let image: String?
    let credit: String?
    let topic: String
    let en: English

    var isState: Bool { state != nil }

    /// "Aufgabe 70" or "NRW 3"
    var label: String { isState ? "NRW \(number)" : "Aufgabe \(number)" }

    /// Stable ordering: general 1…300, then NRW 1…10.
    var order: Int { isState ? 1000 + number : number }

    #if canImport(UIKit)
    var uiImage: UIImage? {
        guard let image, let url = Bundle.module.url(forResource: image, withExtension: nil) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    #endif
}

enum Catalog {
    static let all: [Question] = {
        struct File: Decodable { let questions: [Question] }
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            assertionFailure("catalog.json missing or invalid")
            return []
        }
        return file.questions.sorted { $0.order < $1.order }
    }()

    static let byID: [String: Question] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static var general: [Question] { all.filter { !$0.isState } }
    static var state: [Question] { all.filter(\.isState) }

    static let topics: [String] = [
        "Grundrechte & Verfassung",
        "Staat & Recht",
        "Wahlen & Parteien",
        "Geschichte & Geografie",
        "Arbeit & Wirtschaft",
        "Familie, Bildung & Religion",
        "Nordrhein-Westfalen",
    ]

    static func symbol(for topic: String) -> String {
        switch topic {
        case "Grundrechte & Verfassung": "book.closed"
        case "Staat & Recht": "building.columns"
        case "Wahlen & Parteien": "checkmark.rectangle"
        case "Geschichte & Geografie": "map"
        case "Arbeit & Wirtschaft": "briefcase"
        case "Familie, Bildung & Religion": "figure.2.and.child.holdinghands"
        default: "mappin.and.ellipse"
        }
    }
}
