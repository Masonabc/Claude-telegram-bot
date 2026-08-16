import SwiftUI

enum AppColors {
    // Dark backgrounds
    static let darkBg = Color(hex: 0x0F0F14)
    static let darkSurface = Color(hex: 0x1A1A24)
    static let darkSurfaceVariant = Color(hex: 0x242432)

    // Accent — Claude orange
    static let accentOrange = Color(hex: 0xE8884F)
    static let accentOrangeLight = Color(hex: 0xF5A973)

    // Bot bubble
    static let botBubble = Color(hex: 0x1E1E2E)
    static let botBubbleBorder = Color(hex: 0x2A2A3C)
    static let botText = Color(hex: 0xE4E4ED)

    // User bubble
    static let userBubble = Color(hex: 0xD97706)
    static let userBubbleText = Color.white

    // Session label
    static let sessionLabel = Color(hex: 0x7C7C96)

    // Code blocks
    static let codeBlockBg = Color(hex: 0x12121A)
    static let codeBlockText = Color(hex: 0xD4D4D4)
    static let inlineCodeBg = Color.white.opacity(0.2)

    // Status indicators
    static let connectedGreen = Color(hex: 0x34D399)
    static let reconnectingYellow = Color(hex: 0xFBBF24)
    static let disconnectedRed = Color(hex: 0xF87171)

    // Input bar
    static let inputBg = Color(hex: 0x161622)
    static let inputBorder = Color(hex: 0x2E2E40)
    static let inputBorderFocused = Color(hex: 0xE8884F)
    static let placeholderText = Color(hex: 0x5C5C72)

    // Top bar
    static let topBarBg = Color(hex: 0x13131C)
    static let topBarTitle = Color(hex: 0xE4E4ED)

    // Timestamp
    static let timestampColor = Color(hex: 0x5C5C72)

    // Diff
    static let diffAddedText = Color(hex: 0x34D399)
    static let diffAddedBg = Color(hex: 0x34D399).opacity(0.1)
    static let diffRemovedText = Color(hex: 0xF87171)
    static let diffRemovedBg = Color(hex: 0xF87171).opacity(0.1)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
