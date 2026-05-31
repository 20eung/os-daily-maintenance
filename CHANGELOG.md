# Changelog

All notable changes to this project will be documented in this file.

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
