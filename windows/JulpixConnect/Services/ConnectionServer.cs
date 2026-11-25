using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using JulpixConnect.Models;

namespace JulpixConnect.Services;

public sealed record ConnectedClientInfo(string Id, string DeviceName, string RemoteIp, DateTime ConnectedAt);

public sealed class ConnectionServer : IDisposable
{
    private const int DiscoveryPort = 52841;

    private readonly ConfigService _configService;
    private readonly HardwareStatsService _statsService;
    private readonly ConcurrentDictionary<string, (WebSocket Socket, ConnectedClientInfo Info)> _clients = new();

    private TcpListener? _tcpListener;
    private UdpClient? _udpDiscovery;
    private CancellationTokenSource? _cts;

    public event Action? ClientsChanged;
    public event Action<PcStatsPayload>? StatsUpdated;
    public event Action<string>? StatusMessage;

    public bool IsRunning { get; private set; }

    public ConnectionServer(ConfigService configService, HardwareStatsService statsService)
    {
        _configService = configService;
        _statsService = statsService;
    }

    public IReadOnlyList<ConnectedClientInfo> GetConnectedClients() =>
        _clients.Values.Select(v => v.Info).OrderBy(c => c.ConnectedAt).ToList();

    public void Start()
    {
        if (IsRunning) return;
        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        try
        {
            _tcpListener = new TcpListener(IPAddress.Any, _configService.Config.Port);
            _tcpListener.Start();
            IsRunning = true;
            StatusMessage?.Invoke($"Server läuft auf Port {_configService.Config.Port}");

            _ = Task.Run(() => AcceptTcpLoopAsync(token), token);
            _ = Task.Run(() => DiscoveryLoopAsync(token), token);
            _ = Task.Run(() => BroadcastStatsLoopAsync(token), token);
        }
        catch (Exception ex)
        {
            IsRunning = false;
            StatusMessage?.Invoke($"Fehler beim Start: {ex.Message}");
        }
    }

    public void Stop()
    {
        if (!IsRunning) return;
        IsRunning = false;
        _cts?.Cancel();

        try { _tcpListener?.Stop(); } catch { }
        try { _udpDiscovery?.Close(); } catch { }

        foreach (var kvp in _clients)
        {
            try { kvp.Value.Socket.Abort(); } catch { }
            kvp.Value.Socket.Dispose();
        }
        _clients.Clear();
        ClientsChanged?.Invoke();
        StatusMessage?.Invoke("Server gestoppt");
    }

    public async Task DisconnectClientAsync(string clientId)
    {
        if (_clients.TryRemove(clientId, out var entry))
        {
            try
            {
                if (entry.Socket.State == WebSocketState.Open)
                    await entry.Socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Disconnected by PC", CancellationToken.None);
            }
            catch { }
            entry.Socket.Dispose();
            ClientsChanged?.Invoke();
        }
    }

    private async Task AcceptTcpLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested && _tcpListener != null)
        {
            try
            {
                var tcpClient = await _tcpListener.AcceptTcpClientAsync(token);
                _ = Task.Run(() => HandleTcpClientAsync(tcpClient, token), token);
            }
            catch (OperationCanceledException) { break; }
            catch { }
        }
    }

    private async Task HandleTcpClientAsync(TcpClient tcpClient, CancellationToken token)
    {
        var remoteIp = (tcpClient.Client.RemoteEndPoint as IPEndPoint)?.Address.ToString() ?? "unknown";
        NetworkStream stream = tcpClient.GetStream();

        try
        {
            var buffer = new byte[8192];
            int bytesRead = await stream.ReadAsync(buffer, token);
            if (bytesRead <= 0)
            {
                tcpClient.Dispose();
                return;
            }

            var requestText = Encoding.UTF8.GetString(buffer, 0, bytesRead);
            var lines = requestText.Split("\r\n", StringSplitOptions.None);
            if (lines.Length == 0)
            {
                tcpClient.Dispose();
                return;
            }

            var requestLineParts = lines[0].Split(' ');
            var pathAndQuery = requestLineParts.Length >= 2 ? requestLineParts[1] : "/";

            if (Regex.IsMatch(requestText, @"Upgrade:\s*websocket", RegexOptions.IgnoreCase) &&
                pathAndQuery.StartsWith("/ws", StringComparison.OrdinalIgnoreCase))
            {
                var query = ParseQuery(pathAndQuery);
                query.TryGetValue("pin", out var pin);
                query.TryGetValue("device", out var deviceName);
                deviceName = string.IsNullOrWhiteSpace(deviceName) ? "iPhone" : Uri.UnescapeDataString(deviceName);

                if (!string.Equals(pin, _configService.Config.Pin, StringComparison.Ordinal))
                {
                    var forbidden = "HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nInvalid PIN";
                    await stream.WriteAsync(Encoding.UTF8.GetBytes(forbidden), token);
                    tcpClient.Dispose();
                    return;
                }

                var keyMatch = Regex.Match(requestText, @"Sec-WebSocket-Key:\s*(.+)", RegexOptions.IgnoreCase);
                if (!keyMatch.Success)
                {
                    tcpClient.Dispose();
                    return;
                }

                var wsKey = keyMatch.Groups[1].Value.Trim();
                var acceptKey = Convert.ToBase64String(
                    SHA1.HashData(Encoding.UTF8.GetBytes(wsKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));

                var handshake =
                    "HTTP/1.1 101 Switching Protocols\r\n" +
                    "Connection: Upgrade\r\n" +
                    "Upgrade: websocket\r\n" +
                    $"Sec-WebSocket-Accept: {acceptKey}\r\n\r\n";

                await stream.WriteAsync(Encoding.UTF8.GetBytes(handshake), token);

                using var webSocket = WebSocket.CreateFromStream(stream, isServer: true, subProtocol: null, keepAliveInterval: TimeSpan.FromSeconds(15));
                var clientId = Guid.NewGuid().ToString("N")[..8];
                var info = new ConnectedClientInfo(clientId, deviceName, remoteIp, DateTime.Now);
                _clients[clientId] = (webSocket, info);
                ClientsChanged?.Invoke();

                // Send immediate initial snapshot
                var initial = _statsService.Collect(_configService.Config.PcName);
                await SendJsonAsync(webSocket, initial, token);

                var recvBuffer = new byte[1024];
                while (webSocket.State == WebSocketState.Open && !token.IsCancellationRequested)
                {
                    var result = await webSocket.ReceiveAsync(recvBuffer, token);
                    if (result.MessageType == WebSocketMessageType.Close)
                        break;
                }

                _clients.TryRemove(clientId, out _);
                ClientsChanged?.Invoke();
            }
            else if (pathAndQuery.StartsWith("/health", StringComparison.OrdinalIgnoreCase))
            {
                var json = JsonSerializer.Serialize(new
                {
                    status = "ok",
                    app = "JulpixConnect",
                    name = _configService.Config.PcName,
                    port = _configService.Config.Port
                });
                var body = Encoding.UTF8.GetBytes(json);
                var header = $"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n";
                await stream.WriteAsync(Encoding.UTF8.GetBytes(header), token);
                await stream.WriteAsync(body, token);
                tcpClient.Dispose();
            }
            else
            {
                var body = Encoding.UTF8.GetBytes("JulpixConnect Windows Agent");
                var header = $"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n";
                await stream.WriteAsync(Encoding.UTF8.GetBytes(header), token);
                await stream.WriteAsync(body, token);
                tcpClient.Dispose();
            }
        }
        catch
        {
            tcpClient.Dispose();
        }
    }

    private async Task DiscoveryLoopAsync(CancellationToken token)
    {
        try
        {
            _udpDiscovery = new UdpClient(DiscoveryPort);
            _udpDiscovery.EnableBroadcast = true;

            while (!token.IsCancellationRequested)
            {
                var result = await _udpDiscovery.ReceiveAsync(token);
                var msg = Encoding.UTF8.GetString(result.Buffer).Trim();
                if (msg == "JULPIX_DISCOVER")
                {
                    var responseObj = new
                    {
                        app = "JulpixConnect",
                        name = _configService.Config.PcName,
                        ip = HardwareStatsService.GetPrimaryLocalIp(),
                        port = _configService.Config.Port
                    };
                    var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(responseObj));
                    await _udpDiscovery.SendAsync(bytes, bytes.Length, result.RemoteEndPoint);
                }
            }
        }
        catch (OperationCanceledException) { }
        catch
        {
            // Port may be in use by another instance
        }
    }

    private async Task BroadcastStatsLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                var payload = _statsService.Collect(_configService.Config.PcName);
                StatsUpdated?.Invoke(payload);

                if (!_clients.IsEmpty)
                {
                    var json = JsonSerializer.Serialize(payload);
                    var bytes = Encoding.UTF8.GetBytes(json);

                    foreach (var kvp in _clients.ToArray())
                    {
                        var ws = kvp.Value.Socket;
                        if (ws.State != WebSocketState.Open)
                        {
                            _clients.TryRemove(kvp.Key, out _);
                            ClientsChanged?.Invoke();
                            continue;
                        }

                        try
                        {
                            await ws.SendAsync(bytes, WebSocketMessageType.Text, true, token);
                        }
                        catch
                        {
                            _clients.TryRemove(kvp.Key, out _);
                            ClientsChanged?.Invoke();
                        }
                    }
                }
            }
            catch { }

            try
            {
                await Task.Delay(1000, token);
            }
            catch (OperationCanceledException) { break; }
        }
    }

    private static async Task SendJsonAsync(WebSocket ws, object obj, CancellationToken token)
    {
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(obj));
        await ws.SendAsync(bytes, WebSocketMessageType.Text, true, token);
    }

    private static Dictionary<string, string> ParseQuery(string pathAndQuery)
    {
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var qIndex = pathAndQuery.IndexOf('?');
        if (qIndex < 0 || qIndex >= pathAndQuery.Length - 1) return dict;

        var query = pathAndQuery[(qIndex + 1)..];
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var kv = pair.Split('=', 2);
            if (kv.Length == 2)
                dict[kv[0]] = kv[1];
        }
        return dict;
    }

    public void Dispose()
    {
        Stop();
    }
}
