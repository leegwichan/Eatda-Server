# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

- **Build:** `./gradlew build`
- **Run all tests:** `./gradlew test`
- **Run single test class:** `./gradlew test --tests "eatda.service.store.StoreServiceTest"`
- **Run single test method:** `./gradlew test --tests "eatda.service.store.StoreServiceTest.testMethodName"`
- **Check (tests + static analysis):** `./gradlew check`
- **Coverage report:** `./gradlew jacocoTestReport` (output: `build/reports/jacoco/test/html/index.html`)

## Architecture

Spring Boot 3.5.0 / Java 21 / Gradle. Root package: `eatda` (group: `net.eatda`).

### Layered Architecture

```
Controller (+ Request/Response DTOs) → Service → Persistence → Repository → Domain (JPA Entities)
```

- **Controller** (`eatda.controller.{domain}`): Domain-specific REST endpoints. Always returns `ResponseEntity<T>`. Uses `@Validated` for bean validation.
- **Controller (Web)** (`eatda.controller.web`): Cross-cutting web infrastructure — JWT (`jwt` subpackage), authentication (`auth` subpackage), image presigned URLs (`image` subpackage).
- **Service** (`eatda.service.{domain}`): Business logic. `@Transactional(readOnly = true)` for reads, `@Transactional` for writes. Image-related service in `eatda.service.image`.
- **Persistence** (`eatda.persistence.{domain}`): Complex query logic with custom result objects (e.g., `StorePreviewResult`, `LoginResult`). Sits between Service and Repository when queries go beyond simple JPA methods.
- **Repository** (`eatda.repository.{domain}`): JPA repository interfaces extending `JpaRepository`.
- **Domain** (`eatda.domain.{domain}`): JPA entities with value objects. Base classes: `AuditingEntity` (provides `createdAt`), `BaseImageEntity` (provides `imageKey`, `orderIndex`, `contentType`, `fileSize`, `createdAt`).

### Other Key Packages

- **`eatda.client`**: External API clients — `oauth` (Kakao login), `map` (Kakao Maps), `file` (S3 presigned URLs).
- **`eatda.exception`**: `BusinessException` + `BusinessErrorCode` enum. Error codes are domain-prefixed (MEM, STO, CHE, AUTH, IMG, STY, MAP). `GlobalExceptionHandler` handles all exceptions.

### Domain Model

- **Member** (OAuth-based) — identified via Kakao login
- **Store** — fetched from Kakao Maps, with address/coordinates/district
- **Cheer** — member appreciation for a store, with images (via `CheerImage` extending `BaseImageEntity`) and tags
- **Story** — member experience about a store, with images (via `StoryImage` extending `BaseImageEntity`)
- **Image entities** — all extend `BaseImageEntity` (CheerImage, StoryImage), storing S3 keys and metadata

## Code Conventions

- **Lombok everywhere**: `@Getter`, `@RequiredArgsConstructor`, `@Builder`. Constructor injection only — no `@Autowired` on fields.
- **DTOs**: Request/Response records live in controller packages. Never expose entities in API responses.
- **Error throwing**: `throw new BusinessException(BusinessErrorCode.STORE_NOT_FOUND);`

## Test Setup

- **Integration tests** using `@SpringBootTest(webEnvironment = RANDOM_PORT)` + RestAssured.
- **Base class**: `BaseControllerTest` provides test fixtures, mocked external clients (`OauthClient`, `MapClient`, `FileClient`), and JWT helpers (`accessToken()`, `refreshToken()`).
- **Database cleanup**: `@ExtendWith(DatabaseCleaner.class)` wipes DB between tests.
- **Test data**: Generator classes in `eatda.fixture` (e.g., `MemberGenerator`, `StoreGenerator`) create test entities via repositories.
- **DB**: H2 in-memory for tests, MySQL for production. Flyway manages migrations.

## API Documentation

SpringDoc OpenAPI + Spring REST Docs. `./gradlew openapi3` generates the spec. Swagger UI served from `src/main/resources/static/docs/`.

## Performance Testing

### Load Test Environment

Full-stack load testing infrastructure in `load-test/` directory using Docker Compose:

- **Start test environment:** `./load-test/scripts/start-test-env.sh` (builds app + starts all services)
- **Stop test environment:** `./load-test/scripts/stop-test-env.sh`
- **Run K6 test:** `docker-compose -f load-test/docker-compose.load-test.yml run --rm k6 run /scripts/test-scenario.js`

### Infrastructure Components

- **MySQL 8.0** (max_connections=1000)
- **LocalStack** (S3 mock)
- **Spring Boot App** (JVM: Xms2g, Xmx2g)
- **Prometheus + Grafana** (metrics visualization at http://localhost:3000, admin/admin)
- **Pinpoint APM** (transaction tracing at http://localhost:8081)
- **K6** (load testing tool)

### Mock Data Scale

Auto-generated on first startup (~5-10 minutes):
- Members: 10,000
- Stores: 5,000
- Cheers: 50,000 (avg 10 per store)
- Stories: 30,000 (avg 3 per member)
- Images: ~35,000-40,000

Adjust scale by editing `load-test/scripts/generate-mock-data.sql` variables (`@member_count`, `@store_count`, etc.).

### Test Scenarios

Located in `load-test/docs/`:
- **01_scenario_baseline.md** — Normal operation (~4 req/s baseline)
- **02_scenario_hotplace.md** — Hotspot traffic concentration (single store traffic spike)
- **03_scenario_viral.md** — SNS viral traffic (20-40 req/s for 30-60 min)
- **04_scenario_write_heavy.md** — Write-heavy events (30-50 req/s during campaigns)
- **05_scenario_oauth_failure.md** — External API failure resilience (Kakao OAuth outage)
- **06_scenario_slow_query.md** — Slow query handling (connection pool exhaustion)

Traffic analysis baseline from `docs/traffic-screnario.md` models a niche vertical community (benchmark: Polle — 120K users, 30K MAU, 12K DAU).

### Load Test Profile

`application-load-test.yml` settings:
- HikariCP: `maximum-pool-size: 50`, `minimum-idle: 10`
- JPA batch: `default_batch_fetch_size: 100`, `batch_size: 100`
- LocalStack S3 with presigned URL substitution (internal/external URL routing)

### Quick Troubleshooting

- **Check logs:** `docker-compose -f load-test/docker-compose.load-test.yml logs -f app`
- **Verify mock data:** `docker-compose -f load-test/docker-compose.load-test.yml exec mysql mysql -ueatda -peatda123 -e "SELECT COUNT(*) FROM member"`
- **Full restart (delete data):** `docker-compose -f load-test/docker-compose.load-test.yml down -v`

Detailed guides: `load-test/README.md`, `load-test/LOAD_TEST_GUIDE.md`
