#include "slicCUDA.h"

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

	slicCUDA slicGPU;
	slicGPU.initData(image);
	slicGPU.startKernels();
	slicGPU.neighborMerge();
	slicGPU.colour_with_cluster_means(image);
	imwrite(writePath, image);
}