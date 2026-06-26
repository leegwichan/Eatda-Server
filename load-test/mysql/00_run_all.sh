#!/bin/bash

# =====================================================
# 로드 테스트 데이터 일괄 생성 스크립트
# 사용법: ./00_run_all.sh
#
# 시나리오: 초기 서비스 (론칭 후 6개월~1년)
#   - Member: 50,000명
#   - Cheer: 120,000개
#   - Story: 30,000개
# =====================================================

set -e  # 에러 발생 시 즉시 중단
set -o pipefail  # 파이프라인에서 에러 발생 시 즉시 중단

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# MySQL 연결 정보 (docker-compose.load-test.yml 기준)
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3308}"        # docker-compose.load-test.yml의 호스트 포트
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-rootpassword}"  # docker-compose.load-test.yml의 MYSQL_ROOT_PASSWORD
DB_NAME="${DB_NAME:-eatda}"

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 시작 시간 기록
START_TIME=$(date +%s)

log_info "========================================"
log_info "로드 테스트 데이터 생성 시작"
log_info "========================================"
log_info "DB Host: $DB_HOST:$DB_PORT"
log_info "DB Name: $DB_NAME"
log_info "시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# MySQL 연결 테스트
log_info "MySQL 연결 테스트 중..."
if ! MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "USE $DB_NAME;" 2>/dev/null; then
    log_error "MySQL 연결 실패. 연결 정보를 확인하세요."
    exit 1
fi
log_success "MySQL 연결 성공"
echo ""

# Foreign Key 체크 비활성화
log_info "Foreign Key 체크 비활성화..."
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" -e "SET FOREIGN_KEY_CHECKS = 0;"
log_success "Foreign Key 체크 비활성화 완료"
echo ""

log_warning "======================================"
log_warning "주의: init.sql은 별도로 실행되지 않습니다."
log_warning "초기 설치 시에는 먼저 init.sql을 실행하세요:"
log_warning "  mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD $DB_NAME < init.sql"
log_warning "======================================"
echo ""

# 1. Member 생성
log_info "======================================"
log_info "Step 1: Member 50,000명 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/01_generate_members.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 1 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 2. Store 생성
log_info "======================================"
log_info "Step 2: Store 10,000개 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/02_generate_stores.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 2 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 3. Cheer 생성
log_info "======================================"
log_info "Step 3: Cheer 120,000개 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/03_generate_cheers.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 3 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 4. CheerImage 생성
log_info "======================================"
log_info "Step 4: CheerImage 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/04_generate_cheer_images.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 4 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 5. CheerTag 생성
log_info "======================================"
log_info "Step 5: CheerTag 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/05_generate_cheer_tags.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 5 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 6. Story 생성
log_info "======================================"
log_info "Step 6: Story 30,000개 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/06_generate_stories.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 6 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 7. StoryImage 생성
log_info "======================================"
log_info "Step 7: StoryImage 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/07_generate_story_images.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 7 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 8. 핫플레이스 데이터 생성
log_info "======================================"
log_info "Step 8: 핫플레이스 데이터 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/08_generate_hotplace_data.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 8 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# 9. 바이럴 스토리 데이터 생성
log_info "======================================"
log_info "Step 9: 바이럴 스토리 데이터 생성 중..."
log_info "======================================"
STEP_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$(dirname "$0")/09_generate_viral_story_data.sql"
STEP_END=$(date +%s)
STEP_DURATION=$((STEP_END - STEP_START))
log_success "Step 9 완료 (소요 시간: ${STEP_DURATION}초)"
echo ""

# Foreign Key 체크 재활성화
log_info "Foreign Key 체크 재활성화..."
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" -e "SET FOREIGN_KEY_CHECKS = 1;"
log_success "Foreign Key 체크 재활성화 완료"
echo ""

# 인덱스 최적화
log_info "======================================"
log_info "인덱스 최적화 중..."
log_info "======================================"
OPTIMIZE_START=$(date +%s)
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" <<EOF
OPTIMIZE TABLE member;
OPTIMIZE TABLE store;
OPTIMIZE TABLE cheer;
OPTIMIZE TABLE story;
OPTIMIZE TABLE cheer_image;
OPTIMIZE TABLE story_image;
OPTIMIZE TABLE cheer_tag;
EOF
OPTIMIZE_END=$(date +%s)
OPTIMIZE_DURATION=$((OPTIMIZE_END - OPTIMIZE_START))
log_success "인덱스 최적화 완료 (소요 시간: ${OPTIMIZE_DURATION}초)"
echo ""

# 최종 통계 출력
log_info "======================================"
log_info "최종 데이터 통계"
log_info "======================================"
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" <<EOF
SELECT 'Member' AS entity, COUNT(*) AS count FROM member
UNION ALL
SELECT 'Store', COUNT(*) FROM store
UNION ALL
SELECT 'Cheer', COUNT(*) FROM cheer
UNION ALL
SELECT 'Story', COUNT(*) FROM story
UNION ALL
SELECT 'CheerImage', COUNT(*) FROM cheer_image
UNION ALL
SELECT 'StoryImage', COUNT(*) FROM story_image
UNION ALL
SELECT 'CheerTag', COUNT(*) FROM cheer_tag;
EOF
echo ""

# 종료 시간 기록
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_DURATION / 60))
SECONDS=$((TOTAL_DURATION % 60))

log_success "======================================"
log_success "데이터 생성 완료!"
log_success "======================================"
log_success "종료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
log_success "총 소요 시간: ${MINUTES}분 ${SECONDS}초"
echo ""

log_info "======================================"
log_info "다음 단계: 데이터 백업"
log_info "======================================"
log_info "다음 명령어로 데이터를 백업할 수 있습니다:"
echo ""
echo "  docker exec eatda-mysql mysqldump -u root -prootpassword eatda > load-test-data-backup-\$(date +%Y%m%d-%H%M%S).sql"
echo ""
log_info "백업 파일을 복원하려면:"
echo ""
echo "  docker exec -i eatda-mysql mysql -u root -prootpassword eatda < load-test-data-backup-YYYYMMDD-HHMMSS.sql"
echo ""
