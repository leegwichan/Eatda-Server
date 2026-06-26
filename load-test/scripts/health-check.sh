#!/bin/bash

echo "=== Load Test Environment Health Check ==="
echo ""

# Function to check HTTP endpoint
check_http() {
    local name=$1
    local url=$2
    local expected=$3

    status=$(curl -s -o /dev/null -w "%{http_code}" "$url" --max-time 5)
    if [ "$status" = "$expected" ]; then
        echo "✅ $name: OK (HTTP $status)"
        return 0
    else
        echo "❌ $name: FAILED (HTTP $status, expected $expected)"
        return 1
    fi
}

# Function to check Docker health
check_docker_health() {
    local name=$1
    local container=$2

    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "❌ $name: container not found"
        return 1
    fi

    health=$(docker inspect "$container" --format='{{.State.Health.Status}}' 2>/dev/null)
    if [ "$health" = "healthy" ]; then
        echo "✅ $name: healthy"
        return 0
    elif [ -z "$health" ]; then
        status=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null)
        if [ "$status" = "running" ]; then
            echo "⚠️  $name: running (no health check configured)"
            return 0
        else
            echo "❌ $name: $status"
            return 1
        fi
    else
        echo "❌ $name: $health"
        return 1
    fi
}

# Function to check port
check_port() {
    local name=$1
    local host=$2
    local port=$3

    if nc -z -w 2 "$host" "$port" 2>/dev/null; then
        echo "✅ $name: port $port is open"
        return 0
    else
        echo "❌ $name: port $port is not accessible"
        return 1
    fi
}

failed=0

# Check HTTP endpoints
echo "1. Application Health Checks:"
check_http "Spring Boot" "http://localhost:8080/actuator/health" "200" || ((failed++))
check_http "Prometheus" "http://localhost:9090/-/healthy" "200" || ((failed++))
check_http "Grafana" "http://localhost:3000/api/health" "200" || ((failed++))
check_http "LocalStack" "http://localhost:4566/_localstack/health" "200" || ((failed++))

echo ""
echo "2. Docker Container Health:"
check_docker_health "Spring Boot App" "eatda-app" || ((failed++))
check_docker_health "MySQL" "eatda-mysql" || ((failed++))
check_docker_health "LocalStack" "eatda-localstack" || ((failed++))
check_docker_health "Prometheus" "eatda-prometheus" || ((failed++))
check_docker_health "Grafana" "eatda-grafana" || ((failed++))
check_docker_health "Pinpoint HBase" "eatda-pinpoint-hbase" || ((failed++))
check_docker_health "Pinpoint Collector" "eatda-pinpoint-collector" || ((failed++))
check_docker_health "Pinpoint Web" "eatda-pinpoint-web" || ((failed++))

echo ""
echo "3. Port Connectivity:"
check_port "Application" "localhost" "8080" || ((failed++))
check_port "MySQL" "localhost" "3308" || ((failed++))
check_port "LocalStack" "localhost" "4566" || ((failed++))
check_port "Prometheus" "localhost" "9090" || ((failed++))
check_port "Grafana" "localhost" "3000" || ((failed++))
check_port "Pinpoint Web" "localhost" "8081" || ((failed++))

echo ""
echo "4. Database Connectivity:"
if docker exec eatda-mysql mysqladmin ping -h localhost -u root -prootpassword 2>&1 | grep -q "mysqld is alive"; then
    echo "✅ MySQL: database is alive"
else
    echo "❌ MySQL: database ping failed"
    ((failed++))
fi

echo ""
echo "5. Service-Specific Checks:"
# Check S3 service in LocalStack
s3_status=$(curl -s http://localhost:4566/_localstack/health | jq -r '.services.s3' 2>/dev/null)
if [ "$s3_status" = "running" ]; then
    echo "✅ LocalStack S3: running"
else
    echo "❌ LocalStack S3: not running (status: $s3_status)"
    ((failed++))
fi

# Check Spring Boot components
db_status=$(curl -s http://localhost:8080/actuator/health 2>/dev/null | jq -r '.components.db.status' 2>/dev/null)
if [ "$db_status" = "UP" ]; then
    echo "✅ Spring Boot DB Connection: UP"
else
    echo "❌ Spring Boot DB Connection: $db_status"
    ((failed++))
fi

echo ""
echo "=========================================="
echo "Container Summary:"
echo "=========================================="
docker ps --filter name=eatda --format "table {{.Names}}\t{{.Status}}" | head -10

echo ""
if [ $failed -eq 0 ]; then
    echo "✅ All health checks passed!"
    exit 0
else
    echo "❌ $failed health check(s) failed"
    exit 1
fi
