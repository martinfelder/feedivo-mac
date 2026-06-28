#!/usr/bin/env python3
"""xcstrings-Injektor für L10n-Abschluss. Siehe Plan Task 0."""
import argparse, csv, json, sys

DEFAULT_PATH = "Feedivo/Resources/Localizable.xcstrings"
LANGS = ["de", "en", "fr", "it"]
# CLDR-Plural-Kategorien je Sprache (Spec-Abschnitt 2).
PLURAL_CATS = {"de": ["one", "other"], "en": ["one", "other"],
               "fr": ["one", "other"], "it": ["one", "many"]}

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def save(path, doc):
    doc["strings"] = dict(sorted(doc["strings"].items()))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")

def inject_plain(doc, rows):
    for row in rows:
        key, de, en, fr, it = row["key"], row["de"], row["en"], row["fr"], row["it"]
        entry = doc["strings"].setdefault(key, {"localizations": {}})
        locs = entry.setdefault("localizations", {})
        for lang, val in zip(LANGS, [de, en, fr, it]):
            locs[lang] = unit(val)
        # Plural-Variationen ggf. entfernen, damit plain wieder kanonisch ist.
        for lang in LANGS:
            locs.get(lang, {}).pop("variations", None)

def inject_plural(doc, rows):
    cols = ["key", "de_one", "de_other", "en_one", "en_other",
            "fr_one", "fr_other", "it_one", "it_many"]
    for row in rows:
        key = row["key"]
        entry = doc["strings"].setdefault(key, {"localizations": {}})
        locs = entry.setdefault("localizations", {})
        vals = {lang: {cat: row[f"{lang}_{cat}"] for cat in PLURAL_CATS[lang]}
                for lang in LANGS}
        for lang in LANGS:
            loc = locs.setdefault(lang, {})
            loc.pop("stringUnit", None)  # plain-Wert entfernen, Plural ist kanonisch.
            variations = loc.setdefault("variations", {}).setdefault("plural", {})
            for cat in PLURAL_CATS[lang]:
                variations[cat] = unit(vals[lang][cat])

def read_tsv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["plain", "plural"], required=True)
    ap.add_argument("--table", required=True)
    ap.add_argument("--xcstrings", default=DEFAULT_PATH)
    args = ap.parse_args()
    doc = load(args.xcstrings)
    rows = read_tsv(args.table)
    if args.mode == "plain":
        inject_plain(doc, rows)
    else:
        inject_plural(doc, rows)
    save(args.xcstrings, doc)
    print(f"{args.mode}: {len(rows)} Keys injiziert -> {args.xcstrings}")

if __name__ == "__main__":
    main()
