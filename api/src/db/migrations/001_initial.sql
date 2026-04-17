-- Focus Guard initial schema
-- Run this against your Neon PostgreSQL database

create table if not exists users (
  id         uuid primary key default gen_random_uuid(),
  apple_sub  text unique not null,  -- Apple's "sub" claim from identity token
  email      text,
  created_at timestamptz default now()
);

create table if not exists schedules (
  id                          uuid primary key default gen_random_uuid(),
  user_id                     uuid references users on delete cascade not null,
  name                        text not null,
  is_active                   boolean default true,
  -- [1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat]
  days_of_week                int[] not null,
  start_time                  time not null,
  end_time                    time not null,
  timezone                    text not null default 'UTC',
  -- pomodoro config (null = no pomodoro for this schedule)
  pomodoro_enabled            boolean default false,
  work_minutes                int default 25,
  short_break_min             int default 5,
  long_break_min              int default 15,
  sessions_before_long_break  int default 4,
  created_at                  timestamptz default now(),
  updated_at                  timestamptz default now()
);

create table if not exists blocked_apps (
  id                      uuid primary key default gen_random_uuid(),
  schedule_id             uuid references schedules on delete cascade,
  -- base64-encoded serialized FamilyActivitySelection (iOS only, opaque blob)
  ios_activity_selection  text,
  -- domain names to block (used on macOS via /etc/hosts and can supplement iOS)
  blocked_domains         text[] default '{}',
  updated_at              timestamptz default now()
);

create index if not exists schedules_user_id_idx on schedules(user_id);
-- one blocked_apps row per schedule (upsert relies on this unique constraint)
create unique index if not exists blocked_apps_schedule_id_uniq on blocked_apps(schedule_id);

-- keep updated_at current automatically
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger schedules_updated_at
  before update on schedules
  for each row execute procedure touch_updated_at();

create trigger blocked_apps_updated_at
  before update on blocked_apps
  for each row execute procedure touch_updated_at();
