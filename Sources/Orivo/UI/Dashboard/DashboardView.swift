import SwiftUI

public struct DashboardView: View {
    @ObservedObject var serviceManager = ServiceManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @Environment(\.openWindow) private var openWindow
    
    @Binding var showSettings: Bool
    @Binding var activeLogServiceId: String? // Unused but kept for layout navigation binds
    
    public init(showSettings: Binding<Bool>, activeLogServiceId: Binding<String?>) {
        self._showSettings = showSettings
        self._activeLogServiceId = activeLogServiceId
    }
    
    private var allServicesHealthy: Bool {
        serviceManager.services.allSatisfy { service in
            serviceManager.statuses[service.id] == .healthy
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if allServicesHealthy {
                // Normal mode
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.tr("app_title"))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(OrivoTheme.textPrimary)
                    
                    Text(loc.tr("everything_ready"))
                        .font(.system(size: 13))
                        .foregroundColor(OrivoTheme.textSecondary)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(OrivoTheme.statusColor(for: .healthy))
                            .frame(width: 6, height: 6)
                        Text(loc.tr("online"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(OrivoTheme.textSecondary)
                    }
                }
                
                Button(action: openLibrary) {
                    Text(loc.tr("open_library"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 24)
                        .background(OrivoTheme.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
                
            } else {
                // Attention Mode (any service is failed/stopped)
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.tr("needs_attention"))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(OrivoTheme.statusColor(for: .failed))
                    
                    Text(loc.tr("services_unavailable"))
                        .font(.system(size: 13))
                        .foregroundColor(OrivoTheme.textSecondary)
                }
                
                Button(action: runFix) {
                    Text(loc.tr("fix"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 24)
                        .background(OrivoTheme.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            
            // Divider
            Divider()
                .background(OrivoTheme.borderDefault)
                .padding(.vertical, 2)
            
            // Background Services List
            VStack(alignment: .leading, spacing: 10) {
                Text(loc.tr("background_services"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                    .padding(.bottom, 2)
                
                ForEach(serviceManager.services) { service in
                    let status = serviceManager.statuses[service.id] ?? .stopped
                    Button(action: { openServiceWebUI(serviceId: service.id) }) {
                        ServiceRowView(name: service.name, status: status)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Divider
            Divider()
                .background(OrivoTheme.borderDefault)
                .padding(.vertical, 2)
            
            // Preferences Button
            Button(action: { showSettings = true }) {
                Text(loc.tr("preferences"))
                    .font(.system(size: 12))
                    .foregroundColor(OrivoTheme.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 20)
        .padding(.top, 48) // Extra padding to clear macOS traffic lights
        .frame(width: 340, height: 400)
        .background(OrivoTheme.bgWindow)
    }
    
    private func openLibrary() {
        openWindow(id: "LibraryWindow")
    }
    
    private func runFix() {
        for service in serviceManager.services {
            let status = serviceManager.statuses[service.id] ?? .stopped
            if status == .failed {
                serviceManager.repairAndStart(serviceId: service.id)
            } else if !status.isRunning {
                serviceManager.start(serviceId: service.id)
            }
        }
    }
    
    private func openServiceWebUI(serviceId: String) {
        let port = serviceId == "torrserver" ? 8090 : 9117
        if let url = URL(string: "http://127.0.0.1:\(port)/") {
            NSWorkspace.shared.open(url)
        }
    }
}
