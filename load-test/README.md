# EatDa Load Test Environment

대용량 트래픽 테스트를 위한 완전한 테스트 환경입니다.

## 📁 디렉토리 구조

```
load-test/
├── docker-compose.load-test.yml   # 전체 인프라 정의
├── README.md                       # 이 파일 (개요)
├── LOAD_TEST_GUIDE.md             # 상세 실행 가이드
├── scripts/                        # 환경 구성 스크립트
│   ├── start-test-env.sh          # 환경 시작
│   ├── stop-test-env.sh           # 환경 종료
│   └── ...                        # 기타 유틸리티
├── k6/                            # K6 부하 테스트 시나리오 스크립트
│   └── ...                        # 다양한 테스트 시나리오
├── docs/                          # 시나리오별 상세 문서
│   └── ...                        # 각 시나리오 설명 및 실행 방법
└── monitoring/                    # 모니터링 도구 설정
    ├── prometheus/
    ├── grafana/
    └── pinpoint/
```

## 🚀 Quick Start

```bash
# 1. 테스트 환경 시작
./load-test/scripts/start-test-env.sh

# 2. 부하 테스트 실행 (예시)
cd load-test
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/<scenario>.js

# 3. 환경 종료
./load-test/scripts/stop-test-env.sh
```

**상세한 실행 방법은 `docs/` 디렉토리의 각 시나리오 문서를 참고하세요.**

## 📊 모니터링 Dashboard

테스트 환경 실행 후 다음 URL에서 각 서비스에 접속할 수 있습니다:

| 서비스 | URL | 비고 |
|--------|-----|------|
| Application | http://localhost:8080 | 테스트 대상 서버 |
| Grafana | http://localhost:3000 | 메트릭 시각화 (admin/admin) |
| Prometheus | http://localhost:9090 | 메트릭 수집 |
| Pinpoint APM | http://localhost:8081 | 트랜잭션 추적 |

## 📈 테스트 데이터

초기 환경 구성 시 대용량 Mock 데이터가 자동으로 생성됩니다.

- 데이터 규모는 `scripts/` 내 설정 파일에서 조정 가능
- 상세한 데이터 생성 전략은 `docs/00_data_generation_strategy.md` 참고

## 🧪 부하 테스트 시나리오

다양한 트래픽 패턴을 시뮬레이션하는 시나리오들이 `k6/` 디렉토리에 준비되어 있습니다.

### 실행 방법

```bash
cd load-test

# 기본 실행 형식
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/<scenario-file>.js
```

### 시나리오 목록

각 시나리오의 목적, 설정, 성공 기준 등은 `docs/` 디렉토리의 상세 문서를 참고하세요:

- **Baseline**: 평상시 운영 트래픽 시뮬레이션 → `docs/01_scenario_baseline.md`
- **Hotplace**: 특정 가게 집중 트래픽 → `docs/02_scenario_hotplace.md`
- **Viral**: SNS 바이럴 급증 트래픽 → `docs/03_scenario_viral.md`
- 기타 시나리오는 `docs/` 디렉토리 참고

## 🔧 설정 파일

- **Application**: `../src/main/resources/application-load-test.yml`
  - 부하 테스트 환경 전용 Spring Boot 설정
  - DB 커넥션 풀, JPA, 메트릭 등
  
- **Infrastructure**: `docker-compose.load-test.yml`
  - 전체 테스트 환경 구성 (App, DB, 모니터링 도구 등)
  - JVM 옵션, 리소스 제한 등

## 🐛 문제 해결

### 서비스 상태 확인

```bash
cd load-test

# 로그 확인
docker-compose -f docker-compose.load-test.yml logs -f <service-name>

# 특정 서비스 재시작
docker-compose -f docker-compose.load-test.yml restart <service-name>
```

### 완전 재시작

```bash
cd load-test

# 환경 종료 (볼륨 포함)
docker-compose -f docker-compose.load-test.yml down -v

# 환경 재시작
cd ..
./load-test/scripts/start-test-env.sh
```

더 자세한 트러블슈팅은 `LOAD_TEST_GUIDE.md` 또는 `HEALTH_CHECK.md` 참고

## 📊 모니터링

Grafana, Prometheus, Pinpoint를 통해 다음과 같은 지표를 실시간으로 확인할 수 있습니다:

- 요청 처리량 (Throughput)
- 응답 시간 분포 (Latency)
- 에러율
- JVM 메모리/GC
- DB 커넥션 풀 상태
- 트랜잭션 추적

상세한 모니터링 설정 및 활용은 `PROMETHEUS_GUIDE.md` 참고

## ⚙️ 시스템 요구사항

- Docker Desktop 설치
- 권장 리소스: Memory 8GB+, CPU 4 Core+, Disk 10GB+

## 📝 참고 문서

- **[LOAD_TEST_GUIDE.md](./LOAD_TEST_GUIDE.md)**: 환경 구성 및 실행 상세 가이드
- **[HEALTH_CHECK.md](./HEALTH_CHECK.md)**: 서비스 헬스 체크 방법
- **[PROMETHEUS_GUIDE.md](./PROMETHEUS_GUIDE.md)**: Prometheus 메트릭 활용법
- **`docs/`**: 각 시나리오별 상세 문서

## 🔄 일반적인 워크플로우

1. 테스트 환경 시작
2. 모니터링 대시보드 확인 (Grafana 등)
3. 시나리오 선택 및 부하 테스트 실행
4. 결과 분석 및 병목 지점 파악
5. 필요 시 설정 조정 및 재테스트
6. 환경 종료

각 단계의 상세 절차는 `LOAD_TEST_GUIDE.md` 참고
