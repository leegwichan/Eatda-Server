# 시나리오 2 — 핫플레이스 집중 트래픽 (점심 피크)

## 문서 개요

**시나리오 유형**: Peak Load Test (Hotspot Traffic)  
**난이도**: ⭐⭐ (중간)  
**목적**: 점심시간 특정 가게 상세 페이지에 트래픽이 집중될 때 서버 성능 검증  
**작성일**: 2026-06-26  
**예상 소요 시간**: 30분

---

## 1. 시나리오 배경

### 1.1 비즈니스 컨텍스트

```
상황:
  - 성수동 신상 맛집이 미식가들 사이에서 화제
  - 인플루언서가 점심시간(12:00-12:30)에 해당 가게 링크 공유
  - 뽈레 사용자들이 동시에 해당 가게 상세 페이지 접속

트래픽 특성:
  - 기본 점심 피크: 0.42-0.7 세션/s
  - 핫플레이스 집중 유입: 추가 2-3 세션/s
  - 총: 2.5-3.7 세션/s
```

### 1.2 시나리오 목적

- 특정 가게(Store ID)에 트래픽이 집중될 때 성능 확인
- 가게 상세 페이지 진입 시 4개 API 동시 호출 패턴의 병목 확인
- N+1 쿼리 발생 여부 (Store → Cheer → CheerImage lazy 로드)
- DB 쿼리 캐싱 부재 시 영향 확인

---

## 2. 트래픽 프로필

### 2.1 사용자 행동 패턴

**80%의 사용자**가 동일한 가게(예: storeId=42)를 집중 조회합니다.

```typescript
// 대부분의 사용자 (80%)
// 가게 상세 진입 (4개 API 동시 호출)
GET /api/shops/42
GET /api/shops/42/cheers?size=10
GET /api/shops/42/images
GET /api/shops/42/tags

// 일부 사용자 (20%)
// 홈 탭 → 다른 가게 조회
GET /api/stories?size=20
GET /api/shops?size=20
GET /api/shops/{randomId}
```

### 2.2 시나리오 설정

```yaml
Virtual Users (VUs): 60명 동시 접속
Duration: 30분
Ramp-up: 5분 (0명 → 60명 점진적 증가)
Think Time: 3초 (페이지 간 이동 대기 시간)

트래픽 분포:
  - 80% (48 VU): 핫플레이스 storeId=42 집중 조회
  - 20% (12 VU): 일반 탐색 (홈 탭, 다른 가게)

사용자 여정 (핫플레이스 그룹):
  1. 가게 상세 진입 (4 req) → 3초 대기
  2. 반복
  → 4 req / 3초 = 1.33 req/s per VU

예상 전체 트래픽:
  - 핫플레이스 그룹: 48 VU × 1.33 req/s = 64 req/s
  - 일반 그룹: 12 VU × 0.67 req/s = 8 req/s
  - 총: 72 req/s
```

### 2.3 API 엔드포인트 분포

| API | 호출 빈도 | 비율 |
|-----|----------|------|
| `GET /api/shops/42` (hotspot) | ~1,440회/30분 | 20% |
| `GET /api/shops/42/cheers` | ~1,440회/30분 | 20% |
| `GET /api/shops/42/images` | ~1,440회/30분 | 20% |
| `GET /api/shops/42/tags` | ~1,440회/30분 | 20% |
| 기타 (홈, 다른 가게) | ~1,440회/30분 | 20% |

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
Members: 1,000명
Stores: 500개
Cheers: 5,000개
  - storeId=42: 100개 (핫플레이스)
  - 나머지: 평균 10개
Stories: 2,000개
CheerImages: 10,000개
  - storeId=42 Cheers: 200개 이미지 (각 Cheer당 2개)
StoryImages: 5,000개
```

---

## 4. 성공 기준

### 4.1 성능 목표

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **평균 응답 시간** | < 200ms | < 500ms |
| **P95 응답 시간** | < 500ms | < 1000ms |
| **P99 응답 시간** | < 1000ms | < 2000ms |
| **에러율** | < 0.1% | < 1% |
| **처리량** | > 70 req/s | > 60 req/s |

### 4.2 리소스 사용률

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **CPU 사용률** | 60-80% | < 90% |
| **메모리 사용률** | < 70% | < 85% |
| **DB 커넥션 풀** | < 60% (6/10) | < 80% (8/10) |
| **JVM Heap** | < 2.0 GB | < 2.3 GB |

### 4.3 안정성 목표

- ✅ **메모리 누수 없음**: 30분 동안 Heap 사용량이 일정 범위 유지
- ✅ **GC 일시 정지**: P95 GC < 200ms
- ✅ **에러율 < 1%**: 일시적 지연 허용, 5xx 에러 최소화

---

## 5. 테스트 실행

### 5.1 K6 스크립트

```javascript
// scripts/scenario2_hotplace.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '5m', target: 60 },  // Ramp-up
    { duration: '25m', target: 60 }, // Sustain
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000', 'p(99)<2000'],
    'http_req_failed': ['rate<0.01'],
    'errors': ['rate<0.01'],
  },
};

const BASE_URL = 'http://localhost:8080';
const HOTSPOT_STORE_ID = 42;

export default function() {
  const isHotspotUser = Math.random() < 0.8; // 80%는 핫플레이스 조회
  
  if (isHotspotUser) {
    // 핫플레이스 storeId=42 집중 조회 (4개 API 동시 호출)
    const storeDetailRequests = [
      { method: 'GET', url: `${BASE_URL}/api/shops/${HOTSPOT_STORE_ID}` },
      { method: 'GET', url: `${BASE_URL}/api/shops/${HOTSPOT_STORE_ID}/cheers?size=10` },
      { method: 'GET', url: `${BASE_URL}/api/shops/${HOTSPOT_STORE_ID}/images` },
      { method: 'GET', url: `${BASE_URL}/api/shops/${HOTSPOT_STORE_ID}/tags` },
    ];
    
    const responses = http.batch(storeDetailRequests);
    responses.forEach((res, index) => {
      const success = check(res, {
        'hotspot status is 200': (r) => r.status === 200,
        'hotspot response time < 1000ms': (r) => r.timings.duration < 1000,
      });
      errorRate.add(!success);
    });
    
    sleep(3);
  } else {
    // 일반 사용자 (홈 탭 탐색)
    const homeRequests = [
      { method: 'GET', url: `${BASE_URL}/api/stories?size=20` },
      { method: 'GET', url: `${BASE_URL}/api/shops?size=20` },
    ];
    
    const responses = http.batch(homeRequests);
    responses.forEach(res => {
      const success = check(res, {
        'home status is 200': (r) => r.status === 200,
      });
      errorRate.add(!success);
    });
    
    sleep(5);
    
    // 랜덤 가게 상세 조회
    const randomStoreId = Math.floor(Math.random() * 500) + 1;
    if (randomStoreId !== HOTSPOT_STORE_ID) {
      const storeRes = http.get(`${BASE_URL}/api/shops/${randomStoreId}`);
      check(storeRes, {
        'random store status is 200': (r) => r.status === 200,
      });
      sleep(3);
    }
  }
}
```

### 5.2 실행

```bash
# 시나리오 2 실행
k6 run --out json=results/scenario2.json \
       scripts/scenario2_hotplace.js

# 또는 InfluxDB 연동
k6 run --out influxdb=http://localhost:8086/k6 \
       scripts/scenario2_hotplace.js
```

### 5.3 모니터링

```bash
# 실시간 메트릭 확인 (watch 1초 간격)
watch -n 1 "curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active | jq"

# Grafana 대시보드
open http://localhost:3000

# Docker stats
docker stats eatda-app eatda-mysql
```

---

## 6. 검증 사항

### 6.1 N+1 쿼리 폭발

#### 체크리스트

- [ ] **Cheer → CheerImage lazy 로딩**
  - `GET /api/shops/42/cheers?size=10` 호출 시:
    - Cheer 10개 조회: 1 쿼리
    - 각 Cheer의 CheerImage 조회: N번 쿼리 (N+1 문제)
  - `batch_fetch_size=30`이 제대로 작동하는가?
  - 예상: 1 + ceil(10/30) = 2 쿼리 (batch로 통합)

- [ ] **Store → Cheer → CheerImage 중첩**
  - `GET /api/shops/42` 응답에 Cheer 정보 포함 여부
  - 포함된다면 추가 N+1 쿼리 발생 가능성

#### 확인 방법

```bash
# Hibernate 쿼리 로그 확인
docker logs eatda-app 2>&1 | grep "Hibernate: select" | grep "CheerImage" | wc -l

# 기대값: batch_fetch_size 작동 시 ~150회 (1,440 / 10 = 144 batch)
# 실제 N+1 발생 시: ~14,400회 (1,440 × 10)

# 쿼리 패턴 확인
docker logs eatda-app 2>&1 | grep "WHERE.*IN" | tail -20
```

### 6.2 DB 캐싱 부재 영향

#### 체크리스트

- [ ] **동일 storeId=42 반복 조회**
  - `GET /api/shops/42` 1,440회 호출 시 모두 DB 히트하는가?
  - 애플리케이션 레벨 캐싱(예: Spring Cache, Caffeine) 없다면 매번 DB 조회
  - DB CPU 부하 증가 예상

- [ ] **MySQL Query Cache**
  - MySQL 8.0은 Query Cache 제거됨 (InnoDB Buffer Pool만 사용)
  - 동일 쿼리 반복 시 Buffer Pool Hit 증가 예상
  - 하지만 여전히 쿼리 파싱/최적화 오버헤드 존재

#### 확인 방법

```bash
# MySQL Buffer Pool Hit Rate 확인
docker exec eatda-mysql mysql -u root -proot -e "
  SHOW STATUS LIKE 'Innodb_buffer_pool%';
"

# 기대값: Innodb_buffer_pool_read_requests >> Innodb_buffer_pool_reads
# (메모리에서 대부분 처리)

# DB CPU 사용률 확인
docker stats eatda-mysql
```

### 6.3 DB 커넥션 풀 경합

#### 체크리스트

- [ ] **72 req/s 시 커넥션 풀 사용률**
  - 평균 응답 시간 200ms 가정
  - 필요 커넥션: 72 req/s × 0.2s = 14.4개
  - 기본 10개로 부족 → 대기 발생 가능

- [ ] **HikariCP pending 커넥션**
  - `hikaricp.connections.pending` 메트릭 확인
  - 0 초과 시 커넥션 대기 발생

#### 확인 방법

```bash
# 커넥션 풀 메트릭 확인
curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active | jq
curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.pending | jq
curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.acquire | jq

# 커넥션 획득 시간 확인
# 기대값: p95 < 100ms (여유 있음)
# 경합 발생 시: p95 > 500ms
```

---

## 7. 예상 병목 및 대응

### 7.1 예상 병목

| 병목 | 증상 | 원인 | 대응 |
|------|------|------|------|
| **N+1 쿼리** | P95 > 1s, DB CPU 높음 | CheerImage lazy 로드 | `@EntityGraph` 적용 또는 `fetch join` |
| **DB 커넥션 부족** | Pending > 0, 타임아웃 증가 | 72 req/s > 10 pool | HikariCP pool 증설 (20개) |
| **캐싱 부재** | DB CPU 60%+, 동일 쿼리 반복 | 애플리케이션 캐시 없음 | Spring Cache + Caffeine 도입 |
| **CPU 크레딧 소진** | 30분 후 성능 급락 | t3.medium 크레딧 소진 | t3.unlimited 또는 m5.large 고려 |

### 7.2 대응 방안

#### N+1 쿼리 해결

```java
// Before: N+1 쿼리 발생
@GetMapping("/api/shops/{storeId}/cheers")
public ResponseEntity<StoreCheersResponse> getCheers(@PathVariable Long storeId) {
    List<Cheer> cheers = cheerRepository.findByStoreId(storeId);
    // 각 Cheer마다 CheerImage 개별 조회 (N+1)
    return ResponseEntity.ok(StoreCheersResponse.from(cheers));
}

// After: @EntityGraph로 해결
@EntityGraph(attributePaths = {"cheerImages"})
List<Cheer> findByStoreIdWithImages(@Param("storeId") Long storeId);
```

#### DB 커넥션 풀 증설

```yaml
# application-load-test.yml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20  # 10 → 20 증설
      minimum-idle: 10
      connection-timeout: 5000
```

#### 애플리케이션 캐싱 도입

```java
@Cacheable(value = "stores", key = "#storeId")
@GetMapping("/api/shops/{storeId}")
public ResponseEntity<StoreDetailResponse> getStore(@PathVariable Long storeId) {
    Store store = storeService.getStore(storeId);
    return ResponseEntity.ok(StoreDetailResponse.from(store));
}
```

---

## 8. 결과 분석

### 8.1 K6 출력 예시 (성공 케이스)

```
     ✓ hotspot status is 200
     ✓ hotspot response time < 1000ms

     checks.........................: 98.5% ✓ 8500      ✗ 130
     data_received..................: 125 MB  69 kB/s
     data_sent......................: 18 MB   10 kB/s
     http_req_duration..............: avg=320ms   min=15ms   med=280ms  max=1.8s   p(95)=720ms
     http_req_failed................: 0.5%    ✓ 43       ✗ 8500
     http_reqs......................: 129,600 72 req/s
     iteration_duration.............: avg=3.5s    min=3s     med=3.2s   max=5.2s   p(95)=4.1s
     iterations.....................: 32,400  18/s
     vus............................: 60      min=0       max=60
```

### 8.2 판정 기준

#### ✅ 성공 (다음 조건 모두 충족)

- [ ] 평균 응답 시간 < 500ms
- [ ] P95 응답 시간 < 1000ms
- [ ] 에러율 < 1%
- [ ] CPU 사용률 < 90%
- [ ] 메모리 사용률 < 85%
- [ ] DB 커넥션 pending < 5개

#### ⚠️ 주의 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 500-1000ms
- [ ] P95 응답 시간 1000-2000ms
- [ ] 에러율 1-5%
- [ ] CPU 사용률 90-100%
- [ ] DB 커넥션 pending 5-10개

#### 🚨 실패 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 > 1000ms
- [ ] P95 응답 시간 > 2000ms
- [ ] 에러율 > 5%
- [ ] DB 타임아웃 다수 발생
- [ ] OOM 발생

---

## 9. 다음 단계

### 9.1 성공 시

- ✅ 시나리오 3 진행: [SNS 바이럴 트래픽 (저녁 피크)](03_scenario_viral.md)
- ✅ 핫플레이스 트래픽 집중 패턴 검증 완료
- ✅ N+1 쿼리 해결 여부 확인

### 9.2 최적화 필요 시

- 🔧 **N+1 쿼리 발견**: `@EntityGraph` 적용
- 🔧 **DB 커넥션 부족**: HikariCP pool size 증설 (20개)
- 🔧 **캐싱 필요**: Spring Cache + Caffeine 도입

### 9.3 실패 시

- 🚨 **N+1 쿼리 긴급 수정**: `fetch join` 또는 `@BatchSize` 적용
- 🚨 **DB 커넥션 풀 긴급 증설**: 20-30개로 증설
- 🚨 **Read Replica 고려**: 읽기 트래픽 분산

---

## 10. 참고 자료

- [00_load_test_prerequisites.md](00_load_test_prerequisites.md) — 테스트 전제 조건
- [01_scenario_baseline.md](01_scenario_baseline.md) — 시나리오 1 (Baseline)
- [K6 Stages Documentation](https://k6.io/docs/using-k6/k6-options/reference/#stages)
- [HikariCP Tuning](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing)
- [Spring Cache Documentation](https://docs.spring.io/spring-framework/docs/current/reference/html/integration.html#cache)

---

## 문서 이력

| 버전 | 날짜 | 작성자 | 변경 내역 |
|------|------|--------|----------|
| 1.0 | 2026-06-26 | System | 초기 작성 (프론트엔드 멀티 API 호출 패턴 반영) |
