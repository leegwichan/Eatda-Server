# 로드 테스트 데이터 생성 전략

## 문서 개요

본 문서는 Eatda 서버의 로드 테스트를 위한 테스트 데이터 생성 전략을 정리합니다.

**작성일**: 2026-06-26  
**기준 문서**: `00_load_test_prerequisites.md`  
**목표**: 최소 10,000건 이상의 현실적인 테스트 데이터 구성

---

## 1. 현재 데이터 현황 vs 목표

### 현재 (init.sql)

```
Member:  80명
Store:   110개
Cheer:   125개
Story:   24개
Image:   83개 (CheerImage + StoryImage)
Tag:     313개 (CheerTag)
```

### 목표 (문서 기준)

```
최소 데이터:      10,000건 이상
시뮬레이션 규모:  DAU 12,000명
                 MAU 30,000명
                 누적 가입자 120,000명
```

---

## 2. 권장 데이터 구성

### 2.1 Member (회원) - 15,000~20,000명

```yaml
총 회원 수: 15,000~20,000명

분류:
  활성 사용자 (최근 3개월 내 가입): 12,000명 (80%)
  휴면 사용자 (3개월 이상 경과):    3,000~8,000명 (20%)

OAuth 분산:
  - 대부분 카카오 social_id 보유
  - 일부는 전화번호/마케팅 동의 NULL (신규 가입 시뮬레이션용)
  - social_id 범위: 4000000000 ~ 4020000000

생성 날짜 분포:
  - 2025-04-01 ~ 2026-06-26 (최근 3개월)
  - 2024-01-01 ~ 2025-03-31 (휴면)
```

**이유:**
- DAU 12,000명 시뮬레이션 가능
- OAuth 로그인 시나리오 대응
- 신규 가입 vs 기존 회원 구분 가능

### 2.2 Store (가게) - 5,000~10,000개

```yaml
총 가게 수: 5,000~10,000개

지역 분포 (서울 25개 구):
  핫플레이스 지역 (60%):
    - 강남구: 15% (750~1,500개)
    - 서초구: 15%
    - 송파구: 15%
    - 마포구: 15%
  
  기타 21개 구 (40%):
    - 각 구당 약 2% (100~200개)

카테고리 분포:
  - KOREAN:   40% (2,000~4,000개)
  - WESTERN:  20% (1,000~2,000개)
  - JAPANESE: 20%
  - CHINESE:  10%
  - OTHER:    10%

Kakao 데이터:
  - kakao_id: 실제 또는 더미 ID (1000000000 ~ 2000000000 범위)
  - 주소, 좌표, 전화번호 등 필수 필드 채움
```

**핫플레이스 시나리오 대비:**
- 특정 `store_id` 3~5개는 Cheer/Story 집중 (인기 맛집)
- 나머지는 롱테일 분포 (일부만 응원/스토리 있음)

### 2.3 Cheer (응원) - 30,000~50,000개

```yaml
총 응원 수: 30,000~50,000개
평균: Store당 5~10개

분포 (파레토 법칙):
  상위 5% 인기 맛집:    100~300개/가게
  중간 30% 준인기 맛집: 10~50개/가게
  하위 65% 롱테일:      0~5개/가게

관계 데이터:
  - 각 Cheer마다 CheerImage: 0~3개 (평균 1.5개)
  - 각 Cheer마다 CheerTag:   2~5개 (평균 3개)
  - description: 10~500자 범위

N+1 쿼리 테스트 대비:
  - Store → Cheer → CheerImage lazy 로드 검증
  - batch_fetch_size=30 실효성 검증
```

**시나리오 2 (핫플레이스) 대비:**
- `store_id = 특정값` 한 곳에 Cheer 300개 집중
- 프론트엔드가 상세 진입 시 4개 API 동시 호출 대응

### 2.4 Story (스토리) - 5,000~10,000개

```yaml
총 스토리 수: 5,000~10,000개
평균: 활성 사용자의 50%가 1개 이상 작성

분포:
  파워 유저 (5%):      10~20개/회원
  중간 활동 (20%):     2~5개/회원
  일반 사용자 (75%):   0~1개/회원

관계 데이터:
  - 각 Story마다 StoryImage: 1~4개 (평균 2개)
  - description: 10~1000자 범위
  - store 정보는 Kakao API 형식 그대로 저장
```

**시나리오 3 (SNS 바이럴) 대비:**
- 특정 `story_id` 1개는 매우 인기 (조회 집중 대상)
- GET /api/stories?size=20 반복 DB 히트 검증

### 2.5 Image 데이터 - 80,000~150,000개

```yaml
총 이미지 수: 80,000~150,000개

분류:
  CheerImage: 45,000~75,000개 (평균 Cheer당 1.5개)
  StoryImage: 10,000~20,000개 (평균 Story당 2개)

필드 값:
  - image_key: "cheer/{cheer_id}/{UUID}.jpeg" 또는 "story/{story_id}/{UUID}.jpeg"
  - content_type: 90% image/jpeg, 10% image/png
  - file_size: 500KB~5MB 범위 (랜덤)
  - order_index: 0부터 순차 (같은 Cheer/Story 내에서)
  - created_at: 부모 엔티티(Cheer/Story)와 동일

S3 저장소:
  - LocalStack 환경에서는 실제 파일 없이 메타데이터만 존재
  - Presigned URL 테스트용으로 더미 이미지 1개 사용 가능
```

### 2.6 Tag 데이터 - 100,000~150,000개

```yaml
총 태그 수: 100,000~150,000개
평균: Cheer당 2~3개

CheerTag 분포:
  - GOOD_FOR_DRINKING:        25% (가장 많음)
  - NEAR_SUBWAY:              20%
  - GOOD_FOR_DATING:          15%
  - INSTAGRAMMABLE:           10%
  - ENERGETIC:                 8%
  - GROUP_RESERVATION:         7%
  - MANY_NEARBY_ATTRACTIONS:   5%
  - 기타 태그:                10%

생성 전략:
  - 각 Cheer마다 랜덤하게 2~5개 태그 선택
  - 중복 없음 (같은 Cheer 내에서 동일 태그 불가)
```

---

## 3. 데이터 생성 방법

### 방법 A: SQL 기반 생성 (빠름, 단순)

```sql
-- 예시: Member 10,000명 생성
INSERT INTO member (email, social_id, nickname, created_at)
SELECT 
  CONCAT('user', n, '@test.com'),
  CAST(4000000000 + n AS CHAR),
  CONCAT('유저', n),
  DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND() * 180) DAY)
FROM (
  SELECT @row := @row + 1 AS n
  FROM information_schema.columns c1, information_schema.columns c2
  CROSS JOIN (SELECT @row := 80) r
  LIMIT 10000
) nums;
```

**장점:**
- 빠른 속도 (10,000건 삽입 수 초 내)
- DB에 직접 삽입 가능

**단점:**
- 복잡한 관계 (Cheer ↔ Member ↔ Store) 생성 어려움
- FK 참조 무결성 수동 관리 필요
- UUID 생성, 날짜 랜덤화 복잡

### 방법 B: Java 코드 기반 생성 (권장)

```java
// eatda.fixture.LoadTestDataGenerator 예시
@Component
@RequiredArgsConstructor
public class LoadTestDataGenerator {
    private final MemberRepository memberRepository;
    private final StoreRepository storeRepository;
    private final CheerRepository cheerRepository;
    private final StoryRepository storyRepository;
    
    private final Random random = new Random();
    
    public void generateMembers(int count) {
        List<Member> members = IntStream.range(0, count)
            .mapToObj(i -> Member.builder()
                .email("loadtest" + i + "@test.com")
                .socialId(String.valueOf(4000000000L + i))
                .nickname("테스트유저" + i)
                .phoneNumber(i % 3 == 0 ? null : "010" + String.format("%08d", i))
                .optInMarketing(random.nextBoolean())
                .build())
            .toList();
        
        // 배치 삽입 (1000건씩)
        Lists.partition(members, 1000).forEach(memberRepository::saveAll);
    }
    
    public void generateCheers(int count) {
        List<Member> members = memberRepository.findAll();
        List<Store> stores = storeRepository.findAll();
        
        // 롱테일 분포 구현: 상위 5% 가게에 80% Cheer 집중
        List<Store> topStores = stores.subList(0, (int)(stores.size() * 0.05));
        List<Store> normalStores = stores.subList((int)(stores.size() * 0.05), stores.size());
        
        List<Cheer> cheers = IntStream.range(0, count)
            .mapToObj(i -> {
                Member randomMember = members.get(random.nextInt(members.size()));
                Store randomStore = (random.nextDouble() < 0.8) 
                    ? topStores.get(random.nextInt(topStores.size()))
                    : normalStores.get(random.nextInt(normalStores.size()));
                
                return Cheer.builder()
                    .member(randomMember)
                    .store(randomStore)
                    .description(generateRandomDescription())
                    .isAdmin(false)
                    .build();
            })
            .toList();
        
        Lists.partition(cheers, 1000).forEach(cheerRepository::saveAll);
    }
    
    public void generateCheerImages(int averagePerCheer) {
        List<Cheer> cheers = cheerRepository.findAll();
        
        List<CheerImage> images = cheers.stream()
            .flatMap(cheer -> {
                int imageCount = random.nextInt(4); // 0~3개
                return IntStream.range(0, imageCount)
                    .mapToObj(idx -> CheerImage.builder()
                        .cheer(cheer)
                        .imageKey("cheer/" + cheer.getId() + "/" + UUID.randomUUID() + ".jpeg")
                        .orderIndex(idx)
                        .contentType("image/jpeg")
                        .fileSize((long)(500_000 + random.nextInt(4_500_000)))
                        .build());
            })
            .toList();
        
        Lists.partition(images, 1000).forEach(cheerImageRepository::saveAll);
    }
    
    private String generateRandomDescription() {
        String[] templates = {
            "정말 맛있는 집이에요! 강추합니다.",
            "분위기도 좋고 음식도 훌륭해요.",
            "가격 대비 가성비 최고입니다!",
            "재방문 의사 100% 입니다 ㅎㅎ",
            "주변에 여기 아는 사람이 별로 없어서 웨이팅 없이 편하게 다녀요~"
        };
        return templates[random.nextInt(templates.length)];
    }
}
```

**실행 방법:**

1. **CommandLineRunner로 실행**

```java
@SpringBootApplication
public class EatdaApplication {
    public static void main(String[] args) {
        SpringApplication.run(EatdaApplication.class, args);
    }
    
    @Bean
    @Profile("load-test")
    CommandLineRunner initLoadTestData(LoadTestDataGenerator generator) {
        return args -> {
            if (Arrays.asList(args).contains("--generate-data=true")) {
                System.out.println("=== 로드 테스트 데이터 생성 시작 ===");
                generator.generateMembers(15000);
                generator.generateStores(10000);
                generator.generateCheers(50000);
                generator.generateStories(10000);
                generator.generateCheerImages(1.5);
                generator.generateStoryImages(2.0);
                generator.generateCheerTags(3);
                System.out.println("=== 로드 테스트 데이터 생성 완료 ===");
            }
        };
    }
}
```

2. **실행 명령어**

```bash
./gradlew bootRun --args='--spring.profiles.active=load-test --generate-data=true'
```

**장점:**
- JPA 엔티티 사용으로 안전한 관계 생성
- FK 참조 무결성 자동 관리
- UUID, 날짜 생성 용이
- 롱테일 분포 등 복잡한 로직 구현 가능

**단점:**
- SQL보다 느림 (하지만 배치 삽입으로 최적화 가능)
- 메모리 사용량 높음 (배치 크기 조절 필요)

---

## 4. 시나리오별 특수 데이터 요구사항

### 시나리오 1: 평상시 운영 (Baseline)

```yaml
특별 요구사항: 없음
일반적인 데이터 분포로 충분
```

### 시나리오 2: 핫플레이스 집중 트래픽

```yaml
특수 데이터:
  - store_id = 999 (성수동 신상 맛집)
  - Cheer: 300개
  - Story: 50개
  - CheerImage: 450개 (Cheer당 평균 1.5개)
  - StoryImage: 100개 (Story당 평균 2개)

목적:
  - N+1 쿼리 폭발 여부 검증
  - batch_fetch_size=30 실효성 검증
```

### 시나리오 3: SNS 바이럴 트래픽

```yaml
특수 데이터:
  - story_id = 777 (바이럴 리뷰)
  - 해당 리뷰의 store_id도 인기 가게로 설정
  - StoryImage: 4개 (최대치)

목적:
  - GET /api/stories?size=20 반복 DB 히트 검증
  - 캐싱 부재로 인한 성능 저하 확인
```

### 시나리오 4: 쓰기 트래픽 집중

```yaml
특수 데이터:
  - 신규 Member 1,000명 준비 (social_id만 있고 nickname NULL)
  - OAuth 로그인 시 추가 정보 입력용

목적:
  - POST /api/stories (리뷰 등록)
  - POST /api/image/presigned-url (S3 업로드 URL 발급)
  - POST /api/cheer (응원 등록)
  - DB 커넥션 풀 고갈 검증
```

### 시나리오 5: OAuth 장애

```yaml
특수 데이터:
  - 신규 가입 필요한 Member 미리 준비
  - social_id 없는 더미 데이터

목적:
  - OAuth 타임아웃 시 스레드 풀 고갈 검증
  - 다른 정상 API 요청도 지연 발생하는지 확인
```

### 시나리오 6: DB 슬로우 쿼리

```yaml
특수 데이터:
  - 특정 district (예: 성수동)에 Store 5,000개 집중
  - 인덱스 없는 필터링 대상 데이터

목적:
  - GET /api/stores?district=성수동&sort=latest&size=50
  - Full Table Scan 유도
  - 커넥션 풀 고갈 검증
```

---

## 5. 데이터 생성 실행 계획

### Phase 1: 기본 데이터 생성

```bash
# 1. 기존 init.sql 실행 (80명 회원 + 110개 가게)
docker-compose -f docker-compose.load-test.yml up -d mysql
mysql -h 127.0.0.1 -P 3308 -u root -prootpassword eatda < load-test/mysql/init.sql

# 2. Java Generator로 추가 데이터 생성
./gradlew bootRun --args='--spring.profiles.active=load-test --generate-data=true'
```

**예상 소요 시간:**
- Member 15,000명: ~2분
- Store 10,000개: ~5분
- Cheer 50,000개: ~10분
- Story 10,000개: ~2분
- Image 150,000개: ~15분
- Tag 150,000개: ~10분
- **총합: ~44분**

### Phase 2: 특수 시나리오 데이터 생성

```bash
# 핫플레이스 집중 데이터
./gradlew bootRun --args='--spring.profiles.active=load-test --generate-hotplace-data=true'

# 바이럴 스토리 데이터
./gradlew bootRun --args='--spring.profiles.active=load-test --generate-viral-story=true'
```

### Phase 3: 데이터 검증

```sql
-- 데이터 개수 확인
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

-- 분포 확인
SELECT district, COUNT(*) AS store_count
FROM store
GROUP BY district
ORDER BY store_count DESC;

-- FK 무결성 확인
SELECT COUNT(*) FROM cheer WHERE store_id NOT IN (SELECT id FROM store);
```

---

## 6. 성능 최적화 팁

### 6.1 배치 삽입

```yaml
# application-load-test.yml
spring:
  jpa:
    properties:
      hibernate:
        jdbc:
          batch_size: 1000
        order_inserts: true
        order_updates: true
```

### 6.2 외래 키 체크 임시 비활성화 (MySQL)

```sql
-- 데이터 삽입 전
SET FOREIGN_KEY_CHECKS = 0;

-- 데이터 삽입...

-- 데이터 삽입 후
SET FOREIGN_KEY_CHECKS = 1;
```

### 6.3 인덱스 재생성

```sql
-- 대량 삽입 후 인덱스 최적화
OPTIMIZE TABLE member;
OPTIMIZE TABLE store;
OPTIMIZE TABLE cheer;
OPTIMIZE TABLE story;
```

---

## 7. 데이터 백업 및 복원

### 백업

```bash
# 생성한 테스트 데이터 백업
docker exec eatda-mysql mysqldump -u root -ppassword eatda > load-test-data-backup.sql
```

### 복원

```bash
# 백업한 데이터 복원
docker exec -i eatda-mysql mysql -u root -ppassword eatda < load-test-data-backup.sql
```

---

## 8. 참고 자료

- [MySQL 대량 데이터 삽입 최적화](https://dev.mysql.com/doc/refman/8.0/en/optimizing-innodb-bulk-data-loading.html)
- [JPA 배치 삽입 가이드](https://vladmihalcea.com/jpa-hibernate-batch-insert-update/)
- [Spring Boot 테스트 데이터 생성](https://spring.io/guides/gs/accessing-data-jpa/)

---

## 문서 이력

| 버전 | 날짜 | 작성자 | 변경 내역 |
|------|------|--------|----------|
| 1.0 | 2026-06-26 | System | 초기 작성 |
