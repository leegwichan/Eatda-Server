# 시나리오 5 — OAuth 장애 (외부 의존성 장애 전파)

## 문서 개요

**시나리오 유형**: Failure Recovery Test (Chaos Engineering)  
**난이도**: ⭐⭐⭐⭐ (매우 높음)  
**목적**: 카카오 OAuth 서버 장애 시 전체 서비스 영향 확인 및 격리 검증  
**작성일**: 2026-06-26  
**예상 소요 시간**: 30분 (장애 시뮬레이션 10분 포함)

---

## 1. 시나리오 배경

### 1.1 비즈니스 컨텍스트

```
상황:
  - 점심시간(12:00-12:30) 피크 트래픽 중
  - 카카오 OAuth 서버 장애 발생 (타임아웃/5xx 에러)
  - 모든 로그인 요청 실패

트래픽 특성:
  - 점심 피크 전체: 0.42-0.7 세션/s
  - 그 중 로그인 요청: 20-30% (신규 유저 + 재로그인)
  - OAuth 의존 API: 0.08-0.2 req/s
```

### 1.2 시나리오 목적

- 외부 API 장애가 전체 서비스에 전파되지 않는지 확인
- 스레드 풀 고갈 방지 (타임아웃 설정 확인)
- Circuit Breaker 작동 여부 확인
- 우아한 실패 (Graceful Degradation) 검증

---

## 2. 트래픽 프로필

### 2.1 정상 상태 (0-10분)

```yaml
Virtual Users (VUs): 40명 동시 접속
Think Time: 5초

사용자 여정:
  - 80%: 일반 읽기 작업 (홈, 가게 상세)
  - 20%: 로그인 시도 (OAuth)

OAuth 호출:
  - POST /api/auth/login (카카오 인가 코드 → 액세스 토큰)
  - 정상 응답 시간: 200-500ms
```

### 2.2 장애 상태 (10-20분)

```yaml
OAuth 장애 시뮬레이션:
  - WireMock/LocalStack에서 OAuth 엔드포인트 타임아웃 설정
  - 응답 시간: 5초 후 타임아웃
  - 또는 즉시 500 Internal Server Error 응답

예상 영향:
  - 로그인 요청: 20% × 40 VU = 8 VU
  - 타임아웃 대기: 8 VU × 5s = 40 스레드 점유
  - Tomcat 기본 스레드 풀: 200개 (20% 점유)
```

### 2.3 복구 상태 (20-30분)

```yaml
OAuth 복구:
  - WireMock/LocalStack 정상 응답 복구
  - Circuit Breaker Open → Half-Open → Closed 전환 확인
  - 서비스 정상화 시간 측정
```

---

## 3. 환경 설정

### 3.1 서버 리소스

```yaml
CPU: 2 vCPU (t3.medium 시뮬레이션)
Memory: 4 GB
JVM Heap: -Xms2g -Xmx2.5g
Database: MySQL 8.0 (HikariCP pool size: 20)
Tomcat Thread Pool: 200 (기본값)
```

### 3.2 외부 의존성 Mock 설정

```yaml
# WireMock OAuth 엔드포인트
POST /oauth/token
정상 응답 (0-10분, 20-30분):
  status: 200
  body: { "access_token": "mock-token", "expires_in": 3600 }
  delay: 200ms

장애 응답 (10-20분):
  status: 500
  delay: 5000ms (타임아웃)
```

---

## 4. 성공 기준

### 4.1 장애 격리 목표

| 지표 | 목표 | 허용 한계 |
|------|------|----------|
| **OAuth 에러율** | 100% (장애 시) | - |
| **일반 API 에러율** | < 1% | < 5% |
| **일반 API 응답 시간** | < 500ms | < 1000ms |
| **스레드 풀 사용률** | < 50% | < 80% |

### 4.2 복구 목표

| 지표 | 목표 |
|------|------|
| **Circuit Breaker Open 시간** | < 10초 (장애 감지) |
| **서비스 정상화 시간** | < 30초 (OAuth 복구 후) |
| **누적 에러율** | < 10% (전체 30분 기준) |

---

## 5. 테스트 실행

### 5.1 WireMock 설정

```bash
# docker-compose.load-test.yml
services:
  wiremock:
    image: wiremock/wiremock:latest
    ports:
      - "8081:8080"
    volumes:
      - ./wiremock/mappings:/home/wiremock/mappings
    command: ["--global-response-templating"]
```

```json
// wiremock/mappings/oauth-normal.json
{
  "request": {
    "method": "POST",
    "url": "/oauth/token"
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "access_token": "mock-token-{{randomValue type='UUID'}}",
      "token_type": "bearer",
      "expires_in": 3600
    },
    "fixedDelayMilliseconds": 200
  },
  "priority": 10
}

// wiremock/mappings/oauth-failure.json (수동 전환)
{
  "request": {
    "method": "POST",
    "url": "/oauth/token"
  },
  "response": {
    "status": 500,
    "body": "Internal Server Error",
    "fixedDelayMilliseconds": 5000
  },
  "priority": 1
}
```

### 5.2 K6 스크립트

```javascript
// scripts/scenario5_oauth_failure.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

const errorRate = new Rate('errors');
const oauthErrorRate = new Rate('oauth_errors');
const generalAPIErrorRate = new Rate('general_api_errors');
const oauthLatency = new Trend('oauth_latency');

export const options = {
  stages: [
    { duration: '10m', target: 40 },  // 정상 상태
    { duration: '10m', target: 40 },  // 장애 상태 (수동 WireMock 전환)
    { duration: '10m', target: 40 },  // 복구 상태 (수동 WireMock 복구)
  ],
  thresholds: {
    'general_api_errors': ['rate<0.05'],  // 일반 API는 5% 미만 에러
  },
};

const BASE_URL = 'http://localhost:8080';

export default function() {
  const isLoginAttempt = Math.random() < 0.2;  // 20%는 로그인 시도
  
  if (isLoginAttempt) {
    // OAuth 로그인 시도
    const oauthStart = Date.now();
    const loginRes = http.post(
      `${BASE_URL}/api/auth/login`,
      JSON.stringify({
        code: 'mock-auth-code',
        origin: 'http://localhost:3000',
      }),
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: '10s',  // 10초 타임아웃 설정 확인
      }
    );
    
    oauthLatency.add(Date.now() - oauthStart);
    
    const oauthSuccess = check(loginRes, {
      'oauth login status is 200': (r) => r.status === 200,
      'oauth login response time < 10s': (r) => r.timings.duration < 10000,
    });
    
    oauthErrorRate.add(!oauthSuccess);
    errorRate.add(!oauthSuccess);
    
    sleep(5);
    
  } else {
    // 일반 API 호출 (OAuth 의존 없음)
    const homeRequests = [
      { method: 'GET', url: `${BASE_URL}/api/stories?size=20` },
      { method: 'GET', url: `${BASE_URL}/api/shops?size=20` },
    ];
    
    const responses = http.batch(homeRequests);
    responses.forEach(res => {
      const success = check(res, {
        'general API status is 200': (r) => r.status === 200,
        'general API response time < 1000ms': (r) => r.timings.duration < 1000,
      });
      generalAPIErrorRate.add(!success);
      errorRate.add(!success);
    });
    
    sleep(5);
  }
}
```

### 5.3 실행 및 장애 주입

```bash
# 1. WireMock 시작 (정상 응답)
docker-compose -f docker-compose.load-test.yml up -d wiremock

# 2. K6 테스트 시작
k6 run --out json=results/scenario5.json \
       scripts/scenario5_oauth_failure.js

# 3. 10분 후 장애 주입 (WireMock mapping 전환)
curl -X POST http://localhost:8081/__admin/mappings \
  -H "Content-Type: application/json" \
  -d @wiremock/mappings/oauth-failure.json

# 4. 20분 후 복구 (정상 mapping 복원)
curl -X DELETE http://localhost:8081/__admin/mappings/oauth-failure

# 5. 스레드 풀 모니터링
watch -n 2 "curl -s http://localhost:8080/actuator/metrics/tomcat.threads.busy | jq"
```

---

## 6. 검증 사항

### 6.1 타임아웃 설정 확인

#### 체크리스트

- [ ] **OAuth 클라이언트 타임아웃**
  - RestTemplate / WebClient 타임아웃 설정 여부
  - Connect timeout: 3초
  - Read timeout: 5초
  - **설정 없으면 무한 대기 → 스레드 풀 고갈**

- [ ] **타임아웃 발생 시 에러 핸들링**
  - `SocketTimeoutException` 캐치 여부
  - 사용자에게 명확한 에러 메시지 반환
  - 예: "로그인 서버에 일시적인 문제가 발생했습니다. 잠시 후 다시 시도해주세요."

#### 확인 방법

```java
// OauthClient.java
@Component
public class OauthClient {
    private final RestTemplate restTemplate;
    
    public OauthClient(RestTemplateBuilder builder) {
        this.restTemplate = builder
            .setConnectTimeout(Duration.ofSeconds(3))
            .setReadTimeout(Duration.ofSeconds(5))
            .build();
    }
    
    public LoginResult login(String code) {
        try {
            return restTemplate.postForObject(KAKAO_TOKEN_URL, request, LoginResult.class);
        } catch (ResourceAccessException e) {
            // 타임아웃 발생
            throw new BusinessException(BusinessErrorCode.OAUTH_SERVER_TIMEOUT);
        }
    }
}
```

### 6.2 스레드 풀 고갈 방지

#### 체크리스트

- [ ] **Tomcat 스레드 풀 사용률**
  - 정상 상태: 10-20% (20-40개/200개)
  - 장애 상태: 30-50% (60-100개/200개)
  - **80% 초과 시 위험: 일반 API도 지연 발생**

- [ ] **스레드 점유 시간**
  - OAuth 호출: 5초 타임아웃 후 스레드 해제
  - 8 VU × 5초 = 40 스레드 점유 (20%)
  - 추가 일반 API: ~20 스레드 (10%)
  - 총: ~60 스레드 (30%) → 안전

#### 확인 방법

```bash
# Tomcat 스레드 메트릭 확인
curl -s http://localhost:8080/actuator/metrics/tomcat.threads.busy | jq
curl -s http://localhost:8080/actuator/metrics/tomcat.threads.current | jq

# 기대값:
# - 정상: busy ~40, current 200
# - 장애: busy ~80, current 200 (40% 사용)
# - 위험: busy > 160 (80% 초과)
```

### 6.3 Circuit Breaker 작동

#### 체크리스트

- [ ] **Circuit Breaker 패턴 적용 여부**
  - Resilience4j 또는 Spring Cloud Circuit Breaker 사용
  - 실패율 임계값: 50% (10번 중 5번 실패)
  - Open 지속 시간: 10초
  - Half-Open 시도: 3번

- [ ] **Circuit Open 시 Fallback 응답**
  - 즉시 에러 반환 (타임아웃 대기 없음)
  - 사용자 경험 개선: "로그인 서비스 점검 중"

#### 확인 방법

```java
// OauthClient.java with Resilience4j
@CircuitBreaker(name = "oauth", fallbackMethod = "loginFallback")
public LoginResult login(String code) {
    return restTemplate.postForObject(KAKAO_TOKEN_URL, request, LoginResult.class);
}

private LoginResult loginFallback(String code, Exception e) {
    throw new BusinessException(BusinessErrorCode.OAUTH_SERVICE_UNAVAILABLE);
}

// application.yml
resilience4j:
  circuitbreaker:
    instances:
      oauth:
        failure-rate-threshold: 50
        wait-duration-in-open-state: 10s
        sliding-window-size: 10
```

---

## 7. 예상 결과

### 7.1 타임아웃 미설정 시 (실패 케이스)

```
정상 상태 (0-10분):
  - OAuth 성공률: 100%
  - 일반 API 성공률: 100%
  - 스레드 사용: 20%

장애 상태 (10-20분):
  - OAuth: 무한 대기 → 8 VU × 무한 = 스레드 고갈
  - 일반 API 성공률: 50% 이하 (스레드 부족으로 지연)
  - 스레드 사용: 100% (모든 스레드 블로킹)
  - 전체 서비스 마비

복구 상태 (20-30분):
  - OAuth 복구해도 스레드 고갈로 회복 불가
  - 서버 재시작 필요
```

### 7.2 타임아웃 설정 + Circuit Breaker (성공 케이스)

```
정상 상태 (0-10분):
  - OAuth 성공률: 100%
  - 일반 API 성공률: 100%
  - 스레드 사용: 20%

장애 상태 (10-20분):
  - OAuth 실패율: 100% (5초 타임아웃)
  - 10초 후 Circuit Open → 즉시 에러 반환
  - 일반 API 성공률: 98-100% (격리 성공)
  - 스레드 사용: 30-40% (일시적 증가 후 안정)

복구 상태 (20-30분):
  - Circuit Half-Open → 3번 시도 성공 → Closed
  - OAuth 성공률: 100% (30초 내 복구)
  - 일반 API 성공률: 100%
  - 스레드 사용: 20%
```

---

## 8. 결과 분석

### 8.1 K6 출력 예시 (성공 케이스)

```
     ✓ general API status is 200
     ✗ oauth login status is 200 (장애 구간)

     checks.........................: 86.5% ✓ 6,500     ✗ 1,020
     oauth_errors...................: 95.0% (장애 구간 100%, 전체 평균 95%)
     general_api_errors.............: 1.2%  ✓ 72       ✗ 5,880
     oauth_latency..................: avg=3.2s  (장애 시 5s 타임아웃)
     http_req_duration..............: avg=380ms (일반 API 정상)
     tomcat_threads_busy............: max=85/200 (42.5%)
```

### 8.2 판정 기준

#### ✅ 성공 (다음 조건 모두 충족)

- [ ] 일반 API 에러율 < 5% (장애 격리 성공)
- [ ] 일반 API 응답 시간 < 1000ms (지연 최소화)
- [ ] 스레드 풀 사용률 < 80% (고갈 방지)
- [ ] Circuit Breaker Open 시간 < 30초
- [ ] 복구 후 정상화 시간 < 1분

#### 🚨 실패 (다음 중 하나라도 해당)

- [ ] 일반 API 에러율 > 10% (장애 전파)
- [ ] 일반 API 응답 시간 > 2000ms (스레드 부족)
- [ ] 스레드 풀 사용률 > 90% (고갈 위험)
- [ ] Circuit Breaker 미작동 (무한 재시도)
- [ ] 복구 후 정상화 불가 (재시작 필요)

---

## 9. 다음 단계

### 9.1 성공 시

- ✅ 시나리오 6 진행: [DB 슬로우 쿼리 발생](06_scenario_slow_query.md)
- ✅ 외부 의존성 장애 격리 검증 완료

### 9.2 최적화 필요 시

- 🔧 **타임아웃 설정**: RestTemplate/WebClient timeout 추가
- 🔧 **Circuit Breaker 도입**: Resilience4j 적용
- 🔧 **Fallback 응답 개선**: 사용자 친화적 에러 메시지

### 9.3 실패 시

- 🚨 **긴급 타임아웃 설정**: Connect 3초, Read 5초
- 🚨 **스레드 풀 증설**: 200 → 300개 (임시 조치)
- 🚨 **비동기 처리 도입**: WebClient reactive

---

## 10. 참고 자료

- [00_load_test_prerequisites.md](00_load_test_prerequisites.md) — 테스트 전제 조건
- [Resilience4j Circuit Breaker](https://resilience4j.readme.io/docs/circuitbreaker)
- [Spring RestTemplate Timeout](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/client/RestTemplate.html)
- [Tomcat Thread Pool Tuning](https://tomcat.apache.org/tomcat-9.0-doc/config/executor.html)

---

## 문서 이력

| 버전 | 날짜 | 작성자 | 변경 내역 |
|------|------|--------|----------|
| 1.0 | 2026-06-26 | System | 초기 작성 (OAuth 장애 시나리오) |
