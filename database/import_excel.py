# -*- coding: utf-8 -*-
"""
import_excel.py  |  מערכת דיווח גנים, אריאל, שלב א'
--------------------------------------------------------------
קורא את שני קבצי האקסל של דבורה, מנקה, ומפיק:
  1. 04_import_data.sql      : רק השורות התקינות, להרצה על מסד הייצור
  2. דחויים_לתיקון.xlsx      : כל שורה שלא נכנסה + אזהרות, לצופיה

עיקרון: כפילות או ערך לא בטוח = לא נכנס. עדיף לדחות ולתקן מאשר להכניס טעות.
אחרי שצופיה מתקנת את האקסל, מריצים שוב את הסקריפט.

הרצה:
  pip install pandas pyxlsb openpyxl
  python import_excel.py <טבלה_מרכזת.xlsb> <פרטי_מפעילים.xlsb> [תיקיית_פלט]
"""
import re
import sys
import json
from difflib import SequenceMatcher
from pathlib import Path

import pandas as pd

SCHOOL_YEAR_ID = 2026          # תשפ"ו. ראו נקודה פתוחה במילון הנתונים
SCHOOL_YEAR_START = "2025-09-01"

# ---------------------------------------------------------------- תחומים
# סדר חשוב רק לקריאות. שורה שמתאימה ליותר מתחום אחד = לא חד משמעית = נדחית.
DOMAINS = {
    "ריתמיקה":         ["ריתמיקה", "רתמיקה", "ריתמקה", "רייתמיקה", "ריתמוסיקה", "ריתוסיקה", "רתמוזיקה"],
    "מוזיקה":          ["מוזיקה", "מוסיקה", "מוזיקלי", "זמר", "שירה", "שירים", "אקורדיון", "תיפוף", "טיפוף"],
    "תיאטרון ודרמה":   ["תאטרון", "תיאטרון", "דרמה", "הצגה", "הצגות", "הצגהבעלות", "אגדתא", "בובות", "סיפור", "שבלולה", "מופע"],
    "תנועה וספורט":    ["תנועה", "תנעה", "ספורט", "התעמלות", "חינוך גופני", "פעילות גופנית", "גימבורי", "ריקוד", "ריקודי",
                        "מחול", "קפוארה", "קאפוארה", "לנוע", "הנעה", "קרקס"],
    "יוגה":            ["יוגה"],
    "חיות וטבע":       ["חיות", "טבע", "בעלי חיים"],
    "מדע":             ["מדע", "מדעים", "מדעית", "אלקטרוניקה"],
    "גינון וקיימות":   ["גינון", "גינה", "גינו", "גנן", "חקלאות", "צמחים", "קיימות", "פיסול באדמה"],
    "יצירה ואומנות":   ["קרמיקה", "קארמיקה", "פסיפס", "ספיפס", "יצירה", "מלאכה", "מלאכות", "מלאכת", "חימר", "אומנות", "בועות סבון"],
    "יהדות ומסורת":    ["בית מדרש", "רב גן", "יהדות", "מסורת", "חגים", "חגיגה עברית"],
    "מסיבות":          ["מסיבה", "מסיבות", "מסיבת"],
    "הסעות וטיולים":   ["הסעה", "טיול", "סיור", "משחקיה"],
}
# ביטויים שמכילים מילת מפתח אבל לא מעידים על תחום
DOMAIN_STOP = ["חוג נוסף", "חוג ותנועה"]

TALAN_KW = ["יתרה", "ביתרה", "יתרת", "יתרות", "מיתרת", "מיתרות", "תלן", "תל\"ן", "תוספת", "סוף השנה", "סוף שנה", "סוף הנה", "חוג נוסף", "שנוסף"]
ONETIME_KW = ["חד\"פ", "חדפ", "חד פעמי", "חד פעמית", "חד:\"פ", "באישור", "באשור", "טיול", "הסעה", "סיור"]

ENGAGEMENT_TYPES = {"ANNUAL": 1, "ONE_TIME": 2, "TALAN_SURPLUS": 3}


def norm_text(x):
    if x is None or (isinstance(x, float) and pd.isna(x)):
        return None
    s = re.sub(r"\s+", " ", str(x)).strip()
    return s or None


def norm_name(x):
    s = norm_text(x)
    if not s:
        return None
    return re.sub(r"\s*-\s*$", "", re.sub(r"\s*-\s*", "-", s))


def name_key(x):
    s = norm_text(x) or ""
    return re.sub(r"[^\u0590-\u05FFa-zA-Z0-9]", "", s)


def phones_in(x):
    """מחזיר רשימת מספרי נייד תקינים מתוך תא. 9 ספרות שמתחילות ב-5 = אפס מוביל שנפל באקסל."""
    s = norm_text(x)
    if not s:
        return [], None
    s = re.sub(r"\.0$", "", s)
    chunks = re.findall(r"\+?\d[\d\-\s]{7,14}\d", s)
    out, bad = [], []
    for c in chunks:
        d = re.sub(r"\D", "", c)
        if d.startswith("972"):
            d = "0" + d[3:]
        if len(d) == 9 and d.startswith("5"):
            d = "0" + d
        if re.fullmatch(r"05\d{8}", d):
            out.append(d)
        else:
            bad.append(c)
    if bad or not out:
        return out, s
    return out, None


def to_num(x):
    if x is None or (isinstance(x, float) and pd.isna(x)):
        return None
    try:
        v = float(str(x).replace(",", "").strip())
        return v
    except ValueError:
        return "BAD"


def code6(x):
    if x is None or (isinstance(x, float) and pd.isna(x)):
        return None, "חסר"
    s = re.sub(r"\.0$", "", str(x).strip())
    if re.fullmatch(r"\d{6}", s):
        return s, None
    return None, f"סמל גן לא בן 6 ספרות: {s}"


def supplier_no(x):
    if x is None or (isinstance(x, float) and pd.isna(x)):
        return None
    s = re.sub(r"\.0$", "", str(x).strip())
    return s if re.fullmatch(r"\d{6}", s) else None   # כל מספרי הספק בקבצים הם 6 ספרות


def classify(text):
    t = norm_text(text) or ""
    hits = set()
    tt = t
    for stop in DOMAIN_STOP:
        tt = tt.replace(stop, " ")
    # "ריתמוסיקה" / "רתמוזיקה" הם ריתמיקה, לא ריתמיקה + מוזיקה
    for rv in ["ריתמוסיקה", "רתמוזיקה", "ריתוסיקה"]:
        tt = tt.replace(rv, "ריתמיקה")
    for dom, kws in DOMAINS.items():
        if any(k in tt for k in kws):
            hits.add(dom)
    # "תנועה" בתוך "ריתמיקה ותנועה" וכו' = שני תחומים אמיתיים, נשאר לא חד משמעי
    if any(k in t for k in TALAN_KW):
        etype = "TALAN_SURPLUS"
    elif any(k in t for k in ONETIME_KW):
        etype = "ONE_TIME"
    else:
        etype = "ANNUAL"
    return hits, etype


def sql_str(v):
    if v is None:
        return "NULL"
    return "N'" + str(v).replace("'", "''") + "'"


def sql_num(v):
    return "NULL" if v is None else (f"{v:.2f}" if isinstance(v, float) else str(v))


# =====================================================================
def main(central_path, details_path, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    central_name = Path(central_path).name
    details_name = Path(details_path).name

    rejects = []    # (קובץ, שורה, ישות, סיבה, ערכים)
    warnings = []   # (קובץ, שורה, ישות, אזהרה)

    def clean(raw):
        return {k: (None if (isinstance(v, float) and pd.isna(v)) else v) for k, v in raw.items()} if raw else raw

    def reject(file, row, entity, reason, raw=None):
        raw = clean(raw)
        rejects.append({"קובץ": file, "שורה באקסל": row, "ישות": entity, "סיבת הדחייה": reason,
                        "ערכים מקוריים": json.dumps(raw, ensure_ascii=False, default=str) if raw else ""})

    def warn(file, row, entity, text):
        warnings.append({"קובץ": file, "שורה באקסל": row, "ישות": entity, "אזהרה": text})

    # ---------------------------------------------------------- קריאה
    a = pd.read_excel(central_path, engine="pyxlsb", dtype=object)
    a.columns = [str(c).strip() for c in a.columns]
    a["_row"] = a.index + 2                       # מספר שורה כפי שמופיע באקסל
    b = pd.read_excel(details_path, engine="pyxlsb", dtype=object)
    b.columns = [str(c).strip().rstrip(":") for c in b.columns]
    b["_row"] = b.index + 2

    C_TARIFF_T = "עלות למפגש לפי הגננת"
    C_TARIFF = [c for c in a.columns if c.startswith("עלות למפגש לפי הספק")][0]
    C_MAX, C_ANNUAL = "מס מפגשים המקסימלי", "שנתי לספק"
    C_O1, C_O2 = "הזמנה 1", "הזמנה 2"

    # הסרת שורות ריקות ושורת סיכום (סכום בעמודה בודדת, בלי גן ובלי ספק)
    data_cols = ["סמל גן", "שם הגן", "שם המפעיל", "מספר ספק"]
    is_blank = a[data_cols].isna().all(axis=1)
    a = a[~is_blank].copy()

    # מילוי סמל גן / גננת כלפי מטה (באקסל הם מופיעים רק בשורה הראשונה של כל גן)
    a["_kg_first"] = a["סמל גן"].notna()
    for c in ["סמל גן", "שם הגן", "שם הגננת", "נייד גננת"]:
        a[c] = a[c].ffill()
    rows_read = len(a)

    # ---------------------------------------------------------- גנים
    kgs = {}          # code -> {name}
    bad_kg = set()
    kg_rows = a[a["_kg_first"]]
    by_code = {}
    for _, r in kg_rows.iterrows():
        code, err = code6(r["סמל גן"])
        raw = {"סמל גן": r["סמל גן"], "שם הגן": r["שם הגן"]}
        if err:
            reject(central_name, r["_row"], "גן", err, raw)
            bad_kg.add(str(r["סמל גן"]))
            continue
        by_code.setdefault(code, []).append(r)
    for code, rs in by_code.items():
        names = {norm_text(x["שם הגן"]) for x in rs}
        phones = {norm_text(x["נייד גננת"]) for x in rs}
        if len(rs) > 1 and (len(names) > 1 or len(phones) > 1):
            for x in rs:
                reject(central_name, x["_row"], "גן", f"סמל גן {code} מופיע פעמיים עם שם או נייד שונים",
                       {"שם הגן": x["שם הגן"], "שם הגננת": x["שם הגננת"], "נייד": x["נייד גננת"]})
            bad_kg.add(code)
            continue
        name = norm_text(rs[0]["שם הגן"])
        if not name:
            reject(central_name, rs[0]["_row"], "גן", "שם גן חסר", {"סמל גן": code})
            bad_kg.add(code)
            continue
        kgs[code] = {"name": name, "row": rs[0]["_row"]}

    # ---------------------------------------------------------- גננות
    teachers = {}     # phone -> {name, kgs:set}
    phone_names = {}
    for code, rs in by_code.items():
        if code not in kgs:
            continue
        r = rs[0]
        tname = norm_text(r["שם הגננת"])
        phones, badph = phones_in(r["נייד גננת"])
        raw = {"סמל גן": code, "שם הגננת": r["שם הגננת"], "נייד": r["נייד גננת"]}
        if not tname:
            reject(central_name, r["_row"], "גננת", "שם גננת חסר", raw); continue
        if "/" in tname or len(phones) > 1:
            reject(central_name, r["_row"], "גננת",
                   "שתי גננות או שני ניידים באותו תא, לא ניתן לשייך נייד לכל גננת בוודאות. יש לפצל לשתי שורות", raw)
            continue
        if badph or not phones:
            reject(central_name, r["_row"], "גננת", "נייד חסר או לא תקין (נדרשות 10 ספרות שמתחילות ב-05)", raw); continue
        ph = phones[0]
        phone_names.setdefault(ph, set()).add(name_key(tname))
        teachers.setdefault(ph, {"name": tname, "kgs": set(), "rows": []})
        teachers[ph]["kgs"].add(code)
        teachers[ph]["rows"].append(r["_row"])
    for ph, keys in phone_names.items():
        if len(keys) > 1:
            for row in teachers[ph]["rows"]:
                reject(central_name, row, "גננת", f"אותו נייד ({ph}) רשום לגננות בשמות שונים", {"נייד": ph})
            del teachers[ph]
    kg_with_teacher = {k for t in teachers.values() for k in t["kgs"]}
    for code, kg in kgs.items():
        if code not in kg_with_teacher:
            warn(central_name, kg["row"], "גן", f"לגן {code} ({kg['name']}) אין גננת עם נייד תקין. לא יהיה ניתן לאשר דיווחים עד שיתוקן")

    # ---------------------------------------------------------- ספקים
    det = {}
    for _, r in b.iterrows():
        sn = supplier_no(r.get("מספר ספק"))
        raw = {k: r.get(k) for k in ["מספר ספק", "שם הספק", "כתובת דוא\"ל", "נייד"]}
        if not sn:
            if norm_text(r.get("שם הספק")):
                reject(details_name, r["_row"], "ספק", "מספר ספק חסר או לא תקין", raw)
            continue
        if sn in det:
            reject(details_name, r["_row"], "ספק", f"מספר ספק {sn} מופיע פעמיים בקובץ הפרטים", raw)
            det[sn]["dup"] = True
            continue
        det[sn] = {"name": norm_name(r.get("שם הספק")), "email_raw": r.get("כתובת דוא\"ל"),
                   "phone_raw": r.get("נייד"), "row": r["_row"], "dup": False}

    a["_sn"] = [supplier_no(x) or "" for x in a["מספר ספק"]]
    sup_names_central = {}
    for _, r in a.iterrows():
        if r["_sn"]:
            sup_names_central.setdefault(r["_sn"], []).append((norm_name(r["שם המפעיל"]), r["_row"]))

    suppliers = {}      # sn -> {name, email}
    bad_sup = set()
    row_name_conflict = set()
    for sn in sorted(set(sup_names_central) | set(det)):
        if sn in det and det[sn]["dup"]:
            bad_sup.add(sn); continue
        canonical = det[sn]["name"] if sn in det else None
        names = [n for n, _ in sup_names_central.get(sn, []) if n]
        if not canonical:
            keys = {name_key(n) for n in names}
            if len(keys) == 1:
                canonical = names[0]
            else:
                # שמות שונים ואין קובץ פרטים להכריע
                base = names[0] if names else None
                if base and all(SequenceMatcher(None, name_key(base), name_key(n)).ratio() >= 0.8 for n in names):
                    canonical = max(set(names), key=names.count)
                else:
                    for n, row in sup_names_central.get(sn, []):
                        reject(central_name, row, "ספק", f"מספר ספק {sn} מופיע עם שמות שונים ואין לו שורה בקובץ הפרטים להכרעה", {"שם": n})
                    bad_sup.add(sn); continue
        # בדיקת התאמה של כל שורה בטבלה המרכזת לשם הקנוני
        ck = name_key(canonical)
        for n, row in sup_names_central.get(sn, []):
            nk = name_key(n)
            if not nk:
                continue
            ratio = SequenceMatcher(None, ck, nk).ratio()
            first = (norm_text(canonical) or "").split(" ")[0]
            if ratio < 0.6 and not (ck in nk or nk in ck) and not (len(first) > 2 and first in (n or "")):
                row_name_conflict.add(row)
        email = None
        if sn in det:
            e = norm_text(det[sn]["email_raw"])
            if e:
                e = e.strip("'\" ")
                if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", e):
                    email = e.lower()
                else:
                    reject(details_name, det[sn]["row"], "מייל ספק", "מייל לא תקין או שני מיילים באותו תא. הספק נכנס בלי מייל", {"מייל": e})
            else:
                warn(details_name, det[sn]["row"], "ספק", f"לספק {sn} אין מייל")
        else:
            warn(central_name, sup_names_central[sn][0][1], "ספק", f"ספק {sn} ({canonical}) לא מופיע בקובץ פרטי המפעילים: אין מייל")
        suppliers[sn] = {"name": canonical, "email": email}

    # ---------------------------------------------------------- אנשי קשר
    contacts = {}    # (sn, phone) -> name
    phone_owner = {}
    def add_contact(sn, phone, cname, file, row):
        phone_owner.setdefault(phone, set()).add(sn)
        contacts.setdefault((sn, phone), {"name": cname, "file": file, "row": row})

    for sn, d in det.items():
        if sn not in suppliers:
            continue
        phones, badph = phones_in(d["phone_raw"])
        if not phones:
            reject(details_name, d["row"], "איש קשר", "נייד חסר או לא תקין", {"נייד": d["phone_raw"]}); continue
        if len(phones) > 1 or badph:
            reject(details_name, d["row"], "איש קשר", "כמה מספרים או טקסט באותו תא. יש לפצל לשורה לכל איש קשר", {"נייד": d["phone_raw"]}); continue
        add_contact(sn, phones[0], suppliers[sn]["name"], details_name, d["row"])
    for _, r in a.iterrows():
        sn = r["_sn"]
        if not sn or sn not in suppliers or r["_row"] in row_name_conflict:
            continue
        phones, badph = phones_in(r["נייד ספק"])
        if len(phones) == 1 and not badph:
            add_contact(sn, phones[0], suppliers[sn]["name"], central_name, r["_row"])
    for ph, owners in phone_owner.items():
        if len(owners) > 1:
            for sn in owners:
                c = contacts.pop((sn, ph), None)
                if c:
                    reject(c["file"], c["row"], "איש קשר", f"אותו נייד ({ph}) רשום אצל כמה ספקים שונים: {', '.join(sorted(owners))}", {"נייד": ph})
    sup_with_contact = {sn for sn, _ in contacts}
    for sn, s in suppliers.items():
        if sn not in sup_with_contact:
            warn(details_name if sn in det else central_name, det[sn]["row"] if sn in det else sup_names_central[sn][0][1],
                 "ספק", f"לספק {sn} ({s['name']}) אין נייד תקין. לא יוכל להתחבר עד שיתוקן")

    # ---------------------------------------------------------- התקשרויות
    engagements, orders = [], []
    sig_rows = {}
    candidates = []
    for _, r in a.iterrows():
        if pd.isna(r["שם המפעיל"]) and pd.isna(r["מספר ספק"]):
            continue
        row = r["_row"]
        raw = {k: r.get(k) for k in ["סמל גן", "שם המפעיל", "מספר ספק", "תחום הפעלה", C_TARIFF_T, C_TARIFF, C_MAX, C_ANNUAL]}
        code, _ = code6(r["סמל גן"])
        sn = r["_sn"]
        if not code or code not in kgs:
            reject(central_name, row, "התקשרות", "הגן של השורה נדחה (ראו שורת הגן)", raw); continue
        if not sn:
            orig = norm_text(r["מספר ספק"])
            reason = "מספר ספק חסר" if not orig else f"מספר ספק לא תקין ({re.sub(r'[.]0$', '', orig)}): נדרשות 6 ספרות"
            reject(central_name, row, "התקשרות", reason, raw); continue
        if sn not in suppliers:
            reject(central_name, row, "התקשרות", "הספק של השורה נדחה (ראו שורת הספק)", raw); continue
        if row in row_name_conflict:
            reject(central_name, row, "התקשרות",
                   f"שם המפעיל בשורה לא תואם לשם של מספר ספק {sn} ({suppliers[sn]['name']}). ייתכן מספר ספק שגוי", raw); continue
        src = norm_text(r["תחום הפעלה"])
        if not src:
            reject(central_name, row, "התקשרות", "תחום הפעלה חסר", raw); continue
        doms, etype = classify(src)
        if len(doms) == 0:
            reject(central_name, row, "התקשרות", f"לא ניתן לזהות תחום מתוך \"{src}\"", raw); continue
        if len(doms) > 1:
            reject(central_name, row, "התקשרות", f"תחום לא חד משמעי: \"{src}\" מתאים ל-{' / '.join(sorted(doms))}", raw); continue
        tariff, tariff_t = to_num(r[C_TARIFF]), to_num(r[C_TARIFF_T])
        mx, annual = to_num(r[C_MAX]), to_num(r[C_ANNUAL])
        if tariff in (None, "BAD") or tariff <= 0:
            reject(central_name, row, "התקשרות", "עלות למפגש לפי ההסכם חסרה או לא מספרית", raw); continue
        if tariff_t not in (None, "BAD") and abs(tariff_t - tariff) > 0.005:
            reject(central_name, row, "התקשרות", f"עלות לפי הגננת ({tariff_t:g}) שונה מעלות לפי ההסכם ({tariff:g})", raw); continue
        if tariff_t in (None, "BAD"):
            warn(central_name, row, "התקשרות", "עלות לפי הגננת חסרה, לא ניתן לאמת מול ההסכם. נכנס לפי ההסכם")
        if mx in (None, "BAD") or mx <= 0 or mx != int(mx):
            reject(central_name, row, "התקשרות", "מספר מפגשים מקסימלי חסר או לא מספר שלם", raw); continue
        if annual in (None, "BAD") or annual <= 0:
            reject(central_name, row, "התקשרות", "שנתי לספק חסר או לא מספרי", raw); continue
        if abs(tariff * mx - annual) > 0.5:
            reject(central_name, row, "התקשרות", f"שנתי לספק ({annual:g}) לא שווה לעלות × מפגשים ({tariff * mx:g})", raw); continue
        sig = (code, sn, list(doms)[0], etype, round(tariff, 2), int(mx))
        sig_rows.setdefault(sig, []).append(row)
        candidates.append({"row": row, "code": code, "sn": sn, "domain": list(doms)[0], "etype": etype,
                           "tariff": round(tariff, 2), "max": int(mx), "annual": round(annual, 2), "src": src,
                           "o1": r[C_O1], "o2": r[C_O2]})
    dup_rows = {row for rows in sig_rows.values() if len(rows) > 1 for row in rows}
    for c in candidates:
        if c["row"] in dup_rows:
            others = [x for x in sig_rows[(c["code"], c["sn"], c["domain"], c["etype"], c["tariff"], c["max"])] if x != c["row"]]
            reject(central_name, c["row"], "התקשרות", f"שורה כפולה: זהה לשורה {', '.join(map(str, others))} (גן, ספק, תחום, תעריף ומפגשים)",
                   {"סמל גן": c["code"], "מספר ספק": c["sn"], "תחום": c["src"], "תעריף": c["tariff"], "מפגשים": c["max"]})
            continue
        engagements.append(c)
        total = 0.0
        for seq, key in ((1, "o1"), (2, "o2")):
            v = to_num(c[key])
            if v is None:
                continue
            if v == "BAD":
                reject(central_name, c["row"], "הזמנת עבודה", f"הזמנה {seq} מכילה טקסט ולא סכום", {f"הזמנה {seq}": c[key]}); continue
            if v <= 0:
                continue
            orders.append({"row": c["row"], "seq": seq, "amount": round(v, 2)})
            total += v
        if total > c["annual"] + 0.5:
            warn(central_name, c["row"], "התקשרות", f"סך ההזמנות ({total:,.0f}) גבוה מהתקציב השנתי ({c['annual']:,.0f}). לבדוק אם מכוון")
        if c["etype"] != "ANNUAL":
            warn(central_name, c["row"], "התקשרות", "התקשרות חד פעמית / תוספת מיתרה: אין במסד אישור מפקחת. לצרף אם קיים")

    # ---------------------------------------------------------- כתיבת SQL
    L = []
    w = L.append
    w("/* =====================================================================")
    w("   04_import_data.sql  |  נוצר אוטומטית ע\"י import_excel.py. לא לערוך ידנית.")
    w(f"   מקור: {central_name} ; {details_name}")
    w(f"   שנת לימודים: {SCHOOL_YEAR_ID}. להריץ אחרי 01 ו-03, בסביבת הייצור בלבד.")
    w("   ===================================================================== */")
    w("SET NOCOUNT ON;\nSET XACT_ABORT ON;\nBEGIN TRANSACTION;\n")

    w("-- ספקים")
    for sn, s in sorted(suppliers.items()):
        w(f"INSERT INTO core.Suppliers (SupplierNumber, Name, Email) VALUES ('{sn}', {sql_str(s['name'])}, {sql_str(s['email'])});")
    w("\n-- אנשי קשר לספקים (הראשון לכל ספק מסומן ראשי)")
    seen = set()
    for (sn, ph), c in sorted(contacts.items()):
        primary = 0 if sn in seen else 1
        seen.add(sn)
        w(f"INSERT INTO core.SupplierContacts (SupplierId, FullName, MobilePhone, IsPrimary) "
          f"SELECT SupplierId, {sql_str(c['name'])}, '{ph}', {primary} FROM core.Suppliers WHERE SupplierNumber = '{sn}';")
    w("\n-- גנים")
    for code, k in sorted(kgs.items()):
        w(f"INSERT INTO core.Kindergartens (KindergartenCode, Name) VALUES ('{code}', {sql_str(k['name'])});")
    w("\n-- גננות ושיבוצים")
    for ph, t in sorted(teachers.items()):
        w(f"INSERT INTO core.Teachers (FullName, MobilePhone) VALUES ({sql_str(t['name'])}, '{ph}');")
        for code in sorted(t["kgs"]):
            w(f"INSERT INTO core.TeacherAssignments (TeacherId, KindergartenId, ValidFrom) "
              f"SELECT t.TeacherId, k.KindergartenId, '{SCHOOL_YEAR_START}' FROM core.Teachers t, core.Kindergartens k "
              f"WHERE t.MobilePhone = '{ph}' AND t.IsActive = 1 AND k.KindergartenCode = '{code}';")
    w("\n-- התקשרויות")
    w("CREATE TABLE #eng (SrcRow INT, KgCode CHAR(6) COLLATE DATABASE_DEFAULT, SupplierNumber VARCHAR(10) COLLATE DATABASE_DEFAULT, "
      "Domain NVARCHAR(50) COLLATE DATABASE_DEFAULT, TypeId TINYINT, Tariff DECIMAL(10,2), MaxSessions SMALLINT, "
      "Annual DECIMAL(12,2), SourceNote NVARCHAR(300) COLLATE DATABASE_DEFAULT);")
    for i in range(0, len(engagements), 500):
        chunk = engagements[i:i + 500]
        w("INSERT INTO #eng VALUES")
        w(",\n".join(f"({c['row']}, '{c['code']}', '{c['sn']}', {sql_str(c['domain'])}, {ENGAGEMENT_TYPES[c['etype']]}, "
                     f"{c['tariff']:.2f}, {c['max']}, {c['annual']:.2f}, {sql_str(c['src'])})" for c in chunk) + ";")
    w(f"""INSERT INTO core.Engagements (SchoolYearId, SupplierId, KindergartenId, DomainId, EngagementTypeId,
       TariffPerSession, MaxSessions, AnnualBudget, SourceNote, SourceRowNumber)
SELECT {SCHOOL_YEAR_ID}, s.SupplierId, k.KindergartenId, d.DomainId, e.TypeId, e.Tariff, e.MaxSessions, e.Annual, e.SourceNote, e.SrcRow
FROM #eng e
JOIN core.Suppliers s     ON s.SupplierNumber = e.SupplierNumber
JOIN core.Kindergartens k ON k.KindergartenCode = e.KgCode
JOIN ref.ActivityDomains d ON d.NameHe = e.Domain;
IF @@ROWCOUNT <> {len(engagements)} THROW 50001, N'מספר ההתקשרויות שנכנסו לא תואם לצפוי', 1;""")
    w("\n-- הזמנות עבודה")
    if orders:
        w("CREATE TABLE #ord (SrcRow INT, Seq TINYINT, Amount DECIMAL(12,2));")
        for i in range(0, len(orders), 500):
            chunk = orders[i:i + 500]
            w("INSERT INTO #ord VALUES " + ",\n".join(f"({o['row']}, {o['seq']}, {o['amount']:.2f})" for o in chunk) + ";")
        w(f"""INSERT INTO core.WorkOrders (EngagementId, OrderSeq, Amount)
SELECT e.EngagementId, o.Seq, o.Amount
FROM #ord o JOIN core.Engagements e ON e.SourceRowNumber = o.SrcRow AND e.SchoolYearId = {SCHOOL_YEAR_ID};
IF @@ROWCOUNT <> {len(orders)} THROW 50002, N'מספר ההזמנות שנכנסו לא תואם לצפוי', 1;""")

    w("\n-- תיעוד הייבוא")
    w("DECLARE @batch INT;")
    w(f"INSERT INTO stg.ImportBatches (SourceFiles, RowsRead, RowsAccepted, RowsRejected) VALUES "
      f"({sql_str(central_name + '; ' + details_name)}, {rows_read}, {len(engagements)}, {len(rejects)});")
    w("SET @batch = SCOPE_IDENTITY();")
    for rj in rejects:
        w(f"INSERT INTO stg.RejectedRows (ImportBatchId, SourceFile, SourceRowNumber, Entity, Reason, RawValues) VALUES "
          f"(@batch, {sql_str(rj['קובץ'])}, {rj['שורה באקסל']}, {sql_str(rj['ישות'])}, {sql_str(rj['סיבת הדחייה'])}, {sql_str(rj['ערכים מקוריים'])});")
    w("\nCOMMIT TRANSACTION;")
    w("PRINT N'04_import_data.sql הושלם';")
    sql = "\n".join(L)
    (out_dir / "04_import_data.sql").write_text(sql, encoding="utf-8-sig")

    # ---------------------------------------------------------- קובץ דחויים לצופיה
    def readable(j):
        if not j:
            return ""
        return " | ".join(f"{k}: {'' if v is None else v}" for k, v in json.loads(j).items())
    rdf = pd.DataFrame(rejects, columns=["ישות", "קובץ", "שורה באקסל", "סיבת הדחייה", "ערכים מקוריים"])
    rdf["ערכים מקוריים"] = rdf["ערכים מקוריים"].map(readable)
    rdf["טופל?"] = ""
    rdf["הערה"] = ""
    wdf = pd.DataFrame(warnings, columns=["ישות", "קובץ", "שורה באקסל", "אזהרה"])
    with pd.ExcelWriter(out_dir / "דחויים_לתיקון.xlsx", engine="openpyxl") as xw:
        rdf.sort_values(["ישות", "שורה באקסל"]).to_excel(xw, sheet_name="דחויים", index=False)
        wdf.sort_values(["ישות", "שורה באקסל"]).to_excel(xw, sheet_name="אזהרות", index=False)
        for ws in xw.book.worksheets:
            ws.sheet_view.rightToLeft = True
            ws.freeze_panes = "A2"

    summary = {
        "שורות שנקראו מהטבלה המרכזת": rows_read,
        "גנים שנכנסו": len(kgs),
        "גננות שנכנסו": len(teachers),
        "ספקים שנכנסו": len(suppliers),
        "אנשי קשר לספקים": len(contacts),
        "התקשרויות שנכנסו": len(engagements),
        "הזמנות עבודה שנכנסו": len(orders),
        "שורות שנדחו": len(rejects),
        "אזהרות (נכנסו, לבדיקה)": len(warnings),
    }
    return summary, rejects, warnings, engagements


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    s, rj, wn, _ = main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ".")
    for k, v in s.items():
        print(f"{k}: {v}")
