#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <opencv2\opencv.hpp>
#include <opencv/highgui.h>
#include <stdio.h>
#include <math.h>
#include <vector>
#include <float.h>
using namespace std;
using namespace cv;

#define maxColorDistance 39
#define nc 80 //maximum vizsgált távolság a centroidok keresésekor
#define numberofSuperpixels 4500
#define iteration 10
#define numberOfNeighbors 8
#define maxThreadinoneBlock 700

class slicCUDA
{
private:
	int cols;
	int rows;
	int step;
	int centersLength;
	int centersRowPieces;
	int centersColPieces;
	int *clusters;
	float *distances;
	float *centers;
	int *center_counts;
	uchar3 *colors;
	int *neighbors;



public:
	slicCUDA();
	~slicCUDA();
	float colorDistance(uchar3 actuallPixel, uchar3 neighborPixel);
	void neighborMerge();
	void initData(Mat image);
	void dataCopy();
	void dataFree();
	void colour_with_cluster_means(Mat image);
	void startKernels();
};