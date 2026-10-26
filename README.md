# TV Ovladač

iPhone aplikace pro ovládání televizí Samsung se systémem Tizen přes domácí Wi-Fi.
Bez cloudu, bez účtu Samsung a bez SmartThings. Telefon mluví s televizí přímo.

<p align="center">
  <img src="Docs/remote.png" width="300" alt="Obrazovka ovladače">
</p>

## Co umí

- **Klasický ovladač:** šipky a OK, Zpět, Domů, Zdroj, hlasitost, kanály, ztlumení a vypínač.
- **Podržení tlačítka** opakuje klávesu jako fyzický ovladač (hlasitost, kanály, šipky).
- **Hlasitost na číslo:** posuvník nebo zadání přesné hodnoty 0–100. Aktuální hlasitost i ztlumení se čtou z televize.
- **Hlasitost bočními tlačítky iPhonu,** dokud je aplikace otevřená.
- **Psaní z klávesnice telefonu** do hledání v YouTube, Netflixu a dalších. Panel se otevře sám, jakmile televize ukáže klávesnici.
- **Aplikace z televize:** seznam nainstalovaných aplikací, spuštění jedním klepnutím, oblíbené připnuté přímo na ovladači.
- **Barevná tlačítka** (červené, zelené, žluté, modré) pro teletext, HbbTV a nabídky aplikací.
- **Číselník** pro přímou volbu kanálu.
- **Zapnutí televize** přes Wake-on-LAN.
- **Více televizí:** hledání v síti, každá televize má vlastní párování a oblíbené aplikace, přepínání jedním klepnutím.
- **Siri a Zkratky:** zapnout/vypnout, ztlumit, nastavit nebo změnit hlasitost, spustit aplikaci.

## Jak to funguje

Televize Samsung s Tizenem mají v síti několik rozhraní. Aplikace používá tato:

| Co | Rozhraní | Port |
|---|---|---|
| Klávesy, aplikace, psaní textu | WebSocket API (`samsung.remote.control`) přes TLS, párování tokenem | 8002 |
| Hledání televizí | Bonjour, služba Smart View `_samsungmsf._tcp` | – |
| Údaje o televizi (model, MAC, stav) | REST API `/api/v2/` | 8001 |
| Přesná hlasitost a ztlumení | UPnP `RenderingControl` (SOAP) | 9197 |
| Zapnutí | Wake-on-LAN, magic packet přes UDP | 9 |

Při prvním připojení televize zobrazí dotaz na povolení. Po potvrzení vydá token, který si aplikace
uloží, a další připojení už proběhnou bez ptaní.

Aplikace hledá televize přes Bonjour, ne přes SSDP. SSDP potřebuje od Applu multicast oprávnění, které
bezplatný vývojářský účet nedostane. Bonjour obstarává systém, takže funguje i bez něj.

## Kompatibilita

Televize Samsung s Tizenem, které podporují párování tokenem. Zhruba modely od roku 2017 a novější.
Aplikace nabízí v hledání jen televize, které tuto podporu samy hlásí (`TokenAuthSupport`).

Vyzkoušeno na:
- Samsung UE55RU8002 (řada RU8000, 2019)
- Samsung UE32T5372 (řada T5300, 2020)

## Instalace

Aplikace není v App Storu. Nainstaluješ si ji z Xcode do vlastního iPhonu.

1. Otevři `SamsungTVRemote.xcodeproj` v Xcode 27 nebo novějším.
2. V *Signing & Capabilities* vyber svůj tým. Stačí bezplatné Apple ID (Personal Team).
   Kdyby bylo bundle ID obsazené, změň ho na vlastní.
3. Na iPhonu zapni *Nastavení → Soukromí a zabezpečení → Režim vývojáře* a aplikaci spusť z Xcode.
4. Povol aplikaci **přístup k místní síti**.

S bezplatným účtem vyprší podpis aplikace po 7 dnech a je potřeba ji znovu nahrát z Xcode.

### Nastavení televize

- Televize a telefon musí být ve stejné síti.
- Pro zapnutí přes Wake-on-LAN: *Nastavení → Obecné → Síť → Odborné nastavení → Zapnutí přes mobil*.
- Pevná IP adresa televize (rezervace v routeru) se hodí, ať se po restartu routeru nemusí hledat znovu.

## Struktura projektu

```
SamsungTVRemote/
├── SamsungTVClient.swift      # spojení s televizí, klávesy, aplikace, text, přepínání televizí
├── TVConfig.swift             # uložené televize (UserDefaults)
├── TVDiscovery.swift          # hledání televizí přes Bonjour
├── TVVolume.swift             # hlasitost a ztlumení přes UPnP
├── WakeOnLAN.swift            # magic packet pro zapnutí
├── TVIntents.swift            # akce pro Siri a Zkratky
├── VolumeButtonObserver.swift # boční tlačítka iPhonu
├── ContentView.swift          # obrazovka ovladače
├── RemoteControls.swift       # tlačítka, D-pad, opakování při podržení
└── …Sheet.swift, SettingsView.swift
Tools/faketv.py                # falešná televize pro testování
Design/AppIcon/                # skripty pro Blender, ze kterých je vyrenderovaná ikona
```

## Testování bez televize

`Tools/faketv.py` napodobí WebSocket API televize na `127.0.0.1:8002` a vypisuje všechno, co aplikace pošle:

```bash
python3 Tools/faketv.py
xcrun simctl launch booted cz.jakublanger.SamsungTVRemote -tv.testHost 127.0.0.1
```

Simulátor používá síť Macu, takže když je Mac ve stejné Wi-Fi jako televize, jde aplikaci zkoušet
i proti skutečné televizi přímo ze simulátoru.

## Omezení

- Boční tlačítka iPhonu fungují přes neoficiální postup (iOS na to nemá veřejné API).
- Siri česky nemluví, fráze jsou proto anglicky. V aplikaci Zkratky jsou všechny akce česky.
- Wake-on-LAN posílá paket přímo na IP televize, protože broadcast iOS bez multicast oprávnění blokuje.
  Televize v hlubokém spánku ho občas nemusí zachytit.

---

Osobní projekt, nijak nesouvisí se společností Samsung. Samsung, Tizen a Smart View jsou ochranné známky
svých vlastníků.
