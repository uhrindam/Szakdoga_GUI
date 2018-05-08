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
	//színtávolság
	float dc = sqrt(pow(d_centers[ci *pitch + 0] - colour.x, 2) + pow(d_centers[ci *pitch + 1] - colour.y, 2)
		+ pow(d_centers[ci *pitch + 2] - colour.z, 2));
	//euklideszi távolság
	float ds = sqrt(pow(d_centers[ci *pitch + 3] - x, 2) + pow(d_centers[ci *pitch + 4] - y, 2));

	return sqrt(pow(dc / nc, 2) + pow(ds / d_step, 2));
}

//lépésszám: centroidok száma
//Itt rendelem a pixeleket az egyes clusterekhez szín, valamint euklideszi távolság szerint
__global__ void orderingPixelsForClustersKernel(int d_cols, int d_rows, int d_step, int d_centersLength,
	int *d_clusters, float *d_distances, float *d_centers, int *d_center_counts, uchar3 *d_colors, int pitch)
{
	int clusterIDX = blockIdx.x * blockDim.x + threadIdx.x;
	//mivel nem tudok pontosan annyi szálat indítani ahány clusterem van, 
	//ezért megvizsgálom, hogy az adott clusterindex még létezik-e
	if (clusterIDX < d_centersLength)
	{
		//Bejárom az adott cluster "step" sugarú környezetét
		//Az itt található pixelek mindegyikére megnézem, hogy az aktuálisan vizsgált
		//centroid van-e hozzá a legközelebb, és ha igen, akkor beállítom a megfelelõ adatokat
		//Ez a két egybeágyazott forciklus miatt hosszúnak tûnik, de alapvetõen ez kevés lépésbõl áll
		for (int pixelY = d_centers[clusterIDX *pitch + 3] - (d_step*1.5); pixelY <
			d_centers[clusterIDX *pitch + 3] + (d_step*1.5); pixelY++)
		{
			for (int pixelX = d_centers[clusterIDX *pitch + 4] - (d_step*1.5); pixelX <
				d_centers[clusterIDX *pitch + 4] + (d_step*1.5); pixelX++)
			{
				//Ellenõrzöm a határokat
				if (pixelX >= 0 && pixelX < d_rows && pixelY >= 0 && pixelY < d_cols)
				{
					uchar3 colour = d_colors[d_rows*pixelY + pixelX];
					float distance = compute_dist(clusterIDX, pixelX, pixelY, colour, d_centers, pitch, d_step);
					//ha a távolság kisebb mint az eddig mentett (a default az FLT_MAX) akkor beállítom 
					//az aktuális centroidot a legközelebbinek
					if (distance < d_distances[d_rows*pixelY + pixelX])
					{
						d_distances[d_rows*pixelY + pixelX] = distance;
						d_clusters[d_rows*pixelY + pixelX] = clusterIDX;
					}
				}
			}
		}

		//a centroidok alaphelyzetbe állítása
		d_centers[clusterIDX *pitch + 0] = 0;
		d_centers[clusterIDX *pitch + 1] = 0;
		d_centers[clusterIDX *pitch + 2] = 0;
		d_centers[clusterIDX *pitch + 3] = 0;
		d_centers[clusterIDX *pitch + 4] = 0;
		d_center_counts[clusterIDX] = 0;
	}

}

//lépésszám: pixelek száma
//Itt összegzem a korábban kapott eredményeket.
__global__ void clusterValuesSumByPixelsKernel(int d_cols, int d_rows, int *d_clusters, float *d_distances,
	float *d_centers, int *d_center_counts, uchar3 *d_colors, int pitch)
{
	int idIn1D = blockIdx.x * blockDim.x + threadIdx.x;
	if (idIn1D < d_cols*d_rows)
	{
		//Alaphelyzetbe állítom a távolságértékeket minden piyel esetében
		d_distances[idIn1D] = FLT_MAX;

		//Megkeresem, hogy az adott pixel melyik centroidhoz tartozik.
		//amint ez megvan, összegzem ezeket az értékeket, atomi mûvelettel, ugyanis
		//elõfordulhat hogy egy centroidhoz tartozó tömbértéket egyszerre több pixelszál is szeretne írni
		//majd növelem a centroidhoz tartozó pixelek számát
		int whichCluster = d_clusters[idIn1D];
		atomicAdd(&d_centers[whichCluster*pitch + 0], d_colors[idIn1D].x);
		atomicAdd(&d_centers[whichCluster*pitch + 1], d_colors[idIn1D].y);
		atomicAdd(&d_centers[whichCluster*pitch + 2], d_colors[idIn1D].z);
		atomicAdd(&d_centers[whichCluster*pitch + 3], idIn1D / d_rows);
		atomicAdd(&d_centers[whichCluster*pitch + 4], idIn1D % d_rows);

		atomicAdd(&d_center_counts[whichCluster], 1);
	}
}

//lépésszám: centroidok száma
//Az összegzett centroidértékeket elosztom a centroidhoz tartozó pixelek darabszámával.
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

//A szomszédok összevonásakor használt színtávolság számító függvény
float slicCUDA::colorDistance(uchar3 actuallPixel, uchar3 neighborPixel)
{
	float dc = sqrt(pow(actuallPixel.x - neighborPixel.x, 2) + pow(actuallPixel.y - neighborPixel.y, 2)
		+ pow(actuallPixel.z - neighborPixel.z, 2));
	return dc;
}

//Itt kerülnek összevonásra a szomszédos hasonló színû szegmensek
void slicCUDA::neighborMerge()
{
	const int dx8[numberOfNeighbors] = { -1, -1,  0,  1, 1, 1, 0, -1 };
	const int dy8[numberOfNeighbors] = { 0, -1, -1, -1, 0, 1, 1,  1 };

	for (int i = 0; i < centersLength; i++)
	{
		//kimentem az aktuális centroid értékeit
		uchar3 actuallCluster;
		actuallCluster.x = centers[i * 5];
		actuallCluster.y = centers[i * 5 + 1];
		actuallCluster.z = centers[i * 5 + 2];

		int clusterRow = i / centersRowPieces;
		int clusterCol = i % centersRowPieces;

		//megnézem az aktuális centroid szomszédjait
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//ellenõrzöm a határokat
			if (clusterCol + dy8[j] >= 0 && clusterCol + dy8[j] < centersRowPieces
				&& clusterRow + dx8[j] >= 0 && clusterRow + dx8[j] < centersColPieces)
			{
				//kimentem a szomszédos centroid adatait
				uchar3 neighborPixel;
				neighborPixel.x = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 0];
				neighborPixel.y = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 1];
				neighborPixel.z = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 2];

				//ha az aktuális centroid sorszáma kisebb mint a szomszéd sorszáma, valamint a színtávolság a megengedett határon
				//belül van, akkor felveszem az összevonandó szömszédok közé.
				if (centersRowPieces * clusterRow + clusterCol < centersRowPieces * (clusterRow + dx8[j]) +
					(clusterCol + dy8[j]) && colorDistance(actuallCluster, neighborPixel) < maxColorDistance)
				{
					neighbors[(centersRowPieces * clusterRow + clusterCol) * numberOfNeighbors + j] =
						centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]);
				}
			}
		}
	}

	//inicializálok egy segédtömböt, amelyben el fogom tárolni hogy az egyes centroidokat melyik másik centroiddal kell összevonni
	int2 *changes = new int2[centersLength];
	for (int i = 0; i < centersLength; i++)
	{
		changes[i].x = i;
		changes[i].y = -1;
	}

	//Az itt következõ kódrésznek az a lényege, hogy az összevonandó centroidokat összeláncolom úgy, hogy az egymáshoz közel lévõ
	//megengedett színtávolságú centroidok össze legyenek vonva, annak elkerülése végett, hogy esetleg egy centroid egy olyan másik
	//centroiddal legyen összevonva, amelyet már összevontam egy másikkal.
	//Például: a kép szélén található egy fehér keret, amelyen 500 centroid helyezkedik el. Ezeket párossával is összevonhatnám, de
	//ehelyett mind az 500-at egy centroiddá alakítom, és egyben kezelem az egészet.
	for (int i = 0; i < centersLength; i++)
	{
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//kimentem, hogy az adott szomszéd az melyik centroid
			int cluster = neighbors[i * numberOfNeighbors + j];
			if (cluster != -1)
			{
				//kimentem, hogy az adott centroidot melyik másikkal kell összevonni
				int neighborIDX = changes[cluster].y;
				int clusterIDX = i;
				//Addig megyek végig az összevonandókon amíg el nem érek egy oylan centroidig, amit már nem kell másikkal összevonni
				//(Garantáltan van olyan centroid a lánc végén amelyet nem kell másikkal összevonni, annak köszönhetõen, hogy 
				//csak akkor mentem el szomszédként az adott centroidot ha annak sorszáma nagyobb mint az aktuálisan vizsgált)
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

	//Végül kimentem minden pixel esetében, hogy melyik az új centroid amhez mostantól tartoznak.
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

	//feltöltés default adatokkal
	clusters = new int[cols*rows];
	distances = new float[cols*rows];
	for (int i = 0; i < cols*rows; i++)
	{
		clusters[i] = -1;
		distances[i] = FLT_MAX;
	}

	centersColPieces = 0;
	centersRowPieces = 0;
	//Ez azért kell mert elõre nem tudom, hogy hány eleme lesz a centers-nek, ezért elõször egy vectorhoz adogatom hozzá az elemeket
	// majd késõbb létrehozom a tömböt annyi elemmel, ahány eleme van a segédvectornak, majd átmásolom az adatokat.
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
	//A centers úgy tárolja az adatokat, hogy egy pixelhez letárolja annak x, és y pozícióját a képen, valamint
	//az adott pixel R, G és B színkomponenseit
	//A szomszédtömb esetében pedig feltöltöm a 8 szomszédot jelzõ értéket default adattal.
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

	//Bejárom a képet, majd minden pixel színét (3 érték) elmentem egy uchar3 változóba
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


//A kerneleken használandó tömbök memóriafoglalása, majd átmásolása
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

//A device tömbök felszabadítása
void slicCUDA::dataFree()
{
	cudaFree(d_clusters);
	cudaFree(d_distances);
	cudaFree(d_centers);
	cudaFree(d_center_counts);
	cudaFree(d_colors);
}

//A szükséges adatok visszamásolása kernelrõl, majd a tömbök felszabadítása
void slicCUDA::copyBackAndFree()
{
	cudaMemcpy(distances, d_distances, sizeof(float)*rows*cols, cudaMemcpyDeviceToHost);
	cudaMemcpy(clusters, d_clusters, sizeof(int)*rows*cols, cudaMemcpyDeviceToHost);
	cudaMemcpy(centers, d_centers, sizeof(int)*centersLength * 5, cudaMemcpyDeviceToHost);
	cudaMemcpy(center_counts, d_center_counts, sizeof(int)*centersLength, cudaMemcpyDeviceToHost);
	dataFree();
}

//A feldolgozás befejeztével az eredményeket feldolgozva létrehozok egy új képet az eredmények alapján
void slicCUDA::colour_with_cluster_means(Mat image) {
	for (int i = 0; i < image.cols; i++) {
		for (int j = 0; j < image.rows; j++) {
			//Korábban már meghatároztam ,hogy az adott piyxelhez milyen szín tartozik, 
			//így csak beállítom, hogy az új képen is ez legyen a színe.
			int idx = clusters[i*image.rows + j];
			Vec3b ncolour;

			ncolour.val[0] = centers[idx * 5 + 0];
			ncolour.val[1] = centers[idx * 5 + 1];
			ncolour.val[2] = centers[idx * 5 + 2];

			image.at<Vec3b>(j, i) = ncolour;
		}
	}
}

//Elõször kiszámolom, hogy hány blokkra lesz szükségem, majd elindítom a megfelelõ kerneleket
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

//Itt kerül tesztelésre az, hogy a superpixelek jól szegmentálták-e ki a képet.
//Ehhez az egyes szegmenseket nem az átlagszínnel töltöm fel, hanem random színekkel,
//annak érdekében, hogy ezáltal a szomszédos szegmensek jól elkülönülnek majd egymástól.
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

//Itt kerülnek kiíratásra a tesztelés során szükséges adatok a consolera
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
	printf("%i darab pixelbol all összesen a kep\n", rows*cols);
	printf("%i tavolsagra kerultek elhelyezesre egymastol a centroidok\n\n", step);

	printf("%i darab centroidra van szukseg a feldoglozassoran\n", centersLength);
	printf("%i darab elinditott szal a clentroidok mopzgatasahoz.\n\n", threadsPerBlockInClusterProcess*howManyBlocksInClusterProcess);

	printf("%i darab elinditott szal a pixelek feldolgozasahoz.\n", howManyBlocksInPixelProcess*threadsPerBlockInPixelProcess);
	printf("%i darab pixel centroidhoz van renderve\n", inCentroid);
	printf("%i darab pixel nincs centroidhoz renderve\n", notInCentroid);

	getchar();
}
