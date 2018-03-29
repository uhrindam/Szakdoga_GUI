using Microsoft.Win32;
using Microsoft.WindowsAPICodePack.Dialogs;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;

namespace COTPAB_Szakdolgozat
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        MainWindowViewModell vm;
        int mode;
        string pathtxt = "";

        public MainWindow()
        {
            InitializeComponent();
            vm = new MainWindowViewModell();
            mode = 1;
            this.DataContext = vm;
        }

        private void btnOriginal_Click(object sender, RoutedEventArgs e)
        {
            CommonOpenFileDialog dialog = new CommonOpenFileDialog();
            dialog.InitialDirectory = "";
            dialog.Title = "Feldolgozandó képregény mappájának kiválasztása";
            dialog.IsFolderPicker = true;
            if (dialog.ShowDialog() == CommonFileDialogResult.Ok)
            {
                vm.PathOriginal = dialog.FileName;
                btnProcess.IsEnabled = true;
                if (vm.PathNew == null)
                    vm.PathNew = vm.PathOriginal + "\\Improved";
            }
        }

        private void btnNew_Click(object sender, RoutedEventArgs e)
        {
            CommonOpenFileDialog dialog = new CommonOpenFileDialog();
            if (vm.PathNew != null)
                dialog.InitialDirectory = vm.PathNew;
            else
                dialog.InitialDirectory = "";

            dialog.Title = "Feldolgozott képregény mappájának kiválasztása";
            dialog.IsFolderPicker = true;
            if (dialog.ShowDialog() == CommonFileDialogResult.Ok)
            {
                vm.PathNew = dialog.FileName;
            }
        }

        private void btnProcess_Click(object sender, RoutedEventArgs e)
        {
            if(pathtxt == "" && (mode == 3 || mode == 4 || mode == 5))
            {
                MessageBox.Show("A kiválasztott feldolgozási módhoz ki kell választanod egy szöveges állományt!");
            }
            else
            {
                btnProcess.IsEnabled = false;
                lProcessSteps.Visibility = Visibility.Visible;

                //----------------------------------------------------------------------------------------------------------------------
                bool gpu = false;
                label.Content = "CPU :(";
                ManagementObjectSearcher objvide = new ManagementObjectSearcher("select * from Win32_VideoController");

                foreach (ManagementObject obj in objvide.Get())
                {
                    string a = (string)obj["Name"];
                    if (a.Contains("NVIDIA"))
                    {
                        label.Content = "GPU";
                        gpu = true;
                    }
                }
                //----------------------------------------------------------------------------------------------------------------------

                vm.ImageImproving(mode, pathtxt, gpu);
            }
        }

        #region SetVisibility
        private void SetVisibility(int newMode)
        {
            if (mode != newMode)
            {
                if (mode == 3)
                {
                    Labelmode3.Visibility = Visibility.Hidden;
                    btnmode3.Visibility = Visibility.Hidden;
                }
                else if (mode == 4)
                {
                    Labelmode4.Visibility = Visibility.Hidden;
                    btnmode4.Visibility = Visibility.Hidden;
                }
                else if (mode == 5)
                {
                    Labelmode5.Visibility = Visibility.Hidden;
                    btnmode5.Visibility = Visibility.Hidden;
                }
                //----------------------

                if (newMode == 3)
                {
                    Labelmode3.Visibility = Visibility.Visible;
                    btnmode3.Visibility = Visibility.Visible;
                }
                else if (newMode == 4)
                {
                    Labelmode4.Visibility = Visibility.Visible;
                    btnmode4.Visibility = Visibility.Visible;
                }
                else if (newMode == 5)
                {
                    Labelmode5.Visibility = Visibility.Visible;
                    btnmode5.Visibility = Visibility.Visible;
                }
                mode = newMode;
            }
        }

        private void mode1_Checked(object sender, RoutedEventArgs e)
        {
            SetVisibility(1);
        }

        private void mode2_Checked(object sender, RoutedEventArgs e)
        {
            SetVisibility(2);
        }

        private void mode3_Checked(object sender, RoutedEventArgs e)
        {
            SetVisibility(3);
        }

        private void mode4_Checked(object sender, RoutedEventArgs e)
        {
            SetVisibility(4);
        }

        private void mode5_Checked(object sender, RoutedEventArgs e)
        {
            SetVisibility(5);
        }
        #endregion

        private void btnmode3_Click(object sender, RoutedEventArgs e)
        {
            OpenFileDialog fdlg = new OpenFileDialog();
            fdlg.Title = "A magyar szöveget tartalmazó fájl kiválasztása";
            fdlg.InitialDirectory = "";
            fdlg.Filter = "Txt|*.txt";
            fdlg.ShowDialog();

            if (fdlg.FileName != "")
            {
                pathtxt = fdlg.FileName;
            }
        }

        private void btnmode4_Click(object sender, RoutedEventArgs e)
        {
            CommonOpenFileDialog dialog = new CommonOpenFileDialog();
            dialog.InitialDirectory = "";

            dialog.Title = "Az angol szöveg mappájának kiválasztása";
            dialog.IsFolderPicker = true;
            if (dialog.ShowDialog() == CommonFileDialogResult.Ok)
            {
                pathtxt = dialog.FileName;
            }
        }

        private void btnmode5_Click(object sender, RoutedEventArgs e)
        {
            OpenFileDialog fdlg = new OpenFileDialog();
            fdlg.Title = "A magyar szöveget tartalmazó fájl kiválasztása";
            fdlg.InitialDirectory = "";
            fdlg.Filter = "Txt|*.txt";
            fdlg.ShowDialog();

            if(fdlg.FileName != "")
            {
                pathtxt = fdlg.FileName;
            }
        }

        private void btnSteps_Click(object sender, RoutedEventArgs e)
        {
            ImprovingStepsWindow isw = new ImprovingStepsWindow();
            isw.ShowDialog();
        }

        private void Pages_PreviewTextInput(object sender, TextCompositionEventArgs e)
        {
            Regex regex = new Regex("[^0-9]+");
            e.Handled = regex.IsMatch(e.Text);
        }

        private void cbSteps_Checked(object sender, RoutedEventArgs e)
        {
            lSteps.Visibility = Visibility.Visible;
            tbSteps.Visibility = Visibility.Visible;
        }

        private void cbSteps_Unchecked(object sender, RoutedEventArgs e)
        {
            lSteps.Visibility = Visibility.Hidden;
            tbSteps.Visibility = Visibility.Hidden;
        }
    }
}
