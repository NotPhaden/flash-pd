# Supabase – procedură de migrare controlată (FLASH RP)

## Model canonic

- Gradul curent al unui membru: `officers.rank_id` → `ranks.id`.
- Identitatea contului: `officers.user_id` → `auth.users.id`.
- Permisiuni explicite: `user_roles.role`.
- Apartenențe multiple: `officer_departments`; `officers.department_id` rămâne departamentul principal compatibil.
- Istoric: `officer_promotions`. `officer_ranks` este păstrat ca tabel legacy și nu trebuie folosit pentru afișarea gradului curent.
- Realtime: `officers`, `ranks`, `user_roles`, `departments`.

Nu transforma automat un grad în rol administrativ. Rolurile administrative/instructor/unitate sunt permisiuni distincte; politicile RLS și funcțiile RPC rămân autoritatea finală.

## Înainte de migrare

1. Folosește un proiect Supabase staging sau creează un branch/database branch.
2. Din Supabase Dashboard → Database → Backups creează un backup complet sau folosește `supabase db dump` (schema + data). Exportă separat setările Auth, utilizatorii/identitățile dacă este necesar și Storage.
3. În SQL Editor rulează `00_backup_existing_data.sql`. Acesta creează o copie logică a tabelelor din `public` în schema `flash_backup_20261109`. Este o plasă de siguranță pentru rânduri, NU înlocuiește backup-ul complet: nu copiază funcții, politici, trigger-e, setări Auth sau obiecte Storage.
4. Rulează interogările de diagnostic din `01_canonical_rank_realtime_repair.sql` pe staging mai întâi și verifică duplicatele `officers.user_id`.

## Aplicare pentru o instalare FLASH deja existentă

Migrările istorice din `supabase/` nu sunt un lanț automat sigur: unele se suprapun și înlocuiesc aceleași funcții/politici. Nu le executa pe toate din nou.

1. Compară migrările deja aplicate în Supabase → Database → Migrations (sau istoricul CLI) cu fișierele din arhivă.
2. Dacă lipsesc obiecte necesare frontend-ului, aplică numai migrările lipsă, în ordinea cerută de README-ul corespunzător. Pentru pachetul complet FLASH, documentația istorică a indicat: `rp_accounts_migration.sql`, `flash_corrective_migration.sql`, `flash_functional_fixes.sql`, `sas_dcco_units_migration.sql`, `flash_profile_actions_migration.sql`, `flash_member_profile_inventory_fix.sql`, apoi `flash_final_permissions_departments_profile.sql`, `flash_verified_permissions_repair.sql`, `flash_auth_instructor_access_fix.sql`, `flash_rank_department_access_sync.sql`, `flash_v2_complete_repairs.sql` (unele pot fi deja incluse/aplicate; verifică definițiile înainte de execuție).
3. După ce tabelele/funcțiile cerute există, rulează `01_canonical_rank_realtime_repair.sql`.
4. RPC-ul `save_officer_record_with_career` este folosit de interfață pentru a salva\n   într-o singură tranzacție datele personale, gradul, departamentele și istoricul.\n   Verifică manual rezultatul pentru fiecare cont și grad; nu șterge `officer_ranks`, `officer_promotions` sau `user_roles`.

**Atenție:** lista de mai sus este o hartă a fișierelor istorice, nu o comandă de a le rula orbește. `schema.sql` este pentru un proiect nou/curat; nu îl rula peste baza existentă. Pe o instalare nouă, pornește cu `schema.sql`, apoi aplică numai pachetele de migrare necesare pentru tabelele și funcțiile suplimentare, în staging.

## Verificări după aplicare

Rulează query-urile de la finalul `01_canonical_rank_realtime_repair.sql` și verifică:

- fiecare `officers.user_id` este unic și corespunde contului Auth corect;
- fiecare `officers.rank_id` fie este NULL intenționat, fie indică exact un rând din `ranks`;
- modificarea lui `officers.rank_id` în Table Editor este vizibilă după evenimentul Realtime;
- modificarea `ranks.name`/`ranks.level` actualizează eticheta/nivelul în dashboard;
- modificările `user_roles` reîncarcă permisiunile contului;
- un utilizator obișnuit nu poate acorda singur grade/roluri prin RPC sau API;
- conturile nou create primesc rolul inițial `visitor` conform versiunii finale a funcției `provision_flash_rp_account`;
- RLS pentru toate tabelele operaționale și Storage este verificat separat.

## Configurarea aplicației

Copiază `.env.example` în `.env.local` și setează:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

Folosește numai cheia anon/publishable în browser. Nu folosi `service_role`/secret key în variabile `NEXT_PUBLIC_*`, cod client sau Git.

## Ce trebuie furnizat pentru testarea conexiunii reale

Pentru validare live este suficient un acces controlat la un proiect **staging** Supabase:
- Project URL și cheia publishable/anon pentru rularea frontend-ului local;
- acces SQL Editor sau un dump de schemă anonimizat;
- un cont de test cu rol obișnuit și un cont administrator de test;
- confirmarea migrărilor deja aplicate.

Nu trimite parola contului personal, cheia `service_role`, token-uri JWT sau date personale reale. Preferă un branch/staging și credențiale temporare cu permisiuni minime.

## Policegram și repararea finală a accesului SAS/DCCO

După migrațiile FLASH deja aplicate, rulează `policegram_and_final_access_fix.sql` în Supabase SQL Editor. Migrarea:
- repară funcțiile de acces pentru SAS și DCCO pe baza rolului, gradului și tuturor departamentelor asociate;
- permite conducerii SAS/DCCO să administreze documentele unității proprii și să consulte rosterul corect;
- creează tabelele Policegram pentru postări, comentarii și aprecieri;
- creează bucket-ul public `policegram-media` cu upload autentificat și politici RLS.

Policegram este disponibil conturilor autentificate, inclusiv conturilor cu rol Vizitator/Academie. Feed-ul permite imagini și videoclipuri, comentarii, like-uri și un Top 5 după numărul total de aprecieri primite.

## Corecție finală Conducere SAS/DCCO și moderare Policegram

Rulează `policegram_moderation_and_sas_dcco_departments_fix.sql` după migrațiile Policegram și departamente. Migrarea mută membrii care aveau gradele Conducere SAS/DCCO în departamentele omonime, elimină acele două grade din tabelul de grade, aliniază permisiunile SAS/DCCO la apartenența la departamente și adaugă moderarea Policegram pentru Chestor general și Chestor secundar (ștergere postări și interdicții de publicare).
