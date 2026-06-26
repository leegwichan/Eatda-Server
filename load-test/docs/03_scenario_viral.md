# 시나리오 3 — SNS 바이럴 트래픽 (저녁 피크)

## 문서 개요

**시나리오 유형**: Spike Load Test (Viral Traffic)  
**난이도**: ⭐⭐⭐ (높음)  
**목적**: 특정 스토리가 SNS에서 공유되어 트래픽이 급증할 때 서버 성능 검증  
**작성일**: 2026-06-26  
**예상 소요 시간**: 1시간

---

## 1. 시나리오 배경

### 1.1 비즈니스 컨텍스트

```
상황:
  - 뽈레의 특정 리뷰(스토리)가 SNS(카톡방, 인스타그램)에서 공유
  - 저녁시간(19:00-20:00) "이 리뷰 읽고 싶어!" 클릭 몰림
  - 홈 탭 진입 트래픽 급증

트래픽 특성:
  - 기본 저녁 피크: 0.42-0.7 세션/s
  - 바이럴 추가 유입: 2-3 세션/s
  - 총: 2.5-3.7 세션/s
  
  - 주요 경로:
    * 홈(/) 진입 → GET /api/stories?size=20 (50%)
    * 특정 스토리 상세 → GET /api/stories/{id} (30%)
    * 해당 가게 상세 → GET /api/shops/{id} (20%)
```

### 1.2 시나리오 목적

- 홈 탭 진입 시 3개 API 동시 호출 패턴의 부하 확인
- `GET /api/stories?size=20` 반복 조회 시 DB 부하 확인
- N+1 쿼리 (Story → StoryImage lazy 로드) 영향 확인
- 캐싱 부재 시 성능 저하 정도 측정

---

## 2. 트래픽 프로필

### 2.1 사용자 행동 패턴

```typescript
// 신규 유입 사용자 (50%)
// 홈 탭 진입 (3개 API 동시 호출)
GET /api/stories?size=20
GET /api/cheer?size=20
GET /api/shops?size=20

// 스토리 상세 조회 (30%)
GET /api/stories/{id}

// 가게 상세 조회 (20%)
GET /api/shops/{id}
GET /api/shops/{id}/cheers?size=10
GET /api/shops/{id}/images
GET /api/shops/{id}/tags
```

### 2.2 시나리오 설정

```yaml
Virtual Users (VUs): 100명 동시 접속
Duration: 1시간
Ramp-up: 10분 (0명 → 100명 점진적 증가)
Sustain: 40분 (100명 유지)
Ramp-down: 10분 (100명 → 0명 점진적 감소)
Think Time: 4초 (페이지 간 이동 대기 시간)

트래픽 분포:
  - 50% (50 VU): 홈 탭 반복 새로고침
  - 30% (30 VU): 스토리 상세 조회
  - 20% (20 VU): 가게 상세 조회

사용자 여정 (홈 탭 그룹):
  1. 홈 탭 진입 (3 req) → 4초 대기
  2. 반복
  → 3 req / 4초 = 0.75 req/s per VU

예상 전체 트래픽:
  - 홈 탭 그룹: 50 VU × 0.75 req/s = 37.5 req/s
  - 스토리 상세 그룹: 30 VU × 0.25 req/s = 7.5 req/s
  - 가게 상세 그룹: 20 VU × 1 req/s = 20 req/s
  - 총: 65 req/s
```

### 2.3 API 엔드포인트 분포

| API | 호출 빈도 | 비율 |
|-----|----------|------|
| `GET /api/stories?size=20` | ~4,500회/1시간 | 23% |
| `GET /api/cheer?size=20` | ~4,500회/1시간 | 23% |
| `GET /api/shops?size=20` | ~4,500회/1시간 | 23% |
| `GET /api/stories/{id}` | ~2,700회/1시간 | 14% |
| `GET /api/shops/{id}` | ~1,800회/1시간 | 9% |
| 기타 (가게 상세 sub API) | ~1,800회/1시간 | 8% |

---

## 3. 환경 설정

### 3.1 서버 리소스

```yaml
CPU: 2 vCPU (t3.medium 시뮬레이션)
Memory: 4 GB
JVM Heap: -Xms2g -Xmx2.5g
Database: MySQL 8.0 (HikariCP pool size: 20)  # 시나리오 2 결과 반영
```

### 3.2 테스트 데이터

```
Members: 1,000명
Stores: 500개
Cheers: 5,000개
Stories: 2,000개
  - 최근 24시간 이내: 200개 (홈 탭에서 주로 조회)
CheerImages: 10,000개
StoryImages: 5,000개 (각 Story당 평균 2.5개)
```

---

## 4. 성공 기준

### 4.1 성능 목표

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **평균 응답 시간** | < 300ms | < 700ms |
| **P95 응답 시간** | < 800ms | < 1500ms |
| **P99 응답 시간** | < 1500ms | < 3000ms |
| **에러율** | < 1% | < 5% |
| **처리량** | > 60 req/s | > 50 req/s |

### 4.2 리소스 사용률

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **CPU 사용률** | 70-90% | < 95% |
| **메모리 사용률** | < 75% | < 90% |
| **DB 커넥션 풀** | < 70% (14/20) | < 90% (18/20) |
| **JVM Heap** | < 2.2 GB | < 2.4 GB |

### 4.3 안정성 목표

- ✅ **Graceful Degradation**: 부하 증가 시 점진적 성능 저하 (급격한 에러 증가 없음)
- ✅ **메모리 누수 없음**: 1시간 동안 Heap 사용량이 일정 범위 유지
- ✅ **GC 일시 정지**: P95 GC < 300ms

---

## 5. 테스트 실행

### 5.1 K6 스크립트

```javascript
// scripts/scenario3_viral.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const homeLoadTime = new Trend('home_load_time');

export const options = {
  stages: [
    { duration: '10m', target: 100 },  // Ramp-up
    { duration: '40m', target: 100 },  // Sustain
    { duration: '10m', target: 0 },    // Ramp-down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1500', 'p(99)<3000'],
    'http_req_failed': ['rate<0.05'],
    'errors': ['rate<0.05'],
  },
};

const BASE_URL = 'http://localhost:8080';

export default function() {
  const userType = Math.random();
  
  if (userType < 0.5) {
    // 50%: 홈 탭 반복 조회
    const homeStart = Date.now();
    const homeRequests = [
      { method: 'GET', url: `${BASE_URL}/api/stories?size=20` },
      { method: 'GET', url: `${BASE_URL}/api/cheer?size=20` },
      { method: 'GET', url: `${BASE_URL}/api/shops?size=20` },
    ];
    
    const responses = http.batch(homeRequests);
    homeLoadTime.add(Date.now() - homeStart);
    
    responses.forEach(res => {
      const success = check(res, {
        'home tab status is 200': (r) => r.status === 200,
        'home tab response time < 1500ms': (r) => r.timings.duration < 1500,
      });
      errorRate.add(!success);
    });
    
    sleep(4);
    
  } else if (userType < 0.8) {
    // 30%: 스토리 상세 조회
    const storyId = Math.floor(Math.random() * 200) + 1;
    const storyRes = http.get(`${BASE_URL}/api/stories/${storyId}`);
    
    const success = check(storyRes, {
      'story detail status is 200': (r) => r.status === 200,
      'story detail response time < 1500ms': (r) => r.timings.duration < 1500,
    });
    errorRate.add(!success);
    
    sleep(5);
    
  } else {
    // 20%: 가게 상세 조회
    const storeId = Math.floor(Math.random() * 500) + 1;
    const storeDetailRequests = [
      { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}` },
      { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/cheers?size=10` },
      { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/images` },
      { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/tags` },
    ];
    
    const responses = http.batch(storeDetailRequests);
    responses.forEach(res => {
      const success = check(res, {
        'store detail status is 200': (r) => r.status === 200,
      });
      errorRate.add(!success);
    });
    
    sleep(4);
  }
}
```

### 5.2 실행

```bash
# 시나리오 3 실행
k6 run --out json=results/scenario3.json \
       scripts/scenario3_viral.js

# InfluxDB 연동 + Grafana 실시간 모니터링
k6 run --out influxdb=http://localhost:8086/k6 \
       scripts/scenario3_viral.js
```

### 5.3 모니터링

```bash
# CPU 크레딧 소진 확인 (t3.medium 특성)
# 예상: 40분 후 크레딧 소진 → CPU 성능 저하
watch -n 10 "docker stats eatda-app --no-stream | awk '{print \$3}'"

# JVM GC 모니터링
watch -n 5 "curl -s http://localhost:8080/actuator/metrics/jvm.gc.pause | jq '.measurements[] | select(.statistic==\"MAX\")'"

# DB 커넥션 풀 모니터링
watch -n 5 "curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active | jq '.measurements[0].value'"
```

---

## 6. 검증 사항

### 6.1 홈 탭 반복 조회 부하

#### 체크리스트

- [ ] **`GET /api/stories?size=20` 반복 호출**
  - 4,500회/1시간 = 1.25 req/s
  - 매번 DB에서 Story 20개 + StoryImage lazy 로드
  - N+1 쿼리 발생 시: 1 + 20 = 21 쿼리 × 1.25 req/s = 26 쿼리/s
  - batch_fetch_size 작동 시: 2 쿼리 × 1.25 req/s = 2.5 쿼리/s

- [ ] **캐싱 부재 시 DB CPU 부하**
  - 홈 탭 데이터는 실시간성이 낮음 (5분 캐싱 가능)
  - 캐싱 없이 매번 DB 조회 시 DB CPU 60-80% 예상

#### 확인 방법

```bash
# Story 조회 쿼리 빈도 확인
docker logs eatda-app 2>&1 | grep "from story" | wc -l

# DB CPU 확인
docker stats eatda-mysql --no-stream

# 기대값: 캐싱 있으면 DB CPU 30-40%, 없으면 60-80%
```

### 6.2 N+1 쿼리 (Story → StoryImage)

#### 체크리스트

- [ ] **StoryImage lazy 로딩**
  - `GET /api/stories?size=20` 응답에 각 Story의 이미지 포함
  - N+1 발생 시: 1 (Stories) + 20 (각 Story의 Images) = 21 쿼리
  - batch_fetch_size 작동 시: 1 + ceil(20/30) = 2 쿼리

- [ ] **P95 응답 시간 영향**
  - N+1 발생: 21 쿼리 × 10ms = 210ms overhead
  - batch 적용: 2 쿼리 × 10ms = 20ms overhead

#### 확인 방법

```bash
# StoryImage 쿼리 패턴 확인
docker logs eatda-app 2>&1 | grep "StoryImage" | grep "IN (" | wc -l

# 기대값: batch 작동 시 ~4,500회 (stories 조회 횟수)
# N+1 발생 시: ~90,000회 (stories × 20)
```

### 6.3 CPU 크레딧 소진 (t3.medium)

#### 체크리스트

- [ ] **지속적인 높은 CPU 사용 (70-90%)**
  - t3.medium CPU 크레딧: 초기 288개
  - 70% 사용 시 소모: 시간당 60 크레딧
  - 40분 후 크레딧 소진: 288 - (60 × 40/60) = 248개 남음 (여유 있음)
  - 90% 사용 시 소모: 시간당 84 크레딧
  - 40분 후 크레딧 소진: 288 - (84 × 40/60) = 232개 남음

- [ ] **크레딧 소진 후 성능 저하**
  - CPU 사용률 20%로 제한 → 응답 시간 급증
  - P95 응답 시간 2-3배 증가 예상

#### 확인 방법

```bash
# CPU 사용률 추이 모니터링
docker stats eatda-app --format "{{.CPUPerc}}" | tee cpu_usage.log

# K6 결과에서 시간대별 응답 시간 추이 확인
# 40분 이후 응답 시간 급증 여부 확인
```

---

## 7. 예상 병목 및 대응

### 7.1 예상 병목

| 병목 | 증상 | 원인 | 대응 |
|------|------|------|------|
| **캐싱 부재** | DB CPU 60-80%, 동일 쿼리 반복 | 홈 탭 데이터 매번 DB 조회 | Spring Cache + Redis 도입 |
| **N+1 쿼리** | P95 > 1.5s, 쿼리 수 폭발 | Story → StoryImage lazy 로드 | `@EntityGraph` 적용 |
| **CPU 크레딧 소진** | 40분 후 성능 급락 | t3.medium 크레딧 한계 | t3.unlimited 또는 m5.large |
| **GC 빈도 증가** | GC pause 100ms+, throughput 저하 | Heap 부족 | Heap 증설 (3GB) |

### 7.2 대응 방안

#### 홈 탭 캐싱 도입

```java
// StoriesController.java
@Cacheable(value = "stories", key = "#size")
@GetMapping("/api/stories")
public ResponseEntity<StoriesResponse> getStories(
    @RequestParam(defaultValue = "20") int size
) {
    List<Story> stories = storyService.getRecentStories(size);
    return ResponseEntity.ok(StoriesResponse.from(stories));
}

// CacheConfig.java
@Configuration
@EnableCaching
public class CacheConfig {
    @Bean
    public CacheManager cacheManager() {
        return new CaffeineCacheManager("stories", "shops", "cheers");
    }
    
    @Bean
    public Caffeine<Object, Object> caffeineConfig() {
        return Caffeine.newBuilder()
            .expireAfterWrite(5, TimeUnit.MINUTES)  // 5분 캐싱
            .maximumSize(100)
            .recordStats();
    }
}
```

#### N+1 쿼리 해결

```java
// StoryRepository.java
@EntityGraph(attributePaths = {"storyImages", "member"})
List<Story> findTop20ByOrderByCreatedAtDesc();
```

---

## 8. 결과 분석

### 8.1 K6 출력 예시 (성공 케이스)

```
     ✓ home tab status is 200
     ✓ home tab response time < 1500ms

     checks.........................: 96.8% ✓ 18,500    ✗ 610
     data_received..................: 285 MB  79 kB/s
     data_sent......................: 32 MB   8.9 kB/s
     http_req_duration..............: avg=420ms   min=18ms   med=350ms  max=2.8s   p(95)=980ms
     http_req_failed................: 1.2%    ✓ 230      ✗ 19,000
     http_reqs......................: 234,000 65 req/s
     home_load_time.................: avg=650ms   min=50ms   med=580ms  max=3.2s   p(95)=1.3s
     iteration_duration.............: avg=4.8s    min=4s     med=4.5s   max=8.2s   p(95)=6.1s
     iterations.....................: 58,500  16.25/s
     vus............................: 0-100   min=0       max=100
```

### 8.2 판정 기준

#### ✅ 성공 (다음 조건 모두 충족)

- [ ] 평균 응답 시간 < 700ms
- [ ] P95 응답 시간 < 1500ms
- [ ] 에러율 < 5%
- [ ] CPU 사용률 < 95%
- [ ] 메모리 사용률 < 90%
- [ ] 홈 탭 로딩 시간 P95 < 2초

#### ⚠️ 주의 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 700-1500ms
- [ ] P95 응답 시간 1500-3000ms
- [ ] 에러율 5-10%
- [ ] 40분 후 성능 급격히 저하 (CPU 크레딧 소진)

#### 🚨 실패 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 > 1500ms
- [ ] P95 응답 시간 > 3000ms
- [ ] 에러율 > 10%
- [ ] DB 타임아웃 다수 발생
- [ ] OOM 발생

---

## 9. 다음 단계

### 9.1 성공 시

- ✅ 시나리오 4 진행: [쓰기 트래픽 집중 (이벤트/챌린지)](04_scenario_write_heavy.md)
- ✅ 바이럴 트래픽 패턴 검증 완료
- ✅ 홈 탭 캐싱 효과 확인

### 9.2 최적화 필요 시

- 🔧 **캐싱 도입**: Spring Cache + Caffeine/Redis
- 🔧 **N+1 쿼리 해결**: `@EntityGraph` 적용
- 🔧 **CPU 크레딧 대응**: t3.unlimited 활성화 또는 m5.large 전환

### 9.3 실패 시

- 🚨 **긴급 캐싱 도입**: Caffeine (인메모리 캐시) 즉시 적용
- 🚨 **DB Read Replica**: 읽기 트래픽 분산
- 🚨 **CDN 도입**: 정적 콘텐츠 오프로딩

---

## 10. 참고 자료

- [00_load_test_prerequisites.md](00_load_test_prerequisites.md) — 테스트 전제 조건
- [01_scenario_baseline.md](01_scenario_baseline.md) — 시나리오 1 (Baseline)
- [02_scenario_hotplace.md](02_scenario_hotplace.md) — 시나리오 2 (Hotplace)
- [Spring Cache Documentation](https://docs.spring.io/spring-framework/docs/current/reference/html/integration.html#cache)
- [Caffeine Cache](https://github.com/ben-manes/caffeine)

---

## 문서 이력

| 버전 | 날짜 | 작성자 | 변경 내역 |
|------|------|--------|----------|
| 1.0 | 2026-06-26 | System | 초기 작성 (프론트엔드 멀티 API 호출 패턴 반영) |
