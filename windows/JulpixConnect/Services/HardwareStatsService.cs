using System.Diagnostics;
using System.IO;
using System.Management;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using JulpixConnect.Models;
using LibreHardwareMonitor.Hardware;

namespace JulpixConnect.Services;

public sealed class HardwareStatsService : IDisposable
{
    private readonly Computer _computer;
    private readonly string _cpuName;
    private readonly string _gpuNameFallback;
    private readonly double? _gpuVramTotalFallbackMb;
    private readonly string _osName;
    private readonly int? _ramSpeedMhz;
    private readonly int _physicalCores;

    private PerformanceCounter? _cpuTotalCounter;
    private readonly List<PerformanceCounter> _cpuCoreCounters = new();
    private PerformanceCounter? _diskReadCounter;
    private PerformanceCounter? _diskWriteCounter;

    private long _lastBytesReceived;
    private long _lastBytesSent;
    private DateTime _lastNetSample = DateTime.MinValue;
    private string _activeAdapterName = "";
    private string _activeIp = "";

    private readonly Dictionary<int, (TimeSpan CpuTime, DateTime Timestamp)> _procPrev = new();

    public HardwareStatsService()
    {
        _computer = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMemoryEnabled = true,
            IsNetworkEnabled = false,
            IsStorageEnabled = false
        };

        try
        {
            _computer.Open();
        }
        catch
        {
            // May partially fail without admin; WMI & PerformanceCounter fallbacks handle it
        }

        _cpuName = QueryWmiString("SELECT Name FROM Win32_Processor", "Name") ?? "CPU";
        _physicalCores = QueryWmiInt("SELECT NumberOfCores FROM Win32_Processor", "NumberOfCores") ?? Environment.ProcessorCount;
        (_gpuNameFallback, _gpuVramTotalFallbackMb) = QueryGpuInfo();
        _osName = QueryWmiString("SELECT Caption FROM Win32_OperatingSystem", "Caption") ?? RuntimeInformation.OSDescription;
        _ramSpeedMhz = QueryWmiInt("SELECT Speed FROM Win32_PhysicalMemory", "Speed");

        InitPerformanceCounters();
    }

    private void InitPerformanceCounters()
    {
        try
        {
            _cpuTotalCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total", true);
            _cpuTotalCounter.NextValue();

            for (int i = 0; i < Environment.ProcessorCount; i++)
            {
                var c = new PerformanceCounter("Processor", "% Processor Time", i.ToString(), true);
                c.NextValue();
                _cpuCoreCounters.Add(c);
            }
        }
        catch
        {
            // Fallback to LibreHardwareMonitor
        }

        try
        {
            _diskReadCounter = new PerformanceCounter("PhysicalDisk", "Disk Read Bytes/sec", "_Total", true);
            _diskWriteCounter = new PerformanceCounter("PhysicalDisk", "Disk Write Bytes/sec", "_Total", true);
            _diskReadCounter.NextValue();
            _diskWriteCounter.NextValue();
        }
        catch
        {
            // Ignore
        }
    }

    public PcStatsPayload Collect(string customPcName)
    {
        var payload = new PcStatsPayload
        {
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            System = CollectSystem(customPcName),
            Cpu = CollectCpu(),
            Gpu = CollectGpu(),
            Memory = CollectMemory(),
            Network = CollectNetwork(),
            Disks = CollectDisks(),
            Processes = CollectTopProcesses()
        };

        return payload;
    }

    private SystemStats CollectSystem(string customPcName)
    {
        double? batteryPct = null;
        bool isCharging = false;

        try
        {
            var power = System.Windows.Forms.SystemInformation.PowerStatus;
            if (power.BatteryChargeStatus != BatteryChargeStatus.NoSystemBattery)
            {
                batteryPct = Math.Round(power.BatteryLifePercent * 100.0, 0);
                isCharging = power.PowerLineStatus == PowerLineStatus.Online;
            }
        }
        catch
        {
            // Desktop or unavailable
        }

        return new SystemStats
        {
            Hostname = string.IsNullOrWhiteSpace(customPcName) ? Environment.MachineName : customPcName,
            Os = _osName.Trim(),
            UptimeSeconds = Environment.TickCount64 / 1000,
            BatteryPercent = batteryPct,
            IsCharging = isCharging
        };
    }

    private CpuStats CollectCpu()
    {
        double totalUsage = 0;
        double? tempC = null;
        double? clockMhz = null;
        var perCore = new List<double>();
        string cpuName = _cpuName;

        try
        {
            foreach (var hw in _computer.Hardware)
            {
                if (hw.HardwareType != HardwareType.Cpu) continue;
                hw.Update();
                if (!string.IsNullOrWhiteSpace(hw.Name))
                    cpuName = hw.Name;

                var coreLoads = new List<(int idx, double val)>();
                var clocks = new List<double>();

                foreach (var sensor in hw.Sensors)
                {
                    if (sensor.Value is null) continue;
                    var val = (double)sensor.Value.Value;

                    if (sensor.SensorType == SensorType.Load && sensor.Name.Contains("Total", StringComparison.OrdinalIgnoreCase))
                    {
                        totalUsage = val;
                    }
                    else if (sensor.SensorType == SensorType.Load && sensor.Name.Contains("Core", StringComparison.OrdinalIgnoreCase))
                    {
                        coreLoads.Add((coreLoads.Count, val));
                    }
                    else if (sensor.SensorType == SensorType.Temperature &&
                             (sensor.Name.Contains("Package", StringComparison.OrdinalIgnoreCase) ||
                              sensor.Name.Contains("Tctl", StringComparison.OrdinalIgnoreCase) ||
                              sensor.Name.Contains("Core Average", StringComparison.OrdinalIgnoreCase) ||
                              tempC is null))
                    {
                        tempC = val;
                    }
                    else if (sensor.SensorType == SensorType.Clock && sensor.Name.Contains("Core", StringComparison.OrdinalIgnoreCase))
                    {
                        clocks.Add(val);
                    }
                }

                if (clocks.Count > 0)
                    clockMhz = Math.Round(clocks.Average(), 0);
                if (coreLoads.Count > 0)
                    perCore = coreLoads.Select(c => Math.Round(c.val, 1)).ToList();
            }
        }
        catch
        {
            // Ignore LHM errors
        }

        if (_cpuTotalCounter != null && totalUsage <= 0.01)
        {
            try
            {
                totalUsage = _cpuTotalCounter.NextValue();
            }
            catch { }
        }

        if (perCore.Count == 0 && _cpuCoreCounters.Count > 0)
        {
            foreach (var c in _cpuCoreCounters)
            {
                try { perCore.Add(Math.Round(c.NextValue(), 1)); }
                catch { perCore.Add(0); }
            }
        }

        return new CpuStats
        {
            Name = cpuName.Trim(),
            UsagePercent = Math.Round(Math.Clamp(totalUsage, 0, 100), 1),
            TemperatureC = tempC.HasValue ? Math.Round(tempC.Value, 1) : null,
            ClockMhz = clockMhz,
            Cores = _physicalCores,
            Threads = Environment.ProcessorCount,
            PerCorePercent = perCore
        };
    }

    private GpuStats CollectGpu()
    {
        string name = _gpuNameFallback;
        double? usage = null;
        double? temp = null;
        double? vramUsed = null;
        double? vramTotal = _gpuVramTotalFallbackMb;
        double? fan = null;
        double? clock = null;

        try
        {
            foreach (var hw in _computer.Hardware)
            {
                if (hw.HardwareType != HardwareType.GpuNvidia &&
                    hw.HardwareType != HardwareType.GpuAmd &&
                    hw.HardwareType != HardwareType.GpuIntel)
                    continue;

                hw.Update();
                if (!string.IsNullOrWhiteSpace(hw.Name))
                    name = hw.Name;

                foreach (var sensor in hw.Sensors)
                {
                    if (sensor.Value is null) continue;
                    var val = (double)sensor.Value.Value;

                    switch (sensor.SensorType)
                    {
                        case SensorType.Load when sensor.Name.Contains("Core", StringComparison.OrdinalIgnoreCase):
                            usage = val;
                            break;
                        case SensorType.Temperature when sensor.Name.Contains("Core", StringComparison.OrdinalIgnoreCase) || temp is null:
                            temp = val;
                            break;
                        case SensorType.SmallData when sensor.Name.Contains("Memory Used", StringComparison.OrdinalIgnoreCase):
                            vramUsed = Math.Round(val, 0);
                            break;
                        case SensorType.SmallData when sensor.Name.Contains("Memory Total", StringComparison.OrdinalIgnoreCase):
                            vramTotal = Math.Round(val, 0);
                            break;
                        case SensorType.Control when sensor.Name.Contains("Fan", StringComparison.OrdinalIgnoreCase):
                            fan = Math.Round(val, 1);
                            break;
                        case SensorType.Clock when sensor.Name.Contains("Core", StringComparison.OrdinalIgnoreCase):
                            clock = Math.Round(val, 0);
                            break;
                    }
                }

                break; // Primary discrete/active GPU first
            }
        }
        catch
        {
            // Ignore
        }

        return new GpuStats
        {
            Name = name.Trim(),
            UsagePercent = usage.HasValue ? Math.Round(Math.Clamp(usage.Value, 0, 100), 1) : null,
            TemperatureC = temp.HasValue ? Math.Round(temp.Value, 1) : null,
            VramUsedMb = vramUsed,
            VramTotalMb = vramTotal,
            FanPercent = fan,
            ClockMhz = clock
        };
    }

    private MemoryStats CollectMemory()
    {
        var mem = new MEMORYSTATUSEX();
        mem.dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>();
        if (GlobalMemoryStatusEx(ref mem))
        {
            double totalGb = mem.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
            double availGb = mem.ullAvailPhys / (1024.0 * 1024.0 * 1024.0);
            double usedGb = totalGb - availGb;
            double pct = totalGb > 0 ? (usedGb / totalGb) * 100.0 : 0;

            return new MemoryStats
            {
                TotalGb = Math.Round(totalGb, 2),
                AvailableGb = Math.Round(availGb, 2),
                UsedGb = Math.Round(usedGb, 2),
                UsagePercent = Math.Round(pct, 1),
                SpeedMhz = _ramSpeedMhz
            };
        }

        return new MemoryStats();
    }

    private NetworkStats CollectNetwork()
    {
        try
        {
            var interfaces = NetworkInterface.GetAllNetworkInterfaces()
                .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                            n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                            n.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
                .ToList();

            var primary = interfaces
                .OrderByDescending(n => n.GetIPv4Statistics().BytesReceived)
                .FirstOrDefault();

            if (primary != null)
            {
                var stats = primary.GetIPv4Statistics();
                var now = DateTime.UtcNow;
                double dlKbps = 0;
                double ulKbps = 0;

                if (_lastNetSample != DateTime.MinValue)
                {
                    var elapsed = (now - _lastNetSample).TotalSeconds;
                    if (elapsed > 0.1)
                    {
                        var rxDiff = Math.Max(0, stats.BytesReceived - _lastBytesReceived);
                        var txDiff = Math.Max(0, stats.BytesSent - _lastBytesSent);
                        dlKbps = Math.Round((rxDiff / 1024.0) / elapsed, 1);
                        ulKbps = Math.Round((txDiff / 1024.0) / elapsed, 1);
                    }
                }

                _lastBytesReceived = stats.BytesReceived;
                _lastBytesSent = stats.BytesSent;
                _lastNetSample = now;
                _activeAdapterName = primary.Name;
                _activeIp = primary.GetIPProperties().UnicastAddresses
                    .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork)?.Address.ToString() ?? "";

                return new NetworkStats
                {
                    AdapterName = _activeAdapterName,
                    IpAddress = _activeIp,
                    DownloadKbps = dlKbps,
                    UploadKbps = ulKbps
                };
            }
        }
        catch { }

        return new NetworkStats
        {
            AdapterName = _activeAdapterName,
            IpAddress = _activeIp
        };
    }

    private List<DiskStats> CollectDisks()
    {
        var list = new List<DiskStats>();
        double totalReadKbps = 0;
        double totalWriteKbps = 0;

        try
        {
            if (_diskReadCounter != null) totalReadKbps = Math.Round(_diskReadCounter.NextValue() / 1024.0, 1);
            if (_diskWriteCounter != null) totalWriteKbps = Math.Round(_diskWriteCounter.NextValue() / 1024.0, 1);
        }
        catch { }

        try
        {
            foreach (var drive in DriveInfo.GetDrives().Where(d => d.IsReady && d.DriveType == DriveType.Fixed))
            {
                double totalGb = drive.TotalSize / (1024.0 * 1024.0 * 1024.0);
                double freeGb = drive.AvailableFreeSpace / (1024.0 * 1024.0 * 1024.0);
                double usedGb = totalGb - freeGb;
                double pct = totalGb > 0 ? (usedGb / totalGb) * 100.0 : 0;

                list.Add(new DiskStats
                {
                    Name = drive.Name.TrimEnd('\\'),
                    Label = string.IsNullOrWhiteSpace(drive.VolumeLabel) ? "Local Disk" : drive.VolumeLabel,
                    UsedGb = Math.Round(usedGb, 1),
                    TotalGb = Math.Round(totalGb, 1),
                    UsagePercent = Math.Round(pct, 1),
                    ReadKbps = list.Count == 0 ? totalReadKbps : 0,
                    WriteKbps = list.Count == 0 ? totalWriteKbps : 0
                });
            }
        }
        catch { }

        return list;
    }

    private List<ProcessStats> CollectTopProcesses()
    {
        var results = new List<ProcessStats>();
        var now = DateTime.UtcNow;
        var seenPids = new HashSet<int>();

        try
        {
            foreach (var proc in Process.GetProcesses())
            {
                try
                {
                    int pid = proc.Id;
                    if (pid <= 4) continue;
                    seenPids.Add(pid);

                    var cpuTime = proc.TotalProcessorTime;
                    double cpuPct = 0;

                    if (_procPrev.TryGetValue(pid, out var prev))
                    {
                        var elapsedMs = (now - prev.Timestamp).TotalMilliseconds;
                        if (elapsedMs > 100)
                        {
                            var cpuUsedMs = (cpuTime - prev.CpuTime).TotalMilliseconds;
                            cpuPct = Math.Clamp((cpuUsedMs / (elapsedMs * Environment.ProcessorCount)) * 100.0, 0, 100);
                        }
                    }

                    _procPrev[pid] = (cpuTime, now);

                    results.Add(new ProcessStats
                    {
                        Name = proc.ProcessName,
                        Pid = pid,
                        CpuPercent = Math.Round(cpuPct, 1),
                        MemoryMb = Math.Round(proc.WorkingSet64 / (1024.0 * 1024.0), 1)
                    });
                }
                catch
                {
                    // Access denied for protected system processes
                }
                finally
                {
                    proc.Dispose();
                }
            }

            foreach (var deadPid in _procPrev.Keys.Where(k => !seenPids.Contains(k)).ToList())
                _procPrev.Remove(deadPid);
        }
        catch { }

        return results
            .OrderByDescending(p => p.CpuPercent)
            .ThenByDescending(p => p.MemoryMb)
            .Take(8)
            .ToList();
    }

    public static string GetPrimaryLocalIp()
    {
        try
        {
            using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0);
            socket.Connect("8.8.8.8", 65530);
            if (socket.LocalEndPoint is System.Net.IPEndPoint endPoint)
                return endPoint.Address.ToString();
        }
        catch { }

        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n => n.GetIPProperties().UnicastAddresses)
            .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork)?.Address.ToString() ?? "127.0.0.1";
    }

    private static string? QueryWmiString(string query, string prop)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(query);
            foreach (var obj in searcher.Get())
                return obj[prop]?.ToString();
        }
        catch { }
        return null;
    }

    private static int? QueryWmiInt(string query, string prop)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(query);
            foreach (var obj in searcher.Get())
            {
                if (obj[prop] != null && int.TryParse(obj[prop].ToString(), out int val))
                    return val;
            }
        }
        catch { }
        return null;
    }

    private static (string Name, double? VramMb) QueryGpuInfo()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name, AdapterRAM FROM Win32_VideoController");
            foreach (var obj in searcher.Get())
            {
                var name = obj["Name"]?.ToString();
                if (string.IsNullOrWhiteSpace(name)) continue;
                double? vram = null;
                if (obj["AdapterRAM"] != null && ulong.TryParse(obj["AdapterRAM"].ToString(), out ulong bytes) && bytes > 0)
                    vram = Math.Round(bytes / (1024.0 * 1024.0), 0);
                return (name, vram);
            }
        }
        catch { }
        return ("GPU", null);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    public void Dispose()
    {
        _cpuTotalCounter?.Dispose();
        foreach (var c in _cpuCoreCounters) c.Dispose();
        _diskReadCounter?.Dispose();
        _diskWriteCounter?.Dispose();
        try { _computer.Close(); } catch { }
    }
}
