import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

/// Controls the TV volume with the iPhone's side buttons while the app is open.
///
/// iOS has no public API for this. So we watch the phone's volume and turn every change
/// into VOL+/VOL−. An invisible `MPVolumeView` suppresses the system volume HUD and lets us
/// reset the value to the middle, so you can keep pressing in the same direction. On stop
/// the phone's volume returns to its original value.
final class VolumeButtonObserver {
    var onPress: ((_ up: Bool) -> Void)?
    fileprivate weak var volumeView: MPVolumeView?

    private var subscription: AnyCancellable?
    private var lastVolume: Float = 0
    private var originalVolume: Float?
    /// Value we set ourselves. Its change doesn't count as a button press.
    private var ignoredValue: Float?

    func start() {
        guard subscription == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // .ambient doesn't interrupt music currently playing on the phone.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        let volume = session.outputVolume
        originalVolume = volume
        lastVolume = volume
        subscription = session.publisher(for: \.outputVolume)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] new in self?.volumeChanged(to: new) }
        // At the edge of the range another press in the same direction would have no effect.
        if volume < 0.1 || volume > 0.9 { setSystemVolume(0.5) }
    }

    func stop() {
        guard subscription != nil else { return }
        subscription = nil
        if let originalVolume { setSystemVolume(originalVolume) }
        originalVolume = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func volumeChanged(to new: Float) {
        let old = lastVolume
        lastVolume = new
        if let ignoredValue, abs(new - ignoredValue) < 0.001 {
            self.ignoredValue = nil
            return
        }
        guard new != old else { return }
        onPress?(new > old)
        if new < 0.1 || new > 0.9 { setSystemVolume(0.5) }
    }

    private func setSystemVolume(_ value: Float) {
        guard let slider = volumeView?.subviews.lazy.compactMap({ $0 as? UISlider }).first else { return }
        ignoredValue = value
        slider.value = value
    }
}

/// A nearly invisible system `MPVolumeView`. While it's on screen, iOS doesn't show its own volume HUD.
struct SystemVolumeView: UIViewRepresentable {
    let observer: VolumeButtonObserver

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        observer.volumeView = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
