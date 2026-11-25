using System.IO;
using System.Windows;

namespace JulpixConnect;

public partial class App : System.Windows.Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += (_, args) =>
        {
            var msg = args.Exception.ToString();
            try
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JulpixConnect");
                Directory.CreateDirectory(dir);
                File.WriteAllText(Path.Combine(dir, "error.log"), msg);
            }
            catch { }
            System.Windows.MessageBox.Show(args.Exception.Message, "JulpixConnect Fehler", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
        base.OnStartup(e);
    }
}
