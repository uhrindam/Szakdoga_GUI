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

//a szomsz�dok �sszevon�sakor a maxim�lisan megengedett sz�nt�vols�g
#define maxColorDistance 40

//maximum vizsg�lt t�vols�g a centroidok keres�sekor
#define nc 80 

//a program fut�sa k�zben haszn�lt szuperpixelek sz�ma
#define numberofSuperpixels 4500

//A szegmens finom�t�s iter�ci�inak a sz�ma
#define iterations 10

//egy centroid szomsz�djainak a sz�ma
#define numberOfNeighbors 8

//Egy blokkon bel�l ind�tand� blokkok sz�ma
#define maxThreadinoneBlock 700

class slicCUDA
{
private:
	int cols;
	int rows;
	int step;
	
	//A cetroidok sz�ma
	int centersLength;
	
	//egy sorban tal�lhat� pixelek sz�ma
	int centersRowPieces;

	//egy oszlopban tal�lhat� pixelek sz�ma
	int centersColPieces;

	//itt ker�l elt�rol�sra minden pixelhez hogy melyik centroidhoz tartozik
	int *clusters;

	//az egyes pixelekhez tartoz� t�vol�s a hozz� tartoz� centroidt�l m�rve
	float *distances;

	//a centroidokat tartalmaz� t�mb (x,y,r,g,b)
	float *centers;

	//az adott centroidhoz tartoz� pixelek sz�ma
	int *center_counts;

	//az egyes pixelekhez tartoz� sz�nek
	uchar3 *colors;

	//Az egyes centroidok szomsz�dos centroidjai
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