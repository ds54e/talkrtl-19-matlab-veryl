# LDOモデル仕様

## 概要

MATLAB / Simulink / SimscapeでLDOをモデル化し、StateflowでPGOOD監視ロジックをモデル化する。RTL側ではLDOをSV-RNM、PGOOD監視ロジックをVeryl、APBレジスタをRgGenで実装する。

| 信号 | 内容 |
|---|---|
| `clk` | PGOOD監視ロジックのクロック。周期100 ns |
| `rst` | PGOOD監視ロジックの同期リセット |
| `en` | LDOの有効化 |
| `load_hi` | 負荷切り替え。0: 通常負荷、1: 高負荷 |
| `vout` | LDO出力電圧 |
| `vfb` | フィードバック電圧 |
| `vctrl` | 誤差アンプの制御値 |
| `ipass` | パス電流 |
| `pg_cmp` | PGOOD比較器の出力 |
| `pgood` | PGOOD監視ロジックの出力 |

## LDOモデル

誤差アンプ → パス素子 → `vout` → 分圧抵抗 → 誤差アンプの閉ループとする。Simscape側の入力電圧は1.2 V固定とする。モデル定数は `vref = 0.45`, `rtop = rbot = 100e3`, `cout = 10e-9`, `Rload = 1.8e3`, `A0 = 200`, `tau_ea = 0.5e-6`, `gm_pass = 4e-3`, `imax = 5e-3`, `vctrl = 0..1` とする。

初期値は `vout = 0`, `vctrl = 0`。高負荷時は `Rload = 300` とし、Simscapeでは1.8 kΩへ360 Ωを並列接続して合成300 Ωとする。LDOモデルは次の式で定義する。

```math
\begin{aligned}
v_{\mathrm{fb}}
&=
v_{\mathrm{out}}
\frac{R_{\mathrm{bot}}}{R_{\mathrm{top}}+R_{\mathrm{bot}}}
\\[4pt]
v_{\mathrm{c,target}}
&=
\mathrm{clip}\left(
A_0\,\mathrm{en}\,
\left(V_{\mathrm{ref}}-v_{\mathrm{fb}}\right),
0,\ 1
\right)
\\[4pt]
\frac{\mathrm{d}v_{\mathrm{ctrl}}}{\mathrm{d}t}
&=
\frac{v_{\mathrm{c,target}}-v_{\mathrm{ctrl}}}{\tau_{\mathrm{ea}}}
\\[4pt]
i_{\mathrm{pass}}
&=
\mathrm{en}\,
\mathrm{clip}\left(
g_{\mathrm{m,pass}}v_{\mathrm{ctrl}},
0,\ I_{\mathrm{max}}
\right)
\\[4pt]
C_{\mathrm{out}}
\frac{\mathrm{d}v_{\mathrm{out}}}{\mathrm{d}t}
&=
i_{\mathrm{pass}}
-
\frac{v_{\mathrm{out}}}{R_{\mathrm{load}}}
-
\frac{v_{\mathrm{out}}}{R_{\mathrm{top}}+R_{\mathrm{bot}}}
\end{aligned}
```

`vc_target` のクリップは誤差アンプの一次遅れの前に行う。

## PGOOD

### 比較器

`pg_cmp` は `vout` を監視するヒステリシス比較器とする。

| 現在の `pg_cmp` | 条件 | 次の `pg_cmp` |
|---:|---|---:|
| 0 | `vout > 0.87` | 1 |
| 1 | `vout < 0.85` | 0 |
| - | それ以外 | 保持 |

しきい値と等しい場合は状態を変えず、初期値は0とする。 `en = 0` でも `pg_cmp` は `vout` に従い、0へ強制しない。

### 監視ロジック

PGOOD監視ロジックは100 ns周期で動作し、状態は `OFF`, `WAIT`, `ON` の3つとする。初期状態は `OFF`、`pgood = 0`。 `rst` は `rst = 1` で有効となる同期リセットで、LDOと比較器の状態には影響しない。

| 条件 | 状態 | `pgood` |
|---|---|---:|
| `rst = 1` または `en = 0` | OFF | 0 |
| `en = 1` かつ `pg_cmp = 0` | WAIT | 0 |
| `pg_cmp = 1` の継続が2 µs未満 | WAIT | 0 |
| `pg_cmp = 1` が2 µs継続 | ON | 1 |

`pg_cmp = 1` を初めて観測してから20周期後、つまり2 µs後に `ON` へ移る。最初の観測を含めると21回連続で1を観測することになる。途中で `pg_cmp = 0`、`en = 0`、`rst = 1` のいずれかを観測した場合は、それまでの継続時間を破棄する。

## APBレジスタ

| アドレス | レジスタ | フィールド | アクセス |
|---:|---|---|---|
| 0x00 | CTRL | EN[0] | RW |
| 0x04 | STATUS | PGOOD[0] | RO |

`CTRL.EN` のリセット値は0。 `STATUS.PGOOD` は現在のPGOOD状態を示し、過去の値は保持しない。

## シナリオ

| 時刻 | `en` | `load_hi` | 動作 |
|---:|---:|---:|---|
| 0 µs | 0 | 0 | 初期状態 |
| 2 µs | 1 | 0 | LDO有効化 |
| 25 µs | 1 | 1 | 高負荷へ切り替え |
| 35 µs | 1 | 0 | 通常負荷へ戻す |
| 50 µs | - | - | シミュレーション終了 |

## 比較

StateflowとVerylでは `pgood` と状態遷移を比較し、SimscapeとSV-RNMでは `vout` 波形と `pg_cmp` のしきい値通過時刻を比較する。最終的なMATLAB側とVerilator側の波形比較にはSimulation Data Inspectorを使う。
