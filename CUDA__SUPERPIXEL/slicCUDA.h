#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <opencv2\opencv.hpp>
#include <opencv/highgui.h>
#include <stdio.h>
#include <math.h>
#include <vector>
#include <float.h>
#include <random>
using namespace std;
using namespace cv;

//a szomszédok összevonásakor a maximálisan megengedett színtávolság
#define maxColorDistance 40

//maximum vizsgált távolság a centroidok keresésekor
#define nc 80 

//a program futása közben használt szuperpixelek száma
#define numberofSuperpixels 4500

//A szegmens finomítás iterációinak a száma
#define iterations 10

//egy centroid szomszédjainak a száma
#define numberOfNeighbors 8

//Egy blokkon belül indítandó blokkok száma
#define maxThreadinoneBlock 700

class slicCUDA
{
private:
	int cols;
	int rows;
	int step;
	
	//A cetroidok száma
	int centersLength;
	
	//egy sorban található pixelek száma
	int centersRowPieces;

	//egy oszlopban található pixelek száma
	int centersColPieces;

	//itt kerül eltárolásra minden pixelhez hogy melyik centroidhoz tartozik
	int *clusters;

	//az egyes pixelekhez tartozó távolás a hozzá tartozó centroidtól mérve
	float *distances;

	//a centroidokat tartalmazó tömb (x,y,r,g,b)
	float *centers;

	//az adott centroidhoz tartozó pixelek száma
	int *center_counts;

	//az egyes pixelekhez tartozó színek
	uchar3 *colors;

	//Az egyes centroidok szomszédos centroidjai
	int *neighbors;

	void dataCopy();
	void dataFree();
	void copyBackAndFree();

public:
	slicCUDA();
	~slicCUDA();
	float colorDistance(uchar3 actuallPixel, uchar3 neighborPixel);
	void neighborMerge();
	void initData(Mat image);
	void colour_with_cluster_means(Mat image);
	void startKernels();
	void testSuperpixel(Mat image);
	void testDataToConsole();
};