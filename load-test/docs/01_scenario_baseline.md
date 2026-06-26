# 시나리오 1 — 평상시 운영 (Baseline)

## 문서 개요

**시나리오 유형**: Baseline Performance Test  
**난이도**: ⭐ (낮음)  
**목적**: 일상적인 사용 패턴에서 서버의 기본 성능 및 안정성 검증  
**작성일**: 2026-06-26  
**예상 소요 시간**: 10분

---

## 1. 시나리오 배경

### 1.1 비즈니스 컨텍스트

뽈레(Polle) 서비스의 일상적인 평일 오전/오후 시간대를 시뮬레이션합니다.

```
서비스 규모:
  - MAU: 3만 명
  - DAU: 12,000명
  - 평균 세션: 0.14 세션/s
  - 일반 시간대: 0.17-0.28 세션/s
```

### 1.2 시나리오 목적

- 서버가 정상 트래픽을 안정적으로 처리하는지 확인
- 기본 데이터베이스 설정(HikariCP 10 커넥션)의 적정성 검증
- N+1 쿼리 발생 여부 및 `batch_fetch_size=30` 설정의 실효성 확인
- 프론트엔드의 멀티 API 호출 패턴에서 병목 현상 확인

---

## 2. 트래픽 프로필

### 2.1 사용자 행동 패턴

프론트엔드 4개 탭의 API 호출 패턴을 기반으로 시뮬레이션합니다.

```typescript
// 홈 탭 진입 (3개 API 동시 호출)
GET /api/stories?size=20
GET /api/cheer?size=20
GET /api/shops?size=20

// 가게 상세 진입 (4개 API 동시 호출)
GET /api/shops/{storeId}
GET /api/shops/{storeId}/cheers?size=10
GET /api/shops/{storeId}/images
GET /api/shops/{storeId}/tags

// 마이 탭 진입 (3개 API 동시 호출)
GET /api/member
GET /api/shops/cheered-member
GET /api/stories/member?page=0&size=5
```

### 2.2 시나리오 설정

```yaml
Virtual Users (VUs): 10명 동시 접속
Duration: 10분
Think Time: 5초 (페이지 간 이동 대기 시간)

사용자 여정 (1 iteration):
  1. 홈 탭 진입 (3 req) → 5초 대기
  2. 가게 상세 진입 (4 req) → 5초 대기
  3. 마이 탭 진입 (3 req) → 5초 대기
  → 총 10 req / 15초 = 0.67 req/s per VU

예상 전체 트래픽:
  - 10 VU × 0.67 req/s = 6.7 req/s
  - 총 요청 수: 6.7 req/s × 600초 = 4,020 requests
```

### 2.3 API 엔드포인트 분포

| API | 호출 빈도 | 비율 |
|-----|----------|------|
| `GET /api/stories?size=20` | 10회/10분/VU | 10% |
| `GET /api/cheer?size=20` | 10회/10분/VU | 10% |
| `GET /api/shops?size=20` | 10회/10분/VU | 10% |
| `GET /api/shops/{id}` | 10회/10분/VU | 10% |
| `GET /api/shops/{id}/cheers` | 10회/10분/VU | 10% |
| `GET /api/shops/{id}/images` | 10회/10분/VU | 10% |
| `GET /api/shops/{id}/tags` | 10회/10분/VU | 10% |
| `GET /api/member` | 10회/10분/VU | 10% |
| `GET /api/shops/cheered-member` | 10회/10분/VU | 10% |
| `GET /api/stories/member` | 10회/10분/VU | 10% |

---

## 3. 환경 설정

### 3.1 서버 리소스

```yaml
CPU: 2 vCPU (t3.medium 시뮬레이션)
Memory: 4 GB
JVM Heap: -Xms2g -Xmx2.5g
Database: MySQL 8.0 (HikariCP pool size: 10)
```

### 3.2 테스트 데이터

```
Members: 50,000명
Stores: 10,000개
Cheers: 120,000개 (각 Store당 평균 12개)
Stories: 30,000개
CheerImages: ~180,000개 (각 Cheer당 평균 1.5개)
StoryImages: ~60,000개 (각 Story당 평균 2개)
CheerTags: ~360,000개 (각 Cheer당 평균 3개)
```

---

## 4. 성공 기준

### 4.1 성능 목표

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **평균 응답 시간** | < 100ms | < 200ms |
| **P95 응답 시간** | < 300ms | < 500ms |
| **P99 응답 시간** | < 500ms | < 1000ms |
| **에러율** | 0% | < 0.1% |
| **처리량** | > 6 req/s | > 5 req/s |

### 4.2 리소스 사용률

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **CPU 사용률** | 20-40% | < 60% |
| **메모리 사용률** | < 60% | < 80% |
| **DB 커넥션 풀** | < 30% (3/10) | < 50% (5/10) |
| **JVM Heap** | < 1.5 GB | < 2.0 GB |

### 4.3 안정성 목표

- ✅ **메모리 누수 없음**: 10분 동안 Heap 사용량이 일정 범위 유지
- ✅ **GC 일시 정지**: 모든 GC < 200ms
- ✅ **에러 0건**: 5xx 에러, DB 타임아웃, OOM 등 없음

---

## 5. 테스트 실행

### 5.1 전제 조건

```bash
# 1. Docker 컨테이너 실행
cd load-test
docker-compose -f docker-compose.load-test.yml up -d

# 2. 테스트 데이터 생성 (약 5-10분 소요)
docker-compose -f docker-compose.load-test.yml exec mysql bash -c "cd /docker-entrypoint-initdb.d && ./00_run_all.sh"

# 3. 서버 헬스 체크
curl http://localhost:8080/actuator/health

# 4. 데이터 생성 확인
docker-compose -f docker-compose.load-test.yml exec mysql mysql -ueatda -peatda123 eatda -e "
SELECT 'Member' AS entity, COUNT(*) AS count FROM member
UNION ALL SELECT 'Store', COUNT(*) FROM store
UNION ALL SELECT 'Cheer', COUNT(*) FROM cheer
UNION ALL SELECT 'Story', COUNT(*) FROM story
UNION ALL SELECT 'CheerImage', COUNT(*) FROM cheer_image
UNION ALL SELECT 'StoryImage', COUNT(*) FROM story_image
UNION ALL SELECT 'CheerTag', COUNT(*) FROM cheer_tag;"
```

### 5.2 K6 스크립트

두 가지 버전의 스크립트를 제공합니다:
- **scenario1_baseline_1m.js**: 빠른 검증용 (1분)
- **scenario1_baseline_10m.js**: 메모리 누수 감지용 (10분)

```javascript
// k6/scenario1_baseline_10m.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  vus: 10,
  duration: '10m',
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.001'],
    'errors': ['rate<0.001'],
  },
};

const BASE_URL = 'http://localhost:8080';

export default function() {
  // 1. 홈 탭 진입 (3개 API 동시 호출)
  const homeRequests = [
    { method: 'GET', url: `${BASE_URL}/api/stories?size=20` },
    { method: 'GET', url: `${BASE_URL}/api/cheer?size=20` },
    { method: 'GET', url: `${BASE_URL}/api/shops?size=20` },
  ];
  
  const homeResponses = http.batch(homeRequests);
  homeResponses.forEach(res => {
    const success = check(res, {
      'home tab status is 200': (r) => r.status === 200,
      'home tab response time < 500ms': (r) => r.timings.duration < 500,
    });
    errorRate.add(!success);
  });
  
  sleep(5);
  
  // 2. 가게 상세 진입 (4개 API 동시 호출)
  const storeId = Math.floor(Math.random() * 500) + 1;
  const storeDetailRequests = [
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}` },
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/cheers?size=10` },
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/images` },
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/tags` },
  ];
  
  const storeResponses = http.batch(storeDetailRequests);
  storeResponses.forEach(res => {
    const success = check(res, {
      'store detail status is 200': (r) => r.status === 200,
      'store detail response time < 500ms': (r) => r.timings.duration < 500,
    });
    errorRate.add(!success);
  });
  
  sleep(5);
  
  // 3. 마이 탭 진입 (3개 API 동시 호출)
  // TODO: 인증 토큰 필요 - 일단 생략 또는 Mock 토큰 사용
  const myPageRequests = [
    { method: 'GET', url: `${BASE_URL}/api/member`, headers: { 'Authorization': 'Bearer mock-token' } },
    { method: 'GET', url: `${BASE_URL}/api/shops/cheered-member`, headers: { 'Authorization': 'Bearer mock-token' } },
    { method: 'GET', url: `${BASE_URL}/api/stories/member?page=0&size=5`, headers: { 'Authorization': 'Bearer mock-token' } },
  ];
  
  const myPageResponses = http.batch(myPageRequests);
  myPageResponses.forEach(res => {
    const success = check(res, {
      'my page status is 200 or 401': (r) => r.status === 200 || r.status === 401,
    });
    if (res.status !== 401) {
      errorRate.add(!success);
    }
  });
  
  sleep(5);
}
```

### 5.3 실행

```bash
# 빠른 검증 (1분) - 개발 중
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/scenario1_baseline_1m.js

# 메모리 누수 감지 (10분) - 배포 전 최종 검증
docker-compose -f docker-compose.load-test.yml run --rm k6 run /scripts/scenario1_baseline_10m.js

# 결과를 JSON으로 저장
docker-compose -f docker-compose.load-test.yml run --rm k6 run \
  --out json=/results/scenario1.json \
  /scripts/scenario1_baseline_10m.js
```

### 5.4 모니터링

```bash
# Prometheus 메트릭 확인
curl http://localhost:8080/actuator/prometheus | grep -E 'jvm_memory|http_server|hikaricp'

# Grafana 대시보드
open http://localhost:3000

# Docker stats (실시간 리소스 모니터링)
docker stats eatda-app eatda-mysql
```

---

## 6. 검증 사항

### 6.1 데이터베이스 쿼리

#### 체크리스트

- [ ] **N+1 쿼리 발생 여부**
  - `GET /api/shops/{id}/cheers` 호출 시 각 Cheer마다 CheerImage를 개별 조회하는가?
  - `batch_fetch_size=30` 설정이 제대로 작동하는가?
  - Hibernate 쿼리 로그에서 `SELECT ... WHERE id IN (?, ?, ...)` 패턴 확인

- [ ] **HikariCP 커넥션 풀 사용률**
  - 평균 활성 커넥션: 2-3개 (20-30%)
  - 대기 커넥션: 0개
  - 커넥션 획득 시간: < 10ms

#### 확인 방법

```bash
# Hibernate 쿼리 로그 활성화 (application-load-test.yml)
spring.jpa.show-sql: true
spring.jpa.properties.hibernate.format_sql: true
logging.level.org.hibernate.SQL: DEBUG
logging.level.org.hibernate.type.descriptor.sql.BasicBinder: TRACE

# HikariCP 메트릭 확인
curl http://localhost:8080/actuator/metrics/hikaricp.connections.active | jq
curl http://localhost:8080/actuator/metrics/hikaricp.connections.pending | jq

# 슬로우 쿼리 로그 확인 (MySQL)
docker exec eatda-mysql mysql -u root -proot -e "SELECT * FROM mysql.slow_log ORDER BY query_time DESC LIMIT 10;"
```

### 6.2 프론트엔드 멀티 API 호출 패턴

#### 체크리스트

- [ ] **동시 호출 시 응답 시간 증가**
  - 홈 탭 3개 API가 동시 호출될 때 개별 응답 시간 vs 순차 호출 시 비교
  - DB 커넥션 풀 경합 발생 여부
  - 예상: 동시 호출 시 평균 응답 시간 10-20% 증가

- [ ] **배치 요청 시 DB 부하**
  - `GET /api/stories?size=20` → Story 20개 + 각 StoryImage lazy 로드
  - `GET /api/cheer?size=20` → Cheer 20개 + 각 CheerImage lazy 로드
  - N+1 쿼리로 인한 DB 쿼리 수 폭발 가능성

#### 확인 방법

```bash
# K6 결과에서 batch 호출 응답 시간 분석
jq '.metrics.http_req_duration' results/scenario1.json

# DB 쿼리 수 카운트
docker logs eatda-app 2>&1 | grep "Hibernate: select" | wc -l
```

### 6.3 JVM 메모리 & GC

#### 체크리스트

- [ ] **Heap 사용 패턴**
  - 초기: ~800 MB
  - 안정화 후: 1.0-1.5 GB
  - 10분 동안 일정 범위 유지 (메모리 누수 없음)

- [ ] **GC 빈도 및 일시 정지 시간**
  - Young GC: 평균 20-50ms
  - Full GC: 발생하지 않음 (또는 < 200ms)
  - GC 빈도: 1-2회/분

#### 확인 방법

```bash
# JVM 메트릭 확인
curl http://localhost:8080/actuator/metrics/jvm.memory.used | jq '.measurements[0].value / 1024 / 1024'
curl http://localhost:8080/actuator/metrics/jvm.gc.pause | jq

# GC 로그 확인 (JVM 옵션에 -Xlog:gc*:/tmp/gc.log 추가 필요)
docker exec eatda-app tail -f /tmp/gc.log
```

---

## 7. 예상 병목 및 대응

### 7.1 예상 병목

이 시나리오에서는 **병목이 발생하지 않아야 합니다**.

만약 문제가 발생한다면 다음을 의심:

| 증상 | 원인 | 대응 |
|------|------|------|
| 응답 시간 > 500ms | N+1 쿼리 발생 | `@EntityGraph` 또는 `@BatchSize` 적용 |
| DB 커넥션 풀 > 50% | 쿼리 실행 시간 과다 | 슬로우 쿼리 식별 및 인덱스 추가 |
| Heap 사용률 지속 증가 | 메모리 누수 | Heap dump 분석 (`jmap -dump`) |
| CPU > 60% | 불필요한 연산 | 프로파일링 (JProfiler, VisualVM) |

### 7.2 긴급 대응

```bash
# 1. Heap dump 생성
docker exec eatda-app jmap -dump:format=b,file=/tmp/heap_dump.hprof 1

# 2. Thread dump 생성
docker exec eatda-app jstack 1 > thread_dump.txt

# 3. 슬로우 쿼리 로그 확인
docker exec eatda-mysql mysql -u root -proot -e "SHOW FULL PROCESSLIST;"

# 4. 현재 DB 커넥션 수 확인
docker exec eatda-mysql mysql -u root -proot -e "SHOW STATUS LIKE 'Threads_connected';"
```

---

## 8. 결과 분석

### 8.1 K6 출력 예시 (성공 케이스)

```
     ✓ home tab status is 200
     ✓ home tab response time < 500ms
     ✓ store detail status is 200
     ✓ store detail response time < 500ms

     checks.........................: 100.00% ✓ 4000      ✗ 0
     data_received..................: 8.5 MB  14.2 kB/s
     data_sent......................: 1.8 MB  3.0 kB/s
     http_req_blocked...............: avg=1.5ms   min=0s     med=0s     max=60ms   p(95)=7ms
     http_req_connecting............: avg=1.0ms   min=0s     med=0s     max=40ms   p(95)=5ms
     http_req_duration..............: avg=85ms    min=8ms    med=72ms   max=380ms  p(95)=210ms
     http_req_receiving.............: avg=1.8ms   min=0s     med=1ms    max=18ms   p(95)=6ms
     http_req_sending...............: avg=0.4ms   min=0s     med=0s     max=4ms    p(95)=1ms
     http_req_waiting...............: avg=82ms    min=7ms    med=70ms   max=375ms  p(95)=205ms
     http_reqs......................: 4020    6.7 req/s
     iteration_duration.............: avg=15.2s   min=15s    med=15.1s  max=16s    p(95)=15.5s
     iterations.....................: 402     0.67/s
     vus............................: 10      min=10      max=10
     vus_max........................: 10      min=10      max=10
```

### 8.2 판정 기준

#### ✅ 성공 (다음 조건 모두 충족)

- [ ] 평균 응답 시간 < 200ms
- [ ] P95 응답 시간 < 500ms
- [ ] 에러율 0%
- [ ] CPU 사용률 < 60%
- [ ] 메모리 사용률 < 80%
- [ ] DB 커넥션 풀 < 50%

#### ⚠️ 주의 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 200-500ms
- [ ] P95 응답 시간 500-1000ms
- [ ] CPU 사용률 60-80%
- [ ] 메모리 사용률 80-90%

#### 🚨 실패 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 > 500ms
- [ ] 에러 발생 (5xx, 타임아웃 등)
- [ ] CPU 사용률 > 80%
- [ ] 메모리 사용률 > 90%
- [ ] OOM 발생

---

## 9. 다음 단계

### 9.1 성공 시

- ✅ 시나리오 2 진행: [핫플레이스 집중 트래픽 (점심 피크)](02_scenario_hotplace.md)
- ✅ 기본 설정(HikariCP 10) 유지
- ✅ 프론트엔드 멀티 API 호출 패턴 검증 완료

### 9.2 최적화 필요 시

- 🔧 **N+1 쿼리 발견**: `@EntityGraph` 또는 `@BatchSize` 적용
- 🔧 **슬로우 쿼리 발견**: 인덱스 추가 또는 쿼리 개선
- 🔧 **메모리 누수 발견**: Heap dump 분석 및 객체 참조 해제

### 9.3 실패 시

- 🚨 **근본 원인 분석**: 로그, 프로파일링, DB 슬로우 쿼리 로그
- 🚨 **긴급 패치**: 코드 수정 후 재테스트
- 🚨 **인프라 검토**: 메모리/CPU 부족 시 리소스 증설 고려

---

## 10. 참고 자료

- [00_load_test_prerequisites.md](00_load_test_prerequisites.md) — 테스트 전제 조건
- [../Eatda-Project/docs/frontend-api-reference.md](../../Eatda-Project/docs/frontend-api-reference.md) — 프론트엔드 API 레퍼런스
- [K6 Documentation](https://k6.io/docs/)
- [K6 http.batch() Documentation](https://k6.io/docs/javascript-api/k6-http/batch/)
- [HikariCP Configuration](https://github.com/brettwooldridge/HikariCP#configuration-knobs-baby)

---

## 문서 이력

| 버전 | 날짜 | 작성자 | 변경 내역 |
|------|------|--------|----------|
| 1.0 | 2026-06-26 | System | 초기 작성 |
| 2.0 | 2026-06-26 | System | 프론트엔드 멀티 API 호출 패턴 반영 재작성 |
