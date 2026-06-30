import Foundation
import Combine

public enum OrivoEvent: Hashable, Sendable {
    case serviceStatusChanged(serviceId: String, oldStatus: ServiceStatus, newStatus: ServiceStatus)
    case logReceived(serviceId: String, text: String, isError: Bool)
    case downloadProgress(serviceId: String, progress: Double)
    case message(title: String, body: String, isWarning: Bool)
}

public final class EventBus: @unchecked Sendable {
    public static let shared = EventBus()
    
    private let subject = PassthroughSubject<OrivoEvent, Never>()
    
    private init() {}
    
    public var publisher: AnyPublisher<OrivoEvent, Never> {
        subject.eraseToAnyPublisher()
    }
    
    public func post(_ event: OrivoEvent) {
        if Thread.isMainThread {
            self.subject.send(event)
        } else {
            DispatchQueue.main.async {
                self.subject.send(event)
            }
        }
    }
}
