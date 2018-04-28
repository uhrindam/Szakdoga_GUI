#include "slicCPU.h"

int main(int ArgsC, char* Args[])
{
	//Tesztelés céljából beállítok egy default képnevet
	string readPath = "completed.jpg";
	string writePath = "xmen.jpg";

	//ha van kapott argumentum akkor azokat használom
	if (ArgsC > 1)
	{
		readPath = Args[1];
		writePath = Args[2];
	}

	Mat image = imread(readPath, 1);
	slicCPU slicCPU;
	slicCPU.generate_superpixels(image);
	slicCPU.neighborMerge(image);
	slicCPU.colour_with_cluster_means(image);
	imwrite(writePath, image);
}