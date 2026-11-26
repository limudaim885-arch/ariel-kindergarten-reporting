<div dir="rtl">

# האפליקציה: דיווח הגנים

אפליקציית Next.js (App Router, TypeScript) שמתפרסמת ב-Vercel בכתובת https://ariel-reporting.vercel.app. הנתונים והכניסה ב-Supabase. ההנחיות המלאות לפיתוח נמצאות ב-[CLAUDE.md](../CLAUDE.md).

## הרצה מקומית
```
npm install
cp .env.example .env.local    # ולמלא את שלושת הערכים מ-Supabase
npm run dev                   # http://localhost:3000
```
`.env.local` לא נשמר בריפו. `SUPABASE_SERVICE_ROLE_KEY` משמש רק בצד השרת.

## בדיקות לפני Pull Request
```
npx next typegen && npx tsc --noEmit   # טיפוסים
npm run lint                           # ESLint
npm run build                          # בנייה מלאה
```

## מבנה
```
src/app/login, auth/       כניסה: ספק וגננת עם SMS, צוות עם Microsoft
src/app/supplier/          מסכי הספק: בית, דיווח חדש, הדיווחים שלי
src/app/teacher/           מסכי הגננת: תיבת אישורים, בדיקה ואישור, דיווחים שטופלו
src/app/staff/             מסכי הרפרנטית (בבנייה)
src/app/api/health/        בדיקת זמינות (כולל חיבור למסד)
src/components/            רכיבים משותפים: מבנה עמוד, תפריט, כרטיסים, סטטוסים
src/lib/auth/              סשן, הרשאות ותהליך הכניסה
src/lib/supabase/          חיבורים ל-Supabase (סשן משתמש, ומפתח שרת)
src/lib/supplier, teacher/ קריאת הנתונים של כל תפקיד והטיפוסים שלהם
src/lib/csp.ts             מדיניות האבטחה של הדפדפן (CSP)
src/lib/rate-limit.ts      הגבלת קצב לפעולות רגישות
src/proxy.ts               רץ לפני כל בקשה: רענון סשן, CSP וחסימת עמודים למי שלא נכנס
scripts/provision-users.ts פתיחת משתמשים ב-Supabase Auth (npm run provision)
```

## עקרונות
- הדפדפן לא פונה למסד. כל קריאה עוברת בשרת, דרך פונקציות בסכמה `access` (ראו [database/](../database/)).
- המשתמש מזוהה תמיד לפי הסשן בשרת, אף פעם לפי מזהה שמגיע מהדפדפן.
- בלי עיצוב inline (`style=`), כי ה-CSP חוסם אותו. העיצוב ב-Tailwind, והצבעים מוגדרים ב-`src/app/globals.css`.
- גרסת Next.js כאן חדשה, ויש בה שינויים לעומת גרסאות קודמות. ראו [AGENTS.md](AGENTS.md).

</div>
