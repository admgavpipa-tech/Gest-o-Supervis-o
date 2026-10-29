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
- **Perfil**: trocar senha, **cadastrar outros gestores** (com acesso a toda a gestão; podem ser editados, desativados ou excluídos, menos o próprio acesso), exportar e importar backup.

**ASG**
- Se tem só uma lista liberada, já fica com ela automaticamente. Se tem mais de uma, escolhe ao entrar qual vai assumir no dia. Se uma colega faltou, pode assumir mais de uma lista.
- Vê as tarefas do dia dessas listas, separadas por cômodo, e pode trocar a lista enquanto não tiver registrado nada nela.
- Conclui com foto ou justifica a não execução.
- Uma ocorrência anterior não concluída volta como atrasada, se a tarefa não se repetir no dia.
- Finaliza o dia quando não há pendências. O histórico mostra os últimos 7 dias.

## Acesso

O acesso do gestor já vem cadastrado (e-mail `carlos.santos@gavresorts.com.br`). A senha não fica no arquivo em texto puro, apenas como hash. As ASGs recebem e-mail e senha no cadastro feito pelo gestor.

## Limites desta versão

Os dados ficam salvos no navegador (localStorage) do aparelho em que o sistema é usado. Gestor e ASGs precisam usar o mesmo aparelho/navegador para enxergar os mesmos dados; o backup (Perfil > Exportar/Importar) permite levar os dados para outro aparelho. Para cada ASG usar o próprio celular com dados sincronizados, é necessário um banco compartilhado (por exemplo, Supabase ou Firebase).

O login roda no navegador e não substitui autenticação com servidor: quem tiver o arquivo consegue ler o cadastro de atividades e as marcas incorporadas.

## Executar

Abra `index.html` no navegador ou publique pelo GitHub Pages.

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
- `README.md`: funcionamento, escopo e publicação.
