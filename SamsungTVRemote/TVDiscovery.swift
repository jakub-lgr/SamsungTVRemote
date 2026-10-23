import Foundation
import Network
import Observation

/// Televize Samsung nalezená v místní síti.
nonisolated struct DiscoveredTV: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let model: String
    let host: String
    let mac: String
    let isOn: Bool
}

/// Hledá televize Samsung v síti přes Bonjour (služba Smart View `_samsungmsf._tcp`).
///
/// SSDP, které Samsung používá jinak, potřebuje od Applu multicast oprávnění, které bezplatný
/// účet nedostane. Bonjour obstarává systém, takže funguje bez něj. Záznam služby obsahuje
/// adresu REST API televize, odkud načteme model a MAC adresu.
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
    /// Adresy API, které už načítáme, ať se stejná televize nedotazuje víckrát.
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
                // kDNSServiceErr_NoAuth: uživatel aplikaci nepovolil přístup k místní síti.
                state = .failed("Aplikace nemá přístup k místní síti. Povol ho v Nastavení iPhonu → TV Ovladač.")
            } else {
                state = .failed("Hledání televizí selhalo: \(error.localizedDescription)")
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
              // Párování tokenem (port 8002) umí jen televize, které ho samy hlásí.
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
