#include <opencv2\opencv.hpp>
#include <opencv/highgui.h>
#include <stdio.h>
#include <math.h>
#include <vector>
#include <float.h>
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

class slicCPU {
private:
	int step;

	//egy sorban található pixelek száma
	int centersRowPieces;

	//egy oszlopban található pixelek száma
	int centersColPieces;

	//itt kerül eltárolásra minden pixelhez hogy melyik centroidhoz tartozik
	vector<vector<int> > clusters;

	//az egyes pixelekhez tartozó távolás a hozzá tartozó centroidtól mérve
	vector<vector<double> > distances;

	//a centroidokat tartalmazó tömb (x,y,r,g,b)
	vector<vector<double> > centers;

	//az adott centroidhoz tartozó pixelek száma
	vector<int> center_counts;

	//Az egyes centroidok szomszédos centroidjai
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