import Foundation
import Network
import Observation

/// A Samsung TV found on the local network.
nonisolated struct DiscoveredTV: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let model: String
    let host: String
    let mac: String
    let isOn: Bool
}

/// Looks for Samsung TVs on the network via Bonjour (the Smart View service `_samsungmsf._tcp`).
///
/// SSDP, which Samsung otherwise uses, needs a multicast entitlement from Apple that a free
/// account doesn't get. Bonjour is handled by the system, so it works without one. The service record
/// contains the TV's REST API address, from which we load the model and MAC address.
@Observable
final class TVDiscovery {
    enum State: Equatable {
        case idle
        case searching
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var televisions: [DiscoveredTV] = []

    private var browser: NWBrowser?
    /// API addresses already being loaded, so the same TV isn't queried more than once.
    private var requested: Set<URL> = []

    func start() {
        stop()
        televisions = []
        requested = []
        state = .searching

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_samsungmsf._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated { self?.browserStateChanged(newState) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.resultsChanged(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        if state == .searching { state = .idle }
    }

    private func browserStateChanged(_ newState: NWBrowser.State) {
        switch newState {
        case .failed(let error), .waiting(let error):
            if case .dns(let code) = error, code == -65555 {
                // kDNSServiceErr_NoAuth: the user didn't allow the app access to the local network.
                state = .failed("The app has no access to the local network. Allow it in iPhone Settings → Privacy & Security → Local Network.")
            } else {
                state = .failed("Looking for TVs failed: \(error.localizedDescription)")
            }
        default:
            break
        }
    }

    private func resultsChanged(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case .bonjour(let txt) = result.metadata,
                  let address = txt["se"],
                  let url = URL(string: address),
                  !requested.contains(url) else { continue }
            requested.insert(url)
            Task { await loadDetails(from: url) }
        }
    }

    private func loadDetails(from url: URL) async {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let device = json["device"] as? [String: Any],
              let host = (device["ip"] as? String) ?? url.host(),
              // Only TVs that advertise it support token pairing (port 8002).
              (device["TokenAuthSupport"] as? String) == "true" else { return }

        let rawName = (device["name"] as? String) ?? (json["name"] as? String) ?? "Samsung TV"
        let tv = DiscoveredTV(
            id: (device["id"] as? String) ?? host,
            name: rawName.replacingOccurrences(of: "[TV] ", with: ""),
            model: (device["modelName"] as? String) ?? "",
            host: host,
            mac: ((device["wifiMac"] as? String) ?? "").uppercased(),
            isOn: (device["PowerState"] as? String ?? "on") == "on"
        )
        televisions.removeAll { $0.id == tv.id }
        televisions.append(tv)
        televisions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
