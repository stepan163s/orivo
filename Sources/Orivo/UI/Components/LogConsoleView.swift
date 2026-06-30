import SwiftUI
import Combine

public struct LogConsoleView: View {
    let serviceId: String
    @Binding var activeLogServiceId: String?
    
    @State private var logs: [String] = []
    @State private var cancellables = Set<AnyCancellable>()
    
    public init(serviceId: String, activeLogServiceId: Binding<String?>) {
        self.serviceId = serviceId
        self._activeLogServiceId = activeLogServiceId
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Console text area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if logs.isEmpty {
                            Text(LocalizationManager.shared.tr("no_logs"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(OrivoTheme.textTertiary)
                                .padding()
                        } else {
                            ForEach(logs.indices, id: \.self) { index in
                                let log = logs[index]
                                let isError = log.contains("[ERROR]")
                                
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(isError ? Color(red: 0.9, green: 0.3, blue: 0.3) : OrivoTheme.textSecondary)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                    }
                    .padding(10)
                }
                .background(OrivoTheme.bgControl)
                .cornerRadius(6)
                .onChange(of: logs.count) { _ in
                    if let lastIndex = logs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    logs = LogManager.shared.getLogs(for: serviceId)
                    if let lastIndex = logs.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            listenToLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearLogs"))) { notification in
            if let targetId = notification.object as? String, targetId == serviceId {
                clearConsole()
            }
        }
    }
    
    private func listenToLogs() {
        EventBus.shared.publisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case .logReceived(let id, let text, _):
                    if id == self.serviceId {
                        self.logs.append(text)
                        if self.logs.count > 500 {
                            self.logs.removeFirst()
                        }
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func clearConsole() {
        logs.removeAll()
        LogManager.shared.clearMemoryLogs(for: serviceId)
    }
}
