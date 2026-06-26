# Prometheus 메트릭 수집 확인 및 쿼리 가이드

## ✅ 현재 상태

모든 타겟이 정상적으로 수집 중입니다:
- ✅ Prometheus 자체: `up`
- ✅ Spring Boot App (eatda-app:8080): `up`

---

## 1. 기본 상태 확인

### 1.1 Prometheus Targets 확인
```bash
# 모든 타겟 상태 확인
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# 특정 job만 확인
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spring-boot-app")'
```

### 1.2 수집 중인 메트릭 목록 확인
```bash
# 모든 메트릭 이름 조회
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep -E "jvm|http|hikari" | head -20

# 특정 패턴의 메트릭만 조회
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep "http_server"
```

---

## 2. 주요 메트릭 쿼리

### 2.1 JVM 메트릭

**힙 메모리 사용량**
```bash
# 현재 값 조회 (MB 단위)
curl -s 'http://localhost:9090/api/v1/query?query=jvm_memory_used_bytes' | \
  jq '.data.result[] | {id: .metric.id, area: .metric.area, value_mb: (.value[1] | tonumber / 1024 / 1024 | floor)}'

# 힙 메모리만 조회
curl -s 'http://localhost:9090/api/v1/query?query=jvm_memory_used_bytes{area="heap"}' | \
  jq '.data.result[] | {id: .metric.id, value_mb: (.value[1] | tonumber / 1024 / 1024 | floor)}'
```

**GC 통계**
```bash
# GC 발생 횟수
curl -s 'http://localhost:9090/api/v1/query?query=jvm_gc_pause_seconds_count' | \
  jq '.data.result[] | {gc: .metric.action, cause: .metric.cause, count: .value[1]}'

# GC 소요 시간 합계
curl -s 'http://localhost:9090/api/v1/query?query=jvm_gc_pause_seconds_sum' | \
  jq '.data.result[] | {gc: .metric.action, sum_seconds: .value[1]}'
```

**스레드 상태**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=jvm_threads_states_threads' | \
  jq '.data.result[] | {state: .metric.state, count: .value[1]}'

# 총 스레드 수
curl -s 'http://localhost:9090/api/v1/query?query=jvm_threads_live_threads' | \
  jq '.data.result[] | "Live threads: \(.value[1])"'
```

### 2.2 HTTP 요청 메트릭

**총 요청 수**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=http_server_requests_seconds_count' | \
  jq '.data.result[] | {method: .metric.method, uri: .metric.uri, status: .metric.status, count: .value[1]}'
```

**요청 응답 시간 분포 (Percentiles)**
```bash
# P99 (99번째 백분위수)
curl -s 'http://localhost:9090/api/v1/query?query=http_server_requests_seconds{quantile="0.99"}' | \
  jq '.data.result[] | {uri: .metric.uri, p99_seconds: .value[1]}'

# P95
curl -s 'http://localhost:9090/api/v1/query?query=http_server_requests_seconds{quantile="0.95"}' | \
  jq '.data.result[] | {uri: .metric.uri, p95_seconds: .value[1]}'

# P50 (중앙값)
curl -s 'http://localhost:9090/api/v1/query?query=http_server_requests_seconds{quantile="0.5"}' | \
  jq '.data.result[] | {uri: .metric.uri, p50_seconds: .value[1]}'
```

**평균 응답 시간 (최근 5분)**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_server_requests_seconds_sum[5m])/rate(http_server_requests_seconds_count[5m])' | \
  jq '.data.result[] | {uri: .metric.uri, avg_seconds: .value[1]}'
```

**초당 요청 수 (RPS - Requests Per Second)**
```bash
# 최근 1분간 평균
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_server_requests_seconds_count[1m])' | \
  jq '.data.result[] | {method: .metric.method, uri: .metric.uri, rps: .value[1]}'

# 전체 합계
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(http_server_requests_seconds_count[1m]))' | \
  jq '.data.result[] | "Total RPS: \(.value[1])"'
```

**에러율**
```bash
# 4xx 에러 (최근 5분)
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_server_requests_seconds_count{status=~"4.."}[5m])' | \
  jq '.data.result[] | {uri: .metric.uri, status: .metric.status, rate: .value[1]}'

# 5xx 에러 (최근 5분)
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_server_requests_seconds_count{status=~"5.."}[5m])' | \
  jq '.data.result[] | {uri: .metric.uri, status: .metric.status, rate: .value[1]}'

# 전체 에러율 (%)
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(http_server_requests_seconds_count{status=~"[45].."}[5m]))/sum(rate(http_server_requests_seconds_count[5m]))*100' | \
  jq '.data.result[] | "Error rate: \(.value[1])%"'
```

### 2.3 데이터베이스 (HikariCP) 메트릭

**커넥션 풀 상태**
```bash
# 활성 커넥션 수
curl -s 'http://localhost:9090/api/v1/query?query=hikaricp_connections_active' | \
  jq '.data.result[] | "Active: \(.value[1])"'

# 유휴 커넥션 수
curl -s 'http://localhost:9090/api/v1/query?query=hikaricp_connections_idle' | \
  jq '.data.result[] | "Idle: \(.value[1])"'

# 총 커넥션 수
curl -s 'http://localhost:9090/api/v1/query?query=hikaricp_connections' | \
  jq '.data.result[] | "Total: \(.value[1])"'

# 최대 커넥션 수
curl -s 'http://localhost:9090/api/v1/query?query=hikaricp_connections_max' | \
  jq '.data.result[] | "Max: \(.value[1])"'

# 대기 중인 요청 수
curl -s 'http://localhost:9090/api/v1/query?query=hikaricp_connections_pending' | \
  jq '.data.result[] | "Pending: \(.value[1])"'
```

**커넥션 사용률 (%)**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=(hikaricp_connections_active/hikaricp_connections_max)*100' | \
  jq '.data.result[] | "Connection usage: \(.value[1])%"'
```

**커넥션 획득 시간**
```bash
# 평균 커넥션 획득 시간 (ms)
curl -s 'http://localhost:9090/api/v1/query?query=1000*hikaricp_connections_acquire_seconds_sum/hikaricp_connections_acquire_seconds_count' | \
  jq '.data.result[] | "Avg acquire time: \(.value[1])ms"'
```

### 2.4 시스템 메트릭

**CPU 사용률**
```bash
# 시스템 전체 CPU
curl -s 'http://localhost:9090/api/v1/query?query=system_cpu_usage' | \
  jq '.data.result[] | "System CPU: \(.value[1] | tonumber * 100)%"'

# 프로세스 CPU
curl -s 'http://localhost:9090/api/v1/query?query=process_cpu_usage' | \
  jq '.data.result[] | "Process CPU: \(.value[1] | tonumber * 100)%"'
```

**디스크 사용량**
```bash
# 사용 가능한 디스크 공간 (GB)
curl -s 'http://localhost:9090/api/v1/query?query=disk_free_bytes/1024/1024/1024' | \
  jq '.data.result[] | "Free: \(.value[1] | tonumber | floor)GB"'

# 전체 디스크 공간 (GB)
curl -s 'http://localhost:9090/api/v1/query?query=disk_total_bytes/1024/1024/1024' | \
  jq '.data.result[] | "Total: \(.value[1] | tonumber | floor)GB"'

# 디스크 사용률 (%)
curl -s 'http://localhost:9090/api/v1/query?query=(1-disk_free_bytes/disk_total_bytes)*100' | \
  jq '.data.result[] | "Disk usage: \(.value[1])%"'
```

---

## 3. 부하 테스트용 실시간 모니터링

### 3.1 실시간 모니터링 스크립트

파일 생성: `load-test/scripts/monitor-metrics.sh`

```bash
#!/bin/bash

while true; do
    clear
    echo "========================================"
    echo "   Real-time Load Test Metrics"
    echo "========================================"
    echo ""
    
    # RPS
    echo "📊 Requests Per Second (last 1m):"
    curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(http_server_requests_seconds_count[1m]))' | \
        jq -r '.data.result[] | "  Total: \(.value[1] | tonumber | floor * 60) req/min"'
    echo ""
    
    # 평균 응답 시간
    echo "⏱️  Average Response Time (last 5m):"
    curl -s 'http://localhost:9090/api/v1/query?query=1000*rate(http_server_requests_seconds_sum[5m])/rate(http_server_requests_seconds_count[5m])' | \
        jq -r '.data.result[] | "  \(.metric.uri): \(.value[1] | tonumber | floor)ms"' | head -5
    echo ""
    
    # 에러율
    echo "❌ Error Rate (last 5m):"
    error_rate=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(http_server_requests_seconds_count{status=~"[45].."}[5m]))/sum(rate(http_server_requests_seconds_count[5m]))*100' | \
        jq -r '.data.result[]?.value[1] // "0"')
    echo "  ${error_rate}%"
    echo ""
    
    # HikariCP
    echo "🔗 Database Connections:"
    curl -s 'http://localhost:9090/api/v1/query?query=hikaricp_connections_active' | \
        jq -r '.data.result[] | "  Active: \(.value[1])"'
    curl -s 'http://localhost:9090/api/v1/query?query=hikaricp_connections_idle' | \
        jq -r '.data.result[] | "  Idle: \(.value[1])"'
    curl -s 'http://localhost:9090/api/v1/query?query=(hikaricp_connections_active/hikaricp_connections_max)*100' | \
        jq -r '.data.result[] | "  Usage: \(.value[1] | tonumber | floor)%"'
    echo ""
    
    # JVM Memory
    echo "💾 JVM Heap Memory:"
    curl -s 'http://localhost:9090/api/v1/query?query=sum(jvm_memory_used_bytes{area="heap"})/1024/1024' | \
        jq -r '.data.result[] | "  Used: \(.value[1] | tonumber | floor)MB"'
    curl -s 'http://localhost:9090/api/v1/query?query=sum(jvm_memory_max_bytes{area="heap"})/1024/1024' | \
        jq -r '.data.result[] | "  Max: \(.value[1] | tonumber | floor)MB"'
    echo ""
    
    # CPU
    echo "⚙️  CPU Usage:"
    curl -s 'http://localhost:9090/api/v1/query?query=process_cpu_usage' | \
        jq -r '.data.result[] | "  Process: \(.value[1] | tonumber * 100 | floor)%"'
    echo ""
    
    echo "========================================"
    echo "Press Ctrl+C to exit"
    echo "Next update in 5 seconds..."
    
    sleep 5
done
```

실행:
```bash
chmod +x load-test/scripts/monitor-metrics.sh
./load-test/scripts/monitor-metrics.sh
```

### 3.2 핵심 메트릭 대시보드 쿼리 (PromQL)

**처리량 (Throughput)**
```promql
sum(rate(http_server_requests_seconds_count[1m]))
```

**지연시간 (Latency) - P95**
```promql
histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[5m])) by (le, uri))
```

**에러율 (Error Rate) %**
```promql
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count[5m])) * 100
```

**데이터베이스 커넥션 사용률 %**
```promql
(hikaricp_connections_active / hikaricp_connections_max) * 100
```

**JVM 힙 메모리 사용률 %**
```promql
(sum(jvm_memory_used_bytes{area="heap"}) / sum(jvm_memory_max_bytes{area="heap"})) * 100
```

---

## 4. Prometheus Web UI 활용

### 접속
```
http://localhost:9090
```

### Graph 페이지에서 쿼리 실행
1. 상단 메뉴에서 **"Graph"** 클릭
2. 쿼리 입력란에 PromQL 쿼리 입력
3. **"Execute"** 버튼 클릭
4. **"Graph"** 탭에서 시각화 확인
5. **"Table"** 탭에서 테이블 형식 확인

### 주요 메뉴
- **Graph**: 메트릭 쿼리 및 시각화
- **Alerts**: 알림 규칙 확인
- **Status > Targets**: 스크랩 대상 상태
- **Status > Configuration**: Prometheus 설정
- **Status > Service Discovery**: 서비스 디스커버리 상태

---

## 5. 트러블슈팅

### Target이 Down 상태인 경우
```bash
# 에러 메시지 확인
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.health=="down") | {job: .labels.job, instance: .labels.instance, error: .lastError}'

# 애플리케이션 엔드포인트 직접 확인
curl -v http://localhost:8080/actuator/prometheus
```

### 메트릭이 수집되지 않는 경우
```bash
# Actuator 엔드포인트 활성화 확인
curl http://localhost:8080/actuator | jq '._links | keys'

# Prometheus 설정 확인
curl http://localhost:9090/api/v1/status/config | jq '.data.yaml' | grep -A 5 spring-boot-app
```

### 특정 메트릭이 보이지 않는 경우
```bash
# 애플리케이션에서 직접 메트릭 확인
curl http://localhost:8080/actuator/prometheus | grep "메트릭이름"

# Prometheus에서 메트릭 검색
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep "메트릭이름"
```

---

## 6. 유용한 PromQL 예제

**최근 5분간 가장 느린 엔드포인트 Top 5**
```promql
topk(5, rate(http_server_requests_seconds_sum[5m]) / rate(http_server_requests_seconds_count[5m]))
```

**메모리 증가율 (bytes/sec)**
```promql
rate(jvm_memory_used_bytes{area="heap"}[5m])
```

**GC 빈도 (GC events/sec)**
```promql
rate(jvm_gc_pause_seconds_count[5m])
```

**커넥션 풀 포화도 경고 (90% 이상)**
```promql
(hikaricp_connections_active / hikaricp_connections_max) > 0.9
```

**초당 요청 수 (URI별)**
```promql
sum by(uri) (rate(http_server_requests_seconds_count[1m]))
```

**평균 응답 시간 증가 추세 (URI별)**
```promql
deriv(rate(http_server_requests_seconds_sum[5m])[10m:]) / rate(http_server_requests_seconds_count[5m])
```

---

## 7. 참고 자료

### Prometheus 문서
- [Query Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [PromQL Functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)
- [HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/)

### Micrometer 문서
- [Micrometer Prometheus](https://micrometer.io/docs/registry/prometheus)
- [Spring Boot Actuator Metrics](https://docs.spring.io/spring-boot/reference/actuator/metrics.html)
