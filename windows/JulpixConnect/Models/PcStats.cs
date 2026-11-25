using System.Text.Json.Serialization;

namespace JulpixConnect.Models;

public sealed class PcStatsPayload
{
    [JsonPropertyName("type")]
    public string Type { get; set; } = "stats";

    [JsonPropertyName("timestamp")]
    public long Timestamp { get; set; }

    [JsonPropertyName("system")]
    public SystemStats System { get; set; } = new();

    [JsonPropertyName("cpu")]
    public CpuStats Cpu { get; set; } = new();

    [JsonPropertyName("gpu")]
    public GpuStats Gpu { get; set; } = new();

    [JsonPropertyName("memory")]
    public MemoryStats Memory { get; set; } = new();

    [JsonPropertyName("network")]
    public NetworkStats Network { get; set; } = new();

    [JsonPropertyName("disks")]
    public List<DiskStats> Disks { get; set; } = new();

    [JsonPropertyName("processes")]
    public List<ProcessStats> Processes { get; set; } = new();
}

public sealed class SystemStats
{
    [JsonPropertyName("hostname")]
    public string Hostname { get; set; } = Environment.MachineName;

    [JsonPropertyName("os")]
    public string Os { get; set; } = "";

    [JsonPropertyName("uptimeSeconds")]
    public long UptimeSeconds { get; set; }

    [JsonPropertyName("batteryPercent")]
    public double? BatteryPercent { get; set; }

    [JsonPropertyName("isCharging")]
    public bool IsCharging { get; set; }
}

public sealed class CpuStats
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "CPU";

    [JsonPropertyName("usagePercent")]
    public double UsagePercent { get; set; }

    [JsonPropertyName("temperatureC")]
    public double? TemperatureC { get; set; }

    [JsonPropertyName("clockMhz")]
    public double? ClockMhz { get; set; }

    [JsonPropertyName("cores")]
    public int Cores { get; set; }

    [JsonPropertyName("threads")]
    public int Threads { get; set; }

    [JsonPropertyName("perCorePercent")]
    public List<double> PerCorePercent { get; set; } = new();
}

public sealed class GpuStats
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "GPU";

    [JsonPropertyName("usagePercent")]
    public double? UsagePercent { get; set; }

    [JsonPropertyName("temperatureC")]
    public double? TemperatureC { get; set; }

    [JsonPropertyName("vramUsedMb")]
    public double? VramUsedMb { get; set; }

    [JsonPropertyName("vramTotalMb")]
    public double? VramTotalMb { get; set; }

    [JsonPropertyName("fanPercent")]
    public double? FanPercent { get; set; }

    [JsonPropertyName("clockMhz")]
    public double? ClockMhz { get; set; }
}

public sealed class MemoryStats
{
    [JsonPropertyName("usedGb")]
    public double UsedGb { get; set; }

    [JsonPropertyName("totalGb")]
    public double TotalGb { get; set; }

    [JsonPropertyName("availableGb")]
    public double AvailableGb { get; set; }

    [JsonPropertyName("usagePercent")]
    public double UsagePercent { get; set; }

    [JsonPropertyName("speedMhz")]
    public int? SpeedMhz { get; set; }
}

public sealed class NetworkStats
{
    [JsonPropertyName("adapterName")]
    public string AdapterName { get; set; } = "";

    [JsonPropertyName("ipAddress")]
    public string IpAddress { get; set; } = "";

    [JsonPropertyName("downloadKbps")]
    public double DownloadKbps { get; set; }

    [JsonPropertyName("uploadKbps")]
    public double UploadKbps { get; set; }
}

public sealed class DiskStats
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("label")]
    public string Label { get; set; } = "";

    [JsonPropertyName("usedGb")]
    public double UsedGb { get; set; }

    [JsonPropertyName("totalGb")]
    public double TotalGb { get; set; }

    [JsonPropertyName("usagePercent")]
    public double UsagePercent { get; set; }

    [JsonPropertyName("readKbps")]
    public double ReadKbps { get; set; }

    [JsonPropertyName("writeKbps")]
    public double WriteKbps { get; set; }
}

public sealed class ProcessStats
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("pid")]
    public int Pid { get; set; }

    [JsonPropertyName("cpuPercent")]
    public double CpuPercent { get; set; }

    [JsonPropertyName("memoryMb")]
    public double MemoryMb { get; set; }
}
