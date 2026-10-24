-- =====================================================================
-- Gestão de Contas a Receber — estrutura do banco no Supabase
-- Cole TUDO no Supabase: SQL Editor → New query → Run.
-- Pode rodar mais de uma vez sem problema.
-- =====================================================================

-- 1) Usuários autorizados e seus papéis
create table if not exists public.usuarios (
  email      text primary key,
  nome       text,
  papel      text not null default 'consulta' check (papel in ('editor','consulta')),
  user_id    uuid,
  criado_em  timestamptz not null default now()
);

-- 2) Todos os registros do sistema (credores, devedores, dívidas, pagamentos,
--    ajustes, contatos, auditoria e configurações), separados por coleção
create table if not exists public.registros (
  colecao        text not null,
  id             text not null,
  data           jsonb not null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid,
  primary key (colecao, id)
);

-- 3) Funções de permissão
create or replace function public.papel_atual()
returns text language sql stable security definer set search_path = public as $$
  select papel from public.usuarios where lower(email) = lower(auth.jwt() ->> 'email')
$$;

create or replace function public.meu_perfil()
returns setof public.usuarios language plpgsql security definer set search_path = public as $$
begin
  update public.usuarios set user_id = auth.uid()
   where lower(email) = lower(auth.jwt() ->> 'email') and (user_id is null or user_id <> auth.uid());
  return query select * from public.usuarios where lower(email) = lower(auth.jwt() ->> 'email');
end $$;

-- 4) Segurança por linha: só usuários autorizados leem; só editores alteram
alter table public.usuarios  enable row level security;
alter table public.registros enable row level security;

drop policy if exists usuarios_ler on public.usuarios;
create policy usuarios_ler on public.usuarios for select to authenticated using (public.papel_atual() is not null);

drop policy if exists registros_ler on public.registros;
create policy registros_ler on public.registros for select to authenticated using (public.papel_atual() is not null);
drop policy if exists registros_inserir on public.registros;
create policy registros_inserir on public.registros for insert to authenticated with check (public.papel_atual() = 'editor');
drop policy if exists registros_alterar on public.registros;
create policy registros_alterar on public.registros for update to authenticated using (public.papel_atual() = 'editor') with check (public.papel_atual() = 'editor');
drop policy if exists registros_excluir on public.registros;
create policy registros_excluir on public.registros for delete to authenticated using (public.papel_atual() = 'editor');

-- 5) Atualização em tempo real entre aparelhos
do $$ begin
  alter publication supabase_realtime add table public.registros;
exception when duplicate_object then null; end $$;

-- 6) Documentos anexados (bucket privado)
insert into storage.buckets (id, name, public) values ('anexos', 'anexos', false)
on conflict (id) do nothing;

drop policy if exists anexos_ler on storage.objects;
create policy anexos_ler on storage.objects for select to authenticated using (bucket_id = 'anexos' and public.papel_atual() is not null);
drop policy if exists anexos_enviar on storage.objects;
create policy anexos_enviar on storage.objects for insert to authenticated with check (bucket_id = 'anexos' and public.papel_atual() = 'editor');

-- 7) Você como primeiro usuário, com acesso de editor
insert into public.usuarios (email, nome, papel)
values ('marcelo@grupowqs.com', 'Marcelo', 'editor')
on conflict (email) do update set papel = 'editor';

-- Para dar acesso a outra pessoa no futuro:
--   insert into public.usuarios (email, nome, papel) values ('pessoa@empresa.com', 'Nome', 'consulta');
--   e crie o login dela em Authentication → Users → Add user.
