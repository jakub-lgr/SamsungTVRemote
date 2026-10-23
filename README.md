# TVRemote

Swift balíček s ovladačem pro televize Samsung se systémem Tizen přes domácí Wi-Fi. Bez cloudu,
bez účtu Samsung a bez SmartThings. Vznikl z aplikace
[SamsungTVRemote](https://github.com/jakub-lgr/SamsungTVRemote), kde je podrobně popsaný
protokol televize, kompatibilita a nastavení televize.

## Použití v aplikaci

```swift
import AppIntents
import SwiftUI
import TVRemote

// Hlavní obrazovka. Spojení s televizí naváže sama a při zmizení ho ukončí.
TVRemoteView()

// Údaje pro rozcestník.
TVRemote.name; TVRemote.systemImage; TVRemote.tint

// Akce pro Siri a Zkratky jsou v balíčku, systém je ale najde jen přes AppIntentsPackage aplikace.
struct MyAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [TVRemoteIntents.self] }
}
```

Hotové fráze pro Siri (`AppShortcutsProvider`) Xcode v balíčku nenajde, aplikace je proto skládá
sama z veřejných akcí (`MuteTVIntent`, `SetTVVolumeIntent`, `AdjustTVVolumeIntent`,
`TurnOffTVIntent`, `TurnOnTVIntent`, `OpenTVAppIntent`) a do
`TVRemote.appShortcutParametersChanged` dosadí `updateAppShortcutParameters()` svého providera.

Aplikace navíc potřebuje v Info.plist:

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` s položkou `_samsungmsf._tcp` (hledání televizí)

## Testování bez televize

`Tools/faketv.py` napodobí WebSocket API televize na `127.0.0.1:8002` a vypisuje všechno, co
ovladač pošle. Aplikaci na ni nasměruješ spouštěcím argumentem `-tv.testHost 127.0.0.1`, uložené
nastavení zůstane beze změny (v aplikaci musí být uložená aspoň jedna televize).
