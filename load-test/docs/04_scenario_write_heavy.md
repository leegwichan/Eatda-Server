# 시나리오 4 — 쓰기 트래픽 집중 (이벤트/챌린지)

## 문서 개요

**시나리오 유형**: Write-Heavy Load Test  
**난이도**: ⭐⭐⭐⭐ (매우 높음)  
**목적**: 이벤트 기간 중 리뷰/이미지 업로드가 집중될 때 서버 성능 검증  
**작성일**: 2026-06-26  
**예상 소요 시간**: 3시간

---

## 1. 시나리오 배경

### 1.1 비즈니스 컨텍스트

```
상황:
  - "이번 주 최고의 맛집 리뷰 공모전" 진행 중
  - 저녁 피크 시간(18:00-21:00)에 리뷰/이미지 업로드 집중
  - 마감 임박 시간(20:30-21:00)에 트래픽 최고조

트래픽 특성:
  - 평상시 저녁 피크 읽기: ~0.5 세션/s
  - 이벤트 쓰기 추가: ~1.5-2 세션/s
  - 총: ~2-2.5 세션/s
  
  - 주요 API:
    * POST /api/stories: 리뷰 등록 (40%)
    * POST /api/image/presigned-url: S3 업로드 URL 발급 (40%)
    * POST /api/cheer: 응원 등록 (20%)
```

### 1.2 시나리오 목적

- 쓰기 작업의 평균 처리 시간 확인 (읽기 대비 3-5배 소요)
- DB 커넥션 풀 고갈 위험 확인 (트랜잭션 장시간 점유)
- S3 Presigned URL 발급 처리량 확인
- 동시 쓰기 작업 시 DB 락 경합 확인

---

## 2. 트래픽 프로필

### 2.1 사용자 행동 패턴

```typescript
// 리뷰 등록 플로우 (40%)
// 1. S3 Presigned URL 발급
POST /api/image/presigned-url
{
  "fileDetails": [
    {"fileName": "food1.jpg", "contentType": "image/jpeg", "fileSize": 2048000},
    {"fileName": "food2.jpg", "contentType": "image/jpeg", "fileSize": 1536000}
  ]
}

// 2. S3 직접 업로드 (서버 부하 없음)
PUT {presignedUrl}
[Binary image data]

// 3. 스토리 등록
POST /api/stories
{
  "kakaoId": "12345678",
  "content": "진짜 맛있어요!",
  "imageUrls": ["https://s3.../food1.jpg", "https://s3.../food2.jpg"]
}

// 응원 등록 플로우 (20%)
// 1. S3 Presigned URL 발급
POST /api/image/presigned-url

// 2. S3 직접 업로드
PUT {presignedUrl}

// 3. 응원 등록
POST /api/cheer
{
  "storeId": 42,
  "content": "꼭 가보세요!",
  "tags": ["분위기 좋아요", "데이트 추천"],
  "imageUrls": ["https://s3.../cheer1.jpg"]
}
```

### 2.2 시나리오 설정

```yaml
Virtual Users (VUs): 50명 동시 접속
Duration: 3시간
Stages:
  - Warm-up (18:00-18:30): 0 → 30 VU (30분)
  - Peak (18:30-20:30): 30 → 50 VU (2시간)
  - Final Rush (20:30-21:00): 50 VU 유지 (30분)

Think Time: 10초 (업로드 준비 시간)

사용자 여정 (1 iteration):
  1. Presigned URL 발급 (1 req) → 1초 대기
  2. S3 업로드 (서버 부하 없음) → 2초 대기
  3. 스토리/응원 등록 (1 req) → 10초 대기
  → 2 req / 13초 = 0.15 req/s per VU

예상 전체 트래픽:
  - 50 VU × 0.15 req/s = 7.5 req/s (서버 API만)
  - 추가 읽기 트래픽: ~20 req/s (일반 사용자)
  - 총: ~27.5 req/s
```

### 2.3 API 엔드포인트 분포

| API | 호출 빈도 | 처리 시간 | 비율 |
|-----|----------|----------|------|
| `POST /api/image/presigned-url` | ~4,100회/3시간 | 50ms | 27% |
| `POST /api/stories` | ~2,400회/3시간 | 300ms | 16% |
| `POST /api/cheer` | ~1,200회/3시간 | 200ms | 8% |
| 읽기 API (홈, 가게 상세 등) | ~21,600회/3시간 | 100ms | 49% |

---

## 3. 환경 설정

### 3.1 서버 리소스

```yaml
CPU: 2 vCPU (t3.medium 시뮬레이션)
Memory: 4 GB
JVM Heap: -Xms2g -Xmx2.5g
Database: MySQL 8.0 (HikariCP pool size: 20)
```

### 3.2 테스트 데이터

```
Members: 1,000명 (인증 토큰 필요)
Stores: 500개
기존 Cheers: 5,000개
기존 Stories: 2,000개

테스트 중 생성 예상:
  - 신규 Stories: ~2,400개
  - 신규 Cheers: ~1,200개
  - 신규 StoryImages: ~4,800개 (각 Story당 2개)
  - 신규 CheerImages: ~1,200개 (각 Cheer당 1개)
```

---

## 4. 성공 기준

### 4.1 성능 목표

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **평균 응답 시간** | < 500ms | < 1000ms |
| **P95 응답 시간** | < 1500ms | < 3000ms |
| **P99 응답 시간** | < 3000ms | < 5000ms |
| **에러율** | < 1% | < 5% |
| **처리량 (쓰기)** | > 7 req/s | > 5 req/s |

### 4.2 리소스 사용률

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **CPU 사용률** | 70-90% | < 95% |
| **메모리 사용률** | < 80% | < 90% |
| **DB 커넥션 풀** | < 80% (16/20) | < 95% (19/20) |
| **JVM Heap** | < 2.3 GB | < 2.4 GB |

### 4.3 안정성 목표

- ✅ **DB 커넥션 풀 고갈 없음**: pending < 5개
- ✅ **트랜잭션 타임아웃 없음**: 모든 쓰기 작업 30초 이내 완료
- ✅ **DB 데드락 없음**: 동시 쓰기 시 락 경합 최소화

---

## 5. 테스트 실행

### 5.1 K6 스크립트

```javascript
// scripts/scenario4_write_heavy.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const writeLatency = new Trend('write_latency');

export const options = {
  stages: [
    { duration: '30m', target: 30 },  // Warm-up
    { duration: '2h', target: 50 },   // Peak
    { duration: '30m', target: 50 },  // Final Rush
  ],
  thresholds: {
    'http_req_duration': ['p(95)<3000', 'p(99)<5000'],
    'http_req_failed': ['rate<0.05'],
    'write_latency': ['p(95)<2000'],
  },
};

const BASE_URL = 'http://localhost:8080';
const AUTH_TOKEN = 'Bearer test-token';  // TODO: 실제 토큰 생성 로직

export default function() {
  const isWriter = Math.random() < 0.7;  // 70%는 쓰기 작업
  
  if (isWriter) {
    const isStory = Math.random() < 0.67;  // 40% Story, 27% Cheer
    
    if (isStory) {
      // Story 등록 플로우
      // 1. Presigned URL 발급
      const presignedReq = http.post(
        `${BASE_URL}/api/image/presigned-url`,
        JSON.stringify({
          fileDetails: [
            { fileName: `story_${Date.now()}_1.jpg`, contentType: 'image/jpeg', fileSize: 2048000 },
            { fileName: `story_${Date.now()}_2.jpg`, contentType: 'image/jpeg', fileSize: 1536000 },
          ]
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Authorization': AUTH_TOKEN,
          },
        }
      );
      
      check(presignedReq, {
        'presigned URL status is 200': (r) => r.status === 200,
      });
      
      sleep(1);
      
      // 2. S3 업로드 (mock - 서버 부하 없음)
      sleep(2);
      
      // 3. Story 등록
      const storyStart = Date.now();
      const storeKakaoId = String(Math.floor(Math.random() * 500) + 1);
      const storyRes = http.post(
        `${BASE_URL}/api/stories`,
        JSON.stringify({
          kakaoId: storeKakaoId,
          content: `테스트 리뷰 ${Date.now()}`,
          imageUrls: [`https://s3.mock.com/story1.jpg`, `https://s3.mock.com/story2.jpg`],
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Authorization': AUTH_TOKEN,
          },
        }
      );
      
      writeLatency.add(Date.now() - storyStart);
      
      const success = check(storyRes, {
        'story post status is 200': (r) => r.status === 200,
        'story post response time < 3000ms': (r) => r.timings.duration < 3000,
      });
      errorRate.add(!success);
      
      sleep(10);
      
    } else {
      // Cheer 등록 플로우
      // 1. Presigned URL 발급
      const presignedReq = http.post(
        `${BASE_URL}/api/image/presigned-url`,
        JSON.stringify({
          fileDetails: [
            { fileName: `cheer_${Date.now()}.jpg`, contentType: 'image/jpeg', fileSize: 1024000 },
          ]
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Authorization': AUTH_TOKEN,
          },
        }
      );
      
      check(presignedReq, {
        'presigned URL status is 200': (r) => r.status === 200,
      });
      
      sleep(1);
      sleep(2);  // S3 upload
      
      // 2. Cheer 등록
      const cheerStart = Date.now();
      const storeId = Math.floor(Math.random() * 500) + 1;
      const cheerRes = http.post(
        `${BASE_URL}/api/cheer`,
        JSON.stringify({
          storeId: storeId,
          content: `테스트 응원 ${Date.now()}`,
          tags: ['분위기 좋아요', '데이트 추천'],
          imageUrls: [`https://s3.mock.com/cheer1.jpg`],
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Authorization': AUTH_TOKEN,
          },
        }
      );
      
      writeLatency.add(Date.now() - cheerStart);
      
      const success = check(cheerRes, {
        'cheer post status is 200': (r) => r.status === 200,
        'cheer post response time < 2000ms': (r) => r.timings.duration < 2000,
      });
      errorRate.add(!success);
      
      sleep(10);
    }
  } else {
    // 30%: 읽기 작업 (홈 탭 조회)
    const homeRequests = [
      { method: 'GET', url: `${BASE_URL}/api/stories?size=20` },
      { method: 'GET', url: `${BASE_URL}/api/shops?size=20` },
    ];
    
    const responses = http.batch(homeRequests);
    responses.forEach(res => {
      check(res, {
        'read status is 200': (r) => r.status === 200,
      });
    });
    
    sleep(5);
  }
}
```

### 5.2 실행

```bash
# 시나리오 4 실행 (주의: 3시간 소요)
k6 run --out json=results/scenario4.json \
       scripts/scenario4_write_heavy.js
```

### 5.3 모니터링

```bash
# DB 커넥션 풀 실시간 모니터링
watch -n 2 "curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active | jq; \
            curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.pending | jq"

# 트랜잭션 통계
watch -n 10 "docker exec eatda-mysql mysql -u root -proot -e 'SHOW ENGINE INNODB STATUS\\G' | grep -A 20 'TRANSACTIONS'"

# Slow query 모니터링
docker logs -f eatda-app | grep "exceeded"
```

---

## 6. 검증 사항

### 6.1 DB 커넥션 풀 고갈

#### 체크리스트

- [ ] **쓰기 작업 처리 시간**
  - Story 등록: 평균 300ms (DB INSERT + 이미지 메타데이터)
  - Cheer 등록: 평균 200ms
  - 읽기 작업: 평균 100ms

- [ ] **필요 커넥션 수 계산**
  - 쓰기: 7.5 req/s × 0.3s = 2.25개
  - 읽기: 20 req/s × 0.1s = 2개
  - 총: ~5개 (20개 풀 중 25%)

- [ ] **피크 시간 (20:30-21:00) 커넥션 사용률**
  - 최대 50 VU × 0.3s / 13s = 1.15개 (쓰기)
  - 추가 읽기: ~2개
  - 총: ~4개 (충분)

#### 확인 방법

```bash
# 커넥션 획득 대기 시간 확인
curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.acquire | jq '.measurements[] | select(.statistic=="MAX")'

# 기대값: p95 < 100ms (여유 있음)
# 문제 발생 시: p95 > 1000ms (대기 발생)
```

### 6.2 트랜잭션 장시간 점유

#### 체크리스트

- [ ] **@Transactional 범위 확인**
  - S3 이동 로직이 트랜잭션 내부인가?
  - 외부 API 호출이 트랜잭션 내부인가?
  - 예상: 트랜잭션은 DB 작업만 포함해야 함 (< 100ms)

- [ ] **실제 트랜잭션 점유 시간**
  - Story/Cheer INSERT: ~50ms
  - 이미지 메타데이터 INSERT: ~20ms
  - 총: ~70ms

#### 확인 방법

```bash
# 트랜잭션 지속 시간 확인
docker exec eatda-mysql mysql -u root -proot -e "
  SELECT * FROM information_schema.INNODB_TRX ORDER BY trx_started DESC LIMIT 10;
"

# 기대값: trx_started - 현재 시간 < 1초
# 문제 발생 시: > 5초 (외부 API 호출 포함 의심)
```

### 6.3 DB 락 경합

#### 체크리스트

- [ ] **동일 Store 업데이트 경합**
  - Story/Cheer 등록 시 Store 엔티티 업데이트 (cheer_count++)
  - 동일 storeId에 동시 쓰기 발생 시 락 대기
  - 예상: 500개 Store에 분산되므로 경합 낮음

- [ ] **데드락 발생 여부**
  - Story ↔ Store 순환 참조 시 데드락 가능성
  - InnoDB 데드락 감지 및 롤백 자동 처리

#### 확인 방법

```bash
# 데드락 로그 확인
docker exec eatda-mysql mysql -u root -proot -e "SHOW ENGINE INNODB STATUS\\G" | grep -A 30 "LATEST DETECTED DEADLOCK"

# 락 대기 통계
docker exec eatda-mysql mysql -u root -proot -e "SHOW STATUS LIKE 'Innodb_row_lock%';"
```

---

## 7. 예상 병목 및 대응

### 7.1 예상 병목

| 병목 | 증상 | 원인 | 대응 |
|------|------|------|------|
| **DB 커넥션 부족** | Pending > 5, 타임아웃 증가 | 쓰기 작업 처리 시간 과다 | 커넥션 풀 30개로 증설 |
| **트랜잭션 장시간 점유** | 커넥션 획득 대기 > 1s | S3 로직이 @Transactional 내부 | S3 로직 트랜잭션 외부로 이동 |
| **DB 락 경합** | 응답 시간 급증, 데드락 발생 | 동일 Store 동시 업데이트 | 낙관적 락 또는 비동기 업데이트 |
| **Presigned URL 발급 지연** | presigned API > 500ms | AWS SDK 동기 호출 | 비동기 또는 배치 처리 |

### 7.2 대응 방안

#### 트랜잭션 범위 최소화

```java
// Before: S3 로직이 트랜잭션 내부
@Transactional
public StoryRegisterResponse registerStory(StoryRegisterRequest request) {
    // S3 Presigned URL 발급 (외부 API 호출 - 느림!)
    List<String> imageUrls = fileClient.getPresignedUrls(request.getImageKeys());
    
    Story story = Story.create(...);
    storyRepository.save(story);  // DB INSERT
    
    return StoryRegisterResponse.from(story);
}

// After: S3 로직을 트랜잭션 외부로 분리
public StoryRegisterResponse registerStory(StoryRegisterRequest request) {
    // 트랜잭션 밖에서 S3 URL 발급
    List<String> imageUrls = fileClient.getPresignedUrls(request.getImageKeys());
    
    return registerStoryWithUrls(request, imageUrls);
}

@Transactional
private StoryRegisterResponse registerStoryWithUrls(StoryRegisterRequest request, List<String> imageUrls) {
    Story story = Story.create(...);
    storyRepository.save(story);  // DB INSERT만 트랜잭션 안에서
    return StoryRegisterResponse.from(story);
}
```

#### DB 락 경합 해결 (낙관적 락)

```java
// Store.java
@Entity
public class Store {
    @Id
    private Long id;
    
    @Version  // 낙관적 락
    private Long version;
    
    private int cheerCount;
    
    public void incrementCheerCount() {
        this.cheerCount++;
    }
}

// CheerService.java
@Transactional
public void registerCheer(CheerRegisterRequest request) {
    try {
        Cheer cheer = Cheer.create(...);
        cheerRepository.save(cheer);
        
        Store store = storeRepository.findById(request.getStoreId())
            .orElseThrow();
        store.incrementCheerCount();
    } catch (OptimisticLockException e) {
        // 재시도 로직
        throw new BusinessException(BusinessErrorCode.STORE_UPDATE_CONFLICT);
    }
}
```

---

## 8. 결과 분석

### 8.1 K6 출력 예시 (성공 케이스)

```
     ✓ story post status is 200
     ✓ story post response time < 3000ms

     checks.........................: 94.2% ✓ 5,100     ✗ 310
     data_received..................: 68 MB  6.3 kB/s
     data_sent......................: 45 MB  4.2 kB/s
     http_req_duration..............: avg=720ms   min=35ms   med=580ms  max=4.2s   p(95)=1.8s
     http_req_failed................: 2.1%   ✓ 112      ✗ 5,300
     http_reqs......................: 54,000 5 req/s
     write_latency..................: avg=450ms   min=80ms   med=380ms  max=3.5s   p(95)=1.2s
     iteration_duration.............: avg=13.5s   min=13s    med=13.2s  max=18s    p(95)=15s
     iterations.....................: 4,050  0.375/s
     vus............................: 0-50   min=0       max=50
```

### 8.2 판정 기준

#### ✅ 성공 (다음 조건 모두 충족)

- [ ] 평균 응답 시간 < 1000ms
- [ ] P95 응답 시간 < 3000ms
- [ ] 에러율 < 5%
- [ ] DB 커넥션 pending < 5개
- [ ] 데드락 발생 0건

#### ⚠️ 주의 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 1000-2000ms
- [ ] P95 응답 시간 3000-5000ms
- [ ] 에러율 5-10%
- [ ] DB 커넥션 pending 5-10개

#### 🚨 실패 (다음 중 하나라도 해당)

- [ ] 평균 응답 시간 > 2000ms
- [ ] P95 응답 시간 > 5000ms
- [ ] 에러율 > 10%
- [ ] DB 타임아웃 다수 발생
- [ ] 데드락 빈발 (> 10건)

---

## 9. 다음 단계

### 9.1 성공 시

- ✅ 시나리오 5 진행: [OAuth 장애 (외부 의존성 장애 전파)](05_scenario_oauth_failure.md)
- ✅ 쓰기 트래픽 집중 패턴 검증 완료
- ✅ 트랜잭션 범위 최적화 확인

### 9.2 최적화 필요 시

- 🔧 **DB 커넥션 풀 증설**: 20 → 30개
- 🔧 **트랜잭션 범위 최소화**: S3 로직 분리
- 🔧 **낙관적 락 도입**: Store 업데이트 경합 해결

### 9.3 실패 시

- 🚨 **긴급 커넥션 풀 증설**: 30-40개
- 🚨 **비동기 처리 도입**: 쓰기 작업 큐잉
- 🚨 **Write-Through Cache**: DB 쓰기 부하 감소

---

## 10. 참고 자료

- [00_load_test_prerequisites.md](00_load_test_prerequisites.md) — 테스트 전제 조건
- [HikariCP About Pool Sizing](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing)
- [JPA Optimistic Locking](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#locking)
- [Spring Transaction Management](https://docs.spring.io/spring-framework/docs/current/reference/html/data-access.html#transaction)

---

## 문서 이력

| 버전 | 날짜 | 작성자 | 변경 내역 |
|------|------|--------|----------|
| 1.0 | 2026-06-26 | System | 초기 작성 (프론트엔드 쓰기 플로우 반영) |
