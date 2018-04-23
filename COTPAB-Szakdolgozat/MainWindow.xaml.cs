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
            mode = 0;
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
            btnProcess.IsEnabled = false;
            lProcessSteps.Visibility = Visibility.Visible;

            bool gpu = false;
            ManagementObjectSearcher objvide = new ManagementObjectSearcher("select * from Win32_VideoController");
            foreach (ManagementObject obj in objvide.Get())
            {
                string a = (string)obj["Name"];
                if (a.Contains("NVIDIA"))
                {
                    gpu = true;
                    break;
                }
            }

            int idxofTheSteppedImage = -1;
            if (tbSteps.Text != String.Empty)
            {
                idxofTheSteppedImage = Convert.ToInt32(tbSteps.Text);
            }

            if (mode1.IsChecked == true)
                mode = 0;
            else if(mode2.IsChecked == true)
                mode = 1;
            else if (mode3.IsChecked == true)
                mode = 2;
            else if (mode4.IsChecked == true)
                mode = 3;

            vm.ImageImproving(mode, idxofTheSteppedImage, gpu);
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
