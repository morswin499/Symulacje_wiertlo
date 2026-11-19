#!/usr/bin/env python3
"""
Porównanie pomiaru (Motor Pilot, alien_runK.csv) z eksportem Scope z PLECS.

PLECS: w oknie Scope  File -> Save trace data / Export -> CSV.
Pierwsza kolumna to czas, kolejne to sygnały w kolejności z Scope.

Użycie:
    python compare_plecs.py alien_run1.csv plecs_run1.csv
    python compare_plecs.py alien_run1.csv plecs_run1.csv --n-col 1 --iq-col 2
    python compare_plecs.py alien_run1.csv plecs_run1.csv --n-scale 9.5493   # gdy PLECS daje rad/s
    python compare_plecs.py alien_run1.csv plecs_run1.csv --t-shift 0.02     # przesunięcie PLECS w czasie

Bez --n-col/--iq-col skrypt wypisze kolumny z pliku PLECS i spróbuje zgadnąć.
Wynik: wykres porownanie.png + RMSE prędkości i Iq w kilku fazach testu.
"""
import argparse
import csv
import sys

import numpy as np

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    sys.exit("Brak matplotlib: pip install matplotlib numpy")


def read_plecs(path):
    with open(path, newline="", encoding="utf-8-sig") as fh:
        first = fh.readline()
        fh.seek(0)
        delim = ";" if first.count(";") > first.count(",") else ","
        rows = list(csv.reader(fh, delimiter=delim))
    hdr = rows[0]
    try:
        float(hdr[0])
        hdr, data = [f"col{i}" for i in range(len(rows[0]))], rows
    except ValueError:
        data = rows[1:]
    arr = np.array([[float(x.replace(",", ".")) if delim == ";" else float(x) for x in r]
                    for r in data if r and r[0].strip()])
    return [h.strip() for h in hdr], arr


def guess(hdr, keys):
    for i, h in enumerate(hdr[1:], 1):
        if any(k in h.lower() for k in keys):
            return i
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("meas")
    ap.add_argument("plecs")
    ap.add_argument("--n-col", type=int, help="kolumna prędkości w CSV z PLECS (0 = czas)")
    ap.add_argument("--iq-col", type=int, help="kolumna Iq w CSV z PLECS")
    ap.add_argument("--n-scale", type=float, default=1.0, help="mnożnik prędkości PLECS (rad/s->rpm: 9.5493)")
    ap.add_argument("--iq-scale", type=float, default=1.0)
    ap.add_argument("--t-shift", type=float, default=0.0, help="przesunięcie czasu PLECS [s]")
    ap.add_argument("--avg", type=int, default=20, help="uśrednianie pomiaru (próbek po 50 us)")
    a = ap.parse_args()

    m = np.loadtxt(a.meas, delimiter=",", skiprows=1)
    k = a.avg
    n = len(m) // k * k
    m = m[:n].reshape(-1, k, 4).mean(axis=1)
    tm, iqm, nm = m[:, 0], m[:, 1], m[:, 3]

    hdr, p = read_plecs(a.plecs)
    print("Kolumny w pliku PLECS:", ", ".join(f"{i}:{h}" for i, h in enumerate(hdr)))
    nc = a.n_col if a.n_col is not None else guess(hdr, ("speed", "pred", "n_", "omega", "rpm", "wm"))
    ic = a.iq_col if a.iq_col is not None else guess(hdr, ("iq", "i_q"))
    if nc is None:
        sys.exit("Nie zgadłem kolumny prędkości, podaj --n-col")
    print(f"prędkość = kolumna {nc} ({hdr[nc]}), Iq = kolumna {ic} ({hdr[ic] if ic else '-'})")

    tp = p[:, 0] + a.t_shift
    np_ = p[:, nc] * a.n_scale
    iqp = p[:, ic] * a.iq_scale if ic else None

    # wspólna oś czasu = czas pomiaru w zakresie symulacji
    sel = (tm >= tp[0]) & (tm <= tp[-1])
    t = tm[sel]
    n_sim = np.interp(t, tp, np_)
    e_n = n_sim - nm[sel]
    print(f"\nRMSE prędkości (cały zakres {t[0]:.2f}-{t[-1]:.2f} s): {np.sqrt(np.mean(e_n**2)):.1f} rpm")
    if iqp is not None:
        iq_sim = np.interp(t, tp, iqp)
        e_i = iq_sim - iqm[sel]
        print(f"RMSE Iq: {np.sqrt(np.mean(e_i**2)):.3f} A")
    # fazy: rozpędzanie / ustalona / wybieg
    nmax = np.max(nm)
    acc = sel & (nm > 0.05 * nmax) & (nm < 0.95 * nmax) & (tm < tm[np.argmax(nm)])
    ss = sel & (nm > 0.98 * nmax)
    for name, msk in (("rozpędzanie", acc), ("stan ustalony", ss)):
        if msk.sum() > 10:
            ee = np.interp(tm[msk], tp, np_) - nm[msk]
            line = f"  {name:<14} średni błąd n = {ee.mean():+7.1f} rpm, RMSE = {np.sqrt(np.mean(ee**2)):6.1f} rpm"
            if iqp is not None:
                ei = np.interp(tm[msk], tp, iqp) - iqm[msk]
                line += f" | Iq: śr. {ei.mean():+.3f} A, RMSE {np.sqrt(np.mean(ei**2)):.3f} A"
            print(line)

    fig, ax = plt.subplots(2 if iqp is not None else 1, 1, sharex=True, figsize=(11, 7))
    ax = np.atleast_1d(ax)
    ax[0].plot(tm, nm, lw=1, label="pomiar (Motor Pilot)")
    ax[0].plot(tp, np_, lw=1.2, ls="--", label="PLECS")
    ax[0].set_ylabel("n [rpm]")
    ax[0].legend()
    ax[0].grid(alpha=0.3)
    if iqp is not None:
        ax[1].plot(tm, iqm, lw=0.8, label="pomiar")
        ax[1].plot(tp, iqp, lw=1.2, ls="--", label="PLECS")
        ax[1].set_ylabel("Iq [A]")
        ax[1].grid(alpha=0.3)
        ax[1].legend()
    ax[-1].set_xlabel("t [s]")
    fig.tight_layout()
    fig.savefig("porownanie.png", dpi=130)
    print("\nWykres: porownanie.png")


if __name__ == "__main__":
    main()
