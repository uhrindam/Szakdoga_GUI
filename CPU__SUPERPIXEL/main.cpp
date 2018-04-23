#include "slic.h"

int main(int ArgsC, char* Args[])
{
	string readPath = "completed.jpg";
	string writePath = "xmen.jpg";

	if (ArgsC > 1)
	{
		readPath = Args[1];
		writePath = Args[2];
	}

	Mat image = imread(readPath, 1);

	int step = (sqrt((image.cols * image.rows) / (double)numberofSuperpixels));

	Slic slic;
	slic.generate_superpixels(image, step, 80);

	slic.neighborMerge(image);
	slic.colour_with_cluster_means(image);
	imwrite(writePath, image);
}