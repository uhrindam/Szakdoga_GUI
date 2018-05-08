#include "slicCPU.h"

slicCPU::slicCPU() {}

slicCPU::~slicCPU() {
	clear_data();
}

//A  vectorok tartalmának törlése
void slicCPU::clear_data() {
	clusters.clear();
	distances.clear();
	centers.clear();
	center_counts.clear();
}

void slicCPU::init_data(Mat image) {
	step = (sqrt((image.cols * image.rows) / (double)numberofSuperpixels));

	//feltöltés default adatokkal
	for (int i = 0; i < image.cols; i++) {
		vector<int> cr;
		vector<double> dr;
		for (int j = 0; j < image.rows; j++) {
			cr.push_back(-1);
			dr.push_back(FLT_MAX);
		}
		clusters.push_back(cr);
		distances.push_back(dr);
	}

	centersColPieces = 0;
	centersRowPieces = 0;
	//A centroidok inicializálása
	for (int i = step; i < image.cols - step / 2; i += step) {
		for (int j = step; j < image.rows - step / 2; j += step) {
			vector<double> center;
			Vec3b colour = image.at<Vec3b>(j, i);

			center.push_back(colour.val[0]);
			center.push_back(colour.val[1]);
			center.push_back(colour.val[2]);
			center.push_back(i);
			center.push_back(j);

			centers.push_back(center);
			center_counts.push_back(0);
		}
		centersColPieces++;
	}
	centersRowPieces = centers.size() / centersColPieces;

	//a szomszéd tömb feltöltése default értékekkel
	neighbors = new int[centers.size() * numberOfNeighbors];
	for (int i = 0; i < centers.size(); i++)
	{
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			neighbors[i*numberOfNeighbors + j] = -1;
		}
	}
}

double slicCPU::compute_dist(int ci, Point pixel, Vec3b colour) {
	//színtávolság
	double dc = sqrt(pow(centers[ci][0] - colour.val[0], 2) + pow(centers[ci][1]
		- colour.val[1], 2) + pow(centers[ci][2] - colour.val[2], 2));
	//euklideszi távolság
	double ds = sqrt(pow(centers[ci][3] - pixel.x, 2) + pow(centers[ci][4] - pixel.y, 2));

	return sqrt(pow(dc / nc, 2) + pow(ds / step, 2));
}

//Itt rendelem a pixeleket az egyes clusterekhez szín, valamint euklideszi távolság szerint
void slicCPU::generate_superpixels(Mat image) {
	clear_data();
	init_data(image);

	//A megadott iterációszámszor finomítóm a centroidok helyzetét
	for (int i = 0; i < iterations; i++)
	{
		//Bejárom az adott cluster "step" sugarú környezetét
		//Az itt található pixelek mindegyikére megnézem, hogy az aktuálisan vizsgált
		//centroid van-e hozzá a legközelebb, és ha igen, akkor beállítom a megfelelõ adatokat
		for (int j = 0; j < (int)centers.size(); j++)
		{
			for (int k = centers[j][3] - step; k < centers[j][3] + step; k++)
			{
				for (int l = centers[j][4] - step; l < centers[j][4] + step; l++)
				{
					//Ellenõrzöm a határokat
					if (k >= 0 && k < image.cols && l >= 0 && l < image.rows)
					{
						Vec3b colour = image.at<Vec3b>(l, k);
						double d = compute_dist(j, Point(k, l), colour);
						//ha a távolság kisebb mint az eddig mentett (a default az FLT_MAX) akkor beállítom 
						//az aktuális centroidot a legközelebbinek
						if (d < distances[k][l])
						{
							distances[k][l] = d;
							clusters[k][l] = j;
						}
					}
				}
			}
		}

		//a centroidok alaphelyzetbe állítása
		for (int j = 0; j < (int)centers.size(); j++)
		{
			centers[j][0] = 0;
			centers[j][1] = 0;
			centers[j][2] = 0;
			centers[j][3] = 0;
			centers[j][4] = 0;
			center_counts[j] = 0;
		}

		//Itt összegzem a korábban kapott eredményeket.

		for (int j = 0; j < image.cols; j++)
		{
			for (int k = 0; k < image.rows; k++)
			{
				//Alaphelyzetbe állítom a távolságértékeket minden piyel esetében
				distances[j][k] = FLT_MAX;

				//Megkeresem, hogy az adott pixel melyik centroidhoz tartozik.
				//amint ez megvan, összegzem ezeket az értékeket,
				//majd növelem a centroidhoz tartozó pixelek számát
				int c_id = clusters[j][k];
				if (c_id != -1)
				{
					Vec3b colour = image.at<Vec3b>(k, j);
					centers[c_id][0] += colour.val[0];
					centers[c_id][1] += colour.val[1];
					centers[c_id][2] += colour.val[2];
					centers[c_id][3] += j;
					centers[c_id][4] += k;
					center_counts[c_id] += 1;
				}
			}
		}

		//Az összegzett centroidértékeket elosztom a centroidhoz tartozó pixelek darabszámával.
		for (int j = 0; j < (int)centers.size(); j++)
		{
			centers[j][0] /= center_counts[j];
			centers[j][1] /= center_counts[j];
			centers[j][2] /= center_counts[j];
			centers[j][3] /= center_counts[j];
			centers[j][4] /= center_counts[j];
		}
	}
}

//A szomszédok összevonásakor használt színtávolság számító függvény
float slicCPU::colorDistance(Vec3b actuallPixel, Vec3b neighborPixel)
{
	float dc = sqrt(pow(actuallPixel.val[0] - neighborPixel.val[0], 2) + pow(actuallPixel.val[1] - neighborPixel.val[1], 2)
		+ pow(actuallPixel.val[2] - neighborPixel.val[2], 2));
	return dc;
}

//Itt kerülnek összevonásra a szomszédos hasonló színû szegmensek
void slicCPU::neighborMerge(Mat image)
{
	const int dx8[numberOfNeighbors] = { -1, -1,  0,  1, 1, 1, 0, -1 };
	const int dy8[numberOfNeighbors] = { 0, -1, -1, -1, 0, 1, 1,  1 };

	//A könyebb kezelhetõség érdekében átmásolom a vector értékeit 1d-be.
	int *centersIn1D = new int[centers.size() * 5];
	for (int i = 0; i < centers.size(); i++)
	{
		centersIn1D[i * 5 + 0] = centers[i][0];
		centersIn1D[i * 5 + 1] = centers[i][1];
		centersIn1D[i * 5 + 2] = centers[i][2];
		centersIn1D[i * 5 + 4] = centers[i][3];
		centersIn1D[i * 5 + 5] = centers[i][4];
	}

	for (int i = 0; i < (int)centers.size(); i++)
	{
		//kimentem az aktuális centroid értékeit
		Vec3b actuallCluster;
		actuallCluster.val[0] = centersIn1D[i * 5];
		actuallCluster.val[1] = centersIn1D[i * 5 + 1];
		actuallCluster.val[2] = centersIn1D[i * 5 + 2];

		int clusterRow = i / centersRowPieces;
		int clusterCol = i % centersRowPieces;

		//megnézem az aktuális centroid szomszédjait
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//ellenõrzöm a határokat
			if (clusterCol + dy8[j] >= 0 && clusterCol + dy8[j] < centersRowPieces
				&& clusterRow + dx8[j] >= 0 && clusterRow + dx8[j] < centersColPieces)
			{
				//kimentem a szomszédos centroid adatait
				Vec3b neighborPixel;
				neighborPixel.val[0] = centersIn1D[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 0];
				neighborPixel.val[1] = centersIn1D[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 1];
				neighborPixel.val[2] = centersIn1D[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 2];

				//ha az aktuális centroid sorszáma kisebb mint a szomszéd sorszáma, valamint a színtávolság a megengedett határon
				//belül van, akkor felveszem az összevonandó szömszédok közé.
				if (centersRowPieces * clusterRow + clusterCol < centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]) &&
					colorDistance(actuallCluster, neighborPixel) < maxColorDistance)
				{
					neighbors[(centersRowPieces * clusterRow + clusterCol) * numberOfNeighbors + j] = centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]);
				}
			}
		}
	}

	//inicializálok egy segédtömböt, amelyben el fogom tárolni hogy az egyes centroidokat melyik másik centroiddal kell összevonni
	vector<vector<int> > changes;
	for (int i = 0; i < (int)centers.size(); i++)
	{
		vector<int> change;
		change.push_back(i);
		change.push_back(-1);
		changes.push_back(change);
	}

	//Az itt következõ kódrésznek az a lényege, hogy az összevonandó centroidokat összeláncolom úgy, hogy az egymáshoz közel lévõ
	//megengedett színtávolságú centroidok össze legyenek vonva, annak elkerülése végett, hogy esetleg egy centroid egy olyan másik
	//centroiddal legyen összevonva, amelyet már összevontam egy másikkal.
	//Például: a kép szélén található egy fehér keret, amelyen 500 centroid helyezkedik el. Ezeket párossával is összevonhatnám, de
	//ehelyett mind az 500-at egy centroiddá alakítom, és egyben kezelem az egészet.
	for (int i = 0; i < centers.size(); i++)
	{
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//kimentem, hogy az adott szomszéd az melyik centroid
			int cluster = neighbors[i * numberOfNeighbors + j];
			if (cluster != -1)
			{
				//kimentem, hogy az adott centroidot melyik másikkal kell összevonni
				int neighborIDX = changes[cluster][1];
				int clusterIDX = i;
				//Addig megyek végig az összevonandókon amíg el nem érek egy oylan centroidig, amit már nem kell másikkal összevonni
				//(Garantáltan van olyan centroid a lánc végén amelyet nem kell másikkal összevonni, annak köszönhetõen, hogy 
				//csak akkor mentem el szomszédként az adott centroidot ha annak sorszáma nagyobb mint az aktuálisan vizsgált)
				while (neighborIDX != -1)
				{
					neighborIDX = changes[neighborIDX][1];
					if (neighborIDX != -1)
						clusterIDX = changes[neighborIDX][0];
				}
				if (changes[clusterIDX][1] != -1)
					changes[cluster][1] = changes[clusterIDX][1];
				else
					changes[cluster][1] = clusterIDX;
			}
		}
	}

	//Végül kimentem minden pixel esetében, hogy melyik az új centroid amhez mostantól tartoznak.
	for (int i = 0; i < image.cols; i++)
	{
		for (int j = 0; j < image.rows; j++)
		{
			if (changes[clusters[i][j]][1] != -1)
			{
				clusters[i][j] = changes[clusters[i][j]][1];
			}
		}
	}
}

//A feldolgozás befejeztével az eredményeket feldolgozva létrehozok egy új képet az eredmények alapján
void slicCPU::colour_with_cluster_means(Mat image)
{
	for (int i = 0; i < image.cols; i++)
	{
		for (int j = 0; j < image.rows; j++)
		{
			//Korábban már meghatároztam ,hogy az adott piyxelhez milyen szín tartozik, 
			//így csak beállítom, hogy az új képen is ez legyen a színe.
			int idx = clusters[i][j];
			Vec3b ncolour;

			ncolour.val[0] = centers[idx][0];
			ncolour.val[1] = centers[idx][1];
			ncolour.val[2] = centers[idx][2];

			image.at<Vec3b>(j, i) = ncolour;
		}
	}
}