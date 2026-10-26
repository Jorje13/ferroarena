# Builds the recorded SFX for FerroArena from the CC0 downloads (trim, fades, loudness, mixes).
import subprocess, numpy as np, os, wave
D = "E:/Godot/FerroArena/downloads"; A = D + "/audio4"; O = "E:/Godot/FerroArena/ferro-arena/assets/audio"
SR = 44100
ZY = D + "/zombie_sfx/b/Voice Effects Zombie-Skeleton-Monster Human Male/"
K = A + "/x_kenney_impact/Audio/"; KI = A + "/x_kenney_interface/Audio/"; R = A + "/extra/x_RPGsounds_Kenney/OGG/"
SW = A + "/extra/x_swishes/swishes/"; BF = A + "/x_sfx_breaking_and_falling/"; CR = A + "/x_80-CC0-creature-SFX_0/"

def load(p):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", p, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True).stdout
    a = np.frombuffer(raw, np.float32).copy()
    assert a.size, p
    return a

def onset(a, thr=0.08):
    i = np.argmax(np.abs(a) > thr * np.abs(a).max())
    return max(0, i - int(0.01 * SR))

def cut(a, start=None, dur=None, fade_in=0.004, fade_out=0.08):
    s = onset(a) if start is None else int(start * SR)
    a = a[s:] if dur is None else a[s:s + int(dur * SR)]
    a = a.copy()
    n = min(int(fade_in * SR), a.size); a[:n] *= np.linspace(0, 1, n)
    n = min(int(fade_out * SR), a.size); a[-n:] *= np.linspace(1, 0, n)
    return a

def norm(a, peak_db=-1.0):
    return a / (np.abs(a).max() + 1e-9) * 10 ** (peak_db / 20)

def mix(*layers):  # (signal, delay s, gain)
    n = max(int(d * SR) + s.size for s, d, g in layers)
    out = np.zeros(n, np.float32)
    for s, d, g in layers:
        i = int(d * SR); out[i:i + s.size] += s * g
    return out

def save(a, rel, peak_db=-1.0):
    p = O + "/" + rel; os.makedirs(os.path.dirname(p), exist_ok=True)
    a = norm(a, peak_db)
    tmp = p + ".tmp.wav"
    w = wave.open(tmp, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes()); w.close()
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "6", p], check=True)
    os.remove(tmp); print("%-34s %.2fs" % (rel, a.size / SR))

def lowpass(a, hz):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-af", "lowpass=f=%d,lowpass=f=%d,highpass=f=90" % (hz, hz), "-f", "f32le", "-"], input=a.astype(np.float32).tobytes(), capture_output=True).stdout
    return np.frombuffer(raw, np.float32).copy()

# ---- monsters
# Jumper leap: the loudest burst of the zombie yells (real voice), short and sharp.
for i, n in enumerate([1, 2, 3, 5, 9]):
    a = load(ZY + "zombieYell%d.wav" % n)
    env = np.convolve(np.abs(a), np.ones(2205) / 2205, "same")
    pk = int(np.argmax(env)); s = max(0, pk - int(0.18 * SR))
    save(cut(a, s / SR, 0.75, 0.01, 0.25), "zombie/leap_%d.ogg" % (i + 1))
for i, n in enumerate([3, 4, 6, 7, 8, 9]):
    save(cut(load(SW + "swish-%d.wav" % n), None, None, 0.002, 0.04), "monsters/swipe_%d.ogg" % (i + 1))
# Body slamming the ground (jumper landing, brute slam): heavy soft impact + a little grit.
for i in range(4):
    body = cut(load(K + "impactSoft_heavy_%03d.ogg" % i), None, 0.6, 0.002, 0.15)
    grit = cut(load(BF + "bfh1_hit_%02d.ogg" % (i % 3 + 1)), None, 0.45, 0.002, 0.2)
    save(mix((body, 0, 1.0), (grit, 0.015, 0.35)), "monsters/slam_%d.ogg" % (i + 1))
save(cut(load(CR + "howl.ogg"), None, None, 0.01, 0.2), "zombie/howl_1.ogg")

# ---- player body
for i in range(5):
    save(cut(load(K + "impactPunch_medium_%03d.ogg" % i), None, 0.4, 0.002, 0.1), "foley/hurt_%d.ogg" % (i + 1))
    save(cut(load(K + "impactPunch_heavy_%03d.ogg" % i), None, 0.45, 0.002, 0.12), "impacts/flesh_%d.ogg" % (i + 1))
    save(cut(load(K + "impactSoft_medium_%03d.ogg" % i), None, 0.4, 0.002, 0.1), "impacts/soft_%d.ogg" % (i + 1))
    save(cut(load(K + "impactMetal_light_%03d.ogg" % i), None, 0.5, 0.002, 0.15), "foley/clink_%d.ogg" % (i + 1), -4.0)
# Landing: boots + body (recorded jump landings), plus a soft thud underneath.
for i, f in enumerate(["Jump_1.wav", "Jump_2.wav", "Jump_3.wav", "jumpland.wav"]):
    a = cut(load(A + "/extra/" + f), None, 0.4, 0.002, 0.12)
    save(mix((a, 0, 1.0), (cut(load(K + "impactSoft_medium_%03d.ogg" % i), None, 0.3), 0.0, 0.3)), "foley/land_%d.ogg" % (i + 1))
cloth = [cut(load(R + "cloth%d.ogg" % n), None, None, 0.005, 0.06) for n in range(1, 5)]
# Roll: fabric rustle, shoulder hitting the ground, then the hips.
for i in range(3):
    save(mix((cloth[i], 0, 0.8), (cut(load(K + "impactSoft_medium_%03d.ogg" % i), None, 0.3), 0.06, 0.9),
        (cut(load(K + "impactSoft_medium_%03d.ogg" % (i + 2)), None, 0.3), 0.26, 0.6), (cloth[(i + 1) % 4], 0.22, 0.5)), "foley/roll_%d.ogg" % (i + 1))
# Mantle: hands slapping the ledge, gear and fabric as the body comes up.
for i in range(3):
    save(mix((cut(load(K + "impactSoft_medium_%03d.ogg" % (i + 1)), None, 0.3), 0, 0.9), (cut(load(K + "impactPunch_medium_%03d.ogg" % i), None, 0.3), 0.07, 0.35),
        (cut(load(R + "clothBelt%s.ogg" % ("" if i % 2 == 0 else "2")), None, None), 0.12, 0.7)), "foley/mantle_%d.ogg" % (i + 1))
# Knocked down: body hitting the ground with its gear.
for i in range(2):
    save(mix((cut(load(K + "impactSoft_heavy_%03d.ogg" % (i + 2)), None, 0.6), 0, 1.0), (cut(load(R + "dropLeather.ogg"), None, None), 0.03, 0.6),
        (cut(load(K + "impactMetal_light_%03d.ogg" % (i + 1)), None, 0.3), 0.08, 0.25)), "foley/knock_%d.ogg" % (i + 1))
# Bandage: unwrapping and wrapping fabric.
save(mix((cloth[0], 0, 1.0), (cloth[2], 0.35, 0.9), (cut(load(R + "handleSmallLeather.ogg"), None, None), 0.7, 0.7), (cloth[3], 1.0, 0.8)), "foley/bandage_1.ogg")
save(mix((cloth[1], 0, 1.0), (cut(load(R + "handleSmallLeather2.ogg"), None, None), 0.3, 0.7), (cloth[2], 0.65, 0.9)), "foley/bandage_2.ogg")
for i in range(4):
    save(cloth[i], "foley/cloth_%d.ogg" % (i + 1))
save(mix((cut(load(R + "metalLatch.ogg"), None, None), 0, 1.0), (cut(load(R + "metalClick.ogg"), None, None), 0.18, 0.8)), "foley/attach_stock.ogg")
save(mix((cut(load(R + "drawKnife1.ogg"), None, None), 0, 0.6), (cut(load(R + "metalClick.ogg"), None, None), 0.35, 0.9)), "foley/attach_silencer.ogg")
save(cut(load(A + "/extra/heartbeat_single.flac"), None, 0.7, 0.002, 0.25), "foley/heartbeat.ogg")
# Kill cam: one pass of the recorded air whoosh, the next pass softer for the way out.
wh = load(A + "/extra/whoosh2_0.wav")
save(cut(wh, 0.0, 1.05, 0.05, 0.3), "foley/whoosh_in.ogg", -3.0)
save(cut(wh, 1.05, 1.05, 0.05, 0.3), "foley/whoosh_out.ogg", -6.0)
for i, n in enumerate([1, 2, 3, 7]):
    save(cut(load(BF + "bfh1_falling_%02d.ogg" % n), None, 1.1, 0.01, 0.3), "explosions/debris_%d.ogg" % (i + 1))
# Suppressed shot: the real report through a can (no supersonic crack, low thump and gas puff).
shot = load(O + "/weapons/ferro_shot_near.wav")
save(cut(lowpass(shot, 700), None, 0.55, 0.001, 0.25), "weapons/ferro_shot_suppressed.ogg")
save(cut(load(KI + "select_001.ogg"), None, None, 0.001, 0.02), "foley/ui_click.ogg", -3.0)
