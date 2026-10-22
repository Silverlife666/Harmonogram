-- Plan produkcji: uruchom cały plik raz w SQL Editor tego SAMEGO projektu Supabase.
-- Konta Auth (e-mail + PIN) są wspólne z dostawyozadania.

create table if not exists public.production_schedule_state (
  id smallint primary key default 1 check (id = 1),
  payload jsonb not null default '{"format":"plan-produkcji-html-v1","employees":[],"assignments":[],"lastModified":"—"}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create table if not exists public.production_schedule_users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text default '',
  role text not null default 'Pracownik' check (role in ('Administrator', 'Właściciel', 'Pracownik')),
  permissions text[] not null default array['read','export_pdf']::text[],
  active boolean not null default false,
  created_at timestamptz not null default now()
);

-- Istniejące konta Auth (np. anonimowe) mogą nie posiadać e-maila ani nazwy.
-- Nazwa wyświetlana jest wygodą UI, a nie identyfikatorem bezpieczeństwa.
alter table public.production_schedule_users alter column display_name drop not null;

-- Tworzy profile również dla kont, które istniały zanim powstał ten harmonogram.
insert into public.production_schedule_users (id, display_name)
select u.id, coalesce(nullif(u.raw_user_meta_data ->> 'display_name', ''), nullif(split_part(coalesce(u.email, ''), '@', 1), ''), u.id::text)
from auth.users as u
where not exists (
  select 1 from public.production_schedule_users as p where p.id = u.id
);

-- Każde konto utworzone później dostaje nieaktywny profil. Administrator
-- aktywuje je potem w aplikacji i przyznaje rolę/uprawnienia.
create or replace function public.create_production_schedule_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.production_schedule_users (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), nullif(split_part(coalesce(new.email, ''), '@', 1), ''), new.id::text))
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists production_schedule_profile_after_auth_user on auth.users;
create trigger production_schedule_profile_after_auth_user
  after insert on auth.users for each row execute procedure public.create_production_schedule_profile();
revoke all on function public.create_production_schedule_profile() from public, anon, authenticated;

alter table public.production_schedule_state enable row level security;
alter table public.production_schedule_users enable row level security;

create or replace function public.production_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.production_schedule_users where id = auth.uid() and active and role = 'Administrator');
$$;

create or replace function public.production_has_permission(permission_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.production_schedule_users
    where id = auth.uid() and active and (role = 'Administrator' or permission_name = any(permissions))
  );
$$;

-- SECURITY DEFINER nie może być wykonywane publicznie. Funkcje pomocnicze są
-- wywoływane wyłącznie przez polityki RLS, a zapis planu tylko przez zalogowaną
-- aplikację z prawem edit_plan.
revoke all on function public.production_is_admin() from public, anon;
revoke all on function public.production_has_permission(text) from public, anon;
grant execute on function public.production_is_admin() to authenticated;
grant execute on function public.production_has_permission(text) to authenticated;

drop policy if exists "production schedule read" on public.production_schedule_state;
create policy "production schedule read" on public.production_schedule_state for select using (public.production_has_permission('read'));

create or replace function public.save_production_schedule(next_payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare old_assignment_count integer; new_assignment_count integer;
begin
  if not public.production_has_permission('edit_plan') then raise exception 'Brak uprawnienia do edycji planu'; end if;
  if jsonb_typeof(next_payload) <> 'object'
     or jsonb_typeof(next_payload -> 'employees') <> 'array'
     or jsonb_typeof(next_payload -> 'assignments') <> 'array' then
    raise exception 'Nieprawidłowy format harmonogramu';
  end if;
  select coalesce(jsonb_array_length(payload -> 'assignments'), 0) into old_assignment_count from public.production_schedule_state where id = 1;
  new_assignment_count := coalesce(jsonb_array_length(next_payload -> 'assignments'), 0);
  if coalesce(old_assignment_count, 0) > 0 and new_assignment_count = 0 and not public.production_is_admin() then
    raise exception 'Tylko Administrator może wyczyścić plan';
  end if;
  insert into public.production_schedule_state (id,payload,updated_at,updated_by) values (1,next_payload,now(),auth.uid())
  on conflict (id) do update set payload=excluded.payload, updated_at=excluded.updated_at, updated_by=excluded.updated_by;
end;
$$;

revoke all on function public.save_production_schedule(jsonb) from public, anon;
grant execute on function public.save_production_schedule(jsonb) to authenticated;

-- RLS nie zastępuje grantów. Klient może czytać plan i profile, ale nie ma
-- bezpośredniego prawa zapisu do planu; zapis odbywa się wyłącznie przez RPC.
revoke all on public.production_schedule_state from anon, authenticated;
grant select on public.production_schedule_state to authenticated;
revoke all on public.production_schedule_users from anon, authenticated;
grant select, update on public.production_schedule_users to authenticated;

drop policy if exists "production profile read" on public.production_schedule_users;
drop policy if exists "production profile admin update" on public.production_schedule_users;
create policy "production profile read" on public.production_schedule_users for select using (id = auth.uid() or public.production_is_admin());
create policy "production profile admin update" on public.production_schedule_users for update using (public.production_is_admin()) with check (public.production_is_admin());

-- Po uruchomieniu ustaw swoje istniejące konto jako pierwszy aktywny Admin:
-- update public.production_schedule_users
-- set active = true, role = 'Administrator', permissions = array['edit_plan','manage_people','export_pdf','manage_users']
-- where id = '<UUID z Authentication > Users>';
