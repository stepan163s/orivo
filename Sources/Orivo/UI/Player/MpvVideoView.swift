import SwiftUI
import AppKit

public class MpvVideoView: NSView {
    private var player: MpvPlayer?
    
    public func setPlayer(_ player: MpvPlayer) {
        self.player = player
        player.attach(to: self)
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let player = player {
            player.attach(to: self)
        }
    }
}

public struct MpvVideoViewRepresentable: NSViewRepresentable {
    let player: MpvPlayer
    
    public func makeNSView(context: Context) -> MpvVideoView {
        let view = MpvVideoView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.setPlayer(player)
        return view
    }
    
    public func updateNSView(_ nsView: MpvVideoView, context: Context) {}
}
