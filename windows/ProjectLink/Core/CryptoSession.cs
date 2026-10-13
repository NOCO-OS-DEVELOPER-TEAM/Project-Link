using System.Security.Cryptography;
using System.Text;

namespace ProjectLink.Core;

/// <summary>
/// Pairing token → AES-256-GCM session. Token is shown in QR; never leaves the LAN.
/// </summary>
public sealed class CryptoSession
{
    private readonly byte[] _key;

    public CryptoSession(byte[] key) => _key = key;

    public static byte[] CreateToken(int bytes = 32)
    {
        var t = new byte[bytes];
        RandomNumberGenerator.Fill(t);
        return t;
    }

    public static string ToB64Url(byte[] data) =>
        Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static byte[] FromB64Url(string s)
    {
        s = s.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        return Convert.FromBase64String(s);
    }

    public static CryptoSession FromToken(byte[] token, string pcId, string phoneId)
    {
        // HKDF-SHA256
        var salt = Encoding.UTF8.GetBytes("ProjectLink-v1");
        var info = Encoding.UTF8.GetBytes($"session|{pcId}|{phoneId}");
        Span<byte> prk = stackalloc byte[32];
        HMACSHA256.HashData(salt, token, prk);
        using var hmac = new HMACSHA256(prk.ToArray());
        var key = hmac.ComputeHash(info.Concat(new byte[] { 0x01 }).ToArray());
        return new CryptoSession(key[..32]);
    }

    public byte[] Encrypt(ReadOnlySpan<byte> plain)
    {
        var nonce = new byte[12];
        RandomNumberGenerator.Fill(nonce);
        var cipher = new byte[plain.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(_key, 16);
        aes.Encrypt(nonce, plain, cipher, tag);
        var outBuf = new byte[12 + 16 + cipher.Length];
        nonce.CopyTo(outBuf, 0);
        tag.CopyTo(outBuf, 12);
        cipher.CopyTo(outBuf, 28);
        return outBuf;
    }

    public byte[] Decrypt(ReadOnlySpan<byte> blob)
    {
        if (blob.Length < 28) throw new CryptographicException("short");
        var nonce = blob[..12];
        var tag = blob[12..28];
        var cipher = blob[28..];
        var plain = new byte[cipher.Length];
        using var aes = new AesGcm(_key, 16);
        aes.Decrypt(nonce, cipher, tag, plain);
        return plain;
    }

    public string TokenFingerprint(byte[] token)
    {
        var hash = SHA256.HashData(token);
        return Convert.ToHexString(hash[..8]);
    }
}
