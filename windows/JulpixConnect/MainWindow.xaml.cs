using System.Drawing;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Media.Imaging;
using JulpixConnect.Models;
using JulpixConnect.Services;
using QRCoder;

namespace JulpixConnect;

public partial class MainWindow : Window
{
    private readonly ConfigService _configService = new();
    private readonly HardwareStatsService _statsService = new();
    private readonly ConnectionServer _server;
    private NotifyIcon? _trayIcon;
    private bool _isClosingForReal;

    public MainWindow()
    {
        InitializeComponent();

        _server = new ConnectionServer(_configService, _statsService);
        _server.ClientsChanged += () => Dispatcher.Invoke(RefreshClients);
        _server.StatsUpdated += payload => Dispatcher.Invoke(() => UpdateStatsPreview(payload));
        _server.StatusMessage += msg => Dispatcher.Invoke(() => StatusText.Text = msg);

        SetupTrayIcon();
        LoadPairingUi();
        _server.Start();
    }

    private void SetupTrayIcon()
    {
        _trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "JulpixConnect",
            Visible = true
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add("Öffnen", null, (_, _) => ShowFromTray());
        menu.Items.Add("Beenden", null, (_, _) =>
        {
            _isClosingForReal = true;
            Close();
        });
        _trayIcon.ContextMenuStrip = menu;
        _trayIcon.DoubleClick += (_, _) => ShowFromTray();
    }

    private void ShowFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void LoadPairingUi()
    {
        var ip = HardwareStatsService.GetPrimaryLocalIp();
        PcNameBox.Text = _configService.Config.PcName;
        IpText.Text = ip;
        PortText.Text = _configService.Config.Port.ToString();
        PinText.Text = _configService.Config.Pin;

        var qrPayload = JsonSerializer.Serialize(new
        {
            app = "JulpixConnect",
            name = _configService.Config.PcName,
            ip,
            port = _configService.Config.Port,
            pin = _configService.Config.Pin
        });

        using var generator = new QRCodeGenerator();
        using var data = generator.CreateQrCode(qrPayload, QRCodeGenerator.ECCLevel.M);
        using var pngQr = new PngByteQRCode(data);
        var bytes = pngQr.GetGraphic(10);

        using var ms = new MemoryStream(bytes);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = ms;
        bitmap.EndInit();
        bitmap.Freeze();

        QrImage.Source = bitmap;
    }

    private void UpdateStatsPreview(PcStatsPayload stats)
    {
        CpuPreview.Text = $"{stats.Cpu.UsagePercent:0.0} %";
        var cpuTemp = stats.Cpu.TemperatureC.HasValue ? $" • {stats.Cpu.TemperatureC:0}°C" : "";
        CpuSubPreview.Text = $"{stats.Cpu.Name}{cpuTemp}";

        GpuPreview.Text = stats.Gpu.UsagePercent.HasValue ? $"{stats.Gpu.UsagePercent:0.0} %" : "Aktiv";
        var gpuTemp = stats.Gpu.TemperatureC.HasValue ? $" • {stats.Gpu.TemperatureC:0}°C" : "";
        GpuSubPreview.Text = $"{stats.Gpu.Name}{gpuTemp}";

        RamPreview.Text = $"{stats.Memory.UsagePercent:0.0} %";
        RamSubPreview.Text = $"{stats.Memory.UsedGb:0.0} / {stats.Memory.TotalGb:0.0} GB";

        NetPreview.Text = $"↓ {FormatRate(stats.Network.DownloadKbps)}  ↑ {FormatRate(stats.Network.UploadKbps)}";
        NetSubPreview.Text = stats.Network.AdapterName;
    }

    private static string FormatRate(double kbps) =>
        kbps >= 1024 ? $"{kbps / 1024.0:0.0} MB/s" : $"{kbps:0} KB/s";

    private void RefreshClients()
    {
        var clients = _server.GetConnectedClients();
        ClientsList.ItemsSource = clients;
        NoClientsHint.Visibility = clients.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SavePcName_Click(object sender, RoutedEventArgs e)
    {
        var name = PcNameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name)) return;
        _configService.Config.PcName = name;
        _configService.Save();
        LoadPairingUi();
    }

    private void RegeneratePin_Click(object sender, RoutedEventArgs e)
    {
        _configService.RegeneratePin();
        LoadPairingUi();
    }

    private async void DisconnectClient_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn && btn.Tag is string id)
        {
            await _server.DisconnectClientAsync(id);
        }
    }

    private void MinimizeToTray_Click(object sender, RoutedEventArgs e)
    {
        Hide();
    }

    private void OpenFirewall_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var port = _configService.Config.Port;
            var cmd = $"netsh advfirewall firewall delete rule name=\"JulpixConnect\" & " +
                      $"netsh advfirewall firewall add rule name=\"JulpixConnect\" dir=in action=allow protocol=TCP localport={port} & " +
                      $"netsh advfirewall firewall add rule name=\"JulpixConnect\" dir=in action=allow protocol=UDP localport=52841";

            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/c {cmd}",
                Verb = "runas",
                UseShellExecute = true,
                CreateNoWindow = true
            };
            var proc = System.Diagnostics.Process.Start(psi);
            proc?.WaitForExit(5000);
            System.Windows.MessageBox.Show($"Firewall-Regel für Port {port} (TCP) und 52841 (UDP) wurde hinzugefügt.", "JulpixConnect", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show($"Firewall-Freigabe abgebrochen oder fehlgeschlagen: {ex.Message}", "JulpixConnect", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!_isClosingForReal)
        {
            e.Cancel = true;
            Hide();
            return;
        }

        _server.Dispose();
        _statsService.Dispose();
        if (_trayIcon != null)
        {
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
        }
        base.OnClosing(e);
    }
}
