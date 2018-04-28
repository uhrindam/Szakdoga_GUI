#include <opencv2\opencv.hpp>
#include <opencv/highgui.h>
#include <stdio.h>
#include <math.h>
#include <vector>
#include <float.h>
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

class slicCPU {
private:
	int step;

	//egy sorban tal�lhat� pixelek sz�ma
	int centersRowPieces;

	//egy oszlopban tal�lhat� pixelek sz�ma
	int centersColPieces;

	//itt ker�l elt�rol�sra minden pixelhez hogy melyik centroidhoz tartozik
	vector<vector<int> > clusters;

	//az egyes pixelekhez tartoz� t�vol�s a hozz� tartoz� centroidt�l m�rve
	vector<vector<double> > distances;

	//a centroidokat tartalmaz� t�mb (x,y,r,g,b)
	vector<vector<double> > centers;

	//az adott centroidhoz tartoz� pixelek sz�ma
	vector<int> center_counts;

	//Az egyes centroidok szomsz�dos centroidjai
	int *neighbors;

	double compute_dist(int ci, Point pixel, Vec3b colour);
	void clear_data();
	void init_data(Mat image);

public:
	slicCPU();
	~slicCPU();
	void generate_superpixels(Mat image);
	void colour_with_cluster_means(Mat image);
	float colorDistance(Vec3b actuallPixel, Vec3b neighborPixel);
	void neighborMerge(Mat image);
};