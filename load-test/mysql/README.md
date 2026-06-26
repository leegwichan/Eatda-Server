# 로드 테스트 데이터 생성 스크립트

## 개요

이 디렉토리는 Eatda 서버의 로드 테스트를 위한 대량 데이터 생성 SQL 스크립트를 포함합니다.

**시나리오**: 초기 서비스 (론칭 후 6개월~1년) — 빠른 성장 초기 단계

## 파일 구조

```
load-test/mysql/
├── 00_run_all.sh                    # 모든 스크립트를 순차 실행하는 쉘 스크립트
├── init.sql                         # 기존 초기 데이터 (80명, 110개 가게 등)
├── 01_generate_members.sql          # Member 50,000명 생성
├── 02_generate_stores.sql           # Store 10,000개 생성
├── 03_generate_cheers.sql           # Cheer 120,000개 생성 (롱테일 분포)
├── 04_generate_cheer_images.sql     # CheerImage ~180,000개 생성
├── 05_generate_cheer_tags.sql       # CheerTag ~300,000개 생성
├── 06_generate_stories.sql          # Story 30,000개 생성
├── 07_generate_story_images.sql     # StoryImage ~60,000개 생성
├── 08_generate_hotplace_data.sql    # 핫플레이스 집중 데이터 (시나리오 2)
└── 09_generate_viral_story_data.sql # 바이럴 스토리 데이터 (시나리오 3)
```

## 사용 방법

### 방법 1: 일괄 실행 (권장)

```bash
# 1. Docker Compose로 MySQL 실행
cd /Users/keochan/Documents/Eatda-Server/load-test
docker-compose -f docker-compose.load-test.yml up -d mysql

# 2. MySQL 연결 확인 (비밀번호: rootpassword)
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword

# 3. 초기 설치 시: init.sql 먼저 실행 (최초 1회만)
cd mysql
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < init.sql

# 4. 모든 대량 데이터 생성 스크립트 일괄 실행
./00_run_all.sh
```

**재실행 시 (기존 더미 데이터 삭제 후 재생성):**
```bash
# init.sql은 건너뛰고 바로 실행
./00_run_all.sh
```

**환경 변수 커스터마이징 (선택):**

```bash
# 기본값: docker-compose.load-test.yml 설정에 맞춰져 있음
DB_HOST=127.0.0.1 \
DB_PORT=3308 \
DB_USER=root \
DB_PASSWORD=rootpassword \
DB_NAME=eatda \
./00_run_all.sh
```

### 방법 2: 개별 실행

각 SQL 파일을 순차적으로 실행할 수 있습니다.

```bash
# docker-compose.load-test.yml의 MySQL 사용 (포트 3308, 비밀번호 rootpassword)

# 초기 설치 시: 기존 데이터 로드 (최초 1회만)
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < init.sql

# Member 생성 (재실행 가능 - 기존 더미 데이터 삭제 후 재생성)
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 01_generate_members.sql

# Store 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 02_generate_stores.sql

# Cheer 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 03_generate_cheers.sql

# CheerImage 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 04_generate_cheer_images.sql

# CheerTag 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 05_generate_cheer_tags.sql

# Story 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 06_generate_stories.sql

# StoryImage 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 07_generate_story_images.sql

# 핫플레이스 데이터 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 08_generate_hotplace_data.sql

# 바이럴 스토리 데이터 생성
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 09_generate_viral_story_data.sql
```

## 생성되는 데이터

| 엔티티 | 기존 (init.sql) | 추가 생성 | 총합 |
|--------|----------------|----------|------|
| **Member** | 80명 | 50,000명 | 50,080명 |
| **Store** | 110개 | 10,000개 | 10,110개 |
| **Cheer** | 125개 | 120,000개 | 120,125개 |
| **Story** | 24개 | 30,000개 | 30,024개 |
| **CheerImage** | 83개 | ~180,000개 | ~180,083개 |
| **StoryImage** | 25개 | ~60,000개 | ~60,025개 |
| **CheerTag** | 313개 | ~300,000개 | ~300,313개 |

### 특수 데이터

1. **핫플레이스 (시나리오 2)**
   - Store ID: 자동 생성 (성수동 신상 맛집)
   - Cheer: 300개
   - Story: 50개
   - 이미지 및 태그 포함

2. **바이럴 스토리 (시나리오 3)**
   - Story ID: 자동 생성 (망원동 인기 카페)
   - 이미지: 4개 (최대치)
   - 관련 Cheer: 100개

## 예상 소요 시간

```
init.sql (최초 1회):           ~5초
Step 1 (Member 50K):          ~3-5분
Step 2 (Store 10K):           ~5분
Step 3 (Cheer 120K):          ~3-5분 (최적화됨)
Step 4 (CheerImage 180K):     ~10-15분
Step 5 (CheerTag 300K):       ~15-20분
Step 6 (Story 30K):           ~3-5분
Step 7 (StoryImage 60K):      ~10-15분
Step 8 (Hotplace):            ~1분
Step 9 (Viral Story):         ~1분
인덱스 최적화:                 ~5-10분

총 예상 시간: 약 60-90분 (데이터 규모 증가로 시간 증가)
```

**성능 향상 팁:**
- MySQL 설정 최적화 (`innodb_buffer_pool_size`, `innodb_log_file_size`)
- SSD 사용
- Foreign Key 체크 비활성화 (스크립트에 포함됨)

## 데이터 백업 및 복원

### 백업

```bash
# Docker 컨테이너 내에서 mysqldump 실행
docker exec eatda-mysql mysqldump -u root -prootpassword eatda > load-test-data-backup-$(date +%Y%m%d-%H%M%S).sql

# 또는 호스트에서 직접 실행 (포트 3308 사용)
mysqldump -h 127.0.0.1 -P 3308 -u root -prootpassword eatda > load-test-data-backup.sql
```

### 복원

```bash
# Docker 컨테이너로 복원
docker exec -i eatda-mysql mysql -u root -prootpassword eatda < load-test-data-backup-20260626-120000.sql

# 또는 호스트에서 직접 실행 (포트 3308 사용)
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < load-test-data-backup-20260626-120000.sql
```

## 데이터 검증

### 개수 확인

```sql
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
```

### 분포 확인

```sql
-- Store 지역별 분포
SELECT district, COUNT(*) AS store_count
FROM store
GROUP BY district
ORDER BY store_count DESC;

-- Cheer 상위 10개 인기 가게
SELECT
    s.name,
    s.district,
    COUNT(c.id) AS cheer_count
FROM store s
LEFT JOIN cheer c ON s.id = c.store_id
GROUP BY s.id, s.name, s.district
ORDER BY cheer_count DESC
LIMIT 10;

-- Story 상위 10명 파워 유저
SELECT
    m.nickname,
    COUNT(s.id) AS story_count
FROM member m
LEFT JOIN story s ON m.id = s.member_id
GROUP BY m.id, m.nickname
ORDER BY story_count DESC
LIMIT 10;

-- Tag 사용 빈도
SELECT
    name,
    COUNT(*) AS count,
    CONCAT(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM cheer_tag), 1), '%') AS percentage
FROM cheer_tag
GROUP BY name
ORDER BY count DESC
LIMIT 10;
```

### FK 무결성 확인

```sql
-- Cheer → Store
SELECT COUNT(*) AS invalid_cheer_store
FROM cheer
WHERE store_id NOT IN (SELECT id FROM store);

-- Cheer → Member
SELECT COUNT(*) AS invalid_cheer_member
FROM cheer
WHERE member_id NOT IN (SELECT id FROM member);

-- Story → Member
SELECT COUNT(*) AS invalid_story_member
FROM story
WHERE member_id NOT IN (SELECT id FROM member);

-- CheerImage → Cheer
SELECT COUNT(*) AS invalid_cheer_image
FROM cheer_image
WHERE cheer_id NOT IN (SELECT id FROM cheer);

-- StoryImage → Story
SELECT COUNT(*) AS invalid_story_image
FROM story_image
WHERE story_id NOT IN (SELECT id FROM story);

-- CheerTag → Cheer
SELECT COUNT(*) AS invalid_cheer_tag
FROM cheer_tag
WHERE cheer_id NOT IN (SELECT id FROM cheer);
```

모든 결과가 `0`이면 FK 무결성이 유지되고 있습니다.

## 데이터 초기화

테스트 데이터를 완전히 삭제하고 초기화하려면:

```bash
# 1. MySQL 접속 (포트 3308, 비밀번호 rootpassword)
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda

# 2. 모든 테이블 TRUNCATE (FK 체크 비활성화)
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE cheer_tag;
TRUNCATE TABLE cheer_image;
TRUNCATE TABLE story_image;
TRUNCATE TABLE cheer;
TRUNCATE TABLE story;
TRUNCATE TABLE store;
TRUNCATE TABLE member;
SET FOREIGN_KEY_CHECKS = 1;

# 3. 다시 데이터 생성
exit
./00_run_all.sh
```

## 문제 해결

### 1. "Too many connections" 에러

```sql
-- 최대 연결 수 확인
SHOW VARIABLES LIKE 'max_connections';

-- 최대 연결 수 증가 (MySQL 재시작 필요)
-- my.cnf 또는 my.ini에 추가:
[mysqld]
max_connections = 500
```

### 2. 실행 시간이 너무 오래 걸림

```sql
-- innodb_buffer_pool_size 확인 (RAM의 50-70% 권장)
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';

-- my.cnf 또는 my.ini에 추가:
[mysqld]
innodb_buffer_pool_size = 2G
innodb_log_file_size = 512M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
```

### 3. 스크립트 중간에 실패

```bash
# 실패한 단계부터 개별 실행
# 예: Step 4에서 실패했다면
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 04_generate_cheer_images.sql
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < 05_generate_cheer_tags.sql
# ...
```

## 참고 자료

- [MySQL 대량 데이터 삽입 최적화](https://dev.mysql.com/doc/refman/8.0/en/optimizing-innodb-bulk-data-loading.html)
- [mysqldump 사용법](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html)
- [Docker MySQL 설정](https://hub.docker.com/_/mysql)
- [로드 테스트 전제 조건 문서](../docs/00_load_test_prerequisites.md)

## 문의

데이터 생성 관련 문의사항은 프로젝트 리드에게 연락하세요.
