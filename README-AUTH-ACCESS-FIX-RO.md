# FLASH RP – corecție autentificare și acces

Această actualizare repară înregistrarea conturilor noi și accesul la pagina Instructori.

## Fișiere modificate
- `components/Dashboard.tsx`: ID-ul RP nu mai are limita artificială de 32 caractere; noile conturi folosesc un email sintetic determinist bazat pe SHA-256, iar autentificarea păstrează fallback pentru conturile vechi.
- `components/Dashboard.tsx`: pagina Instructori apare doar instructorilor RADIO/MDT/FINAL/HELI/HS și personalului de la Comisar în sus.
- `components/Dashboard.tsx`: membrii cu gradul exact `Academie` văd doar Academie, Profil și Notificări.
- `components/FeatureSections.tsx`: categoria instructorului este determinată și din departamentele asociate, nu doar din rolurile vechi.
- `supabase/flash_auth_instructor_access_fix.sql`: un singur trigger de provisioning, rol inițial Visitor și politici RLS pentru dosarele instructorilor.

## Aplicare
1. Fă backup bazei Supabase.
2. Rulează `supabase/flash_auth_instructor_access_fix.sql` o singură dată în SQL Editor.
3. Publică frontend-ul din arhivă.
4. Testează înregistrarea cu un ID nou și apoi autentificarea atât cu un cont nou, cât și cu unul vechi.

Nu șterge utilizatorii existenți. Conturile vechi continuă să se autentifice prin emailul sintetic vechi; conturile noi folosesc formatul hash.

## Notă
Nu a fost posibilă rularea build-ului TypeScript în acest mediu deoarece instalarea dependențelor a expirat. Testează pe staging înainte de producție.
