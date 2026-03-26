# Daily Maintenance System

## 목표
macOS 시스템과 개발 환경(Homebrew, npm, pip, Docker, Git, Conda 등)을 매일 오전 09:00에 자동으로 점검하고 최신 상태로 유지하는 자동화 스크립트입니다.

## 핵심 내용
- **OS 패키지**: Homebrew 및 Cask(greedy) 자동 업데이트
- **AI 도구**: Claude Code 및 bkit 플러그인 업데이트
- **개발 언어**: npm 전역 패키지, 주요 pip3 패키지 업데이트
- **컨테이너**: Docker Desktop 앱 업데이트 및 주요 Public 이미지 pull
- **저장소**: `$HOME/Project` 하위 Git 저장소 자동 pull/fetch 점검
- **환경**: conda 자체 업데이트 및 정리
- **시스템**: macOS 시스템 업데이트 확인 및 로그 정리
- **보고**: 작업 결과를 텔레그램으로 자동 전송

## 구조
- `/Users/a04258/.local/bin/daily_maintenance.sh`: 실행 스크립트
- `/Users/a04258/.cokacdir/workspace/admin/logs/`: 작업 로그 저장 위치

## 구현 완료
- [x] conda 서비스 약관(ToS) 대응 및 환경 로딩 보완
- [x] Docker Desktop 앱 자동 업데이트 기능 추가 (4.38+)
- [x] 텔레그램 연동 보고

## 앞으로의 계획
- [ ] 더 많은 Docker 이미지 관리 지원
- [ ] 디스크 공간 부족 시 자동 정리 기능 강화
