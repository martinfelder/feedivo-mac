import { useMemo, useState } from "react";
import {
  Archive,
  BookOpenCheck,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Circle,
  Copy,
  ExternalLink,
  Folder,
  Link2,
  PanelRightClose,
  PanelRightOpen,
  Plus,
  RotateCcw,
  Star,
  Tag,
  Wifi,
  WifiOff,
} from "lucide-react";
import "./styles.css";

const variants = [
  {
    id: "calm-actions",
    title: "Variante 1",
    name: "Calm Actions",
    note: "Wichtige Aktionen oben, Details darunter",
  },
  {
    id: "section-studio",
    title: "Variante 2",
    name: "Section Studio",
    note: "Ruhige Abschnitte mit aufklappbarer Tiefe",
  },
  {
    id: "command-inspector",
    title: "Variante 3",
    name: "Command Inspector",
    note: "Kompakte Aktionszentrale fuer Power-User",
  },
];

const initialTags = [
  { name: "SwiftUI", color: "#0a84ff" },
  { name: "macOS", color: "#24a148" },
  { name: "Release", color: "#df7a18" },
  { name: "Design", color: "#8b5cf6" },
  { name: "Offline", color: "#68707c" },
];

const tagColors = ["#0a84ff", "#24a148", "#df7a18", "#8b5cf6", "#d99a00", "#e5484d"];
const initialFolders = ["Inbox", "Leseliste", "Release", "Recherche", "Archiv"];

const initialArticle = {
  title: "Wie kleine Reader-Details den Lesefluss verbessern",
  feed: "MacStories",
  source: "macstories.net",
  published: "Heute, 14:32",
  readingTime: "5 Min.",
  url: "https://www.macstories.net/feedivo-reader-details",
  summary:
    "Ein ruhiger Inspector soll Kontext liefern, ohne den Artikel zu stoeren. Aktionen sitzen dort, wo man sie beim Sortieren und Nacharbeiten erwartet.",
  isStarred: false,
  isRead: false,
  isOffline: true,
  folder: "Leseliste",
  tags: ["SwiftUI", "Design"],
};

const relatedArticles = [
  "Safari Reader als Referenz fuer ruhige Typografie",
  "Warum Sidebar-Aktionen schneller sein koennen",
  "Offline-Pakete fuer laengere Reisen planen",
];

function FeedFolderField({ article, actions, folders, id = "feed-folder" }) {
  return (
    <div className="feed-folder-field">
      <label className="field-label" htmlFor={id}>Feed-Ordner</label>
      <select id={id} value={article.folder} onChange={(event) => actions.setFolder(event.target.value)}>
        {folders.map((folder) => (
          <option key={folder}>{folder}</option>
        ))}
      </select>
      <p className="field-hint">Aendert die Ordnerzuordnung des Feeds "{article.feed}", nicht nur diesen Artikel.</p>
      <FolderCreator actions={actions} />
    </div>
  );
}

function IconButton({ label, active, children, onClick, tone = "default" }) {
  return (
    <button
      className={`icon-button ${active ? "is-active" : ""} tone-${tone}`}
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
    >
      {children}
    </button>
  );
}

function ToggleRow({ icon, label, detail, active, onClick }) {
  return (
    <button className={`toggle-row ${active ? "is-active" : ""}`} type="button" onClick={onClick}>
      <span className="toggle-row-icon">{icon}</span>
      <span className="toggle-row-text">
        <strong>{label}</strong>
        <small>{detail}</small>
      </span>
      <span className="toggle-row-state">{active ? <CheckCircle2 size={15} /> : <Circle size={15} />}</span>
    </button>
  );
}

function TagPill({ tag, active, onClick }) {
  return (
    <button
      className={`tag-pill ${active ? "is-active" : ""}`}
      style={{ "--tag-color": tag.color }}
      type="button"
      onClick={onClick}
    >
      <Tag size={12} />
      {tag.name}
    </button>
  );
}

function TagCreator({ actions }) {
  const [name, setName] = useState("");
  const [color, setColor] = useState(tagColors[0]);

  const submit = (event) => {
    event.preventDefault();
    actions.createTag(name, color);
    setName("");
  };

  return (
    <form className="tag-creator" onSubmit={submit}>
      <label className="field-label" htmlFor="new-tag-name">Neues Tag</label>
      <div className="tag-create-row">
        <input
          id="new-tag-name"
          value={name}
          type="text"
          placeholder="Tagname"
          onChange={(event) => setName(event.target.value)}
        />
        <button type="submit">
          <Plus size={14} />
        </button>
      </div>
      <div className="color-swatches" aria-label="Tagfarbe">
        {tagColors.map((tagColor) => (
          <button
            aria-label={`Farbe ${tagColor}`}
            className={color === tagColor ? "is-active" : ""}
            key={tagColor}
            style={{ "--swatch-color": tagColor }}
            type="button"
            onClick={() => setColor(tagColor)}
          />
        ))}
      </div>
    </form>
  );
}

function FolderCreator({ actions }) {
  const [name, setName] = useState("");

  const submit = (event) => {
    event.preventDefault();
    actions.createFolder(name);
    setName("");
  };

  return (
    <form className="folder-creator" onSubmit={submit}>
      <label className="field-label" htmlFor="new-folder-name">Neuer Feed-Ordner</label>
      <div className="folder-create-row">
        <input
          id="new-folder-name"
          value={name}
          type="text"
          placeholder="Ordnername"
          onChange={(event) => setName(event.target.value)}
        />
        <button type="submit" aria-label="Feed-Ordner erstellen">
          <Plus size={14} />
        </button>
      </div>
    </form>
  );
}

function Section({ title, action, children, defaultOpen = true }) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section className="section">
      <div className="section-heading">
        <button className="section-toggle" type="button" onClick={() => setOpen(!open)}>
          {open ? <ChevronDown size={15} /> : <ChevronRight size={15} />}
          <span>{title}</span>
        </button>
        {action}
      </div>
      {open ? <div className="section-body">{children}</div> : null}
    </section>
  );
}

function ReaderPreview({ article, isInspectorOpen, setInspectorOpen }) {
  return (
    <main className="reader">
      <header className="toolbar">
        <div className="traffic">
          <span className="traffic-dot red" />
          <span className="traffic-dot yellow" />
          <span className="traffic-dot green" />
        </div>
        <div className="toolbar-title">Feedivo Reader</div>
        <button className="toolbar-button" type="button" onClick={() => setInspectorOpen(!isInspectorOpen)}>
          {isInspectorOpen ? <PanelRightClose size={16} /> : <PanelRightOpen size={16} />}
          Artikelinfos
        </button>
      </header>

      <article className="article">
        <div className="article-meta">{article.feed} · {article.published} · {article.readingTime}</div>
        <h1>{article.title}</h1>
        <p className="lead">{article.summary}</p>
        <p>
          Der Reader bleibt der ruhige Mittelpunkt. Die rechte Seitenleiste nimmt Aufgaben auf, die beim
          Kuratieren eines Artikels direkt greifbar sein sollen: Favorit setzen, Status aendern,
          Tags pflegen und Offline-Verfuegbarkeit pruefen.
        </p>
        <p>
          Wichtig ist, dass diese Kontrollen nicht wie ein zweites Dashboard wirken. Sie sollen erreichbar,
          aber nicht laut sein. Die drei Varianten testen deshalb unterschiedliche Grade an Sichtbarkeit.
        </p>
        <p>
          Beim Anklicken der Controls wird der Status im ganzen Prototyp aktualisiert. So laesst sich
          direkt fuehlen, ob die Seitenleiste im Alltag eher sortiert oder ablenkt.
        </p>
      </article>
    </main>
  );
}

function StatusStrip({ article }) {
  return (
    <div className="status-strip">
      <span className={article.isRead ? "status-dot ok" : "status-dot new"} />
      <span>{article.isRead ? "Gelesen" : "Ungelesen"}</span>
      <span className="status-separator" />
      <Star size={13} className={article.isStarred ? "star-on" : ""} />
      <span>{article.isStarred ? "Favorit" : "Nicht favorisiert"}</span>
    </div>
  );
}

function MetadataBlock({ article }) {
  return (
    <div className="metadata-list">
      <div>
        <span>Feed</span>
        <strong>{article.feed}</strong>
      </div>
      <div>
        <span>Quelle</span>
        <strong>{article.source}</strong>
      </div>
      <div>
        <span>Veroeffentlicht</span>
        <strong>{article.published}</strong>
      </div>
      <div>
        <span>Lesezeit</span>
        <strong>{article.readingTime}</strong>
      </div>
    </div>
  );
}

function CalmActions({ article, actions, availableTags, folders }) {
  return (
    <aside className="inspector calm">
      <div className="inspector-top">
        <p className="eyebrow">Artikelinfos</p>
        <h2>{article.title}</h2>
        <StatusStrip article={article} />
      </div>

      <div className="primary-actions">
        <IconButton
          label={article.isStarred ? "Favorit entfernen" : "Favorisieren"}
          active={article.isStarred}
          tone="star"
          onClick={actions.toggleStar}
        >
          <Star size={18} fill={article.isStarred ? "currentColor" : "none"} />
        </IconButton>
        <IconButton
          label={article.isRead ? "Als ungelesen markieren" : "Als gelesen markieren"}
          active={article.isRead}
          tone="read"
          onClick={actions.toggleRead}
        >
          <BookOpenCheck size={18} />
        </IconButton>
        <IconButton
          label={article.isOffline ? "Offline entfernen" : "Offline speichern"}
          active={article.isOffline}
          tone="offline"
          onClick={actions.toggleOffline}
        >
          {article.isOffline ? <WifiOff size={18} /> : <Wifi size={18} />}
        </IconButton>
        <IconButton label="Link kopieren" tone="default" onClick={actions.copyLink}>
          <Copy size={18} />
        </IconButton>
      </div>

      <Section title="Feed-Ordner">
        <FeedFolderField article={article} actions={actions} folders={folders} id="calm-feed-folder" />
      </Section>

      <Section title="Tags">
        <div className="tag-grid">
          {availableTags.map((tag) => (
            <TagPill
              key={tag.name}
              tag={tag}
              active={article.tags.includes(tag.name)}
              onClick={() => actions.toggleTag(tag.name)}
            />
          ))}
        </div>
        <TagCreator actions={actions} />
      </Section>

      <Section title="Kontext">
        <MetadataBlock article={article} />
      </Section>

      <Section title="Quelle" defaultOpen={false}>
        <button className="wide-button" type="button" onClick={actions.copyLink}>
          <Link2 size={15} />
          Link kopieren
        </button>
        <button className="wide-button" type="button">
          <ExternalLink size={15} />
          Original oeffnen
        </button>
      </Section>
    </aside>
  );
}

function SectionStudio({ article, actions, availableTags, folders }) {
  return (
    <aside className="inspector studio">
      <div className="inspector-top compact">
        <p className="eyebrow">Inspector</p>
        <h2>{article.title}</h2>
      </div>

      <Section title="Aktionen">
        <ToggleRow
          icon={<Star size={16} />}
          label="Favorit"
          detail="In der Favoritenliste behalten"
          active={article.isStarred}
          onClick={actions.toggleStar}
        />
        <ToggleRow
          icon={<BookOpenCheck size={16} />}
          label={article.isRead ? "Gelesen" : "Ungelesen"}
          detail="Status direkt im Artikel setzen"
          active={article.isRead}
          onClick={actions.toggleRead}
        />
        <ToggleRow
          icon={article.isOffline ? <WifiOff size={16} /> : <Wifi size={16} />}
          label="Offline"
          detail={article.isOffline ? "Artikel ist lokal verfuegbar" : "Artikel lokal speichern"}
          active={article.isOffline}
          onClick={actions.toggleOffline}
        />
      </Section>

      <Section title="Feed-Ordner">
        <p className="section-hint">Diese Auswahl sortiert den gesamten Feed in der linken Seitenleiste.</p>
        <div className="folder-list">
          {folders.map((folder) => (
            <button
              className={`folder-choice ${article.folder === folder ? "is-active" : ""}`}
              type="button"
              key={folder}
              onClick={() => actions.setFolder(folder)}
            >
              <Folder size={15} />
              {folder}
            </button>
          ))}
        </div>
        <FolderCreator actions={actions} />
      </Section>

      <Section title="Tags">
        <div className="tag-grid two">
          {availableTags.map((tag) => (
            <TagPill
              key={tag.name}
              tag={tag}
              active={article.tags.includes(tag.name)}
              onClick={() => actions.toggleTag(tag.name)}
            />
          ))}
        </div>
        <TagCreator actions={actions} />
        <button className="soft-add" type="button" onClick={() => actions.toggleTag("Release")}>
          <Plus size={14} />
          Vorschlag Release setzen
        </button>
      </Section>

      <Section title="Artikel" defaultOpen={false}>
        <MetadataBlock article={article} />
      </Section>
    </aside>
  );
}

function CommandInspector({ article, actions, availableTags, folders }) {
  const [mode, setMode] = useState("sort");

  return (
    <aside className="inspector command">
      <div className="command-head">
        <div>
          <p className="eyebrow">Command Inspector</p>
          <h2>{article.title}</h2>
        </div>
        <button className="reset-button" type="button" onClick={actions.reset}>
          <RotateCcw size={15} />
        </button>
      </div>

      <div className="mode-tabs">
        <button className={mode === "sort" ? "is-active" : ""} type="button" onClick={() => setMode("sort")}>Sortieren</button>
        <button className={mode === "meta" ? "is-active" : ""} type="button" onClick={() => setMode("meta")}>Meta</button>
      </div>

      {mode === "sort" ? (
        <>
          <div className="command-grid">
            <button className={article.isStarred ? "is-active star" : ""} type="button" onClick={actions.toggleStar}>
              <Star size={17} fill={article.isStarred ? "currentColor" : "none"} />
              <span>{article.isStarred ? "Favorit" : "Favorit"}</span>
            </button>
            <button className={article.isRead ? "is-active" : ""} type="button" onClick={actions.toggleRead}>
              <BookOpenCheck size={17} />
              <span>{article.isRead ? "Gelesen" : "Lesen"}</span>
            </button>
            <button className={article.isOffline ? "is-active" : ""} type="button" onClick={actions.toggleOffline}>
              <Archive size={17} />
              <span>{article.isOffline ? "Offline" : "Speichern"}</span>
            </button>
            <button type="button" onClick={actions.copyLink}>
              <Copy size={17} />
              <span>Kopieren</span>
            </button>
          </div>

          <div className="quick-panel">
            <div className="quick-row">
              <span>Feed-Ordner</span>
              <select value={article.folder} onChange={(event) => actions.setFolder(event.target.value)}>
                {folders.map((folder) => (
                  <option key={folder}>{folder}</option>
                ))}
              </select>
            </div>
            <p className="field-hint compact">Gilt fuer den Feed "{article.feed}", nicht nur fuer diesen Artikel.</p>
            <FolderCreator actions={actions} />
          </div>

          <div className="quick-panel">
            <div className="quick-panel-title">Tags</div>
            <div className="quick-tags">
              {availableTags.map((tag) => (
                <TagPill
                  key={tag.name}
                  tag={tag}
                  active={article.tags.includes(tag.name)}
                  onClick={() => actions.toggleTag(tag.name)}
                />
              ))}
            </div>
            <TagCreator actions={actions} />
          </div>
        </>
      ) : (
        <div className="meta-panel">
          <MetadataBlock article={article} />
          <div className="related">
            <span>Aehnliche Artikel</span>
            {relatedArticles.map((title) => (
              <button type="button" key={title}>{title}</button>
            ))}
          </div>
        </div>
      )}
    </aside>
  );
}

function PrototypeShell({ variant, article, actions, availableTags, folders }) {
  const [isInspectorOpen, setInspectorOpen] = useState(true);

  const Inspector = useMemo(() => {
    if (variant === "section-studio") return SectionStudio;
    if (variant === "command-inspector") return CommandInspector;
    return CalmActions;
  }, [variant]);

  return (
    <div className={`prototype-shell ${isInspectorOpen ? "" : "inspector-hidden"}`}>
      <ReaderPreview article={article} isInspectorOpen={isInspectorOpen} setInspectorOpen={setInspectorOpen} />
      {isInspectorOpen ? (
        <Inspector article={article} actions={actions} availableTags={availableTags} folders={folders} />
      ) : null}
    </div>
  );
}

export function App() {
  const [selectedVariant, setSelectedVariant] = useState("calm-actions");
  const [article, setArticle] = useState(initialArticle);
  const [availableTags, setAvailableTags] = useState(initialTags);
  const [folders, setFolders] = useState(initialFolders);
  const [toast, setToast] = useState("");

  const showToast = (message) => {
    setToast(message);
    window.clearTimeout(window.feedivoPrototypeToast);
    window.feedivoPrototypeToast = window.setTimeout(() => setToast(""), 1600);
  };

  const actions = {
    toggleStar: () => setArticle((current) => ({ ...current, isStarred: !current.isStarred })),
    toggleRead: () => setArticle((current) => ({ ...current, isRead: !current.isRead })),
    toggleOffline: () => setArticle((current) => ({ ...current, isOffline: !current.isOffline })),
    setFolder: (folder) => setArticle((current) => ({ ...current, folder })),
    createFolder: (rawName) => {
      const folderName = rawName.trim();
      if (!folderName) return;
      setFolders((current) => {
        if (current.some((folder) => folder.toLowerCase() === folderName.toLowerCase())) {
          return current;
        }
        return [...current, folderName];
      });
      setArticle((current) => ({ ...current, folder: folderName }));
      showToast(`Feed-Ordner "${folderName}" erstellt`);
    },
    toggleTag: (tagName) =>
      setArticle((current) => ({
        ...current,
        tags: current.tags.includes(tagName)
          ? current.tags.filter((existingTag) => existingTag !== tagName)
          : [...current.tags, tagName],
      })),
    createTag: (rawName, color) => {
      const tagName = rawName.trim();
      if (!tagName) return;
      setAvailableTags((current) => {
        if (current.some((tag) => tag.name.toLowerCase() === tagName.toLowerCase())) {
          return current;
        }
        return [...current, { name: tagName, color }];
      });
      setArticle((current) => ({
        ...current,
        tags: current.tags.some((existingTag) => existingTag.toLowerCase() === tagName.toLowerCase())
          ? current.tags
          : [...current.tags, tagName],
      }));
      showToast(`Tag "${tagName}" erstellt`);
    },
    copyLink: () => {
      navigator.clipboard?.writeText(article.url);
      showToast("Link kopiert");
    },
    reset: () => {
      setArticle(initialArticle);
      setAvailableTags(initialTags);
      setFolders(initialFolders);
      showToast("Artikelstatus zurueckgesetzt");
    },
  };

  const activeVariant = variants.find((variant) => variant.id === selectedVariant) ?? variants[0];

  return (
    <div className="app">
      <header className="app-header">
        <div>
          <p className="eyebrow">Feedivo · Reader Inspector</p>
          <h1>Drei ruhigere, interaktive Sidebar-Prototypen</h1>
        </div>
        <nav className="variant-switcher" aria-label="Prototyp Varianten">
          {variants.map((variant) => (
            <button
              key={variant.id}
              className={selectedVariant === variant.id ? "is-active" : ""}
              type="button"
              onClick={() => setSelectedVariant(variant.id)}
            >
              <span>{variant.title}</span>
              <strong>{variant.name}</strong>
            </button>
          ))}
        </nav>
      </header>

      <div className="variant-note">
        <strong>{activeVariant.name}</strong>
        <span>{activeVariant.note}</span>
      </div>

      <PrototypeShell
        variant={selectedVariant}
        article={article}
        actions={actions}
        availableTags={availableTags}
        folders={folders}
      />

      {toast ? <div className="toast">{toast}</div> : null}
    </div>
  );
}
