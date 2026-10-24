# Renders Ember's sound effects as 44.1 kHz 16-bit mono WAVs into Ember/Resources/Sounds.
# Standard library only. The same files are used in the app and as notification sounds
# (iOS wants notification sounds under 30 s).
# usage: python tools/make_sounds.py [out_dir]
import math
import os
import random
import struct
import sys
import wave

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "Ember", "Resources", "Sounds")

# partials: (frequency ratio, amplitude, decay time constant in seconds)
BELL = [(1.0, 1.0, 0.9), (2.0, 0.35, 0.5), (3.0, 0.15, 0.3), (4.2, 0.08, 0.18)]
CHIME = [(1.0, 1.0, 1.2), (2.76, 0.30, 0.45), (5.40, 0.10, 0.2), (0.5, 0.12, 1.5)]
MARIMBA = [(1.0, 1.0, 0.35), (3.99, 0.22, 0.07), (9.9, 0.06, 0.025)]
WOOD = [(1.0, 1.0, 0.03), (2.7, 0.35, 0.012), (5.1, 0.12, 0.006)]
SOFT = [(1.0, 1.0, 0.5), (2.0, 0.2, 0.3)]
WARM = [(float(n), 1.0 / n, 1.6) for n in range(1, 7)]


def note(freq, dur, partials, attack=0.004, glide=0.0, vibrato=None):
    """A tone made of decaying partials. glide bends the pitch by that many semitones over the
    note; vibrato is (rate Hz, depth as a fraction of the frequency)."""
    n = int(dur * SR)
    out = [0.0] * n
    for ratio, amp, decay in partials:
        f = freq * ratio
        if f >= SR / 2 - 1000:
            continue
        k = math.exp(-1.0 / (decay * SR))
        env = amp
        phase = 0.0
        step = 2 * math.pi * f / SR
        for i in range(n):
            s = step
            if glide:
                s *= 2 ** (glide * i / n / 12)
            if vibrato:
                s *= 1 + vibrato[1] * math.sin(2 * math.pi * vibrato[0] * i / SR)
            phase += s
            out[i] += env * math.sin(phase)
            env *= k
    a = max(1, int(attack * SR))
    for i in range(min(a, n)):
        out[i] *= i / a
    # raised-cosine release over the last third, so a note never stops while still ringing
    r = max(1, n // 3)
    for i in range(r):
        out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / r)
    return out


def noise(dur, f0, f1, attack, release, seed=1):
    """White noise through a one-pole low-pass whose cutoff sweeps from f0 to f1 Hz."""
    rnd = random.Random(seed)
    n = int(dur * SR)
    out = [0.0] * n
    y = 0.0
    for i in range(n):
        fc = f0 * (f1 / f0) ** (i / n)
        a = 1 - math.exp(-2 * math.pi * fc / SR)
        y += a * (rnd.uniform(-1, 1) - y)
        t = i / SR
        env = t / attack if t < attack else math.exp(-(t - attack) / release)
        out[i] = y * env
    return out


def sweep(f0, f1, dur, decay):
    """A sine whose pitch falls (or rises) exponentially from f0 to f1: pops and thumps."""
    n = int(dur * SR)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        f = f0 * (f1 / f0) ** (i / n)
        phase += 2 * math.pi * f / SR
        out[i] = math.sin(phase) * math.exp(-i / (decay * SR))
    return out


def mix(parts):
    """parts: (start seconds, samples, gain)."""
    out = []
    for at, sig, gain in parts:
        off = int(at * SR)
        if len(out) < off + len(sig):
            out.extend([0.0] * (off + len(sig) - len(out)))
        for i, v in enumerate(sig):
            out[off + i] += v * gain
    return out


def reverb(x, wet=0.2, room=1.0, tail=1.2):
    """A small Schroeder reverb: four combs into two all-passes."""
    x = x + [0.0] * int(tail * SR)
    n = len(x)
    acc = [0.0] * n
    for delay, g in ((0.0297, 0.78), (0.0371, 0.76), (0.0411, 0.74), (0.0437, 0.72)):
        d = int(delay * room * SR)
        buf = [0.0] * d
        j = 0
        for i in range(n):
            y = buf[j]
            buf[j] = x[i] + y * g
            j = (j + 1) % d
            acc[i] += y
    for delay, g in ((0.005, 0.7), (0.0017, 0.7)):
        d = int(delay * SR)
        buf = [0.0] * d
        j = 0
        for i in range(n):
            b = buf[j]
            y = -g * acc[i] + b
            buf[j] = acc[i] + g * y
            j = (j + 1) % d
            acc[i] = y
    return [x[i] + wet * 0.25 * acc[i] for i in range(n)]


def finish(sig, peak_db):
    top = max(abs(v) for v in sig) or 1.0
    scale = 10 ** (peak_db / 20) / top
    sig = [v * scale for v in sig]
    # trim the silent tail, then fade the last 20 ms
    floor = 10 ** (-70 / 20)
    end = len(sig)
    while end > 1 and abs(sig[end - 1]) < floor:
        end -= 1
    sig = sig[:end]
    r = min(int(0.02 * SR), len(sig))
    for i in range(r):
        sig[len(sig) - 1 - i] *= i / r
    return sig


def write(name, sig):
    path = os.path.join(OUT, name + ".wav")
    frames = struct.pack("<%dh" % len(sig), *(max(-32767, min(32767, round(v * 32767))) for v in sig))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print(f"{name:10s} {len(sig) / SR:5.2f} s")


C5, D5, E5, G5, A5, B5 = 523.25, 587.33, 659.25, 783.99, 880.0, 987.77
C6, D6, E6, G6 = 1046.5, 1174.66, 1318.51, 1567.98
C4, E4, G4, B4 = 261.63, 329.63, 392.0, 493.88

os.makedirs(OUT, exist_ok=True)

# Button press: a soft pop.
write("tap", finish(mix([(0, sweep(1400, 700, 0.06, 0.012), 1.0), (0, noise(0.004, 3000, 3000, 0.0005, 0.001), 0.3)]), -12))

# Session start: two rising marimba notes.
write("start", finish(reverb(mix([(0, note(E5, 0.8, MARIMBA), 1.0), (0.11, note(B5, 0.8, MARIMBA), 0.9)]), 0.15), -3))

# XP count-up ticks, a whole tone higher each.
for i in range(8):
    f = 880 * 2 ** (i * 2 / 12)
    write(f"tick{i + 1}", finish(mix([(0, note(f, 0.09, WOOD, attack=0.001), 1.0), (0, noise(0.003, 4000, 4000, 0.0005, 0.001), 0.2)]), -9))

# Block complete: a bright bell arpeggio with a sparkle on top.
write("complete", finish(reverb(mix([
    (0.00, note(C5, 1.8, BELL), 0.8),
    (0.08, note(E5, 1.8, BELL), 0.8),
    (0.16, note(G5, 1.8, BELL), 0.8),
    (0.24, note(C6, 1.8, BELL), 0.9),
    (0.36, note(E6, 1.2, SOFT), 0.25),
    (0.40, note(G6, 1.2, SOFT), 0.2),
]), 0.25), -1))

# Streak extended: a whoosh, a thump as it catches, then a chord swelling with sparkles.
write("streak", finish(reverb(mix([
    (0.00, noise(0.42, 300, 6000, 0.25, 0.12, seed=7), 0.55),
    (0.28, sweep(180, 90, 0.2, 0.06), 0.7),
    (0.30, note(G4, 1.8, WARM, attack=0.04), 0.35),
    (0.30, note(B4, 1.8, WARM, attack=0.04), 0.3),
    (0.30, note(D5, 1.8, WARM, attack=0.04), 0.3),
    (0.30, note(G5, 1.8, WARM, attack=0.04), 0.25),
    (0.45, note(B5, 0.9, BELL), 0.35),
    (0.52, note(D6, 0.9, BELL), 0.35),
    (0.59, note(G6, 0.9, BELL), 0.35),
]), 0.25), -1))

# Milestone: a quick rising arpeggio into a held, gently vibrating chord.
arp = [(i * 0.055, note(f, 0.9, BELL), 0.7) for i, f in enumerate((C5, E5, G5, C6, E6, G6))]
held = [(0.36, note(f, 2.2, WARM, attack=0.03, vibrato=(5.0, 0.004)), 0.28) for f in (C5, E5, G5, C6)]
write("milestone", finish(reverb(mix(arp + held), 0.3, tail=1.4), -1))

# Block unfinished: a soft "pfff" as the flame goes out, then two gentle falling notes.
write("fizzle", finish(reverb(mix([
    (0.00, noise(0.5, 2500, 400, 0.02, 0.18, seed=3), 0.35),
    (0.10, note(E4, 0.6, SOFT, attack=0.02), 0.7),
    (0.38, note(C4, 0.9, SOFT, attack=0.02, glide=-0.3), 0.7),
]), 0.15), -4))

# Break over: two calm chimes.
write("break-end", finish(reverb(mix([(0, note(G5, 1.4, BELL), 0.8), (0.18, note(C6, 1.4, BELL), 0.8)]), 0.2), -2))

# Time check (mock exam halfway, 15 minutes left): one soft bell.
write("cue", finish(reverb(note(A5, 1.6, CHIME), 0.2), -4))

# Come back (leave nudge): a friendly double ping.
write("nudge", finish(reverb(mix([(0, note(B5, 0.5, BELL), 0.8), (0.16, note(E6, 0.6, BELL), 0.8)]), 0.15), -2))
