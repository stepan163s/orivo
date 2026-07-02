import SwiftUI
import AppKit

public class MpvVideoView: NSView {
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
}

public struct MpvVideoViewRepresentable: NSViewRepresentable {
    let player: MpvPlayer
    
    public func makeNSView(context: Context) -> MpvVideoView {
        let view = MpvVideoView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    
    public func updateNSView(_ nsView: MpvVideoView, context: Context) {}
}
