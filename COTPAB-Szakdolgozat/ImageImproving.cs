using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
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
        SemaphoreSlim semaphore;

        MainWindowViewModell vm; //Ez Azért kell hogy a feldolgozás során meg tudjam jeleníteni a feldolgozás állapotát.

        public ImageImproving(int mode, string pathOriginal, string pathNew, string pathtxt, MainWindowViewModell vm)
        {
            this.mode = mode;
            this.pathOriginal = pathOriginal;
            this.pathNew = pathNew;
            this.pathtxt = pathtxt;
            this.vm = vm;
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

        public void Improve()
        {
            Task[] tasks = new Task[howManyImages];
            for (int i = 0; i < tasks.Length; i++)
            {
                int helper = i;
                tasks[i] = Task.Run(() => Processing(helper));
            }
            
        }

        object lockobj = new object();
        private void Processing(int wich)
        {
            semaphore.Wait();

            Process TestProcess = new Process();
            TestProcess.StartInfo.FileName = "seged.exe";
            TestProcess.StartInfo.Arguments = filePaths[wich] + " " + filenames[wich] + " " + pathNew;

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
