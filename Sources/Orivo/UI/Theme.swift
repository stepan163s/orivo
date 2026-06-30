import SwiftUI
import AppKit

public struct OrivoTheme {
    // Pure system colors
    public static let accentColor = Color(nsColor: .controlAccentColor) // System Accent (defaults to #0A84FF)
    public static let systemBlue = Color(red: 0.04, green: 0.52, blue: 1.00) // #0A84FF
    
    public static let textPrimary = Color(nsColor: .labelColor)
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    
    public static let bgWindow = Color(nsColor: .windowBackgroundColor)
    public static let bgControl = Color(nsColor: .controlBackgroundColor)
    public static let borderDefault = Color(nsColor: .separatorColor).opacity(0.4)
    
    // Status colors
    public static func statusColor(for status: ServiceStatus) -> Color {
        switch status {
        case .healthy:
            return Color(red: 0.16, green: 0.80, blue: 0.38) // Apple green
        case .failed:
            return Color(red: 0.92, green: 0.26, blue: 0.21) // Apple red
        default:
            return Color(nsColor: .secondaryLabelColor) // Muted slate gray for active/transitioning
        }
    }
    
    public static func statusText(for status: ServiceStatus) -> String {
        switch status {
        case .healthy: return "Online"
        case .failed: return "Unavailable"
        default: return "Ready"
        }
    }
}

// Clean and slow native animations
public struct AppleTransitionModifier: ViewModifier {
    let active: Bool
    
    public func body(content: Content) -> some View {
        content
            .opacity(active ? 1.0 : 0.0)
            .scaleEffect(active ? 1.0 : 0.99)
            .animation(.easeOut(duration: 0.45), value: active)
    }
}

extension View {
    public func appleTransition(active: Bool) -> some View {
        self.modifier(AppleTransitionModifier(active: active))
    }
}
