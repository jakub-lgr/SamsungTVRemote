# CLAUDE.md

Poznámky pro AI asistenty (Claude Code a další), kteří v tomto repozitáři pracují.

## Projekt

SwiftUI aplikace pro iPhone, která ovládá televize Samsung (Tizen) přes místní síť. Jen pro iPhone,
iOS 27, bez závislostí třetích stran. Podrobný popis funkcí a protokolů je v `README.md`.

## Sestavení

```bash
xcodebuild -scheme SamsungTVRemote -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Build má být bez chyb i bez varování.

## Konvence

- **Čeština:** texty v UI, komentáře i commit zprávy jsou česky. Dokumentační komentáře (`///`)
  vysvětlují *proč*, ne *co*.
- **Souběžnost:** projekt má `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Typy, které se používají
  mimo hlavní vlákno (úložiště, síťové pomocníky, App Intents dotazy), jsou označené `nonisolated`
  (`TVConfig`, `TVVolume`, `WakeOnLAN`, `TVApp`, `SavedTV`, `DiscoveredTV`).
- **Stav aplikace:** jediná instance `SamsungTVClient.shared` (`@Observable`), předávaná přes
  `.environment`. Zkratky a Siri používají stejnou instanci.
- **Nastavení:** `TVConfig` je jediný zdroj pravdy v UserDefaults. `TVConfig.host`, `.token`,
  `.favoriteApps` atd. vždy patří **aktuálně vybrané** televizi ze seznamu `savedTVs`.

## Projekt v Xcode

- Formát projektu je `project.xcproj` (Xcode 27). Složka `SamsungTVRemote/` je synchronizovaná,
  nové soubory se do targetu přidají samy.
- Info.plist se generuje z build settings (`INFOPLIST_KEY_…`). Pole `NSBonjourServices` přes build
  settings zapsat nejde, proto je v doplňkovém `SamsungTVRemote-Info.plist` v kořeni repozitáře
  (mimo synchronizovanou složku, jinak by se kopíroval jako resource).

## Protokol televize

- WebSocket `wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<base64>&token=<token>`.
  Televize má vlastní certifikát, `TVCertificateTrust` ho přijme jen pro IP vybrané televize.
- Zprávy se posílají sériově (`lastSend` řetězí odeslání), jinak by klávesy mohly dorazit přeházeně.
- Události od televize: `ms.channel.connect` (token), `ms.channel.unauthorized`, `ms.channel.timeOut`,
  `ms.remote.imeStart` / `imeEnd` (klávesnice na TV), `ed.installedApp.get` (seznam aplikací).
- Hlasitost a ztlumení jdou jen přes UPnP (`TVVolume`), WebSocket umí jen klávesy VOL+/VOL−.

## Testování

- `Tools/faketv.py` napodobí televizi na `127.0.0.1:8002`. Aplikaci na ni nasměruješ spouštěcím
  argumentem `-tv.testHost 127.0.0.1`, který uložené nastavení nepřepíše.
- Simulátor používá síť Macu, takže dosáhne i na skutečnou televizi v síti.
- Úprava plistu s nastavením přímo na disku se kvůli mezipaměti `cfprefsd` neprojeví spolehlivě.
  Používej spouštěcí argumenty nebo UI aplikace.
- Na skutečné televizi nedělej nic, co mění obraz (spouštění aplikací, přepínání kanálů, psaní),
  bez souhlasu uživatele. Testuj to proti `faketv.py`.
