Windows Font-Manager & Unicode-Matrix

Ein modularer, performanter Windows-Schriftartenmanager in Delphi, konzipiert nach der sauberen Dreischichten-Architektur (MVC). 

Dieses Projekt trennt die visuelle Benutzeroberfläche vollständig von einem autarken WinAPI-Grafiktriebwerk und bricht historische Betriebssystem-Grenzen auf. 

🚀 Kern-Features & Durchbrüche

LF_FACESIZE-31-Zeichen-Bypass: Hebelt das historische GDI-Limit von Windows aus. Über eine DirectWrite-Hintertür (GetTextFace) werden die unbeschnittenen, echten Familiennamen moderner Variable Fonts (z. B. Bitcount Ink) fehlerfrei aufgelöst und im Grid gerendert.
UAC-Doppelinstanz-Modell: Ermöglicht die fehlerfreie Installation und restlose, synchrone Deinstallation von TrueType- (.ttf) und OpenType-Schriften (.otf). Löscht Dateien ohne GDI-Sperrblockaden direkt von der Festplatte und säubert parallel HKLM und HKCU.
Intelligenter System-Schutzschild: Eine integrierte Blacklist schützt kritische Windows-Core-Fonts (wie die Segoe-Familie, Arial oder Calibri) vor unabsichtlichen Löschaktionen. Das System blockiert den Prozess im Vorfeld, noch bevor administrative Rechte angefordert werden.
Echtzeit-Live-Suche & Typ-Filter: Ruckelfreies Durchsuchen der installierten Schriftarten exakt am Namensanfang (inklusive automatischer Bereinigung asiatischer @-Präfixe). Filtert Schriften im RAM blitzschnell nach Monospace (Festbreite) und Rasterschriften (Bitmap) mittels hocheffizientem TextMetric-Caching.
Unicode PUA-Matrix: Findet und rendert verborgene Glyphen und Interface-Icons (z. B. aus Font Awesome oder Google Material Symbols) im Private Use Area. Bietet eine detaillierte Hex-Code-Vorschau und exportiert die echten Unicode-Zeichen per Doppelklick direkt in die Windows-Zwischenablage.
Visuelles OwnerDraw-Feedback: Verwendet ein schnelles, flackerfreies Listen-Zeichnungsverfahren. Geschützte Systemschriftarten werden im UI automatisch grau und kursiv signalisiert, um dem Benutzer editierbare Fonts optisch sofort zu verdeutlichen.

🛠️ Technische Details (Architektur)

Model (Engine): U_FontEngine.pas arbeitet als vollkommen autarker Dienstleister, völlig frei von GUI-Elementen oder visuellen Abhängigkeiten.
View / Controller: U_FV_04.pas dient als schlanker Verwalter der Benutzeroberfläche und bindet die gefilterten Datenströme direkt an ein performantes TStringGrid und eine TListBox an.

📦 Download & Ausführung

Die fertig kompilierte Version für Windows findest du auf der rechten Seite unter Releases. Einfach die ZIP-Datei herunterladen, entpacken und die ausführbare Datei starten!
