#!/usr/bin/env python3
"""Convert a real MIT-BIH ECG segment into an 8-bit hex ROM file for the demo.

Data source (see demo/data/SOURCE.md):
    PhysioNet MIT-BIH Arrhythmia Database, record 100, channel 1 (MLII).
    Raw format: WFDB 212 (two's-complement SIGNED 12-bit, 2 samples packed in
    3 bytes), 360 sps. The .dat is 2 interleaved channels. This is the NATIVE
    format — no conversion step; a 1 950 000 B file holds 650 000 samples/ch.

Why rescale to 8-bit:
    The pipeline's ADC path is 8-bit. window_buffer subtracts a BASELINE_OFFSET
    (169) and clamps; feature_extraction then sign-extends the 8-bit sample
    (bit7 = sign). We map the real 12-bit waveform linearly into 0..255 so the
    ECG *shape* (P/QRS/T) is preserved for a pipeline demo. This is REAL data
    rescaled, NOT a synthetic waveform -- but the pipeline's 8-bit signed +
    baseline-clamp stage will distort it; that distortion is expected and
    reported, not hidden.

Reproducible: same input file + same args -> same output. No randomness.

Usage:
    python3 ecg_convert.py
    python3 ecg_convert.py --start 1000 --n 2048 --channel 0 --out ../demo/ecg_rom.hex
"""
import argparse
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_DAT = HERE / "data" / "mitbih_100.dat"


def read_channel(dat: Path, channel: int, n_channels: int = 2):
    """Return the full list of SIGNED 12-bit samples for one channel.

    WFDB 212: every 3 bytes [b0 b1 b2] hold 2 signed 12-bit samples, two's
    complement. byte0 = sample A (ch0) low 8 bits; byte1's LOW nibble = ch0
    top 4 bits; byte1's HIGH nibble = ch1 top 4 bits; byte2 = ch1 low 8 bits.
      s0 = b0 | ((b1 & 0x0F) << 8)      # ch0: low byte + high nibble
      s1 = b2 | ((b1 & 0xF0) << 4)      # ch1: low byte + high nibble
    A code >= 2048 is negative (12-bit two's complement). Channels interleave
    sample-by-sample, so channel c is every n_channels-th sample from offset c.

    Data-loss policy: an incomplete trailing 3-byte group means missing data --
    it is a DATA BUG, never silently dropped. `main` validates up front that
    the file is exactly 3 bytes per sample-pair; the check here is the guard
    for any direct caller.
    """
    raw = dat.open("rb").read()
    if len(raw) % 3:
        raise ValueError(
            f"212 data: {len(raw)} bytes is not a multiple of 3 "
            f"({len(raw) % 3} trailing byte(s)) — incomplete sample, "
            f"refusing to silently drop it")
    if channel >= n_channels:
        raise IndexError(f"channel {channel} out of range [0, {n_channels})")
    ngroups = len(raw) // 3
    out = []
    for g in range(ngroups):
        b0, b1, b2 = raw[3 * g], raw[3 * g + 1], raw[3 * g + 2]
        s0 = b0 | ((b1 & 0x0F) << 8)
        s1 = b2 | ((b1 & 0xF0) << 4)
        c0 = s0 - 4096 if s0 >= 2048 else s0
        c1 = s1 - 4096 if s1 >= 2048 else s1
        out.append([c0, c1][channel])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dat", default=str(DEFAULT_DAT))
    ap.add_argument("--channel", type=int, default=0, help="0-based channel")
    ap.add_argument("--start", type=int, default=1000, help="first sample index")
    ap.add_argument("--n", type=int, default=2048, help="number of samples")
    ap.add_argument("--out", default=str(HERE / "ecg_rom.hex"))
    args = ap.parse_args()

    dat = Path(args.dat)
    # Explicit data-loss policy (212): the file must hold whole 3-byte groups,
    # and the .hea declares a fixed sample count per channel. Validate BOTH up
    # front so a truncated/foreign file is a hard error, never a silent trim.
    import re
    nbytes = dat.stat().st_size
    ngroups = nbytes // 3
    if nbytes % 3:
        raise SystemExit(f"{dat.name}: {nbytes} bytes is not a multiple of 3 "
                         f"({nbytes % 3} trailing byte(s)) — incomplete 212 "
                         f"sample, refusing to silently drop it")
    n_samples = ngroups * 2
    # .hea (if present) states the authoritative sample count / rate.
    hea = dat.with_suffix(".hea")
    if hea.exists():
        first = hea.read_text().splitlines()[0].split()
        # "<rec> <nch> <sps> <nsamp> [ ... ]"
        nch, sps, nsamp = int(first[1]), int(first[2]), int(first[3])
        if args.channel >= nch:
            raise SystemExit(f"channel {args.channel} out of range "
                             f"(record has {nch})")
        if args.start + args.n > nsamp:
            raise SystemExit(f"segment {args.start}..{args.start+args.n} exceeds "
                             f"record sample count {nsamp}")
        if n_samples != nch * nsamp:
            print(f"WARNING: {dat.name} holds {n_samples} total samples but .hea "
                  f"declares {nch} ch x {nsamp} = {nch*nsamp}; using file size")
        print(f"source : MIT-BIH record {first[0]}, ch{args.channel} "
              f"@ {sps} sps, WFDB 212 (signed 12-bit, 2 samples/3 bytes), "
              f"{nsamp} samples/ch")
    else:
        if args.start + args.n > n_samples // 2:
            raise SystemExit(f"segment exceeds {n_samples // 2} samples/channel")
        print(f"source : {dat.name}, ch{args.channel}, WFDB 212, "
              f"{n_samples // 2} samples/ch (no .hea found)")

    ch = read_channel(dat, args.channel)
    seg = ch[args.start:args.start + args.n]

    lo = min(seg)
    hi = max(seg)
    rng = (hi - lo) or 1

    # Linear rescale to 0..255 (real-data rescale, not synthetic).
    out = []
    for x in seg:
        v = round((x - lo) * 255 / rng)
        v = max(0, min(255, v))
        out.append(v)

    mn8, mx8 = min(out), max(out)
    # Post window_buffer baseline stage: (v>=169)? v-169 : 0
    pre = [ (v - 169) if v >= 169 else 0 for v in out ]
    pre_mn, pre_mx = min(pre), max(pre)

    # windows: window i covers out[i*256 : i*256+512]; count complete windows
    nwin = len(out) // 256  # windows stride 256 (>= need 3)

    outp = Path(args.out)
    # One sample per line, no blank lines (binary write, \n only).
    outp.write_bytes(("\n".join(f"{v:02X}" for v in out) + "\n").encode("ascii"))

    print(f"seg    : start={args.start} n={args.n}")
    # .hea gain = 200 ADC units/mV (5 uV per digital unit); digital p2p in mV.
    print(f"raw12  : min={lo} max={hi} mean={statistics.mean(seg):.1f} "
          f"std={statistics.pstdev(seg):.1f}   "
          f"(200 units/mV -> p2p={(hi-lo)/200:.3f} mV)")
    print(f"map    : raw[{lo}..{hi}] -> 8bit[0..255] linear")
    print(f"out8   : min={mn8} max={mx8}")
    print(f"post-base (window_buffer, 169 clamp): min={pre_mn} max={pre_mx}")
    print(f"windows stride-256 complete: {nwin}  (need >=3)")
    print(f"wrote  : {outp}  ({len(out)} hex lines)")


if __name__ == "__main__":
    main()
