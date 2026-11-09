# FLASH RP – corecții permisiuni, SAS și profil

## Ce s-a schimbat
- Rolurile DCCO/SAS de conducere sunt deduse și din gradul din `officers -> ranks`, nu exclusiv din `user_roles`.
- Accesul la DCCO/SAS se poate deduce din departamentul principal sau din `officer_departments`.
- Lista membrilor DCCO/SAS include membrii identificați prin departament/grad, chiar dacă nu au un rând `user_roles` separat.
- Categoriile de instructor pot fi recunoscute după numele departamentului: RADIO, MDT, FINAL, HELI, HS și variantele `INSTRUCTOR ...`.
- Pagina de profil are butonul EDITEAZĂ în colțul din dreapta sus al bannerului; personalizarea se deschide într-un popup.
- DCCO include și tipurile de document Filaj și Raport organizație.
- Departamentele de conducere și categoriile de instructor sunt create idempotent de migrare.

## Instalare
1. Fă backup bazei Supabase.
2. Rulează `supabase/flash_permissions_profile_departments_fix.sql` în SQL Editor.
3. Publică frontend-ul din arhivă.
4. După modificarea gradului/departamentului unui membru, reîncarcă sesiunea utilizatorului pentru recalcularea meniului.

Permisiunile sunt verificate în Supabase RLS și în funcțiile RPC; ascunderea unei pagini din meniu nu este singurul mecanism de securitate.
