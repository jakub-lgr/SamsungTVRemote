# CLAUDE.md

Poznámky pro AI asistenty (Claude Code a další), kteří v tomto repozitáři pracují.

## Projekt

Ovladač pro televize Samsung (Tizen) přes místní síť. Swift balíček `TVRemote` a samostatná
aplikace pro iPhone v `App/`. Jen pro iPhone, iOS 27, bez závislostí třetích stran. Podrobný
popis funkcí a protokolů je v `README.md`.

Repozitář je výřez většího repozitáře (`git subtree`), kde je balíček vložený do další aplikace.
Proto balíček nesmí záviset na ničem mimo sebe a veřejné je jen to, co aplikace potřebuje
(`TVRemote.swift`, akce v `TVIntents.swift`).

## Sestavení

```bash
xcodebuild -project App/SamsungTVRemote.xcodeproj -scheme SamsungTVRemote -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Build má být bez chyb i bez varování.

## Struktura

- `Sources/TVRemote/` je veškerý kód ovladače.
- `App/` je tenká obálka: `@main`, `AppShortcutsProvider` s frázemi pro Siri, ikona a Info.plist.
  Na balíček odkazuje jako na lokální balíček `..`. `AppShortcutsProvider` v balíčku nefunguje
  (Xcode ho tiše přeskočí), proto je fráze nutné držet v aplikaci.

## Konvence

- **Čeština:** texty v UI, komentáře i commit zprávy jsou česky. Dokumentační komentáře (`///`)
  vysvětlují *proč*, ne *co*.
- **Souběžnost:** balíček i aplikace mají výchozí izolaci `MainActor`. Typy, které se používají
  mimo hlavní vlákno (úložiště, síťové pomocníky, App Intents dotazy), jsou označené `nonisolated`
  (`TVConfig`, `TVVolume`, `WakeOnLAN`, `TVApp`, `SavedTV`, `DiscoveredTV`).
- **Stav aplikace:** jediná instance `SamsungTVClient.shared` (`@Observable`), předávaná přes
  `.environment`. Zkratky a Siri používají stejnou instanci.
- **Nastavení:** `TVConfig` je jediný zdroj pravdy v UserDefaults, klíče mají prefix `tv.`.
  `TVConfig.host`, `.token`, `.favoriteApps` atd. vždy patří **aktuálně vybrané** televizi ze
  seznamu `savedTVs`.
- **Životní cyklus:** po zmizení obrazovky (`onDisappear`) ovladač uvolní spojení i sledování
  bočních tlačítek. Aplikace, která ho vkládá, ho může schovat a sama dál běžet.

## Projekt v Xcode

- Formát projektu je `project.xcproj` (Xcode 27). Složka `App/SamsungTVRemote/` je synchronizovaná,
  nové soubory se do targetu přidají samy. Na úpravy projektu je `xcrun xcodeproj`.
- Info.plist se generuje z build settings (`INFOPLIST_KEY_…`). Pole `NSBonjourServices` přes build
  settings zapsat nejde, proto je v doplňkovém `App/SamsungTVRemote-Info.plist` (mimo
  synchronizovanou složku, jinak by se kopíroval jako resource).

## Protokol televize

- WebSocket `wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<base64>&token=<token>`.
  Televize má vlastní certifikát, `TVCertificateTrust` ho přijme jen pro IP vybrané televize.
- Zprávy se posílají sériově (`lastSend` řetězí odeslání), jinak by klávesy mohly dorazit přeházeně.
- Události od televize: `ms.channel.connect` (token), `ms.channel.unauthorized`, `ms.channel.timeOut`,
  `ms.remote.imeStart` / `imeEnd` (klávesnice na TV), `ed.installedApp.get` (seznam aplikací).
- Hlasitost a ztlumení jdou jen přes UPnP (`TVVolume`), WebSocket umí jen klávesy VOL+/VOL−.
- Modré tlačítko je `KEY_CYAN`, ne `KEY_BLUE`.

## Testování

- `Tools/faketv.py` napodobí televizi na `127.0.0.1:8002`. Aplikaci na ni nasměruješ spouštěcím
  argumentem `-tv.testHost 127.0.0.1`, který uložené nastavení nepřepíše.
- Simulátor používá síť Macu, takže dosáhne i na skutečnou televizi v síti.
- Úprava plistu s nastavením přímo na disku se kvůli mezipaměti `cfprefsd` neprojeví spolehlivě.
  Používej spouštěcí argumenty nebo UI aplikace.
- Na skutečné televizi nedělej nic, co mění obraz (spouštění aplikací, přepínání kanálů, psaní),
  bez souhlasu uživatele. Testuj to proti `faketv.py`.
- Do repozitáře nepatří IP adresy, MAC adresy ani tokeny televizí. Repozitář je veřejný.
