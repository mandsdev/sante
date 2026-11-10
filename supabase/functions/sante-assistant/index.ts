// Sante — função da triagem (Edge Function "sante-assistant").
// Recebe a conversa do app, confere se a pessoa está logada de verdade
// e pede a próxima resposta à Groq (plano gratuito; não guarda nem treina com os dados).
// Segredos necessários em Edge Functions → Secrets: GROQ_API_KEY (obrigatório) e GROQ_MODEL (opcional).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

type ChatMessage = { role: "user" | "assistant"; content: string }

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

// Mesmas instruções usadas no app (AssistantChatView.swift).
// O app reconhece o fim da triagem pelas frases "Resumo para a consulta"
// e "Agende sua consulta" — não mude essas duas sem mudar o TriageReply.swift.
const TRIAGE_INSTRUCTIONS = "Você é a IA de triagem do Sante. Converse em português brasileiro como uma pessoa atenciosa: com gentileza, simplicidade e naturalidade, sem soar formal ou robótica. Seu trabalho é entender o que a pessoa está sentindo e preparar um resumo para a consulta. Comece com uma pergunta acolhedora e direta sobre o que a pessoa está sentindo. Faça uma pergunta curta por mensagem, usando palavras do dia a dia. Demonstre que ouviu a resposta com uma frase breve e natural quando isso ajudar, sem repetir sempre as mesmas expressões. Pergunte somente sobre os sintomas e apenas o que ainda não foi informado: por exemplo, quando começou, onde sente e como está agora. Não junte várias perguntas numa frase, não use termos médicos sem explicar, não investigue histórico ou medicamentos e não ofereça informação geral de saúde. Quando já houver informações suficientes, pare de perguntar e faça um resumo curto, simples e fiel ao que a pessoa contou, com o título \"Resumo para a consulta\". Não invente informações nem diagnóstico. Diga que o resumo é para mostrar ao médico e não afirme que foi enviado. Depois do resumo, escreva exatamente \"Agende sua consulta no aplicativo Sante.\" Se a pessoa descrever sinais de emergência ou risco imediato — por exemplo dor ou aperto no peito (principalmente se for para o braço, costas ou queixo), falta de ar, desmaio, rosto ou boca torta, fraqueza ou dormência de um lado do corpo, fala enrolada, convulsão, sangramento intenso, reação alérgica com inchaço na garganta, ou pensamentos de se machucar — NÃO faça mais perguntas: diga com carinho e clareza para ligar agora para o SAMU no 192 ou ir ao pronto-socorro mais próximo. Se a pessoa falar em se machucar ou tirar a própria vida, diga também que ela pode ligar para o CVV no 188, a qualquer hora."

/** Confere com o Supabase se o token é de uma pessoa logada. */
async function isSignedIn(authorization: string): Promise<boolean> {
  const supabaseURL = Deno.env.get("SUPABASE_URL")
  if (!supabaseURL) return false
  // Projetos novos usam chaves "publishable"; os antigos, a chave "anon".
  let anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  if (!anonKey) {
    try {
      const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}")
      anonKey = Object.values(keys).find((value) => typeof value === "string") as string ?? ""
    } catch { /* sem chave publicável */ }
  }
  if (!anonKey) return false
  try {
    const response = await fetch(`${supabaseURL}/auth/v1/user`, {
      headers: { "Authorization": authorization, "apikey": anonKey },
      signal: AbortSignal.timeout(8_000),
    })
    if (!response.ok) return false
    const user = await response.json()
    return typeof user?.id === "string"
  } catch {
    return false
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (request.method !== "POST") return json({ error: "Método não permitido." }, 405)

  const authorization = request.headers.get("Authorization") ?? ""
  if (!authorization.startsWith("Bearer ") || !(await isSignedIn(authorization))) {
    return json({ error: "Entre na sua conta para usar a triagem." }, 401)
  }

  const apiKey = Deno.env.get("GROQ_API_KEY")
  if (!apiKey) return json({ error: "A triagem ainda não foi configurada." }, 503)

  let messages: ChatMessage[]
  try {
    const body = await request.json()
    if (!Array.isArray(body.messages) || body.messages.length === 0 || body.messages.length > 12) {
      return json({ error: "Envie uma conversa válida." }, 400)
    }
    messages = body.messages.map((message: unknown) => {
      if (!message || typeof message !== "object") throw new Error("invalid")
      const item = message as Record<string, unknown>
      if ((item.role !== "user" && item.role !== "assistant") || typeof item.content !== "string") {
        throw new Error("invalid")
      }
      const content = item.content.trim()
      if (!content || content.length > 1500) throw new Error("invalid")
      return { role: item.role, content }
    })
    if (messages.at(-1)?.role !== "user") return json({ error: "Envie uma mensagem para continuar." }, 400)
  } catch {
    return json({ error: "Não foi possível ler as mensagens." }, 400)
  }

  try {
    const upstream = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-120b",
        temperature: 0.4,
        max_completion_tokens: 700,
        reasoning_effort: "low",
        messages: [
          { role: "system", content: TRIAGE_INSTRUCTIONS },
          ...messages.map(({ role, content }) => ({ role, content })),
        ],
      }),
      signal: AbortSignal.timeout(40_000),
    })

    if (!upstream.ok) {
      console.error("Groq request failed with status", upstream.status, (await upstream.text()).slice(0, 300))
      return json({ error: "A triagem está indisponível no momento." }, 502)
    }

    const result = await upstream.json()
    const reply = String(result?.choices?.[0]?.message?.content ?? "").trim()

    if (!reply) return json({ error: "A triagem não conseguiu responder. Tente novamente." }, 502)
    return json({ reply })
  } catch (error) {
    console.error("Assistant request failed", error instanceof Error ? error.message : "unknown error")
    return json({ error: "A triagem está indisponível no momento." }, 502)
  }
})
