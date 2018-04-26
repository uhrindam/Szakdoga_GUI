using System.Management;

namespace COTPAB_Szakdolgozat
{
    class MainWindowViewModell: Bindable
    {
        private string pathOriginal;
        private string pathNew;
        private string processSteps;

        /// <summary>
        /// Ez a változó tartalmazza a feldolgozandó képregények elérési útvonalát
        /// </summary>
        public string PathOriginal
        {
            get { return pathOriginal; }
            set { pathOriginal = value; OnPropertyChanged(); }
        }

        /// <summary>
        /// Ez a változó tartalmazza a feldolgozott képregények mentési útvonalát
        /// </summary>
        public string PathNew
        {
            get { return pathNew; }
            set { pathNew = value; OnPropertyChanged(); }
        }

        /// <summary>
        /// Ez az érték tartalmazza, hogy éppen hogyan áll a feldolgozás.
        /// </summary>
        public string ProcessSteps
        {
            get { return processSteps; }
            set { processSteps = value; OnPropertyChanged(); }
        }

        /// <summary>
        /// Ebben a metódusban lekérdezésre kerül, hogy van-e NVIDIA videókártya a futtató számítógépben.
        /// </summary>
        /// <returns>Van-e NVIDIA kártya</returns>
        private bool CheckForNVIDIA()
        {
            bool gpu = false;
            ManagementObjectSearcher objvideo = new ManagementObjectSearcher("select * from Win32_VideoController");
            foreach (ManagementObject obj in objvideo.Get())
            {
                string VideoControllersNames = (string)obj["Name"];
                if (VideoControllersNames.Contains("NVIDIA"))
                {
                    gpu = true;
                    break;
                }
            }
            return gpu;
        }

        /// <summary>
        /// A képek feldolgozásának elindítása
        /// </summary>
        /// <param name="mode">A kiváalsztott feldolgozási mód</param>
        /// <param name="idxofTheSteppedImage">-1 Ha nem kell menteni a lépéseket, a kép sorszáma ha kell.</param>
        public void ImageImproving(int mode, int idxofTheSteppedImage)
        {
            ImageImproving ii = new ImageImproving(mode, PathOriginal, PathNew, idxofTheSteppedImage, this, CheckForNVIDIA());
            ii.Improve();
        }

    }
}
