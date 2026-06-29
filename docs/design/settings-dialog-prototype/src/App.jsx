import { useMemo, useState } from "react";
import {
  Bell,
  Check,
  ChevronDown,
  Cloud,
  Download,
  Eye,
  FolderKanban,
  Gauge,
  Grid2X2,
  GripVertical,
  Info,
  Paintbrush,
  RefreshCw,
  Search,
  SlidersHorizontal,
  Sparkles,
  Tag,
  Trash2,
} from "lucide-react";

const tabs = [
  { id: "general", label: "Allgemein", icon: SlidersHorizontal },
  { id: "display", label: "Anzeige", icon: Eye },
  { id: "feeds", label: "Feeds", icon: Grid2X2 },
  { id: "smartFolders", label: "Ordner", icon: FolderKanban },
  { id: "cache", label: "Cache", icon: Gauge },
  { id: "offline", label: "Offline", icon: Download },
  { id: "notifications", label: "Benachrichtigungen", icon: Bell, wide: true },
  { id: "refresh", label: "Aktualisierung", icon: RefreshCw, wide: true },
  { id: "automation", label: "Automatisierung", icon: Sparkles },
  { id: "sync", label: "Sync", icon: Cloud },
  { id: "about", label: "Über", icon: Info },
];

const feeds = [
  { title: "Heise Online", url: "https://www.heise.de/rss/heise-atom.xml", folder: "Technik", unread: 18 },
  { title: "Mac & i", url: "https://www.heise.de/mac-and-i/rss/news-atom.xml", folder: "Apple", unread: 7 },
  { title: "NetNewsWire Blog", url: "https://netnewswire.com/blog/feed.xml", folder: "Apps", unread: 0 },
  { title: "Swift by Sundell", url: "https://swiftbysundell.com/feed.rss", folder: "Entwicklung", unread: 4 },
];

const rules = [
  { name: "Apple-Themen markieren", condition: "Titel enthält Apple oder macOS", action: "Tag: Apple", enabled: true },
  { name: "Security sofort melden", condition: "Text enthält CVE oder Zero-Day", action: "Benachrichtigung", enabled: true },
  { name: "Gewinnspiel ausblenden", condition: "Titel enthält Gewinnspiel", action: "Ausblenden", enabled: false },
];

const smartFolders = [
  { name: "Alle Artikel", meta: "Keine Bedingungen", count: 482, shown: true },
  { name: "Ungelesen", meta: "Status ist ungelesen", count: 129, shown: true },
  { name: "Diese Woche", meta: "Datum ist diese Woche", count: 42, shown: true },
  { name: "Gespeichert", meta: "Status ist mit Stern oder archiviert", count: 16, shown: true },
  { name: "Apple", meta: "Tag ist Apple oder Feed ist in Apple", count: 23, shown: false },
];

function Toggle({ checked, onChange, disabled = false }) {
  return (
    <button
      type="button"
      className={`toggle ${checked ? "is-on" : ""}`}
      aria-pressed={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
    >
      <span>{checked && <Check size={18} strokeWidth={3} />}</span>
    </button>
  );
}

function SelectControl({ value, options, onChange, wide = false, disabled = false }) {
  return (
    <label className={`select-wrap ${wide ? "wide" : ""} ${disabled ? "disabled" : ""}`}>
      <select value={value} onChange={(event) => onChange(event.target.value)} disabled={disabled}>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
      <ChevronDown size={18} />
    </label>
  );
}

function SettingRow({ title, description, children, muted = false }) {
  return (
    <div className={`setting-row ${muted ? "muted" : ""}`}>
      <div className="setting-copy">
        <div className="setting-title">{title}</div>
        {description && <div className="setting-description">{description}</div>}
      </div>
      {children && <div className="setting-control">{children}</div>}
    </div>
  );
}

function Section({ eyebrow, children }) {
  return (
    <section className="settings-section">
      <h2>{eyebrow}</h2>
      <div className="section-body">{children}</div>
    </section>
  );
}

function RangeControl({ value, min, max, onChange, label }) {
  return (
    <div className="range-control">
      <input
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
      <span>{label ?? value}</span>
    </div>
  );
}

function GeneralPane({ state, setState }) {
  return (
    <>
      <Section eyebrow="System">
        <SettingRow
          title="Sprache"
          description="Anzeigesprache wechseln. Ein App-Neustart wird empfohlen."
        >
          <SelectControl
            value={state.language}
            options={["System", "Deutsch", "Englisch", "Französisch", "Italienisch"]}
            onChange={(language) => setState({ ...state, language })}
            wide
          />
        </SettingRow>
        <SettingRow
          title="Reader-Modus"
          description="Standardansicht für geöffnete Artikel."
        >
          <div className="segmented">
            {["Reader", "Original"].map((mode) => (
              <button
                type="button"
                key={mode}
                className={state.readerMode === mode ? "active" : ""}
                onClick={() => setState({ ...state, readerMode: mode })}
              >
                {mode}
              </button>
            ))}
          </div>
        </SettingRow>
        <SettingRow
          title="Artikel beim Öffnen als gelesen markieren"
          description="Markiert den ausgewählten Artikel automatisch als gelesen."
        >
          <Toggle
            checked={state.markRead}
            onChange={(markRead) => setState({ ...state, markRead })}
          />
        </SettingRow>
      </Section>

    </>
  );
}

function RefreshPane({ state, setState }) {
  return (
    <>
      <Section eyebrow="Aktualisierung">
        <SettingRow
          title="Automatische Aktualisierung"
          description="Feeds im Hintergrund aktualisieren, solange Feedivo läuft."
        >
          <Toggle
            checked={state.autoRefresh}
            onChange={(autoRefresh) => setState({ ...state, autoRefresh })}
          />
        </SettingRow>
        <SettingRow title="Aktualisierungsintervall" description="Gilt als Standard für neue Feeds.">
          <SelectControl
            value={state.refreshInterval}
            options={["15 Min", "30 Min", "60 Min", "120 Min"]}
            onChange={(refreshInterval) => setState({ ...state, refreshInterval })}
            disabled={!state.autoRefresh}
          />
        </SettingRow>
        <p className="settings-caption">
          Feedivo nutzt macOS-Hintergrundaktivitäten. Die Aktualisierung läuft systemfreundlich,
          solange die App geöffnet ist oder im Hintergrund weiterlaufen darf.
        </p>
        <div className="refresh-status-block">
          <div className="setting-title">Aktualisierungsstatus</div>
          <div className="setting-description">
            Letzter automatischer Lauf und nächste geplante Aktualisierung.
          </div>
          <div className="refresh-status-summary">
            <div>
              <span>Letzter Lauf</span>
              <strong>Heute, 16:12</strong>
            </div>
            <div>
              <span>Status</span>
              <strong>Erfolgreich</strong>
            </div>
            <div>
              <span>Nächster Lauf</span>
              <strong>Heute, 16:42</strong>
            </div>
          </div>
        </div>
      </Section>
    </>
  );
}

function FeedsPane({ state, setState }) {
  const visibleFeeds = useMemo(() => {
    return feeds.filter((feed) => feed.title.toLowerCase().includes(state.feedSearch.toLowerCase()));
  }, [state.feedSearch]);

  return (
    <>
      <Section eyebrow="Feed-Verwaltung">
        <div className="toolbar-line">
          <label className="search-field">
            <Search size={15} />
            <input
              value={state.feedSearch}
              onChange={(event) => setState({ ...state, feedSearch: event.target.value })}
              placeholder="Feeds suchen"
            />
          </label>
          <button type="button" className="mac-button">Sichtbare auswählen</button>
          <button type="button" className="mac-button">OPML exportieren</button>
        </div>
        <div className="feed-table">
          {visibleFeeds.map((feed) => (
            <div className="feed-row" key={feed.url}>
              <Toggle
                checked={state.selectedFeeds.includes(feed.url)}
                onChange={(selected) => {
                  const selectedFeeds = selected
                    ? [...state.selectedFeeds, feed.url]
                    : state.selectedFeeds.filter((url) => url !== feed.url);
                  setState({ ...state, selectedFeeds });
                }}
              />
              <div className="feed-favicon">{feed.title.slice(0, 1)}</div>
              <div>
                <strong>{feed.title}</strong>
                <span>{feed.url}</span>
              </div>
              <em>{feed.folder}</em>
              <b>{feed.unread}</b>
            </div>
          ))}
        </div>
        <div className="bottom-actions">
          <span>{state.selectedFeeds.length} Feeds ausgewählt</span>
          <button type="button" className="mac-button danger">
            <Trash2 size={15} /> Ausgewählte löschen
          </button>
        </div>
      </Section>

      <Section eyebrow="OPML">
        <SettingRow
          title="Import und Export"
          description="Ordner, Tags und Feed-Beschreibungen können beim Export eingeschlossen werden."
        >
          <button type="button" className="mac-button">OPML importieren...</button>
        </SettingRow>
      </Section>
    </>
  );
}

function DisplayPane({ state, setState }) {
  return (
    <>
      <Section eyebrow="Oberfläche">
        <SettingRow title="UI-Schriftgröße" description="App-weite Skalierung der Bedienoberfläche.">
          <div className="segmented">
            {["Klein", "Standard", "Groß"].map((size) => (
              <button
                type="button"
                key={size}
                className={state.interfaceSize === size ? "active" : ""}
                onClick={() => setState({ ...state, interfaceSize: size })}
              >
                {size}
              </button>
            ))}
          </div>
        </SettingRow>
        <SettingRow
          title="Gelesene Feeds in der Seitenleiste anzeigen"
          description="Blendet Feeds ohne ungelesene Artikel nicht aus."
        >
          <Toggle
            checked={state.showReadFeeds}
            onChange={(showReadFeeds) => setState({ ...state, showReadFeeds })}
          />
        </SettingRow>
        <SettingRow
          title="Badge-Zähler am App-Icon anzeigen"
          description="Zeigt die Anzahl ungelesener Artikel im Dock."
        >
          <Toggle
            checked={state.appBadge}
            onChange={(appBadge) => setState({ ...state, appBadge })}
          />
        </SettingRow>
      </Section>

      <Section eyebrow="Reader">
        <SettingRow title="Titelschrift" description="Schriftfamilie und Gewicht für Artikeltitel.">
          <div className="inline-controls">
            <SelectControl
              value={state.titleFont}
              options={["System", "New York", "Georgia", "Avenir"]}
              onChange={(titleFont) => setState({ ...state, titleFont })}
            />
            <label className="mini-check">
              <input
                type="checkbox"
                checked={state.boldTitle}
                onChange={(event) => setState({ ...state, boldTitle: event.target.checked })}
              />
              Fett
            </label>
          </div>
        </SettingRow>
        <SettingRow title="Fließtext" description="Schriftfamilie und Gewicht für den Artikeltext.">
          <div className="inline-controls">
            <SelectControl
              value={state.bodyFont}
              options={["System", "New York", "Georgia", "Avenir"]}
              onChange={(bodyFont) => setState({ ...state, bodyFont })}
            />
            <label className="mini-check">
              <input
                type="checkbox"
                checked={state.boldBody}
                onChange={(event) => setState({ ...state, boldBody: event.target.checked })}
              />
              Fett
            </label>
          </div>
        </SettingRow>
        <SettingRow title="Textgröße" description="Größe des nativen Reader-Texts.">
          <RangeControl
            value={state.bodySize}
            min={15}
            max={24}
            label={`${state.bodySize} px`}
            onChange={(bodySize) => setState({ ...state, bodySize })}
          />
        </SettingRow>
        <SettingRow title="Zeilenabstand" description="Vertikaler Abstand im Fließtext.">
          <RangeControl
            value={state.lineSpacing}
            min={4}
            max={14}
            label={`${state.lineSpacing} px`}
            onChange={(lineSpacing) => setState({ ...state, lineSpacing })}
          />
        </SettingRow>
        <SettingRow title="Maximale Textbreite" description="Breite der Lesespalte im Reader.">
          <RangeControl
            value={state.contentWidth}
            min={560}
            max={920}
            label={`${state.contentWidth} px`}
            onChange={(contentWidth) => setState({ ...state, contentWidth })}
          />
        </SettingRow>
      </Section>

    </>
  );
}

function CachePane({ state, setState }) {
  return (
    <>
      <Section eyebrow="Cache">
        <SettingRow title="Aktuelle Größe" description="Gespeicherte Bilder und Favicons.">
          <strong className="metric-value">418 MB</strong>
        </SettingRow>
        <SettingRow title="Cache-Limit" description="Feedivo räumt den Cache automatisch bis zu diesem Limit auf.">
          <SelectControl
            value={state.cacheLimit}
            options={["250 MB", "500 MB", "1 GB", "2 GB"]}
            onChange={(cacheLimit) => setState({ ...state, cacheLimit })}
          />
        </SettingRow>
        <p className="settings-caption">
          Der Cache macht Artikelbilder und Favicons schneller verfügbar. Offline gespeicherte Artikel
          werden dadurch nicht gelöscht.
        </p>
        <div className="button-row">
          <button type="button" className="mac-button">Cache-Größe neu berechnen</button>
          <button type="button" className="mac-button danger">Cache leeren</button>
        </div>
      </Section>
    </>
  );
}

function OfflinePane({ state, setState }) {
  return (
    <>
      <Section eyebrow="Offline-Lesen">
        <SettingRow
          title="Manuell offline speichern"
          description="Artikel können über Kontextmenü, Reader und Archiv-Aktion lokal gespeichert oder wieder entfernt werden."
        >
          <div className="offline-badge">
            <Download size={16} />
            Verfügbar
          </div>
        </SettingRow>
        <SettingRow
          title="Feed-Inhalt verwenden"
          description="Feedivo speichert gelieferten Artikelinhalt in SwiftData und nutzt ihn als Basis für Offline-Kopien."
        />
        <SettingRow
          title="Artikel mit Stern automatisch offline speichern"
          description="Wenn aktiv, stoßen Stern-Aktionen aus Artikelzeile, Inspector und Menü/Shortcut automatisch einen Offline-Download an."
        >
          <Toggle
            checked={state.autoOfflineStarred}
            onChange={(autoOfflineStarred) => setState({ ...state, autoOfflineStarred })}
          />
        </SettingRow>
      </Section>

      <Section eyebrow="Archiv">
        <SettingRow
          title="Archivierte Artikel lokal sichern"
          description="Archivieren setzt den Archivstatus nur, wenn eine Offline-Kopie verfügbar ist. Entfernen der Offline-Kopie entfernt auch den Archivstatus."
        />
        <div className="offline-note-panel">
          <strong>Bewusst getrennt</strong>
          <span>Entsternen löscht die Offline-Kopie nicht automatisch. Dafür bleibt die explizite Aktion „Offline-Kopie entfernen“ zuständig.</span>
        </div>
      </Section>
    </>
  );
}

function AutomationPane({ state, setState }) {
  return (
    <>
      <Section eyebrow="Artikel-Aufbewahrung">
        <SettingRow
          title="Alte Artikel automatisch löschen"
          description="Standardmäßig bleiben Artikel erhalten; aktivieren löscht alte Artikel nach dem gewählten Zeitraum."
        >
          <Toggle
            checked={state.retentionEnabled}
            onChange={(retentionEnabled) => setState({ ...state, retentionEnabled })}
          />
        </SettingRow>
        <SettingRow title="Aufbewahrungsdauer" description="Stern- und archivierte Artikel sind geschützt.">
          <SelectControl
            value={state.retentionDays}
            options={["30 Tage", "60 Tage", "90 Tage", "180 Tage"]}
            onChange={(retentionDays) => setState({ ...state, retentionDays })}
            disabled={!state.retentionEnabled}
          />
        </SettingRow>
        <SettingRow title="Geschützte Artikel einschließen" description="Löscht auch Artikel mit Stern oder Archivstatus.">
          <Toggle
            checked={state.includeProtected}
            disabled={!state.retentionEnabled}
            onChange={(includeProtected) => setState({ ...state, includeProtected })}
          />
        </SettingRow>
      </Section>

      <Section eyebrow="Regeln">
        <div className="list-panel">
          {rules.map((rule) => (
            <div className="rule-row" key={rule.name}>
              <Toggle checked={rule.enabled} onChange={() => {}} />
              <div>
                <strong>{rule.name}</strong>
                <span>{rule.condition}</span>
              </div>
              <em>{rule.action}</em>
            </div>
          ))}
        </div>
        <div className="button-row">
          <button type="button" className="mac-button">Regel hinzufügen</button>
          <button type="button" className="mac-button">Alle Regeln anwenden</button>
        </div>
      </Section>

    </>
  );
}

function SmartFoldersPane() {
  return (
    <>
      <Section eyebrow="Intelligente Ordner">
        <div className="smart-settings-head">
          <div>
            <div className="setting-title">Intelligente Ordner verwalten</div>
            <div className="setting-description">
              Reihenfolge per Drag & Drop ändern, Sidebar-Sichtbarkeit setzen und Ordner bearbeiten.
            </div>
          </div>
          <div className="smart-head-actions">
            <button type="button" className="mac-button">Defaults wiederherstellen</button>
            <button type="button" className="mac-button primary">Ordner hinzufügen</button>
          </div>
        </div>

        <div className="smart-folder-table">
          <div className="smart-header">
            <span>Reihenfolge</span>
            <span>Seitenleiste</span>
            <span>Name</span>
            <span>Bedingungen</span>
            <span>Treffer</span>
            <span />
          </div>
          {smartFolders.map((folder) => (
            <div className="smart-folder-row" key={folder.name}>
              <GripVertical className="smart-order-handle" size={18} />
              <Toggle checked={folder.shown} onChange={() => {}} />
              <div className="smart-name">
                <FolderKanban size={18} />
                <div>
                  <strong>{folder.name}</strong>
                  <span>{folder.name === "Apple" ? "Eigener Ordner" : "Standard-Ordner"}</span>
                </div>
              </div>
              <span>{folder.meta}</span>
              <b>{folder.count}</b>
              <div className="smart-row-actions">
                <button type="button" className="icon-mini" aria-label={`${folder.name} bearbeiten`}>
                  <Paintbrush size={14} />
                </button>
                <button type="button" className="icon-mini danger" aria-label={`${folder.name} löschen`}>
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>

        <div className="button-row">
          <button type="button" className="mac-button">Bearbeiten...</button>
          <button type="button" className="mac-button">Duplizieren</button>
          <button type="button" className="mac-button danger">Löschen</button>
        </div>
      </Section>
    </>
  );
}

function SyncPane({ state, setState }) {
  return (
    <>
      <Section eyebrow="iCloud Sync">
        <div className="sync-empty">
          <Cloud size={44} />
          <strong>iCloud Sync ist vorbereitet, aber noch nicht aktiv</strong>
          <span>CloudKit-Voraussetzungen sind im Modell vorbereitet. Die Produktentscheidung für v1 ist noch offen.</span>
          <Toggle checked={state.syncPreview} onChange={(syncPreview) => setState({ ...state, syncPreview })} />
        </div>
      </Section>
    </>
  );
}

function NotificationsPane() {
  return (
    <>
      <Section eyebrow="Mitteilungen">
        <SettingRow title="macOS-Erlaubnis" description="Feedivo darf lokale Benachrichtigungen senden.">
          <button type="button" className="mac-button">Erlaubnis prüfen</button>
        </SettingRow>
        <div className="info-row">
          <Bell size={18} />
          <div>
            <strong>Feed-Benachrichtigungen</strong>
            <span>Neue Artikel können pro Feed in den Feed-Eigenschaften gemeldet werden.</span>
          </div>
        </div>
        <div className="info-row">
          <Sparkles size={18} />
          <div>
            <strong>Regel-Benachrichtigungen</strong>
            <span>Regeln können gezielt Benachrichtigungen auslösen, zum Beispiel für Security- oder Apple-Themen.</span>
          </div>
        </div>
      </Section>

      <Section eyebrow="Dock">
        <SettingRow title="Badge-Zähler" description="Die Sichtbarkeit des ungelesenen Zählers wird unter Anzeige gesteuert." />
      </Section>
    </>
  );
}

function AboutPane() {
  return (
    <>
      <Section eyebrow="Feedivo">
        <div className="about-block">
          <div className="app-icon">F</div>
          <div>
            <h3>Feedivo</h3>
            <p>Nativer macOS RSS Reader mit Tags, Regeln, Offline-Lesen und OPML.</p>
            <span>Version 0.4 Prototype - M4 Polish & Release</span>
          </div>
        </div>
      </Section>
      <Section eyebrow="Release">
        <SettingRow title="Verteilung" description="App Store oder private Verteilung ist noch zu entscheiden." />
        <SettingRow title="Lokalisierung" description="Deutsch, Englisch, Französisch und Italienisch sind im String Catalog vorbereitet." />
      </Section>
    </>
  );
}

const initialState = {
  language: "System",
  readerMode: "Reader",
  markRead: true,
  autoRefresh: true,
  refreshInterval: "30 Min",
  feedSearch: "",
  selectedFeeds: [feeds[0].url, feeds[1].url],
  interfaceSize: "Standard",
  showReadFeeds: true,
  titleFont: "System",
  bodyFont: "System",
  boldTitle: true,
  boldBody: false,
  bodySize: 18,
  lineSpacing: 8,
  contentWidth: 760,
  cacheLimit: "500 MB",
  autoOfflineStarred: false,
  retentionEnabled: false,
  retentionDays: "90 Tage",
  includeProtected: false,
  appBadge: true,
  syncPreview: false,
};

export function App() {
  const [activeTab, setActiveTab] = useState("general");
  const [state, setState] = useState(initialState);

  return (
    <main className="prototype-stage">
      <div className="settings-window">
        <div className="titlebar">
          <div className="traffic-lights" aria-hidden="true">
            <span className="red" />
            <span className="yellow" />
            <span className="green" />
          </div>
          <h1>{tabs.find((tab) => tab.id === activeTab)?.label}</h1>
          <div className="titlebar-spacer" />
        </div>

        <nav className="toolbar" aria-label="Einstellungen">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            return (
              <button
                key={tab.id}
                type="button"
                className={`${activeTab === tab.id ? "active" : ""}${tab.wide ? " wide" : ""}`}
                onClick={() => setActiveTab(tab.id)}
              >
                <Icon size={34} strokeWidth={1.9} />
                <span>{tab.label}</span>
              </button>
            );
          })}
        </nav>

        <div className="content-shell">
          <div className="scroll-area">
            {activeTab === "general" && <GeneralPane state={state} setState={setState} />}
            {activeTab === "display" && <DisplayPane state={state} setState={setState} />}
            {activeTab === "feeds" && <FeedsPane state={state} setState={setState} />}
            {activeTab === "smartFolders" && <SmartFoldersPane />}
            {activeTab === "cache" && <CachePane state={state} setState={setState} />}
            {activeTab === "offline" && <OfflinePane state={state} setState={setState} />}
            {activeTab === "notifications" && <NotificationsPane />}
            {activeTab === "refresh" && <RefreshPane state={state} setState={setState} />}
            {activeTab === "automation" && <AutomationPane state={state} setState={setState} />}
            {activeTab === "sync" && <SyncPane state={state} setState={setState} />}
            {activeTab === "about" && <AboutPane />}
          </div>
        </div>
      </div>
    </main>
  );
}
