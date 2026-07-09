import SwiftUI
import Combine

public struct OnboardingView: View {
    @Binding var onboardingCompleted: Bool
    @Environment(\.openWindow) private var openWindow
    @StateObject private var loc = LocalizationManager.shared
    
    @State private var currentStep = 1 // 1: Welcome, 2: Installing, 3: Done
    @State private var statusText = ""
    
    @State private var torrProgress: Double = 0.0
    @State private var jackettProgress: Double = 0.0
    @State private var cancellables = Set<AnyCancellable>()
    
    public init(onboardingCompleted: Binding<Bool>) {
        self._onboardingCompleted = onboardingCompleted
    }
    
    private var averageProgress: Double {
        (torrProgress + jackettProgress) / 2.0
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                if currentStep == 1 {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(loc.tr("welcome_title"))
                            .font(.system(size: 28, weight: .medium, design: .default))
                            .foregroundColor(OrivoTheme.textPrimary)
                        
                        Text(loc.tr("welcome_subtitle"))
                            .font(.system(size: 14))
                            .foregroundColor(OrivoTheme.textSecondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    
                } else if currentStep == 2 {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(statusText.isEmpty ? loc.tr("downloading") : statusText)
                            .font(.system(size: 14))
                            .foregroundColor(OrivoTheme.textPrimary)
                        
                        ProgressView(value: averageProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .tint(OrivoTheme.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    
                } else if currentStep == 3 {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(loc.tr("done_title"))
                            .font(.system(size: 28, weight: .medium, design: .default))
                            .foregroundColor(OrivoTheme.textPrimary)
                        
                        Text(loc.tr("done_subtitle"))
                            .font(.system(size: 14))
                            .foregroundColor(OrivoTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            HStack {
                Spacer()
                
                if currentStep == 1 {
                    Button(action: startInstallation) {
                        HStack(spacing: 6) {
                            Text(loc.tr("continue"))
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(OrivoTheme.accentColor)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if currentStep == 3 {
                    Button(action: finishOnboarding) {
                        Text(loc.tr("open_library"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(OrivoTheme.accentColor)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 500, height: 420)
        .background(OrivoTheme.bgWindow)
        .onAppear {
            statusText = loc.tr("downloading")
            listenToEvents()
        }
    }
    
    private func listenToEvents() {
        EventBus.shared.publisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case .downloadProgress(let serviceId, let progress):
                    if serviceId == "torrserver" {
                        self.torrProgress = progress
                    } else if serviceId == "jackett" {
                        self.jackettProgress = progress
                    }
                    
                    if self.averageProgress >= 1.0 {
                        self.statusText = loc.tr("installing")
                    } else {
                        self.statusText = loc.tr("downloading")
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func startInstallation() {
        withAnimation(.easeOut(duration: 0.4)) {
            currentStep = 2
        }
        
        let updateManager = UpdateManager.shared
        guard let torrRelease = updateManager.getOnboardingRelease(for: "torrserver"),
              let jackettRelease = updateManager.getOnboardingRelease(for: "jackett") else {
            statusText = loc.tr("error_config")
            return
        }
        
        let group = DispatchGroup()
        
        group.enter()
        updateManager.startInstallation(serviceId: "torrserver", urlString: torrRelease.url, sha256: torrRelease.sha256) { success in
            DispatchQueue.main.async {
                self.torrProgress = success ? 1.0 : 0.0
                group.leave()
            }
        }
        
        group.enter()
        updateManager.startInstallation(serviceId: "jackett", urlString: jackettRelease.url, sha256: jackettRelease.sha256) { success in
            DispatchQueue.main.async {
                self.jackettProgress = success ? 1.0 : 0.0
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if self.torrProgress == 1.0 && self.jackettProgress == 1.0 {
                self.statusText = loc.tr("starting_services")
                
                ServiceManager.shared.loadServices()
                ServiceManager.shared.start(serviceId: "torrserver")
                ServiceManager.shared.start(serviceId: "jackett")
                
                Watchdog.shared.startMonitoring()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        self.currentStep = 3
                    }
                }
            } else {
                withAnimation {
                    self.currentStep = 1
                }
            }
        }
    }
    
    private func finishOnboarding() {
        withAnimation(.easeOut(duration: 0.45)) {
            onboardingCompleted = true
        }
        openLibrary()
    }
    
    private func openLibrary() {
        openWindow(id: "LibraryWindow")
    }
}
