-- =====================================================================
-- Etapa 2 · Carteiras separadas por pessoa + sócios por empresa
-- Cole TUDO no SQL Editor e clique em Run. Pode rodar mais de uma vez.
-- =====================================================================

-- 1) Novas colunas: quem criou o registro e a qual credor ele pertence
alter table public.registros add column if not exists dono uuid default auth.uid();
alter table public.registros add column if not exists credor_id text
  generated always as (case when colecao = 'credores' then id else data->>'credorId' end) stored;

-- 2) Quem acessa cada credor (carteira)
create table if not exists public.acessos (
  email     text not null,
  credor_id text not null,
  criado_em timestamptz not null default now(),
  primary key (email, credor_id)
);

-- 3) Tudo o que já existe passa a ser do Marcelo
update public.registros set dono = (select user_id from public.usuarios where lower(email) = 'marcelo@grupowqs.com')
 where dono is null;
insert into public.acessos (email, credor_id)
select 'marcelo@grupowqs.com', id from public.registros where colecao = 'credores'
on conflict do nothing;

-- 4) Funções de permissão
create or replace function public.pode_credor(cid text)
returns boolean language sql stable security definer set search_path = public as $$
  select cid is not null and exists (
    select 1 from public.acessos where lower(email) = lower(auth.jwt() ->> 'email') and credor_id = cid)
$$;

create or replace function public.sou_dono_credor(cid text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.registros where colecao = 'credores' and id = cid and dono = auth.uid())
$$;

create or replace function public.devedor_visivel(did text, d_dono uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select d_dono = auth.uid() or exists (
    select 1 from public.registros r
    join public.acessos a on a.credor_id = r.credor_id and lower(a.email) = lower(auth.jwt() ->> 'email')
    where r.colecao = 'dividas' and r.data->>'devedorId' = did)
$$;

create or replace function public.registro_visivel(col text, rid text, cid text, d_dono uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when public.papel_atual() is null then false
    when col = 'config'    then true
    when col = 'devedores' then public.devedor_visivel(rid, d_dono)
    when col = 'auditoria' then case when cid is null then d_dono = auth.uid() else public.pode_credor(cid) end
    else public.pode_credor(cid)
  end
$$;

create or replace function public.pode_gravar(col text, rid text, dados jsonb)
returns boolean language sql stable security definer set search_path = public as $$
  select public.papel_atual() = 'editor' and case
    when col in ('credores', 'devedores', 'config') then true
    when col = 'auditoria' then (dados->>'credorId') is null or public.pode_credor(dados->>'credorId')
    else public.pode_credor(dados->>'credorId')
  end
$$;

-- 5) Quem cria um credor ganha acesso a ele automaticamente
create or replace function public.dar_acesso_credor()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.colecao = 'credores' and (auth.jwt() ->> 'email') is not null then
    insert into public.acessos (email, credor_id) values (lower(auth.jwt() ->> 'email'), new.id)
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists trg_dar_acesso on public.registros;
create trigger trg_dar_acesso after insert on public.registros
  for each row execute function public.dar_acesso_credor();

-- 6) Regras de segurança dos registros
drop policy if exists registros_ler on public.registros;
create policy registros_ler on public.registros for select to authenticated
  using (public.registro_visivel(colecao, id, credor_id, dono));
drop policy if exists registros_inserir on public.registros;
create policy registros_inserir on public.registros for insert to authenticated
  with check (public.pode_gravar(colecao, id, data));
drop policy if exists registros_alterar on public.registros;
create policy registros_alterar on public.registros for update to authenticated
  using (public.papel_atual() = 'editor' and public.registro_visivel(colecao, id, credor_id, dono))
  with check (public.pode_gravar(colecao, id, data));
drop policy if exists registros_excluir on public.registros;
create policy registros_excluir on public.registros for delete to authenticated
  using (public.papel_atual() = 'editor' and case when colecao = 'devedores' then dono = auth.uid()
         else public.registro_visivel(colecao, id, credor_id, dono) end);

-- 7) Regras da tabela de acessos (só quem cadastrou a empresa compartilha)
alter table public.acessos enable row level security;
drop policy if exists acessos_ler on public.acessos;
create policy acessos_ler on public.acessos for select to authenticated
  using (lower(email) = lower(auth.jwt() ->> 'email') or public.sou_dono_credor(credor_id));
drop policy if exists acessos_inserir on public.acessos;
create policy acessos_inserir on public.acessos for insert to authenticated
  with check (public.sou_dono_credor(credor_id)
              and exists (select 1 from public.usuarios u where lower(u.email) = lower(acessos.email)));
drop policy if exists acessos_excluir on public.acessos;
create policy acessos_excluir on public.acessos for delete to authenticated
  using (public.sou_dono_credor(credor_id) and lower(email) <> lower(auth.jwt() ->> 'email'));

-- 8) Documentos anexados: só quem tem acesso ao credor
drop policy if exists anexos_ler on storage.objects;
create policy anexos_ler on storage.objects for select to authenticated
  using (bucket_id = 'anexos' and public.papel_atual() is not null
         and (public.pode_credor(split_part(name, '/', 1)) or owner = auth.uid()));
drop policy if exists anexos_enviar on storage.objects;
create policy anexos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'anexos' and public.papel_atual() = 'editor'
              and public.pode_credor(split_part(name, '/', 1)));
