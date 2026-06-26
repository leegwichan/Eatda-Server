# 대용량 트래픽 테스트 환경 가이드

## 개요
이 가이드는 EatDa 서버의 대용량 트래픽 테스트 환경을 구축하고 실행하는 방법을 설명합니다.

## 환경 구성

### 1. 인프라 컴포넌트
- **MySQL 8.0**: 프로덕션 DB
- **LocalStack**: S3 Mock 서비스
- **Spring Boot App**: WAS (JVM 2GB Heap)
- **Prometheus**: 메트릭 수집
- **Grafana**: 시각화 대시보드
- **Pinpoint**: APM (Application Performance Monitoring)
- **K6**: 부하 테스트 도구

### 2. Mock Data 규모
- Members: 10,000명
- Stores: 5,000개
- Cheers: 평균 가게당 10개 (총 50,000개)
- Stories: 평균 회원당 3개 (총 30,000개)
- Images: Cheer 70%, Story 100%

## 시작하기

### 사전 요구사항
```bash
# Docker 및 Docker Compose 설치 확인
docker --version
docker-compose --version

# 프로젝트 빌드
./gradlew clean build -x test
```

### 1단계: 전체 환경 시작
```bash
# 모든 서비스 시작 (최초 실행 시 Mock Data 생성 포함)
docker-compose -f docker-compose.load-test.yml up -d

# 로그 확인
docker-compose -f docker-compose.load-test.yml logs -f app

# 서비스 상태 확인
docker-compose -f docker-compose.load-test.yml ps
```

**주의**: 최초 실행 시 Mock Data 생성에 시간이 소요됩니다 (약 5-10분).

### 2단계: 서비스 Health Check
```bash
# Application Health
curl http://localhost:8080/actuator/health

# Prometheus
curl http://localhost:9090/-/healthy

# LocalStack S3
curl http://localhost:4566/_localstack/health
```

### 3단계: 모니터링 접속
- **Grafana**: http://localhost:3000
  - ID: admin
  - PW: admin
  - Dashboard: "EatDa Performance Dashboard"

- **Prometheus**: http://localhost:9090

- **Pinpoint Web**: http://localhost:8081

- **Application Swagger**: http://localhost:8080/docs/swagger

## 부하 테스트 실행

### K6 테스트 시나리오

#### 1. Smoke Test (기본 기능 확인)
```bash
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/test-scenario.js \
  -e BASE_URL=http://app:8080 \
  --scenarios smoke
```

#### 2. Load Test (일반 부하)
```bash
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/test-scenario.js \
  -e BASE_URL=http://app:8080 \
  --scenarios load
```

#### 3. Stress Test (고부하)
```bash
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/test-scenario.js \
  -e BASE_URL=http://app:8080 \
  --scenarios stress
```

#### 4. Spike Test (급격한 트래픽 증가)
```bash
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/test-scenario.js \
  -e BASE_URL=http://app:8080 \
  --scenarios spike
```

### 테스트 커스터마이징
`scripts/load-test/k6/test-scenario.js` 파일을 수정하여:
- VU (Virtual Users) 수 조정
- Duration 변경
- API 엔드포인트 추가/변경
- Threshold 조정

## 모니터링 지표

### Grafana Dashboard에서 확인할 수 있는 주요 지표:

1. **Request Rate (req/sec)**
   - 초당 요청 수
   - URI별 분산

2. **Response Time Percentiles**
   - P50, P95, P99
   - URI별 응답 시간

3. **Success Rate**
   - 전체 요청 대비 성공률
   - 5xx 에러 비율

4. **JVM Heap Memory**
   - Heap 사용량
   - GC 빈도

5. **HikariCP Connection Pool**
   - Active/Idle/Pending connections
   - 커넥션 대기 시간

### Pinpoint에서 확인할 수 있는 지표:
- 트랜잭션 맵
- 응답 시간 분포
- Slow Query 추적
- JVM 상세 정보

## Mock Data 재생성

기존 데이터를 삭제하고 새로운 Mock Data를 생성하려면:

```bash
# 1. 서비스 중지
docker-compose -f docker-compose.load-test.yml down -v

# 2. MySQL 볼륨 삭제 (데이터 완전 삭제)
docker volume rm eatda-server_mysql-data

# 3. 재시작 (자동으로 Mock Data 생성)
docker-compose -f docker-compose.load-test.yml up -d
```

## Mock Data 규모 조정

`scripts/load-test/generate-mock-data.sql` 파일 상단의 변수를 수정:

```sql
SET @member_count = 10000;        -- 회원 수
SET @store_count = 5000;          -- 가게 수
SET @cheer_per_store_avg = 10;    -- 가게당 평균 응원 수
SET @story_per_member_avg = 3;    -- 회원당 평균 스토리 수
```

## 성능 튜닝 포인트

### 1. JVM 설정
`docker-compose.load-test.yml`의 `JAVA_OPTS` 수정:
```yaml
JAVA_OPTS: >-
  -Xms2g                    # 초기 Heap
  -Xmx2g                    # 최대 Heap
  -XX:+UseG1GC              # GC 알고리즘
  -XX:MaxGCPauseMillis=200  # GC 최대 pause time
```

### 2. HikariCP 설정
`application-load-test.yml` 수정:
```yaml
hikari:
  maximum-pool-size: 50      # 최대 커넥션 수
  minimum-idle: 10           # 최소 idle 커넥션
  connection-timeout: 30000  # 커넥션 타임아웃
```

### 3. MySQL 설정
`docker-compose.load-test.yml`의 MySQL command:
```yaml
command:
  - --max-connections=1000       # 최대 동시 연결 수
  - --max-allowed-packet=256M    # 최대 패킷 크기
```

## 문제 해결

### 서비스가 시작되지 않을 때
```bash
# 로그 확인
docker-compose -f docker-compose.load-test.yml logs app

# 특정 서비스 재시작
docker-compose -f docker-compose.load-test.yml restart app
```

### MySQL 연결 실패
```bash
# MySQL 상태 확인
docker-compose -f docker-compose.load-test.yml exec mysql mysqladmin ping -p

# MySQL 로그 확인
docker-compose -f docker-compose.load-test.yml logs mysql
```

### Mock Data 생성 실패
```bash
# MySQL에 직접 접속하여 확인
docker-compose -f docker-compose.load-test.yml exec mysql mysql -ueatda -peatda123 eatda

# 테이블 확인
SHOW TABLES;
SELECT COUNT(*) FROM member;
SELECT COUNT(*) FROM store;
```

### 메모리 부족
Docker Desktop 설정에서 리소스 할당 증가:
- Memory: 최소 8GB 권장
- CPU: 최소 4 Core 권장

## 클린업

### 모든 서비스 중지 및 삭제
```bash
# 컨테이너 중지 및 삭제
docker-compose -f docker-compose.load-test.yml down

# 볼륨까지 완전 삭제
docker-compose -f docker-compose.load-test.yml down -v

# 이미지 삭제 (선택사항)
docker rmi $(docker images 'eatda-server*' -q)
```

## 참고 자료

- [K6 Documentation](https://k6.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Pinpoint Documentation](https://pinpoint-apm.gitbook.io/)
- [HikariCP Configuration](https://github.com/brettwooldridge/HikariCP#configuration-knobs-baby)

## 다음 단계

테스트 환경이 준비되었으면:
1. 기본 성능 측정 (Baseline)
2. 병목 지점 식별
3. 최적화 적용
4. 성능 개선 확인
5. 결과 문서화
