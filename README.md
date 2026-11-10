# sante

App iOS de saúde feito em SwiftUI. Ajuda a pessoa a organizar seus dados de saúde, conversar com uma triagem por IA que monta um resumo dos sintomas e pedir uma consulta ao médico por e-mail.

> Projeto pessoal e de estudo. Não é um serviço médico e não substitui atendimento profissional. Em emergências, ligue 192.

## O que o app faz

- **Cadastro e login** com Supabase (e-mail e senha, recuperação de senha por código).
- **Prontuário**: dados de saúde (tipo sanguíneo, alergias, medicamentos…), foto e documentos como exames e receitas.
- **Triagem por IA**: perguntas curtas sobre os sintomas e um "Resumo para a consulta" no final.
  - **Proteção de emergência**: se a pessoa escreve sinais como dor no peito ou falta de ar, o app mostra na hora o botão para ligar 192 (e o CVV 188 em caso de risco de se machucar), sem depender da IA.
- **Pedido de consulta** por e-mail, com o resumo da triagem e os dados do paciente.
- **Excluir conta** e apagar todos os dados pelo próprio app.
- Tela de abertura com **moldura de folhas em parallax**, que se mexe com a inclinação do iPhone.

## Tecnologias

| Parte | Ferramenta |
| --- | --- |
| App | Swift, SwiftUI, CoreMotion |
| Banco, login e arquivos | [Supabase](https://supabase.com) (Postgres com Row Level Security), região São Paulo |
| IA no simulador | [Ollama](https://ollama.com) com o modelo `qwen3.5:4b`, rodando no Mac |
| IA no iPhone (opcional) | Função do Supabase `sante-assistant` usando a [Groq](https://groq.com) |

## Como rodar

1. Abra `sante.xcodeproj` no Xcode.
2. Instale o Ollama e baixe o modelo: `ollama pull qwen3.5:4b`. Deixe o Ollama aberto.
3. Escolha um simulador de iPhone e aperte **⌘R**.

### Usar o seu próprio Supabase

1. Crie um projeto no Supabase.
2. No SQL Editor, rode o arquivo [`sante/supabase/sante_schema.sql`](sante/supabase/sante_schema.sql). Ele cria as tabelas, as regras de segurança, os buckets de arquivos e a função de excluir conta. (A pasta [`supabase/`](supabase/) tem o mesmo banco em migrações, para quem usa a Supabase CLI.)
3. Em `sante/SupabaseBackend.swift`, troque o endereço e a chave **publicável** (`sb_publishable_…`) pelas do seu projeto.

A chave publicável pode ficar no código: quem protege os dados são as regras do banco (cada pessoa só acessa os próprios dados). **Nunca** coloque no código uma chave secreta (`sb_secret_…`) ou chaves de serviços de IA. Elas ficam só nos Secrets do Supabase.

## Testes

No Xcode, aperte **⌘U**. Os testes rodam no Mac e conferem as partes mais importantes da lógica:

- **Emergência**: frases de emergência sempre mostram o aviso do SAMU (192) e, em risco de se machucar, o CVV (188); sintomas comuns não disparam o aviso.
- **Fim da triagem**: o app reconhece o resumo da IA e monta o texto que vai para o médico.
- **Validações**: CPF, e-mail, telefone, regras de senha e código recebido por e-mail.

## Estrutura

| Arquivo | O que tem |
| --- | --- |
| `sante/WelcomeView.swift` | Abertura com parallax, login e recuperação de senha |
| `sante/SingupView.swift` | Cadastro e confirmação de e-mail |
| `sante/ContentView.swift` | Tela inicial e guia de primeiro uso |
| `sante/AssistantChatView.swift` | Triagem por IA e proteção de emergência |
| `sante/AppointmentBookingView.swift` | Pedido de consulta por e-mail |
| `sante/PatientProfileView.swift` | Perfil, dados de saúde e documentos |
| `sante/AccountStore.swift` | Conta, sessão e comunicação com o Supabase |
| `sante/SanteTheme.swift` | Cores, fontes e componentes visuais |
| `sante/SanteValidation.swift` | Regras de CPF, e-mail, telefone, senha e código |
| `santeTests/` | Testes automatizados (rode com ⌘U no Xcode) |
| `supabase/` | Migrações do banco e código da função da triagem |
