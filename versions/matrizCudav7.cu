/*
#v1
Ideia: Transformar as matrizes em transpostas para nao precisar fazer ler dois ponteiros, apenas usar o deslocamento
Resultado: Aumento de performance. Tempo 1/8 vezes o anterior #8.2 -> 1.1

#v2
Ideia: Transformar matriz em vetor para preparar para CUDA
Resultado: Perda de desempenho. Tempo 2.4 vezes o anterior #1.1 -> 2.4
	#v2.1
	Ideia: otimizar o codigo antes do CUDA procurando por calculos repetidos e os atribuindo a auxiliares
	Resultado: Ganho de desempenho. Tempo 10/15 vezes o anterior #2.4 -> 1.55

#v3
Ideia: Utilizar a GPU para fazer os calculos quando a matriz for grande
Resultado: Ganho de desempenho. Tempo 10/50 vezes o anterior #1.55 -> 0.35

#v4 - DESCONSIDERADO
Otimizar processamento na CPU com e SSE
Resultado: N/A

#v4.1
Utilizar AVX ao inves de SSE
Resultado: Ganho de desempenho. Tempo 10/28 vezes o anterior # 1.55 -> 0.55
	#v4.2
	Encontradas novas contas frequentes e foram trocadas para variaveis auxiliar

#v5 - DESCONSIDERADO
Utilizar GPU e CPU ao mesmo tempo e remover if do kernel da GPU
Resultado: Perda de desempenho

#v5.1
Utilizar OpenMp para paralelizar codigos na CPU
Resultado: Ganho de performance. Tempo > 1/2 vezes o anterior #0.55 -> 0.22 ######AINDA NAO ESTIMADO
	#5.1.1
	Melhora pequena, porem consideravel ao guardar o endereco de C[indiceC]

#v6
Melhorar CUDA para vencer a CPU
Realizado: Correcao do do race condition de escrever na matriz C
Resultado: Ganho de performance. Tempo > 1/2 vezes o anterior

#v7
Encontrar os pontos os quais a CPU ganha da GPU e escolher a melhor funcao para cada
Resultado: Encontrados de forma parcial, consegue acertar para a maioria dos casos
*/

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <immintrin.h>
#include <omp.h>

#define NTRANS 0
#define TRANS 1

#define OPMAX 1024
#define MAXTHREADS_GPU 32	//32*32=1024, Nao se deve ter mais que 1024 threads por bloco

#define MAXTHREADS_CPU 8

#define AVXJUMP 8

#define SEC_AS_NANO 1000000000.0

struct _matriz
{
	int n;
	int m;
	int *cont;
}; typedef struct _matriz Matriz;

struct _input
{
	Matriz *a;
	Matriz *b;
	Matriz *c;
	short int salvar;
}; typedef struct _input Input;

Matriz *criarMatriz(int n, int m)
{
	Matriz *mat = (Matriz*) malloc(sizeof(Matriz));

	mat->n = n;
	mat->m = m;
	mat->cont = (int*) malloc(n * m * sizeof(int*));

	return mat;
}

void liberarMatriz(Matriz *m)
{
	free(m->cont);
	free(m);
}

Matriz *gerarMatriz(int n, int m)
{
	Matriz *mat = criarMatriz(n, m);
	
	for(int i = 0; i < n; i++)
		for(int j = 0; j < m; j++)
			{
				mat->cont[i * m + j] = rand() % 100;
			}

	return mat;
}

void printarMatriz(Matriz *mat)
{
	for(int i = 0; i < mat->n; i++)
	{
		for(int j = 0; j < mat->m; j++)
			printf("%d ", mat->cont[i * mat->m + j]);
		printf("\n");
	}
}

void multiplicarMatrizesAVX(Matriz *matA, Matriz *matB, Matriz *matC)
{
	int *a = matA->cont, *b = matB->cont, *c = matC->cont, *alvoC;
	int aN = matA->n, bN = matB->n, aM = matA->m, bM = matB->m, cM = matC->m;

	__m256i mask = _mm256_setr_epi32(-1, -2, -3, -4, -5, -6, -7, -8);	//MASCARA INFORMA QUE SERAO USADOS OS 256 BITS DO AVX
	__m256i regMults;

	int indiceA, indiceB;
	int limK = bM - (bM % AVXJUMP);

	int i, j, k;

	#pragma omp parallel for firstprivate(aN, indiceA, aM, bN, indiceB, bM, alvoC, c, cM, limK, a, b) private(i, j, k, regMults)
	for(i = 0; i < aN; i++)
	{
		indiceA = i * aM;
		for(j = 0; j < bN; j++)
		{
			indiceB = j * bM;
			alvoC = &c[i * cM + j];
			*alvoC = 0;

			for(k = 0; k < limK; k += AVXJUMP)	//LOOP PARA MULTIPLOS DE 8, LIMITE DO AVX E THREADS
			{
					regMults = _mm256_mullo_epi32(_mm256_maskload_epi32(&a[indiceA + k], mask),
									_mm256_maskload_epi32(&b[indiceB + k], mask));
					regMults = _mm256_hadd_epi32(regMults, regMults);
					regMults = _mm256_hadd_epi32(regMults, regMults);
					*alvoC += (_mm256_extract_epi32(regMults, 0) + _mm256_extract_epi32(regMults, 7));
			}
		}
	}

	if(limK < bM)	//SEPARADO DO LOOP J PRINCIPAL PARA EVITAR CALCULOS EM MULTIPLOS DE 8
	{
		#pragma omp parallel for firstprivate(aN, indiceA, aM, bN, indiceB, bM, alvoC, c, cM, limK, a, b) private(i, j, k)
		for(i = 0; i < aN; i++)
		{
			indiceA = i * aM;
			for(j = 0; j < bN; j++)
			{
				indiceB = j * bM;
				alvoC = &c[i * cM + j];

				for(k = limK; k < bM; k++)	//LOOP PARA CASO O N°COL DE C NAO SEJA MULTIPLO DE 8
					*alvoC += a[indiceA + k] * b[indiceB + k];
			}
		}

	}
}

//KERNEL QUE EXECUTA AS INSTRUCOES NA GPU
__global__ void kernelMulMatriz(int *a, int aN, int aM, int *b, int bN, int bM, int *c, int cM)
{
	int i = blockDim.x * blockIdx.x + threadIdx.x;
	int j = blockDim.y * blockIdx.y + threadIdx.y;

	if(i < aN && j < bN)
	{
		int indiceA = i * aM;
		int indiceB = j * bM;
		int soma = 0;
		for(int k = 0; k < bM; k++)
			soma += a[indiceA + k] * b[indiceB + k];
		c[i * cM + j] = soma;
	}
}

//FUNCAO QUE PREPARA PARA A GPU
void multiplicarMatrizesCUDA(Matriz *a, Matriz *b, Matriz *c)
{
	int *d_a, *d_b, *d_c, opCount = a->n * b->n;
	dim3 blocksPerGrid(1, 1), threadsPerBlock(a->n, b->n);
	if(opCount > OPMAX)
	{
		threadsPerBlock.x = MAXTHREADS_GPU;
		threadsPerBlock.y = MAXTHREADS_GPU;
		blocksPerGrid.x = ceil(((double) a->n / MAXTHREADS_GPU));
		blocksPerGrid.y = ceil(((double) b->n / MAXTHREADS_GPU));
	}

	cudaMalloc(&d_a, sizeof(int) * a->n * a->m);
	cudaMalloc(&d_b, sizeof(int) * b->n * b->m);
	cudaMalloc(&d_c, sizeof(int) * c->n * c->m);
	cudaMemcpy(d_a, a->cont, sizeof(int) * a->n * a->m, cudaMemcpyHostToDevice);
	cudaMemcpy(d_b, b->cont, sizeof(int) * b->n * b->m, cudaMemcpyHostToDevice);

	kernelMulMatriz <<<blocksPerGrid, threadsPerBlock>>> (d_a, a->n, a->m, d_b, b->n, b->m, d_c, c->m);

	cudaMemcpy(c->cont, d_c, sizeof(int) * c->n * c->m, cudaMemcpyDeviceToHost);

	cudaFree(d_a);
	cudaFree(d_b);
	cudaFree(d_c);

	cudaDeviceSynchronize();
}

Matriz *lerMatriz(char *nome, int n, int m, short int trans)
{
	Matriz *mat = NULL;
	FILE *f = fopen(nome, "r");
	if(trans)
	{
		mat = criarMatriz(m, n);

		for(int i = 0; i < n; i++)
			for(int j = 0; j < m; j++)
				fscanf(f, " %d", &(mat->cont[j * n + i]));
	}
	else
	{
		mat = criarMatriz(n, m);

		for(int i = 0; i < n; i++)
			for(int j = 0; j < m; j++)
				fscanf(f, " %d", &(mat->cont[i * m + j]));
	}
	fclose(f);

	return mat;
}

void salvarMatriz(Matriz *mat, short int trans)
{
	static int i = 0;
	char nome[100];

	if(trans)	sprintf(nome, "%d-%dx%d.txt", i, mat->m, mat->n);
	else		sprintf(nome, "%d-%dx%d.txt", i, mat->n, mat->m);

	FILE *f = fopen(nome, "w");

	if(trans)
		for(int i = 0; i < mat->m; i++)
		{
			for(int j = 0; j < mat->n; j++)
				fprintf(f, "%d ", mat->cont[j * mat->m + i]);
			fprintf(f, "\n");
		}
	else
		for(int i = 0; i < mat->n; i++)
		{
			for(int j = 0; j < mat->m; j++)
				fprintf(f, "%d ", mat->cont[i * mat->m + j]);
			fprintf(f, "\n");
		}

	fclose(f);
	i++;
}

Input *lerInput(int argc, char **argv)
{
	if(argc >= 6)
	{
		Input *i = (Input *) malloc(sizeof(Input));
		i->salvar = 0;

		int n1, m1, n2, m2;
		char op;

		op = argv[1][0];
		
		sscanf(argv[2], " %d", &n1);
		sscanf(argv[3], " %d", &m1);
		sscanf(argv[4], " %d", &n2);
		sscanf(argv[5], " %d", &m2);
	
		if(m1 == n2)
		{
			Matriz *a, *b, *c;		
			
			switch(op)
			{
				case 'g':
					srand(time(NULL));
					a = gerarMatriz(n1, m1);
					b = gerarMatriz(m2, n2); //INVERTIDOS PARA A TRANSPOSTA
					if(argc == 7 && argv[6][0] == 's')
						i->salvar = 1;
					break;
				case 'f':
					a = lerMatriz(argv[6], n1, m1, NTRANS);
					b = lerMatriz(argv[7], n2, m2, TRANS);
					break;
				default:
					return 0;
			}
			c = criarMatriz(n1, m2);

			i->a = a;
			i->b = b;
			i->c = c;

			return i;
		}
		else
		{
			printf("Matrizes Incompativeis!\n");
			exit(0);
		}
	}

	return NULL;
}

double medirTempoInput(Input **i, int argc, char **argv, Input *ler(int, char**))
{
	timespec ini, fim;
	clock_gettime(CLOCK_REALTIME, &ini);
	*i = ler(argc, argv);
	clock_gettime(CLOCK_REALTIME, &fim);

	double iniSec = ini.tv_sec + ini.tv_nsec / SEC_AS_NANO;
	double fimSec = fim.tv_sec + fim.tv_nsec / SEC_AS_NANO;	

	return (fimSec - iniSec);
}

double medirTempoExecMul(Input *i, void mul(Matriz*, Matriz*, Matriz*))
{
	timespec ini, fim;
	clock_gettime(CLOCK_REALTIME, &ini);
	mul(i->a, i->b, i->c);
	clock_gettime(CLOCK_REALTIME, &fim);

	double iniSec = ini.tv_sec + ini.tv_nsec / SEC_AS_NANO;
	double fimSec = fim.tv_sec + fim.tv_nsec / SEC_AS_NANO;	

	return (fimSec - iniSec);
}

void salvarELiberarMatrizes(Input *i)
{	
	if(i->salvar)
	{
		salvarMatriz(i->a, NTRANS);
		salvarMatriz(i->b, TRANS);
	}
	salvarMatriz(i->c, NTRANS);

	liberarMatriz(i->a);
	liberarMatriz(i->b);
	liberarMatriz(i->c);
	free(i);
}

int verificarArgumentos(int argc, char **argv)
{
	if(argc < 6)
	{
		printf("Poucos argumentos\n"
			"#  FONTE: f para arquivos, g para gerar\n"
			"#  LINSA: linhas para matriz A\n"
			"#  COLSA: colunas para matriz A\n"
			"#  LINSB: linhas para matriz B\n"
			"#  COLSB: colunas para matriz B\n"
			"#  ARQA: arquivo com a matriz A\n"
			"#  ARQB: arquivo com a matriz B\n"
			"#  SAV (opcional): salva as matrizes A e B geradas"
			"##  ./prog f LA CA LB CB ARQA ARQB\n"
			"##  ./prog g LA CA LB CB SAV\n");
		return 0;
	}
	else
	{
		if(argv[1][0] != 'f' && argv[1][0] != 'g')
		{
			printf("Argumento fonte invalido, use g ou f\n");
			return 0;
		}

		int aux;
		for(int i = 2; i < 6; i++)
			if(!sscanf(argv[i], "%d", &aux))
			{
				printf("O valor %d nao e um numero, informe as dimensoes das matrizes A e B\n", (i - 1));
				return 0;
			}

		if(argv[1][0] == 'g')
			if(argc == 7)
				if(argv[6][0] != 's')
				{
					printf("Adicione s para salvar as matrizes A e B\n");
					return 0;
				}

		if(argv[1][0] == 'f')
		{
			FILE *f;
			if((f = fopen(argv[6], "r")) == NULL)
			{
				printf("O arquivo da matriz A nao existe\n");
				return 0;
			}
			else
				fclose(f);
			if((f = fopen(argv[7], "r")) == NULL)
			{
				printf("O arquivo da matriz B nao existe\n");
				return 0;
			}
			else
				fclose(f);
		}
		
	}

	return 1;
}

void inicializar()
{
	omp_set_num_threads(MAXTHREADS_CPU);
}

typedef void(FuncMul)(Matriz*, Matriz*, Matriz*);

FuncMul *escolherFuncao(Input *i)
{
	int col = i->c->m;
	int lin = i->c->n;

	if(lin < col)
	{
		if(lin < 64)
			return &multiplicarMatrizesAVX;
		else if(lin < 400 && col < 700)
			return &multiplicarMatrizesAVX;
		else if(lin < 500 && col < 450)
			return &multiplicarMatrizesAVX;
	}
	else
	{
		if(lin == col)
		{
			if(lin < 375)
				return &multiplicarMatrizesAVX;
		}
		else
			if(lin > col)
				if(col < 175)
					return &multiplicarMatrizesAVX;
	}

	return &multiplicarMatrizesCUDA;
}

int main(int argc, char ** argv)
{
	if(verificarArgumentos(argc, argv))
	{
			inicializar();
			Input *i = (Input*) malloc(sizeof(Input));
			printf("Tempo de criacao: %lf\n", medirTempoInput(&i, argc, argv, &lerInput));
			printf("Tempo de execucao: %lf\n", medirTempoExecMul(i, escolherFuncao(i)));
			printf("Tempo de execucao AVX: %lf\n", medirTempoExecMul(i, &multiplicarMatrizesAVX));
			printf("Tempo de execucao CUDA: %lf\n", medirTempoExecMul(i, &multiplicarMatrizesCUDA));
			salvarELiberarMatrizes(i);
	}

	return 0;
}
