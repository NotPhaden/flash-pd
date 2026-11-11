# Raport de audit tehnic – Kromix Police Department Panel

## Domeniul inspectat
- Cod Next.js/React: `app/`, `components/`, `lib/`.
- Configurație: `package.json`, `tsconfig.json`, configurația Tailwind/Next.
- Toate cele 14 fișiere SQL din `supabase/`.
- Documentația existentă README.
- Arhiva includea și `node_modules`, `.next`, `.git` și `.env`; acestea nu sunt incluse în arhiva reparată. `.env` poate conține chei și nu trebuie distribuit.

## Dependențe DB identificate în frontend
Tabele accesate direct: `absence_requests`, `academy_applications`, `action_forms`,
`action_participants`, `action_templates`, `activities`, `attendance`,
`certificate_applications`, `dcco_reports`, `departments`, `instructor_forums`,
`notifications`, `officer_certificates`, `officer_departments`,
`officer_promotions`, `officers`, `ranks`, `rp_accounts`, `sanctions`, `unit_documents`,
`user_roles`. Storage: bucket `avatars`. Aplicația mai folosește RPC-uri pentru
administrarea carierei, editarea personalului, profil și permisiuni.

## Probleme și riscuri constatate
1. **Migrări suprapuse / istoric dificil de urmărit.** `schema.sql` include deja
   extensii ulterioare, iar alte fișiere (`flash_corrective_migration.sql`,
   `flash_functional_fixes.sql`, `flash_repair_bundle.sql`,
   `flash_verified_permissions_repair.sql`, `flash_v2_complete_repairs.sql`,
   `flash_rank_department_access_sync.sql` etc.) înlocuiesc funcții și politici
   din versiuni anterioare. README-urile istorice cer ordini diferite. Aplicarea
   tuturor fișierelor fără verificarea stării reale poate crea conflicte sau
   politici redundante.
2. **Gradul și rolul sunt două concepte distincte.** Frontend-ul citește gradul
   curent din `officers.rank_id -> ranks.id`, dar folosește `user_roles.role`
   pentru permisiunile explicite și apoi deduce unele roluri de unitate din grad
   și departament. `officer_ranks` este o structură suplimentară care poate
   induce ambiguitate; codul curent folosește `officers.rank_id` pentru afișare.
   `officer_promotions` este jurnalul schimbărilor de carieră.
3. **Sincronizarea Realtime era incompletă în frontend.** Existau ascultători
   pentru `officers` și `notifications`, dar nu pentru `ranks` și `user_roles`.
   Modificarea numelui/nivelului unui grad în `ranks` nu produce automat UPDATE
   în `officers`, deci join-ul putea rămâne învechit în UI.
4. **Politicile RLS au evoluat în mai multe fișiere.** Funcțiile precum
   `is_Kromix_leadership`, `is_Kromix_top_command`, `has_role` și procedurile RPC
   trebuie păstrate coerente. Ascunderea elementelor de meniu în frontend nu
   este control de securitate; decizia finală trebuie să rămână în SQL/RLS/RPC.
5. **Tabele istorice și funcționale.** `officer_ranks` și `officer_promotions`
   nu trebuie șterse pentru a rezolva afișarea gradului. Datele de carieră se
   păstrează, iar `officers.rank_id` rămâne relația pentru gradul curent.
6. **Nu există acces la proiectul Supabase live în acest mediu.** Nu au fost
   inspectate datele reale, setările Auth, politicile instalate efectiv,
   publication membership sau Storage. Nu se poate confirma migrarea live.

## Modificări efectuate în această arhivă
- `components/Dashboard.tsx`: refresh pentru personal și profilul contului curent
  la evenimente Realtime din `ranks` și `user_roles`, pe lângă `officers`.
- `lib/supabase.ts`: configurare explicită pentru sesiune persistentă,
  refresh automat al tokenului și detectarea callback-ului Auth; un singur client.
- `supabase/00_backup_existing_data.sql`: backup logic al tabelelor din schema
  `public` într-o schemă separată, fără ștergere sau modificare a surselor.
- `supabase/01_canonical_rank_realtime_repair.sql`: indexuri utile, actualizare
  `updated_at`, politică de citire pentru catalogul de grade și includerea
  tabelelor relevante în `supabase_realtime`; diagnostic pentru duplicatele
  `officers.user_id`.
- `README.md` și `supabase/README-MIGRATIONS-RO.md`: pași de instalare și
  limitările verificării.

## Verificări executate
- `tsc --noEmit`: **PASS** (codul TypeScript compilează).
- `next build`: **NEFINALIZAT**. Next.js 14.2.35 a încercat să descarce
  `@next/swc-linux-x64-gnu`, dar mediul nu a avut acces DNS/rețea la
  `registry.npmjs.org`. Nu este raportat ca build reușit.
- SQL: verificare statică a fișierelor și a referințelor; **nu** a fost executat
  împotriva unei instanțe PostgreSQL/Supabase.
- Fluxuri Auth/RLS/Realtime: **neconfirmate live**, necesită proiect Supabase
  sau un proiect staging.

## Decizii de migrare
Nu se face DROP/DELETE de tabele, coloane sau utilizatori. Nu se unifică automat
`user_roles` cu `ranks`: ar amesteca permisiunile cu ierarhia profesională.
Nu se copiază chei secrete în frontend sau în arhiva livrată.
