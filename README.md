# Julpix — Windows PC-Bridge & iPhone Querformat Stats App

Dieses Projekt besteht aus zwei aufeinander abgestimmten Apps:

1. **`windows/JulpixConnect`** — Windows Desktop-App (.NET 8 WPF)
   - Sammelt Live-Telemetrie deines PCs (CPU, Auslastung pro Kern, Temperatur, Takt, GPU, VRAM, Lüfter, RAM, Festplatten, Netzwerk Up/Down, Uptime, Top-Prozesse).
   - Zeigt einen **QR-Code** + **6-stelligen PIN** an, um deinen PC in der iPhone-App hinzuzufügen.
   - Antwortet automatisch auf WLAN-Suche (UDP Port `52841`) und streamt Stats per WebSocket (TCP Port `52840`).

2. **`ios/JulpixStats`** — Native iOS SwiftUI App (Querformat / Landscape)
   - Läuft fest im **Querformat**.
   - **PC hinzufügen**: Per QR-Code-Scanner, automatischer WLAN-Suche oder manueller IP/PIN-Eingabe.
   - **Live-Hintergrundbilder ohne iPhone Live-Photo-Funktion**:
     - 4 eingebaute 60fps Live-Effekte (*Cyberpunk Grid*, *Sternen-Partikel*, *Aurora Wellen*, *Matrix Regen*).
     - Eigene **MP4/MOV-Videos** oder **animierte GIFs** aus der Fotos-Mediathek oder Dateien-App als Endlos-Loop-Hintergrund.
     - Einstellbare Abdunklung, Unschärfe und Karten-Transparenz.

---

## 1. Windows-App starten

```powershell
cd windows\JulpixConnect
dotnet run -c Release
```
Oder direkt die kompilierte `JulpixConnect.exe` aus `windows\JulpixConnect\bin\Release\net8.0-windows\` starten.
*(Tipp: Für alle Hardware-Temperatursensoren ggf. einmal als Administrator starten; für normale Stats funktioniert es auch ohne Adminrechte.)*

---

## 2. iOS `.ipa` automatisch bauen (GitHub Actions)

Da `.ipa`-Dateien Xcode auf macOS benötigen, liegt unter `.github/workflows/build-ipa.yml` ein fertiger Workflow:

1. Lade diesen Ordner in ein GitHub-Repository hoch (`git push`).
2. Öffne auf GitHub den Tab **Actions** → **Build iOS IPA (JulpixStats)** → **Run workflow**.
3. Lade nach ~2 Minuten das Artifact **`JulpixStats-ipa`** herunter und installiere `JulpixStats.ipa` mit **Sideloadly**, **AltStore** oder **SideStore** auf deinem iPhone.
