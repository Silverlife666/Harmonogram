# Harmonogram produkcji

Ta aplikacja używa tego samego projektu Supabase i tych samych kont e-mail +
PIN co `dostawyozadania`, ale ma niezależne profile ról i uprawnienia.

1. Uruchom `supabase/schema.sql` w SQL Editor projektu Supabase.
2. Ustaw istniejące konto jako pierwszy aktywny Administrator poleceniem z
   końca tego pliku SQL.
3. Publiczny klucz publishable jest już wpisany w `index.html`. Nie wolno tam
   wpisywać `service_role` ani `sb_secret`.
4. Jednorazowo skopiuj stary plan npoint:

   ```powershell
   $env:SUPABASE_URL = "https://hjadatjvyrjexgmicggi.supabase.co"
   $env:SUPABASE_SERVICE_ROLE_KEY = "..."
   python scripts/migrate_npoint_to_supabase.py
   ```

Administrator zarządza rolami i uprawnieniami. Właściciel oraz Pracownik mogą
osobno otrzymać: edycję planu, zarządzanie pracownikami i pobieranie PDF.
Wyczyszczenie planu ma prawo wykonać wyłącznie Administrator — również reguły
w Supabase odrzucą taką próbę od innych kont.
