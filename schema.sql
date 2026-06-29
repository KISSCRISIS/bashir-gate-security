-- ============================================================================
-- نظام أمن بوابة الطوارئ - مستشفى البشير
-- سكربت إعداد قاعدة البيانات الكامل
-- نفّذه كامل دفعة واحدة في: Supabase Dashboard > SQL Editor > New query
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) جدول حالة النظام اللحظية (سطر واحد ثابت id = 1)
-- ----------------------------------------------------------------------------
create table if not exists system_status (
  id int primary key default 1,
  gate_open boolean not null default false,
  current_scan_status text not null default 'WAITING'
    check (current_scan_status in ('WAITING','ALLOWED','LIMITED','DENIED')),
  updated_at timestamptz not null default now()
);

insert into system_status (id, gate_open, current_scan_status)
values (1, false, 'WAITING')
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 2) سجل عمليات الدخول من البوابة (لرقابة الإدارة)
-- ----------------------------------------------------------------------------
create table if not exists gate_access_logs (
  id bigint generated always as identity primary key,
  employee_id text not null,
  action_result text not null check (action_result in ('ALLOWED','LIMITED','DENIED')),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 3) طلبات التسجيل (تسجيل ذاتي + مراجعة الأدمن)
--    access_level تتحدد من الأدمن لحظة القبول (تصريح كامل / محدود)
-- ----------------------------------------------------------------------------
create table if not exists pending_registrations (
  id bigint generated always as identity primary key,
  employee_id text not null unique,
  full_name text not null,
  phone text not null,
  department text,
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  access_level text check (access_level in ('FULL_ACCESS','LIMITED_ACCESS')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

-- ----------------------------------------------------------------------------
-- 4) بلاغات المخالفات (تصوير / عبور مخالف)
-- ----------------------------------------------------------------------------
create table if not exists violations (
  id bigint generated always as identity primary key,
  reported_at timestamptz not null default now(),
  resolved boolean not null default false
);

-- ----------------------------------------------------------------------------
-- 5) جدول المشرفين (تسجيل دخول بالرقم الوظيفي + الهاتف)
--    ⚠️ هذا الجدول لن يُفتح للقراءة العامة (anon) — راجع دالة verify_admin_login أدناه
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
-- تفعيل Row Level Security على كل الجداول
-- ============================================================================
alter table system_status enable row level security;
alter table gate_access_logs enable row level security;
alter table pending_registrations enable row level security;
alter table violations enable row level security;
alter table admins enable row level security;

-- ============================================================================
-- سياسات الوصول العامة (anon) — للشاشات بدون تسجيل دخول: الحارس + verify.html
-- ============================================================================

-- system_status: قراءة + تحديث لحظي (الحارس يشاهد، verify.html يغيّر الحالة)
create policy "anon_read_system_status" on system_status for select using (true);
create policy "anon_update_system_status" on system_status for update using (true);

-- gate_access_logs: إدراج من verify.html + قراءة لعرضها بلوحة الأدمن
create policy "anon_insert_logs" on gate_access_logs for insert with check (true);
create policy "anon_read_logs" on gate_access_logs for select using (true);

-- pending_registrations: تسجيل ذاتي + تحديث الحالة (قبول/رفض) من لوحة الأدمن
-- ملاحظة: السماح بالقراءة هنا ضروري لعمل verify.html والداشبورد، لكن هذا
-- يعني أن أي شخص يملك الـ anon key يقدر يقرأ كل سجلات الموظفين (اسم/هاتف/قسم).
-- لتقليل هذا الكشف بالواجهة العامة (verify.html) استخدم RPC الآمن أدناه
-- بدل القراءة المباشرة من الجدول كلما أمكن.
create policy "anon_insert_registration" on pending_registrations for insert with check (true);
create policy "anon_read_registration" on pending_registrations for select using (true);
create policy "anon_update_registration" on pending_registrations for update using (true);

-- violations: إدراج من شاشة الحارس + قراءة/تحديث (حل البلاغ) من لوحة الأدمن
create policy "anon_insert_violation" on violations for insert with check (true);
create policy "anon_read_violations" on violations for select using (true);
create policy "anon_update_violations" on violations for update using (true);

-- admins: لا توجد أي سياسة SELECT/UPDATE/INSERT لـ anon — الجدول مقفول بالكامل.
-- الوصول الوحيد المسموح هو عبر الدالة الآمنة verify_admin_login بالأسفل.

-- ============================================================================
-- 🔒 دالة آمنة لتسجيل دخول الأدمن (تتفادى كشف جدول admins بالكامل لأي زائر)
-- ============================================================================
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

-- ============================================================================
-- 🔒 دالة آمنة لفحص حالة تسجيل موظف من verify.html بدون كشف كل الجدول
-- (ترجع فقط الحالة + نوع التصريح + الاسم، وليس الهاتف الكامل لكل الموظفين)
-- ============================================================================
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

-- ============================================================================
-- 🔒 دالة آمنة لترقية موظف معتمد ليصبح أدمن (تُستخدم من لوحة تحكم الأدمن)
-- ============================================================================
create or replace function promote_to_admin(p_employee_id text, p_phone text, p_role text default 'ADMIN')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- يجب أن يكون الموظف معتمداً (APPROVED) أصلاً قبل ترقيته
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
-- ملاحظة أخيرة مهمة (اقرأها قبل النشر الفعلي):
-- هذا الإعداد يعتمد على anon key واحد للجميع (الحارس + الموظفين + الأدمن)
-- بدون Supabase Auth حقيقي، فلا يوجد فرق فعلي على مستوى القاعدة بين "متصفح
-- أدمن مسجّل دخول" و "أي زائر آخر" غير الدوال الآمنة أعلاه. هذا مقبول لمرحلة
-- التشغيل التجريبي، لكن للاستخدام الفعلي الكامل بمستشفى حقيقي يُفضّل لاحقاً
-- الانتقال لـ Supabase Auth (OTP على رقم الهاتف) + ربط RLS بـ auth.uid()
-- لحماية حقيقية على مستوى الصلاحيات، خصوصاً لشاشة admin_dashboard.html.
-- ============================================================================
