# 시나리오 6 — DB 슬로우 쿼리 발생

## 문서 개요

**시나리오 유형**: Database Performance Test (Slow Query)  
**난이도**: ⭐⭐⭐ (높음)  
**목적**: 특정 쿼리가 예상보다 오래 걸려 커넥션 풀 고갈 시 영향 확인  
**작성일**: 2026-06-26  
**예상 소요 시간**: 15분

---

## 1. 시나리오 배경

### 1.1 비즈니스 컨텍스트

```
상황:
  - 복잡한 필터링/정렬 쿼리 실행
  - 인덱스 미적용 시 Full Table Scan 발생
  - 특정 API의 쿼리가 5초 소요

트래픽 특성:
  - 평상시: 모든 쿼리 50ms 이내
  - 슬로우 쿼리 발생: GET /api/stories?district=성수동&sort=latest&size=50
  - 해당 API 호출 빈도: 2 req/s
```

### 1.2 시나리오 목적

- 슬로우 쿼리 발생 시 커넥션 풀 고갈 확인
- 다른 정상 API의 영향 확인
- Slow query log로 원인 쿼리 식별 가능 여부 확인
- HikariCP connection timeout 설정 검증

---

## 2. 트래픽 프로필

### 2.1 정상 상태 (0-5분)

```yaml
Virtual Users (VUs): 30명 동시 접속
Think Time: 5초

사용자 여정:
  - 80%: 일반 API (홈, 가게 상세) - 평균 100ms
  - 20%: 필터링 검색 - 평균 100ms (정상)

예상 트래픽:
  - 30 VU × 0.2 req/s = 6 req/s
  - 필요 커넥션: 6 req/s × 0.1s = 0.6개
```

### 2.2 슬로우 쿼리 발생 (5-10분)

```yaml
슬로우 쿼리 주입:
  - GET /api/stories?district=성수동&sort=latest&size=50
  - 응답 시간: 5초 (Full Table Scan)
  - 호출 빈도: 20% × 30 VU / 5s = 1.2 req/s

필요 커넥션 계산:
  - 슬로우 쿼리: 1.2 req/s × 5s = 6개
  - 일반 API: 4.8 req/s × 0.1s = 0.5개
  - 총: 6.5개 (HikariCP 20개 풀의 32.5%)

주의: 10 req/s로 증가 시
  - 슬로우 쿼리: 2 req/s × 5s = 10개
  - 일반 API: 8 req/s × 0.1s = 0.8개
  - 총: 10.8개 (54%) → 여유 있음

위험: 20 req/s로 증가 시
  - 슬로우 쿼리: 4 req/s × 5s = 20개
  - 커넥션 풀 고갈 → 대기 발생
```

### 2.3 복구 상태 (10-15분)

```yaml
인덱스 추가 시뮬레이션:
  - 슬로우 쿼리 개선: 5s → 50ms
  - 필요 커넥션: 1.2 req/s × 0.05s = 0.06개
  - 정상화 확인
```

---

## 3. 환경 설정

### 3.1 서버 리소스

```yaml
CPU: 2 vCPU (t3.medium 시뮬레이션)
Memory: 4 GB
JVM Heap: -Xms2g -Xmx2.5g
Database: MySQL 8.0 (HikariCP pool size: 20)
HikariCP connection-timeout: 30초
```

### 3.2 슬로우 쿼리 주입 방법

```sql
-- 테스트 데이터: Story 10,000개 생성 (대량 데이터)
-- district 컬럼에 인덱스 제거
ALTER TABLE story DROP INDEX idx_district;

-- 슬로우 쿼리 발생
SELECT s.*, si.image_url
FROM story s
LEFT JOIN story_image si ON s.id = si.story_id
WHERE s.district = '성수동'
ORDER BY s.created_at DESC
LIMIT 50;

-- 실행 계획 확인 (Full Table Scan)
EXPLAIN SELECT ...;
-- type: ALL (Full Table Scan)
-- rows: 10,000

-- 인덱스 추가 후 (복구)
CREATE INDEX idx_district_created_at ON story(district, created_at DESC);

-- 실행 계획 확인 (Index Scan)
EXPLAIN SELECT ...;
-- type: ref (Index Scan)
-- rows: 100
```

---

## 4. 성공 기준

### 4.1 성능 목표 (슬로우 쿼리 발생 시)

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **슬로우 쿼리 응답 시간** | - | 5000ms (의도적) |
| **일반 API 평균 응답 시간** | < 300ms | < 1000ms |
| **일반 API 에러율** | < 5% | < 10% |
| **DB 커넥션 pending** | < 5개 | < 10개 |

### 4.2 모니터링 목표

- ✅ **Slow query log 기록**: 5초 쿼리 자동 감지
- ✅ **HikariCP 메트릭**: pending 커넥션 즉시 파악
- ✅ **Alert 발생**: 커넥션 풀 사용률 80% 초과 시

---

## 5. 테스트 실행

### 5.1 테스트 데이터 준비

```sql
-- MySQL 슬로우 쿼리 로그 활성화
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;  -- 1초 이상 쿼리 기록
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Story 테이블 대량 데이터 생성 (10,000개)
-- data-generator 스크립트 실행

-- district 인덱스 제거 (슬로우 쿼리 유발)
ALTER TABLE story DROP INDEX IF EXISTS idx_district;
ALTER TABLE story DROP INDEX IF EXISTS idx_district_created_at;
```

### 5.2 K6 스크립트

```javascript
// scripts/scenario6_slow_query.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const slowQueryLatency = new Trend('slow_query_latency');
const generalAPILatency = new Trend('general_api_latency');

export const options = {
  stages: [
    { duration: '5m', target: 30 },   // 정상 상태
    { duration: '5m', target: 30 },   // 슬로우 쿼리 발생
    { duration: '5m', target: 30 },   // 복구 상태
  ],
  thresholds: {
    'general_api_latency': ['p(95)<1000'],  // 일반 API는 1초 이내
    'errors': ['rate<0.1'],
  },
};

const BASE_URL = 'http://localhost:8080';

export default function() {
  const isFilterSearch = Math.random() < 0.2;  // 20%는 필터링 검색
  
  if (isFilterSearch) {
    // 필터링 검색 (슬로우 쿼리 가능성)
    const slowStart = Date.now();
    const searchRes = http.get(
      `${BASE_URL}/api/stories?district=성수동&sort=latest&size=50`,
      { timeout: '10s' }
    );
    
    slowQueryLatency.add(Date.now() - slowStart);
    
    const success = check(searchRes, {
      'filter search status is 200': (r) => r.status === 200,
      'filter search response time < 10s': (r) => r.timings.duration < 10000,
    });
    errorRate.add(!success);
    
    sleep(5);
    
  } else {
    // 일반 API 호출
    const generalStart = Date.now();
    const homeRequests = [
      { method: 'GET', url: `${BASE_URL}/api/stories?size=20` },
      { method: 'GET', url: `${BASE_URL}/api/shops?size=20` },
    ];
    
    const responses = http.batch(homeRequests);
    generalAPILatency.add(Date.now() - generalStart);
    
    responses.forEach(res => {
      const success = check(res, {
        'general API status is 200': (r) => r.status === 200,
        'general API response time < 1000ms': (r) => r.timings.duration < 1000,
      });
      errorRate.add(!success);
    });
    
    sleep(5);
  }
}
```

### 5.3 실행 및 인덱스 추가

```bash
# 1. K6 테스트 시작
k6 run --out json=results/scenario6.json \
       scripts/scenario6_slow_query.js

# 2. 10분 후 인덱스 추가 (복구)
docker exec eatda-mysql mysql -u root -proot eatda -e "
  CREATE INDEX idx_district_created_at ON story(district, created_at DESC);
"

# 3. 모니터링
# HikariCP 커넥션 풀 모니터링
watch -n 2 "curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active | jq; \
            curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.pending | jq"

# Slow query log 확인
docker exec eatda-mysql tail -f /var/log/mysql/slow-query.log
```

---

## 6. 검증 사항

### 6.1 커넥션 풀 고갈

#### 체크리스트

- [ ] **슬로우 쿼리 시 커넥션 사용률**
  - 1.2 req/s × 5s = 6개 커넥션 점유
  - 20개 풀의 30% → 안전
  - 하지만 트래픽 증가 시 위험

- [ ] **pending 커넥션 발생**
  - `hikaricp.connections.pending > 0` 시 대기 발생
  - 대기 시간: `connection-timeout` 설정값 (30초)
  - 30초 초과 시 `SQLTransientConnectionException` 발생

- [ ] **일반 API 영향**
  - 커넥션 부족으로 일반 API도 지연
  - 평균 응답 시간 100ms → 500ms 증가

#### 확인 방법

```bash
# 커넥션 풀 메트릭 확인
curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active | jq
curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.pending | jq
curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.acquire | jq

# 기대값 (슬로우 쿼리 발생 시):
# - active: 6-8개 (슬로우 쿼리) + 1-2개 (일반 API) = 7-10개
# - pending: 0-2개 (일시적 대기)
# - acquire p95: 100-500ms

# 위험 (트래픽 증가 시):
# - active: 18-20개 (풀 고갈 직전)
# - pending: 5-10개 (대기 증가)
# - acquire p95: 1000-5000ms
```

### 6.2 슬로우 쿼리 식별

#### 체크리스트

- [ ] **MySQL Slow Query Log 기록**
  - `long_query_time = 1` 설정 확인
  - 5초 쿼리 자동 기록
  - Query time, Lock time, Rows examined 확인

- [ ] **EXPLAIN 분석**
  - `type: ALL` → Full Table Scan 확인
  - `rows: 10,000` → 전체 테이블 스캔 확인
  - 인덱스 추가 후 `type: ref` 확인

#### 확인 방법

```bash
# Slow query log 확인
docker exec eatda-mysql tail -100 /var/log/mysql/slow-query.log

# 예시 출력:
# Time: 2026-06-26T12:15:43.123456Z
# User@Host: eatda[eatda] @ localhost []
# Query_time: 5.234567  Lock_time: 0.000123  Rows_sent: 50  Rows_examined: 10000
# SELECT s.*, si.image_url FROM story s LEFT JOIN story_image si ...

# EXPLAIN 분석
docker exec eatda-mysql mysql -u root -proot eatda -e "
  EXPLAIN SELECT s.*, si.image_url 
  FROM story s 
  LEFT JOIN story_image si ON s.id = si.story_id 
  WHERE s.district = '성수동' 
  ORDER BY s.created_at DESC 
  LIMIT 50;
"

# 슬로우 쿼리 발생 시:
# +----+-------------+-------+------+---------------+------+---------+------+-------+-------+
# | id | select_type | table | type | possible_keys | key  | key_len | ref  | rows  | Extra |
# +----+-------------+-------+------+---------------+------+---------+------+-------+-------+
# |  1 | SIMPLE      | s     | ALL  | NULL          | NULL | NULL    | NULL | 10000 | Using where; Using filesort |
```

### 6.3 인덱스 추가 효과

#### 체크리스트

- [ ] **쿼리 응답 시간 개선**
  - Before: 5000ms
  - After: 50ms (100배 개선)

- [ ] **커넥션 풀 사용률 감소**
  - Before: 6개 (30%)
  - After: 0.06개 (0.3%)

- [ ] **일반 API 정상화**
  - 평균 응답 시간: 500ms → 100ms 복구

#### 확인 방법

```bash
# 인덱스 추가 후 EXPLAIN 재확인
docker exec eatda-mysql mysql -u root -proot eatda -e "
  EXPLAIN SELECT s.*, si.image_url 
  FROM story s 
  LEFT JOIN story_image si ON s.id = si.story_id 
  WHERE s.district = '성수동' 
  ORDER BY s.created_at DESC 
  LIMIT 50;
"

# 인덱스 적용 후:
# +----+-------------+-------+------+---------------------------+---------------------------+---------+------+------+-------+
# | id | select_type | table | type | possible_keys             | key                       | key_len | ref  | rows | Extra |
# +----+-------------+-------+------+---------------------------+---------------------------+---------+------+------+-------+
# |  1 | SIMPLE      | s     | ref  | idx_district_created_at   | idx_district_created_at   | 767     | const| 100  | Using where |

# K6 결과에서 응답 시간 추이 확인
jq '.metrics.slow_query_latency' results/scenario6.json
```

---

## 7. 예상 병목 및 대응

### 7.1 예상 병목

| 병목 | 증상 | 원인 | 대응 |
|------|------|------|------|
| **Full Table Scan** | 쿼리 5s 소요 | district 인덱스 없음 | 복합 인덱스 추가 |
| **커넥션 풀 고갈** | pending > 5개, 타임아웃 발생 | 슬로우 쿼리 장시간 점유 | 인덱스 추가 + 풀 증설 |
| **일반 API 지연** | 평균 응답 500ms | 커넥션 대기 발생 | 슬로우 쿼리 긴급 최적화 |

### 7.2 대응 방안

#### 인덱스 추가

```sql
-- 복합 인덱스 (district + created_at)
CREATE INDEX idx_district_created_at ON story(district, created_at DESC);

-- 커버링 인덱스 (쿼리 최적화)
CREATE INDEX idx_district_created_at_id ON story(district, created_at DESC, id);

-- 인덱스 효과 확인
SHOW INDEX FROM story;
```

#### 쿼리 최적화

```java
// Before: N+1 쿼리 + Full Table Scan
@Query("SELECT s FROM Story s WHERE s.district = :district ORDER BY s.createdAt DESC")
List<Story> findByDistrictOrderByCreatedAtDesc(
    @Param("district") String district, 
    Pageable pageable
);

// After: JOIN FETCH + 인덱스 활용
@Query("SELECT s FROM Story s " +
       "LEFT JOIN FETCH s.storyImages " +
       "WHERE s.district = :district " +
       "ORDER BY s.createdAt DESC")
List<Story> findByDistrictWithImagesOrderByCreatedAtDesc(
    @Param("district") String district, 
    Pageable pageable
);
```

---

## 8. 결과 분석

### 8.1 K6 출력 예시 (성공 케이스)

```
     ✓ general API status is 200
     ✗ filter search response time < 10s (슬로우 구간)

     checks.........................: 92.3% ✓ 4,150     ✗ 340
     slow_query_latency.............: avg=4.8s  (5-10분 구간)
                                      avg=65ms  (10-15분 복구 후)
     general_api_latency............: avg=280ms (5-10분 구간)
                                      avg=95ms  (10-15분 복구 후)
     http_req_duration..............: avg=720ms   min=18ms   med=180ms  max=9.5s   p(95)=5.2s
     hikaricp_active_connections....: max=9      (슬로우 구간)
     hikaricp_pending_connections...: max=2      (일시적)
```

### 8.2 판정 기준

#### ✅ 성공 (다음 조건 모두 충족)

- [ ] 슬로우 쿼리 로그 기록 확인
- [ ] 일반 API 에러율 < 10% (격리 성공)
- [ ] 커넥션 pending < 10개
- [ ] 인덱스 추가 후 쿼리 시간 < 100ms
- [ ] 복구 후 정상화 시간 < 1분

#### 🚨 실패 (다음 중 하나라도 해당)

- [ ] 일반 API 에러율 > 20% (격리 실패)
- [ ] 커넥션 pending > 10개 (풀 고갈)
- [ ] 타임아웃 에러 다수 발생
- [ ] 인덱스 추가 후에도 쿼리 > 1s

---

## 9. 다음 단계

### 9.1 성공 시

- ✅ 전체 시나리오 완료
- ✅ 슬로우 쿼리 감지 및 대응 검증 완료
- ✅ [00_load_test_prerequisites.md](00_load_test_prerequisites.md) 의사결정 기준 적용

### 9.2 최적화 필요 시

- 🔧 **인덱스 추가**: district, created_at 복합 인덱스
- 🔧 **쿼리 리팩토링**: JOIN FETCH로 N+1 해결
- 🔧 **페이징 개선**: Cursor 기반 페이징 도입

### 9.3 실패 시

- 🚨 **긴급 인덱스 추가**: 즉시 적용
- 🚨 **커넥션 풀 긴급 증설**: 20 → 30개
- 🚨 **해당 API 비활성화**: 임시 404 응답

---

## 10. 참고 자료

- [00_load_test_prerequisites.md](00_load_test_prerequisites.md) — 테스트 전제 조건
- [MySQL Slow Query Log](https://dev.mysql.com/doc/refman/8.0/en/slow-query-log.html)
- [MySQL EXPLAIN](https://dev.mysql.com/doc/refman/8.0/en/explain.html)
- [HikariCP Troubleshooting](https://github.com/brettwooldridge/HikariCP/wiki/Bad-Behavior:-Starvation)

---

## 문서 이력

| 버전 | 날짜 | 작성자 | 변경 내역 |
|------|------|--------|----------|
| 1.0 | 2026-06-26 | System | 초기 작성 (슬로우 쿼리 시나리오) |
