import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

/// Ovládání hlasitosti televize bočními tlačítky iPhonu, dokud je aplikace otevřená.
///
/// iOS na to nemá veřejné API. Sledujeme proto hlasitost telefonu a každou změnu přeložíme
/// na VOL+/VOL−. Neviditelné `MPVolumeView` potlačí systémový ukazatel hlasitosti a umožní
/// hodnotu vracet doprostřed, aby šlo mačkat stejným směrem pořád dokola. Při ukončení
/// se hlasitost telefonu vrátí na původní hodnotu.
final class VolumeButtonObserver {
    var onPress: ((_ up: Bool) -> Void)?
    fileprivate weak var volumeView: MPVolumeView?

    private var subscription: AnyCancellable?
    private var lastVolume: Float = 0
    private var originalVolume: Float?
    /// Hodnota, kterou jsme nastavili sami. Její změnu nepovažujeme za stisk tlačítka.
    private var ignoredValue: Float?

    func start() {
        guard subscription == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // .ambient nepřeruší hudbu, která v telefonu zrovna hraje.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        let volume = session.outputVolume
        originalVolume = volume
        lastVolume = volume
        subscription = session.publisher(for: \.outputVolume)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] new in self?.volumeChanged(to: new) }
        // Na kraji rozsahu by se další stisk stejným směrem neprojevil.
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

/// Skoro neviditelné systémové `MPVolumeView`. Dokud je na obrazovce, iOS neukazuje vlastní ukazatel hlasitosti.
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
