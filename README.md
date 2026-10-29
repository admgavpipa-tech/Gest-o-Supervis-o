# GAV - Protótipo de rotinas de limpeza

Protótipo HTML navegável da experiência de execução das tarefas de limpeza, com identidade visual do template GAV.

## Direção definida

O gestor definirá as tarefas da operação. A forma de cadastro e planejamento aguarda o detalhamento do responsável pelo projeto.

A equipe de ASGs seguirá o fluxo já demonstrado: escolher local, consultar a tarefa e suas instruções, registrar foto ou justificar a não execução e finalizar o turno quando não houver registros pendentes.

O cadastro pertence à operação. A distribuição considera as pessoas presentes, permitindo cobrir o essencial de vários locais quando uma ASG faltar. Uma tarefa não pertence permanentemente a uma pessoa.

Não há interface funcional do gestor nesta versão. As opções de Ajustes são controles da demonstração, não permissões operacionais concedidas à ASG.

## Executar a prévia

Abra `index.html` no navegador. O e-mail e a senha de exemplo já estão preenchidos. Nenhuma conta real é acessada e nenhuma senha é enviada.

O arquivo é independente: inclui as logos, os estilos e os dados necessários à demonstração.

## O que pode ser experimentado

- Navegação por locais, tarefas e instruções.
- Conclusão com uma foto escolhida no dispositivo ou com registro demonstrativo.
- Justificativa de tarefa não realizada, distinta de limpeza concluída.
- Fechamento bloqueado enquanto há tarefa sem conclusão ou justificativa.
- Tarefas atrasadas sem duplicar uma atividade que se repete hoje.
- Grupos de esforço 1, 2 e 3.
- Consulta às 131 atividades da planilha e filtro por local e grupo.
- Simulação de falta de uma ASG e alternância entre turno diurno e noturno.

A agenda e a data mostradas são exemplos. Não há geração de agenda real a partir das frequências da planilha.

## Registros e acesso

Os registros são guardados somente no navegador do dispositivo. Não há sincronização de equipe, autenticação real, banco compartilhado ou controle de acesso por perfil.

O login não protege o conteúdo do arquivo. A publicação deve considerar que o cadastro de atividades, materiais, instruções e as marcas incorporadas ficam acessíveis junto da demonstração.

O uso real com gestor e equipe exigirá que as regras de definição das tarefas sejam detalhadas e que os registros sejam compartilhados de forma adequada entre os perfis.

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

- `index.html`: protótipo completo.
- `.nojekyll`: configuração para arquivos estáticos.
- `.gitignore`: arquivos locais excluídos do versionamento.
- `README.md`: funcionamento, escopo e publicação.
