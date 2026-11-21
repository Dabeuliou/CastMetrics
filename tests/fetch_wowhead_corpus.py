"""Fetch multi-class spell tooltips from Wowhead across locales for parser testing."""

import html
import json
import re
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

LOCALES = {
    "enUS": "en",
    "frFR": "fr",
    "deDE": "de",
    "esES": "es",
}

# Representative Retail spells across all 13 classes and damage/heal mechanics
SPELLS = [
    # Druid
    (5176, "Druid", "Wrath"),
    (8921, "Druid", "Moonfire"),
    (93402, "Druid", "Sunfire"),
    (8936, "Druid", "Regrowth"),
    (774, "Druid", "Rejuvenation"),
    (1822, "Druid", "Rake"),
    (5221, "Druid", "Shred"),
    (22568, "Druid", "Ferocious Bite"),
    (1079, "Druid", "Rip"),
    (285381, "Druid", "Primal Wrath"),
    (213771, "Druid", "Swipe"),
    # Mage
    (133, "Mage", "Fireball"),
    (11366, "Mage", "Pyroblast"),
    (116, "Mage", "Frostbolt"),
    (5143, "Mage", "Arcane Missiles"),
    (2120, "Mage", "Flamestrike"),
    # Priest
    (585, "Priest", "Smite"),
    (589, "Priest", "Shadow Word: Pain"),
    (2061, "Priest", "Flash Heal"),
    (139, "Priest", "Renew"),
    (15407, "Priest", "Mind Flay"),
    # Warlock
    (686, "Warlock", "Shadow Bolt"),
    (980, "Warlock", "Agony"),
    (172, "Warlock", "Corruption"),
    (234153, "Warlock", "Drain Life"),
    # Shaman
    (188196, "Shaman", "Lightning Bolt"),
    (188389, "Shaman", "Flame Shock"),
    (8004, "Shaman", "Healing Surge"),
    (61295, "Shaman", "Riptide"),
    # Paladin
    (20271, "Paladin", "Judgment"),
    (19750, "Paladin", "Flash of Light"),
    (85256, "Paladin", "Templar's Verdict"),
    # Rogue
    (1752, "Rogue", "Sinister Strike"),
    (196819, "Rogue", "Eviscerate"),
    (1943, "Rogue", "Rupture"),
    (32645, "Rogue", "Envenom"),
    # Warrior
    (1464, "Warrior", "Slam"),
    (12294, "Warrior", "Mortal Strike"),
    (23881, "Warrior", "Bloodthirst"),
    # Hunter
    (19434, "Hunter", "Aimed Shot"),
    (193455, "Hunter", "Cobra Shot"),
    (259495, "Hunter", "Wildfire Bomb"),
    # Death Knight
    (49143, "Death Knight", "Frost Strike"),
    (49998, "Death Knight", "Death Strike"),
    (47541, "Death Knight", "Death Coil"),
    # Monk
    (100780, "Monk", "Tiger Palm"),
    (107428, "Monk", "Rising Sun Kick"),
    (116670, "Monk", "Vivify"),
    # Demon Hunter
    (162794, "Demon Hunter", "Chaos Strike"),
    (198013, "Demon Hunter", "Eye Beam"),
    # Evoker
    (361469, "Evoker", "Living Flame"),
    (357208, "Evoker", "Fire Breath"),
    (355913, "Evoker", "Emerald Blossom"),
]


def eval_formula_token(expr: str) -> str:
    """Replace a Wowhead spell formula expression with a realistic numeric value."""
    stat_pat = r"\(\[?([\d.]+)%\s+(?:of|de|der|del)\s+[^)\]]+\]?\)"
    work = re.sub(
        stat_pat,
        lambda m: str(max(10, int(round(float(m.group(1)) * 5)))),
        expr,
    )
    stat_pat2 = r"\(([\d.]+)%\s+(?:of|de|der|del)\s+[^)]+\)"
    work = re.sub(
        stat_pat2,
        lambda m: str(max(10, int(round(float(m.group(1)) * 5)))),
        work,
    )
    work = work.strip()
    if work.startswith("[") and work.endswith("]"):
        work = work[1:-1].strip()
    if work.startswith("(") and work.endswith(")"):
        work = work[1:-1].strip()

    # Evaluate safe arithmetic like "145 * 2" or "2 * 3"
    if re.fullmatch(r"[\d.\s+\-*/()]+", work):
        try:
            val = eval(work, {"__builtins__": {}}, {})
            if isinstance(val, (int, float)):
                if abs(val - round(val)) < 1e-6:
                    return str(int(round(val)))
                return f"{val:.1f}"
        except Exception:
            pass
    return "250"


def html_to_lines(tooltip_html: str) -> list[str]:
    """Convert Wowhead HTML tooltip payload into rendered in-game-like lines."""
    text = re.sub(r"<!--.*?-->", "", tooltip_html, flags=re.S)

    # Strip inline talent modifier callouts ([Talent: Effect]) that Wowhead appends
    text = re.sub(r"\s*\[<span class=['\"]q2['\"]>.*?</span>\]", "", text, flags=re.S)

    # Strip conditional wrappers like {?a12345[{...}][{...}]} keeping the first branch
    text = re.sub(r"\{\?[^{}\[]+\[\{([^}]*)\}\]\[?\{?[^}]*\}?\]?\}?", r"\1", text)

    # Replace percentage-of-stat tokens first (EN: of, FR: de, DE: der, ES: del)
    text = re.sub(
        r"\(\[?([\d.]+)%\s+(?:of|de|der|del)\s+[^)\]]+\]?\)",
        lambda m: str(max(10, int(round(float(m.group(1)) * 5)))),
        text,
    )
    text = re.sub(
        r"\(([\d.]+)%\s+(?:of|de|der|del)\s+[^)<]+\)",
        lambda m: str(max(10, int(round(float(m.group(1)) * 5)))),
        text,
    )
    # Strip Min/Max/Máx calls like [Min(20, 100)]
    text = re.sub(r"\[?(?:Min|Max|Mín|Máx)\([^)]+\)\]?", "20", text)
    # Evaluate arithmetic in brackets like [78 * 2] or [368 + 578] or [(817) + (197 * (10 + 0 + 0))]
    for _ in range(3):
        text = re.sub(
            r"\[([\d.\s+\-*/()]+)\]",
            lambda m: eval_formula_token(m.group(1)),
            text,
        )
        text = re.sub(
            r"\((\d+(?:\.\d+)?\s*[*/+-]\s*[\d.\s+\-*/()]+)\)",
            lambda m: eval_formula_token(m.group(1)),
            text,
        )
        text = re.sub(r"\((\d+(?:\.\d+)?)\)", r"\1", text)

    # Convert structural tags into newlines
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"</(?:div|tr|p|li|table)>", "\n", text, flags=re.I)
    text = re.sub(r"<t[dh][^>]*>", " ", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    # Replace NBSP with normal space for readability, keeping line breaks
    text = text.replace("\u00a0", " ")

    lines = []
    for raw in text.splitlines():
        cleaned = re.sub(r"\s+", " ", raw).strip()
        if cleaned:
            lines.append(cleaned)
    return lines


def fetch_one(spell_id: int, spell_class: str, en_name: str, loc_code: str, wh_loc: str) -> dict:
    url = f"https://nether.wowhead.com/tooltip/spell/{spell_id}?dataEnv=1&locale={wh_loc}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (CastMetrics test runner)"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            tooltip_html = data.get("tooltip") or ""
            return {
                "spellID": spell_id,
                "class": spell_class,
                "enName": en_name,
                "locale": loc_code,
                "name": data.get("name") or en_name,
                "lines": html_to_lines(tooltip_html),
                "ok": bool(tooltip_html),
            }
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            if attempt == 2:
                return {
                    "spellID": spell_id,
                    "class": spell_class,
                    "enName": en_name,
                    "locale": loc_code,
                    "name": en_name,
                    "lines": [],
                    "ok": False,
                    "error": str(exc),
                }
            time.sleep(0.5 * (attempt + 1))


def lua_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "")
    )


def write_lua_corpus(records: list[dict], out_path: Path) -> None:
    lines = ["return {"]
    for rec in records:
        if not rec["ok"]:
            continue
        lines.append("\t{")
        lines.append(f'\t\tspellID = {rec["spellID"]},')
        lines.append(f'\t\tclass = "{lua_escape(rec["class"])}",')
        lines.append(f'\t\tenName = "{lua_escape(rec["enName"])}",')
        lines.append(f'\t\tlocale = "{rec["locale"]}",')
        lines.append(f'\t\tname = "{lua_escape(rec["name"])}",')
        lines.append("\t\tlines = {")
        for line in rec["lines"]:
            lines.append(f'\t\t\t"{lua_escape(line)}",')
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    out_dir = Path(__file__).resolve().parent
    records: list[dict] = []

    tasks = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for spell_id, spell_class, en_name in SPELLS:
            for loc_code, wh_loc in LOCALES.items():
                tasks.append(pool.submit(fetch_one, spell_id, spell_class, en_name, loc_code, wh_loc))
        for fut in as_completed(tasks):
            records.append(fut.result())

    loc_order = {k: idx for idx, k in enumerate(LOCALES)}
    records.sort(key=lambda r: (loc_order.get(r["locale"], 99), r["class"], r["spellID"]))

    (out_dir / "corpus.json").write_text(
        json.dumps(records, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    write_lua_corpus(records, out_dir / "corpus_data.lua")

    ok_count = sum(1 for r in records if r["ok"])
    fail_count = len(records) - ok_count
    print(f"Fetched {ok_count}/{len(records)} tooltips ({fail_count} failed).")
    for r in records:
        if not r["ok"]:
            print(f"  FAIL [{r['locale']}] {r['spellID']} ({r['enName']}): {r.get('error')}")


if __name__ == "__main__":
    main()
