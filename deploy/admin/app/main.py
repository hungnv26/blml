"""BLML admin console.

Phase 0 (auth, shell, audit), Phase 1 (dashboard), Phase 2 (people).

Reads come from Postgres; writes that change chat state go through the Tinode
API as root. Nothing in here reads message bodies — that is the product's
stated privacy position and it is enforced by simply never selecting the
column.
"""
from __future__ import annotations

import os
from pathlib import Path

from fastapi import Depends, FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import audit, auth, charts, db, tinode
from .security import hash_password  # noqa: F401  (re-exported for ops use)

BASE = Path(__file__).parent
app = FastAPI(title="BLML admin", docs_url=None, redoc_url=None,
              openapi_url=None)
app.mount("/static", StaticFiles(directory=BASE / "static"), name="static")
templates = Jinja2Templates(directory=BASE / "templates")

# Set only when the console is served over TLS, which is the intended
# deployment. Off for local development, or the cookie never comes back.
SECURE_COOKIES = os.environ.get("ADMIN_SECURE_COOKIES", "true").lower() == "true"


@app.on_event("startup")
def _startup() -> None:
    db.init_schema()
    auth.ensure_operator()
    auth.sweep_sessions()


def client_ip(request: Request) -> str:
    """Behind Caddy, so trust the proxy's header and fall back to the peer."""
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "?"


def current_session(request: Request) -> dict:
    session = auth.session_for(request.cookies.get(auth.COOKIE_NAME))
    if not session:
        raise HTTPException(status_code=303, headers={"Location": "/login"})
    return session


@app.exception_handler(HTTPException)
async def _redirect_unauthenticated(request: Request, exc: HTTPException):
    if exc.status_code == 303 and "Location" in (exc.headers or {}):
        return RedirectResponse(exc.headers["Location"], status_code=303)
    return HTMLResponse(f"<h1>{exc.status_code}</h1><p>{exc.detail}</p>",
                        status_code=exc.status_code)


def render(request: Request, name: str, **ctx) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request, name=name,
        context={"nav": request.url.path, **ctx})


# ── Auth ─────────────────────────────────────────────────────────────────────

@app.get("/login", response_class=HTMLResponse)
def login_form(request: Request):
    op = auth.operator()
    return render(request, "login.html", error=None,
                  totp_required=bool(op and op["totp_enrolled"]))


@app.post("/login")
def login(request: Request, username: str = Form(...),
          password: str = Form(...), totp: str = Form("")):
    ip = client_ip(request)
    ok, message = auth.check_credentials(username, password, totp, ip)
    if not ok:
        op = auth.operator()
        return render(request, "login.html", error=message,
                      totp_required=bool(op and op["totp_enrolled"]))
    token = auth.start_session(ip, request.headers.get("user-agent", ""))
    response = RedirectResponse("/", status_code=303)
    response.set_cookie(auth.COOKIE_NAME, token, httponly=True,
                        secure=SECURE_COOKIES, samesite="strict",
                        max_age=auth.SESSION_HOURS * 3600, path="/")
    return response


@app.post("/logout")
def logout(request: Request):
    auth.end_session(request.cookies.get(auth.COOKIE_NAME), client_ip(request))
    response = RedirectResponse("/login", status_code=303)
    response.delete_cookie(auth.COOKIE_NAME, path="/")
    return response


@app.post("/stepup")
def stepup(request: Request, password: str = Form(...),
           back: str = Form("/"), session: dict = Depends(current_session)):
    """Re-enter the password to authorise destructive actions for a few
    minutes. Holding a session is not the same as being at the keyboard."""
    op = auth.operator()
    from .security import verify_password
    if not op or not verify_password(password, op["password_hash"]):
        audit.record("stepup.failed", outcome="denied", ip=client_ip(request))
        return render(request, "stepup.html", back=back,
                      error="That password is not right.")
    auth.grant_stepup(request.cookies.get(auth.COOKIE_NAME))
    audit.record("stepup.ok", ip=client_ip(request))
    return RedirectResponse(back, status_code=303)


def require_stepup(request: Request, session: dict, back: str):
    if not auth.has_stepup(session):
        return render(request, "stepup.html", back=back, error=None)
    return None


# ── Dashboard ────────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
def dashboard(request: Request, session: dict = Depends(current_session)):
    series = db.messages_per_day(30)
    return render(request, "dashboard.html",
                  totals=db.dashboard_totals(),
                  series=series,
                  spark=charts.sparkline([r["n"] for r in series]),
                  signups=db.recent_signups())


# ── Groups ───────────────────────────────────────────────────────────────────

@app.get("/groups", response_class=HTMLResponse)
def groups(request: Request, session: dict = Depends(current_session)):
    """Read-only for now. Membership editing and deletion are Phase 4; this
    exists so retiring the old page does not remove a view the operator
    already had."""
    return render(request, "groups.html", topics=db.list_topics())


# ── People ───────────────────────────────────────────────────────────────────

@app.get("/people", response_class=HTMLResponse)
def people(request: Request, q: str = "",
           session: dict = Depends(current_session)):
    return render(request, "people.html", people=db.list_people(q or None), q=q)


@app.get("/people/{user_id}", response_class=HTMLResponse)
def person(request: Request, user_id: int,
           session: dict = Depends(current_session)):
    row = db.get_person(user_id)
    if not row:
        raise HTTPException(404, "No such member")
    return render(request, "person.html", person=row,
                  extras=db.person_extras(user_id),
                  stepup=auth.has_stepup(session))


@app.post("/people/{user_id}/password")
def reset_password(request: Request, user_id: int,
                   new_password: str = Form(...),
                   session: dict = Depends(current_session)):
    back = f"/people/{user_id}"
    if (gate := require_stepup(request, session, back)) is not None:
        return gate
    login = db.uid_encoded(user_id)
    row = db.get_person(user_id)
    if not login or not row:
        raise HTTPException(404, "No such member")
    try:
        with tinode.root_session() as root:
            root.set_password(root.resolve_uid(login), login, new_password)
    except Exception as err:  # noqa: BLE001 - surfaced to the operator
        audit.record("person.password_reset", target=login, outcome="error",
                     detail={"error": str(err)[:300]}, ip=client_ip(request))
        raise HTTPException(500, f"Could not reset the password: {err}")
    audit.record("person.password_reset", target=login, ip=client_ip(request))
    return RedirectResponse(back, status_code=303)


@app.post("/people/{user_id}/state")
def set_state(request: Request, user_id: int, state: str = Form(...),
              session: dict = Depends(current_session)):
    back = f"/people/{user_id}"
    if (gate := require_stepup(request, session, back)) is not None:
        return gate
    before = db.get_person(user_id)
    login = db.uid_encoded(user_id)
    if not before or not login:
        raise HTTPException(404, "No such member")
    try:
        with tinode.root_session() as root:
            root.set_state(root.resolve_uid(login), state)
    except Exception as err:  # noqa: BLE001
        audit.record("person.state", target=str(user_id), outcome="error",
                     detail={"error": str(err)[:300]}, ip=client_ip(request))
        raise HTTPException(500, f"Could not change the account state: {err}")
    audit.record("person.state", target=str(user_id),
                 detail={"before": before["state"], "after": state},
                 ip=client_ip(request))
    return RedirectResponse(back, status_code=303)


# ── Audit ────────────────────────────────────────────────────────────────────

@app.get("/audit", response_class=HTMLResponse)
def audit_log(request: Request, session: dict = Depends(current_session)):
    return render(request, "audit.html", entries=audit.recent(200))


@app.get("/healthz")
def healthz():
    return {"ok": True}
