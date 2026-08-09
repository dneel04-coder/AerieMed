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

  -- tac_markers
  create table if not exists tac_markers (
    id uuid default gen_random_uuid() primary key,
    mission_code text not null,
    type text not null,
    label text not null default '',
    lat double precision not null,
    lng double precision not null,
    placed_by text not null default '',
    created_at timestamptz default now()
  );
  begin
    alter table tac_markers enable row level security;
    create policy "public_access" on tac_markers
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table tac_markers;
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

  -- teams: standing organizational teams (not mission-specific), matching
  -- REMS roster conventions (Type 1/Type 2 resource typing, A/B squad
  -- designations). color_hex drives team color-coding on the map/roster.
  create table if not exists teams (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    color_hex text not null default '#2196F3',
    designation text not null default '',
    notes text default '',
    created_at timestamptz default now()
  );
  begin
    alter table teams enable row level security;
    create policy "public_access" on teams
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table teams;
  exception when others then null;
  end;

  -- user_profiles: single-resource typing (wildland fire ICS conventions —
  -- EMT, EMT-Paramedic, Rope Rescue Technician, Driver/Operator, Team Leader)
  -- and standing team membership. resource_type is intentionally free text,
  -- not a check constraint, matching how status/cert_level/zone_type are
  -- validated client-side elsewhere in this schema rather than locked at
  -- the DB level.
  alter table if exists user_profiles add column if not exists resource_type text default '';
  alter table if exists user_profiles add column if not exists team_id uuid references teams(id);

  -- deployment_status: where someone is relative to an incident assignment —
  -- Standby / In Transit / On Mission / Off Duty. Independent of incident
  -- membership: people can be on standby with assets pre-staged, or moving
  -- toward an incident, before any incident_members row exists for them.
  alter table if exists user_profiles add column if not exists deployment_status text default 'Standby';

  -- assets: persistent, org-wide resource registry (vehicles, equipment,
  -- caches). Not mission-scoped — where an asset currently is / who has it
  -- lives in asset_assignments below, so its history isn't lost when it moves.
  create table if not exists assets (
    id uuid default gen_random_uuid() primary key,
    type text not null,
    identifier text not null,
    status text not null default 'Available',
    notes text default '',
    created_at timestamptz default now(),
    unique(type, identifier)
  );
  begin
    alter table assets enable row level security;
    create policy "public_access" on assets
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table assets;
  exception when others then null;
  end;

  -- asset_assignments: polymorphic — an asset can be assigned to a user, a
  -- team, or a mission (incident). assignable_id is resolved by the app
  -- against user_profiles/teams/incidents based on assignable_type; Postgres
  -- can't natively FK-constrain across a type discriminator without a
  -- trigger, so referential integrity here is enforced app-side, same as
  -- incident_members.user_id elsewhere in this schema. The partial unique
  -- index ensures an asset has only one active assignment at a time.
  create table if not exists asset_assignments (
    id uuid default gen_random_uuid() primary key,
    asset_id uuid not null references assets(id) on delete cascade,
    assignable_type text not null check (assignable_type in ('user', 'team', 'mission')),
    assignable_id text not null,
    assigned_at timestamptz default now(),
    assigned_by text default '',
    unassigned_at timestamptz,
    notes text default ''
  );
  create unique index if not exists asset_assignments_one_active_uq
    on asset_assignments (asset_id) where unassigned_at is null;
  begin
    alter table asset_assignments enable row level security;
    create policy "public_access" on asset_assignments
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table asset_assignments;
  exception when others then null;
  end;

  -- app_settings: simple team-wide key/value config (currently just the
  -- shared team drive link patient reports can be sent to). Unlike admin
  -- credentials elsewhere (per-device, in SharedPreferences), this is meant
  -- to be the same for every device, so it lives here instead.
  create table if not exists app_settings (
    key text primary key,
    value text not null default ''
  );
  begin
    alter table app_settings enable row level security;
    create policy "public_access" on app_settings
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- device_push_tokens: one current FCM token per user_id, overwritten on
  -- each registration — mirrors the single-device assumption already baked
  -- into tac_user_id / callsign uniqueness elsewhere in this app.
  create table if not exists device_push_tokens (
    user_id text primary key,
    fcm_token text not null,
    platform text not null default '',
    updated_at timestamptz default now()
  );
  begin
    alter table device_push_tokens enable row level security;
    create policy "public_access" on device_push_tokens
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- internal_secrets: NOT publicly readable — RLS is enabled with zero
  -- policies, which denies all access via the REST API (anon/authenticated
  -- roles), while the SECURITY DEFINER trigger function below (running as
  -- the table owner) bypasses RLS entirely, per Postgres's default
  -- owner-exempt-from-RLS behavior. This exists because Supabase's hosted
  -- Postgres doesn't grant superuser to any customer-accessible role
  -- (confirmed: `alter database ... set app.settings.x` fails with
  -- "permission denied" even from the SQL editor's own connection), so the
  -- originally-planned session-GUC approach for storing the push trigger
  -- secret isn't available — this table is the workaround.
  create table if not exists internal_secrets (
    key text primary key,
    value text not null
  );
  begin
    alter table internal_secrets enable row level security;
  exception when others then null;
  end;

  -- Fires on a new/reset incident assignment (mirrors the same
  -- accepted_at/left_at both-null guard used client-side in
  -- _subscribeMissionAssignments) and POSTs to the push-mission-assignment
  -- Edge Function so the assigned user gets a real push notification even
  -- if their app is closed. Silently no-ops (net.http_post still fires, but
  -- the function 401s) until the one-time push_trigger_secret row is
  -- inserted into internal_secrets.
  begin
    create extension if not exists pg_net;
  exception when others then null;
  end;

  create or replace function notify_incident_member_pending() returns trigger as $trg$
  declare
    secret_value text;
  begin
    select value into secret_value from internal_secrets where key = 'push_trigger_secret';
    perform net.http_post(
      url := 'https://vlgiclyuxaleyusalexo.supabase.co/functions/v1/push-mission-assignment',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', coalesce(secret_value, '')
      ),
      body := jsonb_build_object('user_id', new.user_id, 'incident_id', new.incident_id)
    );
    return new;
  end;
  $trg$ language plpgsql security definer;

  drop trigger if exists incident_members_push_trigger on incident_members;
  create trigger incident_members_push_trigger
    after insert or update of accepted_at, left_at on incident_members
    for each row
    when (new.accepted_at is null and new.left_at is null)
    execute function notify_incident_member_pending();
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
