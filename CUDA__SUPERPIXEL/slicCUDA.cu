#include "slicCUDA.h"

__device__ int *d_clusters;								//cols * rows
__device__ float *d_distances;							//cols * rows
__device__ float *d_centers;							//centersLength * 5
__device__ int *d_center_counts;						//centersLength
__device__ uchar3 *d_colors;							//cols * rows
__device__ int *d_neighbors;							//centerlength * 8

slicCUDA::slicCUDA(){}

slicCUDA::~slicCUDA(){}

__device__ float compute_dist(int ci, int y, int x, uchar3 colour, float *d_centers, int pitch, int d_step)
{
	//sz�nt�vols�g
	float dc = sqrt(pow(d_centers[ci *pitch + 0] - colour.x, 2) + pow(d_centers[ci *pitch + 1] - colour.y, 2)
		+ pow(d_centers[ci *pitch + 2] - colour.z, 2));
	//euklideszi t�vols�g
	float ds = sqrt(pow(d_centers[ci *pitch + 3] - x, 2) + pow(d_centers[ci *pitch + 4] - y, 2));

	return sqrt(pow(dc / nc, 2) + pow(ds / d_step, 2));
}

__global__ void compute(int d_cols, int d_rows, int d_step, int d_centersLength, int *d_clusters, float *d_distances,
	float *d_centers, int *d_center_counts, uchar3 *d_colors, int pitch)
{
	int clusterIDX = blockIdx.x * blockDim.x + threadIdx.x;

	if (clusterIDX < d_centersLength)
	{
		for (int pixelY = d_centers[clusterIDX *pitch + 3] - (d_step*1.5); pixelY < d_centers[clusterIDX *pitch + 3] + (d_step*1.5); pixelY++)
		{
			for (int pixelX = d_centers[clusterIDX *pitch + 4] - (d_step*1.5); pixelX < d_centers[clusterIDX *pitch + 4] + (d_step*1.5); pixelX++)
			{
				if (pixelX >= 0 && pixelX < d_rows && pixelY >= 0 && pixelY < d_cols)
				{
					uchar3 colour = d_colors[d_rows*pixelY + pixelX];
					float distance = compute_dist(clusterIDX, pixelX, pixelY, colour, d_centers, pitch, d_step);
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

__global__ void compute1(int d_cols, int d_rows, int *d_clusters, float *d_distances,
	float *d_centers, int *d_center_counts, uchar3 *d_colors, int pitch)
{
	int idIn1D = blockIdx.x * blockDim.x + threadIdx.x;
	if (idIn1D < d_cols*d_rows)
	{
		d_distances[idIn1D] = FLT_MAX;

		int whichCluster = d_clusters[idIn1D];
		atomicAdd(&d_centers[whichCluster*pitch + 0], d_colors[idIn1D].x);
		atomicAdd(&d_centers[whichCluster*pitch + 1], d_colors[idIn1D].y);
		atomicAdd(&d_centers[whichCluster*pitch + 2], d_colors[idIn1D].z);
		atomicAdd(&d_centers[whichCluster*pitch + 3], idIn1D / d_rows);
		atomicAdd(&d_centers[whichCluster*pitch + 4], idIn1D % d_rows);

		atomicAdd(&d_center_counts[whichCluster], 1);
	}
}

__global__ void compute2(int d_centersLength, float *d_centers, int *d_center_counts, int pitch)
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

float slicCUDA::colorDistance(uchar3 actuallPixel, uchar3 neighborPixel)
{
	float dc = sqrt(pow(actuallPixel.x - neighborPixel.x, 2) + pow(actuallPixel.y - neighborPixel.y, 2)
		+ pow(actuallPixel.z - neighborPixel.z, 2));
	return dc;
}

void slicCUDA::neighborMerge()
{
	const int dx8[numberOfNeighbors] = { -1, -1,  0,  1, 1, 1, 0, -1 };
	const int dy8[numberOfNeighbors] = { 0, -1, -1, -1, 0, 1, 1,  1 };

	for (int i = 0; i < centersLength; i++)
	{
		uchar3 actuallCluster;
		actuallCluster.x = centers[i * 5];
		actuallCluster.y = centers[i * 5 + 1];
		actuallCluster.z = centers[i * 5 + 2];

		int clusterRow = i / centersRowPieces;
		int clusterCol = i % centersRowPieces;

		for (int j = 0; j < numberOfNeighbors; j++)
		{
			if (clusterCol + dy8[j] >= 0 && clusterCol + dy8[j] < centersRowPieces
				&& clusterRow + dx8[j] >= 0 && clusterRow + dx8[j] < centersColPieces)
			{
				uchar3 neighborPixel;
				neighborPixel.x = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 0];
				neighborPixel.y = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 1];
				neighborPixel.z = centers[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 2];

				if (centersRowPieces * clusterRow + clusterCol < centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]) &&
					colorDistance(actuallCluster, neighborPixel) < maxColorDistance)
				{
					neighbors[(centersRowPieces * clusterRow + clusterCol) * numberOfNeighbors + j] = centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]);
				}
			}
		}
	}

	int2 *changes = new int2[centersLength];
	for (int i = 0; i < centersLength; i++)
	{
		changes[i].x = i;
		changes[i].y = -1;
	}

	for (int i = 0; i < centersLength; i++)
	{
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			int cluster = neighbors[i * numberOfNeighbors + j];
			if (cluster != -1)
			{
				int neighborIDX = changes[cluster].y;
				int clusterIDX = i;
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

	clusters = new int[cols*rows];
	distances = new float[cols*rows];
	for (int i = 0; i < cols*rows; i++)
	{
		clusters[i] = -1;
		distances[i] = FLT_MAX;
	}

	//Ez az�rt kell mert el�re nem tudom, hogy h�ny eleme lesz a centers-nek, ez�rt el�sz�r egy vectorhoz adogatom hozz� az elemeket
	// majd k�s�bb l�trehozom a t�mb�t annyi elemmel, ah�ny eleme van a seg�dvectornak, majd �tm�solom az adatokat.
	centersColPieces = 0;
	centersRowPieces = 0;
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

void slicCUDA::dataFree()
{
	cudaFree(d_clusters);
	cudaFree(d_distances);
	cudaFree(d_centers);
	cudaFree(d_center_counts);
	cudaFree(d_colors);
}

void slicCUDA::colour_with_cluster_means(Mat image) {
	cout << "FILL" << endl;

	for (int i = 0; i < image.cols; i++) {
		for (int j = 0; j < image.rows; j++) {
			int idx = clusters[i*image.rows + j];
			Vec3b ncolour = image.at<Vec3b>(j, i);

			ncolour.val[0] = centers[idx * 5 + 0];
			ncolour.val[1] = centers[idx * 5 + 1];
			ncolour.val[2] = centers[idx * 5 + 2];

			image.at<Vec3b>(j, i) = ncolour;
		}
	}
}

void slicCUDA::startKernels()
{
	int howManyBlocks = centersLength / maxThreadinoneBlock;
	int threadsPerBlock = (centersLength / howManyBlocks) + 1;

	int howManyBlocks2 = rows*cols / maxThreadinoneBlock;
	int threadsPerBlock2 = (rows*cols / howManyBlocks2) + 1;
	for (int i = 0; i < iteration; i++)
	{
		dataCopy();
		compute << <howManyBlocks, threadsPerBlock >> > (cols, rows, step, centersLength, d_clusters, d_distances, d_centers, d_center_counts, d_colors, 5);
		compute1 << <howManyBlocks2, threadsPerBlock2 >> > (cols, rows, d_clusters, d_distances, d_centers, d_center_counts, d_colors, 5);
		compute2 << <howManyBlocks, threadsPerBlock >> > (centersLength, d_centers, d_center_counts, 5);

		cudaMemcpy(distances, d_distances, sizeof(float)*rows*cols, cudaMemcpyDeviceToHost);
		cudaMemcpy(clusters, d_clusters, sizeof(int)*rows*cols, cudaMemcpyDeviceToHost);
		cudaMemcpy(centers, d_centers, sizeof(int)*centersLength * 5, cudaMemcpyDeviceToHost);
		cudaMemcpy(center_counts, d_center_counts, sizeof(int)*centersLength, cudaMemcpyDeviceToHost);

		dataFree();
	}
}