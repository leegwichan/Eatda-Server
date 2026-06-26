# Load Test Environment Health Check Guide

## Quick Check - All Components

```bash
# Check all container status
docker ps --filter name=eatda --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check Docker health status
docker ps --filter name=eatda --format "table {{.Names}}\t{{.Status}}" | grep healthy
```

---

## 1. Spring Boot Application (eatda-app)

### Method 1: Actuator Health Endpoint (추천)
```bash
curl -s http://localhost:8080/actuator/health | jq '.'
```

**Expected Output:**
```json
{
  "status": "UP",
  "components": {
    "db": { "status": "UP" },
    "diskSpace": { "status": "UP" },
    "ping": { "status": "UP" }
  }
}
```

### Method 2: Docker Health Check
```bash
docker inspect eatda-app --format='{{.State.Health.Status}}'
# Expected: healthy
```

### Method 3: Specific Endpoints
```bash
# Info endpoint
curl -s http://localhost:8080/actuator/info

# Metrics endpoint
curl -s http://localhost:8080/actuator/metrics

# Prometheus metrics
curl -s http://localhost:8080/actuator/prometheus
```

### Method 4: Check Application Logs
```bash
docker logs eatda-app --tail 50

# Follow logs in real-time
docker logs -f eatda-app
```

---

## 2. MySQL Database (eatda-mysql)

### Method 1: Docker Health Check (추천)
```bash
docker inspect eatda-mysql --format='{{.State.Health.Status}}'
# Expected: healthy
```

### Method 2: MySQL Connection Test
```bash
docker exec eatda-mysql mysqladmin ping -h localhost -u root -prootpassword
# Expected: mysqld is alive
```

### Method 3: Database Access Test
```bash
# Test with application user
docker exec eatda-mysql mysql -u eatda -peatda123 -e "SELECT 1 as health;" eatda

# Check databases
docker exec eatda-mysql mysql -u eatda -peatda123 -e "SHOW DATABASES;"

# Check tables
docker exec eatda-mysql mysql -u eatda -peatda123 -e "SHOW TABLES;" eatda
```

### Method 4: Connection Pool Status
```bash
# Check connections
docker exec eatda-mysql mysql -u root -prootpassword -e "SHOW PROCESSLIST;"
```

### Method 5: Connect from host
```bash
mysql -h 127.0.0.1 -P 3308 -u eatda -peatda123 eatda
```

---

## 3. LocalStack (S3 Mock)

### Method 1: Health Endpoint (추천)
```bash
curl -s http://localhost:4566/_localstack/health | jq '.services'
# Expected: "s3": "running"
```

### Method 2: Docker Health Check
```bash
docker inspect eatda-localstack --format='{{.State.Health.Status}}'
# Expected: healthy
```

### Method 3: S3 Service Test
```bash
# List buckets
aws --endpoint-url=http://localhost:4566 s3 ls

# Check specific bucket
aws --endpoint-url=http://localhost:4566 s3 ls s3://eatda-storage-local/
```

### Method 4: Check LocalStack Logs
```bash
docker logs eatda-localstack --tail 50
```

---

## 4. Prometheus

### Method 1: Health Check (추천)
```bash
curl -s http://localhost:9090/-/healthy
# Expected: Prometheus Server is Healthy.
```

### Method 2: Ready Check
```bash
curl -s http://localhost:9090/-/ready
# Expected: Prometheus Server is Ready.
```

### Method 3: Targets Status
```bash
# Check scrape targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

### Method 4: Web UI
```
http://localhost:9090
```

---

## 5. Grafana

### Method 1: Health API (추천)
```bash
curl -s http://localhost:3000/api/health | jq '.'
```

**Expected Output:**
```json
{
  "database": "ok",
  "version": "13.1.0"
}
```

### Method 2: Login Test
```bash
curl -s -u admin:admin http://localhost:3000/api/org
```

### Method 3: Web UI
```
http://localhost:3000
Username: admin
Password: admin
```

---

## 6. Pinpoint HBase

### Method 1: Docker Container Status (추천)
```bash
docker ps --filter name=eatda-pinpoint-hbase --format "table {{.Names}}\t{{.Status}}"
```

### Method 2: ZooKeeper Port Check
```bash
nc -zv localhost 2181
# Expected: Connection succeeded
```

### Method 3: HBase Master Port Check
```bash
nc -zv localhost 16000
nc -zv localhost 16010  # Web UI port
```

### Method 4: Check Logs
```bash
docker logs eatda-pinpoint-hbase --tail 50
```

---

## 7. Pinpoint Collector

### Method 1: Docker Container Status (추천)
```bash
docker ps --filter name=eatda-pinpoint-collector --format "table {{.Names}}\t{{.Status}}"
```

### Method 2: Port Check
```bash
# TCP Receiver
nc -zv localhost 9994

# gRPC ports
nc -zv localhost 9991
nc -zv localhost 9992
nc -zv localhost 9993
```

### Method 3: Check Logs
```bash
docker logs eatda-pinpoint-collector --tail 50
```

---

## 8. Pinpoint Web

### Method 1: HTTP Check (추천)
```bash
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:8081
# Expected: HTTP Status: 200 or 302
```

### Method 2: Docker Container Status
```bash
docker ps --filter name=eatda-pinpoint-web --format "table {{.Names}}\t{{.Status}}"
```

### Method 3: Web UI
```
http://localhost:8081
```

---

## Automated Health Check Script

모든 컴포넌트를 한 번에 체크하는 스크립트:

```bash
#!/bin/bash

echo "=== Load Test Environment Health Check ==="
echo ""

# Function to check HTTP endpoint
check_http() {
    local name=$1
    local url=$2
    local expected=$3
    
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    if [ "$status" = "$expected" ]; then
        echo "✅ $name: OK (HTTP $status)"
    else
        echo "❌ $name: FAILED (HTTP $status, expected $expected)"
    fi
}

# Function to check Docker health
check_docker_health() {
    local name=$1
    local container=$2
    
    health=$(docker inspect "$container" --format='{{.State.Health.Status}}' 2>/dev/null)
    if [ "$health" = "healthy" ]; then
        echo "✅ $name: healthy"
    elif [ -z "$health" ]; then
        status=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null)
        if [ "$status" = "running" ]; then
            echo "⚠️  $name: running (no health check)"
        else
            echo "❌ $name: $status"
        fi
    else
        echo "❌ $name: $health"
    fi
}

# Check all components
echo "1. Application Health Checks:"
check_http "Spring Boot" "http://localhost:8080/actuator/health" "200"
check_http "Prometheus" "http://localhost:9090/-/healthy" "200"
check_http "Grafana" "http://localhost:3000/api/health" "200"
check_http "LocalStack" "http://localhost:4566/_localstack/health" "200"
check_http "Pinpoint Web" "http://localhost:8081" "200"

echo ""
echo "2. Docker Container Health:"
check_docker_health "eatda-app" "eatda-app"
check_docker_health "eatda-mysql" "eatda-mysql"
check_docker_health "eatda-localstack" "eatda-localstack"
check_docker_health "eatda-prometheus" "eatda-prometheus"
check_docker_health "eatda-grafana" "eatda-grafana"
check_docker_health "eatda-pinpoint-hbase" "eatda-pinpoint-hbase"
check_docker_health "eatda-pinpoint-collector" "eatda-pinpoint-collector"
check_docker_health "eatda-pinpoint-web" "eatda-pinpoint-web"

echo ""
echo "3. Container Summary:"
docker ps --filter name=eatda --format "table {{.Names}}\t{{.Status}}"
```

스크립트 실행:
```bash
# 실행 권한 부여
chmod +x load-test/scripts/health-check.sh

# 실행
./load-test/scripts/health-check.sh
```

---

## Troubleshooting

### 컨테이너가 시작되지 않는 경우
```bash
# 로그 확인
docker logs <container-name>

# 컨테이너 재시작
docker restart <container-name>

# 전체 재시작
cd load-test
docker-compose -f docker-compose.load-test.yml restart
```

### Health check가 실패하는 경우
```bash
# 상세 로그 확인
docker logs <container-name> --tail 100

# 컨테이너 내부 접속
docker exec -it <container-name> /bin/bash

# 네트워크 연결 확인
docker network inspect load-test_eatda-network
```

### 포트 충돌 문제
```bash
# 포트 사용 확인
lsof -i :<port-number>

# 프로세스 종료
kill -9 <PID>
```

---

## Monitoring URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://localhost:8080 | - |
| Swagger UI | http://localhost:8080/docs/swagger | - |
| Actuator | http://localhost:8080/actuator | - |
| Prometheus | http://localhost:9090 | - |
| Grafana | http://localhost:3000 | admin/admin |
| Pinpoint Web | http://localhost:8081 | - |
| LocalStack | http://localhost:4566 | - |
| MySQL | localhost:3308 | eatda/eatda123 |
