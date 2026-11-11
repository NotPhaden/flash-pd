# Kromix Police Department Panel

Proiect Next.js existent, cu interfața și funcționalitățile originale păstrate. Modificările acestei livrări se concentrează pe sincronizarea Supabase/Auth/Realtime și pe o procedură de migrare nedistructivă.

## Instalare locală

1. Instalează Node.js 20+.
2. Rulează `npm ci`.
3. Copiază `.env.example` în `.env.local`.
4. Completează `NEXT_PUBLIC_SUPABASE_URL` și `NEXT_PUBLIC_SUPABASE_ANON_KEY` cu valorile proiectului Supabase.
5. Rulează `npm run dev`.

Pentru verificare: `npx tsc --noEmit`. Pentru build: `npm run build`.

## Supabase

Citește obligatoriu:
- `PROJECT_AUDIT_RO.md` – inventarul și constatările auditului.
- `supabase/README-MIGRATIONS-RO.md` – backup, ordinea migrărilor și verificări.

**Nu rula `supabase/schema.sql` peste o bază de date existentă.** Pentru o bază existentă, identifică întâi migrările aplicate, fă backup complet și aplică numai schimbările lipsă. Apoi rulează `00_backup_existing_data.sql` și `01_canonical_rank_realtime_repair.sql` conform instrucțiunilor.

## Grad și rol

`officers.rank_id` → `ranks.id` este sursa unică a gradului curent. `user_roles.role` rămâne sursa rolurilor de autorizare. `officer_promotions` păstrează istoricul; `officer_ranks` este păstrat pentru compatibilitate și nu este folosit ca grad curent de interfață.

## Securitate

Nu distribui `.env`, cheia `service_role`, token-uri sau date reale. Arhiva livrată exclude `.env`, `.git`, `.next` și `node_modules`; dependențele se reinstalează prin `npm ci`.

## Starea testelor acestei livrări

- TypeScript `tsc --noEmit`: PASS.
- Build Next.js: nefinalizat deoarece pachetul SWC nativ nu a putut fi descărcat în mediul fără acces la registry.
- SQL și integrarea Supabase live: neexecutate; necesită un proiect Supabase staging și credențiale de test.
