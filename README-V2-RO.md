# FLASH Police Panel – corecții v2

Această versiune include corecții pentru încărcarea avatarului/fundalului, grade distincte de instructor, certificatele Radio/MDT/Heli/Moto/HS, accesul DCCO/SAS, statisticile acțiunilor, conturile Vizitator și istoricul UP/DOWN.

## Pași obligatorii pentru Supabase

1. Fă backup bazei de date.
2. Verifică faptul că migrările FLASH anterioare sunt deja aplicate (inclusiv `flash_final_permissions_departments_profile.sql`, `flash_verified_permissions_repair.sql`, `flash_profile_actions_migration.sql` și `sas_dcco_units_migration.sql`).
3. În Supabase → SQL Editor, rulează **o singură dată**, la final, `supabase/flash_v2_complete_repairs.sql`.
4. Verifică în Storage că există bucket-ul public `avatars` și că upload-ul se face în folderul cu UUID-ul utilizatorului.
5. Publică aplicația cu variabilele `NEXT_PUBLIC_SUPABASE_URL` și `NEXT_PUBLIC_SUPABASE_ANON_KEY` din proiectul tău.

Nu rula `schema.sql` peste o bază de date existentă. Migrarea v2 este incrementală și trebuie aplicată după migrările FLASH anterioare.

## Teste recomandate după migrare

- Cont nou: rol și grad `Vizitator`; vede doar Academia, Profilul și Notificările.
- Profil: încarcă JPG/PNG/WebP/GIF atât pentru fotografie, cât și pentru fundal; reîncarcă pagina și verifică persistența.
- Personal: modifică data intrării, acordă/revocă fiecare certificat și verifică salvarea.
- Instructori: fiecare rol de instructor vede doar aplicațiile certificatului corespunzător.
- DCCO/SAS: atribuie persoana departamentului corect și verifică pagina, documentele și lista membrilor.
- Acțiuni: creează o acțiune și participă la una; verifică separat statisticile din profil.
- UP/DOWN: testează cu un cont Chestor secundar sau Chestor general; verifică istoricul și datele afișate în profil.

## Verificare locală

Verificarea TypeScript se poate rula cu `npx tsc --noEmit`. Build-ul Next.js necesită binarul SWC pentru sistemul de operare pe care rulează; arhiva sursă nu include `node_modules` sau `.next`.
