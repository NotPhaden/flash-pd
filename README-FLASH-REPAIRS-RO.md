# FLASH RP – pachet reparații

## Ce include
- Corectarea funcției `manage_officer_career`: UP/DOWN blochează doar rândul din `officers`, evitând eroarea PostgreSQL `FOR UPDATE cannot be applied to the nullable side of an outer join`.
- Departamentele de instructori RADIO, MDT, FINAL, HELI și HS.
- Migrarea membrilor cu rolurile istorice de instructor în departamentele corespunzătoare.
- Verificări de acces la certificate în funcție de categoria instructorului.
- Tabel și pagină `Instructori` pentru dosare cu candidat, CNP, decizie și dovadă video/link.
- Pagina de audit redenumită `Logs`.
- Activitatea săptămânală calculată de la `joined_at` (S1 începe la data intrării), nu ca fereastră mobilă de 28 de zile.

## Instalare
1. Fă backup bazei Supabase.
2. În Supabase SQL Editor rulează `supabase/flash_repair_bundle.sql` o singură dată.
3. Configurează variabilele `NEXT_PUBLIC_SUPABASE_URL` și `NEXT_PUBLIC_SUPABASE_ANON_KEY` conform `.env.example`.
4. Instalează dependențele cu `npm ci` și pornește cu `npm run dev` sau construiește cu `npm run build`.

## Atenție
- Nu este inclus fișierul `.env` și nu trebuie publicate cheile secrete.
- Proiectul folosește în continuare rolurile istorice `instructor_*` pentru compatibilitate și permisiuni; departamentele devin clasificarea vizibilă în structura de personal.
- Categoria `FINAL` este asociată rolului istoric `instructor_moto`, deoarece schema existentă nu avea un rol `instructor_final`.
- Build-ul Next.js nu a putut fi executat în mediul de lucru deoarece pachetul SWC nativ nu era disponibil offline. Verificarea TypeScript (`tsc --noEmit`) a trecut.
- Rulează migrarea întâi pe o bază de test și verifică politicile RLS înainte de producție.
