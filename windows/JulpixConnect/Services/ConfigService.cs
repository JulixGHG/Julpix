using System.IO;
using System.Security.Cryptography;
using System.Text.Json;

namespace JulpixConnect.Services;

public sealed class AppConfig
{
    public string PcName { get; set; } = Environment.MachineName;
    public int Port { get; set; } = 52840;
    public string Pin { get; set; } = GeneratePin();

    public static string GeneratePin()
    {
        return RandomNumberGenerator.GetInt32(100000, 999999).ToString();
    }
}

public sealed class ConfigService
{
    private static readonly string ConfigDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "JulpixConnect");

    private static readonly string ConfigPath = Path.Combine(ConfigDir, "config.json");

    public AppConfig Config { get; private set; } = new();

    public ConfigService()
    {
        Load();
    }

    public void Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                var json = File.ReadAllText(ConfigPath);
                var loaded = JsonSerializer.Deserialize<AppConfig>(json);
                if (loaded != null)
                {
                    if (string.IsNullOrWhiteSpace(loaded.Pin))
                        loaded.Pin = AppConfig.GeneratePin();
                    if (string.IsNullOrWhiteSpace(loaded.PcName))
                        loaded.PcName = Environment.MachineName;
                    if (loaded.Port <= 0 || loaded.Port > 65535)
                        loaded.Port = 52840;
                    Config = loaded;
                    return;
                }
            }
        }
        catch
        {
            // Fall back to defaults
        }

        Config = new AppConfig();
        Save();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(ConfigDir);
            var json = JsonSerializer.Serialize(Config, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(ConfigPath, json);
        }
        catch
        {
            // Ignore write errors
        }
    }

    public string RegeneratePin()
    {
        Config.Pin = AppConfig.GeneratePin();
        Save();
        return Config.Pin;
    }
}
