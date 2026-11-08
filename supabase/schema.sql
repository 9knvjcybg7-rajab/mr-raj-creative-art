-- MR RAJ CREATIVE ART – Supabase schema (run in Supabase SQL Editor)
-- Order: this file once. Then make yourself admin (see bottom).

create extension if not exists pgcrypto;

-- ============ ENUMS ============
create type user_role as enum ('student','admin');
create type enrol_status as enum ('pending','active','cancelled');
create type payment_status as enum ('unpaid','pending_verification','verified','rejected');
create type approval_status as enum ('pending','approved','rejected');

-- ============ TABLES ============
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  phone text,
  bio text,
  avatar_url text,
  role user_role not null default 'student',
  created_at timestamptz not null default now()
);

create table courses (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  description text,
  month_number int,
  price_kes int not null default 0 check (price_kes >= 0),
  cover_url text,
  published boolean not null default false,
  created_at timestamptz not null default now()
);

create table lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references courses(id) on delete cascade,
  position int not null,
  title text not null,
  description text,
  video_path text,              -- path in private 'lesson-videos' bucket
  published boolean not null default false,
  unique (course_id, position)
);

create table lesson_materials (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references lessons(id) on delete cascade,
  title text not null,
  file_path text not null       -- path in private 'materials' bucket
);

create table assignments (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null unique references lessons(id) on delete cascade,
  title text not null,
  instructions text,
  max_marks int not null default 100,
  due_date date
);

create table enrolments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  course_id uuid not null references courses(id) on delete cascade,
  status enrol_status not null default 'pending',
  created_at timestamptz not null default now(),
  unique (user_id, course_id)
);

create table payments (
  id uuid primary key default gen_random_uuid(),
  enrolment_id uuid not null references enrolments(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  amount_kes int not null,
  method text not null default 'mpesa',
  mpesa_code text,                       -- code the student reports
  checkout_request_id text,              -- set by Daraja STK push
  provider_receipt text,                 -- set ONLY by server callback
  status payment_status not null default 'unpaid',
  verified_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table lesson_progress (
  user_id uuid not null references profiles(id) on delete cascade,
  lesson_id uuid not null references lessons(id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignments(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  file_path text,                        -- private 'submissions' bucket
  notes text,
  marks int,
  feedback text,
  graded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (assignment_id, user_id)
);

create table certificates (
  id uuid primary key default gen_random_uuid(),
  certificate_no text unique not null,
  user_id uuid not null references profiles(id) on delete cascade,
  course_id uuid not null references courses(id) on delete cascade,
  student_name text not null,
  course_title text not null,
  issued_at date not null default current_date,
  revoked boolean not null default false,
  unique (user_id, course_id)
);

create table gallery_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  description text,
  image_path text not null,              -- public 'gallery' bucket
  status approval_status not null default 'pending',
  created_at timestamptz not null default now()
);

create table site_content (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table contact_enquiries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  topic text,
  message text not null,
  created_at timestamptz not null default now()
);

create index on lessons (course_id, position);
create index on enrolments (user_id);
create index on submissions (user_id);
create index on gallery_items (status);

-- ============ HELPERS ============
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function has_course_access(cid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() or exists (
    select 1 from enrolments
    where user_id = auth.uid() and course_id = cid and status = 'active');
$$;

-- New auth user -> profile (always a student)
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Students can never change their own role
create or replace function block_role_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role and not is_admin() then
    raise exception 'Not allowed to change role';
  end if;
  return new;
end $$;
create trigger profiles_role_guard before update on profiles
  for each row execute function block_role_change();

-- Enrolment status is forced: free course => active, paid => pending
create or replace function set_enrolment_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare p int;
begin
  if is_admin() then return new; end if;
  select price_kes into p from courses where id = new.course_id and published;
  if p is null then raise exception 'Course not available'; end if;
  new.status := case when p = 0 then 'active' else 'pending' end;
  return new;
end $$;
create trigger enrolment_status_guard before insert on enrolments
  for each row execute function set_enrolment_status();

-- Students may not set grading fields or payment verification
create or replace function guard_submission() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    new.marks := null; new.feedback := null; new.graded_at := null;
    if tg_op = 'UPDATE' then
      new.marks := old.marks; new.feedback := old.feedback; new.graded_at := old.graded_at;
    end if;
  end if;
  return new;
end $$;
create trigger submission_guard before insert or update on submissions
  for each row execute function guard_submission();

-- Eligibility: all published lessons completed AND all assignments submitted
create or replace function certificate_eligible(uid uuid, cid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select
    not exists (select 1 from lessons l where l.course_id = cid and l.published
      and not exists (select 1 from lesson_progress p where p.lesson_id = l.id and p.user_id = uid))
    and not exists (select 1 from assignments a join lessons l on l.id = a.lesson_id
      where l.course_id = cid and l.published
      and not exists (select 1 from submissions s where s.assignment_id = a.id and s.user_id = uid))
    and exists (select 1 from lessons where course_id = cid and published);
$$;

-- Admin issues a certificate (checks eligibility; never automatic)
create or replace function issue_certificate(uid uuid, cid uuid) returns text
language plpgsql security definer set search_path = public as $$
declare no text; nm text; ct text;
begin
  if not is_admin() then raise exception 'Admins only'; end if;
  if not certificate_eligible(uid, cid) then raise exception 'Student has not met the requirements'; end if;
  select full_name into nm from profiles where id = uid;
  select title into ct from courses where id = cid;
  no := 'MRC-' || to_char(now(),'YYYY') || '-' || upper(substr(encode(gen_random_bytes(5),'hex'),1,8));
  insert into certificates (certificate_no, user_id, course_id, student_name, course_title)
  values (no, uid, cid, nm, ct)
  on conflict (user_id, course_id) do update set revoked = false
  returning certificate_no into no;
  return no;
end $$;

-- Public certificate verification (returns minimal data only)
create or replace function verify_certificate(cert_no text)
returns table (student_name text, course_title text, issued_at date, valid boolean)
language sql stable security definer set search_path = public as $$
  select student_name, course_title, issued_at, not revoked
  from certificates where certificate_no = upper(trim(cert_no));
$$;
grant execute on function verify_certificate(text) to anon, authenticated;

-- ============ ROW LEVEL SECURITY ============
alter table profiles enable row level security;
alter table courses enable row level security;
alter table lessons enable row level security;
alter table lesson_materials enable row level security;
alter table assignments enable row level security;
alter table enrolments enable row level security;
alter table payments enable row level security;
alter table lesson_progress enable row level security;
alter table submissions enable row level security;
alter table certificates enable row level security;
alter table gallery_items enable row level security;
alter table site_content enable row level security;
alter table contact_enquiries enable row level security;

-- profiles
create policy "own profile read" on profiles for select using (id = auth.uid() or is_admin());
create policy "own profile update" on profiles for update using (id = auth.uid() or is_admin());

-- courses: published are public (catalogue); admin manages all
create policy "courses public read" on courses for select using (published or is_admin());
create policy "courses admin write" on courses for all using (is_admin()) with check (is_admin());

-- lessons: titles visible only to enrolled students; admin all
create policy "lessons read" on lessons for select using ((published and has_course_access(course_id)) or is_admin());
create policy "lessons admin write" on lessons for all using (is_admin()) with check (is_admin());

create policy "materials read" on lesson_materials for select using (
  is_admin() or exists (select 1 from lessons l where l.id = lesson_id and l.published and has_course_access(l.course_id)));
create policy "materials admin write" on lesson_materials for all using (is_admin()) with check (is_admin());

create policy "assignments read" on assignments for select using (
  is_admin() or exists (select 1 from lessons l where l.id = lesson_id and l.published and has_course_access(l.course_id)));
create policy "assignments admin write" on assignments for all using (is_admin()) with check (is_admin());

-- enrolments
create policy "own enrolments read" on enrolments for select using (user_id = auth.uid() or is_admin());
create policy "enrol self" on enrolments for insert with check (user_id = auth.uid() or is_admin());
create policy "enrolments admin update" on enrolments for update using (is_admin());
create policy "enrolments admin delete" on enrolments for delete using (is_admin());

-- payments: students read own and may report an M-Pesa code; only admin/server verifies
create policy "own payments read" on payments for select using (user_id = auth.uid() or is_admin());
create policy "report payment" on payments for insert with check (
  user_id = auth.uid() and status in ('unpaid','pending_verification') and provider_receipt is null and verified_by is null);
create policy "payments admin update" on payments for update using (is_admin());

-- progress
create policy "own progress read" on lesson_progress for select using (user_id = auth.uid() or is_admin());
create policy "mark complete" on lesson_progress for insert with check (
  user_id = auth.uid() and exists (select 1 from lessons l where l.id = lesson_id and has_course_access(l.course_id)));
create policy "unmark complete" on lesson_progress for delete using (user_id = auth.uid());

-- submissions
create policy "own submissions read" on submissions for select using (user_id = auth.uid() or is_admin());
create policy "submit" on submissions for insert with check (
  user_id = auth.uid() and exists (
    select 1 from assignments a join lessons l on l.id = a.lesson_id
    where a.id = assignment_id and has_course_access(l.course_id)));
create policy "resubmit or grade" on submissions for update using (user_id = auth.uid() or is_admin());

-- certificates: read own; creation only through issue_certificate()
create policy "own certificates read" on certificates for select using (user_id = auth.uid() or is_admin());
create policy "certificates admin update" on certificates for update using (is_admin());

-- gallery: approved are public; owners see their own; admin approves
create policy "gallery read" on gallery_items for select using (status = 'approved' or user_id = auth.uid() or is_admin());
create policy "gallery upload" on gallery_items for insert with check (user_id = auth.uid() and status = 'pending');
create policy "gallery owner edit" on gallery_items for update using (user_id = auth.uid() and status <> 'approved' or is_admin());
create policy "gallery delete" on gallery_items for delete using (user_id = auth.uid() or is_admin());

-- site content & enquiries
create policy "content public read" on site_content for select using (true);
create policy "content admin write" on site_content for all using (is_admin()) with check (is_admin());
create policy "enquiry anyone insert" on contact_enquiries for insert with check (true);
create policy "enquiry admin read" on contact_enquiries for select using (is_admin());

-- ============ STORAGE ============
insert into storage.buckets (id, name, public) values
  ('lesson-videos','lesson-videos',false),
  ('materials','materials',false),
  ('submissions','submissions',false),
  ('gallery','gallery',true)
on conflict do nothing;

-- Convention: submissions/<user_id>/<file>, gallery/<user_id>/<file>
create policy "admin manages lesson media" on storage.objects for all
  using (bucket_id in ('lesson-videos','materials') and is_admin())
  with check (bucket_id in ('lesson-videos','materials') and is_admin());
create policy "enrolled read lesson media" on storage.objects for select
  using (auth.role() = 'authenticated' and bucket_id in ('lesson-videos','materials'));
  -- Tighten later: serve videos via short-lived signed URLs from an Edge Function that checks has_course_access().
create policy "own submission files" on storage.objects for all
  using (bucket_id = 'submissions' and (auth.uid()::text = (storage.foldername(name))[1] or is_admin()))
  with check (bucket_id = 'submissions' and (auth.uid()::text = (storage.foldername(name))[1] or is_admin()));
create policy "gallery public read" on storage.objects for select using (bucket_id = 'gallery');
create policy "own gallery upload" on storage.objects for insert
  with check (bucket_id = 'gallery' and auth.uid()::text = (storage.foldername(name))[1]);

-- ============ SEED: 3 COURSES + 10 LESSONS EACH ============
insert into courses (title, slug, month_number, price_kes, description, published) values
 ('Adobe Illustrator','illustrator',1,2500,'Vector drawing, logos and print design.',true),
 ('Adobe Photoshop','photoshop',2,2500,'Photo editing, retouching and advertising design.',true),
 ('Procreate','procreate',3,2500,'Digital illustration and painting.',true);

insert into lessons (course_id, position, title, published)
select c.id, t.pos, t.title, true from courses c join (values
 ('illustrator',1,'Introduction to Graphic Design'),('illustrator',2,'Illustrator workspace and tools'),
 ('illustrator',3,'Selection and shape tools'),('illustrator',4,'Pen Tool and vector drawing'),
 ('illustrator',5,'Typography and text effects'),('illustrator',6,'Colour theory and colour application'),
 ('illustrator',7,'Logo design and brand identity'),('illustrator',8,'Flyer and poster design'),
 ('illustrator',9,'Business card design'),('illustrator',10,'Practical final project'),
 ('photoshop',1,'Introduction to Photoshop'),('photoshop',2,'Photoshop workspace and tools'),
 ('photoshop',3,'Layers and layer masks'),('photoshop',4,'Photo editing and retouching'),
 ('photoshop',5,'Background removal'),('photoshop',6,'Image manipulation'),
 ('photoshop',7,'Colour correction'),('photoshop',8,'Social media graphics'),
 ('photoshop',9,'Advertising poster design'),('photoshop',10,'Practical final project'),
 ('procreate',1,'Introduction to digital illustration'),('procreate',2,'Procreate interface and tools'),
 ('procreate',3,'Brushes and brush settings'),('procreate',4,'Sketching and line art'),
 ('procreate',5,'Layers and blending modes'),('procreate',6,'Digital portrait illustration'),
 ('procreate',7,'Character design'),('procreate',8,'Digital painting'),
 ('procreate',9,'Animation Assist'),('procreate',10,'Final digital artwork project')
) as t(slug,pos,title) on c.slug = t.slug;

-- One assignment per lesson (edit instructions in the admin dashboard)
insert into assignments (lesson_id, title, instructions)
select id, 'Assignment: ' || title, 'Complete the practical task for this lesson and upload your work.' from lessons;

-- ============ MAKE YOURSELF ADMIN ============
-- 1) Register on the site with your email. 2) Then run:
-- update profiles set role = 'admin' where email = 'rajabhassan345@gmail.com';