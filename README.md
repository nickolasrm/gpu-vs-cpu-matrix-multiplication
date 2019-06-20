# AA de Arquitetura 1
Processos realizados
- Transposta
- Otimização de partes recorrentes
- AVX
- OMP
- CUDA
- Tile based

**COMANDOS**
- Compilar os codigos com comando "make"
- Gerar uma matriz "./PROG g L1 C1 L2 C2 s"
  - "PROG" é o programa a ser utilizado (./cuda ou ./norm)
  - "g" diz ao programa para gerar uma matriz
  - "L1 C1" são as dimensoes da matriz A
  - "L2 C2" são as dimensões da matriz B
  - "s", é opcional e diz ao programa para salvar as matrizes A e B. (Caso não o tenha, só é salva a matriz C)
- Ler uma matriz "./PROG f L1 C1 L2 C2 ARQ1 ARQ2"
  - "PROG" é o programa a ser utilizado (./cuda ou ./norm)
  - "f" diz ao programa para ler uma matriz
  - "L1 C1" são as dimensoes da matriz A
  - "L2 C2" são as dimensões da matriz B
  - "ARQ1" é o nome do arquivo da matriz A
  - "ARQ2" é o nome do arquivo da matriz B
- Compilar comparador de matrizes com "make comparador"
- Comparar resultado das matrizes com  "./comp C1.txt C2.txt"
- Renomear matrizes 0....txt, 1....txt e  2....txt para a.txt, b.txt e c.txt com "make rename"
- Limpar txts com "make clean"
