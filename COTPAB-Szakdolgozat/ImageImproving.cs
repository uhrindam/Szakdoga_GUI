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
        string pathtxt;
        int howManyTaskIsFinished;
        bool gpu;
        SemaphoreSlim semaphore;

        MainWindowViewModell vm; //Ez Azért kell hogy a feldolgozás során meg tudjam jeleníteni a feldolgozás állapotát.

        public ImageImproving(int mode, string pathOriginal, string pathNew, string pathtxt, MainWindowViewModell vm, bool gpu)
        {
            this.mode = mode;
            this.pathOriginal = pathOriginal;
            this.pathNew = pathNew;
            this.pathtxt = pathtxt;
            this.vm = vm;
            this.gpu = gpu;
            howManyTaskIsFinished = -1;
            semaphore = new SemaphoreSlim(Environment.ProcessorCount);

            Directory.CreateDirectory(pathNew); //ha már létezik a mappa akkor nem történik semmi.

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
            ProcessStepsInc();
            Improve();
        }


        //[DllImport("C:\\Users\\Adam\\Desktop\\COTPAB-Szakdolgozat\\x64\\Debug\\CUDA_SuperPixel.dll", CallingConvention = CallingConvention.Cdecl)]
        [DllImport("CUDA_SuperPixel.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void SP(string readPath, string writePath);

        //[DllImport("C:\\Users\\Adam\\Desktop\\COTPAB-Szakdolgozat\\x64\\Debug\\CUDA_SuperPixel.dll", CallingConvention = CallingConvention.Cdecl)]
        [DllImport("CUDA_SuperPixel.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void SuperPixel(string readPath, string writePath);

        public void Improve()
        {
            if (gpu)
                SP(filePaths[0], pathNew + "\\" + filenames[0]);
            else
                SuperPixel(filePaths[0], pathNew + "\\" + filenames[0]);


            //Task[] tasks = new Task[howManyImages];
            //for (int i = 0; i < tasks.Length; i++)
            //{
            //    int helper = i;
            //    tasks[i] = Task.Run(() => Processing(helper));
            //}

        }

        object lockobj = new object();
        private void Processing(int which)
        {
            semaphore.Wait();

            Process TestProcess = new Process();
            TestProcess.StartInfo.FileName = "seged.exe";
            TestProcess.StartInfo.Arguments = filePaths[which] + " " + filenames[which] + " " + pathNew;

            TestProcess.Start();


            TestProcess.WaitForExit();
            lock (lockobj)
            {
                ProcessStepsInc();
            }
            semaphore.Release();
        }

        private void ProcessStepsInc()
        {
            howManyTaskIsFinished++;
            vm.ProcessSteps = "A képek feldolgozása folyamatban. A feldolgozás állapota: " + howManyImages + " / " + howManyTaskIsFinished + ".";
            //if (howManyTaskIsFinished == howManyImages)
            //    MessageBox.Show("A feldolgozás befejeződött!");
        }
    }
}
