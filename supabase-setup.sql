-- Kahwa Queue: run this once in Supabase > SQL Editor

create table if not exists public.reports (
  id         bigint generated always as identity primary key,
  place_id   int  not null check (place_id between 1 and 1000),
  wait       text not null check (wait in ('0','15','30','60','120','down','closed')),
  device     text not null check (char_length(device) between 4 and 40),
  created_at timestamptz not null default now()
);

create index if not exists reports_created_idx on public.reports (created_at);
create index if not exists reports_dev_idx on public.reports (device, place_id, created_at);

-- Row level security: anyone can read and add, nobody can edit or delete
alter table public.reports enable row level security;
drop policy if exists "read reports" on public.reports;
drop policy if exists "add reports" on public.reports;
create policy "read reports" on public.reports for select to anon using (true);
create policy "add reports"  on public.reports for insert to anon with check (true);

-- Hide the device id from the public; expose only what the page needs
revoke all on public.reports from anon;
grant select (place_id, wait, created_at) on public.reports to anon;
grant insert (place_id, wait, device)     on public.reports to anon;

-- Server-side spam limit: one report per device per place every 10 minutes
create or replace function public.check_rate() returns trigger as $$
begin
  if exists (
    select 1 from public.reports
    where device = new.device and place_id = new.place_id
      and created_at > now() - interval '10 minutes'
  ) then
    raise exception 'rate_limit';
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists t_rate on public.reports;
create trigger t_rate before insert on public.reports
for each row execute function public.check_rate();
