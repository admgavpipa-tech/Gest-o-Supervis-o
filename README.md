# GAV - Gestão de rotinas de limpeza

Aplicativo estático em HTML e JavaScript de gestão geral da GAV: rotinas de limpeza das ASGs e contagem de estoque do salão pelos garçons, com identidade visual do template GAV. Publique `index.html` e `reliability.js` juntos.

## Perfis

- **Gestor**: menu com Controle, Setores, Registros e Usuários. Setores e Registros têm duas visões, **Limpeza** e **Garçom**, trocadas no topo da tela; o app lembra a última visão escolhida. O Controle mostra os dois lados com o mesmo peso: Salão (contagens do dia e maiores quedas) e Limpeza (andamento, justificativas e listas).
  - Setores → Limpeza: Listas e Cômodos. Setores → Garçom: status da contagem de hoje e a lista de itens contados, que a gestão edita (incluir, renomear, remover e reordenar).
  - Registros → Limpeza: fotos, justificativas e pendências. Registros → Garçom: contagens do salão.
- **ASG**: rotina de limpeza (sem mudanças).
- **Garçom**: contagem de estoque do turno.

Para incluir outro perfil no futuro, acrescente-o na regra `profiles_role_check` de `supabase/equipe.sql` e crie as telas correspondentes.

## Computador e celular

No celular, o app usa a barra de navegação embaixo. No computador (telas a partir de 1040 px), vira um painel completo: menu lateral por área (Limpeza, Salão, Pessoas) com a marca e o usuário, barra do topo com o caminho da tela, a data e os avisos, conteúdo largo com cartões em grade, Controle com Salão e Limpeza lado a lado, contagem com o calendário ao lado da tabela, contagem do garçom em duas colunas e entrada com a tela dividida entre a marca e o formulário. O app fica sempre no tema claro, com as fontes Fraunces (títulos) e Figtree (texto).

## Primeiro acesso

Na primeira entrada, ASG e garçom veem um passo a passo de 5 telas que ensina o uso do app (a ASG pode liberar a câmera ali mesmo). Ele aparece uma vez por aparelho e pode ser revisto em Perfil → "Ver o passo a passo de novo".

## Cadastro pelo site

Na tela de entrada, **Quero me cadastrar** abre o formulário: nome, e-mail, senha e função (ASG ou garçom). O cadastro fica **aguardando aprovação**, sem acesso a nada. Em **Usuários**, a gestão aprova como ASG ou como garçom, ou recusa. O Controle avisa quando há cadastros pendentes. Quem tenta entrar antes da aprovação vê a mensagem de que o cadastro aguarda a gestão.

## Contagem de estoque (garçons)

- São **duas contagens por dia**: uma no turno do dia e outra no da noite.
- O garçom entra direto na tela **Contagem**. O turno já vem escolhido pelo horário e pelo que falta enviar. Ele digita a quantidade de cada item (teclado numérico; o "próximo" do teclado pula para o item seguinte), vê o progresso e o botão "Faltam N itens" leva ao primeiro em branco. O que foi digitado fica guardado no aparelho até o envio.
- A tela cumprimenta pelo nome e pelo horário e diz quanto tempo leva. Durante a contagem, o app comemora cada grupo concluído e avisa quando faltam poucos itens (“Quase lá! Faltam só 3”).
- Os itens aparecem **agrupados** (Bebidas, Café e açúcar, Petiscos, Louças e taças, Descartáveis), com atalhos por grupo, botões − e +, e marcação verde do que já foi contado.
- **Nada fica sem contar:** todo item precisa de um número, inclusive o zero; os que faltam ficam em vermelho e o botão leva ao primeiro. O servidor também recusa contagem incompleta. Se o garçom tentar sair ou fechar a página com a contagem pela metade, o app pergunta antes; os números ficam salvos no celular e, ao voltar, ele continua de onde parou.
- Antes de enviar, ele confere todos os números. No fim da lista há um campo de **observação** opcional (até 500 caracteres), visto pela gestão no Controle, em Registros e no CSV.
- **Uma contagem por turno, feita em equipe.** Quem começa a contar salva o andamento no servidor; os outros garçons veem "Bruno está fazendo esta contagem · 12 de 29" com os grupos já contados e, se ele precisar parar, tocam em **Continuar daqui** e seguem de onde parou (só quem está com a contagem edita). Depois de enviada, o turno fica fechado para os outros garçons.
- Ao enviar, a data, a hora e os nomes de quem participou são gravados pelo servidor. O garçom não vê histórico.
- **Correção só com aprovação e só no mesmo dia.** Quem participou pode pedir correção no dia; os números novos só valem quando a gestão aprovar. A gestão vê o pedido no Controle e em Registros → Contagem do salão (o que muda, enviado → correção) e aprova ou recusa; o garçom vê o resultado. No dia seguinte não dá mais para pedir.
- **Contar de verdade.** O passo a passo e a tela lembram de contar olhando, sem print, sem copiar a contagem anterior e sem fazer conta de cabeça. Se 80% ou mais dos números forem iguais aos da outra contagem do dia, o app avisa antes do envio, e a gestão vê o alerta de números iguais aos da contagem anterior.
- A gestão vê em **Registros → Contagem do salão** o calendário do mês (dias com as duas contagens, só uma ou nenhuma), filtro por turno, a tabela do dia com cada contagem e a **variação** em relação à contagem anterior (a do dia comparada com a noite anterior; a da noite, com o dia): ▼ vermelho quando diminuiu, ▲ verde quando aumentou. No topo aparecem as maiores quedas e reposições, e há o filtro “Só itens que mudaram”, e pode exportar o mês em CSV para o Excel. O Controle mostra a contagem de hoje dos dois turnos.
- Em Setores → Garçom, a gestão vê os itens separados por tipo (Bebidas, Café e açúcar, Petiscos, Louças e taças, Descartáveis, Outros), escolhe o tipo ao incluir ou editar um item (`countGroups`) e muda a ordem arrastando pelo ⋮⋮ ou pelas setas, dentro do tipo. A ordem e o tipo valem para a tela dos garçons.
- Os itens contados são editados pela gestão em Setores → Garçom e ficam salvos na programação (`countItems`). Enquanto ninguém editar, vale a lista padrão da planilha do salão (`DEFAULT_COUNT_ITEMS`, no `index.html`).

## Administrativo (assistente de contratos e analista administrativo)

Cada perfil vê só a própria parte; a gestão vê e configura tudo (Setores → Adm. no celular, grupo Administrativo no computador).

- **Cronograma** (os dois perfis): a gestão cria a tarefa com data (uma vez só ou repetindo, na frequência que quiser) ou **pontual** (fica na lista até alguém concluir, com prazo opcional) e escolhe quem faz. Quem recebe marca como feita (sem foto). Tarefas de dias anteriores não feitas aparecem em Atrasadas por 14 dias.
- **Auditoria de contratos** (assistente): as mesmas colunas da planilha da sala (cliente, aprovador, data da venda, turno, cotas, responsável pelo lançamento, auditado, data e responsável pela auditoria, erro, boletos, documentação UAU, CRM e Flow). Quem lança não audita o próprio contrato. Cada item auditado recebe **verde** (certo), **amarelo** (erro mediano, talvez não venha) ou **vermelho** (erro que vai ou corre muito risco de ser pontuado); a cor do contrato é a do pior item. Filtro por cor, busca por cliente e exportação do mês no formato da planilha.
- **Chamados** (assistente): número, data de abertura e descrição do chamado aberto em outro sistema; marcar como feito; **Copiar** copia os chamados em aberto no modelo da sala (“descrição” e, embaixo, “(Chamado aberto #número aberto dia dd/mm/aaaa)”).
- **Notas fiscais** (analista): cadastro de parceiros e de alimentação PJ; por mês, uma linha por parceiro com nota recebida, baixa nos vouchers (ou “parceiro não entregou voucher este mês”), lançamento no Zeev e pagamento (previsto ou efetivado). Cada nota tem histórico de quem fez cada coisa e quando, e a lista “A cobrar” (com botão de copiar) mostra o que falta de nota e de voucher no mês.
- **Pedidos** (analista): pedido mensal do setor de compras com a data em que chegaram o pedido e a nota, o lançamento no Zeev, o pagamento programado e a conferência (conforme ou não conforme). O andamento vai em comentários, cada um com usuário e hora; o comentário final pode fechar o pedido como resolvido. Alterações de datas também ficam registradas.
- **Caixas** (analista; configurados pela gestão): cada caixa tem equipes com valor mensal (ex.: SPIF com 4 equipes de R$ 1.000 e Administrativo com R$ 1.500). Saldo do mês total e por equipe, lançamento de pagamentos (lançado ou pago), comprovante anexado (recibo assinado ou nota), exportação do mês e **recibo de pagamento** no modelo da sala, um por pagamento, pronto para imprimir e assinar.
- **Painel de contratos** (gestão): números do mês por cor, gráfico dos últimos 6 meses, onde estão os erros (por item), por responsável pelo lançamento e a lista dos erros do mês. É só para acompanhar; o aviso de “erros novos” some depois que a gestão abre o painel.
- **Funções por pessoa**: o padrão é analista com notas, pedidos e caixas, e assistente de contratos com contratos e chamados. Em Usuários → Administrativo, a gestão marca outras funções para cada pessoa (coluna `adm_modules`). O cronograma é de todos, mas cada um vê só as próprias tarefas (também no banco) e pode criar tarefas para si.
- **Histórico**: notas, pedidos, pagamentos, contratos e chamados guardam quem lançou e cada alteração (botão Histórico). Pagamento não é apagado: é cancelado e continua no histórico.
- **Parceiros**: entram na lista a partir de um mês e podem sair a partir de outro; os meses anteriores continuam com as notas registradas. “Sem nota este mês” tira o parceiro dos pendentes; voucher não entregue continua na cobrança. Há dois tipos de pendente: de receber e com problema na nota (com a descrição do problema); depois vem o lançado no Zeev. O pagamento é opcional e não entra no painel.
- **Controle do gestor**: “Precisa de você” reúne as pendências de todas as áreas (cadastros, correções de contagem, contagem não enviada, limpeza atrasada, contratos vermelhos ou sem auditoria, pedidos com pendência, chamados novos (só o aviso; o resto é acompanhamento), tarefas atrasadas, saldo negativo), e abaixo vem um cartão por área.
- Banco: rode `supabase/administrativo.sql` no SQL Editor (depois de `equipe.sql`). Ele cria a tabela `adm_items`, as permissões por perfil e o armazenamento privado `comprovantes` (fora da limpeza de 30 dias das fotos).

## Como funciona

Nada é atribuído direto a uma ASG: as tarefas entram em **listas**, e cada lista é liberada para uma ou mais ASGs. Ao entrar, a ASG escolhe qual lista vai assumir no dia.

**Gestor**
- **Controle**: progresso de todas as listas no dia (concluídas, justificadas, pendentes e atrasadas), quem assumiu cada lista, situação de cada ASG e justificativas do dia.
- **Limpar atrasadas** (só gestão): quando há tarefas atrasadas pendentes, o Controle mostra o botão **Limpar N tarefas atrasadas**. Elas deixam de ser cobradas das ASGs a partir do dia da limpeza; o dia original continua no histórico como sem registro. Atrasadas já concluídas ou justificadas no dia não mudam.
- **Cômodos**: a gestão cria os cômodos e o que será feito em cada um (tarefa, instruções com uma etapa por linha, materiais, se a foto é obrigatória e frequência sugerida). Os cômodos e as tarefas da planilha já vêm cadastrados.
- **Listas**: crie quantas listas quiser. Em cada lista:
  - **Adicionar tarefas**: seletor com todas as tarefas por cômodo, com "Marcar todas" em cada cômodo. Depois, escolha entre usar a frequência sugerida de cada tarefa ou uma mesma repetição para todas;
  - a repetição de cada tarefa pode ser ajustada (uma vez, a cada N dias, dias da semana a cada N semanas, todo mês num dia, com início e término), e a tarefa pode ser pausada ou removida;
  - **Liberar ASG**: escolha as ASGs que podem assumir a lista. Quem tem menos atividades aparece primeiro.
- **ASG**: cadastro (nome, e-mail de acesso, senha, ativa ou inativa) e as listas que cada uma pode assumir.
- **Calendário da ASG**: ao tocar no nome da ASG, aparece o calendário do mês. Nos dias passados, mostra o que ela fez (concluídas/total, com cor para tudo feito, com justificativa ou pendente). Nos dias futuros, mostra quantas tarefas estão previstas nas listas liberadas para ela. Ao tocar no dia, aparecem as tarefas daquele dia.
- **Registros**: por dia e por lista, com quem assumiu, justificativas e o que ficou sem registro. Tarefas com foto mostram o ícone **Ver foto**, e a imagem só é baixada ao tocar nele.
- **Perfil**: trocar senha, **cadastrar outros gestores** (com acesso a toda a gestão; podem ser editados, desativados ou excluídos, menos o próprio acesso), exportar backup e importar cômodos e listas de um backup.

**ASG**
- Se tem só uma lista liberada, já fica com ela automaticamente. Se tem mais de uma, escolhe ao entrar qual vai assumir no dia. Se uma colega faltou, pode assumir mais de uma lista.
- Vê as tarefas do dia dessas listas, separadas por cômodo, e pode trocar a lista enquanto não tiver registrado nada nela.
- Conclui com foto (obrigatória ou opcional, conforme a tarefa) ou justifica a não execução. A foto é tirada na hora pela câmera, sem opção de escolher da galeria, e sai com data e hora gravadas.
- Se a câmera ainda não foi liberada, a tela inicial mostra o botão **Permitir câmera**. Se o acesso foi bloqueado, aparecem as instruções para liberar no Android (Chrome) ou no iPhone (Safari).
- Uma ocorrência anterior não concluída volta como atrasada, se a tarefa não se repetir no dia.
- Finaliza o dia quando não há pendências. O histórico mostra os últimos 7 dias.

## Acesso e dados (Supabase)

Os dados ficam no Supabase (projeto `lwegjqiavjfprrapxjle`): login, cômodos, tarefas, listas, registros e fotos. Qualquer aparelho com o mesmo login vê as mesmas informações, e as telas se atualizam sozinhas quando alguém registra algo.

- A chave usada no `index.html` é a chave pública (publishable). As permissões ficam nas regras do banco (`supabase/schema.sql`): somente gestores alteram cômodos, listas e cadastros; a equipe registra tarefas e escolhe a própria lista.
- O primeiro gestor é `carlos.santos@gavresorts.com.br`. Outros gestores e as ASGs são cadastrados pelo sistema.
- As fotos ficam no bucket privado `fotos`. O aplicativo pede uma URL temporária de 2 minutos para exibir cada comprovante. Links públicos antigos são convertidos em caminhos para leitura autenticada.
- Conclusões, escolhas e fechamentos são validados no banco por `gav_apply_changes`, em uma transação. A interface só confirma o sucesso após a resposta do servidor. Uma falha de conexão mantém a edição pendente neste aparelho para nova tentativa.
- Alterações da programação exigem a versão que o gestor carregou. Um conflito é recusado, a versão atual é recarregada e a edição local fica disponível para baixar e conferir.
- O histórico guarda versões da programação e uma cópia da tarefa em cada conclusão/justificativa. Excluir um acesso arquiva o perfil, preservando a autoria e os fechamentos.
- Consultas e backup são paginados; o backup inclui os registros disponíveis no servidor, sem o corte anterior de 120 dias. Os arquivos das fotos continuam no armazenamento e não são incorporados ao JSON exportado.

### Preparar o Supabase (uma vez)

1. **SQL Editor > New query**: colar todo o conteúdo de `supabase/schema.sql` e clicar em **Run**.
2. **Authentication > Sign In / Providers > Email**: desligar **Confirm email** e salvar. Sem isso, o cadastro de ASGs e gestores pelo sistema não funciona.
3. **Authentication > Users > Add user > Create new user**: e-mail `carlos.santos@gavresorts.com.br`, a senha do gestor e **Auto Confirm User** marcado. Ele vira gestor automaticamente.

No primeiro acesso do gestor, o sistema cria os cômodos e as tarefas da planilha. Se o navegador tinha dados da versão anterior, que guardava tudo localmente, os cômodos, tarefas e listas dessa versão são aproveitados. As ASGs precisam ser cadastradas de novo, porque as senhas antigas ficavam só no aparelho.

### Atualizar uma instalação existente

Execute `supabase/reliability.sql` no SQL Editor do projeto existente e publique a versão correspondente de `index.html` e `reliability.js`. O script usa uma transação e pode ser repetido. Não apaga registros nem fotos. Instalações novas podem executar o `schema.sql` completo, que já inclui esta atualização.

O procedimento torna o bucket privado e bloqueia as gravações diretas da versão antiga; por isso banco e arquivos do site devem ser atualizados juntos. Navegadores já abertos devem recarregar a página depois da publicação. Dados e descrições removidos antes desta atualização não podem ser reconstruídos automaticamente; os registros antigos ainda vinculados a tarefas recebem os metadados disponíveis na instalação.

### Fotos apagadas após 30 dias

Execute `supabase/photo-retention.sql` no SQL Editor (uma vez; pode ser repetido). Depois disso, quando um gestor abre o app, uma vez por dia, as fotos com mais de 30 dias são apagadas do armazenamento. O registro da tarefa continua no histórico, marcado como "Foto apagada após 30 dias". O banco só permite que a gestão apague fotos vencidas; ASGs não apagam nenhuma.

Enquanto o script não for executado, o app segue normalmente e apenas não faz a limpeza. Se nenhum gestor abrir o app por alguns dias, a limpeza acontece no próximo acesso.

### Equipe geral: garçons, cadastro pelo site e contagem

Execute `supabase/equipe.sql` no SQL Editor (uma vez; pode ser repetido; não apaga dados). Ele libera o perfil de garçom, o cadastro com aprovação, a tabela de contagens, a contagem em equipe (`count_progress`) e a aprovação de correções. Sem o script, a contagem mostra que falta atualizar o banco e o cadastro pelo site avisa que ainda não está ativo. Mantenha **Confirm email** desligado: o cadastro pelo site depende disso.

### Testes

Com Node.js e as dependências de desenvolvimento instaladas, execute `npm test`. Os testes do banco usam PostgreSQL local via PGlite, sem tocar nos dados reais. Cobrem autorização entre ASGs, impedimento de fechamento pendente, gravação atômica, foto obrigatória, privacidade do armazenamento, histórico, conflitos de versão, recuperação de atraso e repetição da atualização.

## Executar

Publique pelo GitHub Pages ou abra `index.html` no navegador. É preciso internet para entrar.

## Publicação com GitHub Pages

Após definir o repositório e autorizar a publicação:

1. Colocar estes arquivos na raiz da branch `main`.
2. Abrir Settings > Pages no repositório.
3. Selecionar Deploy from a branch, branch `main`, pasta `/ (root)`.
4. Salvar e aguardar o endereço confirmado pelo GitHub.

`index.html` é o ponto de entrada. `.nojekyll` mantém a publicação como arquivos estáticos.

Repositório privado e site com acesso restrito não são equivalentes. A modalidade disponível depende da conta e do plano; a visibilidade deve ser definida antes da publicação.

Referência: [Criar um site do GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site).

## Arquivos

- `index.html`: sistema completo (gestor e ASG).
- `reliability.js`: sincronização, paginação, histórico preservado e acesso às fotos privadas.
- `.nojekyll`: configuração para arquivos estáticos.
- `.gitignore`: arquivos locais excluídos do versionamento.
- `supabase/schema.sql`: tabelas, regras de acesso, funções da gestão e armazenamento das fotos no Supabase.
- `supabase/reliability.sql`: atualização transacional para instalações existentes.
- `supabase/photo-retention.sql`: exclusão das fotos com mais de 30 dias.
- `supabase/equipe.sql`: perfil de garçom, cadastro pelo site com aprovação e contagem de estoque.
- `supabase/administrativo.sql`: perfis do administrativo, cronograma, contratos, chamados, notas, pedidos, caixas e comprovantes.
- `admin.js` e `admin.css`: telas do administrativo e do controle do gestor.
- `tests/`: testes isolados de regressão e do banco.
- `README.md`: funcionamento, escopo e publicação.
