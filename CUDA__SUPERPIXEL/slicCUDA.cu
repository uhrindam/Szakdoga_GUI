#include "slicCUDA.h"

__device__ int *d_clusters;								//cols * rows
__device__ float *d_distances;							//cols * rows
__device__ float *d_centers;							//centersLength * 5
__device__ int *d_center_counts;						//centersLength
__device__ uchar3 *d_colors;							//cols * rows

slicCUDA::slicCUDA() {}

slicCUDA::~slicCUDA() {}

__device__ float compute_dist(int ci, int y, int x, uchar3 colour, float *d_centers, int pitch, int d_step)
{
	//sz�nt�vols�g
	float dc = sqrt(pow(d_centers[ci *pitch + 0] - colour.x, 2) + pow(d_centers[ci *pitch + 1] - colour.y, 2)
		+ pow(d_centers[ci *pitch + 2] - colour.z, 2));
	//euklideszi t�vols�g
	float ds = sqrt(pow(d_centers[ci *pitch + 3] - x, 2) + pow(d_centers[ci *pitch + 4] - y, 2));

	return sqrt(pow(dc / nc, 2) + pow(ds / d_step, 2));
}

//l�p�ssz�m: centroidok sz�ma
//Itt rendelem a pixeleket az egyes clusterekhez sz�n, valamint euklideszi t�vols�g szerint
__global__ void orderingPixelsForClustersKernel(int d_cols, int d_rows, int d_step, int d_centersLength,
	int *d_clusters, float *d_distances, float *d_centers, int *d_center_counts, uchar3 *d_colors, int pitch)
{
	int clusterIDX = blockIdx.x * blockDim.x + threadIdx.x;
	//mivel nem tudok pontosan annyi sz�lat ind�tani ah�ny clusterem van, 
	//ez�rt megvizsg�lom, hogy az adott clusterindex m�g l�tezik-e
	if (clusterIDX < d_centersLength)
	{
		//Bej�rom az adott cluster "step" sugar� k�rnyezet�t
		//Az itt tal�lhat� pixelek mindegyik�re megn�zem, hogy az aktu�lisan vizsg�lt
		//centroid van-e hozz� a legk�zelebb, �s ha igen, akkor be�ll�tom a megfelel� adatokat
		//Ez a k�t egybe�gyazott forciklus miatt hossz�nak t�nik, de alapvet�en ez kev�s l�p�sb�l �ll
		for (int pixelY = d_centers[clusterIDX *pitch + 3] - (d_step*1.5); pixelY <
			d_centers[clusterIDX *pitch + 3] + (d_step*1.5); pixelY++)
		{
			for (int pixelX = d_centers[clusterIDX *pitch + 4] - (d_step*1.5); pixelX <
				d_centers[clusterIDX *pitch + 4] + (d_step*1.5); pixelX++)
			{
				//Ellen�rz�m a hat�rokat
				if (pixelX >= 0 && pixelX < d_rows && pixelY >= 0 && pixelY < d_cols)
				{
					uchar3 colour = d_colors[d_rows*pixelY + pixelX];
					float distance = compute_dist(clusterIDX, pixelX, pixelY, colour, d_centers, pitch, d_step);
					//ha a t�vols�g kisebb mint az eddig mentett (a default az FLT_MAX) akkor be�ll�tom 
					//az aktu�lis centroidot a legk�zelebbinek
					if (distance < d_distances[d_rows*pixelY + pixelX])
					{
						d_distances[d_rows*pixelY + pixelX] = distance;
						d_clusters[d_rows*pixelY + pixelX] = clusterIDX;
					}
				}
			}
		}

		//a centroidok alaphelyzetbe �ll�t�sa
		d_centers[clusterIDX *pitch + 0] = 0;
		d_centers[clusterIDX *pitch + 1] = 0;
		d_centers[clusterIDX *pitch + 2] = 0;
		d_centers[clusterIDX *pitch + 3] = 0;
		d_centers[clusterIDX *pitch + 4] = 0;
		d_center_counts[clusterIDX] = 0;
	}

}

//l�p�ssz�m: pixelek sz�ma
//Itt �sszegzem a kor�bban kapott eredm�nyeket.
__global__ void clusterValuesSumByPixelsKernel(int d_cols, int d_rows, int *d_clusters, float *d_distances,
	float *d_centers, int *d_center_counts, uchar3 *d_colors, int pitch)
{
	int idIn1D = blockIdx.x * blockDim.x + threadIdx.x;
	if (idIn1D < d_cols*d_rows)
	{
		//Alaphelyzetbe �ll�tom a t�vols�g�rt�keket minden piyel eset�ben
		d_distances[idIn1D] = FLT_MAX;

		//Megkeresem, hogy az adott pixel melyik centroidhoz tartozik.
		//amint ez megvan, �sszegzem ezeket az �rt�keket, atomi m�velettel, ugyanis
		//el�fordulhat hogy egy centroidhoz tartoz� t�mb�rt�ket egyszerre t�bb pixelsz�l is szeretne �rni
		//majd n�velem a centroidhoz tartoz� pixelek sz�m�t
		int whichCluster = d_clusters[idIn1D];
		atomicAdd(&d_centers[whichCluster*pitch + 0], d_colors[idIn1D].x);
		atomicAdd(&d_centers[whichCluster*pitch + 1], d_colors[idIn1D].y);
		atomicAdd(&d_centers[whichCluster*pitch + 2], d_colors[idIn1D].z);
		atomicAdd(&d_centers[whichCluster*pitch + 3], idIn1D / d_rows);
		atomicAdd(&d_centers[whichCluster*pitch + 4], idIn1D % d_rows);

		atomicAdd(&d_center_counts[whichCluster], 1);
	}
}

//l�p�ssz�m: centroidok sz�ma
//Az �sszegzett centroid�rt�keket elosztom a centroidhoz tartoz� pixelek darabsz�m�val.
__global__ void computeCorrectCentroidValuesKernel(int d_centersLength, float *d_centers, int *d_center_counts, int pitch)
{
	int idIn1D = blockIdx.x * blockDim.x + threadIdx.x;
	if (idIn1D < d_centersLength)
	{
		d_centers[idIn1D*pitch + 0] = (int)(d_centers[idIn1D*pitch + 0] / d_center_counts[idIn1D]);
		d_centers[idIn1D*pitch + 1] = (int)(d_centers[idIn1D*pitch + 1] / d_center_counts[idIn1D]);
		d_centers[idIn1D*pitch + 2] = (int)(d_centers[idIn1D*pitch + 2] / d_center_counts[idIn1D]);
		d_centers[idIn1D*pitch + 3] = (int)(d_centers[idIn1D*pitch + 3] / d_center_counts[idIn1D]);
		d_centers[idIn1D*pitch + 4] = (int)(d_centers[idIn1D*pitch + 4] / d_center_counts[idIn1D]);
	}
}

//A szomsz�dok �sszevon�sakor haszn�lt sz�nt�vols�g sz�m�t� f�ggv�ny
float slicCUDA::colorDistance(uchar3 actuallPixel, uchar3 neighborPixel)
{
	float dc = sqrt(pow(actuallPixel.x - neighborPixel.x, 2) + pow(actuallPixel.y - neighborPixel.y, 2)
		+ pow(actuallPixel.z - neighborPixel.z, 2));
	return dc;
}

//Itt ker�lnek �sszevon�sra a szomsz�dos hasonl� sz�n� szegmensek
void slicCUDA::neighborMerge()
{
	const int dx8[numberOfNeighbors] = { -1, -1,  0,  1, 1, 1, 0, -1 };
	const int dy8[numberOfNeighbors] = { 0, -1, -1, -1, 0, 1, 1,  1 };

	for (int i = 0; i < centersLength; i++)
	{
		//kimentem az aktu�lis centroid �rt�keit
		uchar3 actuallCluster;
		actuallCluster.x = centers[i * 5];
		actuallCluster.y = centers[i * 5 + 1];
		actuallCluster.z = centers[i * 5 + 2];

		int clusterRow = i / centersRowPieces;
		int clusterCol = i % centersRowPieces;

		//megn�zem az aktu�lis centroid szomsz�djait
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//ellen�rz�m a hat�rokat
			if (clusterCol + dy8[j] >= 0 && clusterCol + dy8[j] < centersRowPieces
				&& clusterRow + dx8[j] >= 0 && clusterRow + dx8[j] < centersColPieces)
			{
				//kimentem a szomsz�dos centroid adatait
				uchar3 neighborPixel;
				neighborPixel.x = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 0];
				neighborPixel.y = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 1];
				neighborPixel.z = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 2];

				//ha az aktu�lis centroid sorsz�ma kisebb mint a szomsz�d sorsz�ma, valamint a sz�nt�vols�g a megengedett hat�ron
				//bel�l van, akkor felveszem az �sszevonand� sz�msz�dok k�z�.
				if (centersRowPieces * clusterRow + clusterCol < centersRowPieces * (clusterRow + dx8[j]) +
					(clusterCol + dy8[j]) && colorDistance(actuallCluster, neighborPixel) < maxColorDistance)
				{
					neighbors[(centersRowPieces * clusterRow + clusterCol) * numberOfNeighbors + j] =
						centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]);
				}
			}
		}
	}

	//inicializ�lok egy seg�dt�mb�t, amelyben el fogom t�rolni hogy az egyes centroidokat melyik m�sik centroiddal kell �sszevonni
	int2 *changes = new int2[centersLength];
	for (int i = 0; i < centersLength; i++)
	{
		changes[i].x = i;
		changes[i].y = -1;
	}

	//Az itt k�vetkez� k�dr�sznek az a l�nyege, hogy az �sszevonand� centroidokat �sszel�ncolom �gy, hogy az egym�shoz k�zel l�v�
	//megengedett sz�nt�vols�g� centroidok �ssze legyenek vonva, annak elker�l�se v�gett, hogy esetleg egy centroid egy olyan m�sik
	//centroiddal legyen �sszevonva, amelyet m�r �sszevontam egy m�sikkal.
	//P�ld�ul: a k�p sz�l�n tal�lhat� egy feh�r keret, amelyen 500 centroid helyezkedik el. Ezeket p�ross�val is �sszevonhatn�m, de
	//ehelyett mind az 500-at egy centroidd� alak�tom, �s egyben kezelem az eg�szet.
	for (int i = 0; i < centersLength; i++)
	{
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//kimentem, hogy az adott szomsz�d az melyik centroid
			int cluster = neighbors[i * numberOfNeighbors + j];
			if (cluster != -1)
			{
				//kimentem, hogy az adott centroidot melyik m�sikkal kell �sszevonni
				int neighborIDX = changes[cluster].y;
				int clusterIDX = i;
				//Addig megyek v�gig az �sszevonand�kon am�g el nem �rek egy oylan centroidig, amit m�r nem kell m�sikkal �sszevonni
				//(Garant�ltan van olyan centroid a l�nc v�g�n amelyet nem kell m�sikkal �sszevonni, annak k�sz�nhet�en, hogy 
				//csak akkor mentem el szomsz�dk�nt az adott centroidot ha annak sorsz�ma nagyobb mint az aktu�lisan vizsg�lt)
				while (neighborIDX != -1)
				{
					neighborIDX = changes[neighborIDX].y;
					if (neighborIDX != -1)
						clusterIDX = changes[neighborIDX].x;
				}
				if (changes[clusterIDX].y != -1)
					changes[cluster].y = changes[clusterIDX].y;
				else
					changes[cluster].y = clusterIDX;
			}
		}
	}

	//V�g�l kimentem minden pixel eset�ben, hogy melyik az �j centroid amhez mostant�l tartoznak.
	for (int i = 0; i < cols*rows; i++)
	{
		if (changes[clusters[i]].y != -1)
		{
			clusters[i] = changes[clusters[i]].y;
		}
	}
}

void slicCUDA::initData(Mat image)
{
	cols = image.cols;
	rows = image.rows;
	step = (sqrt((cols * rows) / (double)numberofSuperpixels));

	//felt�lt�s default adatokkal
	clusters = new int[cols*rows];
	distances = new float[cols*rows];
	for (int i = 0; i < cols*rows; i++)
	{
		clusters[i] = -1;
		distances[i] = FLT_MAX;
	}

	centersColPieces = 0;
	centersRowPieces = 0;
	//Ez az�rt kell mert el�re nem tudom, hogy h�ny eleme lesz a centers-nek, ez�rt el�sz�r egy vectorhoz adogatom hozz� az elemeket
	// majd k�s�bb l�trehozom a t�mb�t annyi elemmel, ah�ny eleme van a seg�dvectornak, majd �tm�solom az adatokat.
	vector<vector<float> > h_centers;
	for (int i = step; i < cols - step / 2; i += step) {
		for (int j = step; j < rows - step / 2; j += step) {
			vector<float> center;
			Vec3b colour = image.at<Vec3b>(j, i);

			center.push_back(colour.val[0]);
			center.push_back(colour.val[1]);
			center.push_back(colour.val[2]);
			center.push_back(i);
			center.push_back(j);

			h_centers.push_back(center);
		}
		centersColPieces++;
	}

	centersLength = h_centers.size();
	centersRowPieces = centersLength / centersColPieces;

	centers = new float[centersLength * 5];
	center_counts = new int[centersLength];
	neighbors = new int[centersLength * numberOfNeighbors];
	//A centers �gy t�rolja az adatokat, hogy egy pixelhez let�rolja annak x, �s y poz�ci�j�t a k�pen, valamint
	//az adott pixel R, G �s B sz�nkomponenseit
	//A szomsz�dt�mb eset�ben pedig felt�lt�m a 8 szomsz�dot jelz� �rt�ket default adattal.
	int idx = 0;
	for (int i = 0; i < centersLength; i++)
	{
		for (int j = 0; j < 5; j++)
		{
			centers[idx] = h_centers[i][j];
			idx++;
		}
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			neighbors[i * numberOfNeighbors + j] = -1;
		}
		center_counts[i] = 0;
	}

	//Bej�rom a k�pet, majd minden pixel sz�n�t (3 �rt�k) elmentem egy uchar3 v�ltoz�ba
	colors = new uchar3[rows*cols];
	for (int i = 0; i < cols; i++)
	{
		for (int j = 0; j < rows; j++)
		{
			Vec3b colour = image.at<Vec3b>(j, i);
			colors[i * rows + j] = make_uchar3(colour.val[0], colour.val[1], colour.val[2]);
		}
	}
}


//A kerneleken haszn�land� t�mb�k mem�riafoglal�sa, majd �tm�sol�sa
void slicCUDA::dataCopy()
{
	cudaMalloc((void**)&d_clusters, sizeof(int)*rows*cols);
	cudaMemcpy(d_clusters, clusters, sizeof(int)*rows*cols, cudaMemcpyHostToDevice);
	cudaMalloc((void**)&d_distances, sizeof(float)*rows*cols);
	cudaMemcpy(d_distances, distances, sizeof(float)*rows*cols, cudaMemcpyHostToDevice);
	cudaMalloc((void**)&d_centers, sizeof(float)*centersLength * 5);
	cudaMemcpy(d_centers, centers, sizeof(float)*centersLength * 5, cudaMemcpyHostToDevice);
	cudaMalloc((void**)&d_center_counts, sizeof(int)*centersLength);
	cudaMemcpy(d_center_counts, center_counts, sizeof(int)*centersLength, cudaMemcpyHostToDevice);
	cudaMalloc((void**)&d_colors, sizeof(uchar3)*rows*cols);
	cudaMemcpy(d_colors, colors, sizeof(uchar3)*rows*cols, cudaMemcpyHostToDevice);
}

//A device t�mb�k felszabad�t�sa
void slicCUDA::dataFree()
{
	cudaFree(d_clusters);
	cudaFree(d_distances);
	cudaFree(d_centers);
	cudaFree(d_center_counts);
	cudaFree(d_colors);
}

//A sz�ks�ges adatok visszam�sol�sa kernelr�l, majd a t�mb�k felszabad�t�sa
void slicCUDA::copyBackAndFree()
{
	cudaMemcpy(distances, d_distances, sizeof(float)*rows*cols, cudaMemcpyDeviceToHost);
	cudaMemcpy(clusters, d_clusters, sizeof(int)*rows*cols, cudaMemcpyDeviceToHost);
	cudaMemcpy(centers, d_centers, sizeof(int)*centersLength * 5, cudaMemcpyDeviceToHost);
	cudaMemcpy(center_counts, d_center_counts, sizeof(int)*centersLength, cudaMemcpyDeviceToHost);
	dataFree();
}

//A feldolgoz�s befejezt�vel az eredm�nyeket feldolgozva l�trehozok egy �j k�pet az eredm�nyek alapj�n
void slicCUDA::colour_with_cluster_means(Mat image) {
	for (int i = 0; i < image.cols; i++) {
		for (int j = 0; j < image.rows; j++) {
			//Kor�bban m�r meghat�roztam ,hogy az adott piyxelhez milyen sz�n tartozik, 
			//�gy csak be�ll�tom, hogy az �j k�pen is ez legyen a sz�ne.
			int idx = clusters[i*image.rows + j];
			Vec3b ncolour;

			ncolour.val[0] = centers[idx * 5 + 0];
			ncolour.val[1] = centers[idx * 5 + 1];
			ncolour.val[2] = centers[idx * 5 + 2];

			image.at<Vec3b>(j, i) = ncolour;
		}
	}
}

//El�sz�r kisz�molom, hogy h�ny blokkra lesz sz�ks�gem, majd elind�tom a megfelel� kerneleket
void slicCUDA::startKernels()
{
	int howManyBlocksInClusterProcess = centersLength / maxThreadinoneBlock;
	int threadsPerBlockInClusterProcess = (centersLength / howManyBlocksInClusterProcess) + 1;

	int howManyBlocksInPixelProcess = rows*cols / maxThreadinoneBlock;
	int threadsPerBlockInPixelProcess = (rows*cols / howManyBlocksInPixelProcess) + 1;

	for (int i = 0; i < iterations; i++)
	{
		dataCopy();
		orderingPixelsForClustersKernel << <howManyBlocksInClusterProcess, threadsPerBlockInClusterProcess >> >
			(cols, rows, step, centersLength, d_clusters, d_distances, d_centers, d_center_counts, d_colors, 5);
		clusterValuesSumByPixelsKernel << <howManyBlocksInPixelProcess, threadsPerBlockInPixelProcess >> >
			(cols, rows, d_clusters, d_distances, d_centers, d_center_counts, d_colors, 5);
		computeCorrectCentroidValuesKernel << <howManyBlocksInClusterProcess, threadsPerBlockInClusterProcess >> >
			(centersLength, d_centers, d_center_counts, 5);

		copyBackAndFree();
	}
}

//Itt ker�l tesztel�sre az, hogy a superpixelek j�l szegment�lt�k-e ki a k�pet.
//Ehhez az egyes szegmenseket nem az �tlagsz�nnel t�lt�m fel, hanem random sz�nekkel,
//annak �rdek�ben, hogy ez�ltal a szomsz�dos szegmensek j�l elk�l�n�lnek majd egym�st�l.
void slicCUDA::testSuperpixel(Mat image)
{
	for (int i = 0; i < centersLength; i++)
	{
		centers[i * 5 + 0] = rand() % 255 + 0;
		centers[i * 5 + 1] = rand() % 255 + 0;
		centers[i * 5 + 2] = rand() % 255 + 0;
	}

	for (int i = 0; i < image.cols; i++) {
		for (int j = 0; j < image.rows; j++) {
			int idx = clusters[i*image.rows + j];
			Vec3b ncolour;

			ncolour.val[0] = centers[idx * 5 + 0];
			ncolour.val[1] = centers[idx * 5 + 1];
			ncolour.val[2] = centers[idx * 5 + 2];

			image.at<Vec3b>(j, i) = ncolour;
		}
	}
	imwrite("testWithRandomColour.jpg", image);
}

//Itt ker�lnek ki�rat�sra a tesztel�s sor�n sz�ks�ges adatok a consolera
void slicCUDA::testDataToConsole()
{
	int howManyBlocksInClusterProcess = centersLength / maxThreadinoneBlock;
	int threadsPerBlockInClusterProcess = (centersLength / howManyBlocksInClusterProcess) + 1;

	int howManyBlocksInPixelProcess = rows*cols / maxThreadinoneBlock;
	int threadsPerBlockInPixelProcess = (rows*cols / howManyBlocksInPixelProcess) + 1;

	int notInCentroid = 0;
	for (int i = 0; i < rows*cols; i++)
	{
		if (clusters[i] == -1)
		{
			notInCentroid++;
		}
	}
	int inCentroid = rows*cols - notInCentroid;

	printf("%i a kep sorainak a szama\n", rows);
	printf("%i a kep oszlopainak a szama\n", cols);
	printf("%i darab pixelbol all �sszesen a kep\n", rows*cols);
	printf("%i tavolsagra kerultek elhelyezesre egymastol a centroidok\n\n", step);

	printf("%i darab centroidra van szukseg a feldoglozassoran\n", centersLength);
	printf("%i darab elinditott szal a clentroidok mopzgatasahoz.\n\n", threadsPerBlockInClusterProcess*howManyBlocksInClusterProcess);

	printf("%i darab elinditott szal a pixelek feldolgozasahoz.\n", howManyBlocksInPixelProcess*threadsPerBlockInPixelProcess);
	printf("%i darab pixel centroidhoz van renderve\n", inCentroid);
	printf("%i darab pixel nincs centroidhoz renderve\n", notInCentroid);

	getchar();
}
