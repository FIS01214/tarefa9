# tarefa9 - Analise de eventos LHE

Este repositorio contem uma tarefa individualizada da disciplina FIS01214 para analise de eventos simulados em formato LHE. As amostras de sinal e fundo foram geradas com MadGraph5_aMC@NLO e estao disponiveis na pasta data.

## Estrutura

- data/sinal.lhe.gz
- data/fundo.lhe.gz
- data/sobre_lhe.txt
- notebooks/01_leitura_texto.ipynb
- notebooks/02_leitura_pylhe.ipynb
- notebooks/03_leitura_dataframe.ipynb
- notebooks/01_leitura_texto_parte2.ipynb
- notebooks/02_leitura_pylhe_parte2.ipynb
- notebooks/03_leitura_dataframe_parte2.ipynb
- notebooks/analise_parte1.ipynb
- resultados/graficos/
- instrucoes.txt
- parte1.txt
- parte2.txt

## Uso no Google Colab

Se você baixar este repositório pelo GitHub como arquivo `.zip`, faça o upload
desse `.zip` no Google Colab. Antes de começar a análise, peça ao agente que
gere o código para descompactar o arquivo no ambiente do Colab, entrar na
pasta extraída e confirmar que `data/sinal.lhe.gz` e `data/fundo.lhe.gz`
existem.

Depois disso, execute o notebook escolhido usando caminhos relativos à raiz
do repositório descompactado.

## Como usar

1. Leia instrucoes.txt, parte1.txt e parte2.txt.
2. Use o notebook indicado pelo professor.
3. Peca a um agente de IA para gerar o codigo pedido em cada celula de instrucao.
4. Copie o codigo gerado para a celula vazia correspondente e execute localmente.
5. Salve graficos e tabelas derivados em resultados/.

## Observacoes

- Nao altere manualmente os arquivos data/sinal.lhe.gz e data/fundo.lhe.gz.
- Use caminhos relativos a raiz do repositorio.
- Os eventos estao em nivel de gerador, nao em nivel de detector reconstruido.
- Quarks e gluons no estado final devem ser tratados como partons.

## 0. Preparação no Google Colab

Antes de iniciar a análise, siga este fluxo no ambiente do Google Colab:

1. No GitHub, baixe o arquivo ZIP deste repositório (**Code → Download ZIP**) e baixe também o notebook desta tarefa que você vai executar.
2. Abra o notebook no Colab e use o painel **Arquivos** para fazer upload do arquivo `.ipynb` e do arquivo `.zip`. O ZIP deve ficar no mesmo ambiente de execução do notebook, como arquivo de dados.
3. Peça ao agente para gerar e executar um código que localize o ZIP enviado, descompacte o repositório no ambiente do Colab e entre na pasta extraída.
4. Em seguida, peça ao agente para gerar e executar um código que infle (descomprima com `gzip`) `data/sinal.lhe.gz` e `data/fundo.lhe.gz`, criando `data/sinal.lhe` e `data/fundo.lhe`. Mantenha os arquivos `.lhe.gz` originais.
5. Confirme com o agente que a pasta `data/` contém os dois arquivos compactados e as duas versões infladas antes de prosseguir.

Depois dessa preparação, peça ao agente os códigos de cada etapa indicada neste notebook e copie-os nas células de código correspondentes. Use a pasta extraída como diretório de trabalho e mantenha os caminhos relativos aos arquivos de dados.
