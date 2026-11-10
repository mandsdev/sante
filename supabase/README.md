# Banco de dados do Sante

O projeto remoto Sante (`santee`) está em `posvneeaxnjxxxgiuiws`, na região de São Paulo (`sa-east-1`), plano Free. No plano Free o projeto pausa sozinho depois de alguns dias sem uso: reative em **Resume project** no painel. A URL do projeto e a publishable key estão no cliente Swift em `sante/SupabaseBackend.swift`. Essa chave é pública e limitada pelas regras RLS; não coloque uma `secret` ou `service_role` key no app.

## Dados e segurança

- `profiles`: nome, CPF, telefone, nascimento e caminho da foto.
- `health_profiles`: peso, altura, tipo sanguíneo, alergias, condições, medicamentos e contato de emergência.
- `patient_documents`: metadados de exames e documentos.
- Buckets privados `profile-photos` e `patient-documents`.
- Row Level Security e políticas de Storage limitam cada conta aos próprios registros e arquivos.
- Um trigger cria as linhas de perfil quando o Supabase Auth cria a conta.

Arquivos usam caminhos começando pelo UUID da conta: `<user-id>/<uuid>.<extensão>`.

## Migrações

- `migrations/20261103000100_initial_patient_data.sql` cria tabelas, políticas, buckets e trigger.
- `migrations/20261103000200_add_cpf_to_profiles.sql` guarda o CPF validado do cadastro e o inclui no trigger.
- `migrations/20261105000100_delete_own_account.sql` cria a função usada pelo botão "Excluir minha conta".

O arquivo `sante/supabase/sante_schema.sql` tem o banco inteiro num script só, para colar no SQL Editor de um projeto novo.

As alterações foram aplicadas pelo SQL Editor do projeto Supabase e verificadas no banco. Para próximas mudanças, use `supabase link --project-ref posvneeaxnjxxxgiuiws` e `supabase db push`; antes do primeiro uso da CLI neste banco, alinhe o histórico das migrações que já foram aplicadas pelo painel.

O app usa o Supabase Auth para cadastro e login, Postgres para os dados pessoais/de saúde e Storage privado para fotos/documentos. Contas criadas com o antigo fluxo exclusivamente local precisam se cadastrar novamente no Supabase.

## Assistente de saúde por IA

A tela `Sante IA` chama a Edge Function `sante-assistant` com a sessão autenticada do Supabase. A função confere se o token é de uma conta logada, limita cada chamada a 12 mensagens e 1.500 caracteres por mensagem, não grava a conversa no banco e envia apenas as mensagens digitadas para a Groq, que pelo plano gratuito não guarda nem usa os dados para treinar IA. Peso, perfil, CPF, prontuário e documentos não são anexados ao pedido. A chave da Groq fica somente nos segredos da função. No simulador do Mac, o app usa o Ollama local (`qwen3.5:4b`) e não chama a função.

Para habilitar as respostas:

1. Configure `GROQ_API_KEY` nos segredos de Edge Functions do projeto Supabase. Opcionalmente, configure `GROQ_MODEL` (o padrão é `openai/gpt-oss-120b`). Nunca coloque essas chaves em arquivos versionados ou no app.
2. Instale e autentique o Supabase CLI, então execute `supabase link --project-ref posvneeaxnjxxxgiuiws` e `supabase functions deploy sante-assistant`.
3. Rode o app com uma conta autenticada do Sante.

Para desenvolvimento local, copie `functions/.env.example` para `functions/.env` e use `supabase functions serve sante-assistant`. O arquivo `.env` está ignorado pelo Git.

A IA conduz uma triagem focada nos sintomas, gera um resumo e mostra a ação para agendar. Essa ação abre um único fluxo de solicitação de consulta: a pessoa escolhe especialidade, data e horário, informa o e-mail do médico e revisa uma mensagem que inclui o resumo da triagem antes de enviar. O envio depende de uma conta de e-mail configurada no dispositivo. O Sante não confirma reservas, não envia mensagens automaticamente e não salva a conversa ou o resumo no perfil. Ainda não há integração com prontuário ou agenda clínica. A IA não diagnostica nem prescreve e, em emergência no Brasil, orienta procurar atendimento imediato ou ligar 192. A interface informa que a IA pode errar e não substitui um profissional.


Além da IA, o próprio app detecta sinais de emergência no que a pessoa escreve (dor no peito, falta de ar, risco de se machucar…) e mostra na hora o botão de ligar 192 e, quando for o caso, o CVV 188, sem esperar a IA.
