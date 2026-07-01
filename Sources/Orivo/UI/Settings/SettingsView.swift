import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var serviceManager = ServiceManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @Binding var showSettings: Bool
    
    @State private var showingAdvanced = false
    @State private var selectedLogServiceId: String? = nil
    
    public init(showSettings: Binding<Bool>) {
        self._showSettings = showSettings
    }
    
    private var currentTitle: String {
        if let serviceId = selectedLogServiceId {
            let name = serviceManager.services.first(where: { $0.id == serviceId })?.name ?? "Service"
            return "\(name) Log"
        } else if showingAdvanced {
            return loc.tr("advanced")
        } else {
            return loc.tr("settings")
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Unified Navigation Header
            navigationHeader
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            // Content Pane
            ZStack {
                if let serviceId = selectedLogServiceId {
                    LogConsoleView(serviceId: serviceId, activeLogServiceId: $selectedLogServiceId)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .transition(.move(edge: .trailing))
                } else if showingAdvanced {
                    ScrollView(.vertical, showsIndicators: false) {
                        advancedView
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        mainSettingsView
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                    }
                    .transition(.move(edge: .leading))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 340, height: 400)
        .background(OrivoTheme.bgWindow)
        .animation(.easeInOut(duration: 0.25), value: showingAdvanced)
        .animation(.easeInOut(duration: 0.25), value: selectedLogServiceId)
    }
    
    private var navigationHeader: some View {
        ZStack {
            // Centered Screen Title
            Text(currentTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(OrivoTheme.textPrimary)
            
            // Left Navigation (Back button, pushed past macOS traffic lights)
            HStack {
                Button(action: handleBackAction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(OrivoTheme.accentColor)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 70) // Safety space to clear traffic lights horizontally
                
                Spacer()
            }
            
            // Right Action (Clear logs button, visible only in console view)
            if selectedLogServiceId != nil {
                HStack {
                    Spacer()
                    Button(action: triggerClearLogs) {
                        Text(loc.tr("clear"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OrivoTheme.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 24)
                }
            }
        }
        .frame(height: 48)
        .padding(.top, 16) // Pushes header down below the rounded corners
    }
    
    private var mainSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // General settings
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.tr("general"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                Toggle(loc.tr("launch_login"), isOn: Binding(
                    get: { settingsManager.settings.launchAtLogin },
                    set: { settingsManager.updateSetting(\.launchAtLogin, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                Toggle(loc.tr("check_updates"), isOn: .constant(true))
                .toggleStyle(CheckboxToggleStyle())
                .disabled(true)
                
                Toggle(loc.tr("open_library_launch"), isOn: Binding(
                    get: { settingsManager.settings.openLibraryOnLaunch },
                    set: { settingsManager.updateSetting(\.openLibraryOnLaunch, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                Toggle(loc.tr("quit_on_close"), isOn: Binding(
                    get: { settingsManager.settings.quitOnClose },
                    set: { settingsManager.updateSetting(\.quitOnClose, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
            }
            .font(.system(size: 13))
            
            // Language selector
            HStack {
                Text(loc.tr("language"))
                    .foregroundColor(OrivoTheme.textSecondary)
                Spacer()
                Picker("", selection: $loc.currentLanguage) {
                    Text(loc.tr("english")).tag("en")
                    Text(loc.tr("russian")).tag("ru")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 140)
            }
            .font(.system(size: 13))
            .padding(.top, 2)
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            // Components section
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.tr("components"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                ForEach(serviceManager.services) { service in
                    HStack {
                        Button(action: { openServiceWebUI(serviceId: service.id) }) {
                            HStack(spacing: 4) {
                                Text(service.name)
                                    .underline()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(OrivoTheme.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Text(loc.tr("installed"))
                            .foregroundColor(OrivoTheme.textTertiary)
                    }
                    .font(.system(size: 13))
                }
            }
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            // Local Network section
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.tr("local_network"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                HStack {
                    Text(loc.tr("mac_ip"))
                        .foregroundColor(OrivoTheme.textSecondary)
                    Spacer()
                    Text(getLocalIPAddress())
                        .foregroundColor(OrivoTheme.textPrimary)
                        .textSelection(.enabled)
                }
                .font(.system(size: 13))
            }
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            // Advanced navigation button
            Button(action: { showingAdvanced = true }) {
                HStack {
                    Text(loc.tr("advanced_dots"))
                        .font(.system(size: 12))
                        .foregroundColor(OrivoTheme.accentColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(OrivoTheme.textTertiary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var advancedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.tr("system_logs"))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(OrivoTheme.textTertiary)
            
            ForEach(serviceManager.services) { service in
                Button(action: { selectedLogServiceId = service.id }) {
                    HStack {
                        Text("\(service.name) " + loc.tr("log_stream"))
                            .foregroundColor(OrivoTheme.textSecondary)
                        Spacer()
                        Image(systemName: "terminal")
                            .foregroundColor(OrivoTheme.textTertiary)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private func handleBackAction() {
        if selectedLogServiceId != nil {
            selectedLogServiceId = nil
        } else if showingAdvanced {
            showingAdvanced = false
        } else {
            showSettings = false
        }
    }
    
    private func triggerClearLogs() {
        if let serviceId = selectedLogServiceId {
            NotificationCenter.default.post(name: NSNotification.Name("ClearLogs"), object: serviceId)
        }
    }
    
    private func openServiceWebUI(serviceId: String) {
        let port = serviceId == "torrserver" ? 8091 : 9117
        if let url = URL(string: "http://127.0.0.1:\(port)/") {
            NSWorkspace.shared.open(url)
        }
    }

    
    private func getLocalIPAddress() -> String {
        var address: String = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            var addr = ptr.pointee.ifa_addr.pointee
            
            if addr.sa_family == UInt8(AF_INET) {
                if (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
