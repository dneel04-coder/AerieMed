-- ResQruck — Supabase SQL schema
-- Safe to run multiple times (idempotent).

-- ── Core tables ───────────────────────────────────────────────────────────────

create table if not exists protocols (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  version int not null default 1,
  file_path text not null,
  is_active boolean default true,
  updated_at timestamptz default now(),
  updated_by text default '',
  notes text default ''
);

create table if not exists protocol_acknowledgments (
  id uuid default gen_random_uuid() primary key,
  user_id text not null,
  callsign text not null,
  protocol_id uuid references protocols(id) on delete cascade,
  acknowledged_at timestamptz default now(),
  unique(user_id, protocol_id)
);

create table if not exists patient_reports (
  id text primary key,
  user_id text not null,
  callsign text not null,
  report_data jsonb not null,
  submitted_at timestamptz default now()
);

alter table protocols enable row level security;
alter table protocol_acknowledgments enable row level security;
alter table patient_reports enable row level security;

do $$ begin
  create policy "public_access" on protocols
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "public_access" on protocol_acknowledgments
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "public_access" on patient_reports
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

insert into storage.buckets (id, name, public)
  values ('protocols', 'protocols', true)
  on conflict (id) do nothing;

do $$ begin
  create policy "public_protocols" on storage.objects
    for all using (bucket_id = 'protocols')
    with check (bucket_id = 'protocols');
exception when duplicate_object then null; end $$;

-- ── Team certifications ───────────────────────────────────────────────────────

create table if not exists team_certs (
  id text primary key,
  user_id text not null,
  callsign text not null,
  license_type text not null,
  state text not null,
  original_file_name text not null,
  uploaded_at timestamptz not null,
  file_path text not null,
  expiration_date date
);

alter table team_certs add column if not exists expiration_date date;

alter table team_certs enable row level security;

do $$ begin
  create policy "public_access" on team_certs
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

insert into storage.buckets (id, name, public)
  values ('certs', 'certs', false)
  on conflict (id) do nothing;

do $$ begin
  create policy "public_certs" on storage.objects
    for all using (bucket_id = 'certs')
    with check (bucket_id = 'certs');
exception when duplicate_object then null; end $$;

-- ── Deployment orders ─────────────────────────────────────────────────────────

create table if not exists deployment_orders (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  notes text default '',
  file_path text not null default '',
  file_name text not null default '',
  uploaded_at timestamptz default now(),
  uploaded_by text default ''
);

create table if not exists deployment_order_views (
  user_id text not null,
  order_id uuid references deployment_orders(id) on delete cascade,
  viewed_at timestamptz default now(),
  primary key (user_id, order_id)
);

alter table deployment_orders enable row level security;
alter table deployment_order_views enable row level security;

do $$ begin
  create policy "public_access" on deployment_orders
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "public_access" on deployment_order_views
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

insert into storage.buckets (id, name, public)
  values ('deployment_orders', 'deployment_orders', true)
  on conflict (id) do nothing;

do $$ begin
  create policy "public_orders" on storage.objects
    for all using (bucket_id = 'deployment_orders')
    with check (bucket_id = 'deployment_orders');
exception when duplicate_object then null; end $$;

-- ── Team availability ─────────────────────────────────────────────────────────

create table if not exists team_availability (
  user_id text not null,
  callsign text not null,
  date date not null,
  status text not null default 'Available',
  notes text default '',
  updated_at timestamptz default now(),
  primary key (user_id, date)
);

alter table team_availability enable row level security;

do $$ begin
  create policy "public_access" on team_availability
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

-- ── User profiles ─────────────────────────────────────────────────────────────

create table if not exists user_profiles (
  user_id text primary key,
  name text not null default '',
  callsign text not null default '',
  cert_level text not null default 'None',
  rt130 boolean not null default false,
  rope_rescue boolean not null default false,
  updated_at timestamptz default now()
);

alter table user_profiles enable row level security;

do $$ begin
  create policy "public_access" on user_profiles
    for all using (true) with check (true);
exception when duplicate_object then null; end $$;

-- ── Auto-migration function (called by the app on every startup) ──────────
-- SECURITY DEFINER means it runs as the DB owner even when called by the
-- anon key — so the app can apply schema changes without admin intervention
-- after this SQL has been run once.

create or replace function resqruck_auto_migrate()
returns void
language plpgsql
security definer
as $func$
begin
  -- tac_users: Life360 columns
  alter table if exists tac_users add column if not exists battery_level int;
  alter table if exists tac_users add column if not exists status text default 'Active';

  -- tac_breadcrumbs
  create table if not exists tac_breadcrumbs (
    id uuid default gen_random_uuid() primary key,
    user_id text not null,
    callsign text not null,
    mission_code text not null,
    lat double precision not null,
    lng double precision not null,
    recorded_at timestamptz default now()
  );
  begin
    alter table tac_breadcrumbs enable row level security;
    create policy "public_access" on tac_breadcrumbs
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- tac_zones
  create table if not exists tac_zones (
    id uuid default gen_random_uuid() primary key,
    mission_code text not null,
    name text not null,
    zone_type text not null default 'Custom',
    lat double precision not null,
    lng double precision not null,
    radius_m double precision not null default 100,
    created_by text not null default '',
    created_at timestamptz default now()
  );
  begin
    alter table tac_zones enable row level security;
    create policy "public_access" on tac_zones
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- tac_sos
  create table if not exists tac_sos (
    id uuid default gen_random_uuid() primary key,
    user_id text not null,
    callsign text not null,
    mission_code text not null,
    lat double precision not null,
    lng double precision not null,
    message text default '',
    triggered_at timestamptz default now(),
    resolved_at timestamptz,
    resolved_by text default ''
  );
  begin
    alter table tac_sos enable row level security;
    create policy "public_access" on tac_sos
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- team_certs: expiration date column
  alter table if exists team_certs add column if not exists expiration_date date;

  -- team_positions: ATAK / CoT feed written by the Oracle Cloud CoT listener
  -- callsign is UNIQUE so the server can upsert by callsign on each position update
  create table if not exists team_positions (
    id uuid default gen_random_uuid() primary key,
    callsign text not null unique,
    lat double precision not null,
    lon double precision not null,
    role text not null default '',
    status text not null default 'Active',
    last_updated timestamptz default now()
  );
  begin
    alter table team_positions enable row level security;
    create policy "public_access" on team_positions
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    -- Enable realtime so the app receives live position updates
    alter publication supabase_realtime add table team_positions;
  exception when others then null;
  end;

  -- admin_alerts: real-time notifications delivered to admins
  create table if not exists admin_alerts (
    id uuid default gen_random_uuid() primary key,
    type text not null,
    title text not null,
    callsign text not null default '',
    body text not null default '',
    created_at timestamptz default now(),
    read boolean not null default false
  );
  begin
    alter table admin_alerts enable row level security;
    create policy "public_access" on admin_alerts
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table admin_alerts;
  exception when others then null;
  end;

  -- tac_pois: optional points of interest layer
  create table if not exists tac_pois (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    type text not null default 'generic',
    lat double precision not null,
    lng double precision not null,
    notes text default '',
    created_at timestamptz default now()
  );
  begin
    alter table tac_pois enable row level security;
    create policy "public_access" on tac_pois
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- deployment_orders: optional per-user targeting (NULL = broadcast to everyone, unchanged default)
  alter table if exists deployment_orders add column if not exists target_user_ids text[];

  -- incidents: formal admin-managed incident sessions, each wrapping a tac_map mission_code
  create table if not exists incidents (
    id uuid default gen_random_uuid() primary key,
    name text not null default '',
    mission_code text not null,
    status text not null default 'open',
    opened_at timestamptz default now(),
    closed_at timestamptz,
    opened_by text default '',
    notes text default ''
  );
  begin
    alter table incidents enable row level security;
    create policy "public_access" on incidents
      for all using (true) with check (true);
  exception when others then null;
  end;
  create unique index if not exists incidents_open_mission_code_uq
    on incidents (mission_code) where status = 'open';
  begin
    alter publication supabase_realtime add table incidents;
  exception when others then null;
  end;

  -- incident_members: durable roster attached to an incident by the admin console
  -- (kept separate from tac_users, which is deleted on mission leave and would
  -- otherwise silently lose incident history for anyone who goes offline)
  create table if not exists incident_members (
    id uuid default gen_random_uuid() primary key,
    incident_id uuid references incidents(id) on delete cascade,
    user_id text not null,
    callsign text not null default '',
    joined_at timestamptz default now(),
    left_at timestamptz,
    accepted_at timestamptz,
    unique(incident_id, user_id)
  );
  alter table if exists incident_members add column if not exists accepted_at timestamptz;
  begin
    alter table incident_members enable row level security;
    create policy "public_access" on incident_members
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table incident_members;
  exception when others then null;
  end;
end;
$func$;

-- Allow the anon key (used by the app) to call this function.
grant execute on function resqruck_auto_migrate() to anon;
grant execute on function resqruck_auto_migrate() to authenticated;

-- ── Access codes (run once, outside the migration function) ──────────────────
create table if not exists app_access_codes (
  id uuid default gen_random_uuid() primary key,
  code text unique not null,
  description text not null default '',
  is_active boolean not null default true,
  bypass_paywall boolean not null default false,
  uses integer not null default 0,
  created_at timestamptz default now()
);
do $$ begin
  alter table app_access_codes add column if not exists bypass_paywall boolean not null default false;
exception when others then null;
end $$;
do $$ begin
  alter table app_access_codes enable row level security;
  create policy "public_access" on app_access_codes
    for all using (true) with check (true);
exception when others then null;
end $$;
