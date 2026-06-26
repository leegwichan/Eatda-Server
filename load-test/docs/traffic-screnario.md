# 트래픽 진단: 뽈레(Polle) 기반 현실적 시나리오

> **기준 서비스**: 뽈레 (니치 버티컬 미식가 커뮤니티)
> **근거**: 누적 가입자 12만 명, MAU 2~4만 (DAU/MAU 비율 높은 헤비 유저 중심)

---

## 현재 서버 상태 (베이스라인)

| 항목 | 현재 설정 | 비고 |
|------|-----------|------|
| DB 커넥션 풀 | HikariCP 기본값 (10개) | 명시적 설정 없음 |
| 캐싱 | 없음 | Redis/로컬 캐시 미적용 |
| Batch Fetch Size | 30 | N+1 부분 대응 |
| open-in-view | false | 트랜잭션 범위 명확 |
| 외부 API | 카카오맵 API + 카카오 OAuth | 가게 검색 및 로그인 시 호출 |
| 이미지 | S3 Presigned URL | 업로드는 클라이언트 직접, 등록 시 temp→permanent 이동 |

---

## 기본 수치 역산

### 사용자 기반 추정

```
누적 가입자: 120,000
MAU: 30,000 (2~4만의 중간값)
DAU/MAU: 40% (헤비 유저 중심 특성)
  → DAU: 12,000명
```

### 일일 API 호출 패턴

```
활성 시간대: 8시간 (점심 12~1시 + 저녁 6~11시)
  - 점심: 20% 트래픽 (12시~1시 1시간)
  - 저녁: 80% 트래픽 (6시~10시 4시간)

사용자당 일일 행동:
  - 세션: 2회 (평균 20분/세션)
  - 세션당 API 호출: 5회
    (홈 조회 1 + 리뷰 목록 1 + 상세 진입 1 + 필터링 1 + 더보기/무한스크롤 1)

일일 총 요청: 12,000 × 2 × 5 = 120,000 req/day
```

### 평상시 req/s

```
일일 활성 시간: 8시간 = 28,800초
평상시 평균: 120,000 / 28,800 = 4.2 req/s

시간대별 분산:
  - 점심 (12~1시): 24,000 req / 3,600s = 6.7 req/s
  - 저녁 (6~10시): 96,000 req / (4 × 3,600s) = 6.7 req/s
  - 평소: 2~3 req/s
```

---

## 시나리오 1 — 평상시 운영 (현재 상태)

### 트래픽 프로필

```
피크: 저녁 6~10시, ~6~7 req/s
오프피크: 오전/자정, ~1~2 req/s
평균: ~4 req/s
```

### 예상 병목 없음

- **HikariCP 10개 커넥션**: 충분 (req/s당 DB 체류 시간 ~50ms 기준, 최대 동시 요청 7개 가능)
- **캐싱 필요도**: 낮음 (읽기 요청이 많지만 개인화 정보 비중 높음)
- **외부 API 호출**: 최소 (가게 검색 시에만, 일일 ~100회)

### 이 규모에서의 개선점

1. **슬로우 쿼리 모니터링 시작**: MySQL slow query log (`long_query_time=1`)
    - 리뷰 정렬/필터링 쿼리 식별
2. **기본 메트릭 수집**: HikariCP Active Connections, SQL 실행 시간
3. **문제 발견 전 예방**: `StorePersistence` N+1 쿼리 미리 확인

---

## 시나리오 2 — 특정 맛집 집중 ("핫플레이스" 효과)

### 배경

뽈레의 특성: "성수동, 홍대 등 주요 핫플레이스에서는 대형 플랫폼 못지않은 리뷰 데이터 밀도"

특정 가게(예: 성수동 신상 치킨집)가 미식가들의 화제가 되면,
해당 가게 상세 페이지 트래픽이 일시적으로 집중.

### 트래픽 패턴

```
평상시: GET /api/shops/{id} = 20 req/day
핫플레이스 집중: 인플루언서 공유 후 2-3분 내 500 req 집중

실제 트래픽 급증:
  - 500 req / 180s = 2.8 req/s (단일 store_id에 집중)
  
프론트엔드가 상세 진입 시 동시에 4개 API 호출:
  1. GET /api/shops/{id}
  2. GET /api/shops/{id}/cheers?size=10
  3. GET /api/shops/{id}/images
  4. GET /api/shops/{id}/tags

동시 요청: 2.8 req/s × 4 = 11.2 req/s
DB 커넥션 사용: 11.2 × 0.05s = 0.56개 (기본값 10개로 충분)

⚠️ 그러나 문제는 "동시성" 아니라 "N+1 쿼리 폭발":
  - Store 상세 조회 시 각 Cheer를 lazy 로드
  - batch_fetch_size=30으로 설정되어 있으나, 확인 필요
  - 2-3분간 지속적인 DB 히트 → CPU 스파이크 가능
```

### 실제 문제점

1. **쿼리 폭발 위험**: 500 req/hour × 4 API × (1 Store + N Cheer 지연로딩)
   ```sql
   SELECT * FROM store WHERE id = 123;        -- 1회
   SELECT * FROM cheer WHERE store_id = 123;  -- 1회 (batch 처리됨)
   SELECT * FROM cheer_image WHERE cheer_id IN (...);  -- N/30회
   ```

2. **S3 이미지 URL 응답 지연**: 이미지 개수가 많을 경우

### 최적화 방향

- [ ] `GET /api/shops/{id}` 응답을 로컬 캐시 (Caffeine, TTL 5분)
  → 500 req/hour → 초기 1회만 DB 히트, 이후 캐시
- [ ] EntityGraph로 Store + Cheer + CheerImage를 한 번에 로드 확인
- [ ] 프론트엔드: 4개 API 대신 BFF 패턴으로 `/api/shops/{id}/detail` 단일화 검토

---

## 시나리오 3 — SNS 공유 (미식가 커뮤니티 바이럴)

### 배경

뽈레 특정 리뷰가 여식 SNS (쇼핑, 블로그, 카톡방) 에서 공유되고,
"이 리뷰 읽고 싶어!" 클릭이 몰림.

### 트래픽 패턴

```
평상시: ~4 req/s
바이럴 중: ~20~40 req/s (30분~1시간)

주요 경로:
  - 홈 (/) 진입 → 리뷰 목록 조회 (GET /api/stories)
  - 특정 리뷰 상세 (GET /api/stories/{id})
  - 해당 가게 상세 (GET /api/shops/{id})
```

### 병목 분석

```
바이럴 시 요청 분포:
  GET /api/stories?size=20       : 40% (홈 진입)
  GET /api/stories/{id}          : 30% (리뷰 상세 클릭)
  GET /api/shops/{id}            : 20% (가게 상세)
  GET /api/stories/{id}/comments : 10% (댓글 조회)

40 req/s × 40% = 16 req/s on GET /api/stories?size=20
```

**문제점:**

1. **캐싱 부재**: `GET /api/stories?size=20`는 정적 콘텐츠이지만, 매번 DB 히트
    - DB CPU 스파이크 (단순 SELECT * 지만 반복)
    - 24개 스토리 × 각 스토리의 이미지 + 작성자 정보 lazy 로드

2. **커넥션 풀은 아직 여유**:
   ```
   동시 요청: 16 req/s (각각 50ms 체류 가정)
     → 동시 활성 커넥션: 16 × 0.05 = 0.8개 (기본 10개로 충분)
   
   ※ GET /api/stories?size=20는 순수 DB 조회이므로,
      카카오맵 API 호출이 없어 체류 시간이 짧음.
   ```
   
3. **N+1 쿼리 반복**: 
   - 24개 스토리 각각의 이미지, 작성자 정보 lazy 로드
   - batch_fetch_size=30 설정되어 있으나, 16 req/s로 반복 조회 시 DB CPU 부하

### 최적화 방향

- [ ] **우선순위 1**: `GET /api/stories?size=20` Caffeine 캐시 (TTL 설정은 실측 후 결정)
    - 효과: 16 req/s → 1 req/s (캐시 미스 시에만 DB 히트)
    - **탐구 포인트**: TTL은 얼마가 적절한가?
      - 신규 리뷰 등록 빈도 측정 필요 (1분당 N개?)
      - 사용자가 "최신성"을 얼마나 기대하는가?
      - 제안: 초기 30초로 시작, 캐시 히트율/불만 피드백 보고 조정
- [ ] **우선순위 2**: `GET /api/shops/{id}` 캐시 (TTL 설정은 실측 후 결정)
    - **탐구 포인트**: 가게 정보는 얼마나 자주 변경되는가?
      - 운영시간/전화번호 변경 빈도
      - Cheer 수 실시간 반영 필요성
      - 제안: 초기 5분으로 시작, 모니터링 후 조정
- [ ] **우선순위 3**: HikariCP `maximum-pool-size` 명시 (20~30)
    - 외부 API 타임아웃 시 버퍼 제공 (시나리오 4 대비)

---

## 시나리오 4 — 특정 시간 쓰기 집중 (이벤트/챌린지)

### 배경

예: "이번 주 최고의 맛집 리뷰 공모전" 기간 중
저녁 6~9시에 리뷰/이미지 업로드 집중.

### 트래픽 패턴

```
평상시 쓰기: 2 req/s
이벤트 중 쓰기: 30~50 req/s (3시간 지속)

주요 API:
  POST /api/stories: 리뷰 등록
  POST /api/image/presigned-url: S3 업로드 URL 발급
  PUT {presignedUrl}: S3 직접 업로드 (서버 부하 없음)
  POST /api/cheer: 응원 등록
```

### 병목 분석

```
50 req/s of POST /api/stories (각각 트랜잭션):
  1. 이미지 temp → permanent S3 이동
  2. Story 엔티티 저장
  3. 트랜잭션 커밋
  
트랜잭션 체류 시간: 500ms (S3 이동 포함)
동시 활성 커넥션: 50 × 0.5 = 25개 (기본 10개로 부족!)
```

**문제점:**

1. **DB 커넥션 고갈**: 기본값 10개로는 부족
    - 11번째 요청부터 큐에서 대기 (queue timeout 30초)

2. **S3 이동 로직이 트랜잭션 내부**:
   ```
   @Transactional
   public void registerStory(StoryRequest req) {
       // ...
       s3Client.moveObject(...); // 외부 I/O, 트랜잭션 내부!
       storyRepository.save(...);
   }
   ```
    - S3 지연 → DB 커넥션 장시간 점유

3. **카카오 OAuth 의존성**: 이벤트 유입 시 신규 유저 로그인 집중
   ```
   POST /api/auth/login → 카카오 OAuth 서버 외부 호출 (~500ms)
   50 req/s 중 30%가 신규 유저 로그인: 15 req/s × 0.5초 = 7.5개 커넥션 추가 점유
   카카오 API 지연 시 스레드 블로킹 → 전체 처리량 저하
   ```

4. **동시 쓰기 락 경합**: 동일 가게에 대한 응원이 많을 경우
    - Store 엔티티 업데이트 시 낙관적/비관적 락 필요

### 최적화 방향

- [ ] **우선순위 1**: HikariCP `maximum-pool-size` = 30 (또는 계산값)
  ```yaml
  spring:
    datasource:
      hikari:
        maximum-pool-size: 30
        minimum-idle: 10
        connection-timeout: 30000
        idle-timeout: 600000
  ```

- [ ] **우선순위 2**: S3 이동 로직 트랜잭션 분리
  ```java
  @Transactional
  public Story registerStory(StoryRequest req) {
      Story story = Story.from(req);
      return storyRepository.save(story);  // DB 저장만
  }
  
  @Async
  public void moveImagesToPermanent(Story story) {
      // S3 이동은 비동기 (트랜잭션 외부)
      for (StoryImage img : story.getImages()) {
          s3Client.moveObject(img.getTempKey(), img.getPermanentKey());
      }
  }
  ```

- [ ] **우선순위 3**: 카카오 API 호출에 타임아웃 + 서킷브레이커 적용
    - Resilience4j `@CircuitBreaker` 적용
    - 카카오 API 2초 이상 지연 시 fallback 처리

- [ ] **우선순위 4**: 응원 등록 시 낙관적 락 추가
  ```java
  @Entity
  public class Store {
      @Version
      private Long version;  // Optimistic Lock
      
      private Integer cheerCount;
  }
  ```

---

## 시나리오 5 — OAuth 장애 (외부 의존성 장애 전파)

### 배경

카카오 OAuth 서버 장애 시, 모든 로그인 요청이 타임아웃되어 전체 서비스에 영향.

### 트래픽 패턴

```
평상시 로그인: 2 req/s
이벤트/바이럴 시: 10~15 req/s (신규 유저 유입)

카카오 OAuth 서버 응답:
  - 정상: 200~500ms
  - 장애: 타임아웃 5초 (설정된 경우) 또는 무한 대기
```

### 병목 분석

```
OAuth 장애 시 타임아웃 5초 가정:
  10 req/s × 5s = 50개 스레드 블로킹
  
Tomcat 기본 스레드 풀: 200개
  → OAuth 요청이 스레드 풀의 25% 점유
  → 다른 정상 API 요청도 지연 발생 (스레드 대기)
```

**문제점:**

1. **장애 전파**: 외부 API 장애가 전체 서비스 가용성에 영향
2. **타임아웃 미설정 시**: 무한 대기로 스레드 풀 고갈 → 전체 서비스 마비
3. **재시도 로직 없음**: 일시적 네트워크 장애에도 즉시 실패

### 최적화 방향

- [ ] **우선순위 1**: Circuit Breaker 적용 (Resilience4j)
  ```yaml
  resilience4j:
    circuitbreaker:
      instances:
        kakaoOauth:
          failureRateThreshold: 50         # 50% 실패 시 Open
          waitDurationInOpenState: 30000   # 30초 후 Half-Open
          slidingWindowSize: 10            # 최근 10개 요청 기준
  ```
  
- [ ] **우선순위 2**: Timeout 명시 (RestTemplate/WebClient)
  ```java
  RestTemplate restTemplate = new RestTemplate();
  HttpComponentsClientHttpRequestFactory factory = 
      new HttpComponentsClientHttpRequestFactory();
  factory.setConnectTimeout(2000);  // 연결 타임아웃 2초
  factory.setReadTimeout(3000);     // 읽기 타임아웃 3초
  restTemplate.setRequestFactory(factory);
  ```

- [ ] **우선순위 3**: Fallback 응답
  - Circuit Open 시: "카카오 로그인이 일시적으로 불가합니다" 응답
  - 재시도 안내 또는 대체 로그인 수단 제공

---

## 시나리오 6 — DB 슬로우 쿼리 발생

### 배경

특정 쿼리(예: 복잡한 필터링, 정렬)가 예상보다 오래 걸려 커넥션 풀 고갈.

### 트래픽 패턴

```
평상시: 모든 쿼리 50ms 이내
슬로우 쿼리 발생: 특정 API의 쿼리가 5초 소요

예시: GET /api/stories?district=성수동&sort=latest&size=50
  - 인덱스 미적용 시: Full Table Scan → 5초
```

### 병목 분석

```
슬로우 쿼리 발생 시:
  10 req/s × 5s = 50개 커넥션 필요
  
HikariCP 기본값: 10개
  → 11번째 요청부터 대기 (connection-timeout: 30초)
  → 30초 후 타임아웃 에러 발생
  → 사용자 경험 악화 (HTTP 500 또는 504)
```

**문제점:**

1. **커넥션 풀 고갈**: 슬로우 쿼리가 커넥션을 장시간 점유
2. **연쇄 장애**: 다른 정상 API도 커넥션을 얻지 못해 실패
3. **감지 지연**: 슬로우 쿼리 로그가 없으면 원인 파악 어려움

### 최적화 방향

- [ ] **우선순위 1**: MySQL slow query log 활성화
  ```sql
  SET GLOBAL slow_query_log = 'ON';
  SET GLOBAL long_query_time = 1;  -- 1초 이상 쿼리 기록
  SET GLOBAL log_queries_not_using_indexes = 'ON';
  ```

- [ ] **우선순위 2**: Query timeout 설정
  ```yaml
  spring:
    jpa:
      properties:
        javax.persistence.query.timeout: 3000  # 3초
        hibernate.query.timeout: 3000
  ```

- [ ] **우선순위 3**: 인덱스 최적화
  - 자주 사용되는 필터 컬럼에 인덱스 추가
  - 복합 인덱스 고려 (district + createdAt)

- [ ] **우선순위 4**: 슬로우 쿼리 모니터링
  - Spring Boot Actuator + Micrometer로 쿼리 실행 시간 수집
  - 임계값 초과 시 알림 (Slack, 이메일)

---

## 공통 최적화 로드맵

### Phase 1 — 즉시 (설정 변경만, 코드 무수정)

| 항목 | 설정 | 효과 | 구현 시간 |
|------|------|------|----------|
| HikariCP 풀 크기 | `maximum-pool-size: 30` | 동시 요청 최대 30개 처리 | 5분 |
| MySQL slow query log | `long_query_time=1` | 1초 이상 쿼리 식별 | 5분 |
| Hibernate batch fetch | 이미 `batch_fetch_size: 30` 설정됨 | N+1 부분 대응 | 0분 |
| JVM Heap 명시 | `-Xms256m -Xmx512m` | GC pause 감소 | 5분 |

### Phase 2 — 단기 (1주)

| 항목 | 기술 | 대상 시나리오 | 기대 효과 |
|------|------|---------------|----------|
| 읽기 API 캐싱 | Caffeine (로컬) | 시나리오 2, 3 | 캐시 히트 시 DB 요청 90% 감소 |
| S3 분리 | @Async | 시나리오 4 | DB 커넥션 체류 시간 80% 감소 |
| 슬로우 쿼리 분석 | - | 모든 시나리오 | 병목 쿼리 식별 |

### Phase 3 — 중기 (1개월)

| 항목 | 기술 | 예상 비용 |
|------|------|----------|
| Redis 도입 | 분산 캐시 | ~$10/월 (AWS ElastiCache 기본) |
| CDN | CloudFront | S3 이미지 캐싱, 이미지 직접 접근 비용 절감 |
| 카카오 API 서킷브레이커 | Resilience4j | 0 (라이브러리만), OAuth + 맵 API 공통 적용 |

---

## 뽈레 기반 최종 진단

### 현재 상태 평가

| 구분 | 평가 | 이유 |
|------|------|------|
| 평상시 운영 | ✅ 문제없음 | 4 req/s는 서버 여유 충분 |
| 핫플레이스 집중 | ⚠️ 잠재 위험 | N+1 미확인, 캐싱 미적용 |
| SNS 바이럴 | ⚠️ 주의 | 캐싱 전무, 20 req/s 시 DB 부하 |
| 쓰기 이벤트 | ❌ 개선 필요 | 커넥션 풀 부족, S3 로직 분리 필수 |

### 우선순위 수정 (뽈레 기준)

**즉시 적용** (영향도 높음):
1. HikariCP `maximum-pool-size: 30` 설정
2. MySQL slow query log 활성화
3. `StorePersistence` N+1 쿼리 실측

**1주일 내**:
1. `GET /api/stories?size=N` 캐싱 (Caffeine, TTL 30초)
2. `GET /api/shops/{id}` 캐싱 (TTL 5분)
3. S3 이동 로직 트랜잭션 분리

**1개월**:
1. Redis 도입 (분산 캐시, 다중 서버 준비)
2. 응원 엔티티 낙관적 락 추가

---

## 이력서 서술 포인트

> "뽈레(12만 누적, MAU 3만)를 벤치마크해 니치 버티컬 서비스의 트래픽을 분석하고, 평상시 4 req/s 규모에서 특정 이벤트 시 40 req/s로 급증할 때를 대비해 병목을 단계별로 최적화하는 전략을 수립했다. 단순 스케일아웃이 아닌, 단일 서버 내에서의 레이어별 최적화(커넥션 풀 → 캐싱 → 비동기)를 통해 10배 트래픽 증가를 감당할 수 있는 구조를 설계했다."
