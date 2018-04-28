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
        const string CUDAEXENAME = "CUDA__SUPERPIXEL.exe";
        const string CPUEXENAME = "CPU__SUPERPIXEL.exe";
        const string BUBLESEARCHEREXENAME = "BubleFinderWithOpenCV.exe";
        const string TEXTWRITEREXENAME = "BubleTextWriter.exe";

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
        MainWindowViewModell vm;

        /// <summary>
        /// Az értékek inicializálása
        /// </summary>
        /// <param name="mode"></param>
        /// <param name="pathOriginal"></param>
        /// <param name="pathNew"></param>
        /// <param name="idxofTheSteppedImage"></param>
        /// <param name="vm"></param>
        /// <param name="gpu"></param>
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

        /// <summary>
        /// A felhasználó által kiválasztott feldolgozandó mappa tartalma között megkeresem a képeket, 
        /// majd azok neveit (és elérési útjaikat) eltárolom későbbi feldolgozás céljából.
        /// Később beállítom annak a változónak az értékét amely jelzi, hogy el kell-e menteni a feldolgozási lépéseket.
        /// </summary>
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

        /// <summary>
        /// Megnézem hogy az exe mellett megtalálhatóak-e a kívánt exe-k és ha nem, akkor átmásolom azokat.
        /// </summary>
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
            string cudaEXEPath = projectRootPath + "x64\\Debug\\" + CUDAEXENAME;
            string cpuEXEPath = projectRootPath + "x64\\Debug\\" + CPUEXENAME;

            if (Directory.GetFiles(onlyPath, CUDAEXENAME).Length == 0)
            {
                File.Copy(cudaEXEPath, onlyPath + CUDAEXENAME, true);
            }
            if (Directory.GetFiles(onlyPath, CPUEXENAME).Length == 0)
            {
                File.Copy(cpuEXEPath, onlyPath + CPUEXENAME, true);
            }
        }

        /// <summary>
        /// Itt történik meg a processhívás, amely során a paramtéerként kapott nevű exe-t indítom el
        /// az előre legenerált argumentumlistával. Ezt úgy teszem meg, hogy console ablak ne jelenjen meg a hívás során.
        /// Amennyiben egy process végzett, az megnöveli a feldolgozottsági értéket, amelyet a szálbiztosság érdekében
        /// kölcsönös kizárással oldottam meg.
        /// Ahol ezt a metódust használni fogom, ott Annyi szálat hozok létre ahány képet fel kell dolgoznom, 
        /// viszont annak érdekében, hogy ne legyen túl nagy overhead, egyszerre csak annyi szálat engedek dolgozni 
        /// amennyi processzormag találhatóa futtoató számítógépben. Ennek a megvalósítására semaphoret használok.
        /// </summary>
        object processLockObj = new object();
        private void useProcess(string exeName, string arguments)
        {
            semaphore.Wait();

            Process process = new Process();
            process.StartInfo.FileName = exeName;
            process.StartInfo.UseShellExecute = false;
            process.StartInfo.CreateNoWindow = true;
            process.StartInfo.Arguments = arguments;
            process.Start();
            process.WaitForExit();

            lock (processLockObj)
            {
                ProcessStepsInc();
            }

            semaphore.Release();
        }

        /// <summary>
        /// A 0. felhasználói mód, amely során a kiválasztott képek szövegbuborékaiból eltávolításra kerülnek 
        /// azok tartalmai. Amennyiben szükség van  a feldolgozási lépések megjelenítésére, akkor a kép sorszámát 
        /// adom át paraméterül, különben pedig egy "-" jelet.
        /// </summary>
        private void processMode0()
        {
            InitProcessSteps(1);
            semaphore = new SemaphoreSlim(Environment.ProcessorCount);
            Task[] tasks = new Task[howManyImages];
            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                if (idxofTheSteppedImage != index)
                    tasks[index] = Task.Run(() => useProcess(BUBLESEARCHEREXENAME, filePaths[index] + " " +
                        filenames[index] + " " + pathNew + "\\" + " " + "-" + " " + mode));
                else
                    tasks[index] = Task.Run(() => useProcess(BUBLESEARCHEREXENAME, filePaths[index] + " " +
                        filenames[index] + " " + pathNew + "\\" + " " + idxofTheSteppedImage.ToString() + " " + mode));
            }
        }

        /// <summary>
        /// Az 1. felhasználói mód, amely során a kiválasztott képek szövegbuborékaiból eltávolításra kerülnek 
        /// azok tartalmai, majd pedig az eredeti szöveg visszaírásra kerül. Amennyiben szükség van  a feldolgozási lépések
        /// megjelenítésére, akkor a kép sorszámát adom át paraméterül, különben pedig egy "-" jelet.
        /// </summary>
        private void processMode1()
        {
            InitProcessSteps(2);
            Directory.CreateDirectory(pathNew + "\\Temp");
            semaphore = new SemaphoreSlim(Environment.ProcessorCount);
            Task[] tasks = new Task[howManyImages];
            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                if (idxofTheSteppedImage != index)
                {
                    tasks[index] = Task.Run(() => useProcess(BUBLESEARCHEREXENAME, filePaths[index] + " " + filenames[index] + " "
                        + pathNew + "\\" + " " + "-" + " " + mode));
                    tasks[index].ContinueWith(antecedent => useProcess(TEXTWRITEREXENAME, filePaths[index] + " "
                        + filenames[index] + " " + pathNew + "\\"));
                }
                else
                {
                    tasks[index] = Task.Run(() => useProcess(BUBLESEARCHEREXENAME, filePaths[index] + " " +
                        filenames[index] + " " + pathNew + "\\" + " " + idxofTheSteppedImage.ToString() + " " + mode));
                    tasks[index].ContinueWith(antecedent => useProcess(TEXTWRITEREXENAME, filePaths[index] + " " +
                        filenames[index] + " " + pathNew + "\\"));
                }
            }
        }

        /// <summary>
        /// A 2. felhasználói mód, amely során a kiválasztott képek szövegbuborékaiból eltávolításra kerülnek 
        /// azok tartalmai, majd pedig attól függően hogy a futtató számítógépben található-e CUDA-képes NVIDIA kártya,
        /// elindítom a kép feljavítását GPU-n vagy CPU-n.
        /// </summary>
        private void processMode2()
        {
            InitProcessSteps(2);
            Task[] tasks = new Task[howManyImages];

            string exeName = String.Empty;
            if (gpu)
            {
                semaphore = new SemaphoreSlim(1);
                exeName = CUDAEXENAME;
            }
            else
            {
                semaphore = new SemaphoreSlim(Environment.ProcessorCount);
                exeName = CPUEXENAME;
            }

            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                tasks[index] = Task.Run(() => useProcess(BUBLESEARCHEREXENAME, filePaths[index] + " " +
                    filenames[index] + " " + pathNew + "\\" + " " + "-" + " " + mode));
                tasks[index].ContinueWith(antecedent => useProcess(exeName, pathNew + "\\" +
                    filenames[index] + " " + pathNew + "\\" + filenames[index]));
            }
        }

        /// <summary>
        /// A 3. felhasználói mód, amely során a kiválasztott képek szövegbuborékaiból eltávolításra kerülnek 
        /// azok tartalmai, majd pedig attól függően hogy a futtató számítógépben található-e CUDA-képes NVIDIA kártya,
        /// elindítom a kép feljavítását GPU-n vagy CPU-n. Ezt követően az eredeti szöveg visszaírásra kerül. 
        /// </summary>
        private void processMode3()
        {
            InitProcessSteps(3);
            Directory.CreateDirectory(pathNew + "\\Temp");
            Task[] tasks = new Task[howManyImages];
            string exeName = String.Empty;
            if (gpu)
            {
                semaphore = new SemaphoreSlim(1);
                exeName = CUDAEXENAME;
            }
            else
            {
                semaphore = new SemaphoreSlim(Environment.ProcessorCount);
                exeName = CPUEXENAME;
            }

            for (int i = 0; i < howManyImages; i++)
            {
                int index = i;
                tasks[index] = Task.Run(() => useProcess(BUBLESEARCHEREXENAME, filePaths[index] + " " +
                    filenames[index] + " " + pathNew + "\\" + " " + "-" + " " + mode));
                Task middle = tasks[index].ContinueWith(antecedent => useProcess(exeName, pathNew + "\\" +
                    filenames[index] + " " + pathNew + "\\" + filenames[index]));
                middle.ContinueWith(antecedent => useProcess(TEXTWRITEREXENAME, filePaths[index] + " " +
                    filenames[index] + " " + pathNew + "\\"));
            }
        }

        /// <summary>
        /// Itt hívom meg a felhasználó által kiválasztott módnak megfelelő metódusokat.
        /// </summary>
        public void Improve()
        {
            //üres, nincs feljavitás
            if (mode == 0)
                processMode0();
            //eredeti szöveg, nincs feljavítás
            else if (mode == 1)
                processMode1();
            //üres szövegbuborékok, feljavtott kép
            else if (mode == 2)
                processMode2();
            //eredeti szöveg, feljavtott kép
            else if (mode == 3)
                processMode3();
        }

        /// <summary>
        /// Amennyiben elindítja a felhasználó a feldolgozást, akkor ezzel a metódussal 
        /// inicializálom a feldolgozás állapotát jelzó részt.
        /// </summary>
        /// <param name="howmanyRound"></param>
        private void InitProcessSteps(int howmanyRound)
        {
            maxProcessSteps = howManyImages * howmanyRound;
            vm.ProcessSteps = "A képek feldolgozása folyamatban. A feldolgozás állapota: " + maxProcessSteps +
                " / " + howManyTaskIsFinished + ".";
        }

        /// <summary>
        /// A feldolgozás során amennyiben egy feladattal végzett a program, lépteti a feldolgozottsági állapot értékét, 
        /// amelyet ezzel a metódussal tehet meg. Amennyiben a feldolgozás állapotát jelző érték, valamint az összes feladat
        /// száma megegyezik, akkor végetért a feldolgozás, amelyről értesítést ad a program egy messageBox segítségével.
        /// Amennyiben a feldolgozás 1, vagy 3as módban történt, eltávolításra kerül a Temp mappa, annak minden tartalmával együtt.
        /// </summary>
        private void ProcessStepsInc()
        {
            howManyTaskIsFinished++;
            vm.ProcessSteps = "A képek feldolgozása folyamatban. A feldolgozás állapota: " + maxProcessSteps +
                " / " + howManyTaskIsFinished + ".";
            if (howManyTaskIsFinished == maxProcessSteps)
            {
                if (idxofTheSteppedImage < 0)
                    MessageBox.Show("A feldolgozás befejeződött!");
                else
                    MessageBox.Show("A feldolgozás befejeződött!\nA feldolgozási lépések képei megtalálhatóak" +
                        "a kiválaszott mentési könyvtár \\Steps alkönyvtárában.");
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
