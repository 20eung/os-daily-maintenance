# Changelog

All notable changes to this project will be documented in this file.

## [v3.4.2] - 2026-06-16

### Fixed
- **Tailscale 업데이트 sudo 추가**: `tailscale update --yes` 명령에 `sudo` 를 붙여 권한 부족으로 실패하던 문제 수정. 이미 NOPASSWD 권한이 있으므로 cron 환경에서도 정상 동작.

---

## [v3.4.1] - 2026-06-11

### Fixed
- **보안/OS 업데이트 경고 오해 방지**: 섹션 13이 `apt upgrade` 이전 스냅샷(`_APT_UPGRADABLE_LIST`)을 재사용하던 구조를 수정. 업그레이드 완료 후 현재 시점으로 `apt list --upgradable` 재실행하여 실제로 미처리된 항목만 `⚠️ 오류/경고`에 표시. 정상 처리된 경우 `✔ 최신 상태 > 보안: 최신`으로 보고.
- 경고 문구 "대기" → "미처리"로 변경하여 실패 케이스임을 명확히 표현.

---

## [v3.4.0] - 2026-06-08

### Added
- **Tailscale 섹션 (섹션 18)**: VPN mesh 데몬의 일일 점검 추가.
  - `timeout 30 tailscale update --yes` 로 cron 환경에서 sudo 프롬프트 행(hang) 방지. 패키지 매니저 관리 인스톨(apt/brew)은 `managed by package manager` 메시지로 자동 거부 — 섹션 1에서 이미 처리되었음을 안내.
  - `tailscale status --json` 으로 `BackendState` / peer 수 / self IP 파싱. `Running` / `NeedsLogin` / `NoState` / `Stopped` / 비정상 상태를 분기 처리하여 `RESULTS` 또는 `ERRORS` 에 보고.
  - 비설치 시 `SKIPPED` 추가, 데몬 미실행 시 `ERRORS` 에 추가.

### Notes
- README "실행 섹션" 표 갱신: 18 → Tailscale, 텔레그램 보고는 19 로 이동.
- `tailscale update` 가 sudo 가 필요한 환경에서는 `Tailscale: 1.X.Y (sudo 필요)` 로 보고되며, 패키지 매니저가 처리한 동일 버전이 섹션 1에 함께 보고됨. 완전 자동화를 원하면 `visudo` 에 `NOPASSWD: /usr/bin/tailscale` 추가.

---

## [v3.3.2] - 2026-06-07

### Changed
- **텔레그램 최신 상태 메시지에 버전 표시**: 버전 정보를 알 수 있는 항목은 Claude 와 동일한 형식으로 버전 번호 포함
  - `npm: 11.16.0 최신` (기존: `npm: 최신`)
  - `Hermes: e2cc24e3 최신` (기존: `Hermes: 최신`)
  - pip는 PEP 668 스킵 환경에서 RESULTS 배열에 미포함되므로 변화 없음

---

## [v3.3.1] - 2026-06-07

### Fixed
- **journald 사용량 파싱 버그**: `journalctl --disk-usage` 출력이 `38.5M` 형식(B 접미사 없음)으로 오는 경우 정규식 미매치로 "기존 사용량: ?" 로 표시되던 버그 수정. `grep -oP '[\d.]+ ?\w+(?= in)'` 패턴으로 교체하여 `38.5M` 정상 파싱

---

## [v3.3.0] - 2026-06-07

### Added
- **snap 패키지 섹션 (섹션 1c, Linux 전용)**: `snap refresh --list` 로 업데이트 가능한 패키지 감지 후 `sudo snap refresh` 자동 실행 (oracle-cloud-agent 등 OCI 환경 snap 패키지 대응)
- **Swap 모니터링**: Linux 시스템 상태 확인 섹션에 Swap 사용률 추가. 50% 초과 시 경고
- **journald vacuum**: 로그 정리 섹션에 `journalctl --vacuum-time` 추가 — `/var/log/*.log` 정리에 더해 systemd journal 도 함께 정리
- **텔레그램 보고에 소요시간 추가**: 스크립트 시작·종료 시각 기록 후 `⏱ 소요시간: N초` 를 메시지 말미에 표시

### Fixed
- **XDG_RUNTIME_DIR cron 미설정 버그**: cron 환경에서 `XDG_RUNTIME_DIR` 이 미설정되면 Hermes 업데이트 후 서비스 재시작이 항상 스킵되던 버그 수정. Linger=yes 유저는 `/run/user/$(id -u)` 경로가 실제 존재하므로 해당 경로로 자동 fallback 후 `[ -d ]` 체크 방식으로 전환
- **apt upgrade interactive prompt 방지**: `sudo apt upgrade` 에 `DEBIAN_FRONTEND=noninteractive` 추가 — cron 환경에서 일부 패키지의 debconf 프롬프트로 인한 행 현상 방지
- **보안 업데이트 체크 중복 및 타이밍 오류**: 섹션 1에서 `apt update` 직후 업그레이드 목록을 `_APT_UPGRADABLE_LIST` 에 캡처. 섹션 13에서 이 스냅샷을 재사용 — `apt list` 를 3회 중복 호출하던 것을 1회로 줄이고, `apt upgrade` 완료 후 체크해 항상 0개가 나오던 타이밍 버그 수정

---

## [v3.2.0] - 2026-06-07

### Changed
- **Project root 통일**: macOS / Linux 모두 `~/Project` (대문자 P) 사용. `USER_PROJECT_DIRS` 의 각 토큰이 실제 존재하는지 검증하여 silent false-positive 방지.
- **Hermes 재시작 unit 다중화**: 단일 `hermes-dashboard.service` → `MAINTENANCE_HERMES_UNITS` 환경변수로 공백 구분 다중 unit 지원 (기본값: `hermes-gateway.service hermes-dashboard.service`). OCI 환경에서 실제로 운영 중인 `hermes-gateway` 도 자동 재시작.
- **Hermes stamp 경로 변경**: `~/.hermes/scripts/.hermes-last-commit` (scripts/ 디렉토리 의존) → `~/.hermes/.hermes-last-commit` (디렉토리 자동 생성, macOS/Linux 공통).

### Fixed
- **Hermes 업데이트 silent fail**: stamp 디렉토리 부재 시 `mkdir -p` 보장 + 쓰기 실패 시 로그 기록.
- **systemd --user 세션 부재 시 오탐**: `XDG_RUNTIME_DIR` / `systemctl --user status` 가드로 세션이 살아있을 때만 재시작 시도. SSH 환경 / linger 비활성 환경에서의 false error 제거.
- **tune2fs sudo 누락**: fsck 섹션에서 `tune2fs` 가 root 전용인데 `sudo` 없이 호출되던 버그 수정.
- **pip 섹션 PEP 668 호환**: OCI/Ubuntu 23+ 및 Homebrew python 의 externally-managed-environment 에서 `pip install --upgrade` 가 항상 실패하던 문제를 `--user` 자동 fallback 으로 해결. `PIP_TARGET_PACKAGES` 화이트리스트 우선 적용.
- **find 경로 -path 옵션 오동작**: `-not -path "*/node_modules/*"` 가 basename 으로만 매칭되던 버그를 `-name "node_modules" -prune` 으로 교체.
- **df 출력 파싱**: `tail -1` → `awk 'NR==2'` 로 변경, macOS BSD df 와 GNU df 출력 차이 흡수.
- **Obsidian-Wiki 섹션 `cd` 잔재 제거**: `cd` 없이 `git -C` 만 사용하도록 정리 (작업 디렉토리 보존).
- **conda clean 권한 가드**: macOS 에서 root 권한 필요 케이스 `sudo -n` 가드 추가.
- **USER_PROJECT_DIRS 미설정 시 silent skip**: GitHub 섹션이 비어있을 때 명확한 SKIPPED 메시지 출력.
- **pip PEP 668 감지 오작동**: `set -o pipefail` 환경에서 `cmd | grep -q` 가 grep 0 매치(externally-managed 발견) 시 exit 0 → OK, grep 1(미발견) 시 exit 1 → pipefail 로 if false. 즉 PEP 668 환경임에도 영원히 false 로 평가돼 가드가 무력화되던 버그를 변수로 받아 직접 매칭하는 방식으로 수정. Ubuntu 24.04 / Homebrew python 환경에서 7개 패키지가 30초 동안 무의미한 업그레이드 시도를 하던 문제 해결.

### Notes
- `~/project` → `~/Project` 마이그레이션 필요: OCI VM 에서 `mv ~/project ~/Project` 한 번 실행.
- macOS 의 `~/Project` 는 변경 없음.

---

## [v3.1.0] - 2026-05-31

### Fixed
- **pip**: `--break-system-packages` 플래그 제거 — Ubuntu 22.04+ 시스템 Python 패키지 파손 위험 해소
- **Docker**: `docker stop/start` → `docker compose up -d` 로 변경 — 새 이미지가 실제로 적용되지 않던 버그 수정 (compose 라벨 자동 감지)
- **fsck**: `sudo touch /forcefsck` → `sudo tune2fs -C 1 <ROOT_DEV>` 로 변경 — Ubuntu 20.04+ 호환 방식 적용 (`findmnt` 로 루트 디바이스 자동 감지)

### Changed
- **Docker 이미지 pull 빈도**: 매일 → **주 1회 (일요일)** — HDD 환경에서 발생하는 iowait 스파이크 방지

---

## [v3.0.1] - 2026-05-31

### Fixed
- bkit: `claude` 미설치 서버에서 `SKIPPED` 배열에 추가되지 않던 silent skip 보완
- GitHub: 저장소가 없는 서버에서 "모두 최신" 오탐 방지 (`git_repo_count` 추가)
- fsck: Linux에서 `fsck` 미설치 또는 `sudo` 없을 때 결과 미기록 문제 수정

### Added
- Docker 섹션 추가: Watchtower 실행 중이면 자동 스킵, 없으면 `docker pull` 후 변경된 컨테이너 재시작

---

## [v3.0.0] - 2026-05-31

### Changed
- `daily_maintenance_linux.sh` + `daily_maintenance_macos.sh` 를 단일 `daily_maintenance.sh` 로 통합
- Docker Compose 섹션 제거 (Watchtower로 위임)
- README, PROMPT 문서 v3.0.0 기준으로 업데이트

---

## [v2.4.3] - 2026-04-01

### Changed
- 버전 번호 수정 (문서)

## [v2.4.2] - 2026-04-01

### Fixed
- LOG_STAGING_DIR 경로를 SCRIPT_DIR 기준으로 변경
- 파일시스템 점검 오류 내용 및 재시동 안내를 텔레그램 메시지에 포함

## [v2.2.7] - 2026-03-01

### Changed
- Docker Compose 섹션 제거 반영 (README 업데이트)

## [v2.2.5] - 2026-03-01

### Added
- Claude & bkit 섹션 통합 (양쪽 OS 동일한 섹션 구조)
- Git sync: stash 기능 Ubuntu로 이전, diverged 상태 감지
