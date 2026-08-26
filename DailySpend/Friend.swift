import SwiftData
import SwiftUI

@Model
final class Friend {
    var name: String
    var isFavorite: Bool
    var avatarColorHex: String
    var createdAt: Date
    
    init(name: String, isFavorite: Bool = false, avatarColorHex: String? = nil) {
        self.name = name
        self.isFavorite = isFavorite
        self.avatarColorHex = avatarColorHex ?? Friend.randomColorHex()
        self.createdAt = Date()
    }
    
    @Transient var color: Color {
        Color(hex: avatarColorHex) ?? .gray
    }
    
    static func randomColorHex() -> String {
        let colors = ["#FF5733", "#33FF57", "#3357FF", "#F033FF", "#FF33A8", "#33FFF5", "#FFC300", "#FF8C00", "#8A2BE2", "#00CED1"]
        return colors.randomElement() ?? "#808080"
    }
}

// Helper extension for Hex Color
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
