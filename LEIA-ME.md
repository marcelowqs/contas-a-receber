# Gestão de Contas a Receber — versão Vercel + Supabase

## Arquivos
- `index.html` — o aplicativo completo.
- `supabase/schema.sql` — cria o banco, as permissões e o armazenamento de documentos.

## Passo a passo
1. **Supabase → SQL Editor → New query:** cole todo o conteúdo de `supabase/schema.sql` e clique em **Run**.
2. **Supabase → Authentication → Users → Add user → Create new user:** e-mail `marcelo@grupowqs.com`, uma senha sua e a opção **Auto Confirm User** marcada.
3. **Supabase → Authentication → Sign In / Providers → Email:** desligue **Allow new users to sign up**, para ninguém se cadastrar sozinho.
4. **index.html:** nas linhas `SUPABASE_URL` e `SUPABASE_KEY`, no início do segundo bloco `<script>`, cole a Project URL e a chave anon/publishable.
5. **Vercel:** publique a pasta. Depois copie o endereço do site e cole em Supabase → Authentication → URL Configuration → **Site URL**, para o link de "esqueci minha senha" funcionar.
6. **Migrar os dados do app antigo:** no app antigo, Configurações → Baixar backup. No novo, Configurações → Restaurar backup.
   Os documentos anexados no app antigo não são transferidos e precisam ser anexados de novo.

## Dar acesso a outra pessoa
No SQL Editor:
```sql
insert into public.usuarios (email, nome, papel) values ('pessoa@empresa.com', 'Nome', 'consulta'); -- ou 'editor'
```
Depois crie o login dela em Authentication → Users → Add user.

## Backup
O Supabase guarda tudo. Ainda assim, baixe de vez em quando o backup em Configurações → Baixar backup.
