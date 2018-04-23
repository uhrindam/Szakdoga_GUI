using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;

namespace COTPAB_Szakdolgozat
{
    class ImageImproving
    {
        string[] filePaths;
        string[] filenames;
        int howManyImages;
        int mode;
        string pathOriginal;
        string pathNew;
        int howManyTaskIsFinished;
        bool gpu;
        int idxofTheSteppedImage;
        SemaphoreSlim semaphore;
        int maxProcessSteps;
        MainWindowViewModell vm; //Ez Azért kell hogy a feldolgozás során meg tudjam jeleníteni a feldolgozás állapotát.

        public ImageImproving(int mode, string pathOriginal, string pathNew, int idxofTheSteppedImage, MainWindowViewModell vm, bool gpu)
        {
            this.mode = mode;
            this.pathOriginal = pathOriginal;
            this.pathNew = pathNew;
            this.idxofTheSteppedImage = idxofTheSteppedImage;
            this.vm = vm;
            this.gpu = gpu;
            howManyTaskIsFinished = 0;
            maxProcessSteps = 0;
            EXECopy();
            Directory.CreateDirectory(pathNew);
            ProcessingThePaths();
        }

        private void ProcessingThePaths()
        {
            filePaths = Directory.GetFiles(pathOriginal, "*.jp*"); //Azért jp* mert jpg és jpeg is lehet.
            filenames = new string[filePaths.Length];

            for (int i = 0; i < filePaths.Length; i++)
            {
                filenames[i] = filePaths[i].Split('\\').Last();
            }

            howManyImages = filePaths.Length;
            if (idxofTheSteppedImage > howManyImages)
                idxofTheSteppedImage = -1;
            else
                idxofTheSteppedImage--;


        }

        private void EXECopy()
        {
            var exePath = System.Reflection.Assembly.GetEntryAssembly().Location.Split('\\');
            string projectRootPath = string.Empty;
            string onlyPath = string.Empty;

            for (int i = 0; i < exePath.Length - 1; i++)
            {
                if (i < exePath.Length - 4)
                    projectRootPath += exePath[i] + '\\';
                onlyPath += exePath[i] + '\\';
            }
            string cudaEXEPath = projectRootPath + "x64\\Debug\\CUDA__SUPERPIXEL.exe";
            string cpuEXEPath = projectRootPath + "x64\\Debug\\CPU__SUPERPIXEL.exe";

            if (Directory.GetFiles(onlyPath, "CUDA__SUPERPIXEL.exe").Length == 0)
            {
                File.Copy(cudaEXEPath, onlyPath + "CUDA__SUPERPIXEL.exe", true);
            }
            if (Directory.GetFiles(onlyPath, "CPU__SUPERPIXEL.exe").Length == 0)
            {
                File.Copy(cpuEXEPath, onlyPath + "CPU__SUPERPIXEL.exe", true);
            }
        }

        object processLockObj = new object();
        private void useProcess(string exeName, string arguments)
        {
            semaphore.Wait();

            Process TestProcess = new Process();
            TestProcess.StartInfo.FileName = exeName;
            TestProcess.StartInfo.UseShellExecute = false;
            TestProcess.StartInfo.CreateNoWindow = true;
            TestProcess.StartInfo.Arguments = arguments;
            TestProcess.Start();
            TestProcess.WaitForExit();

            lock (processLockObj)
            {
                ProcessStepsInc();
            }

            semaphore.Release();
        }

        private void processMode0()
        {
            IniProcessSteps(1);
            semaphore = new SemaphoreSlim(Environment.ProcessorCount);
            Task[] tasks = new Task[howManyImages];
            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                if (idxofTheSteppedImage != index)
                    tasks[index] = Task.Run(() => useProcess("BubleFinderWithOpenCV.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\" + " " + "-" + " " + mode));
                else
                    tasks[index] = Task.Run(() => useProcess("BubleFinderWithOpenCV.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\" + " " + idxofTheSteppedImage.ToString() + " " + mode));
            }
        }

        private void processMode1()
        {
            IniProcessSteps(2);
            Directory.CreateDirectory(pathNew + "\\Temp");
            semaphore = new SemaphoreSlim(Environment.ProcessorCount);
            Task[] tasks = new Task[howManyImages];
            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                if (idxofTheSteppedImage != index)
                {
                    tasks[index] = Task.Run(() => useProcess("BubleFinderWithOpenCV.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\" + " " + "-" + " " + mode));
                    tasks[index].ContinueWith(antecedent => useProcess("BubleTextWriter.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\"));
                }
                else
                {
                    tasks[index] = Task.Run(() => useProcess("BubleFinderWithOpenCV.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\" + " " + idxofTheSteppedImage.ToString() + " " + mode));
                    tasks[index].ContinueWith(antecedent => useProcess("BubleTextWriter.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\"));
                }
            }
        }

        private void processMode2()
        {
            IniProcessSteps(2);
            Task[] tasks = new Task[howManyImages];

            string exeName = String.Empty;
            if (gpu)
            {
                semaphore = new SemaphoreSlim(1);
                exeName = "CUDA__SUPERPIXEL";
            }
            else
            {
                semaphore = new SemaphoreSlim(Environment.ProcessorCount);
                exeName = "CPU__SUPERPIXEL";
            }

            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                tasks[index] = Task.Run(() => useProcess("BubleFinderWithOpenCV.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\" + " " + "-" + " " + mode));
                tasks[index].ContinueWith(antecedent => useProcess(exeName, pathNew + "\\" + filenames[index] + " " + pathNew + "\\" + filenames[index]));
            }
        }

        private void processMode3()
        {
            IniProcessSteps(3);
            Directory.CreateDirectory(pathNew + "\\Temp");
            Task[] tasks = new Task[howManyImages];
            string exeName = String.Empty;
            if (gpu)
            {
                semaphore = new SemaphoreSlim(1);
                exeName = "CUDA__SUPERPIXEL";
            }
            else
            {
                semaphore = new SemaphoreSlim(Environment.ProcessorCount);
                exeName = "CPU__SUPERPIXEL";
            }

            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                tasks[index] = Task.Run(() => useProcess("BubleFinderWithOpenCV.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\" + " " + "-" + " " + mode));
                Task middle = tasks[index].ContinueWith(antecedent => useProcess(exeName, pathNew + "\\" + filenames[index] + " " + pathNew + "\\" + filenames[index]));
                middle.ContinueWith(antecedent => useProcess("BubleTextWriter.exe", filePaths[index] + " " + filenames[index] + " " + pathNew + "\\"));
            }
        }

        public void Improve()
        {
            //üres, nincs feljavitás
            if (mode == 0)
            {
                processMode0();

            }
            //eredeti szöveg, nincs feljavítás
            else if (mode == 1)
            {
                processMode1();
            }
            //üres szövegbuborékok, feljavtott kép
            else if (mode == 2)
            {
                processMode2();
            }
            //eredeti szöveg, feljavtott kép
            else if (mode == 3)
            {
                processMode3();
            }
        }

        private void IniProcessSteps(int howmanyRound)
        {
            maxProcessSteps = howManyImages * howmanyRound;
            vm.ProcessSteps = "A képek feldolgozása folyamatban. A feldolgozás állapota: " + maxProcessSteps + " / " + howManyTaskIsFinished + ".";
        }

        private void ProcessStepsInc()
        {
            howManyTaskIsFinished++;
            vm.ProcessSteps = "A képek feldolgozása folyamatban. A feldolgozás állapota: " + maxProcessSteps + " / " + howManyTaskIsFinished + ".";
            if (howManyTaskIsFinished == maxProcessSteps)
            {
                if (idxofTheSteppedImage < 0)
                    MessageBox.Show("A feldolgozás befejeződött!");
                else
                    MessageBox.Show("A feldolgozás befejeződött!\nA feldolgozási lépések képei megtalálhatóak a kiválaszott mentési könyvtár \\Steps alkönyvtárában.");
                if (mode == 1 || mode == 3)
                {
                    System.IO.DirectoryInfo di = new DirectoryInfo(pathNew + "\\Temp");

                    foreach (FileInfo file in di.GetFiles())
                    {
                        file.Delete();
                    }
                    Directory.Delete(pathNew + "\\Temp");
                }
            }
        }
    }
}
