using Microsoft.WindowsAPICodePack.Dialogs;
using System;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Input;

namespace COTPAB_Szakdolgozat
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        MainWindowViewModell vm;
        int mode;

        public MainWindow()
        {
            InitializeComponent();
            vm = new MainWindowViewModell();
            mode = 0;
            this.DataContext = vm;
        }

        /// <summary>
        /// A feldolgozandó képregények útvonalának megadása történik itt.
        /// + default mentési hely beállítása
        /// </summary>
        /// <param name="sender">-</param>
        /// <param name="e">-</param>
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

        /// <summary>
        /// A feldolgozott kérpegények mentési helyénk megadása történik itt.
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
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

        /// <summary>
        /// Itt indul el a feldolgozás, a láthatósági értékek beállítása után kigyűjtöm, hogy el 
        /// kell-e a feldolgozási lépéseket elmentem, beállítom a kiválasztott mód értékét, majd elindítom a keresést.
        /// </summary>
        /// <param name="sender">-</param>
        /// <param name="e">-</param>
        private void btnProcess_Click(object sender, RoutedEventArgs e)
        {
            btnProcess.IsEnabled = false;
            lProcessSteps.Visibility = Visibility.Visible;

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

            vm.ImageImproving(mode, idxofTheSteppedImage);
        }

        /// <summary>
        /// Ezzel megakadályozom, hogy számtól különböző karaktert is beírhassanak a textboxba.
        /// </summary>
        /// <param name="sender">-</param>
        /// <param name="e">-</param>
        private void Pages_PreviewTextInput(object sender, TextCompositionEventArgs e)
        {
            Regex regex = new Regex("[^0-9]+");
            e.Handled = regex.IsMatch(e.Text);
        }

        /// <summary>
        /// Láthgatósgi értékek beállítása
        /// </summary>
        /// <param name="sender">-</param>
        /// <param name="e">-</param>
        private void cbSteps_Checked(object sender, RoutedEventArgs e)
        {
            lSteps.Visibility = Visibility.Visible;
            tbSteps.Visibility = Visibility.Visible;
        }

        /// <summary>
        /// Láthgatósgi értékek beállítása
        /// </summary>
        /// <param name="sender">-</param>
        /// <param name="e">-</param>
        private void cbSteps_Unchecked(object sender, RoutedEventArgs e)
        {
            lSteps.Visibility = Visibility.Hidden;
            tbSteps.Visibility = Visibility.Hidden;
        }
    }
}
