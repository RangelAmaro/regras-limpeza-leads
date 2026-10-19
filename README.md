# Regras de limpeza e qualificação de lead

Especificação dos filtros que limpam a base de leads antes de contar lead, MQL e custo por resultado. Se o dashboard aplicar estas regras, nesta ordem, os números batem com os da reunião de métricas.

> **Valores mascarados.** Este repositório é público. Os e-mails de colaborador, os identificadores do banco e das contas de anúncio e os números de leads e de investimento não estão aqui: no texto e no SQL aparecem como `<MARCADOR>`. Os valores reais ficam com o gestor de tráfego.

## Resumo em uma tela

1. Ler a **tabela do funil**, nunca a `geral` (seção 1).
2. Converter a data para **horário de Brasília** antes de cortar o período. Duas tabelas já gravam em Brasília e não se convertem (seção 2).
3. Tirar, nesta ordem:
   1. lead sem e-mail;
   2. e-mail interno ou de exemplo;
   3. e-mail de colaborador;
   4. "teste" no nome ou no e-mail;
   5. telefone com dígito repetido;
   6. telefone curto;
   7. lead sintético `e2e-check`.

   **Nunca** filtrar "teste" na UTM (seção 3).
4. Tirar duplicado por e-mail **por último**, ficando com a primeira entrada do período (seção 4).
5. Aplicar a régua de MQL do funil: **MQL = semi-qualificado + qualificado** (seção 5).

O SQL completo está em [`regras.sql`](regras.sql).

---

## 1. De onde ler

| Funil | Tabela de lead | Observação |
|---|---|---|
| FAP-01 · Aplicação | `[Leads] FAP01` | |
| FAP-05 · Remarketing | `[Leads] [GHL] Remarketing` | É a lista de captação do FAP-05. Cada linha traz `calendario = Calendário Remarketing`, mas conta como lead. A tabela `[Leads] FAP05` existe e está vazia |
| Site Institucional | `[Leads] Site Institucional` | Inbound, sem UTM |
| FAQ-03 · Playbook | `[Leads] [Isca Gratuita] PlayBook` | |
| FAQ-01 · MSS (Quiz) | `[Leads] [Inlead] Quiz` | |
| FAQ-06 · Pop-Up | `[Leads] [FAQ06] Pop-Up` | |
| FAP-06 · Espaço de Eventos | `[Leads] FAP06` | |
| FAP-09 · Imersão Comercial | `[Leads] Imersao Estruturado` | Não confundir com a do FAQ-05 |
| FAQ-05 · Aula Comercial | `[Leads] Aula Comercial Estruturado` | |
| FAP-07 · Med Day | `[Leads] MedDay` | Funil desativado |
| FAP-08 · Mentoria | `[Leads] Pag Mentoria` | Funil desativado |

> ⚠️ **Não use a tabela `geral` para contar lead.**
> - **Apagamento automático:** um job do `pg_cron` roda toda meia-noite e **apaga da `geral` todo e-mail cujo nome termina em número** (`joao1990@`, `maria2@`). Por isso ela fica com uns 20% a menos que as tabelas de funil.
> - **Funis que não entram:** a `geral` não recebe FAP-06, FAP-09, FAQ-05, Med Day nem Mentoria.

Os nomes das tabelas têm colchete e espaço: no SQL vão entre aspas duplas (`FROM "[Leads] FAP01"`). Todas as colunas de conteúdo são `text`, inclusive `faturamento`.

---

## 2. Data e fuso

O período é fechado em **horário de Brasília**: de `AAAA-MM-DD 00:00` do primeiro dia a `23:59:59` do último. Converter primeiro e só depois cortar.

| Tabela | Coluna | Como converter |
|---|---|---|
| `[Leads] FAP01` | `data_padronizada` | UTC de verdade: `data_padronizada AT TIME ZONE 'America/Sao_Paulo'` |
| `[Leads] [Isca Gratuita] PlayBook` | `data_padronizada` | UTC de verdade: idem |
| `[Leads] [FAQ06] Pop-Up` | `data_padronizada` | idem |
| `[Leads] FAP06` | `data_padronizada` | idem |
| `[Leads] Imersao Estruturado` | `created_at` | idem (a tabela não tem `data_padronizada`) |
| `[Leads] Aula Comercial Estruturado` | `created_at` | idem |
| `[Leads] [GHL] Remarketing` | `created_at` | idem |
| **`[Leads] [Inlead] Quiz`** | `data_padronizada` | **Já está em Brasília, com rótulo de UTC. NÃO converter:** `data_padronizada AT TIME ZONE 'UTC'` |
| **`[Leads] Site Institucional`** | `data_padronizada` | **Já está em Brasília, com rótulo de UTC. NÃO converter:** idem |
| `agendamentos_playbook` e `agendamentos_fap` | `created_at` | UTC de verdade. **Não usar `data_padronizada`**: na `agendamentos_playbook` é NULL em todas as linhas e na `agendamentos_fap` nem existe |

Erro típico: cortar o dia em UTC. Um lead gravado entre 00:00 e 02:59 UTC é do **dia anterior** em Brasília.

---

## 3. Filtros de limpeza

Aplicados em todos os funis, **nesta ordem**. A ordem só muda em qual motivo o lead aparece; o total limpo é o mesmo. Comparar sempre o e-mail normalizado: `lower(btrim(email))`.

| # | Filtro | Regra exata |
|---|---|---|
| 1 | Sem e-mail | `email` vazio ou nulo sai. **Exceção: FAP-05** (ver seção 4) |
| 2 | Domínio interno e de exemplo | sai se contém `@<DOMINIO_INTERNO>` (o domínio de e-mail da própria empresa) ou `example.com` |
| 3 | Colaborador | sai se for `<EMAIL_COLABORADOR_1>` ou casar com a regex `<REGEX_COLABORADOR_2>` |
| 4 | Teste | sai se o **e-mail** contém `teste` ou o **nome** contém `teste` (sem diferenciar maiúscula) |
| 5 | Telefone com dígito repetido | só dígitos (`regexp_replace(telefone, '\D', '', 'g')`) e sai se tiver o mesmo dígito 8 vezes seguidas ou mais: regex `(\d)\1{7,}` (pega `99999999`, `11999999999`, `00000000`) |
| 6 | Telefone curto | só dígitos, sai com **menos de 10 dígitos** (DDD + número) |
| 7 | Lead sintético | sai `utm_source = 'e2e-check'` (monitoramento automático de um dos formulários) |

### Os colaboradores (filtro 3)

São dois colaboradores que entram nos formulários e não são lead. O domínio interno do filtro 2 não pega nenhum deles, porque os dois usam e-mail pessoal (gmail).

- **Colaborador 1:** um e-mail só, fixo: `<EMAIL_COLABORADOR_1>`.
- **Colaborador 2 (tecnologia):** testa os formulários e cada teste sai com um e-mail diferente.
  - **Variações conhecidas:** já apareceram 14, com número no fim, prefixo, sufixo de versão, outro domínio e até um erro de digitação no domínio.
  - **Por isso o filtro é uma regex** (`<REGEX_COLABORADOR_2>`), não uma lista. Ela casa o nome de usuário dele com e sem ponto, com o prefixo `dev` e com o `qa` opcional.
  - **Cuidado com regex aberta demais:** existem leads reais de fora com parte desse nome no e-mail. A regex exige o prefixo dele e não pega essas pessoas.
- Os dois valores reais estão com o gestor.

### "Teste" NÃO se filtra na UTM

A campanha de teste de criativos se chama `[TESTE-CRIATIVOS]`. Ela gera **lead real**, pago, e é uma das campanhas que mais traz MQL. Por isso:
- `teste` sai **só** no nome e no e-mail;
- **nunca** filtre `utm_campaign`, `utm_source`, `utm_medium`, `utm_content` ou `utm_term` por `teste`.

Num funil medido em setembro de 2026, o filtro na UTM teria apagado 7 de cada 8 leads com campanha.

---

## 4. Duplicidade de entradas

- **Por último**, depois de todos os filtros da seção 3.
- **Chave:** e-mail normalizado, `lower(btrim(email))`.
- **Qual fica:** a **primeira entrada do período**, pela data. As outras saem.
- **Escopo:** **dentro do mesmo funil e do mesmo período.**
  - A mesma pessoa em dois funis conta uma vez em cada funil.
  - A mesma pessoa que entrou antes do período e voltou dentro dele conta no período.
- **Classificação:** o cargo e o faturamento que valem são os da entrada que ficou (a primeira).
- **Exceção, FAP-05:** a `[Leads] [GHL] Remarketing` costuma vir **sem e-mail** (a maior parte das linhas). Nela, a identidade é o e-mail e, sem e-mail, os **últimos 8 dígitos do telefone**: `coalesce(nullif(lower(btrim(email)), ''), right(telefone_so_digitos, 8))`. O filtro 1 (sem e-mail) não se aplica a ela. Os filtros 5 e 6 de telefone valem do mesmo jeito. Se o filtro exigir e-mail nesse funil, ele perde a maior parte dos leads.

---

## 5. Régua de MQL por funil

**MQL = semi-qualificado + qualificado.** Os dois aparecem separados e o MQL é a soma. Só se classifica quem é **decisor** pelo cargo. Quem não é decisor continua contando como lead, mas não entra no MQL.

Os valores abaixo são os textos exatos gravados no banco. As tabelas misturam o formato atual (slug) com rótulos antigos, e os dois contam.

### FAP-01 · Aplicação, FAQ-03 · Playbook, Site Institucional e FAQ-06 · Pop-Up

**Decisor (`cargo`):** `socio-empresario`, `Sócio/Empresário`, `Sócio ou Fundador`, `Sócio / Empresário`.

| Degrau | `faturamento` |
|---|---|
| **Qualificado** (acima de R$ 50 mil) | `50k-100k`, `100k-300k`, `300k-500k`, `500k-1m`, `acima-1m`, `Entre R$50 mil a R$100 mil`, `Entre R$50 mil e R$100 mil`, `Entre R$100 mil a R$300 mil`, `Entre R$100 mil e R$300 mil`, `Entre R$300 mil e R$500 mil`, `Entre R$300 mil a R$1 milhão`, `Entre R$500 mil e R$1 milhão`, `Entre R$500 mil a R$1 milhão`, `Acima de R$1 milhão`, `Acima de R$ 1 milhão`, `Mais de R$1 milhão por mês` |
| **Semi-qualificado** (R$ 40 a 50 mil) | `40k-50k`, `Entre R$40 mil e R$50 mil`, e os legados de R$ 30 a 50 mil: `30k-50k`, `Entre R$30 mil a R$50 mil`, `Entre R$30 mil e R$50 mil`, `R$30 mil a R$50 mil` |
| Não MQL | `abaixo-40k`, `abaixo-30k`, `Abaixo de R$40 mil` e as faixas abaixo de R$ 30 mil |

- **Mudança de 02/10/2026:** as páginas trocaram `abaixo-30k`/`30k-50k` por `abaixo-40k`/`40k-50k`. Em período que atravessa essa data, conte os dois códigos de semi juntos.
- **Site Institucional:** `Selecionar` no cargo ou no faturamento quer dizer que a pessoa não respondeu. É lead, mas não MQL.
- **Rótulo antigo que escapa:** no PlayBook, o histórico `Empresário ou Empreendedor` não entra como decisor (é dado antigo, fora das semanas recentes).

### FAQ-01 · MSS (Quiz)

As faixas do quiz não têm corte em R$ 50 mil, por isso a régua é outra.

**Decisor (`cargo`, que no quiz é o perfil):** `Dono ou Sócio`, `Eu sou empresário e tenho um time comercial`, `Eu sou empresário e eu mesmo vendo`.

Ficam fora como não decisor: `Eu sou profissional de vendas`, `Vendedor`, `Gestor Comercial`, `Outro` e `Sou curioso e não atuo com vendas`.

| Degrau | `faturamento` |
|---|---|
| **Qualificado** (acima de R$ 100 mil) | `Entre R$100 e R$500 mil`, `Entre R$500 e R$ 1 milhão`, `Acima de R$ 1 milhão` |
| **Semi-qualificado** (R$ 30 a 100 mil) | `Entre R$30 e R$100 mil` |
| Não MQL | `Até R$30 mil` |

### FAQ-05 · Aula Comercial

**Decisor:** `cargo = 'socio'`. O `diretor` fica fora.

| Degrau | `faturamento` |
|---|---|
| **Qualificado** (acima de R$ 100 mil) | `100k-500k`, `500k-mais` |
| **Semi-qualificado** | `30k-100k` |
| Não MQL | `ate-30k` |

A coluna `qualificado` da tabela **não** é o MQL: não use.

### FAP-09 · Imersão Comercial

**MQL:** `cargo IN ('socio', 'diretor')` **e** `faturamento <> 'ate_40'`. A régua dele não tem semi; para dividir, a faixa:

| Degrau | `faturamento` (com cargo `socio` ou `diretor`) |
|---|---|
| **Qualificado** (acima de R$ 150 mil) | `150_500`, `500_mais` |
| **Semi-qualificado** (R$ 40 a 150 mil) | `40_150` |
| Não MQL | `ate_40`, ou cargo `gestor` ou `outro` |

A coluna `qualificado` da tabela e o evento de pixel de lead qualificado desse funil olham só o faturamento e contam `gestor` e `outro`: não use como MQL.

### Funis sem régua de MQL (contam só lead)

- **FAP-05 · Remarketing:** a lista não traz cargo nem faturamento, e o público já é lead.
- **FAP-06 · Espaço de Eventos:** é locação, decide por custo por lead. O `cargo` é tipo de cliente (`dono-evento`, `agencia`, `assessoria`, `outro`).
- **FAP-07 · Med Day e FAP-08 · Mentoria:** desativados.

### Taxa de qualificação

MQL ÷ lead limpo, do mesmo funil e período. Nas somas por frente e no total, os leads dos funis sem régua entram no denominador.

---

## 6. Pré-agendamentos

- **Tabelas:** `agendamentos_playbook` (Playbook) e `agendamentos_fap` (FAP-01).
- **Data:** `created_at` em Brasília.
- **Limpeza:** os filtros 2 a 7 da seção 3.
- **Duplicado:** por e-mail ou, sem e-mail, pelos últimos 8 dígitos do telefone. Sem e-mail não sai: uma parte relevante das linhas da `agendamentos_playbook` não tem e-mail.
- **Divisão:** por `calendario`:
  - Playbook: `Playbook - Qualificado` / `Playbook - Semi Qualificado`;
  - FAP-01: `FAP - Qualificado` / `FAP - SemiQualificado`.
- **O Playbook gera aplicação:** o lead se cadastra e depois pré-agenda. Na reunião, o pré-agendamento dele é **citado junto da Aplicação, mas não soma no lead nem no custo por lead**.
- **Campanha:** a `utm_campaign` dessas tabelas quase sempre vem vazia. Para atribuir campanha, case o e-mail com a tabela de lead do funil.

---

## 7. Investido

- **Meta:**
  - só a conta de anúncio principal (`<CONTA_META>`), nível campanha;
  - o funil sai do código no nome da campanha: `[FAP-01]`, `[FAQ-03]` (inclui `[FAQ-03-4]`), `[FAQ-01]`, `[FAP-05]`, `[FAP-06]`, `[FAP-09]`;
  - campanhas de outras áreas (sem código de funil) ficam fora.
- **Google Ads:**
  - conta `<CONTA_GOOGLE>`, somando o recurso `campaign` (é o que bate com a tela; o recurso `customer` pode trazer gasto antigo que não aparece em nenhuma campanha);
  - o funil sai do código no nome da campanha (`[FAP-01]…`, `[FAP-06]…`);
  - campanhas sem código de funil ficam fora.
- **Investido do caixa (a métrica principal):** gasto em mídia **menos a venda do período**.
  - Hoje só o FAQ-01 (MSS) tem venda.
  - **Custo por lead, por MQL e por qualificado saem do investido do caixa.** O gasto bruto fica como métrica secundária.
- **Funis sem investimento no período:** mostram lead e MQL, sem custo.

---

## 8. SQL de referência

Ver [`regras.sql`](regras.sql). Antes de rodar, troque os marcadores (`<EMAIL_COLABORADOR_1>`, `<REGEX_COLABORADOR_2>`, `<DOMINIO_INTERNO>`) pelos valores reais e as duas datas pelo período. Com os valores reais, ele devolve exatamente os leads, semi e qualificados da reunião de métricas de 10 a 16/10/2026.

---

## 9. Conferência

Para comparar o dashboard com a contagem de referência, monte por funil, no mesmo período, esta tabela. Cada linha sai pelo **primeiro** motivo que a pega, na ordem da seção 3.

| Funil | Brutos | Sem e-mail | Interno/exemplo | Colaborador | Teste | Telefone repetido | Telefone curto | `e2e-check` | Duplicado | **Limpos** | Semi | Qualif. | **MQL** |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|

Os valores de referência de cada semana estão com o gestor. Se o total limpo bate e o MQL não, o problema está na régua (seção 5). Se nem o limpo bate, compare filtro a filtro: a diferença costuma estar no fuso (seção 2), no "teste" na UTM (seção 3) ou no FAP-05 sem e-mail (seção 4).
