# GAV - Gestão de rotinas de limpeza

Sistema HTML de arquivo único para a gestão atribuir tarefas de limpeza às ASGs e acompanhar a execução, com identidade visual do template GAV.

## Como funciona

O sistema tem dois perfis, com a mesma tela de entrada.

**Gestor**
- **Controle**: progresso da equipe no dia (concluídas, justificadas, pendentes e atrasadas), situação de cada ASG e justificativas do dia.
- **Cômodos**: a gestão cria os cômodos e o que será feito em cada um (tarefa, instruções com uma etapa por linha, materiais, cobertura essencial e frequência sugerida). Os cômodos e as tarefas da planilha já vêm cadastrados.
- **Distribuir**: todas as tarefas numa lista, cada uma com um seletor de ASG. O número ao lado do nome mostra quantas atividades ela já tem. Há filtro por cômodo e para ver só as tarefas sem ASG.
- **ASG**: cadastro (nome, e-mail de acesso, senha, ativa ou inativa). Na página da ASG, "Escolher tarefas" mostra todas as tarefas para marcar o que fica com ela.
- **Listas**: as tarefas de cada ASG ficam numa lista, onde a repetição de cada uma pode ser ajustada (uma vez, a cada N dias, dias da semana a cada N semanas, todo mês num dia, com início e término). Uma lista inteira pode ser transferida para outra ASG quando houver troca. A tela de escolha mostra primeiro quem tem menos atividades. O histórico anterior continua com a ASG de antes.
- **Registros**: por dia e por ASG, com fotos, justificativas e o que ficou sem registro.
- **Perfil**: trocar senha, exportar e importar backup.

**ASG**
- Vê somente as tarefas do dia, separadas por cômodo.
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
