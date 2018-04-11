#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <opencv2\opencv.hpp>

using namespace std;
using namespace cv;

#define nc 80 //maximum vizsg�lt t�vols�g a centroidok keres�sekor
#define numberofSuperpixels 4500
#define iteration 10


int cols;
int rows;
int step;
int centersLength;
int *clusters;
float *distances;
float *centers;
int *center_counts;
uchar3 *colors;

__device__ int *d_clusters;			//1D --> cols * rows
__device__ float *d_distances;		//1D --> cols * rows
__device__ float *d_centers;		//1D --> centersLength * 5
__device__ int *d_center_counts;	//1D --> centersLength
__device__ uchar3 *d_colors;		//1D --> cols * rows

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

__global__ void compute1(int d_cols, int d_rows, int d_step, int d_centersLength, int *d_clusters, float *d_distances,
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

__global__ void compute2(int d_cols, int d_rows, int d_step, int d_centersLength, int *d_clusters, float *d_distances,
	float *d_centers, int *d_center_counts, uchar3 *d_colors, int pitch)
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


void initData(Mat image)
{
	clusters = new int[cols*rows];
	distances = new float[cols*rows];
	for (int i = 0; i < cols*rows; i++)
	{
		clusters[i] = -1;
		distances[i] = FLT_MAX;
	}

	//Ez az�rt kell mert el�re nem tudom, hogy h�ny eleme lesz a centers-nek, ez�rt el�sz�r egy vectorhoz adomgatom hozz� az elemeket
	// majd k�s�bb l�trehozom a t�mb�t annyi elemmel, ah�ny eleme van a seg�dvectornak, majd �tm�solom az adatokat.
	vector<vector<float> > h_centers;
	for (int i = step; i < cols - step / 2; i += step) {
		for (int j = step; j < rows - step / 2; j += step) {
			vector<float> center;
			/* Find the local minimum (gradient-wise). */
			//Point nc = find_local_minimum(image, Point(i, j));
			Vec3b colour = image.at<Vec3b>(j, i);//nc.y, nc.x);

			center.push_back(colour.val[0]);
			center.push_back(colour.val[1]);
			center.push_back(colour.val[2]);
			center.push_back(i);//nc.x);
			center.push_back(j);//nc.y);

			h_centers.push_back(center);
		}
	}

	centersLength = h_centers.size();

	centers = new float[centersLength * 5];
	center_counts = new int[centersLength];
	int idx = 0;
	for (int i = 0; i < centersLength; i++)
	{
		for (int j = 0; j < 5; j++)
		{
			centers[idx] = h_centers[i][j];
			idx++;
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

void dataCopy()
{
	cudaMalloc((void**)&d_clusters, sizeof(int)*rows*cols);
	cudaMemcpy(d_clusters, clusters, sizeof(int)*rows*cols, cudaMemcpyHostToDevice);
	cudaMalloc((void**)&d_distances, sizeof(float)*rows*cols);
	cudaMemcpy(d_distances, distances, sizeof(float)*rows*cols, cudaMemcpyHostToDevice);

	//size_t pitch = 5;
	//cudaMallocPitch((void**)&d_centers, &pitch, sizeof(float) * centersLength, 5);
	//cudaMemcpy2D(d_centers, pitch, centers, sizeof(float) * centersLength, sizeof(float) * centersLength, 5, cudaMemcpyHostToDevice);

	cudaMalloc((void**)&d_centers, sizeof(float)*centersLength * 5);
	cudaMemcpy(d_centers, centers, sizeof(float)*centersLength * 5, cudaMemcpyHostToDevice);


	cudaMalloc((void**)&d_center_counts, sizeof(int)*centersLength);
	cudaMemcpy(d_center_counts, center_counts, sizeof(int)*centersLength, cudaMemcpyHostToDevice);
	cudaMalloc((void**)&d_colors, sizeof(uchar3)*rows*cols);
	cudaMemcpy(d_colors, colors, sizeof(uchar3)*rows*cols, cudaMemcpyHostToDevice);
}

void dataFree()
{
	cudaFree(d_clusters);
	cudaFree(d_distances);
	cudaFree(d_centers);
	cudaFree(d_center_counts);
	cudaFree(d_colors);
}

void colour_with_cluster_means(Mat image) {
	cout << "FILL" << endl;//----------------------------------------------------------------------

	vector<vector<int>> t_colours(centersLength);
	for (int i = 0; i < t_colours.size(); i++)
	{
		t_colours[i].push_back(0);
		t_colours[i].push_back(0);
		t_colours[i].push_back(0);
	}

	/* Gather the colour values per cluster. */
	for (int i = 0; i < image.cols; i++) {
		for (int j = 0; j < image.rows; j++) {
			int index = clusters[i*image.rows + j];
			Vec3b colour = image.at<Vec3b>(j, i);

			t_colours[index][0] += colour.val[0];
			t_colours[index][1] += colour.val[1];
			t_colours[index][2] += colour.val[2];
		}
	}

	/* Divide by the number of pixels per cluster to get the mean colour. */
	for (int i = 0; i < (int)t_colours.size(); i++) {
		if (center_counts[i] != 0)
		{
			t_colours[i][0] /= center_counts[i];
			t_colours[i][1] /= center_counts[i];
			t_colours[i][2] /= center_counts[i];
		}
	}

	/* Fill in. */
	for (int i = 0; i < image.cols; i++) {
		for (int j = 0; j < image.rows; j++) {
			int idx = clusters[i*image.rows + j];
			Vec3b ncolour = image.at<Vec3b>(j, i);

			ncolour.val[0] = t_colours[idx][0];
			ncolour.val[1] = t_colours[idx][1];
			ncolour.val[2] = t_colours[idx][2];

			image.at<Vec3b>(j, i) = ncolour;
		}
	}
}

void display_contours(Mat image, Vec3b colour) {
	cout << "Display contours" << endl;

	const int dx8[8] = { -1, -1,  0,  1, 1, 1, 0, -1 };
	const int dy8[8] = { 0, -1, -1, -1, 0, 1, 1,  1 };

	/* Initialize the contour vector and the matrix detailing whether a pixel
	* is already taken to be a contour. */
	vector<Point> contours;
	vector<vector<bool> > istaken;
	for (int i = 0; i < image.cols; i++) {
		vector<bool> nb;
		for (int j = 0; j < image.rows; j++) {
			nb.push_back(false);
		}
		istaken.push_back(nb);
	}

	/* Go through all the pixels. */
	for (int i = 0; i < image.cols; i++) {
		for (int j = 0; j < image.rows; j++) {
			int nr_p = 0;

			/* Compare the pixel to its 8 neighbours. */
			for (int k = 0; k < 8; k++) {
				int x = i + dx8[k], y = j + dy8[k];

				if (x >= 0 && x < image.cols && y >= 0 && y < image.rows) {
					if (istaken[x][y] == false && clusters[i*image.rows + j] != clusters[x*image.rows + y]) {
						nr_p += 1;
					}
				}
			}

			/* Add the pixel to the contour list if desired. */
			if (nr_p >= 2) {
				contours.push_back(Point(i, j));
				istaken[i][j] = true;
			}
		}
	}

	/* Draw the contour pixels. */
	for (int i = 0; i < (int)contours.size(); i++) {
		image.at<Vec3b>(contours[i].y, contours[i].x) = colour;
	}
}

int main(int ArgsC, char* Args[])
{
	string readPath;
	string writePath;
	if (ArgsC < 2)
	{
		readPath = "C:\\Users\\Adam\\Desktop\\samples\\completed.jpg";
		writePath = "C:\\Users\\Adam\\Desktop\\xmen.jpg";
	}
	else
	{
		readPath = Args[1];
		writePath = Args[2];
	}
	Mat image = imread(readPath, 1);
	cols = image.cols;
	rows = image.rows;

	step = (sqrt((cols * rows) / (double)numberofSuperpixels));

	initData(image);
	//dataCopy();

	int howManyBlocks = centersLength / 700;
	int threadsPerBlock = (centersLength / howManyBlocks) + 1;

	int threadsToBeStarted2 = rows*cols;
	int howManyBlocks2 = threadsToBeStarted2 / 700;
	int threadsPerBlock2 = (threadsToBeStarted2 / howManyBlocks2) + 1;

	for (int i = 0; i < 10; i++)
	{
		dataCopy();
		compute << <howManyBlocks, threadsPerBlock >> > (cols, rows, step, centersLength, d_clusters, d_distances, d_centers, d_center_counts, d_colors, 5);
		compute1 << <howManyBlocks2, threadsPerBlock2 >> > (cols, rows, step, centersLength, d_clusters, d_distances, d_centers, d_center_counts, d_colors, 5);
		compute2 << <howManyBlocks, threadsPerBlock >> > (cols, rows, step, centersLength, d_clusters, d_distances, d_centers, d_center_counts, d_colors, 5);

		cudaMemcpy(distances, d_distances, sizeof(float)*rows*cols, cudaMemcpyDeviceToHost);
		cudaMemcpy(clusters, d_clusters, sizeof(int)*rows*cols, cudaMemcpyDeviceToHost);
		cudaMemcpy(centers, d_centers, sizeof(int)*centersLength * 5, cudaMemcpyDeviceToHost);
		cudaMemcpy(center_counts, d_center_counts, sizeof(int)*centersLength, cudaMemcpyDeviceToHost);

		dataFree();
	}

	//cudaMemcpy(distances, d_distances, sizeof(float)*rows*cols, cudaMemcpyDeviceToHost);
	//cudaMemcpy(clusters, d_clusters, sizeof(int)*rows*cols, cudaMemcpyDeviceToHost);
	//cudaMemcpy(centers, d_centers, sizeof(int)*centersLength * 5, cudaMemcpyDeviceToHost);
	//cudaMemcpy(center_counts, d_center_counts, sizeof(int)*centersLength, cudaMemcpyDeviceToHost);
	//dataFree();

	int a = 0;
	for (int i = 0; i < rows*cols; i++) { if (clusters[i] == -1) { a++; } }
	int b = rows*cols - a;

	printf("%i elinditott szal\n", threadsPerBlock2*howManyBlocks2);
	printf("%i steps\n", step);
	printf("%i rows\n", rows);
	printf("%i cols\n", cols);
	printf("%i darab cluster\n", centersLength);
	printf("%i darab pixel\n", rows*cols);
	printf("%i darab elinditott szal\n", threadsPerBlock*howManyBlocks);
	printf("%i darab clusterhez van renderve\n", b);
	printf("%i darab nincs clusterhez renderve\n", a);

	int dis = 0;
	for (int i = 0; i < rows*cols; i++) { if (distances[i] == FLT_MAX) { dis++; } }
	printf("%i dis\n", dis);


	int mennyi = 0;
	for (int i = 0; i < centersLength; i++) { mennyi += center_counts[i]; }
	printf("%i darab pixel\n", rows*cols);
	printf("%i mennyi\n", mennyi);

	//Mat cont = image.clone();
	//display_contours(cont, Vec3b(0, 0, 255));
	//imwrite("C:\\Users\\Adam\\Desktop\\000Cont.jpg", cont);

	Mat cwtm = image.clone();
	colour_with_cluster_means(cwtm);
	imwrite(writePath, cwtm);

	//getchar();
	//for (int i = 0; i < rows*cols; i++)
	//{
	//	cout << distances[i] << endl;
	//}

	//getchar();
	//int c = 0;
	//for (int i = 0; i < centersLength; i += 5)
	//{
	//	cout << centers[i] << " " << centers[i + 1] << " " << centers[i + 2] << " " << centers[i + 3] << " " << centers[i + 4] << "  -->  " << endl;
	//	//seged[i] << " " << seged[i + 1] << " " << seged[i + 2] << " " << seged[i + 3] << " " << seged[i + 4] << " --> " << center_counts[c++] << endl;
	//}



	printf("\nvege");

	///* Load the image and convert to Lab colour space. */
	//Mat image = imread("C:\\Users\\Adam\\Desktop\\samples\\completed.jpg", 1);
	//Mat lab_image = image.clone();
	//cvtColor(image, lab_image, CV_BGR2Lab);

	///* Yield the number of superpixels and weight-factors from the user. */
	//int w = image.cols;
	//int h = image.rows;
	//int nr_superpixels = 5000;
	//int nc = 80;

	//double step = (sqrt((w * h) / (double)nr_superpixels));
	////1400*900-as k�pn�l, 1000 superpixellel --> 35,496 --> v�zszintesen 39,444, f�gg�legesen 25,354

	///* Perform the SLIC superpixel algorithm. */
	//Slic slic;
	//slic.generate_superpixels(lab_image, step, nc);
	//slic.create_connectivity(lab_image);

	///* Display the contours and show the result. */
	//Mat tt = image.clone();
	//slic.display_contours(tt, Vec3b(0, 0, 255));
	//imwrite("C:\\Users\\Adam\\Desktop\\0MATsamplewitchLines.jpg", tt);

	////----------------------
	//slic.colour_with_cluster_means(image);
	//imwrite("C:\\Users\\Adam\\Desktop\\1MATsamplefilled.jpg", image);
	////----------------------

	//getchar();
}