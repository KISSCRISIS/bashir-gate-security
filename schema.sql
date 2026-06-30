-- ============================================================================
-- نظام أمن بوابة الطوارئ - مستشفى البشير
-- سكربت إعداد قاعدة البيانات الكامل (مُحدَّث مع العمودين المطلوبين)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) جدول حالة النظام اللحظية (سطر واحد ثابت id = 1)
-- ----------------------------------------------------------------------------
create table if not exists system_status (
  id int primary key default 1,
  gate_open boolean not null default false,
  current_scan_status text not null default 'WAITING'
    check (current_scan_status in ('WAITING','ALLOWED','LIMITED','DENIED')),
  last_scanned_employee text default '',   -- ✅ العمود الجديد
  updated_at timestamptz not null default now()
);

insert into system_status (id, gate_open, current_scan_status, last_scanned_employee)
values (1, false, 'WAITING', '')
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 2) سجل عمليات الدخول من البوابة
-- ----------------------------------------------------------------------------
create table if not exists gate_access_logs (
  id bigint generated always as identity primary key,
  employee_id text not null,
  action_result text not null check (action_result in ('ALLOWED','LIMITED','DENIED')),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 3) طلبات التسجيل (مع إضافة عمود role لإدارة رتب المشرفين)
-- ----------------------------------------------------------------------------
create table if not exists pending_registrations (
  id bigint generated always as identity primary key,
  employee_id text not null unique,
  full_name text not null,
  phone text not null,
  department text,
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  access_level text check (access_level in ('FULL_ACCESS','LIMITED_ACCESS')),
  role text,   -- ✅ العمود الجديد (ADMIN, SUPER_ADMIN, SUB_ADMIN, أو NULL)
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

-- ----------------------------------------------------------------------------
-- 4) بلاغات المخالفات
-- ----------------------------------------------------------------------------
create table if not exists violations (
  id bigint generated always as identity primary key,
  reported_at timestamptz not null default now(),
  resolved boolean not null default false
);

-- ----------------------------------------------------------------------------
-- 5) جدول المشرفين (تسجيل دخول بالرقم الوظيفي + الهاتف)
-- ----------------------------------------------------------------------------
create table if not exists admins (
  id bigint generated always as identity primary key,
  employee_id text not null unique,
  phone text not null,
  role text not null default 'ADMIN' check (role in ('ADMIN','SUPER_ADMIN')),
  created_at timestamptz not null default now()
);

-- 👈 غيّر القيم هنا وفعّل السطر لإضافة أول حساب أدمن لك بنفسك:
-- insert into admins (employee_id, phone, role) values ('EMP001', '0790000000', 'SUPER_ADMIN');

-- ============================================================================
-- تفعيل التحديث اللحظي Realtime
-- ============================================================================
alter publication supabase_realtime add table system_status;
alter publication supabase_realtime add table violations;
alter publication supabase_realtime add table pending_registrations;

-- ============================================================================
-- تفعيل Row Level Security
-- ============================================================================
alter table system_status enable row level security;
alter table gate_access_logs enable row level security;
alter table pending_registrations enable row level security;
alter table violations enable row level security;
alter table admins enable row level security;

-- ============================================================================
-- سياسات الوصول العامة (anon)
-- ============================================================================

-- system_status: قراءة + تحديث
create policy "anon_read_system_status" on system_status for select using (true);
create policy "anon_update_system_status" on system_status for update using (true);

-- gate_access_logs: إدراج + قراءة
create policy "anon_insert_logs" on gate_access_logs for insert with check (true);
create policy "anon_read_logs" on gate_access_logs for select using (true);

-- pending_registrations: إدراج + قراءة + تحديث (يسمح بتعديل role)
create policy "anon_insert_registration" on pending_registrations for insert with check (true);
create policy "anon_read_registration" on pending_registrations for select using (true);
create policy "anon_update_registration" on pending_registrations for update using (true);

-- violations: إدراج + قراءة + تحديث
create policy "anon_insert_violation" on violations for insert with check (true);
create policy "anon_read_violations" on violations for select using (true);
create policy "anon_update_violations" on violations for update using (true);

-- admins: لا توجد سياسات لـ anon (مقفول بالكامل)

-- ============================================================================
-- دوال RPC الآمنة
-- ============================================================================

-- 1) تسجيل دخول الأدمن
create or replace function verify_admin_login(p_employee_id text, p_phone text)
returns table(employee_id text, role text)
language sql
security definer
set search_path = public
as $$
  select a.employee_id, a.role
  from admins a
  where a.employee_id = p_employee_id
    and a.phone = p_phone;
$$;

revoke all on function verify_admin_login(text, text) from public;
grant execute on function verify_admin_login(text, text) to anon;

-- 2) فحص حالة تسجيل موظف (لـ verify.html)
create or replace function check_registration_status(p_employee_id text)
returns table(status text, access_level text, full_name text)
language sql
security definer
set search_path = public
as $$
  select p.status, p.access_level, p.full_name
  from pending_registrations p
  where p.employee_id = p_employee_id;
$$;

revoke all on function check_registration_status(text) from public;
grant execute on function check_registration_status(text) to anon;

-- 3) عدّ المشرفين الحاليين (لسقف 5)
create or replace function count_admins()
returns integer
language sql
security definer
set search_path = public
as $$
  select count(*)::integer from admins;
$$;

revoke all on function count_admins() from public;
grant execute on function count_admins() to anon;

-- 4) ترقية موظف معتمد إلى أدمن (مع سقف 5)
create or replace function promote_to_admin(p_employee_id text, p_phone text, p_role text default 'ADMIN')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_count integer;
begin
  select count(*) into current_admin_count from admins;

  if current_admin_count >= 5 and not exists (
    select 1 from admins where employee_id = p_employee_id
  ) then
    raise exception 'تم الوصول للحد الأقصى المسموح به (5 مشرفين)';
  end if;

  if not exists (
    select 1 from pending_registrations
    where employee_id = p_employee_id and status = 'APPROVED'
  ) then
    raise exception 'الموظف غير معتمد، لا يمكن ترقيته كأدمن';
  end if;

  insert into admins (employee_id, phone, role)
  values (p_employee_id, p_phone, p_role)
  on conflict (employee_id) do update set phone = excluded.phone, role = excluded.role;
end;
$$;

revoke all on function promote_to_admin(text, text, text) from public;
grant execute on function promote_to_admin(text, text, text) to anon;

-- ============================================================================
-- تنبيه أمني: هذا الإعداد يعتمد على anon key واحد للجميع بدون مصادقة حقيقية.
-- مناسب للتشغيل التجريبي، لكن للإنتاج يُفضّل استخدام Supabase Auth مع RLS.
-- ============================================================================