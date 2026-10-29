# GAV - Gestão de rotinas de limpeza

Sistema HTML de arquivo único para a gestão atribuir tarefas de limpeza às ASGs e acompanhar a execução, com identidade visual do template GAV.

## Como funciona

Nada é atribuído direto a uma ASG: as tarefas entram em **listas**, e cada lista é liberada para uma ou mais ASGs. Ao entrar, a ASG escolhe qual lista vai assumir no dia.

**Gestor**
- **Controle**: progresso de todas as listas no dia (concluídas, justificadas, pendentes e atrasadas), quem assumiu cada lista, situação de cada ASG e justificativas do dia.
- **Cômodos**: a gestão cria os cômodos e o que será feito em cada um (tarefa, instruções com uma etapa por linha, materiais, cobertura essencial e frequência sugerida). Os cômodos e as tarefas da planilha já vêm cadastrados.
- **Listas**: crie quantas listas quiser. Em cada lista:
  - **Adicionar tarefas**: seletor com todas as tarefas por cômodo, com "Marcar todas" em cada cômodo. Depois, escolha entre usar a frequência sugerida de cada tarefa ou uma mesma repetição para todas;
  - a repetição de cada tarefa pode ser ajustada (uma vez, a cada N dias, dias da semana a cada N semanas, todo mês num dia, com início e término), e a tarefa pode ser pausada ou removida;
  - **Liberar ASG**: escolha as ASGs que podem assumir a lista. Quem tem menos atividades aparece primeiro.
- **ASG**: cadastro (nome, e-mail de acesso, senha, ativa ou inativa) e as listas que cada uma pode assumir.
- **Calendário da ASG**: ao tocar no nome da ASG, aparece o calendário do mês. Nos dias passados, mostra o que ela fez (concluídas/total, com cor para tudo feito, com justificativa ou pendente). Nos dias futuros, mostra quantas tarefas estão previstas nas listas liberadas para ela. Ao tocar no dia, aparecem as tarefas daquele dia.
- **Registros**: por dia e por lista, com quem assumiu, fotos, justificativas e o que ficou sem registro.
- **Perfil**: trocar senha, **cadastrar outros gestores** (com acesso a toda a gestão; podem ser editados, desativados ou excluídos, menos o próprio acesso), exportar backup e importar cômodos e listas de um backup.

**ASG**
- Se tem só uma lista liberada, já fica com ela automaticamente. Se tem mais de uma, escolhe ao entrar qual vai assumir no dia. Se uma colega faltou, pode assumir mais de uma lista.
- Vê as tarefas do dia dessas listas, separadas por cômodo, e pode trocar a lista enquanto não tiver registrado nada nela.
- Conclui com foto ou justifica a não execução.
- Uma ocorrência anterior não concluída volta como atrasada, se a tarefa não se repetir no dia.
- Finaliza o dia quando não há pendências. O histórico mostra os últimos 7 dias.

## Acesso e dados (Supabase)

Os dados ficam no Supabase (projeto `lwegjqiavjfprrapxjle`): login, cômodos, tarefas, listas, registros e fotos. Qualquer aparelho com o mesmo login vê as mesmas informações, e as telas se atualizam sozinhas quando alguém registra algo.

- A chave usada no `index.html` é a chave pública (publishable). As permissões ficam nas regras do banco (`supabase/schema.sql`): somente gestores alteram cômodos, listas e cadastros; a equipe registra tarefas e escolhe a própria lista.
- O primeiro gestor é `carlos.santos@gavresorts.com.br`. Outros gestores e as ASGs são cadastrados pelo sistema.
- As fotos ficam no bucket público `fotos`, com nomes aleatórios.

### Preparar o Supabase (uma vez)

1. **SQL Editor > New query**: colar todo o conteúdo de `supabase/schema.sql` e clicar em **Run**.
2. **Authentication > Sign In / Providers > Email**: desligar **Confirm email** e salvar. Sem isso, o cadastro de ASGs e gestores pelo sistema não funciona.
3. **Authentication > Users > Add user > Create new user**: e-mail `carlos.santos@gavresorts.com.br`, a senha do gestor e **Auto Confirm User** marcado. Ele vira gestor automaticamente.

No primeiro acesso do gestor, o sistema cria os cômodos e as tarefas da planilha. Se o navegador tinha dados da versão anterior, que guardava tudo localmente, os cômodos, tarefas e listas dessa versão são aproveitados. As ASGs precisam ser cadastradas de novo, porque as senhas antigas ficavam só no aparelho.

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
- `.nojekyll`: configuração para arquivos estáticos.
- `.gitignore`: arquivos locais excluídos do versionamento.
- `supabase/schema.sql`: tabelas, regras de acesso, funções da gestão e armazenamento das fotos no Supabase.
- `README.md`: funcionamento, escopo e publicação.
