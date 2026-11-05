"""Tests for demo/ecg_convert.py::read_channel — WFDB 212 (signed 12-bit,
2 samples / 3 bytes) channel separation, order, sign extension, edges, and
the explicit data-loss policy (no silent truncation).

Fixtures are INDEPENDENT of the function under test: the byte literals below
were hand-derived from the 212 packing definition (ch0 = every 3rd-group
sample 0, ch1 = sample 1), NOT by running read_channel. Negative and edge
values (0, 2047, -1, -2048) are covered.

Run:  python -I -m pytest demo/test_ecg_convert.py   (or plain main below)
"""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ecg_convert", HERE / "ecg_convert.py")
cv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cv)
read_channel = cv.read_channel


# 6 sample-pairs (3-byte groups), packed under the CORRECT 212 layout by hand
# (independent of read_channel): b0=ch0 low8, b1=ch0 high4 | ch1 high4,
# b2=ch1 low8. Groups: +0/+255, +100/+1, +2047/+1, -1/-1, -50/0, -2048/-2048
# The literal bytes are hand-derived, NOT produced by any pack/unpack helper;
# verified: the correct decoder recovers all 6 pairs, the OLD formula
# `((b1&0xF0)>>4)|(b2<<4)` gets ch1 wrong on 4/6 -> this fixture catches it.
FIX212 = bytes.fromhex("0000FF 640001 FF0701 FFFFFF CE0F00 008800".replace(" ", ""))
CH0_EXPECT = [0, 100, 2047, -1, -50, -2048]
CH1_EXPECT = [255, 1, 1, -1, 0, -2048]


def _write(tmp: Path, blob: bytes, name="t.dat") -> Path:
    p = tmp / name
    p.write_bytes(blob)
    return p


def test_hand_computed_212(tmp):
    p = _write(tmp, FIX212)
    assert read_channel(p, 0) == CH0_EXPECT, read_channel(p, 0)
    assert read_channel(p, 1) == CH1_EXPECT, read_channel(p, 1)
    print("PASS hand_computed_212 (neg + edges 0/2047/-1/-2048, both channels)")


def test_incomplete_group_rejected(tmp):
    # 3-byte group with one trailing byte: 3*k+1 -> data loss, must raise,
    # never silently drop the partial sample.
    p = _write(tmp, FIX212[:7], "short.dat")   # 7 bytes = 2 groups + 1 stray
    try:
        read_channel(p, 0)
    except ValueError:
        print("PASS incomplete_group_rejected (ValueError, no silent truncate)")
    else:
        raise AssertionError("incomplete 212 group must raise, not truncate")


def test_invalid_channel_raises(tmp):
    p = _write(tmp, FIX212)
    try:
        read_channel(p, 5)
    except IndexError:
        print("PASS invalid_channel_raises")
    else:
        raise AssertionError("channel >= n_channels must raise IndexError")


def test_single_channel(tmp):
    # One channel only: n_channels=1 -> every 3-byte group yields sample 0.
    p = _write(tmp, FIX212, "one.dat")
    assert read_channel(p, 0, n_channels=1) == CH0_EXPECT
    print("PASS single_channel (n_channels=1)")


# ---------------------------------------------------------------------------
# Real-data, decoder-INDEPENDENT integrity check (task item 2).
#
# This does NOT use read_channel's output as the expected value. It unpacks
# the WFDB 212 bit layout by hand (a second, self-contained implementation)
# and checks ONLY against external ground truth:
#   * file size == 650000 samples/ch x 2 ch x 12 bit / 8  (whole-record intgty)
#   * per-channel sample count == .hea nsamp (650000)
#   * ch0[0] == .hea MLII initial value (995)
# It also prints a full-channel checksum fingerprint for BOTH channels so a
# later official-WFDB diff can confirm byte-exactness (not asserted here,
# because no WFDB reference is installed in this environment).
# ---------------------------------------------------------------------------
REAL_DAT = HERE / "data" / "mitbih_100.dat"
REAL_HEA = HERE / "data" / "mitbih_100.hea"


def _unpack212_independent(raw: bytes):
    """Self-contained 212 unpack (independent of read_channel). ch0=group samp0,
    ch1=group samp1. Returns (ch0, ch1) as signed 12-bit lists."""
    c0, c1 = [], []
    append0, append1 = c0.append, c1.append
    for i in range(len(raw) // 3):
        b0 = raw[3 * i]
        b1 = raw[3 * i + 1]
        b2 = raw[3 * i + 2]
        s0 = b0 | ((b1 & 0x0F) << 8)
        s1 = b2 | ((b1 & 0xF0) << 4)
        append0(s0 - 4096 if s0 >= 2048 else s0)
        append1(s1 - 4096 if s1 >= 2048 else s1)
    return c0, c1


def test_real_data_independent_212(tmp):
    assert REAL_DAT.exists() and REAL_HEA.exists(), "real data/.hea not present"
    raw = REAL_DAT.open("rb").read()

    # .hea ground truth (external, written by the official WFDB tools from
    # their own decode of THIS file): "100 2 360 650000" + per-channel lines.
    # Per-channel fields: "<file> 212 <gain> <nbits> <baseoff> <baseval=first
    # sample> <scale=sum-of-samples mod 2^16> <zerobased> <label>"
    hea_lines = REAL_HEA.read_text().splitlines()
    hdr = hea_lines[0].split()
    nch = int(hdr[1])
    nsamp = int(hdr[3])
    # Parse EVERY channel line into {label: (baseval, scale)}
    per_ch = {}
    for l in hea_lines:
        f = l.split()
        if len(f) >= 8 and f[1] == "212":
            per_ch[f[-1]] = {"baseval": int(f[5]), "scale": int(f[6])}
    assert len(per_ch) == nch, (per_ch, nch)

    # 1) whole-record integrity: file size == packed bytes for nsamp/ch.
    expect_bytes = nch * nsamp * 12 // 8
    assert len(raw) == expect_bytes, (len(raw), expect_bytes)

    # 2) sample count per channel == .hea nsamp.
    c0, c1 = _unpack212_independent(raw)
    assert len(c0) == nsamp and len(c1) == nsamp, (len(c0), nsamp)

    # 3) EVERY channel: initial value == .hea baseval  AND  full-channel sum
    #    mod 65536 == .hea scale field. This is the external, decoder-
    #    independent proof that the 212 unpack is correct on BOTH channels.
    #    (A wrong second-sample layout still matches ch0 but silently breaks
    #    ch1 -- asserting both channels catches it.)
    chans = {"MLII": c0, "V5": c1}
    for label, ch in chans.items():
        exp_base, exp_scale = per_ch[label]["baseval"], per_ch[label]["scale"]
        got_base, got_scale = ch[0], (sum(ch) & 0xFFFF)
        # sum(ch)&0xFFFF may be >32767 for a positive scale; .hea stores the
        # signed 16-bit value, so compare as signed 16-bit.
        got_scale_s = got_scale - 65536 if got_scale >= 32768 else got_scale
        assert ch[0] == exp_base, \
            f"{label}: first sample {ch[0]} != .hea baseval {exp_base}"
        assert got_scale_s == exp_scale, \
            f"{label}: sum mod 2^16 = {got_scale_s} (0x{got_scale:04X}) != " \
            f".hea scale {exp_scale}"
        print(f"PASS {label}: n={len(ch)} first={ch[0]}==baseval {exp_base}, "
              f"sum16={got_scale_s}==scale {exp_scale} (0x{got_scale:04X})")
    # NOTE: .hea fields are external ground truth, NOT produced by this
    # decoder; a byte-exact diff vs the official WFDB reader is still a
    # separate (optional) confirmation, recorded in AUTOMATION_STATUS §11.


def main(tmpdir):
    t = Path(tmpdir)
    t.mkdir(parents=True, exist_ok=True)
    test_hand_computed_212(t)
    test_incomplete_group_rejected(t)
    test_invalid_channel_raises(t)
    test_single_channel(t)
    test_real_data_independent_212(t)
    print("ALL 212 converter tests PASS")


if __name__ == "__main__":
    import tempfile
    main(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp())
