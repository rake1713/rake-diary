"""FastAPI-приложение: API под /api, веб-клиент (Flutter web) — на том же домене."""

# Без `from __future__ import annotations`: FastAPI читает аннотации маршрутов
# во время выполнения, а зависимости (Conn, CurrentDriver) объявлены внутри
# create_app — строковые аннотации он бы не разрешил и принял бы их за query-параметры.
import logging
import sqlite3
from collections.abc import Iterator
from contextlib import asynccontextmanager
from datetime import date, timedelta
from pathlib import Path
from typing import Annotated
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, FastAPI, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from diary import db
from diary.config import Settings
from diary.schemas import (
    DayListItem,
    DayOut,
    LoginIn,
    LoginOut,
    MeOut,
    SummaryOut,
    TripIn,
    TripOut,
)
from diary.security import (
    Driver,
    RateLimiter,
    authenticate,
    create_session,
    delete_session,
    resolve_session,
)
from diary.seed import seed
from diary.summary import summarize
from diary.timeutil import format_utc_offset
from diary.trips import SaveResult, Trip, day_totals, save_trip, trips_for_day

log = logging.getLogger("diary")

CSRF_HEADER = "x-requested-with"
CSRF_VALUE = "diary-web"
MOBILE_CLIENT_HEADER = "x-client"
UNSAFE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}

CSP = "; ".join(
    [
        "default-src 'self'",
        # Flutter web (CanvasKit) — WebAssembly; eval по-прежнему запрещён.
        "script-src 'self' 'wasm-unsafe-eval'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: blob:",
        "font-src 'self' data: https://fonts.gstatic.com",
        "connect-src 'self' https://fonts.gstatic.com",
        "worker-src 'self' blob:",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
    ]
)


def error(status: int, code: str, message: str, **extra: object) -> JSONResponse:
    return JSONResponse({"error": code, "message": message, **extra}, status_code=status)


def too_large() -> JSONResponse:
    return error(413, "payload_too_large", "Слишком большой запрос")


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, headers: dict[str, str] | None = None):
        self.status, self.code, self.message, self.headers = status, code, message, headers


# ---------- middleware ----------


class BodySizeLimit:
    """Ограничивает тело запроса, в том числе при chunked-передаче без Content-Length."""

    def __init__(self, app: ASGIApp, max_bytes: int) -> None:
        self.app, self.max_bytes = app, max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        for name, value in scope["headers"]:
            if name == b"content-length":
                try:
                    too_big = int(value) > self.max_bytes
                except ValueError:
                    too_big = True
                if too_big:
                    await too_large()(scope, receive, send)
                    return
        received = 0
        response_started = False
        rejected = False

        async def limited_receive() -> Message:
            # Превысили лимит — отвечаем 413 сами, а приложению сообщаем об обрыве
            # соединения: исключение отсюда FastAPI превратил бы в 400.
            nonlocal received, rejected
            if rejected:
                return {"type": "http.disconnect"}
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    rejected = True
                    if not response_started:
                        await too_large()(scope, receive, send)
                    return {"type": "http.disconnect"}
            return message

        async def guarded_send(message: Message) -> None:
            nonlocal response_started
            if rejected:
                return
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, guarded_send)
        except Exception:
            if not rejected:
                raise


class SecurityHeaders:
    def __init__(self, app: ASGIApp, hsts: bool) -> None:
        self.app, self.hsts = app, hsts

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        path: str = scope["path"]
        is_docs = path in {"/docs", "/redoc", "/openapi.json"} or path.startswith("/docs/")

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = [(k, v) for k, v in message.get("headers", []) if k.lower() != b"server"]
                headers += [
                    (b"x-content-type-options", b"nosniff"),
                    (b"x-frame-options", b"DENY"),
                    (b"referrer-policy", b"no-referrer"),
                    (b"cross-origin-opener-policy", b"same-origin"),
                    (b"cross-origin-resource-policy", b"same-origin"),
                    (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
                ]
                if not is_docs:
                    headers.append((b"content-security-policy", CSP.encode()))
                if path.startswith("/api/"):
                    headers.append((b"cache-control", b"no-store"))
                if self.hsts:
                    headers.append(
                        (b"strict-transport-security", b"max-age=31536000; includeSubDomains")
                    )
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, send_with_headers)


# ---------- приложение ----------


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    tz = settings.driver_utc_offset
    utc_offset = format_utc_offset(tz)
    cookie_name = "__Host-diary_session" if settings.cookie_secure else "diary_session"
    login_limiter = RateLimiter(settings.login_max_failures, settings.login_window)
    api_limiter = RateLimiter(settings.api_rate_per_minute, timedelta(minutes=1))

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        db.init_db(settings.db_path)
        with db.connection(settings.db_path) as conn:
            seed(conn, settings)
        yield

    app = FastAPI(
        title="Дневник смен водителя",
        version="1.0.0",
        lifespan=lifespan,
        # В проде документация API не публикуется — меньше поверхность атаки.
        docs_url=None if settings.is_prod else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_prod else "/openapi.json",
    )
    app.state.settings = settings
    app.state.login_limiter = login_limiter
    app.add_middleware(SecurityHeaders, hsts=settings.is_prod)
    app.add_middleware(BodySizeLimit, max_bytes=settings.max_body_bytes)

    # ---- обработка ошибок: без стектрейсов и без эха введённых данных ----

    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        resp = error(exc.status, exc.code, exc.message)
        for k, v in (exc.headers or {}).items():
            resp.headers[k] = v
        return resp

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        details = [
            {
                "field": ".".join(str(p) for p in e.get("loc", ()) if p != "body") or None,
                "message": str(e.get("ctx", {}).get("error", e.get("msg", "")))
                if e.get("type") == "value_error"
                else e.get("msg", ""),
            }
            for e in exc.errors()
        ]
        return error(422, "validation_error", "Данные не прошли проверку", details=details)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        codes = {404: "not_found", 405: "method_not_allowed"}
        return error(exc.status_code, codes.get(exc.status_code, "http_error"), str(exc.detail))

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception) -> JSONResponse:
        log.exception("Необработанная ошибка", exc_info=exc)
        return error(500, "internal_error", "Внутренняя ошибка сервера")

    # ---- зависимости ----

    def get_conn() -> Iterator[sqlite3.Connection]:
        with db.connection(settings.db_path) as conn:
            yield conn

    Conn = Annotated[sqlite3.Connection, Depends(get_conn)]

    def client_ip(request: Request) -> str:
        # За реверс-прокси настоящий IP подставляет uvicorn (--proxy-headers
        # с --forwarded-allow-ips), заголовкам от клиента напрямую не доверяем.
        return request.client.host if request.client else "unknown"

    def rate_limit(request: Request) -> None:
        if not api_limiter.hit(f"ip:{client_ip(request)}"):
            raise ApiError(429, "rate_limited", "Слишком много запросов", {"Retry-After": "60"})

    def check_csrf(request: Request) -> None:
        """Для cookie-сессии: изменяющие запросы обязаны нести свой заголовок
        (чужой сайт не может его поставить без CORS, а CORS мы не разрешаем)
        и, если браузер прислал Origin, он должен совпадать с нашим хостом."""
        if request.method not in UNSAFE_METHODS:
            return
        if request.headers.get(CSRF_HEADER) != CSRF_VALUE:
            raise ApiError(403, "csrf_failed", "Запрос отклонён (CSRF)")
        origin = request.headers.get("origin")
        if origin and urlsplit(origin).netloc != request.headers.get("host"):
            raise ApiError(403, "csrf_failed", "Запрос отклонён (CSRF)")

    def unauthorized() -> ApiError:
        return ApiError(401, "unauthorized", "Требуется вход", {"WWW-Authenticate": "Bearer"})

    def session_token(request: Request) -> tuple[str | None, bool]:
        """(токен, пришёл_из_cookie)."""
        auth = request.headers.get("authorization")
        if auth:
            scheme, _, token = auth.partition(" ")
            if scheme.lower() != "bearer" or not token:
                raise unauthorized()
            return token.strip(), False
        return request.cookies.get(cookie_name), True

    def current_driver(request: Request, conn: Conn) -> Driver:
        token, from_cookie = session_token(request)
        if not token:
            raise unauthorized()
        if from_cookie:
            check_csrf(request)
        driver = resolve_session(conn, token)
        if driver is None:
            raise ApiError(401, "unauthorized", "Сессия недействительна или истекла")
        return driver

    CurrentDriver = Annotated[Driver, Depends(current_driver)]

    def me_out(d: Driver) -> MeOut:
        return MeOut(login=d.login, name=d.name, utc_offset=utc_offset)

    # ---- маршруты ----

    api = APIRouter(prefix="/api", dependencies=[Depends(rate_limit)])

    @api.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @api.post("/auth/login")
    def login(body: LoginIn, request: Request, response: Response, conn: Conn) -> LoginOut:
        is_mobile = request.headers.get(MOBILE_CLIENT_HEADER) == "mobile"
        if not is_mobile:
            check_csrf(request)
        keys = (f"ip:{client_ip(request)}", f"login:{body.login.lower()}")
        if any(login_limiter.is_blocked(k) for k in keys):
            raise ApiError(
                429,
                "too_many_attempts",
                "Слишком много неудачных попыток входа, попробуйте позже",
                {"Retry-After": str(int(settings.login_window.total_seconds()))},
            )
        driver = authenticate(conn, body.login, body.password)
        if driver is None:
            for k in keys:
                login_limiter.hit(k)
            # Одинаковый ответ для «нет такого логина» и «неверный пароль».
            raise ApiError(401, "invalid_credentials", "Неверный логин или пароль")
        login_limiter.reset(f"login:{body.login.lower()}")
        token = create_session(conn, driver.id, settings.session_ttl)
        ttl = int(settings.session_ttl.total_seconds())
        if is_mobile:
            return LoginOut(driver=me_out(driver), token=token, expires_in=ttl)
        response.set_cookie(
            cookie_name,
            token,
            max_age=ttl,
            path="/",
            secure=settings.cookie_secure,
            httponly=True,
            samesite="strict",
        )
        return LoginOut(driver=me_out(driver), expires_in=ttl)

    @api.post("/auth/logout", status_code=204)
    def logout(request: Request, response: Response, conn: Conn) -> Response:
        token, from_cookie = session_token(request)
        if from_cookie:
            check_csrf(request)
        if token:
            delete_session(conn, token)
        response.status_code = 204
        response.delete_cookie(
            cookie_name, path="/", secure=settings.cookie_secure, httponly=True, samesite="strict"
        )
        return response

    @api.get("/auth/me")
    def me(driver: CurrentDriver) -> MeOut:
        return me_out(driver)

    def parse_day(raw: str) -> date:
        try:
            parsed = date.fromisoformat(raw)
            if len(raw) != 10 or not 2000 <= parsed.year <= 2100:
                raise ValueError
        except ValueError:
            raise ApiError(422, "invalid_date", "Дата должна быть в формате ГГГГ-ММ-ДД") from None
        return parsed

    @api.get("/days")
    def list_days(
        driver: CurrentDriver,
        conn: Conn,
        start: Annotated[str | None, Query(alias="from")] = None,
        end: Annotated[str | None, Query(alias="to")] = None,
    ) -> list[DayListItem]:
        """Дни с поездками и заработок «на руки». С `from`/`to` — за период (до 93 дней)."""
        if (start is None) != (end is None):
            raise ApiError(422, "invalid_range", "Нужно указать оба параметра: from и to")
        lo = hi = None
        if start is not None and end is not None:
            lo, hi = parse_day(start), parse_day(end)
            if lo > hi or (hi - lo).days > 92:
                raise ApiError(422, "invalid_range", "Период должен быть не длиннее 93 дней")
        return [
            DayListItem(date=t.date, trips=t.trips, net=t.net)
            for t in day_totals(conn, driver.id, tz, lo, hi)
        ]

    @api.get("/days/{day}")
    def get_day(day: str, driver: CurrentDriver, conn: Conn) -> DayOut:
        parsed = parse_day(day)
        trips = trips_for_day(conn, driver.id, parsed, tz)
        s = summarize(trips)
        return DayOut(
            date=parsed.isoformat(),
            utc_offset=utc_offset,
            summary=SummaryOut(**s.__dict__),
            trips=[t.to_out(tz) for t in trips],
        )

    @api.post(
        "/trips",
        status_code=201,
        responses={200: {"description": "Повторная отправка той же поездки"}, 409: {}},
    )
    def add_trip(body: TripIn, driver: CurrentDriver, conn: Conn, response: Response) -> TripOut:
        result, trip = save_trip(conn, driver.id, Trip.from_input(body))
        if result is SaveResult.CONFLICT:
            raise ApiError(
                409, "trip_conflict", f"Поездка {body.id} уже сохранена с другими данными"
            )
        response.status_code = 201 if result is SaveResult.CREATED else 200
        return trip.to_out(tz)

    app.include_router(api)

    @app.api_route("/api/{rest:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
    def api_not_found(rest: str) -> JSONResponse:
        return error(404, "not_found", "Нет такого метода API")

    _mount_web(app, settings.web_dir)
    return app


NO_CACHE = {"cache-control": "no-cache"}
RESERVED_PATHS = {"docs", "redoc", "openapi.json"}


def _mount_web(app: FastAPI, web_dir: Path | None) -> None:
    """Раздача собранного Flutter web. Пути проверяются, выйти за папку нельзя."""
    if web_dir is None or not (web_dir / "index.html").is_file():
        log.info("Веб-клиент не собран (%s) — раздаю только API", web_dir)
        return
    root = web_dir.resolve()

    @app.get("/{path:path}", include_in_schema=False)
    def web(path: str) -> Response:
        # Служебные пути не подменяем страницей приложения: если документация
        # API выключена (прод), они должны честно отвечать 404.
        if path.strip("/") in RESERVED_PATHS:
            return error(404, "not_found", "Не найдено")
        candidate = (root / path).resolve()
        if path and candidate.is_relative_to(root) and candidate.is_file():
            # У Flutter web в именах файлов нет хеша (main.dart.js остаётся
            # main.dart.js), поэтому браузер перепроверяет каждый файл по ETag.
            # Без этого он может долго показывать старую сборку.
            return FileResponse(candidate, headers=NO_CACHE)
        # Нет такого файла (favicon.ico, main.js…) — честный 404. Иначе браузер
        # получил бы HTML вместо картинки или скрипта. Страницу приложения
        # отдаём только для «маршрутов» без расширения.
        if "." in path.rsplit("/", 1)[-1]:
            return error(404, "not_found", "Не найдено")
        return FileResponse(root / "index.html", headers=NO_CACHE)
