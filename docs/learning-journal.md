# Learning Journal

## Objetivo

Criar uma gem Rails chamada `rails_doctor` que trate diagnostico de aplicacoes
Rails como uma plataforma extensivel, nao como um script de checklist. O alvo
publico e `bin/rails doctor`, com formato texto, JSON, severidade e exit code
configuravel.

## Decisoes iniciais

1. Ruby local fixado em 3.4.9 porque e a versao estavel mais recente ja instalada
   no workspace. Ruby 4.0 existe, mas seria uma aposta ruim para compatibilidade
   de uma gem Rails no MVP.
2. Dependencia runtime em `railties >= 7.1, < 9.0`. A gem precisa integrar com
   comandos Rails sem impor Active Record, Active Storage ou uma app completa.
3. Minitest e Standard Ruby no desenvolvimento. Menos dependencias e feedback
   rapido valem mais que um stack de teste pesado neste corte.
4. Checks oficiais separados por dominio em `lib/rails_doctor/checks/`. Um unico
   arquivo de checklist viraria o problema que a gem tenta evitar.
5. `Context` e a unica borda de leitura da aplicacao. Isso facilita testes com
   fakes e reduz acoplamento direto a constantes opcionais de Rails.

## Riscos reconhecidos

- O risco central e superficialidade: um check que so olha uma flag pode gerar
  falsa confianca. Por isso cada falha exige `message`, `hint` e `evidence`.
- O comando Rails agora foi validado em uma dummy app, mas ainda falta matriz
  multi-versao antes de chamar isso de release publico forte.
- Algumas configuracoes Rails variam por versao e por arquitetura de deploy. O MVP
  deve preferir achados acionaveis a pretensao de cobertura total.

## Evolucao apos o MVP

O passo seguinte para sair do modo "MVP bem testado por fakes" foi atacar dois
gaps de producao. O primeiro gap era operacional: apps reais precisam declarar
env obrigatorio, suprimir falso positivo conhecido e, em investigacao, limitar a
execucao a um subconjunto de checks. Isso virou `config.x.rails_doctor` com
`required_env`, `only_checks` e `exclude_checks`, alem de `--only` e `--exclude`
na CLI.

O segundo gap era evidencial: testar so por `FakeApplication` nao prova que
`bin/rails doctor` sobe dentro do lifecycle de uma app Rails. A resposta foi um
harness de integracao que monta uma app Rails temporaria e roda o comando real.
Isso nao substitui uma matriz multi-versao, mas remove a maior lacuna entre
"parece integrar" e "integra de fato".

O passo seguinte foi atacar a outra metade do mesmo risco: uma gem que declara
`railties >= 7.1, < 9.0` mas so roda testes em uma versao nao esta pronta para
release forte. Entrou `Appraisal` com uma matriz explicita para Rails 7.1, 7.2,
8.0 e 8.1. A decisao importante aqui foi manter a matriz honesta: appraisals
pinam `railties`, porque e isso que a gem declara suportar e realmente usa.
Nao forcei o meta-gem `rails` sem necessidade.

Na pratica, a matriz resolveu e executou contra `railties` 7.1.6, 7.2.3.1,
8.0.5 e 8.1.3. Os `gemfiles/*.gemfile` e seus lockfiles deixaram de ser lixo de
geracao e passaram a ser evidencia de compatibilidade declarada e repetivel.

## Evolucao para probes de readiness

O gap seguinte deixou de ser compatibilidade e voltou a ser produto: sem uma
superficie explicita para reachability de dependencias, `rails_doctor` ainda
parava em checks de configuracao e `/up` continuava mais honesto do que o nome
"doctor" merecia. A resposta foi um framework pequeno de probes opt-in.

Entraram `RailsDoctor::ProbeFailure`, `RailsDoctor::Probes` e o check
`readiness.configured_probes_failing`. O shape foi mantido intencionalmente
estreito: apps registram probes na configuracao, probes retornam sucesso ou
levantam falha estruturada, e o check oficial transforma isso em resultado
acionavel. Nao criei um segundo registry nem um mini-framework paralelo.

Os primeiros helpers oficiais sao `RailsDoctor::Probes.active_record` e
`RailsDoctor::Probes.cache`. Eles bastam para provar que a extensao funciona em
casos reais sem forcar IO extra em toda app por padrao.

Esse lote tambem expôs um bug importante de bootstrap: no caminho de
`bin/rails doctor`, a gem podia ser carregada antes de `Rails::Railtie` existir.
Sem o `Railtie`, `config.x.rails_doctor.register_probe(...)` virava no-op
silencioso via `OrderedOptions`. A correcao foi mover o bootstrap do comando
para carregar `rails` antes de `rails_doctor`, o que garante a instalacao do
`Railtie` no caminho real da CLI.

## Evolucao para reachability de Redis

Com o framework de probes estavel, o proximo passo nao era adicionar mais
checklist de configuracao. Era provar um probe first-party que fizesse IO real
de dependencia sem deformar a gem. Redis foi o melhor corte: o contrato de
`PING` e pequeno, claro e comum em varias topologias Rails.

A decisao importante aqui foi nao acoplar o probe a uma gem especifica nem
tentar autodetectar todos os lugares onde Redis pode morar. O helper aceita um
cliente direto, um wrapper com `#call("PING")` ou um pool com `#with`. Isso
preserva a direcao de plataforma: `rails_doctor` fornece contrato e tratamento
de falha, enquanto a app escolhe o cliente real.

Tambem evitei um probe oficial de Active Job neste lote. Enfileirar trabalho
para provar reachability muda estado externo e depende demais do adapter. Para
um comando de deploy, isso e uma borda pior do que um PING de Redis.

## Evolucao para reachability de Active Storage

O passo seguinte natural era storage, mas com um cuidado: eu nao queria mudar o
contrato da gem para depender runtime de `activestorage`. O helper precisava
continuar opcional e testavel fora de uma app completa.

A forma mais honesta foi um probe que faz round-trip curto de objeto:
`upload`, `download` e `delete`. Quando `ActiveStorage::Blob.service` existe, o
helper usa a configuracao real da app. Quando nao existe, aceita um service
objeto explicito com o mesmo contrato minimo. Isso preserva o desenho de
plataforma e evita acoplamento a adapters concretos.

Tambem tratei cleanup como parte do probe. Se upload e download funcionam mas o
delete falha, o deploy ainda nao esta numa condicao limpa o suficiente para eu
chamar de ready. Ao mesmo tempo, o cleanup nao pode mascarar a falha primaria de
upload/download. O controle desse detalhe virou parte importante do lote.

## Evolucao para baseline de benchmark

Outro risco residual ja nao era de produto, mas de prova: a documentacao falava
de metodologia de benchmark sem nenhum numero medido. Isso ainda cheirava a MVP.

A correcao foi pragmatica. Extraí o harness da app de integracao para reuso e
criei `bin/benchmark`, que sobe a dummy app uma vez, exclui boot do loop medido
e roda `RailsDoctor::Runner#call` 100 vezes por padrao. O resultado sai em JSON
simples com `median`, `p95`, `max`, versao do Ruby e numero de checks.

Com isso, `benchmarks/baseline.md` deixou de ser promessa e passou a carregar um
baseline real do ambiente local. Ainda nao mede startup de processo nem custo
total de `bin/rails doctor`, mas ja fecha o gap mais util para evolucao do core
de checks.

## Evolucao para reachability de Solid Queue

Com Redis e Active Storage cobertos, o risco residual mais obvio passou a ser
queue. Eu nao quis resolver isso com `perform_later` em job fake, porque isso
contamina estado externo, depende de comportamento do adapter e transforma um
comando de diagnostico em gerador de trafego operacional.

A resposta melhor foi um probe especifico para Solid Queue que usa a conexao
real da fila e verifica as tabelas nucleares do schema: jobs, ready executions,
scheduled executions e processes. Se `SolidQueue::Record.connection_pool` estiver
carregado, o helper usa isso automaticamente. Caso contrario, aceita um pool ou
conexao explicita. Continua sendo uma borda pequena, real e sem efeito colateral.

Esse lote nao tenta provar recorrencia, semaforos ou todas as tabelas opcionais
do schema. O objetivo foi capturar o miolo que mais costuma quebrar boot e
processamento em deploys sem virar um validador acoplado demais ao internals do
gem.

## Evolucao para checks de installer

Depois dos probes, o proximo gap ainda era bem concreto: eu conseguia provar
reachability, mas ainda faltava validar se a app tinha sido instalada direito
para `Solid Queue` e `Active Storage`.

Para `Solid Queue`, o corte pequeno e útil foi checar tres coisas: se o role
configurado em `config.solid_queue.connects_to` realmente existe no
`database.yml`, se os artefatos `db/queue_schema.rb` ou `db/queue_migrate`
continuam no app quando o modo de banco separado está ligado, e manter a
checagem anterior de `config/queue.yml`.

Para `Active Storage`, o check novo verifica se o service escolhido em
`config.active_storage.service` existe de fato em `config/storage.yml`. Isso
elimina um erro de install/configuracao bem comum antes mesmo de qualquer probe
de upload/download rodar.

## Evolucao para compatibilidade de Ruby

Depois de fechar o grosso do produto e do install/config, sobrou um risco mais
simples e mais incômodo: a gem declarava `required_ruby_version >= 3.2`, mas a
evidencia automatizada do CI ainda estava toda em Ruby `3.4.9`.

A decisao aqui foi pragmatica. Em vez de explodir a matriz para todas as
combinacoes de Rails e Ruby, eu separei os objetivos:

1. `quality` roda em Ruby `3.2`, `3.3` e `3.4`, provando que o core da gem,
   lint e build continuam saudaveis nas series suportadas.
2. `compatibility` roda a matriz Rails inteira no Ruby minimo suportado
   (`3.2`), que e exatamente onde a chance de regressao de compatibilidade e
   mais valiosa.

Isso melhora a prova sem transformar o CI em ruido caro demais.

Como `3.3.6` ja estava instalada localmente, complementei a mudanca com uma
prova real nessa serie: `bundle install`, `bundle exec rake test`,
`bundle exec ruby -S standardrb` e `bundle exec rake build` rodaram nela sem
desvio. Nao fiz a mesma alegacao para `3.2`, porque essa versao nao estava
presente na maquina atual.

## Evolucao para prova de redaction

O gap seguinte ja nao era de feature, era de confianca. Os checks de secrets
ja evitavam imprimir valores raw por desenho, mas isso ainda estava mais claro
na implementacao do que na prova automatizada.

Fechei isso em dois niveis. No nivel unitario, os testes agora garantem que os
checks de `secret_key_base` e env obrigatorio reportam so metadados seguros,
como nomes ausentes e comprimento do segredo, sem ecoar valores em `message`,
`hint` ou `evidence`. No nivel de integracao, a dummy app roda o
`bin/rails doctor --format=json` real e prova que nem `stdout` nem `stderr`
carregam o valor do segredo ou de envs presentes.

A consequencia pratica e importante: a barra de seguranca deixou de depender de
leitura manual do codigo e passou a ter regressao automatizada no caminho real
da CLI.

## Evolucao para robustez de extensoes e erros de CLI

O passo seguinte atacou um risco de plataforma. `rails_doctor` ja se vendia como
framework extensivel, mas um check de terceiro que levantasse excecao ainda
podia derrubar o comando inteiro e esconder os demais achados. Isso era
aceitavel em MVP, nao em uma gem que quer virar superficie operacional de
deploy.

A correcao foi manter o desenho pequeno. Em vez de criar um modo "strict", mais
flags ou um subsistema de retries, o proprio `Check#execute` agora encapsula
excecoes inesperadas levantadas pelo bloco do check como falha estruturada do
mesmo `check_id`. O output
preserva severidade e inclui so `error_class`, evitando ecoar mensagens cruas
que podem carregar segredo, token ou URL sensivel.

Tambem endureci o caminho de erro do comando. Casos como `--only` com ID
desconhecido, formato invalido ou severidade invalida agora saem com status `1`
e stderr curto, sem despejar backtrace do framework. O efeito combinado e
simples: uma extensao defeituosa ou erro operacional nao transforma o doctor em
uma ferramenta frágil.

## Evolucao para redaction de excecoes externas

O risco seguinte ficou mais sutil. Eu ja tinha fechado vazamento em checks
oficiais e no crash de checks customizados, mas ainda existiam caminhos onde
mensagens de adapters e clientes externos podiam entrar em `error_message`
quase cruas, especialmente nos probes e em alguns rescues de checks.

A correcao foi centralizar o problema no lugar certo. Em vez de espalhar
`gsub` por probe, check e comando, entrou um redactor pequeno usado por
`Result.failed` e `ProbeFailure`. Isso mantem a politica em um ponto só e faz a
sanitizacao valer tanto para built-ins quanto para extensoes de terceiros que
sigam o contrato da gem.

A heuristica escolhida foi deliberadamente conservadora: userinfo em URLs,
pares `token=...`, `password=...`, `Authorization: Bearer ...` e chaves de
evidence com nomes sensiveis passam a sair como `[REDACTED]`. O objetivo nao e
virar um DLP genérico; e reduzir o risco operacional mais provavel sem deformar
o resto da evidência útil.

## Evolucao para redaction contextual de aplicacao

Depois disso, sobrou um limite claro: a heuristica fixa da gem nunca vai
conhecer todos os formatos de token, account id, DSN ou segredo textual usados
por adapters de terceiros. Se eu parasse ali, a gem continuaria segura no caso
comum, mas ainda pouco maleavel para producao real.

A resposta pequena e alinhada com a arquitetura foi puxar a politica para o
`Context`, exatamente como o ADR ja permitia. `Reporter` agora recebe dois
insumos contextuais: chaves sensiveis vindas de `config.filter_parameters` e
patterns explicitos vindos de `config.x.rails_doctor.redacted_patterns`. Isso
mantem `Result` e `ProbeFailure` com a redaction base e deixa a camada final de
renderizacao aplicar o ajuste especifico da app.

O ganho e pragmatico: um time pode ensinar o `rails_doctor` a esconder um
`acct-live-*`, um `tenant-secret-value` ou uma chave customizada de evidence
sem tocar nos checks built-in e sem forcar uma configuracao global obscura.

## Evolucao para detecao realista de pool e threads

Com a superficie de seguranca mais madura, o proximo buraco pratico apareceu no
check `database.pool.too_small`. O MVP funcionava bem para demos baseadas em
`DB_POOL` e `RAILS_MAX_THREADS`, mas isso ainda deixava de fora formatos bem
comuns de app Rails real: `config/database.yml` com `primary.pool` em setups
multi-database e `config/puma.rb` usando o template padrao do Rails, onde o
default de threads vive num `ENV.fetch("RAILS_MAX_THREADS") { 5 }`.

A mudanca pequena, mas importante, foi colocar essa inteligencia no `Context`,
nao no check. O check continua simples: compara dois inteiros e falha com hint
claro. O `Context` passou a resolver a origem do pool e da contagem de threads,
preferindo o valor vivo do `ActiveRecord::Base.connection_pool.size`, depois as
formas relevantes de `database.yml`, depois os envs legados de pool. Para Puma,
ele usa `RAILS_MAX_THREADS` quando presente e cai para uma leitura restrita do
template comum em `config/puma.rb` quando o env nao existe.

Isso melhora a gem em dois eixos. Primeiro, reduz falso negativo em producao
real sem inflar a DSL nem espalhar regex de config pelo projeto. Segundo, a
evidence ficou auditavel: o resultado agora informa nao so `database_pool` e
`puma_threads`, mas tambem `database_pool_source` e `puma_threads_source`, o
que ajuda a entender rapidamente de onde veio cada numero quando o check falha.

## Evolucao para credentials obrigatorias

Mesmo depois desses passos, ainda havia um buraco objetivo frente ao enunciado
original: a gem ja suportava `required_env`, mas "credentials/env obrigatorios
ausentes" continuava implementado so pela metade. Em producao isso importava,
porque muitos times guardam segredos obrigatorios no `Rails.application.credentials`
e nao em variaveis de ambiente planas.

A correcao pequena foi estender a configuracao, nao inventar um subsistema novo.
`RailsDoctor::Configuration` agora aceita `required_credentials`, e o contrato
publico usa paths com ponto, como `aws.access_key_id`. A leitura dessa
estrutura ficou no `Context`, que passou a navegar hash, `OrderedOptions` e
objetos com metodos de forma conservadora para responder apenas a pergunta que
o check precisa: esse caminho existe e contem algum valor util?

O check novo, `rails.secrets.required_credentials_missing`, ficou simples e
simetrico ao de env: calcula caminhos ausentes, falha com hint claro e nunca
ecoa valores presentes. O teste de integracao faz questao de provar isso no
comando real, sobrescrevendo `Rails.application.credentials` na app temporaria
e garantindo que o output so mostra os caminhos faltantes, nunca o segredo ja
configurado.

## Evolucao para policy file com validacao

Com envs e credentials obrigatorias cobertos, o proximo risco residual vinha do
lado operacional. A gem ja aceitava supressoes e requisitos via
`config.x.rails_doctor`, mas faltava uma superficie mais declarativa para times
que preferem manter politica de deploy em arquivo. Isso tambem conversava
diretamente com um abuso case real: se a ferramenta acusa falso positivo com
frequencia, o time tende a desligar o gate inteiro em vez de registrar a
excecao no lugar certo.

A resposta pequena foi adicionar `config/rails_doctor.yml`, sempre escopado por
ambiente, com suporte a `default` e secoes como `production`. Em vez de criar
uma segunda semantica, o arquivo alimenta a mesma `Configuration` e faz merge
com a config Ruby ja existente. O merge foi desenhado para ser conservador:
`exclude_checks`, `required_env`, `required_credentials` e patterns de redacao
fazem uniao; `only_checks` faz interseccao quando aparece dos dois lados, o que
evita widen acidental do conjunto executado.

O detalhe mais importante foi nao tratar o arquivo como "best effort". Chave
desconhecida em `config/rails_doctor.yml` agora falha o comando com erro curto e
sem backtrace cru. Isso e mais duro, mas operacionalmente melhor: typo em
policy de producao nao pode virar supressao silenciosa.

## Evolucao para rejeitar zero checks selecionados

Depois disso apareceu um bug mais serio do que parecia. A politica de `only`
ficava conceitualmente correta no merge, mas a camada final de execucao ainda
tratava `[]` e "nenhum filtro informado" como a mesma coisa. Na pratica, uma
interseccao vazia entre `config.x.rails_doctor.only_checks` e `--only` podia
voltar a abrir a execucao para todos os checks, o que e ruim dos dois lados:
nem respeita o filtro pedido, nem falha de forma auditavel.

A correcao foi separar semanticamente "sem filtro" de "filtro explicitamente
vazio". `Configuration#filters` agora devolve `nil` quando realmente nao existe
`only`, e devolve `[]` quando a interseccao calculada zera o conjunto. A
`Registry` passou a honrar essa diferenca e falhar se nenhum check sobrar depois
dos filtros, com mensagem curta e deterministica.

Esse guardrail e importante porque elimina um falso verde operacional. Em vez de
um pipeline passar com escopo acidentalmente widen ou ambíguo, o comando agora
forca o operador a corrigir a policy.

## Evolucao para severidade valida em checks de terceiros

O passo seguinte atacou um risco de extensibilidade mais sutil. O framework ja
aceitava checks de terceiros, mas ainda deixava passar qualquer valor em
`check.severity`. Isso parecia inofensivo enquanto o output fosse texto simples,
mas quebrava um contrato importante: severidade precisa ser rankeavel para
`--fail-on` e previsivel para automacao.

A correcao pequena foi mover a validacao para o proprio `Check`, no ponto de
escrita, em vez de esperar o erro aparecer mais tarde no `Runner` ou no
`Result`. Agora o conjunto suportado fica explicito: `low`, `warning`,
`medium`, `high` e `critical`. Se uma extensao registrar `:urgent`, o comando
falha cedo com erro curto e sem backtrace cru.

Isso melhora a gem como plataforma. O problema deixa de aparecer como falha
operacional difusa em runtime e passa a ser erro de contrato logo no momento em
que a extensao tenta se plugar ao framework.

## Evolucao para IDs validos em checks

O risco seguinte era parecido, mas do lado do identificador do check. O
framework dependia de `check_id` para filtro, exclusao, policy file, output JSON
e leitura humana, mas a `Registry` ainda aceitava qualquer string. Isso deixava
espaco para extensoes registrarem ID vazio, com espaço, uppercase ou hifen e so
descobrir o estrago mais tarde, em pontos diferentes do sistema.

A correcao foi endurecer o contrato no proprio `Registry#register`. O formato
agora e simples e coerente com a gem inteira: segmentos em minusculo separados
por ponto, com underscore opcional dentro de cada segmento, como
`database.pool.too_small` ou `solid_queue.database_role_missing`.

O valor pratico aqui e previsibilidade operacional. Um ID malformado nao chega
mais a contaminar `--only`, `--exclude`, `config/rails_doctor.yml` ou o output
consumido por CI. Ele falha cedo, com mensagem curta, no momento em que a
extensao tenta entrar na registry.

## Evolucao para flags de session cookie em producao

Mesmo com `force_ssl`, `same_site` e cache de producao cobertos, ainda faltava
um pedaço literal do enunciado inicial: "cookies/session config fraca". O ponto
mais útil do MVP nao era inventar um scanner amplo de middleware, mas atacar o
caso mais comum e mais perigoso em apps Rails padrao: session cookie sem
`secure` efetivo ou com `httponly: false`.

A implementacao foi mantida no arquivo canonical de config de producao,
`production_config.rb`, para nao espalhar semantica de cookie por outros
modulos. O check novo, `rails.session.cookie_flags_weak`, roda apenas em
producao, lê `config.session_options` e falha com evidence estruturada quando:

- `secure` nao esta explicitamente protegido e `force_ssl` tambem nao ajuda;
- `httponly` foi explicitamente desligado.

Essa leitura precisou ser mais cuidadosa do que parecia. Na app Rails real do
teste de integracao, `session_options[:secure]` e `[:httponly]` vinham `nil`
por default, e o comportamento de `same_site` ainda podia depender do
`load_defaults` da app. Ou seja, assumir que "nil significa inseguro em todos
os casos" teria gerado falso positivo, e assumir que "nil sempre herda algo
seguro" teria mascarado config fraca.

O equilibrio pragmatico foi este: `force_ssl` satisfaz o requisito de transporte
seguro quando `secure` nao esta `true`, mas `httponly: false` continua sendo
falha explicita. A evidence exposta pelo check lista `issues`, `secure`,
`httponly` e `force_ssl`, o que deixa claro por que o resultado falhou sem
obrigar leitura de codigo.

Tambem endureci a borda do built-in para nao depender de shape perfeito.
`session_options` passa por `Hash.try_convert` antes de leitura, o que evita um
crash do check caso alguma app ou teste injete `nil` ou outro objeto fora do
contrato esperado.

Na revisao seguinte apareceu um falso positivo mais serio: `config.session_options`
continua existindo ate em app `api_only`, entao o built-in poderia marcar APIs
sem sessao de navegador como "fracas" so por inspecionar config residual. A
correcao pequena foi pular esse check quando `config.api_only` esta ativo. Isso
reduz ruido operacional sem esconder o caso principal, que continua coberto
pelos testes unitarios e pelo comando real em uma app Rails tradicional.

## Evolucao para supressoes auditaveis

O proximo gap que realmente separava a gem de um uso mais confiavel em producao
nao era "mais um check". Era politica operacional. O repo ja tinha
`exclude_checks`, mas isso era cego: escondia um falso positivo sem registrar
por que aquele ID foi suprimido. Em um framework de diagnostico, isso e risco
real de manutencao, porque um deploy estranho de hoje vira silencio opaco
amanha.

O caminho escolhido foi deliberadamente pequeno. Em vez de criar uma DSL de
policy ampla, entrou uma unidade explicita e estreita: `Suppression`, com
`check_id` e `because`. Isso foi suficiente para elevar a semantica de policy
sem inventar um motor de regras paralelo ao de checks.

`Configuration` agora aceita suppressions tanto por Ruby config quanto por
`config/rails_doctor.yml`, e tambem expoe um helper direto:

- `config.x.rails_doctor.suppress("rails.production.force_ssl_disabled", because: "...")`

No merge, a escolha importante foi sobrescrever por `check_id`, nao acumular
duplicatas. Isso deixa `default` e `production` previsiveis: a policy mais
especifica pode refinar a justificativa de uma supressao herdada sem deixar
duas razoes concorrentes para o mesmo check.

Tambem mantive `exclude_checks`, mas rebaixado conceitualmente para escape
hatch. Isso preserva compatibilidade e evita churn desnecessario para quem ja
usa a gem, sem tratar uma lista opaca de IDs como o contrato ideal de
producao.

O spec-driven aqui importou porque o proprio repo estava em drift: o plano e o
case study ainda falavam em suppression policy como trabalho futuro, embora a
necessidade operacional ja estivesse madura. Corrigir esse drift junto com o
codigo foi parte do incremento, nao documentacao secundaria.

## Evolucao para supressoes visiveis no output

Depois do passo anterior, apareceu um limite importante: a supressao ja era
estruturada na config, mas continuava invisivel no resultado do comando. Isso
era melhor do que `exclude_checks` puro do ponto de vista de manutencao do repo,
mas ainda fraco para operacao real. Um pipeline ou dashboard continuaria vendo
apenas "nao falhou", sem distinguir "passou" de "foi suprimido por policy".

A correcao certa nao era inventar um relatorio separado. O contrato natural do
framework ja era `Result`, entao a mudanca pequena e coerente foi adicionar um
novo status: `suppressed`. Isso manteve o reporter como superficie canonical e
evitou um canal paralelo de metadados.

Essa decisao puxou uma mudanca mais sutil no `Registry`. Antes, suppressions
viravam exclusoes na pratica. Agora a selecao e feita em duas fases:

- `exclude_checks` continua removendo checks de forma cega;
- `suppressions` retiram checks da execucao, mas devolvem `Result.suppressed`
  com a severidade original e o `because` registrado.

O ganho operacional mais importante veio como efeito colateral bom: uma execucao
em que todos os checks selecionados estao suprimidos deixa de cair no erro de
"zero checks". Isso seria um falso alarme, porque houve selecao real e policy
real; so nao houve check executado. O guardrail de zero checks continua valendo
para interseccoes vazias e exclusoes que de fato deixam a execucao sem escopo.

No texto e no JSON, a diferenca agora fica legivel para humanos e automacao.
Isso aproxima a gem de um deploy gate mais honesto: ela nao apenas falha ou
passa, ela tambem mostra quando alguma parte do bar foi conscientemente
derrogada.

## Evolucao para owner e expiração obrigatorios

O passo seguinte foi transformar suppression de "auditavel" em "governavel".
Mesmo com `suppressed` visivel no output, ainda existia um buraco classico de
plataforma interna: excecoes sem dono e sem prazo viram entulho permanente.

Aqui a escolha deliberada foi endurecer o contrato em vez de criar mais um
check brando. `Suppression` agora exige quatro campos:

- `check_id`
- `because`
- `owner`
- `expires_on`

Isso muda o ponto de falha para mais cedo e de forma mais util. Se a policy for
malformada, o comando nao tenta adivinhar. Se a data vier fora de
`YYYY-MM-DD`, falha no parse com erro curto. Isso e mais duro, mas melhor do
que aceitar politica ambigua em um gate de deploy.

O detalhe mais importante foi separar suppressions ativas de suppressions
expiradas no `Registry`. Uma suppressao vencida nao pode mais esconder o check
original. Ela deixa de participar da supressao, o check real volta a rodar, e o
framework ainda emite um segundo sinal formal via built-in
`rails_doctor.suppressions.expired`.

Isso evita dois erros comuns ao mesmo tempo:

- stale suppression que continua escondendo problema real;
- comando quebrando como erro de configuracao generico quando o caso certo e um
  resultado estruturado e acionavel.

O produto ficou mais honesto. Agora a excecao operacional precisa ter motivo,
dono e horizonte temporal. E quando esse horizonte vence, a gem nao silencia
nem explode: ela mostra o problema de policy e reexibe o problema original.

## Evolucao para reminder de expiracao proxima

O passo seguinte natural foi evitar que a governanca de suppressions fosse so
reativa. Detectar expiracao vencida e importante, mas isso ainda deixa o time
descobrir o problema tarde, quando a excecao ja virou passivo. Para um comando
pensado como gate operacional, o comportamento melhor era avisar antes.

A escolha foi manter isso dentro do mesmo modelo do produto: um built-in check
normal, nao um scheduler paralelo e nao um comando separado. Entrou
`rails_doctor.suppressions.expiring_soon` com severidade `warning`, olhando a
mesma policy carregada pelo framework e falhando quando uma suppressao ativa
tem 14 dias ou menos restantes.

Isso preserva algumas propriedades boas do design:

- o lembrete aparece no mesmo output textual e JSON que o resto da gem;
- `--fail-on warning` continua sendo o mecanismo de gate, sem excecao nova;
- gems terceiras e apps nao precisam aprender uma segunda API de governanca;
- a implementacao continua pequena, porque `policy.rb` segue sendo apenas mais
  um grupo de checks oficiais.

No nivel de modelo, `Suppression` ganhou os metodos que faltavam para esse
comportamento ficar explicito e testavel: `days_until_expiry`,
`expires_on_date` e `expiring_within?`. Isso e melhor do que espalhar calculo
de data em `Registry`, `Reporter` ou checks avulsos.

Tambem houve cuidado com a evidencia. O reminder nao podia ser um warning
generico. Ele agora carrega:

- `window_days` para deixar claro o criterio aplicado;
- `days_until_expiry` por suppressao afetada;
- `owner`, `check_id`, `because` e `expires_on` para revisao operacional.

Com isso, a diferenca entre os dois checks de policy ficou nitida:

- `rails_doctor.suppressions.expiring_soon` antecipa revisao;
- `rails_doctor.suppressions.expired` acusa policy vencida;
- o check original volta a rodar assim que a suppressao expira.

O que ficou deliberadamente de fora foi exportacao ou notificacao externa.
Slack, webhook, dashboard ou relatorio periodico podem existir depois, mas
seriam outra superficie de produto. Para este passo, o contrato certo era fazer
o proprio `bin/rails doctor` continuar sendo a verdade unica e auditavel.

## Evolucao para inventario exportavel de suppressions

Depois dos checks `expired` e `expiring_soon`, ficou um gap operacional claro:
o produto ja conseguia bloquear deploy e avisar sobre policy ruim, mas ainda
nao conseguia exportar o inventario completo das excecoes de forma limpa. Para
CI e auditoria isso forcava parse oportunista do output normal dos checks,
quando o contrato certo era outro.

A decisao aqui foi manter o escopo pequeno e explicito:

- o comando continua sendo `bin/rails doctor`;
- entrou um modo dedicado `--report=suppressions`;
- esse modo nao roda checks normais;
- esse modo rejeita `--fail-on`, `--only` e `--exclude`.

Essa ultima parte foi importante. Misturar filtros de execucao de checks com um
inventario de policy abriria uma superficie ambigua e dificil de operar. O
inventario existe para auditoria de excecoes, nao para gate por severidade.

No modelo, o passo adicionou `SuppressionReport`, que transforma a policy ja
carregada pelo framework em um inventario ordenado com:

- `check_id`
- `because`
- `owner`
- `expires_on`
- `days_until_expiry`
- `status` em `active`, `expiring_soon` ou `expired`

O renderer ficou separado em `SuppressionReporter`. Isso evitou deformar o
`Reporter` normal, cujo contrato continua sendo renderizar resultados de checks.
Foi uma separacao pequena, mas importante para manter ownership claro:

- `Reporter` fala de resultados de diagnostico;
- `SuppressionReporter` fala de inventario de policy;
- `Runner` so roteia entre as duas superficies.

Tambem houve preocupacao com honestidade de seguranca e ergonomia:

- o export usa a mesma pipeline de redacao contextual;
- o contrato funciona em `text` e `json`;
- o caminho real do `bin/rails doctor` ganhou teste de integracao para esse
  modo;
- o README, a spec de readiness e o roadmap foram atualizados no mesmo
  incremento para evitar drift.

Isso fecha um ponto importante da tese do produto. Agora RailsDoctor nao apenas
detecta excecoes operacionais ruins; ele tambem consegue listar, de forma
consumivel, todas as excecoes operacionais ativas e seu estado de validade.

## Evolucao para formato GitHub Actions e workflows oficiais

Com o inventario de suppressions em JSON, o passo seguinte mais valioso para
tirar a gem do territorio de MVP era fechar a ponte com CI real. O gap nao era
mais "conseguir exportar dados"; isso ja existia. O gap era obrigar cada time
consumidor a escrever glue proprio para transformar output em anotacoes
operacionais legiveis dentro do fluxo de deploy.

A direcao escolhida foi deliberadamente pequena:

- nao entrou integracao com Slack, webhook, email ou storage externo;
- nao entrou scheduler proprio;
- nao entrou uma segunda CLI separada.

Em vez disso, a propria superficie existente ganhou `--format=github-actions`.
Isso preserva a tese do produto:

- RailsDoctor continua sendo um framework de checks e reporting;
- a integracao downstream continua sendo derivada de output estavel;
- o time consumidor nao precisa parsear `text` nem escrever `jq` para tudo.

O incremento ficou dividido em tres pecas:

1. `GitHubActions`, um helper pequeno para escapar corretamente `title` e
   `message` no protocolo de annotations.
2. `Reporter` emitindo `error`, `warning` e `notice` para checks falhos ou
   `suppressed`.
3. `SuppressionReporter` emitindo annotations so para `expired` e
   `expiring_soon`, mantendo `json` e `text` como superficies do inventario
   completo.

Isso parece simples, mas havia um risco importante de integracao quebrada:
mensagens com `%`, quebra de linha, `:` ou `,` podem gerar annotations
invalidas. Por isso o incremento foi dirigido por teste de escaping, nao so por
snapshot superficial de string.

Tambem aproveitei para transformar a parte de "workflow downstream" em artefato
real do repo:

- guia em `docs/product/ci-integration.md`;
- exemplo de deploy gate em GitHub Actions;
- exemplo de scheduled suppression audit;
- teste leve confirmando que os exemplos continuam apontando para a superficie
  correta da gem.

O roadmap mudou de lugar por causa disso. "GitHub Actions e deploy gates" nao e
mais trabalho futuro; agora o que resta nesse eixo sao integracoes fora do
GitHub, como chat/webhook ou consumo downstream mais especifico.

## Evolucao para hooks opcionais antes de server e db:migrate

Com a policy mais madura, o proximo gap evidente para a tese do produto era a
distancia entre o comando explicito e o fluxo real do Rails. O framework ja
estava forte em `bin/rails doctor`, mas ainda faltava aproximar a experiencia
do modelo do Django, onde checks podem aparecer antes de comandos operacionais
sensíveis.

A armadilha aqui era cair em duas implementacoes diferentes: uma para o comando
explicito e outra para hooks automaticos. Isso enfraqueceria o produto porque
duplicaria runner, reporter, thresholds e politica de redacao. A decisao foi
na direcao oposta: hooks opcionais, mas sempre usando o mesmo `Runner`, o mesmo
`Reporter` e a mesma `Configuration`.

Entrou um modelo pequeno e explicito, `CommandHook`, com suporte inicial so
para `server` e `db:migrate`. Cada hook aceita:

- `command`
- `fail_on`
- `only_checks`
- `exclude_checks`

No Ruby DSL isso virou `before_command`, e no `config/rails_doctor.yml` entrou
`command_hooks`. O contrato continua enxuto: nada de linguagem generica de
policy, so nomes de comandos suportados e filtros reaproveitando os mesmos
check IDs estaveis do produto.

O ponto mais importante de design apareceu no `db:migrate`. Rodar o framework
completamente antes de migrar parece obvio, mas quebra no caso mais banal:
`database.migrations.pending` e verdadeiro exatamente quando uma migracao
legitima ainda precisa rodar. Se esse check bloqueasse o hook, o produto seria
auto-contraditorio.

Por isso o hook de `db:migrate` ganhou uma exclusao padrao de
`database.migrations.pending`. Essa foi a parte mais spec-driven do incremento:
nao bastava "rodar checks antes de migrate"; precisava continuar sendo verdade
que o fluxo normal de migrar uma app com migracoes pendentes e valido.

Outra decisao boa foi separar os pontos de integracao por superficie nativa do
Rails:

- `server` usa o hook oficial `server do` do Railtie;
- `db:migrate` usa um prerequisite de Rake em `rake_tasks`.

Isso evitou monkey patches maiores no `RakeCommand` e manteve a responsabilidade
localizada no boundary certo de cada comando.

Os testes precisaram provar mais do que "o objeto existe". O recorte correto
foi:

- configuracao normaliza e valida `command_hooks`;
- o runner de hook bloqueia quando o threshold e atingido;
- `db:migrate` nao se auto-bloqueia por `database.migrations.pending`;
- o comando real `bin/rails server` pode ser barrado antes de subir;
- o comando real `bin/rails db:migrate` pode ser barrado ou liberado conforme
  `only_checks`, `exclude_checks` e `fail_on`.

Isso puxou a gem para mais perto de "plataforma operacional" e menos de
"checklist manual". O diagnostico continua explicitamente invocavel, mas agora
tambem pode proteger fluxos Rails importantes sem inventar um segundo produto.

## Evolucao para readiness route via route set real

Outro ponto que ainda cheirava a MVP era `health.readiness_route_missing`.
Embora a ideia do check estivesse certa, a implementacao ainda era rasa demais:
lia `config/routes.rb` como texto e procurava `"/up"`, `rails/health` e alguma
ocorrencia de `ready`. Isso funciona para casos simples, mas cai rapido quando
uma app monta engines ou encapsula readiness fora do arquivo principal.

O problema mais serio nao era "imprecisao teorica". Era um falso positivo
operacional concreto: uma app podia expor readiness de forma valida por um
route set montado e ainda assim o doctor mandar o time criar suppression para
um problema que nao existe. Isso enfraquece a confianca no produto.

A mudanca correta foi empurrar a verificacao para o dado real que o Rails ja
tem depois do boot: o route set. `Context` ganhou `route_definitions`, que
percorre `application.routes.routes`, normaliza paths e segue route sets
montados via `route.app.app` quando o endpoint e um mount.

Essa escolha preserva algumas propriedades importantes:

- continua sendo leitura apenas, sem mutar a app;
- usa uma fonte de verdade mais forte que texto cru;
- reduz necessidade de suppression em apps com engines;
- ainda tem fallback para `config/routes.rb` quando route objects nao estao
  disponiveis.

O ponto mais util foi manter a heuristica pequena mesmo depois da melhora.
Nao tentei inferir semantica completa de todos os endpoints da app. O check
continua respondendo a uma pergunta simples:

- existe um boot health route como `/up` ou `rails/health`?
- existe alguma readiness route real como `/ready`, `/readiness` ou `/readyz`,
  inclusive quando ela vem de um route set montado?

Se a resposta for "sim" para a primeira e "nao" para a segunda, falha. Se a
readiness existir num engine montado, passa. Isso foi suficiente para tirar o
check da categoria "grep sofisticado" e colocar numa base mais honesta sem
criar um mini framework de analise de rotas.

## Evolucao para secret_key_base placeholder e repeticao explicita

Outro lugar onde ainda havia cheiro de MVP era `rails.secrets.secret_key_base_missing`.
O contrato do produto dizia "ausente/inseguro", mas a implementacao ainda
confiava demais em comprimento minimo e numa lista curta de palavras obvias.

Na pratica isso deixava passar um caso feio: `\"x\" * 64`. Esse valor e longo o
bastante para passar no critério de tamanho, mas continua sendo um placeholder
ridiculamente fraco. E se o proprio dummy app da suite usa isso como default,
era sinal claro de que a heuristica ainda nao estava segurando uma classe
importante de falso verde.

A correção foi manter regras pequenas e explicaveis, sem cair em score opaco de
entropia:

- `missing`
- `too_short`
- `obvious_placeholder`
- `repeated_character`
- `repeated_pattern`
- `low_character_variety`

O ponto de design mais importante foi nao tentar "medir segredo forte" de forma
generica. Isso seria facil de exagerar e dificil de explicar. Em vez disso, o
check agora veta formas de segredo que sao claramente inaceitaveis em producao:

- placeholders conhecidos como `change-me`, `dummy`, `test`, `secret`;
- um unico caractere repetido;
- um padrao exato repetido varias vezes;
- variedade de caracteres baixa demais para um valor longo.

Isso melhora bastante o sinal do produto sem tornar o check arbitrario. Quem
olhar a evidencia entende por que falhou, e quem precisa suprimir um caso
intencional continua tendo um motivo claro para revisar.

O ganho mais honesto foi alinhar o comportamento ao enunciado original da gem:
`secret_key_base` inseguro agora e tratado como inseguro de verdade, nao apenas
como "curto demais".

## Evolucao para hook opcional antes de db:prepare

O proximo gap mais nitido depois disso nao estava em mais um check isolado.
Estava no fluxo operacional. A spec e o roadmap ainda deixavam claro que os
hooks automaticos paravam em `server` e `db:migrate`, mas `db:prepare` e um
comando muito comum em bootstrap local, CI e deploy.

O ponto importante foi manter a disciplina spec-driven e nao sair ampliando a
superficie de forma vaga. Antes de mexer no core, a expectativa foi travada em
tres niveis:

- configuracao aceita e normaliza `before_command("db:prepare", ...)`;
- o `CommandHookRunner` aplica as exclusoes padrao certas para esse comando;
- o comando real `bin/rails db:prepare` pode ser barrado ou liberado conforme
  `fail_on`, `only` e o estado da app.

Isso tambem forçou uma decisao de design util: nao transformar a feature num
hook generico para qualquer task de Rake. Seria facil abrir uma DSL mais ampla
cedo demais e acabar sustentando um produto mais dificil de explicar e validar.
`db:prepare` era um caso forte o bastante para entrar como comando suportado,
mas ainda dentro da whitelist explicita do framework.

O segundo detalhe importante foi reaproveitar a mesma excecao operacional de
`db:migrate`. Se `database.migrations.pending` bloqueasse `db:prepare`, o hook
se tornaria auto-contraditorio exatamente no fluxo que deveria proteger. Por
isso `db:prepare` entrou no mesmo grupo de comandos que excluem esse check por
padrao.

No codigo, o ajuste bom foi pequeno:

- `CommandHook::SUPPORTED_COMMANDS` ganhou `db:prepare`;
- `CommandHookRunner::DEFAULT_EXCLUDE_CHECKS` passou a cobrir os dois comandos
  de setup de banco;
- o `Railtie` deixou de ter um unico prerequisite hardcoded e passou a iterar
  um mapa pequeno de hooks de Rake para `db:migrate` e `db:prepare`.

Esse ultimo ponto importa porque reduz duplicacao sem cair numa abstracao
genetica. Ainda e facil ler onde cada hook Rails entra, mas o arquivo nao
precisa mais crescer por copia e cola sempre que um segundo comando do mesmo
tipo entra.

O teste de integracao tambem ficou mais honesto. Em vez de fingir Active Record
ou depender de adaptadores reais, o harness continuou registrando um task
`db:prepare` minimo dentro da app temporaria. Isso provou o boundary que
interessa aqui: o hook barra ou libera a execucao do comando Rails real antes
da acao do task, sem inventar dependencias de banco que nao fazem parte da gem.

## Evolucao para probes oficiais de Sidekiq e GoodJob

Com os hooks mais maduros, o proximo gap util voltou para readiness. O core ja
tinha probes bons para Redis, Active Storage e Solid Queue, mas ainda faltava
uma ponte honesta para adapters terceiros muito comuns. O roadmap ja admitia
isso como risco residual: cobertura mais profunda para adapters populares sem
transformar a gem num catalogo confuso de checks acoplados a cada ecossistema.

A decisao mais importante aqui foi de escopo. Em vez de adicionar checks
built-in opinativos para Sidekiq e GoodJob, a evolucao foi pelo mesmo modelo
que ja estava funcionando: probes opt-in. Isso preserva duas propriedades boas:

- o core continua focado em readiness e nao em regras arbitrarias de cada gem;
- apps e gems continuam podendo compor o framework sem depender de um
  crescimento desordenado de checks oficiais.

O recorte spec-driven ficou assim:

- `RailsDoctor::Probes.sidekiq` deve usar a conexao real do Sidekiq quando ela
  estiver disponivel via `Sidekiq.redis_pool` ou `Sidekiq.redis`;
- `RailsDoctor::Probes.good_job` deve usar o pool real do GoodJob quando ele
  estiver disponivel via `GoodJob::BaseRecord` ou `GoodJob::Job`;
- ambos precisam continuar opt-in, com erro claro quando a dependencia nao
  estiver configurada;
- ambos precisam funcionar no comando real, nao so por doubles unitarios.

O ajuste de arquitetura ficou pequeno e coerente:

- `Context` ganhou apenas descoberta do target padrao para Sidekiq e GoodJob;
- `Probes` ganhou dois helpers novos e um pequeno reaproveitamento interno da
  logica de cliente Redis;
- a suite ganhou um arquivo novo de integracao para esses helpers, em vez de
  continuar engordando `integration_command_test.rb`.

Esse ultimo ponto importa. O arquivo principal de integracao ja estava
encostando no limite onde cada incremento adiciona mais ruido do que sinal.
Criar um teste de integracao focado em probe helpers foi a maneira mais limpa
de ampliar a prova sem piorar a navegabilidade do repo.

Tambem houve um detalhe bom de robustez no probe de Sidekiq. Dentro de uma app
Rails real, tratar qualquer objeto que responda a `call` como cliente Redis
direto era fraco demais, porque um modulo pode responder a isso por outros
motivos. O helper precisou priorizar a interface `Sidekiq.redis` antes do
fallback mais generico. Esse e exatamente o tipo de falso verde/falso negativo
que so aparece quando a spec insiste em exercitar o boundary real da
integracao, nao apenas o caminho unitario mais obvio.

## Evolucao para hook opcional antes de assets:precompile

Depois de `db:prepare`, o proximo fluxo operacional com mais cheiro de deploy
real ainda ficava de fora: `assets:precompile`. Isso estava alinhado com o
roadmap e com a tese do produto. Se o objetivo e deixar o doctor mais proximo
de um guardrail operacional, parar antes de compilar assets em producao e um
caso forte, nao um capricho.

O risco obvio era repetir o erro classico de `db:migrate` em outra superficie:
o proprio hook se auto-bloquear pelo check que ele deveria tornar valido. Aqui
o paralelo era `assets.production_build_missing`. Antes do build, o manifesto
nao existe mesmo. Se esse check barrasse `assets:precompile`, o produto virava
contraditorio de novo.

Por isso a spec foi travada em tres partes:

- configuracao aceita `before_command("assets:precompile", ...)`;
- o `CommandHookRunner` exclui `assets.production_build_missing` por padrao;
- o comando real pode ser barrado por outro problema forte, mas nao por falta
  do manifesto que ele vai gerar.

O desenho final ficou coerente com a arquitetura que ja existia:

- `CommandHook::SUPPORTED_COMMANDS` ganhou `assets:precompile`;
- `CommandHookRunner::DEFAULT_EXCLUDE_CHECKS` ganhou a exclusao padrao do
  manifesto;
- o `Railtie` so expandiu o pequeno mapa de hooks Rake, sem criar branch
  especial nem segundo caminho de execucao.

Esse ultimo detalhe foi importante para nao diluir o design. A feature cresceu
na mesma direcao dos hooks anteriores: whitelist explicita, reuse do runner, e
conhecimento operacional so onde ele realmente pertence.

Os testes tambem mostraram um ponto util de contrato. Para provar a exclusao
padrao no comando real, nao bastava usar so `assets.production_build_missing` em
`only_checks`, porque isso colapsaria a selecao para zero checks depois da
exclusao. A spec precisou manter um segundo check estavel e passante na mesma
selecao. Isso e bom: protege a regra de "zero checks e erro" enquanto ainda
prova que o hook nao se auto-bloqueia.

## Evolucao para exemplos oficiais de policy validados por teste

Depois dos fluxos de deploy principais estarem cobertos, um tipo diferente de
risco continuava em aberto: adocao errada. A gem ja tinha um modelo forte de
policy em `config/rails_doctor.yml`, mas ainda faltavam exemplos oficiais para
topologias reais. Isso mantinha um cheiro de MVP porque a capacidade existia,
mas o caminho de uso em producao ainda dependia demais de inferencia do leitor.

O ponto importante aqui foi nao cair num anti-padrao comum: documentacao bonita
que nao conversa com o contrato executavel. Por isso a decisao nao foi so
escrever uma pagina com snippets. O incremento ficou em duas partes acopladas:

- exemplos versionados em YAML para topologias reais;
- teste automatizado que carrega esses exemplos pelo mesmo caminho real que a
  gem usa no runtime.

As topologias escolhidas foram deliberadamente pragmaticas:

- TLS terminado no ingress antes do Rails;
- pipeline de assets externo com manifesto publicado fora do host Rails;
- servico API-only atras de gateway, sem dependencia de browser cookies ou
  assets compilados localmente.

Cada exemplo usa `suppressions` com `because`, `owner` e `expires_on`, em vez
de normalizar o uso de `exclude_checks`. Isso importa porque o valor real da
gem nao esta em "calar warnings", e sim em deixar excecoes intencionais
auditaveis.

O teste novo ficou pequeno, mas o contrato dele e forte. Para cada arquivo em
`docs/examples/policies`, o suite:

- copia o YAML para `config/rails_doctor.yml` de uma app temporaria;
- executa o runner real em ambiente `production`;
- confirma que as suppressions esperadas aparecem como `suppressed`.

Esse detalhe eleva bastante a confianca. Agora o repo nao tem so exemplos
plausiveis; tem exemplos que provam continuamente que ainda batem com o parser,
com a validacao de IDs, com a governanca de suppressions e com o caminho real
de carga da policy.

## Proxima leitura recomendada

1. `README.md` para contrato de produto e API publica.
2. `lib/rails_doctor/check.rb` e `lib/rails_doctor/registry.rb` para a DSL.
3. `lib/rails_doctor/context.rb` para o limite entre framework e app Rails.
4. `lib/rails_doctor/checks/` para os checks oficiais.
5. `test/rails_doctor/integration_command_test.rb` para o comando real.
6. `test/rails_doctor/` para os demais exemplos executaveis.
