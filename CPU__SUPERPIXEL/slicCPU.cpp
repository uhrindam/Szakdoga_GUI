#include "slicCPU.h"

slicCPU::slicCPU() {}

slicCPU::~slicCPU() {
	clear_data();
}

//A  vectorok tartalm�nak t�rl�se
void slicCPU::clear_data() {
	clusters.clear();
	distances.clear();
	centers.clear();
	center_counts.clear();
}

void slicCPU::init_data(Mat image) {
	step = (sqrt((image.cols * image.rows) / (double)numberofSuperpixels));

	//felt�lt�s default adatokkal
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
	//A centroidok inicializ�l�sa
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

	//a szomsz�d t�mb felt�lt�se default �rt�kekkel
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
	//sz�nt�vols�g
	double dc = sqrt(pow(centers[ci][0] - colour.val[0], 2) + pow(centers[ci][1]
		- colour.val[1], 2) + pow(centers[ci][2] - colour.val[2], 2));
	//euklideszi t�vols�g
	double ds = sqrt(pow(centers[ci][3] - pixel.x, 2) + pow(centers[ci][4] - pixel.y, 2));

	return sqrt(pow(dc / nc, 2) + pow(ds / step, 2));
}

//Itt rendelem a pixeleket az egyes clusterekhez sz�n, valamint euklideszi t�vols�g szerint
void slicCPU::generate_superpixels(Mat image) {
	clear_data();
	init_data(image);

	//A megadott iter�ci�sz�mszor finom�t�m a centroidok helyzet�t
	for (int i = 0; i < iterations; i++)
	{
		//Bej�rom az adott cluster "step" sugar� k�rnyezet�t
		//Az itt tal�lhat� pixelek mindegyik�re megn�zem, hogy az aktu�lisan vizsg�lt
		//centroid van-e hozz� a legk�zelebb, �s ha igen, akkor be�ll�tom a megfelel� adatokat
		for (int j = 0; j < (int)centers.size(); j++)
		{
			for (int k = centers[j][3] - step; k < centers[j][3] + step; k++)
			{
				for (int l = centers[j][4] - step; l < centers[j][4] + step; l++)
				{
					//Ellen�rz�m a hat�rokat
					if (k >= 0 && k < image.cols && l >= 0 && l < image.rows)
					{
						Vec3b colour = image.at<Vec3b>(l, k);
						double d = compute_dist(j, Point(k, l), colour);
						//ha a t�vols�g kisebb mint az eddig mentett (a default az FLT_MAX) akkor be�ll�tom 
						//az aktu�lis centroidot a legk�zelebbinek
						if (d < distances[k][l])
						{
							distances[k][l] = d;
							clusters[k][l] = j;
						}
					}
				}
			}
		}

		//a centroidok alaphelyzetbe �ll�t�sa
		for (int j = 0; j < (int)centers.size(); j++)
		{
			centers[j][0] = 0;
			centers[j][1] = 0;
			centers[j][2] = 0;
			centers[j][3] = 0;
			centers[j][4] = 0;
			center_counts[j] = 0;
		}

		//Itt �sszegzem a kor�bban kapott eredm�nyeket.

		for (int j = 0; j < image.cols; j++)
		{
			for (int k = 0; k < image.rows; k++)
			{
				//Alaphelyzetbe �ll�tom a t�vols�g�rt�keket minden piyel eset�ben
				distances[j][k] = FLT_MAX;

				//Megkeresem, hogy az adott pixel melyik centroidhoz tartozik.
				//amint ez megvan, �sszegzem ezeket az �rt�keket,
				//majd n�velem a centroidhoz tartoz� pixelek sz�m�t
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

		//Az �sszegzett centroid�rt�keket elosztom a centroidhoz tartoz� pixelek darabsz�m�val.
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

//A szomsz�dok �sszevon�sakor haszn�lt sz�nt�vols�g sz�m�t� f�ggv�ny
float slicCPU::colorDistance(Vec3b actuallPixel, Vec3b neighborPixel)
{
	float dc = sqrt(pow(actuallPixel.val[0] - neighborPixel.val[0], 2) + pow(actuallPixel.val[1] - neighborPixel.val[1], 2)
		+ pow(actuallPixel.val[2] - neighborPixel.val[2], 2));
	return dc;
}

//Itt ker�lnek �sszevon�sra a szomsz�dos hasonl� sz�n� szegmensek
void slicCPU::neighborMerge(Mat image)
{
	const int dx8[numberOfNeighbors] = { -1, -1,  0,  1, 1, 1, 0, -1 };
	const int dy8[numberOfNeighbors] = { 0, -1, -1, -1, 0, 1, 1,  1 };

	//A k�nyebb kezelhet�s�g �rdek�ben �tm�solom a vector �rt�keit 1d-be.
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
		//kimentem az aktu�lis centroid �rt�keit
		Vec3b actuallCluster;
		actuallCluster.val[0] = centersIn1D[i * 5];
		actuallCluster.val[1] = centersIn1D[i * 5 + 1];
		actuallCluster.val[2] = centersIn1D[i * 5 + 2];

		int clusterRow = i / centersRowPieces;
		int clusterCol = i % centersRowPieces;

		//megn�zem az aktu�lis centroid szomsz�djait
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//ellen�rz�m a hat�rokat
			if (clusterCol + dy8[j] >= 0 && clusterCol + dy8[j] < centersRowPieces
				&& clusterRow + dx8[j] >= 0 && clusterRow + dx8[j] < centersColPieces)
			{
				//kimentem a szomsz�dos centroid adatait
				Vec3b neighborPixel;
				neighborPixel.val[0] = centersIn1D[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 0];
				neighborPixel.val[1] = centersIn1D[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 1];
				neighborPixel.val[2] = centersIn1D[(centersRowPieces* (clusterRow + dx8[j]) + (clusterCol + dy8[j])) * 5 + 2];

				//ha az aktu�lis centroid sorsz�ma kisebb mint a szomsz�d sorsz�ma, valamint a sz�nt�vols�g a megengedett hat�ron
				//bel�l van, akkor felveszem az �sszevonand� sz�msz�dok k�z�.
				if (centersRowPieces * clusterRow + clusterCol < centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]) &&
					colorDistance(actuallCluster, neighborPixel) < maxColorDistance)
				{
					neighbors[(centersRowPieces * clusterRow + clusterCol) * numberOfNeighbors + j] = centersRowPieces * (clusterRow + dx8[j]) + (clusterCol + dy8[j]);
				}
			}
		}
	}

	//inicializ�lok egy seg�dt�mb�t, amelyben el fogom t�rolni hogy az egyes centroidokat melyik m�sik centroiddal kell �sszevonni
	vector<vector<int> > changes;
	for (int i = 0; i < (int)centers.size(); i++)
	{
		vector<int> change;
		change.push_back(i);
		change.push_back(-1);
		changes.push_back(change);
	}

	//Az itt k�vetkez� k�dr�sznek az a l�nyege, hogy az �sszevonand� centroidokat �sszel�ncolom �gy, hogy az egym�shoz k�zel l�v�
	//megengedett sz�nt�vols�g� centroidok �ssze legyenek vonva, annak elker�l�se v�gett, hogy esetleg egy centroid egy olyan m�sik
	//centroiddal legyen �sszevonva, amelyet m�r �sszevontam egy m�sikkal.
	//P�ld�ul: a k�p sz�l�n tal�lhat� egy feh�r keret, amelyen 500 centroid helyezkedik el. Ezeket p�ross�val is �sszevonhatn�m, de
	//ehelyett mind az 500-at egy centroidd� alak�tom, �s egyben kezelem az eg�szet.
	for (int i = 0; i < centers.size(); i++)
	{
		for (int j = 0; j < numberOfNeighbors; j++)
		{
			//kimentem, hogy az adott szomsz�d az melyik centroid
			int cluster = neighbors[i * numberOfNeighbors + j];
			if (cluster != -1)
			{
				//kimentem, hogy az adott centroidot melyik m�sikkal kell �sszevonni
				int neighborIDX = changes[cluster][1];
				int clusterIDX = i;
				//Addig megyek v�gig az �sszevonand�kon am�g el nem �rek egy oylan centroidig, amit m�r nem kell m�sikkal �sszevonni
				//(Garant�ltan van olyan centroid a l�nc v�g�n amelyet nem kell m�sikkal �sszevonni, annak k�sz�nhet�en, hogy 
				//csak akkor mentem el szomsz�dk�nt az adott centroidot ha annak sorsz�ma nagyobb mint az aktu�lisan vizsg�lt)
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

	//V�g�l kimentem minden pixel eset�ben, hogy melyik az �j centroid amhez mostant�l tartoznak.
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

//A feldolgoz�s befejezt�vel az eredm�nyeket feldolgozva l�trehozok egy �j k�pet az eredm�nyek alapj�n
void slicCPU::colour_with_cluster_means(Mat image)
{
	for (int i = 0; i < image.cols; i++)
	{
		for (int j = 0; j < image.rows; j++)
		{
			//Kor�bban m�r meghat�roztam ,hogy az adott piyxelhez milyen sz�n tartozik, 
			//�gy csak be�ll�tom, hogy az �j k�pen is ez legyen a sz�ne.
			int idx = clusters[i][j];
			Vec3b ncolour;

			ncolour.val[0] = centers[idx][0];
			ncolour.val[1] = centers[idx][1];
			ncolour.val[2] = centers[idx][2];

			image.at<Vec3b>(j, i) = ncolour;
		}
	}
}