class_name FdlSource
## C# (compiled by PowerShell's Add-Type, C# 5 compatible) for the incremental "FDL" patches.
##
## An FDL patch turns the previous release's exe into the new one: the new file is cut into
## the parts it shares with the old one (COPY old offset + length) and what is really new
## (INSERT bytes), gzip-compressed. Shared parts are found like rsync does: a rolling checksum
## over 2 KiB blocks of the old file, checked byte by byte, then extended as far as the bytes
## keep matching, so data that merely moved (a bigger script table shifts everything after it)
## still counts as shared. A SHA-256 of the result is stored and checked when applying.
##
## Used by tools/release.ps1 (Fdl.Create, which extracts this text) and by the updater's
## install script (Fdl.Apply, which needs no big buffer: streams old -> new).
## Format: "FDL1", int64 old size, int64 new size, 32-byte SHA-256 of the new file, then ops:
## 0 = COPY (int64 offset, int32 length), 1 = INSERT (int32 length, bytes), 2 = END.

const SOURCE := r"""
using System;
using System.IO;
using System.IO.Compression;
using System.Collections.Generic;
using System.Security.Cryptography;

public static class Fdl
{
    const int B = 2048;

    static uint Weak(byte[] d, int off)
    {
        uint a = 0, b = 0;
        for (int k = 0; k < B; k++)
        {
            a += d[off + k];
            b += (uint)(B - k) * d[off + k];
        }
        return ((b & 0xFFFF) << 16) | (a & 0xFFFF);
    }

    public static string Create(string oldPath, string newPath, string outPath)
    {
        byte[] o = File.ReadAllBytes(oldPath);
        byte[] n = File.ReadAllBytes(newPath);
        int nb = o.Length / B;
        Dictionary<uint, int> head = new Dictionary<uint, int>(nb);
        int[] next = new int[nb];
        for (int i = 0; i < nb; i++)
        {
            uint w = Weak(o, i * B);
            int h;
            next[i] = head.TryGetValue(w, out h) ? h : -1;
            head[w] = i;
        }
        byte[] sha = SHA256.Create().ComputeHash(n);
        long copied = 0, inserted = 0;
        using (FileStream fs = File.Create(outPath))
        using (GZipStream gz = new GZipStream(fs, CompressionLevel.Optimal))
        using (BinaryWriter bw = new BinaryWriter(gz))
        {
            bw.Write(new byte[] { (byte)'F', (byte)'D', (byte)'L', (byte)'1' });
            bw.Write((long)o.Length);
            bw.Write((long)n.Length);
            bw.Write(sha);
            long pOff = -1; int pLen = 0;
            int litStart = 0, pos = 0;
            int a = 0, bsum = 0;
            bool have = false;
            while (pos + B <= n.Length)
            {
                if (!have)
                {
                    uint w0 = Weak(n, pos);
                    a = (int)(w0 & 0xFFFF);
                    bsum = (int)(w0 >> 16);
                    have = true;
                }
                uint weak = (uint)((bsum << 16) | a);
                int cand;
                int found = -1;
                if (head.TryGetValue(weak, out cand))
                {
                    for (int j = cand; j >= 0; j = next[j])
                    {
                        int oo = j * B;
                        bool eq = true;
                        for (int k = 0; k < B; k++) { if (o[oo + k] != n[pos + k]) { eq = false; break; } }
                        if (eq) { found = j; break; }
                    }
                }
                if (found >= 0)
                {
                    long oo2 = (long)found * B;
                    int len = B;
                    while (pos + len < n.Length && oo2 + len < o.Length && o[oo2 + len] == n[pos + len]) len++;
                    // Literal bytes before the match.
                    if (pos > litStart)
                    {
                        if (pLen > 0) { bw.Write((byte)0); bw.Write(pOff); bw.Write(pLen); copied += pLen; pLen = 0; }
                        bw.Write((byte)1); bw.Write(pos - litStart); bw.Write(n, litStart, pos - litStart);
                        inserted += pos - litStart;
                    }
                    if (pLen > 0 && pOff + pLen == oo2) pLen += len;
                    else
                    {
                        if (pLen > 0) { bw.Write((byte)0); bw.Write(pOff); bw.Write(pLen); copied += pLen; }
                        pOff = oo2; pLen = len;
                    }
                    pos += len;
                    litStart = pos;
                    have = false;
                }
                else
                {
                    if (pos + B < n.Length)
                    {
                        int outb = n[pos], inb = n[pos + B];
                        a = (a - outb + inb) & 0xFFFF;
                        bsum = (bsum - B * outb + a) & 0xFFFF;
                    }
                    pos++;
                }
            }
            if (pLen > 0) { bw.Write((byte)0); bw.Write(pOff); bw.Write(pLen); copied += pLen; }
            if (n.Length > litStart)
            {
                bw.Write((byte)1); bw.Write(n.Length - litStart); bw.Write(n, litStart, n.Length - litStart);
                inserted += n.Length - litStart;
            }
            bw.Write((byte)2);
        }
        return "reutilise " + (copied / 1048576) + " Mo, nouveau " + (inserted / 1048576.0).ToString("0.0") + " Mo, patch " + (new FileInfo(outPath).Length / 1048576.0).ToString("0.0") + " Mo";
    }

    public static void Apply(string oldPath, string deltaPath, string outPath)
    {
        using (FileStream dfs = File.OpenRead(deltaPath))
        using (GZipStream gz = new GZipStream(dfs, CompressionMode.Decompress))
        using (BinaryReader br = new BinaryReader(gz))
        using (FileStream ofs = new FileStream(oldPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        using (FileStream nfs = new FileStream(outPath, FileMode.Create, FileAccess.Write))
        {
            byte[] magic = br.ReadBytes(4);
            if (magic.Length != 4 || magic[0] != 'F' || magic[1] != 'D' || magic[2] != 'L' || magic[3] != '1') throw new Exception("patch invalide");
            long oldLen = br.ReadInt64();
            long newLen = br.ReadInt64();
            byte[] want = br.ReadBytes(32);
            if (ofs.Length != oldLen) throw new Exception("le patch ne correspond pas a cette version");
            SHA256 sha = SHA256.Create();
            byte[] buf = new byte[1 << 20];
            long written = 0;
            while (true)
            {
                int t = br.ReadByte();
                if (t == 2) break;
                if (t == 0)
                {
                    long off = br.ReadInt64();
                    int len = br.ReadInt32();
                    ofs.Position = off;
                    while (len > 0)
                    {
                        int r = ofs.Read(buf, 0, Math.Min(buf.Length, len));
                        if (r <= 0) throw new Exception("lecture de l'ancienne version impossible");
                        nfs.Write(buf, 0, r);
                        sha.TransformBlock(buf, 0, r, null, 0);
                        len -= r; written += r;
                    }
                }
                else if (t == 1)
                {
                    int len = br.ReadInt32();
                    while (len > 0)
                    {
                        int r = br.Read(buf, 0, Math.Min(buf.Length, len));
                        if (r <= 0) throw new Exception("patch tronque");
                        nfs.Write(buf, 0, r);
                        sha.TransformBlock(buf, 0, r, null, 0);
                        len -= r; written += r;
                    }
                }
                else throw new Exception("patch corrompu");
            }
            sha.TransformFinalBlock(new byte[0], 0, 0);
            if (written != newLen) throw new Exception("taille finale inattendue");
            byte[] got = sha.Hash;
            for (int i = 0; i < 32; i++) if (got[i] != want[i]) throw new Exception("empreinte SHA-256 differente");
        }
    }
}
"""
