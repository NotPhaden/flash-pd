# FLASH RP – corecție permisiuni pe grad, departamente și sincronizare avatar

## Ce rezolvă
- Un membru cu grad atribuit (Agent sau mai mare) nu mai rămâne blocat ca `visitor` doar pentru că în `user_roles` a rămas rolul inițial `visitor`.
- `Vizitator` și `Academie` rămân limitate la Academie, Profil și Notificări.
- Accesul la DCCO/SAS și Instructori se rezolvă din departamentele primare și multiple (`officer_departments`).
- Instructorii își pot crea/gestiona dosare numai în categoria departamentului lor; Comisar+ poate consulta toate categoriile, fără drepturi automate de editare.
- RLS-ul Supabase pentru forumurile instructorilor și certificate verifică departamentul real, nu doar rolurile vechi din `user_roles`.
- Avatarul salvat în Profil se actualizează imediat și în sidebar; avatarul existent este încărcat și la autentificare și la actualizarea profilului.
- Tranziții/animări discrete sunt păstrate prin stilurile existente.

## Instalare
1. Fă backup bazei Supabase.
2. Rulează `supabase/flash_rank_department_access_sync.sql` în Supabase SQL Editor, după migrările FLASH existente.
3. Înlocuiește codul aplicației cu această arhivă și păstrează variabilele de mediu ale proiectului în `.env` (nu copia `.env` din arhivă).
4. Publică aplicația și reconectează utilizatorii / reîncarcă sesiunea după ce le schimbi gradul sau departamentele.

## Reguli de acces în interfață
- Vizitator / fără grad operațional: Academie, Profil, Notificări.
- Gradul Academie: Academie, Profil, Notificări.
- Agent și toate gradele operaționale: meniul general.
- Subcomisar+ (nivel 8+) și instructorii desemnați: pagina Instructori; instructorul gestionează numai categoria lui.
- DCCO și SAS: membri identificați prin departamentul primar sau prin `officer_departments`; conducerea unității păstrează drepturile de administrare definite în modul.
- Logs și Recrutări: Subcomisar+ / rolurile de comandă.

## Verificare
Codul sursă a fost modificat. Verificarea TypeScript/build nu a putut fi finalizată în mediul de lucru deoarece instalarea locală a pachetelor `@types/*` este incompletă. Migrarea trebuie verificată pe o copie a bazei înainte de producție.
