-- =====================================================================
-- Talentos Brasileiros - verificação e reforço de segurança no Supabase
-- Rode no SQL Editor do Supabase. Comece pela PARTE 1 (só leitura).
-- NÃO rode a parte 3 sem comparar com o que já existe: ela é só referência.
-- =====================================================================

-- PARTE 1 - AUDITORIA (só leitura, pode rodar sempre)
-- 1.1  Todas as tabelas devem aparecer com rls_ativo = true
select schemaname, tablename, rowsecurity as rls_ativo
from pg_tables
where schemaname = 'public'
order by tablename;

-- 1.2  Políticas existentes (confira quem pode ler/alterar cada tabela)
select tablename, policyname, cmd as operacao, roles, qual as condicao_usar, with_check as condicao_gravar
from pg_policies
where schemaname = 'public'
order by tablename, cmd;

-- 1.3  O que o visitante anônimo (anon) consegue fazer em cada tabela.
--      athlete_contacts e athlete_access NÃO devem ter SELECT para anon.
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public'
order by table_name, privilege_type;

-- PARTE 2 - TRAVAS DE DADOS (seguras: valem só para registros novos/alterados)
-- Impedem endereço (slug) fora do padrão, WhatsApp inválido e abas gigantes.
alter table public.athletes
  add constraint athletes_slug_formato check (slug ~ '^[a-z0-9-]{3,40}$') not valid;
alter table public.athletes
  add constraint athletes_tema_tamanho check (pg_column_size(tema) < 200000) not valid;
alter table public.athlete_contacts
  add constraint contacts_whatsapp_formato check (whatsapp ~ '^[0-9]{10,15}$') not valid;
alter table public.athlete_access
  add constraint access_email_minusculo check (email = lower(email)) not valid;

-- PARTE 3 - REFERÊNCIA DE POLÍTICAS (NÃO rode às cegas; compare com a Parte 1.2)
-- Regra esperada:
--   athletes          : qualquer pessoa LÊ abas publicadas; só o dono (athlete_access) ou admin ALTERA.
--   athlete_access    : cada pessoa lê só as próprias linhas; só admin cria/remove.
--   athlete_contacts  : NINGUÉM lê direto; só o dono/admin grava; o público usa get_whatsapp().
--   admins            : cada pessoa vê só a própria linha; ninguém grava pelo site.
--
-- alter table public.athletes         enable row level security;
-- alter table public.athlete_access   enable row level security;
-- alter table public.athlete_contacts enable row level security;
-- alter table public.admins           enable row level security;
--
-- create policy "ler abas publicadas" on public.athletes for select
--   using (published = true or exists (select 1 from public.athlete_access a
--          where a.slug = athletes.slug and a.email = lower(auth.jwt() ->> 'email'))
--          or exists (select 1 from public.admins d where d.user_id = auth.uid()));
--
-- create policy "dono altera a propria aba" on public.athletes for update
--   using (exists (select 1 from public.athlete_access a
--          where a.slug = athletes.slug and a.email = lower(auth.jwt() ->> 'email')))
--   with check (exists (select 1 from public.athlete_access a
--          where a.slug = athletes.slug and a.email = lower(auth.jwt() ->> 'email')));
--
-- A função get_whatsapp deve ser SECURITY DEFINER com search_path vazio e devolver
-- o número só de abas publicadas:
-- create or replace function public.get_whatsapp(p_slug text) returns text
--   language sql security definer set search_path = '' as $$
--   select c.whatsapp from public.athlete_contacts c
--   join public.athletes a on a.slug = c.slug
--   where c.slug = p_slug and a.published = true $$;
