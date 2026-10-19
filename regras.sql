-- Regras de limpeza e qualificação de lead: contagem de referência por funil.
-- Antes de rodar, troque os marcadores <...> pelos valores reais (com o gestor) e as duas datas pelo período.
-- Período fechado em horário de Brasília: de 10/10 00h00 até antes de 17/10 00h00 no exemplo.

with cru as (
  select 'FAP-01' f, email, nome, telefone, cargo, faturamento, utm_source, (data_padronizada at time zone 'America/Sao_Paulo') ts from "[Leads] FAP01"
  union all select 'FAQ-03', email, nome, telefone, cargo, faturamento, utm_source, (data_padronizada at time zone 'America/Sao_Paulo') from "[Leads] [Isca Gratuita] PlayBook"
  union all select 'FAQ-01', email, nome, telefone, cargo, faturamento, utm_source, (data_padronizada at time zone 'UTC') from "[Leads] [Inlead] Quiz"           -- já em Brasília: não converter
  union all select 'SITE',   email, nome, telefone, cargo, faturamento, utm_source, (data_padronizada at time zone 'UTC') from "[Leads] Site Institucional"      -- já em Brasília: não converter
  union all select 'FAQ-06', email, nome, telefone, cargo, faturamento, utm_source, (data_padronizada at time zone 'America/Sao_Paulo') from "[Leads] [FAQ06] Pop-Up"
  union all select 'FAP-06', email, nome, telefone, cargo, faturamento, utm_source, (data_padronizada at time zone 'America/Sao_Paulo') from "[Leads] FAP06"
  union all select 'FAP-09', email, nome, telefone, cargo, faturamento, utm_source, (created_at at time zone 'America/Sao_Paulo') from "[Leads] Imersao Estruturado"
  union all select 'FAQ-05', email, nome, telefone, cargo, faturamento, utm_source, (created_at at time zone 'America/Sao_Paulo') from "[Leads] Aula Comercial Estruturado"
  union all select 'FAP-05', email, nome, telefone, null, null, utm_source, (created_at at time zone 'America/Sao_Paulo') from "[Leads] [GHL] Remarketing"
),
periodo as (
  select *, lower(btrim(email)) em, regexp_replace(coalesce(telefone,''),'\D','','g') tel
  from cru
  where ts >= '2026-10-10' and ts < '2026-10-17'
),
limpo as (
  select *, case when f = 'FAP-05' then coalesce(nullif(em,''), right(tel, 8)) else em end chave
  from periodo
  where (f = 'FAP-05' or coalesce(em,'') <> '')                                              -- 1 sem e-mail (exceto FAP-05)
    and coalesce(em,'') not like '%@<DOMINIO_INTERNO>%'                                        -- 2 domínio interno
    and coalesce(em,'') not like '%example.com%'                                               -- 2 exemplo
    and coalesce(em,'') <> '<EMAIL_COLABORADOR_1>'                                             -- 3 colaborador 1
    and coalesce(em,'') !~ '<REGEX_COLABORADOR_2>'                                             -- 3 colaborador 2 (variações)
    and coalesce(em,'') not like '%teste%' and coalesce(nome,'') not ilike '%teste%'           -- 4 teste (NUNCA na UTM)
    and tel !~ '(\d)\1{7,}'                                                                    -- 5 dígito repetido 8x ou mais
    and length(tel) >= 10                                                                      -- 6 telefone curto
    and coalesce(utm_source,'') <> 'e2e-check'                                                 -- 7 lead sintético
),
unico as (
  select distinct on (f, chave) * from limpo order by f, chave, ts                            -- duplicado: fica a 1ª entrada do período
)
select f,
  count(*) as leads,
  count(*) filter (where q = 'semi') as semi,
  count(*) filter (where q = 'qualificado') as qualificado
from (
  select f, case
    when f in ('FAP-01','FAQ-03','SITE','FAQ-06') and cargo in ('socio-empresario','Sócio/Empresário','Sócio ou Fundador','Sócio / Empresário') then
      case when faturamento in ('50k-100k','100k-300k','300k-500k','500k-1m','acima-1m','Entre R$50 mil a R$100 mil','Entre R$50 mil e R$100 mil','Entre R$100 mil a R$300 mil','Entre R$100 mil e R$300 mil','Entre R$300 mil e R$500 mil','Entre R$300 mil a R$1 milhão','Entre R$500 mil e R$1 milhão','Entre R$500 mil a R$1 milhão','Acima de R$1 milhão','Acima de R$ 1 milhão','Mais de R$1 milhão por mês') then 'qualificado'
           when faturamento in ('40k-50k','Entre R$40 mil e R$50 mil','30k-50k','Entre R$30 mil a R$50 mil','Entre R$30 mil e R$50 mil','R$30 mil a R$50 mil') then 'semi' end
    when f = 'FAQ-01' and cargo in ('Dono ou Sócio','Eu sou empresário e tenho um time comercial','Eu sou empresário e eu mesmo vendo') then
      case when faturamento in ('Entre R$100 e R$500 mil','Entre R$500 e R$ 1 milhão','Acima de R$ 1 milhão') then 'qualificado'
           when faturamento = 'Entre R$30 e R$100 mil' then 'semi' end
    when f = 'FAQ-05' and cargo = 'socio' then
      case when faturamento in ('100k-500k','500k-mais') then 'qualificado' when faturamento = '30k-100k' then 'semi' end
    when f = 'FAP-09' and cargo in ('socio','diretor') and faturamento <> 'ate_40' then
      case when faturamento in ('150_500','500_mais') then 'qualificado' else 'semi' end
  end q
  from unico
) x
group by f
order by f;
-- MQL = semi + qualificado. FAP-05 e FAP-06 não têm régua de MQL: contam só lead.
