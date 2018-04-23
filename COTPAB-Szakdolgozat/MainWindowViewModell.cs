using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace COTPAB_Szakdolgozat
{
    class MainWindowViewModell: Bindable
    {
        private string pathOriginal;

        public string PathOriginal
        {
            get { return pathOriginal; }
            set { pathOriginal = value; OnPropertyChanged(); }
        }

        private string pathNew;

        public string PathNew
        {
            get { return pathNew; }
            set { pathNew = value; OnPropertyChanged(); }
        }

        private string processSteps;

        public string ProcessSteps
        {
            get { return processSteps; }
            set { processSteps = value; OnPropertyChanged(); }
        }


        public void ImageImproving(int mode, int idxofTheSteppedImage, bool gpu)
        {
            ImageImproving ii = new ImageImproving(mode, PathOriginal, PathNew, idxofTheSteppedImage, this, gpu);
            ii.Improve();
        }

    }
}
