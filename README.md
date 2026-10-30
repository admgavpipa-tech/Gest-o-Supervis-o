# GAV - Gestão de rotinas de limpeza

Aplicativo estático em HTML e JavaScript para a gestão atribuir tarefas de limpeza às ASGs e acompanhar a execução, com identidade visual do template GAV. Publique `index.html` e `reliability.js` juntos.

## Como funciona

Nada é atribuído direto a uma ASG: as tarefas entram em **listas**, e cada lista é liberada para uma ou mais ASGs. Ao entrar, a ASG escolhe qual lista vai assumir no dia.

**Gestor**
- **Controle**: progresso de todas as listas no dia (concluídas, justificadas, pendentes e atrasadas), quem assumiu cada lista, situação de cada ASG e justificativas do dia.
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
- `tests/`: testes isolados de regressão e do banco.
- `README.md`: funcionamento, escopo e publicação.
