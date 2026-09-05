# Agentic Workflow — ac-sm_IaC

Loop agentic hasil port dari repo **LPMS-3**, disesuaikan untuk proyek desain
hardware (VHDL / Verilog / SystemVerilog).

Yang di-port hanya **loop agentic**. Workflow CI/build, deploy, publish image,
migration smoke, dependency review, dan weekly digest dari LPMS-3 **tidak**
ikut di-port — ditambahkan nanti setelah struktur repo ini terbentuk.

---

## Alur

```
   Issue dibuat (template) ──label: agent-task──►  agent-plan.yml  (MODEL KUAT)
                                                          │
                                          agent post komentar <!-- agent-plan -->
                                          + label 'plan-posted'
                                                          │
                             ┌────────────────────────────┴──────────────────┐
                    human review rencana                            rencana ditolak
                             │                                       (edit issue,
              label: plan-approved                                    ulangi plan)
                             │
                             ▼
                  agent-trigger.yml  (MODEL MURAH)
                  branch feat/acsm-issue-N → lint/elaborate → PR
                             │
                             ▼
                   ocr-review.yml  (OpenCodeReview, LLM terpisah)
                   review inline pada baris yang bermasalah
                             │
                             ▼
                    agent-fix.yml  ── perbaiki + balas tiap temuan
                             │           (loop cap: 3× untuk trigger bot)
                             │
                 ┌───────────┴──────── agent tidak setuju ──► 🤔 Rebuttal
                 │                                                  │
                 ▼                                                  ▼
          ac-verify.yml                                    ocr-rebuttal.yml
   (model 'agent-verify' menilai AC)                (OCR menjawab: concede/maintain,
   tabel MET / PARTIAL / NOT MET                     maksimal 2 balasan per thread)
                 │
      ada PARTIAL / NOT MET? ──ya──► auto-comment '/agent-fix' ──► balik ke agent-fix
                 │
                tidak
                 ▼
          human merge manual
```

Bypass untuk perubahan kecil: beri label **`fast-track`** — tahap PLAN dilewati,
agent langsung implement.

---

## Workflow

| File | Trigger | Fungsi |
|------|---------|--------|
| `agent-plan.yml` | label `agent-task`, atau `workflow_dispatch` | Tahap PLAN: menyusun rencana rinci, memposting `<!-- agent-plan -->`, memasang `plan-posted` |
| `agent-trigger.yml` | label `plan-approved` / `fast-track`, atau `workflow_dispatch` | Tahap IMPLEMENT: branch, lint, simulasi, PR |
| `agent-fix.yml` | komentar `/agent-fix`, atau review dari bot reviewer | Perbaiki temuan reviewer & ac-verify, balas tiap thread |
| `ac-verify.yml` | review/komentar bot reviewer, atau `workflow_dispatch` | Cek acceptance criteria secara independen, auto-trigger agent-fix bila ada yang belum terpenuhi |
| `ocr-review.yml` | PR opened/reopened, komentar `/open-code-review` | Review kode oleh OpenCodeReview (LLM Quality Gate terpisah) |
| `ocr-rebuttal.yml` | balasan berisi `🤔 Rebuttal` | OCR menjawab rebuttal agent di thread yang sama |

Template issue: `.github/ISSUE_TEMPLATE/acsm-feature.yml` (otomatis memberi label `agent-task`).

---

## Pemisahan model perencana dan pelaksana

Perencanaan dan pelaksanaan sengaja dipisah ke dua workflow agar keduanya bisa
memakai model berbeda. Perencanaan menuntut kemampuan arsitektur yang kuat tapi
jarang dijalankan; pelaksanaan dijalankan lebih sering dan hanya menerjemahkan
rencana yang sudah rinci menjadi kode, sehingga model murah sudah memadai.

Konsekuensinya mengikat: **rencana harus cukup rinci sehingga pelaksana tidak
perlu mengambil satu pun keputusan desain.** Prompt di `agent-plan.yml`
mewajibkan sebelas bagian, termasuk deklarasi modul yang bisa disalin apa
adanya, nilai localparam yang sudah terhitung, tabel FSM lengkap, dan skenario
uji bernomor dengan nilai konkret. Rencana di bawah 1.500 karakter ditolak
otomatis dan diulang.

Model diatur lewat **repository variables**, jadi bisa diganti tanpa menyunting
workflow. Semua punya nilai default, aman dikosongkan.

| Variable | Dipakai | Default |
|---|---|---|
| `PLAN_MODEL` | agent-plan | `agent-planning` |
| `PLAN_BASE_URL` | agent-plan | gateway yang sama |
| `CODE_MODEL` | agent-trigger | `agent-coding` |
| `CODE_BASE_URL` | agent-trigger | gateway yang sama |

Secret opsional `PLAN_API_KEY` dan `CODE_API_KEY` dipakai bila kedua tahap
memakai penyedia berbeda; bila kosong, keduanya jatuh ke `AGENT_API_KEY`.

Contoh mengarahkan perencana ke model kuat dan pelaksana ke model murah:

```bash
gh variable set PLAN_MODEL --repo hargithub/ac-sm_IaC --body "nama-model-kuat"
gh variable set CODE_MODEL --repo hargithub/ac-sm_IaC --body "nama-model-murah"
```

Satu catatan operasional: `agent-plan.yml` tidak memasang toolchain HDL karena
tahap rencana tidak mengompilasi apa pun — menghemat sekitar 40 detik per run.

---

## Prasyarat 1 — Secrets

Set di **Settings → Secrets and variables → Actions**. Nilainya sama dengan yang
sudah dipakai di repo LPMS-3.

| Secret | Dipakai oleh | Keterangan |
|--------|--------------|------------|
| `GH_PAT` | agent-trigger, agent-fix | PAT untuk push branch & buat PR. `GITHUB_TOKEN` bawaan tidak cukup karena push-nya harus memicu workflow lain |
| `AGENT_API_KEY` | agent-trigger, agent-fix | Token gateway Anthropic-compatible, model `agent-coding` |
| `AC_VERIFY_API_KEY` | ac-verify | Token untuk model `agent-verify` (penilai AC) |
| `QG_LLM_URL` | ocr-review, ocr-rebuttal | Endpoint LLM Quality Gate |
| `QG_API_KEY` | ocr-review, ocr-rebuttal | Token LLM Quality Gate |
| `QG_LLM_MODEL` | ocr-review, ocr-rebuttal | Nama model reviewer |
| `QG_LLM_USE_ANTHROPIC` | ocr-review, ocr-rebuttal | `true` bila endpoint memakai format Anthropic Messages API |
| `OCR_GITHUB_APP_ID` | ocr-review, ocr-rebuttal | GitHub App supaya komentar OCR punya identitas sendiri |
| `OCR_GITHUB_APP_PRIVATE_KEY` | ocr-review, ocr-rebuttal | Private key GitHub App tersebut |

`GITHUB_TOKEN` disediakan otomatis oleh Actions — tidak perlu di-set.

GitHub App OCR harus **di-install ke repo ini** (app yang sama boleh dipakai
ulang dari LPMS-3, cukup tambahkan ac-sm_IaC ke daftar repository-nya).

### Variables opsional

`ocr-review.yml` membaca `vars.OCR_*` untuk tuning retry/rate-limit
(`OCR_MAX_RETRIES`, `OCR_RETRY_BASE_DELAY`, `OCR_RETRY_MAX_DELAY`,
`OCR_SUCCESS_DELAY`, `OCR_FAILURE_DELAY`, `OCR_LOW_REMAINING_THRESHOLD`,
`OCR_LOW_REMAINING_SPACING`). Semuanya punya nilai default di kode — aman
dikosongkan.

---

## Prasyarat 2 — Labels

Loop tidak jalan tanpa label berikut:

```bash
gh label create agent-task      --repo hargithub/ac-sm_IaC --color 1d76db --description "Memicu tahap PLAN agent" --force
gh label create plan-posted     --repo hargithub/ac-sm_IaC --color fbca04 --description "Agent sudah posting rencana, menunggu review human" --force
gh label create plan-approved   --repo hargithub/ac-sm_IaC --color 0e8a16 --description "Rencana disetujui — memicu tahap IMPLEMENT" --force
gh label create fast-track      --repo hargithub/ac-sm_IaC --color d93f0b --description "Lewati tahap PLAN, langsung implement" --force
gh label create agent-generated --repo hargithub/ac-sm_IaC --color ededed --description "PR dibuat oleh agent" --force
gh label create needs-human     --repo hargithub/ac-sm_IaC --color b60205 --description "Loop auto-fix mentok, butuh keputusan human" --force
```

---

## Prasyarat 3 — CLAUDE.md (disarankan)

Prompt di `agent-trigger.yml` dan `agent-fix.yml` membaca `CLAUDE.md` kalau ada,
dan konvensi di situ **menang** atas default agent. Di LPMS-3, file inilah yang
paling menentukan kualitas output agent.

Untuk repo HDL, isi minimal yang layak ditulis:

- Bahasa mana untuk apa (mis. SystemVerilog untuk RTL baru, VHDL untuk modul legacy)
- Konvensi penamaan sinyal/modul/file, dan sufiks port (`_i`, `_o`, `_n`)
- Strategi reset baku (sinkron/asinkron, active-low/high)
- Daftar clock domain dan aturan CDC
- Build system: filelist `.f`, Makefile, FuseSoC, atau project vendor
- Target device/toolchain sintesis, kalau ada batasan primitif
- Aturan testbench: framework, wajib self-checking, letak file

---

## Toolchain HDL di runner

`agent-trigger.yml` (tahap implement) dan `agent-fix.yml` meng-install lewat apt:

- **Verilator** — `verilator --lint-only -Wall` untuk lint Verilog/SystemVerilog
- **Icarus Verilog** — `iverilog -g2012` + `vvp` untuk simulasi testbench
- **GHDL** — `ghdl -s` / `-a` / `-e` / `-r` untuk VHDL

GHDL di-install dengan fallback non-fatal: kalau paketnya tidak tersedia di
runner, job tetap jalan dan hanya memunculkan warning.

Agent diinstruksikan memakai build system repo lebih dulu (Makefile / filelist /
FuseSoC) dan baru jatuh ke perintah tool langsung kalau belum ada.

---

## Catatan port

- **Nama branch** agent: `feat/acsm-issue-<N>` (di LPMS-3: `feat/lpms3-issue-<N>`).
- **Guardrail** khusus AntDesign Blazor diganti guardrail RTL: latch tak sengaja,
  blocking vs non-blocking, CDC tanpa sinkronisator, konsistensi reset, `case`
  tanpa `default`, lebar bit, konstruksi non-sintesis di RTL, dan kewajiban
  mendaftarkan file baru ke filelist.
- **Implicit checks** di `ac-verify.yml` diganti pola bug hardware (8 pola),
  menggantikan pola .NET/EF Core milik LPMS-3.
- **Poll `ci-cd.yml`** di gate `ac-verify.yml` dibuat fail-safe (`|| echo 0`).
  Di LPMS-3 workflow itu ada; di sini belum. Tanpa fallback, query `gh run list`
  ke workflow yang tidak ada akan error, hasilnya kosong, dan gate menggantung
  sampai timeout tanpa pernah menjalankan verifikasi.
- **Trigger `workflow_run: ["CI/CD Pipeline"]`** di `ac-verify.yml` dipertahankan
  tapi belum aktif — baru menyala kalau nanti dibuat workflow CI dengan nama
  persis itu.
- **Referensi bot `codacy` / `cubic`** dipertahankan di kondisi `if`. Sekarang
  tidak berpengaruh; kalau integrasi itu dipasang, workflow langsung ikut jalan.

---

## Cara pakai

1. Buat issue dengan template **AC-SM Feature Request (HDL)** — label `agent-task`
   terpasang otomatis dan tahap PLAN langsung jalan.
2. Baca komentar rencana (`<!-- agent-plan -->`). Kalau setuju, tambahkan label
   **`plan-approved`**. Kalau tidak, perbaiki issue-nya dan jalankan ulang.
3. Agent membuat branch, lint/elaborate, lalu buka PR.
4. OpenCodeReview review PR; `agent-fix` memperbaiki dan membalas tiap temuan.
5. `ac-verify` menilai acceptance criteria. Kalau ada PARTIAL/NOT MET, loop
   fix jalan otomatis (maksimal 3× untuk trigger bot).
6. Kalau loop mentok, PR diberi label `needs-human`. Lanjutkan dengan
   `/agent-fix <instruksi eksplisit>` — komentar dari human selalu mem-bypass cap.
7. **Merge dilakukan manual oleh human.** Semua workflow dilarang auto-merge.

Trigger manual:

```bash
gh workflow run agent-trigger.yml -f issue_number=12 -f mode=plan
gh workflow run ac-verify.yml -f pr_number=34
```
