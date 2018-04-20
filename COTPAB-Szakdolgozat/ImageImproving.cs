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
            CopyOfTheEXE();
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
        }

        private void CopyOfTheEXE()
        {
            var exePath = System.Reflection.Assembly.GetEntryAssembly().Location.Split('\\');
            string dllPath = string.Empty;
            string onlyPath = string.Empty;

            for (int i = 0; i < exePath.Length - 1; i++)
            {
                if (i < exePath.Length - 4)
                    dllPath += exePath[i] + '\\';
                onlyPath += exePath[i] + '\\';
            }
            dllPath += "x64\\Debug\\CUDA__SUPERPIXEL.exe";

            if (Directory.GetFiles(onlyPath, "CUDA__SUPERPIXEL.exe").Length == 0)
                File.Copy(dllPath, onlyPath + "CUDA__SUPERPIXEL.exe");
        }

        private void ImageQualityImprove(bool isGPU)
        {
            string isGPUProcess = String.Empty;
            if (gpu)
            {
                semaphore = new SemaphoreSlim(1);
                isGPUProcess = "gpu";
            }
            else
            {
                semaphore = new SemaphoreSlim(Environment.ProcessorCount);
                isGPUProcess = "cpu";
            }

            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                Task.Run(() => ImageQualityImproveProcessing(index, isGPUProcess));
            }
        }

        object improcessLockObj = new object();
        private void ImageQualityImproveProcessing(int which, string isGPUProcess)
        {
            semaphore.Wait();
            Console.WriteLine(which);

            Process TestProcess = new Process();
            TestProcess.StartInfo.FileName = "CUDA__SUPERPIXEL.exe";
            TestProcess.StartInfo.UseShellExecute = false;
            TestProcess.StartInfo.CreateNoWindow = true;
            TestProcess.StartInfo.Arguments = filePaths[which] + " " + pathNew + "\\"
                + filenames[which] + " " + isGPUProcess;

            TestProcess.Start();
            TestProcess.WaitForExit();
            lock (improcessLockObj)
            {
                ProcessStepsInc();
            }

            semaphore.Release();
        }

        private void DeleteBubleContent()
        {
            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                Task.Run(() => DeleteBubleContentProcessing(index));
            }
        }

        object deleteBubleContentLockObj = new object();
        private void DeleteBubleContentProcessing(int which)
        {
            semaphore.Wait();

            Process TestProcess = new Process();
            TestProcess.StartInfo.FileName = "seged.exe";
            TestProcess.StartInfo.Arguments = filePaths[which] + " " + filenames[which] + " " + pathNew;

            TestProcess.Start();
            TestProcess.WaitForExit();
            lock (deleteBubleContentLockObj)
            {
                ProcessStepsInc();
            }

            semaphore.Release();
        }

        public void Improve()
        {
            //üres szövegbuborékok, feljavtott kép
            if (mode == 0)
            {
                ImageQualityImprove(gpu);
            }
            //eredeti szöveg, feljavtott kép
            else if (mode == 1)
            {

            }
            //lefordtott, fejavtott kép
            else if (mode == 2)
            {

            }
            //eredeti szöveg, nincs feljavítás
            else if (mode == 3)
            {

            }
            //lefordtott, nincs feljavítás
            else if (mode == 4)
            {

            }
            //üres, nincs feljavitás
            else
            {
                DeleteBubleContent();
            }
        }

        private void ProcessStepsInc()
        {
            howManyTaskIsFinished++;
            vm.ProcessSteps = "A képek feldolgozása folyamatban. A feldolgozás állapota: " + howManyImages + " / " + howManyTaskIsFinished + ".";
            if (howManyTaskIsFinished == howManyImages)
                MessageBox.Show("A feldolgozás befejeződött!");
        }
    }
}
