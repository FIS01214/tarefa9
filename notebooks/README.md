# Notebooks

Use esta pasta para manter os notebooks da analise.

Sugestao de organizacao:

- `01_*.ipynb`: leitura com biblioteca especializada;
- `02_*.ipynb`: leitura e analise com `pandas`;
- `03_*.ipynb`: leitura manual com Python;
- `analise_parte1.ipynb`: roteiro da primeira entrega, sem codigo pronto;
- `analise_parte1_referencia.ipynb`: versao completa com codigo e respostas de
  referencia;
- `analise_parte2.ipynb`: notebook consolidado da segunda entrega, quando aplicavel.

Para sorteio de abordagens entre estudantes, use o conjunto:

- `01_leitura_texto.ipynb`: instrucoes para leitura do LHE como arquivo texto;
- `02_leitura_pylhe.ipynb`: instrucoes para leitura com `pylhe`;
- `03_leitura_dataframe.ipynb`: instrucoes para leitura com `pandas.DataFrame`;
- `01_leitura_texto_referencia.ipynb`: referencia completa do caso texto;
- `02_leitura_pylhe_referencia.ipynb`: referencia completa do caso `pylhe`;
- `03_leitura_dataframe_referencia.ipynb`: referencia completa do caso
  DataFrame.

Para a Parte 2, use o conjunto equivalente:

- `01_leitura_texto_parte2.ipynb`: instrucoes para Parte 2 com leitura por texto;
- `02_leitura_pylhe_parte2.ipynb`: instrucoes para Parte 2 com `pylhe`;
- `03_leitura_dataframe_parte2.ipynb`: instrucoes para Parte 2 com DataFrame;
- `01_leitura_texto_parte2_referencia.ipynb`: referencia completa da Parte 2
  com leitura por texto;
- `02_leitura_pylhe_parte2_referencia.ipynb`: referencia completa da Parte 2
  com `pylhe`;
- `03_leitura_dataframe_parte2_referencia.ipynb`: referencia completa da Parte 2
  com DataFrame.

Os notebooks da Parte 2 terminam com uma estimativa simplificada da secao de
choque usando `sigma = N/(A * epsilon * L)`, comparada com a secao de choque
registrada no LHE.

Os notebooks devem usar caminhos relativos a raiz do repositorio. Por exemplo:
`../data/sinal.lhe.gz` quando o notebook estiver nesta pasta.

No notebook de analise, as celulas de codigo devem permanecer vazias no
template. Os estudantes devem preencher essas celulas com codigo gerado por um
agente e revisado por eles antes da execucao.
