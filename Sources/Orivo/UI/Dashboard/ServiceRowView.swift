import SwiftUI

public struct ServiceRowView: View {
    let name: String
    let status: ServiceStatus
    
    public init(name: String, status: ServiceStatus) {
        self.name = name
        self.status = status
    }
    
    public var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 13, design: .default))
                    .foregroundColor(OrivoTheme.textSecondary)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 9))
                    .foregroundColor(OrivoTheme.textTertiary)
            }
            Spacer()
            Circle()
                .fill(OrivoTheme.statusColor(for: status))
                .frame(width: 6, height: 6)
        }
    }
}
