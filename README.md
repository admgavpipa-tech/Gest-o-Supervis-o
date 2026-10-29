# GAV - Gestão de rotinas de limpeza

Sistema HTML de arquivo único para a gestão atribuir tarefas de limpeza às ASGs e acompanhar a execução, com identidade visual do template GAV.

## Como funciona

O sistema tem dois perfis, com a mesma tela de entrada:

**Gestor** (controle geral)
- **Controle**: progresso da equipe no dia, concluídas, justificadas, pendentes e atrasadas, situação de cada ASG e justificativas do dia.
- **ASG**: cadastro das ASGs (nome, e-mail de acesso, senha e turno; ativar ou desativar) e, dentro de cada uma, as **atribuições**.
- **Atribuição**: para qual ASG, qual tarefa (da planilha ou personalizada), local, instruções (uma etapa por linha), materiais, grupo de esforço, turno, cobertura essencial, observação e **quando**:
  - não repetir (uma vez, em uma data);
  - repetir a cada N dias;
  - repetir em dias da semana, a cada N semanas;
  - repetir todo mês em um dia, a cada N meses;
  - data de início, término opcional e horário opcional. O resumo mostra as próximas datas antes de salvar.
  - Atribuições podem ser editadas, pausadas ou excluídas. "Salvar e atribuir outra" mantém a repetição para cadastrar várias tarefas seguidas.
- **Registros**: por dia e por ASG, com fotos, justificativas e o que ficou sem registro.
- **Atividades**: as 131 atividades da planilha, com botão para atribuir. A frequência da planilha já sugere a repetição.
- **Perfil**: trocar senha, exportar e importar backup.

**ASG**
- Vê somente as tarefas atribuídas a ela para o dia, separadas por local.
- Conclui com foto ou justifica a não execução.
- Uma ocorrência anterior não concluída volta como atrasada, se a atribuição não se repetir no dia.
- Finaliza o turno quando não há pendências. O histórico mostra os últimos 7 dias.

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
