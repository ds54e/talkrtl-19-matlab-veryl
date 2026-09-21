# generated RTL snapshots

GitHub上で生成RTLを直接読めるようにcommitしているsnapshotです。
**source of truthではありません。**

| snapshot | source of truth | 生成器 |
|---|---|---|
| `rggen/ldo_csr.sv` | `csr/rggen.yml` + `csr/ldo_csr.yml` | RgGen (`bash tools/gen-csr`) |
| `veryl/pgood_supervisor.sv` | `rtl/veryl/pgood_supervisor.veryl` + `Veryl.toml` / `Veryl.lock` | Veryl (`veryl build`) |

`SHA256SUMS` は上の2 fileのhashです。RgGen / Verylをinstallしなくても中身を読めます。

snapshot の last verified: veryl 0.21.0 / RgGen 0.36 (rggen-core 0.36.1, rggen-sv-rtl 0.36.0)。

## 規則

- **手編集禁止。** 変更は必ずsource of truth側で行い、再生成したものをcopyします。
- snapshotはsource of truthの**再生成結果**です。値や意味の正本ではありません。
- drift確認:

  ```bash
  bash tools/check-generated-rtl      # -> GENERATED_RTL_CHECK_PASS
  sha256sum -c rtl/generated/SHA256SUMS
  ```

  `tools/check-generated-rtl` はcheck modeです。snapshotを書き換えず、生成物はtemp dirに
  出して破棄します。生成・確認はlocal toolchainだけで行い、CIは使いません。

## 更新手順 (copyは明示的に行う)

```bash
# Veryl
veryl build
cp results/generated/veryl/pgood_supervisor.sv rtl/generated/veryl/

# RgGen
bash tools/gen-csr
cp results/generated/csr/ldo_csr.sv rtl/generated/rggen/

# 正本hashを更新して確認 (repo rootで実行)
sha256sum rtl/generated/rggen/ldo_csr.sv rtl/generated/veryl/pgood_supervisor.sv \
  > rtl/generated/SHA256SUMS
sha256sum -c rtl/generated/SHA256SUMS
bash tools/check-generated-rtl
```

## ここに置かないもの

`results/generated/**`、MATLAB/SDIの生成物 (`*.mldatx`, generated `.slx`)、raw CSV / waveform /
simulator log、Verilator `obj_dir`、Verylの `*.f` filelist (checkout依存absolute pathを含む) は
commitしません。
